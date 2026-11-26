extends RefCounted
# Two-player match over WebSocket matchmaking / private room relay, with automatic AI fallback
# when no human opponent is found or the matchmaker server is unavailable.
#
# Deterministic lockstep (human vs human): both clients run the same Battle from the same seed and
# exchange only player commands. A command made at tick t is scheduled for tick t+DELAY, sent via
# the WebSocket relay, and executed on both clients at that tick.
const B = preload("res://balance.gd")
const DeckStore = preload("res://deck_store.gd")
const Battle = preload("res://battle.gd")

const DEFAULT_SERVER_URL := "ws://127.0.0.1:24680"
const CONFIG_PATH := "user://net_config.json"
const PORT := 24680
const DELAY := 6 # ticks of input delay (0.1 s at 60 ticks per second)
const CHECK_EVERY := 60
const DT := 1.0/60.0
const SEARCH_AI_FALLBACK_SEC := 12.0
const CONNECT_FAIL_MIN_SEARCH_SEC := 2.5

var ws: WebSocketPeer
var server_url := DEFAULT_SERVER_URL
var state := "idle" # idle, connecting, searching, room_waiting, joining, playing, lost, error
var mode := "quick" # quick, create_room, join_room
var message := ""
var room_code := ""
var target_code := ""
var online_count := 0
var queued_count := 0
var local_team := 0
var my_deck: Array = []
var my_lord := ""
var match_difficulty := 1
var allow_ai_fallback := true
var ai_fallback_sec := SEARCH_AI_FALLBACK_SEC
var search_elapsed := 0.0
var server_unreachable := false
var sent_action := false
var is_ai_match := false
var ai_opponent_name := ""
var peer_name := ""
var start_info: Dictionary = {} # seed, decks, lords
var tick := 0
var frames := [{},{}] # frames[team][tick] = Array of commands
var pending: Array = [] # local commands waiting for the next frame we send
var checks := [{},{}] # checks[team][tick] = state summary
var desync := false
var stalled_for := 0.0 # seconds the peer's frame has been missing

static func version() -> String:
	# Both clients must run identical rules, or lockstep simulations will diverge.
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for fname: String in ["arcane_mechanics.gd","attack_windup.gd","balance.gd","battle.gd","boss_traits.gd","card_upgrades.gd","closed_lanes.gd","conveyor.gd","core_cards.gd","dark_sorcery.gd","day_cycle.gd","expansion_cards.gd","expansion_more.gd","faction_cards.gd","farm_opening.gd","frontier_cards.gd","giant_unit.gd","glutton_nest.gd","gold_monster.gd","grid_rules.gd","hero_slash.gd","large_body.gd","layout.gd","lord.gd","lord_expansion.gd","map_mech.gd","monster_cards.gd","relic_triggers.gd","seal_altar.gd","season.gd","spell_lead.gd","ward_rules.gd"]:
		ctx.update(fname.to_utf8_buffer())
		ctx.update(FileAccess.get_file_as_bytes("res://"+fname))
	return ctx.finish().hex_encode()

static func default_url() -> String:
	var env_url := OS.get_environment("MATCHMAKER_URL").strip_edges()
	if not env_url.is_empty(): return env_url
	if FileAccess.file_exists(CONFIG_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			var saved := String(parsed.get("server_url","")).strip_edges()
			if not saved.is_empty(): return saved
	return DEFAULT_SERVER_URL

static func save_server_url(url: String) -> String:
	var cleaned := url.strip_edges()
	if cleaned.is_empty(): cleaned = DEFAULT_SERVER_URL
	var file := FileAccess.open(CONFIG_PATH,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"server_url":cleaned}))
	return cleaned

func _prepare(deck: Array, lord: String, url: String) -> String:
	close()
	my_deck = deck.duplicate()
	my_lord = lord
	var resolved := url.strip_edges() if not url.strip_edges().is_empty() else default_url()
	server_url = resolved
	return resolved

func _connect_ws(url: String) -> bool:
	ws = WebSocketPeer.new()
	var err := ws.connect_to_url(url)
	if err != OK:
		ws = null
		return false
	return true

func search_match(deck: Array, lord: String, difficulty: int = 1, url: String = "", ai_fallback: bool = true, fallback_sec: float = SEARCH_AI_FALLBACK_SEC) -> bool:
	var resolved := _prepare(deck,lord,url)
	mode = "quick"
	match_difficulty = clampi(difficulty,0,2)
	allow_ai_fallback = ai_fallback
	ai_fallback_sec = maxf(0.05,fallback_sec)
	state = "connecting"
	message = "正在搜尋對手…"
	if not _connect_ws(resolved):
		server_unreachable = true
		if not allow_ai_fallback:
			_fail("無法連線到配對伺服器：%s" % resolved)
			return false
		state = "searching"
	return true

