extends SceneTree
# 一日戰役 (battle.gd day_phase / night_rate / crumble_gates / dawn_verdict), the ceremonies and
# the settings that came with it (2026-11-12).
# Standalone: godot_console --headless --path . -s tools/test_day_cycle.gd

const Battle = preload("res://battle.gd")
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Rogue = preload("res://roguelike.gd")
const Ceremony = preload("res://battle_ceremony.gd")
const DayCycle = preload("res://day_cycle.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run_standalone")

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + msg)

func run_standalone() -> void:
	run(self)
	if failures > 0:
		printerr("TEST FAIL: %d checks, %d failures" % [checks, failures])
		quit(1)
	else:
		print("DAY CYCLE PASS: %d checks, 0 failures" % checks)
		quit(0)

# A battle with nobody playing: no AI, no lords walking about, so only the clock acts.
static func quiet(seed_value: int = 1) -> Battle:
	var m := Battle.new(seed_value,[],[],"lion","lion")
	m.ai_enabled = [false,false]
	return m

static func run_to(m: Battle, seconds: float) -> void:
	while m.elapsed < seconds-0.000001 and not m.ended: m.step(1.0/60.0)

static func run(t) -> void:
	# ---- the phases and what they do to the gold --------------------------------------------
	var m := quiet()
	t.check(m.day_phase() == 0 and is_equal_approx(m.multiplier(),1.0),"daytime (0-3m): phase 0, gold x1")
	m.elapsed = B.RAMP_1
	t.check(m.day_phase() == 1 and is_equal_approx(m.multiplier(),1.5),"noon (3-4:30m): phase 1, gold x1.5")
	m.elapsed = B.RAMP_2
	t.check(m.day_phase() == 2 and is_equal_approx(m.multiplier(),2.0),"dusk (4:30-6m): phase 2, gold x2")
	m.elapsed = B.NIGHT_START
	t.check(m.day_phase() == 3 and is_equal_approx(m.multiplier(),B.NIGHT_GOLD),"night (6-9m): phase 3, gold x NIGHT_GOLD")
	t.check(B.RAMP_1 == 180.0 and B.RAMP_2 == 270.0 and B.NIGHT_START == 360.0 and B.DAWN == 540.0,"day 3m -> noon 1.5m -> dusk 1.5m -> night 3m -> dawn 9m")
	# ---- gates stand all day and crumble at night, twice as fast each minute ----------------
	m = quiet()
	run_to(m,B.NIGHT_START-1.0)
	t.check(m.gates[0].all(func(hp: float) -> bool: return hp == B.GATE_HP) and m.gates[1].all(func(hp: float) -> bool: return hp == B.GATE_HP),"no gate loses anything before nightfall")
	t.check(is_zero_approx(m.night_rate()),"the crumbling rate is 0 by day")
	m.events.clear()
	run_to(m,B.NIGHT_START+1.0)
	t.check(m.events.any(func(e: Dictionary) -> bool: return e.kind == "nightfall" and e.get("first",false)),"nightfall is announced once, as the first toll")
	t.check(is_equal_approx(m.night_rate(),B.NIGHT_DECAY),"first minute of night: NIGHT_DECAY per second")
	run_to(m,B.NIGHT_START+30.0)
	var lost: float = B.GATE_HP-m.gates[0][2]
	t.check(absf(lost-B.NIGHT_DECAY*30.0) < B.NIGHT_DECAY*0.1,"30 s into the night a gate has lost 30 x NIGHT_DECAY (%s)" % lost)
	t.check(is_equal_approx(m.gates[0][0],m.gates[1][4]),"both sides' gates crumble alike")
	m.events.clear()
	run_to(m,B.NIGHT_START+B.NIGHT_STEP+1.0)
	t.check(is_equal_approx(m.night_rate(),B.NIGHT_DECAY*2.0),"second minute: the rate has doubled")
	t.check(m.events.filter(func(e: Dictionary) -> bool: return e.kind == "nightfall").size() == 1 and not m.events.any(func(e: Dictionary) -> bool: return e.kind == "nightfall" and e.get("first",false)),"each doubling tolls once more, not as the first")
	# Untouched gates all fall together, well before dawn.
	run_to(m,B.DAWN-1.0)
	t.check(not m.ended,"gates crumbling to nothing does not end the match by itself")
	t.check(m.gates[0].all(func(hp: float) -> bool: return hp <= 0) and m.gates[1].all(func(hp: float) -> bool: return hp <= 0),"every untouched gate is gone before dawn")
	t.check(m.events.filter(func(e: Dictionary) -> bool: return e.kind == "breach" and e.get("crumbled",false)).size() == 10,"each crumbled gate is reported as a breach")
	t.check(m.first_breach > B.NIGHT_START and m.first_breach < B.DAWN,"a crumbled gate counts as the first breach")
	# A gate that crumbles releases its land like a stormed one.
	m = quiet(9)
	m.buildings.clear()
	m.refresh_territory()
	t.check(m.land(0) == L.GRID_ROWS and m.land(1) == L.GRID_ROWS,"with no buildings each side holds only the column in front of its gates")
	m.elapsed = B.NIGHT_START+1.0
	for side: int in range(2):
		for lane: int in range(5): m.gates[side][lane] = 1.0
	for i: int in range(30): m.step(1.0/60.0)
	t.check(m.land(0) == 0 and m.land(1) == 0,"land held only by a crumbled gate is released")
	# A wounded gate falls first.
	m = quiet(2)
	m.gates[1][3] = 300.0
	run_to(m,B.NIGHT_START+25.0)
	t.check(m.gates[1][3] <= 0 and m.gates[1][2] > 0,"the weakest gate crumbles first")
	# ---- an open gate at night is still a way in ---------------------------------------------
	m = quiet(3)
	m.elapsed = B.NIGHT_START+100.0
	m.gates[1][2] = 0.0
	var raider: Dictionary = m.spawn_unit(0,2,"militia",Vector2(L.gate_stop(1)-5,L.cell_center(Vector2i(0,2)).y))
	raider.climb = B.RUBBLE_TIME
	m.lord_active = [false,false]
	m.lords[1].hp = 0 # nobody home (a lord standing in the gateway would be fought first)
	for i: int in range(240): m.step(1.0/60.0)
	t.check(m.ended and m.winner == 0,"a soldier through a fallen gate still wins the match at night")
	# ---- dawn: more land wins, level is a draw -----------------------------------------------
	m = quiet(4)
	m.add_building(0,Vector2i(3,2),"barricade")
	m.elapsed = B.DAWN-0.5
	run_to(m,B.DAWN+0.5)
	t.check(m.ended and m.winner == 0 and m.land(0) > m.land(1),"at dawn the side with more land wins (%d : %d)" % [m.land(0),m.land(1)])
	t.check(m.events.any(func(e: Dictionary) -> bool: return e.kind == "dawn"),"dawn is announced")
	t.check(Ceremony.dawn(m),"the closing page knows the match ended at dawn")
	m = quiet(5)
	m.elapsed = B.DAWN-0.5
	run_to(m,B.DAWN+0.5)
	t.check(m.ended and m.winner == -1 and m.land(0) == m.land(1),"level land at dawn is a draw (winner -1)")
	m = quiet(6)
	m.add_building(1,Vector2i(5,1),"barricade")
	m.elapsed = B.DAWN-0.5
	run_to(m,B.DAWN+0.5)
	t.check(m.ended and m.winner == 1,"blue wins at dawn with more land")
	# Land counts only the lanes in play.
	m = quiet(7)
	m.active_lanes.assign([1,2,3])
	t.check(m.land(0) == m.land(1) and m.land(0) <= 3*L.GRID_COLUMNS,"land counts active lanes only")
	# ---- modes without a night ---------------------------------------------------------------
	m = quiet(8)
	m.night_decay = false
	m.elapsed = B.DAWN+60.0
	for i: int in range(120): m.step(1.0/60.0)
	t.check(not m.ended and m.day_phase() == 2 and is_equal_approx(m.multiplier(),2.0),"night_decay off: dusk never ends, gold stays x2, no dawn verdict")
	t.check(m.gates[0].all(func(hp: float) -> bool: return hp == B.GATE_HP),"night_decay off: gates never crumble")
	var r := Rogue.new()
	r.save_path = "user://day-cycle-test-rogue.json"
	r.begin("rune","mage",7)
	t.check(not r.make_battle().night_decay,"roguelike battles have no night (gate wounds carry over; their own time limit ends them)")
	for path: String in [r.save_path,r.save_path+".bak",r.save_path+".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	# ---- the game around it ------------------------------------------------------------------
	var g = load("res://main.tscn").instantiate()
	t.root.add_child(g)
	g.set_process(false)
	g.set_physics_process(false)
	g.sound_enabled = false
	g.sound.enabled = false
	g.deck_path = "user://day-cycle-test-deck.json"
	g.settings_path = "user://day-cycle-test-settings.json"
	g.adventure.progress_path = "user://day-cycle-test-adventure.json"
	g.adventure.start(g,0)
	t.check(not g.model.night_decay,"the first lesson has no night")
	g.adventure.start(g,1)
	t.check(g.model.night_decay,"later adventure stages have a night")
	g.adventure.index = -1
	g.spectating = false
	g.player_deck = B.DEFAULT_DECK.duplicate()
	g.player_lord = B.DEFAULT_LORD
	g.start_battle()
	t.check(g.model.night_decay and g.intro_left > 0,"a free battle has a night and opens with the banner")
	t.check(g.in_battle() and DayCycle.marks(g) == [0.0,B.RAMP_1,B.RAMP_2,B.NIGHT_START,B.DAWN],"the day track shows day, noon, dusk and night up to dawn")
	g.model.paused = true
	t.check(g.overlay_buttons().map(func(b: Array) -> String: return b[1]) == ["繼續","重新開始","設定","回到標題"],"pause banner: continue, restart, settings, title")
	t.check(g.overlay_buttons().all(func(b: Array) -> bool: return L.OVERLAY_RECT.encloses(b[0])),"the pause buttons fit inside the banner")
	g.overlay_buttons()[2][2].call()
	t.check(g.screen == "settings" and g.in_battle() and g.model.paused,"settings opened from the pause banner keep the battle (and its music) in place")
	preload("res://settings_screen.gd").back(g)
	t.check(g.screen == "battle" and g.model.paused and g.settings_return == "title","back from settings returns to the paused battle")
	g.model.paused = false
	# Winner, loser and draw each get their own closing page.
	g.model.finish(0)
	g._process(0.1)
	t.check(Ceremony.mood(g) == 1 and Ceremony.title(g) == "勝利" and g.result_seen == g.model,"red walks in: victory page")
	t.check(g.overlay_buttons().all(func(b: Array) -> bool: return g.RESULT_RECT.encloses(b[0])),"the closing page's buttons fit inside it")
	t.check(Ceremony.rows(g).size() == 5 and Ceremony.rows(g).all(func(row: Array) -> bool: return row.size() == 3),"closing page: five rows, a figure for each side")
	g.start_battle()
	g.model.finish(1)
	t.check(Ceremony.mood(g) == -1 and Ceremony.title(g) == "敗北","blue walks in: defeat page")
	g.start_battle()
	g.model.elapsed = B.DAWN
	g.model.finish(-1)
	t.check(Ceremony.mood(g) == 0 and Ceremony.title(g) == "平手" and Ceremony.dawn(g.model),"level at dawn: draw page")
	t.check(Ceremony.champion(g.model,0) == "","nobody fought: no champion card")
	g.model.stats[0].damage = {"militia":40.0,"hunter":90.0,"lord":500.0}
	t.check(Ceremony.champion(g.model,0) == "hunter","the champion is the card with the most damage (the lord is not a card)")
	# Settings survive a save and a load, and old files still read.
	g.music_volume = 0.35
	g.sfx_volume = 0.6
	g.fullscreen = false
	g.save_settings()
	g.music_volume = 1.0
	g.sfx_volume = 1.0
	g.load_settings()
	t.check(is_equal_approx(g.music_volume,0.35) and is_equal_approx(g.sfx_volume,0.6),"volumes are saved and loaded")
	var old := FileAccess.open(g.settings_path,FileAccess.WRITE)
	old.store_string(JSON.stringify({"effects":true,"shake":false,"sound":false}))
	old.close()
	g.load_settings()
	t.check(is_zero_approx(g.sfx_volume) and is_equal_approx(g.music_volume,0.7) and not g.shake_enabled,"a settings file from before the sliders: sound off means sfx volume 0")
	g.apply_audio_settings()
	t.check(not g.sound_enabled and AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),"sfx volume 0 mutes the SFX bus")
	t.check(AudioServer.get_bus_index("Music") >= 0 and g.music.players.has("menu") and g.music.players.has("battle") and g.music.players.has("night"),"the music player has its three pieces")
	g.music.want("battle",1)
	t.check(g.music.wanted == "battle" and g.music.layer_target == [1.0,1.0,0.0],"noon: the lute and the drums")
	g.music.want("nothing-like-this")
	t.check(g.music.wanted == "","an unknown piece means silence")
	for file: String in ["menu","battle_lute","battle_drums","battle_tune","night","victory","defeat"]:
		t.check(ResourceLoader.exists("res://assets/music/"+file+".ogg"),"music file "+file)
	for path: String in [g.deck_path,g.settings_path,g.adventure.progress_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	g.free()
