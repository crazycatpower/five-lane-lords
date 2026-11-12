extends RefCounted
# Two-player match over a direct IP connection (producer 2026-11-06).
#
# Deterministic lockstep: both machines run the same Battle from the same seed and exchange only the
# players' commands. A command made at tick t is scheduled for tick t+DELAY, sent to the peer at once,
# and run on both machines at that tick, so the two simulations never diverge. Every tick each side
# sends one frame (its commands for tick+DELAY, often empty); a side only advances a tick once it
# holds the peer's frame for it. Every CHECK_EVERY ticks both sides compare a summary of the state.
#
# The host is red (team 0) and picks the seed; the guest is blue (team 1).
const B = preload("res://balance.gd")
const Battle = preload("res://battle.gd")
const PORT := 24680
const DELAY := 6 # ticks of input delay (0.1 s at 60 ticks per second)
const CHECK_EVERY := 60
const DT := 1.0/60.0

var peer: ENetMultiplayerPeer
var state := "idle" # idle, hosting, joining, waiting, playing, lost, error
var message := ""
var local_team := 0
var my_deck: Array = []
var my_lord := ""
var peer_hello: Dictionary = {}
var start_info: Dictionary = {} # seed, decks, lords
var tick := 0
var frames := [{},{}] # frames[team][tick] = Array of commands
var pending: Array = [] # local commands waiting for the next frame we send
var checks := [{},{}] # checks[team][tick] = state summary
var desync := false
var stalled_for := 0.0 # seconds the peer's frame has been missing

static func version() -> String:
	# Both machines must run the same rules, or the simulations drift apart.
	return FileAccess.get_md5("res://balance.gd")+FileAccess.get_md5("res://battle.gd")

func host(deck: Array, lord: String) -> bool:
	close()
	my_deck = deck.duplicate()
	my_lord = lord
	local_team = 0
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT,1)
	if err != OK:
		_fail("無法開房（連接埠 %d 可能被占用）" % PORT)
		return false
	_wire()
	state = "hosting"
	message = "等待對手加入…"
	return true

func join(ip: String, deck: Array, lord: String) -> bool:
	close()
	my_deck = deck.duplicate()
	my_lord = lord
	local_team = 1
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(),PORT)
	if err != OK:
		_fail("無法連線到 %s" % ip)
		return false
	_wire()
	state = "joining"
	message = "連線中…"
	return true

func _wire() -> void:
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.peer_connected.connect(func(_id: int): _send({"t":"hello","deck":my_deck,"lord":my_lord,"version":version()}))
	peer.peer_disconnected.connect(func(_id: int):
		if state in ["playing","waiting","hosting","joining"]:
			state = "lost"
			message = "對手已離線")

func close() -> void:
	if peer != null: peer.close()
	peer = null
	state = "idle"
	message = ""
	peer_hello = {}
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
	if peer != null: peer.close()
	peer = null

func _send(msg: Dictionary) -> void:
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return
	peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
	peer.put_packet(var_to_bytes(msg))

func local_ips() -> Array:
	return Array(IP.get_local_addresses()).filter(func(a: String) -> bool: return a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."))

# Called every physics frame. Reads the network; returns true once a match should start.
func poll() -> bool:
	if peer == null: return false
	if state in ["lost","error"]: return false
	peer.poll()
	if peer == null: return false
	if state in ["playing","waiting"] and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		state = "lost"
		message = "對手已離線"
		return false
	if state == "joining" and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_fail("連不上對方：請確認 IP、對方已開房，以及防火牆允許連接埠 %d" % PORT)
		return false
	while peer != null and peer.get_available_packet_count() > 0:
		var msg = bytes_to_var(peer.get_packet())
		if not msg is Dictionary: continue
		_receive(msg)
	return state == "playing" and tick == 0 and not start_info.is_empty() and not start_info.get("started",false)

func _receive(msg: Dictionary) -> void:
	var other := 1-local_team
	match msg.get("t",""):
		"hello":
			if msg.get("version","") != version():
				_fail("雙方遊戲版本不同，請兩邊更新到同一版")
				return
			peer_hello = msg
			if local_team == 0:
				var rng := RandomNumberGenerator.new()
				rng.randomize()
				start_info = {"seed":rng.randi_range(1,2000000000),"decks":[my_deck,msg.deck],"lords":[my_lord,msg.lord]}
				_send({"t":"start","seed":start_info.seed,"decks":start_info.decks,"lords":start_info.lords})
				_begin()
		"start":
			start_info = {"seed":msg.seed,"decks":msg.decks,"lords":msg.lords}
			_begin()
		"f":
			frames[other][int(msg.k)] = msg.c
		"h":
			checks[other][int(msg.k)] = msg.v
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
	m.ai_enabled = [false,false]
	m.difficulty = 1
	start_info.started = true
	return m

# Local player's command, run on both machines DELAY ticks from now.
func queue(cmd: Array) -> void:
	pending.append(cmd)

# Advances the shared battle by as many ticks as the peer's frames allow (at most 3 per call, to
# catch up after a hiccup). on_tick is called after each step (events, effects).
func advance(model, dt: float, on_tick: Callable) -> void:
	if state != "playing": return
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

# A compact fingerprint of the battle; both machines must agree on it every CHECK_EVERY ticks.
static func summary(model) -> String:
	var hp := 0.0
	var xs := 0.0
	for u: Dictionary in model.units:
		hp += u.hp
		xs += u.pos.x
	for b: Dictionary in model.buildings: hp += b.hp
	return "%d|%d|%d|%.3f|%.3f|%.3f|%.3f" % [model.units.size(),model.buildings.size(),int(model.ended),hp,xs,model.ink[0],model.ink[1]]