func host_room(deck: Array, lord: String, url: String = "") -> bool:
	var resolved := _prepare(deck,lord,url)
	mode = "create_room"
	allow_ai_fallback = false
	state = "connecting"
	message = "正在連線並建立好友房間…"
	if not _connect_ws(resolved):
		_fail("無法連線到配對伺服器：%s" % resolved)
		return false
	return true

func join_room(code: String, deck: Array, lord: String, url: String = "") -> bool:
	var cleaned := code.strip_edges().to_upper()
	if cleaned.is_empty():
		_fail("請輸入好友提供的房間代碼")
		return false
	var resolved := _prepare(deck,lord,url)
	mode = "join_room"
	target_code = cleaned
	allow_ai_fallback = false
	state = "connecting"
	message = "正在加入房間 %s…" % cleaned
	if not _connect_ws(resolved):
		_fail("無法連線到配對伺服器：%s" % resolved)
		return false
	return true

func close() -> void:
	if ws != null:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and state in ["searching","room_waiting"]:
			_send({"t":"cancel"})
		ws.close()
	ws = null
	state = "idle"
	mode = "quick"
	message = ""
	room_code = ""
	target_code = ""
	online_count = 0
	queued_count = 0
	local_team = 0
	search_elapsed = 0.0
	server_unreachable = false
	sent_action = false
	is_ai_match = false
	ai_opponent_name = ""
	peer_name = ""
	start_info = {}
	tick = 0
	frames = [{},{}]
	pending.clear()
	checks = [{},{}]
	desync = false
	stalled_for = 0.0

func _fail(text: String) -> void:
	state = "error"
	message = text
	if ws != null: ws.close()
	ws = null

func _send(msg: Dictionary) -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN: return
	ws.send_text(JSON.stringify(msg))

func _fallback_to_ai() -> void:
	if ws != null:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_send({"t":"cancel"})
		ws.close()
		ws = null
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var lords: Array = B.LORDS.keys().filter(func(k: String) -> bool: return k != my_lord)
	if lords.is_empty(): lords = B.LORDS.keys()
	var foe_lord := String(lords[rng.randi_range(0,lords.size()-1)])
	var foe_deck: Array = DeckStore.balanced_random_deck(rng,foe_lord)
	local_team = 0
	is_ai_match = true
	ai_opponent_name = "%s（AI）" % B.lord_name(foe_lord)
	start_info = {
		"seed":rng.randi_range(1,2000000000),
		"decks":[my_deck,foe_deck],
		"lords":[my_lord,foe_lord],
	}
	state = "playing"
	message = "已為你配對對手：%s" % ai_opponent_name

# Called every physics frame. Reads WebSocket / matchmaking timers; returns true once a match starts.
func poll(dt: float = DT) -> bool:
	if state in ["idle","lost","error"]: return false
	if state == "playing":
		if ws != null: _pump_ws()
		return tick == 0 and not start_info.is_empty() and not start_info.get("started",false)

	if mode == "quick":
		search_elapsed += dt
		var wait_offline_sec := minf(ai_fallback_sec,CONNECT_FAIL_MIN_SEARCH_SEC)
		if allow_ai_fallback and (search_elapsed >= ai_fallback_sec or (server_unreachable and search_elapsed >= wait_offline_sec)):
			_fallback_to_ai()
			return true

	if ws != null:
		_pump_ws()

	if state == "playing":
		return tick == 0 and not start_info.is_empty() and not start_info.get("started",false)
	if mode == "quick" and state in ["connecting","searching"]:
		message = "正在搜尋對手… %d 秒" % int(search_elapsed)
	return false

func _pump_ws() -> void:
	if ws == null: return
	ws.poll()
	if ws == null: return
	var ready := ws.get_ready_state()
	if ready == WebSocketPeer.STATE_OPEN:
		if not sent_action:
			sent_action = true
			match mode:
				"quick":
					state = "searching"
					_send({"t":"queue","version":version(),"lord":my_lord,"deck":my_deck,"name":B.lord_name(my_lord)})
				"create_room":
					state = "room_waiting"
					_send({"t":"create_room","version":version(),"lord":my_lord,"deck":my_deck,"name":B.lord_name(my_lord)})
				"join_room":
					state = "joining"
					_send({"t":"join_room","code":target_code,"version":version(),"lord":my_lord,"deck":my_deck,"name":B.lord_name(my_lord)})
		while ws != null and ws.get_available_packet_count() > 0:
			var raw := ws.get_packet().get_string_from_utf8()
			var parsed = JSON.parse_string(raw)
			if parsed is Dictionary: _receive(parsed)
	elif ready == WebSocketPeer.STATE_CLOSED:
		ws = null
		if state == "playing":
			if not is_ai_match:
				state = "lost"
				message = "對手已離線"
		elif mode == "quick" and allow_ai_fallback:
			server_unreachable = true
			state = "searching"
		else:
			_fail("無法連線到配對伺服器（%s）" % server_url)

