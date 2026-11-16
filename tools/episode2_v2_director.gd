extends SceneTree
## Episode 2: deterministic native AI match, event-driven editorial overlays.
const Battle = preload("res://battle.gd")
const B = preload("res://balance.gd")
const Deck = preload("res://deck_store.gd")
const RED := ["arcane_golem", "artificer", "arcane_archer", "chronomancer", "blink_blade", "phase_rider", "summon_trap", "teleport_trap"]
const BLUE := ["pouch_beast", "belly_eye", "fishbeak", "hooknose_flyer", "long_dragon", "eyewing_dragon", "bearded_imp", "thorn_dragon"]
const BASE := "res://recordings/episode02_rune_vs_beast_v2"
var model
var game
var verify := false
var ready := false
var tick := 0
var tail := 360
var seen := {}
var last_spot := -600
var journal: Array = []
var preview := false
var mage_cast := false
var film_frame := 0
var slow_frames := 0

func _initialize() -> void:
	verify = "--verify" in OS.get_cmdline_user_args()
	preview = "--preview" in OS.get_cmdline_user_args()
	assert(Deck.valid(RED, "rune"))
	assert(Deck.valid(BLUE, "beast"))
	model = Battle.new(23, RED.duplicate(), BLUE.duplicate(), "rune", "beast")
	model.difficulty = 1
	model.ai_enabled = [true, true]
	if verify:
		while not model.ended and tick < 60 * 650:
			advance()
		write_notes("_verified")
		quit(0 if model.ended else 1)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	call_deferred("prepare")

func prepare() -> void:
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.spectating = false
	game.me = 0
	game.mirror_view = false
	game.field_mirror = false
	game.model = model
	game.cinematic = preload("res://tools/episode2_cinematic.gd").new()
	game.enter_battle("")
	game.recorder.reset(false)
	game.cinematic.enabled = true
	game.music_volume = 0.55
	game.sfx_volume = 0.7
	ready = true

func advance() -> void:
	# Direct a legal save-for-skill decision; no resource or cooldown overrides.
	if tick >= 3900 and not mage_cast and not model.ended:
		model.ai_enabled[0] = false
		if model.skill_error(0).is_empty():
			mage_cast = model.cast_skill(0)
			model.ai_enabled[0] = true
	if not verify:
		game.attack_animation.observe(model)
	model.step(1.0 / 60.0)
	for e: Dictionary in model.events:
		var kind := String(e.kind)
		if kind in ["play", "skill", "breach", "invaded", "finish", "nightfall"]:
			var item := {"frame": tick, "seconds": float(tick) / 60.0, "film_seconds": float(film_frame) / 60.0, "event": kind, "team": e.get("team", -1), "card": e.get("card", ""), "lane": e.get("lane", -1)}
			journal.append(item)
		if verify:
			continue
		var team := int(e.get("team", 0))
		if kind == "play" and tick > 300:
			var card := String(e.get("card", ""))
			if not seen.has(card) and tick - last_spot > 420:
				seen[card] = true
				last_spot = tick
				slow_frames = 180
				var data: Dictionary = B.CARDS.get(card, {})
				game.cinematic.trigger_spotlight(game, e.get("pos", Vector2(800, 394)), team, card, String(data.get("role", "")), 1.15, 2.2, 3.2)
		elif kind == "skill":
			slow_frames = 300
			game.cinematic.trigger_subtitle("符文前線｜五路法陣迎擊獸群" if team == 0 else "獸群號角｜五路獸群奔向前線", team, 4.0)
		elif kind == "breach":
			slow_frames = 180
			game.cinematic.trigger_subtitle("第 %d 路城門突破！最後一道防線" % (int(e.lane) + 1), team, 3.5)
	if not verify:
		game.attack_animation.observe(model)
		game.consume_events()
		if tick == 30:
			game.cinematic.trigger_chapter("第二集｜符文與獸群", "符文領主 × 馴獸領主", 3.5)
		elif tick == 480:
			game.cinematic.trigger_subtitle("行軍三倍速｜卡牌、技能與破城恢復正常速度", 0, 4.0)
		elif tick == 2400:
			game.cinematic.trigger_chapter("第二幕｜戰線交錯", "看清兵線，再看領主的下一步", 2.5)
		elif tick == 5100:
			game.cinematic.trigger_chapter("第三幕｜法陣與號角", "攻勢與守勢，勝負仍未落定", 2.5)
		elif tick == 6300:
			game.cinematic.trigger_chapter("終幕｜破城之戰", "守住缺口，還是完成最後一擊", 2.5)
	else:
		model.events.clear()
	tick += 1

func _physics_process(_dt: float) -> bool:
	if not ready or model.ended:
		return false
	var steps := 1 if tick < 600 or slow_frames > 0 else 3
	for i: int in range(steps):
		if model.ended:
			break
		advance()
		if slow_frames > 0:
			break
	slow_frames = maxi(0, slow_frames - 1)
	film_frame += 1
	return false

func _process(_dt: float) -> bool:
	if not ready:
		return false
	if preview and tick >= 1200:
		return true
	if model.ended:
		tail -= 1
		if tail == 359:
			write_notes("")
		if tail <= 0:
			return true
	return tick > 60 * 650

func write_notes(suffix: String) -> void:
	var winner := "符文領主" if model.winner == 0 else ("馴獸領主" if model.winner == 1 else "平手")
	var lines: PackedStringArray = ["# 第二集｜符文與獸群", "", "符文領主 × 馴獸領主。延續第一集的手抄本戰場、章節與卡牌特寫。", "", "- Seed：23；普通 AI 對局；紅方在 65 秒後暫停自動出牌，存足金幣合法施放符文前線後恢復 AI。未修改金幣、冷卻、傷害或勝負。", "- 本集為獨立新對局，不使用第一集重剪。", "- 勝方：%s；實際影格：%d；原始對局時間：%.3f 秒。" % [winner, tick, float(tick) / 60.0], "- 紅方牌組：%s" % str(RED), "- 藍方牌組：%s" % str(BLUE), "", "## 實際事件時間表（原始對局時間，非加速後成片時間）"]
	for item: Dictionary in journal:
		var sec := float(item.seconds)
		var card := String(item.card)
		var label := String(B.CARDS.get(card, {}).get("name", card))
		lines.append("- [%02d:%05.2f] %s · %s · %s" % [int(sec) / 60, fmod(sec, 60.0), String(item.event), "紅方" if item.team == 0 else "藍方", label])
	var file := FileAccess.open(BASE + suffix + ".md", FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	var data := FileAccess.open(BASE + suffix + ".json", FileAccess.WRITE)
	data.store_string(JSON.stringify({"seed": 23, "winner": model.winner, "frames": tick, "events": journal}, "\t"))
	print("EPISODE2 winner=%s frames=%d seconds=%.3f events=%d" % [winner, tick, float(tick)/60.0, journal.size()])