func _receive(msg: Dictionary) -> void:
	match str(msg.get("t","")):
		"stats":
			online_count = int(msg.get("online",online_count))
			queued_count = int(msg.get("queued",queued_count))
		"queued":
			state = "searching"
			online_count = int(msg.get("online",online_count))
			queued_count = int(msg.get("queued",queued_count))
		"room_created":
			state = "room_waiting"
			room_code = str(msg.get("code",""))
			online_count = int(msg.get("online",online_count))
			message = "房間已建立，代碼：%s（等待好友加入…）" % room_code
		"error":
			_fail(str(msg.get("msg","配對失敗")))
		"peer_left":
			if state == "playing" and not is_ai_match:
				state = "lost"
				message = "對手已離線"
		"matched":
			local_team = int(msg.get("team",0))
			var other := 1-local_team
			is_ai_match = false
			var raw_names: Array = Array(msg.get("names",[]))
			peer_name = str(raw_names[other]) if raw_names.size() > other else ""
			start_info = {
				"seed":int(msg.seed),
				"decks":[Array(msg.decks[0]),Array(msg.decks[1])],
				"lords":[str(msg.lords[0]),str(msg.lords[1])],
			}
			_begin()
		"f":
			frames[1-local_team][int(msg.k)] = msg.c
		"h":
			checks[1-local_team][int(msg.k)] = str(msg.v)
			_compare(int(msg.k))

func _begin() -> void:
	state = "playing"
	message = ""
	tick = 0
	frames = [{},{}]
	for t: int in range(DELAY):
		frames[0][t] = []
		frames[1][t] = []

func make_battle():
	var m = Battle.new(int(start_info.seed),Array(start_info.decks[0]).duplicate(),Array(start_info.decks[1]).duplicate(),start_info.lords[0],start_info.lords[1])
	m.ai_enabled = [false,is_ai_match]
	m.difficulty = match_difficulty if is_ai_match else 1
	start_info.started = true
	return m

# Local player's command, run on both clients DELAY ticks from now.
func queue(cmd: Array) -> void:
	pending.append(cmd)

# Advances the shared battle by as many ticks as the peer's frames allow (at most 3 per call, to
# catch up after a hiccup). on_tick is called after each step (events, effects).
func advance(model, dt: float, on_tick: Callable) -> void:
	if state != "playing" or is_ai_match: return
	var other := 1-local_team
	var steps := 0
	while steps < 3 and frames[other].has(tick) and not model.ended:
		if steps >= 1 and not frames[other].has(tick+DELAY): break # extra steps only while the peer is ahead of us
		# Our frame for tick+DELAY goes out first, then this tick runs with both sides' commands.
		frames[local_team][tick+DELAY] = pending.duplicate(true)
		_send({"t":"f","k":tick+DELAY,"c":pending})
		pending.clear()
		for team: int in [0,1]:
			for cmd in frames[team].get(tick,[]): _apply(model,team,cmd)
		frames[0].erase(tick)
		frames[1].erase(tick)
		model.step(DT)
		tick += 1
		if tick % CHECK_EVERY == 0:
			var v := summary(model)
			checks[local_team][tick] = v
			_send({"t":"h","k":tick,"v":v})
			_compare(tick)
		on_tick.call()
		steps += 1
	stalled_for = 0.0 if steps > 0 else stalled_for+dt

func _apply(model, team: int, cmd: Array) -> void:
	if cmd.is_empty(): return
	match str(cmd[0]):
		"p": model.play(team,int(cmd[1]),Vector2(float(cmd[2]),float(cmd[3])))
		"s": model.cast_skill(team)

func _compare(k: int) -> void:
	if checks[0].has(k) and checks[1].has(k):
		if checks[0][k] != checks[1][k]: desync = true
		checks[0].erase(k)
		checks[1].erase(k)

# A compact fingerprint of the battle; both clients must agree on it every CHECK_EVERY ticks.
static func summary(model) -> String:
	var hp := 0.0
	var xs := 0.0
	for u: Dictionary in model.units:
		hp += u.hp
		xs += u.pos.x
	for b: Dictionary in model.buildings: hp += b.hp
	return "%d|%d|%d|%.3f|%.3f|%.3f|%.3f" % [model.units.size(),model.buildings.size(),int(model.ended),hp,xs,model.ink[0],model.ink[1]]
