extends Node2D
const B = preload("res://balance.gd")
const Frontier = preload("res://frontier_cards.gd")
const L = preload("res://layout.gd")
const DeckStore = preload("res://deck_store.gd")
const Battle = preload("res://battle.gd")
const Arcane = preload("res://arcane_mechanics.gd")
const ART = preload("res://manuscript_art.gd")
const AttackAnimation = preload("res://attack_animation.gd")
var attack_animation := AttackAnimation.new()
var library = preload("res://card_library.gd").new(self)
var review := preload("res://battle_review.gd").new()
var adventure := preload("res://adventure.gd").new()
var rogue := preload("res://roguelike.gd").new()
const PAPER = preload("res://assets/parchment-background.png")
const INK := Color("463529")
const RED := Color("9c3d30")
const BLUE := Color("355b78")
# Battlefield palette (art-direction sheet): our meadow, the sandy no-man's land, the enemy's frost.
const MEADOW := Color("7d9c54")
const SAND := Color("b08b52")
const FROST := Color("5a8fd0")
const PAPER_TINT := Color(0.94,0.90,0.83) # the whole page a little darker: less glare
const FIELD_TINT := Color(0.88,0.82,0.70)
var vignette: GradientTexture2D
var model: RefCounted
var font: Font
var textures: Dictionary = {}
var blue_art: Dictionary = {}
static var recolor_cache: Dictionary = {}
static var prepared_art: Dictionary = {}
static var palette_manifest: Dictionary = {}
# Bump only when team_material or palette conversion changes, not for UI/gameplay edits.
const PALETTE_REVISION := "team-material-v2"
const ROMAN := ["I","II","III","IV","V"]
var selected := -1
var notice := "1–4 選牌 · 點戰場放置 · 右鍵取消 · 空白鍵暫停"
# No text prompts in battle (producer 2026-11-03): events and refusals show as visual cues.
# notice still records the last message for the review log and tests.
var purse_alarm := 0.0 # missing coins flash and the heap shakes (not enough gold)
var purse_need := 0.0 # gold the refused card or skill wanted
var card_shake := {} # hand slot -> seconds left of a "still cooling" shake
var place_flash := 0.0 # valid cells pulse after a placement on a wrong cell
var skill_shake := 0.0
var screen := "title"
var player_deck: Array = []
var player_lord := "adventure"
var deck_path := "user://deck.json"
var adventure_deck_mode := false
# Two-player network match (net_match.gd). me = the local player's team; the guest (blue) sees the
# field mirrored so both players fight from the left. field_mirror is on only while the field draws.
const NetMatch = preload("res://net_match.gd")
var net = null
var me := 0
var mirror_view := false
var field_mirror := false
var net_ip := "192.168."
var watch_edit := -1 # >= 0: the deck screen is editing this spectate side (nothing is saved to disk)
var watch_stash := {} # the player's own deck and lord while a spectate side is being edited
var deck_tab := "all"
var deck_page := 0
var difficulty := 1
var spectating := false
var menu_notice := ""
# Spectate setup: each side's deck, lord and where the deck came from (WATCH_SOURCES index, -1 = edited by hand).
var watch_decks: Array = [[],[]]
var watch_lords: Array = ["lion","lion"]
var watch_source: Array = [0,0]
const WATCH_SOURCES := ["隨機","我的牌組"] # recommended presets removed from the menus (producer 2026-11-05)
var start_button: Button
var effects: Array[Dictionary] = []
const FactionVisuals = preload("res://faction_visuals.gd")
const DayCycle = preload("res://day_cycle.gd")
const Ceremony = preload("res://battle_ceremony.gd")
var levy_visuals := {} # last visible positions; scoped to this model
var levy_visual_model: RefCounted
var adventure_attack_frames: Array[Texture2D] = [
	preload("res://assets/manuscript-v1/adventure-lord-attack/frame-0.png"),
	preload("res://assets/manuscript-v1/adventure-lord-attack/frame-1.png"),
	preload("res://assets/manuscript-v1/adventure-lord-attack/frame-2.png"),
	preload("res://assets/manuscript-v1/adventure-lord-attack/frame-3.png"),
	preload("res://assets/manuscript-v1/adventure-lord-attack/frame-4.png"),
	preload("res://assets/manuscript-v1/adventure-lord-attack/frame-5.png"),
]
var adventure_attack_frames_blue: Array[Texture2D] = []

func get_adventure_frame(f: int, team: int = 0) -> Texture2D:
	var idx := clampi(f, 0, adventure_attack_frames.size() - 1)
	if team == 1:
		if adventure_attack_frames_blue.is_empty():
			for tex: Texture2D in adventure_attack_frames:
				adventure_attack_frames_blue.append(recolor_blue(tex, 384, "lord_adventure"))
		return adventure_attack_frames_blue[idx]
	return adventure_attack_frames[idx]
var seed_value := 1
var ui: Array[Control] = []
var fx_enabled := true
var shake_enabled := true
var shake_left := 0.0
var sound: Node
var sound_enabled := true
# Music and presentation state (2026-11-12). None of it is read by the rules.
const Music = preload("res://music_player.gd")
var music: Node
var music_volume := 0.7 # 0..1, settings
var sfx_volume := 0.8
var fullscreen := false
var clock := 0.0 # seconds of real time since launch: drives menu and overlay animation
var veil: ColorRect # parchment wash that fades out after every screen change
var veil_left := 0.0
var last_screen := ""
var result_age := 0.0 # seconds since the match ended (the result panel and its ceremony ease in)
var result_seen: RefCounted # the model whose ending has been announced
var intro_left := 0.0 # seconds left of the "who fights whom" banner at the start of a battle
const INTRO_TIME := 2.4
const VERSION := "0.2.0"
var hover_slot := -1
var dragging := false
var press_pos := Vector2.ZERO
var press_was_selected := false
var speed := 1
const RESULT_RECT := Rect2(310,110,980,506) # the closing page (battle_ceremony.gd PANEL)
const SPEEDS := [1,2,4,8]
const SPEED_RECTS := [Rect2(1360,736,46,32),Rect2(1412,736,46,32),Rect2(1464,736,46,32),Rect2(1516,736,46,32)]
const NEXT_RECT := Rect2(1102,748,96,128)
const SKILL_RECT := Rect2(1212,734,350,54)
const LORD_PLATE := Rect2(1206,726,360,152)

# Shared by the asset preflight and the game; prepared palettes load directly at launch.
static func prepare_art(progress: Callable = Callable()) -> void:
	if not prepared_art.is_empty(): return
	var textures: Dictionary = {}
	var blue_art: Dictionary = {}
	for pair: Array in [["militia","manuscript-v1/militia-red.png"],["farmer","farmer.png"],["farm","farmland.png"],["castle_red","manuscript-v1/castle-red.png"],["castle_blue","manuscript-v1/castle-red.png"]]:
		textures[pair[0]] = load("res://assets/"+pair[1])
	for kind: String in B.CARDS:
		var file := "res://assets/manuscript-v1/"+kind+".png"
		if ResourceLoader.exists(file): textures[kind] = load(file)
	for pair: Array in [["glutton_nest_closed","glutton_nest_closed"],["gate","lane-wall"],["gate_broken","lane-wall-broken"],["crest","crown"],["castle_wall","castle-wall"]]:
		textures[pair[0]] = load("res://assets/manuscript-v1/"+pair[1]+".png")
	for lord_kind: String in B.LORDS:
		textures["lord_"+lord_kind] = load("res://assets/manuscript-v1/lord-"+lord_kind+".png")
	var done := 0
	for kind: String in textures:
		if kind != "castle_blue": blue_art[kind] = recolor_blue(textures[kind],0 if kind in ["castle_red","castle_wall","gate","gate_broken"] else 384,kind)
		done += 1
		if progress.is_valid(): progress.call(done,textures.size())
	textures.castle_blue = textures.castle_red
	blue_art.castle_blue = blue_art.castle_red
	# A card without its own picture yet borrows the one named in its "art" field (placeholder).
	for kind: String in B.CARDS:
		var reference: Variant = B.CARDS[kind].get("art",[kind])
		var borrow: String = reference if reference is String else reference[0]
		if not textures.has(kind) and textures.has(borrow):
			textures[kind] = textures[borrow]
			if blue_art.has(borrow): blue_art[kind] = blue_art[borrow]
	# 小怪領主 (roguelike) use the picture of the card they are named after.
	for lord_kind: String in B.MINION_LORDS:
		var card: String = B.MINION_LORDS[lord_kind].card
		if textures.has(card): textures["lord_"+lord_kind] = textures[card]
		if blue_art.has(card): blue_art["lord_"+lord_kind] = blue_art[card]
	prepared_art = {"textures":textures,"blue":blue_art}

func _ready() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Noto Serif TC","PMingLiU","Microsoft JhengHei"])
	# Bundled Noto Serif TC subset (tools/build_font.py); the system font only covers glyphs it lacks.
	var bundled: FontFile = load("res://assets/fonts/ManuscriptSerif-subset.ttf")
	if bundled != null:
		bundled.fallbacks = [sf]
		font = bundled
	else: font = sf
	for problem: String in B.validate(): push_error("balance.gd: "+problem) # see docs/新增卡牌指南.md
	if prepared_art.is_empty(): prepare_art()
	textures = prepared_art.textures.duplicate()
	blue_art = prepared_art.blue.duplicate()
	# Darkened field edges pull the eye to the middle of the battle.
	var shade := Gradient.new()
	shade.set_color(0,Color(0.2,0.12,0.04,0.0))
	shade.set_color(1,Color(0.2,0.12,0.04,0.34))
	shade.add_point(0.62,Color(0.2,0.12,0.04,0.0))
	vignette = GradientTexture2D.new()
	vignette.gradient = shade
	vignette.fill = GradientTexture2D.FILL_RADIAL
	vignette.fill_from = Vector2(0.5,0.5)
	vignette.fill_to = Vector2(1.0,1.0)
	vignette.width = 256
	vignette.height = 256
	blue_art.castle_blue = blue_art.castle_red
	seed_value = int(Time.get_unix_time_from_system())
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.substr(7))
	load_settings()
	Music.ensure_buses()
	sound = preload("res://sound_bank.gd").new()
	add_child(sound)
	sound.enabled = sound_enabled
	music = Music.new()
	add_child(music)
	# The veil sits on its own layer so it also covers the buttons of the screen fading in.
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	veil = ColorRect.new()
	veil.color = Color(0.93,0.87,0.72,0.0)
	veil.size = L.VIEWPORT_SIZE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(veil)
	apply_audio_settings()
	fit_window()
	var saved: Dictionary = DeckStore.load_full(deck_path)
	player_deck = saved.cards
	player_lord = saved.lord
	model = Battle.new(seed_value,player_deck,[],player_lord)
	show_title()

func start_battle() -> void:
	adventure.index = -1
	rogue.in_battle = false
	if spectating:
		for team: int in range(2):
			if not DeckStore.valid(watch_decks[team],watch_lords[team]): watch_decks[team] = DeckStore.fit_to_lord(watch_decks[team],watch_lords[team])
			if not DeckStore.valid(watch_decks[team],watch_lords[team]): set_watch_source(team,0)
		model = Battle.new(seed_value,watch_decks[0].duplicate(),watch_decks[1].duplicate(),watch_lords[0],watch_lords[1])
	else:
		if not DeckStore.valid(player_deck,player_lord):
			show_deck()
			return
		DeckStore.save_deck(player_deck,deck_path,player_lord)
		model = Battle.new(seed_value,player_deck,B.PRESETS[difficulty],player_lord,B.PRESET_LORDS[difficulty])
	model.difficulty = difficulty
	model.ai_enabled = [spectating,true]
	enter_battle("觀戰中：AI 操控雙方。1–4 或 + / − 調整速度，空白鍵暫停。" if spectating else "拖曳卡牌到戰場，或按 1–4／F 選牌再點格子 · 右鍵取消 · 空白鍵暫停")

func restart() -> void:
	if net != null or rogue.in_battle: return # a roguelike battle cannot be replayed
	if adventure.index >= 0: adventure.start(self,adventure.index)
	else: start_battle()

func enter_battle(message: String) -> void:
	review.clear()
	attack_animation.clear()
	selected = -1
	dragging = false
	speed = 1
	position = Vector2.ZERO
	notice = message
	screen = "battle"
	effects.clear()
	result_age = 0.0
	result_seen = null
	intro_left = 0.0 if adventure.is_opening() else INTRO_TIME # the first lesson has its own opening scene
	if music != null: music.stop_sting()
	clear_ui()
	queue_redraw()

# Field mirror for the guest: x -> 1600 - x (the field is centred on the page).
func view_mirror() -> Transform2D:
	return Transform2D(Vector2(-1,0),Vector2(0,1),Vector2(L.VIEWPORT_SIZE.x,0))

func tf(pos: Vector2 = Vector2.ZERO, rot: float = 0.0, scl: Vector2 = Vector2.ONE) -> void:
	var t := Transform2D(rot,scl,0.0,pos)
	draw_set_transform_matrix(view_mirror()*t if field_mirror else t)

# Screen point -> battle point (and back: the mirror is its own inverse).
func to_model(p: Vector2) -> Vector2:
	return Vector2(L.VIEWPORT_SIZE.x-p.x,p.y) if mirror_view else p

func field_mouse() -> Vector2:
	return to_model(get_global_mouse_position())

# Text on the mirrored field stays readable: drawn unmirrored at the mirrored spot.
func field_text(pos: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, color: Color) -> void:
	if not field_mirror:
		draw_string(font,pos,text,align,width,size,color)
		return
	var w: float = width if width > 0 else font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_string(font,Vector2(L.VIEWPORT_SIZE.x-pos.x-w,pos.y),text,align,width,size,color)
	tf()

func say(text: String, _urgent: bool = false) -> void:
	notice = text # kept for the review log; nothing is drawn as text

func clear_ui() -> void:
	for control: Control in ui:
		remove_child(control)
		control.queue_free()
	ui.clear()

func button(rect: Rect2, caption: String, action: Callable) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.text = caption
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font",font)
	b.add_theme_font_size_override("font_size",20)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ead6aa")
	style.border_color = Color("846539")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal",style)
	b.add_theme_color_override("font_color",INK)
	b.pressed.connect(func():
		if ui_time_locked(): return
		if sound != null: sound.cue("ui_click")
		action.call())
	b.mouse_entered.connect(func():
		if sound != null and not b.disabled and not ui_time_locked(): sound.cue("ui_hover"))
	add_child(b)
	ui.append(b)
	return b

func _physics_process(dt: float) -> void:
	if net != null:
		if net.poll() and screen == "net": start_net_battle()
		if screen == "net": queue_redraw()
		if screen == "battle" and net.state == "playing":
			net.advance(model,dt,func():
				attack_animation.observe(model)
				consume_events())
		return
	if screen != "battle": return
	# Spectate mode can fast-forward: several fixed steps per frame, so results match 1x exactly.
	for i: int in range(speed if spectating else 1):
		if adventure.is_opening(): adventure.opening.advance(self,dt)
		attack_animation.observe(model)
		model.step(dt)
		if adventure.is_opening(): adventure.opening.observe(self)
		attack_animation.observe(model)
		consume_events()
		if not model.time_stopped():
			adventure.update(self)
			rogue.update(self)

func consume_events() -> void:
	review.observe(model)
	if levy_visual_model != model:
		levy_visuals.clear()
		levy_visual_model = model
	var current_levies := {}
	for u: Dictionary in model.units:
		if u.hp > 0 and u.get("levy",false): current_levies[u.id] = u
	if fx_enabled:
		for id in levy_visuals:
			if current_levies.has(id): continue
			var old: Dictionary = levy_visuals[id]
			# Only leaving territory vanishes; ordinary deaths keep their own effect.
			if old.hp > 0 and model.territory_owner(model.cell_at(old.pos)) != old.team:
				effects.append({"kind":"levy_dust","pos":old.pos,"life":0.5,"duration":0.5})
	levy_visuals = current_levies
	var hop := 0
	var sacrifice_team := -1
	for event_index: int in range(model.events.size()):
		var e: Dictionary = model.events[event_index]
		if e.kind == "spell":
			hop = 0
			sacrifice_team = e.team if e.get("card","") == "sacrifice" else -1
		if e.kind == "breach": say(("我方第 %d 路城牆被攻破！敵兵走進來就輸了" if e.team == 1 else "攻破藍旗第 %d 路城牆！派兵走進去就贏") % (e.lane+1),e.team == 1)
		if e.kind == "skill": say("%s%s發動「%s」" % ["紅方" if e.team == 0 else "藍方",B.lord_name(e.lord),B.lord_data(e.lord).get("skill","技能")])
		if e.kind == "ramp": say("金幣產出與卡牌冷卻加快 ×%.1f" % e.multiplier)
		if e.kind == "nightfall" and e.get("first",false): say("入夜：金幣 ×%s，雙方城牆開始朽壞" % B.number(B.NIGHT_GOLD))
		if e.kind == "overflow" and e.team == me and not spectating: say("金幣袋滿了，繼續產出的金幣會浪費")
		if sound != null:
			if sound.has_method("cue_event"): sound.cue_event(e)
			else: sound.cue(e.kind)
		if e.kind == "breach" and shake_enabled: shake_left = 0.25
		if fx_enabled:
			var copy := e.duplicate()
			copy.life = {"nightfall":2.6 if e.get("first",false) else 1.2,"breach":2.0,"ramp":1.4,"burn":5.0,"death":0.35,"play":0.45,"ink":0.6,"skill":1.0,"link":0.6,"slash":0.35,"drum":0.6,"stone_impact":0.5,"catapult_fire":0.4,"curse_rise":0.5}.get(e.kind,0.7)
			if e.kind == "link" and e.style == "lightning":
				copy.hop = hop
				hop += 1
				copy.life = 0.3
			if e.kind == "link" and e.style == "devour" and e.team == sacrifice_team and event_index+1 < model.events.size() and model.events[event_index+1].kind == "hit" and model.events[event_index+1].pos == e.pos:
				# Sacrifice links end at the cast point; blood-tower links retain their target.
				for cast_event: Dictionary in model.events:
					if cast_event.kind == "spell" and cast_event.get("card","") == "sacrifice" and cast_event.team == e.team and cast_event.pos == e.to:
						copy.to = to_model(preload("res://economy_hud.gd").PURSE.get_center() if e.team == me else Vector2(1322,35))
						copy.life = 0.85
						break
			if e.kind == "summoned" and model.units.any(func(u: Dictionary) -> bool: return u.get("levy",false) and u.team == e.team and u.pos.is_equal_approx(e.pos)):
				copy.kind = "levy_summon"
			copy.duration = copy.life
			effects.append(copy)
	model.events.clear()

# Screens that belong to the battle being played (the music and the veil treat them as one place).
func in_battle() -> bool:
	return screen in ["battle","battle_info","recap"] or (screen == "codex" and library.return_screen == "battle_info") or (screen == "settings" and settings_return == "battle")

# Presentation on real time, paused or not: the veil between screens, the ceremonies, the music.
const VEIL_TIME := 0.32
func present(dt: float) -> void:
	clock += dt
	var here := "battle" if in_battle() else screen
	if here != last_screen:
		if not last_screen.is_empty(): veil_left = VEIL_TIME
		last_screen = here
	veil_left = maxf(0.0,veil_left-dt)
	if veil != null: veil.color.a = pow(veil_left/VEIL_TIME,1.5)*0.92
	if model == null: return
	var fighting := in_battle()
	if fighting and not model.paused and not model.ended: intro_left = maxf(0.0,intro_left-dt)
	if fighting and model.ended:
		if result_seen != model:
			result_seen = model
			result_age = 0.0
			if music != null: music.play_sting("victory" if Ceremony.mood(self) > 0 else "defeat")
		result_age += dt
	if music == null: return
	music.enabled = music_volume > 0.001
	if not fighting:
		music.stop_sting()
		music.duck = 1.0
		music.want("menu")
	elif model.ended: music.want("")
	else:
		music.duck = 0.4 if model.paused else 1.0
		var phase: int = model.day_phase()
		if phase == 3: music.want("night")
		else: music.want("battle",phase)

func _process(dt: float) -> void:
	present(dt)
	if ui_time_locked():
		queue_redraw()
		return
	if model != null and model.paused: dt = 0
	shake_left = maxf(0,shake_left-dt)
	purse_alarm = maxf(0,purse_alarm-dt)
	place_flash = maxf(0,place_flash-dt)
	skill_shake = maxf(0,skill_shake-dt)
	for k: int in card_shake.keys():
		card_shake[k] -= dt
		if card_shake[k] <= 0: card_shake.erase(k)
	position = Vector2(sin(shake_left*180),cos(shake_left*210))*shake_left*18 if shake_enabled and shake_left > 0 else Vector2.ZERO
	for e: Dictionary in effects: e.life -= dt
	effects = effects.filter(func(e: Dictionary) -> bool: return e.life > 0)
	queue_redraw()

# Hand area: the permanent farmland slot, the four rotating cards, then the next-card preview.
func card_rect(slot: int) -> Rect2:
	if slot == Battle.FARM_SLOT: return Rect2(418,730,124,158)
	return Rect2(560+slot*134,730,124,158)

func card_at(pos: Vector2) -> int:
	for i: int in [0,1,2,3,Battle.FARM_SLOT]:
		if card_rect(i).has_point(pos): return i
	return -1

func toggle_pause() -> void:
	if ui_time_locked() or net != null: return
	if not model.ended: model.paused = not model.paused

func set_speed(value: int) -> void:
	speed = value
	say("觀戰速度 ×%d" % speed)

# Buttons on the pause banner / closing page: [rect, caption, action], centred as a row.
func overlay_buttons() -> Array:
	var entries: Array = []
	if not model.ended: entries.append(["繼續",toggle_pause])
	else: entries.append(["戰局復盤",show_review])
	if net == null and not rogue.in_battle: entries.append(["重新開始",restart])
	if not model.ended: entries.append(["設定",func(): settings_return = "battle"; show_settings()])
	if rogue.in_battle: entries.append(["肉鴿進度" if model.ended else "認輸離開",func(): rogue.leave_battle(self)])
	else: entries.append(["冒險地圖",show_adventure] if adventure.index >= 0 else ["回到標題",show_title])
	var y := RESULT_RECT.end.y-62 if model.ended else L.OVERLAY_RECT.position.y+95
	var width := 190.0 if entries.size() <= 3 else 158.0
	var gap := 20.0 if entries.size() <= 3 else 12.0
	var x := L.VIEWPORT_SIZE.x*0.5-(entries.size()*width+(entries.size()-1)*gap)*0.5
	var items: Array = []
	for i: int in range(entries.size()): items.append([Rect2(x+i*(width+gap),y,width,40),entries[i][0],entries[i][1]])
	return items

func try_play(slot: int, pos: Vector2) -> bool:
	if adventure.is_opening() and adventure.opening.active: return false
	pos = to_model(pos)
	var reason: String = model.play_error(me,slot,pos)
	if reason.is_empty() and net != null:
		net.queue(["p",slot,pos.x,pos.y]) # runs on both machines a few ticks from now
		selected = -1
		return true
	if reason.is_empty() and model.play(me,slot,pos):
		selected = -1
		return true
	say(reason)
	match model.play_check(me,slot,pos):
		Battle.Refusal.GOLD:
			purse_alarm = 0.9
			purse_need = B.CARDS[model.kind_at(me,slot)].cost
		Battle.Refusal.COOLDOWN: card_shake[slot] = 0.45
		Battle.Refusal.NOT_OURS, Battle.Refusal.OFF_GRID, Battle.Refusal.OCCUPIED: place_flash = 1.0
	effects.append({"kind":"fail","pos":pos,"life":0.5,"duration":0.5})
	if sound != null: sound.cue("fail")
	return false

func _unhandled_input(event: InputEvent) -> void:
	if ui_time_locked(): return
	if screen == "recap" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_review()
		return
	if screen == "deck" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if watch_edit >= 0:
			finish_watch_edit(false)
			return
		if adventure_deck_mode:
			if DeckStore.valid(player_deck,player_lord):
				adventure.custom_deck = player_deck.duplicate()
				adventure.save_progress()
			adventure_deck_mode = false
			show_adventure()
		else:
			show_title()
		return
	if screen in ["codex","battle_info"]:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			if screen == "codex": library.back()
			else: library.close_battle_info()
		return
	if screen in ["settings","help","watch","net","adventure","rogue"] and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if screen == "settings": preload("res://settings_screen.gd").back(self)
		else: show_title()
		return
	if screen != "battle": return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and library.INFO_RECT.has_point(event.position):
		library.show_battle_info()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			var index: int = event.keycode-KEY_1
			if spectating: set_speed(SPEEDS[index])
			else: selected = -1 if selected == index else index
		if event.keycode == KEY_Q and not spectating: try_skill()
		if event.keycode == KEY_F and not spectating: selected = -1 if selected == Battle.FARM_SLOT else Battle.FARM_SLOT
		if spectating and event.keycode in [KEY_EQUAL,KEY_KP_ADD,KEY_PLUS]: set_speed(SPEEDS[mini(SPEEDS.find(speed)+1,SPEEDS.size()-1)])
		if spectating and event.keycode in [KEY_MINUS,KEY_KP_SUBTRACT]: set_speed(SPEEDS[maxi(SPEEDS.find(speed)-1,0)])
		if event.keycode == KEY_ESCAPE:
			if selected >= 0: selected = -1
			else: toggle_pause()
		if event.keycode == KEY_SPACE: toggle_pause()
		if event.keycode == KEY_R and net == null:
			if model.paused or model.ended: restart()
			else: say("戰鬥中 R 不重開；空白鍵暫停後可重玩")
	if event is InputEventMouseMotion:
		var over: int = -1 if spectating else card_at(event.position)
		if over != hover_slot and over >= 0 and not model.paused and not model.ended and sound != null: sound.cue("ui_hover")
		hover_slot = over
	if event is InputEventMouseButton:
		var pos: Vector2 = event.position
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			selected = -1
			dragging = false
		if event.button_index != MOUSE_BUTTON_LEFT: return
		if event.pressed:
			if model.ended and result_age < Ceremony.PANEL_DELAY+Ceremony.PANEL_IN: return
			if model.paused or model.ended:
				for item: Array in overlay_buttons():
					if item[0].has_point(pos):
						item[2].call()
						return
				if L.PAUSE_RECT.has_point(pos): toggle_pause()
				return
			if L.PAUSE_RECT.has_point(pos):
				toggle_pause()
				return
			if spectating:
				for i: int in range(SPEEDS.size()):
					if SPEED_RECTS[i].has_point(pos): set_speed(SPEEDS[i])
				return
			if SKILL_RECT.has_point(pos):
				try_skill()
				return
			var slot := card_at(pos)
			if slot >= 0:
				# Press on a card selects it and starts a drag; releasing over the field plays it.
				if sound != null: sound.cue("ui_click")
				press_was_selected = selected == slot
				selected = slot
				dragging = true
				press_pos = pos
				return
			if selected >= 0: try_play(selected,pos)
		elif dragging:
			dragging = false
			var slot := card_at(pos)
			if slot < 0 and pos.distance_to(press_pos) > 12 and selected >= 0: try_play(selected,pos)
			elif slot == selected and press_was_selected and pos.distance_to(press_pos) <= 12: selected = -1 # clicking the selected card again puts it back

func label_at(pos: Vector2, text: String, size: int = 20, color: Color = INK) -> void:
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func panel(rect: Rect2, fill: Color = Color("ecdcb6"), border: Color = INK) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(border,0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	draw_style_box(style,rect)
	if rect.size.x > 30 and rect.size.y > 20: draw_rect(rect.grow(-4),Color(border,0.3),false,1)

func bar(rect: Rect2, value: float, maximum: float, color: Color) -> void:
	draw_rect(rect.grow(1),Color(INK,0.8))
	draw_rect(rect,Color("dccba3"))
	draw_rect(Rect2(rect.position,Vector2(rect.size.x*clampf(value/maximum,0,1),rect.size.y)),color)

# Hand-drawn ink stroke: a slightly wavering line instead of a ruler-straight one.
func ink_line(a: Vector2, b: Vector2, seed: float, color: Color = Color(INK,0.35), width: float = 1.6) -> void:
	var points := PackedVector2Array()
	var normal := (b-a).orthogonal().normalized()
	for i: int in range(33):
		var t := i/32.0
		points.append(a.lerp(b,t)+normal*(sin(t*17.0+seed*3.1)*1.4+sin(t*43.0+seed)*0.6))
	draw_polyline(points,color,width,true)

# Manuscript-style diagonal hatching clipped to a rectangle.
func hatch(rect: Rect2, color: Color, step: float = 13.0) -> void:
	var w := rect.size.x
	var h := rect.size.y
	var d := -h
	while d < w:
		var x0 := d
		var y0 := h
		var x1 := d+h
		var y1 := 0.0
		if x0 < 0:
			y0 += x0
			x0 = 0
		if x1 > w:
			y1 += x1-w
			x1 = w
		if x0 < x1: draw_line(rect.position+Vector2(x0,y0),rect.position+Vector2(x1,y1),color,1.2,true)
		d += step

func ink_frame(rect: Rect2) -> void:
	draw_rect(rect,Color(INK,0.8),false,3)
	draw_rect(rect.grow(-6),Color(INK,0.45),false,1)

func art(kind: String, team: int = 0) -> Texture2D:
	if team == 1 and blue_art.has(kind): return blue_art[kind]
	if kind == "lord_adventure": return get_adventure_frame(0, team)
	return textures.get(kind,textures.militia)

func lord_art(kind: String, team: int = 0) -> Texture2D:
	var key := kind if kind.begins_with("lord_") else "lord_"+kind
	return blue_art[key] if team == 1 and blue_art.has(key) else textures.get(key,textures.militia)

# Recolour only designated team materials. Natural fields/skin/wood are not team ink.
# Ox cloth additionally has a spatial mask so its brown coat never enters the palette swap.
# 魔物 art paints its team zone in a warmer vermilion; open mouths and tongues stay red on both teams.
const BEAST_MOUTHS := {"eyewing_dragon":Rect2(0.58,0.62,0.22,0.35),"belly_eye":Rect2(0.68,0.30,0.25,0.32),"fishbeak":Rect2(0.70,0.30,0.16,0.14),"hooknose_flyer":Rect2(0.76,0.44,0.08,0.12),"long_dragon":Rect2(0.78,0.40,0.22,0.45),"thorn_dragon":Rect2(0.80,0.40,0.20,0.50)}

static func team_material(kind: String, uv: Vector2, c: Color) -> bool:
	if kind == "sacrifice": return false
	if B.CARDS.get(kind,{}).get("series","") == "beast":
		if BEAST_MOUTHS.has(kind) and BEAST_MOUTHS[kind].has_point(uv): return false
		return c.a >= 0.05 and c.s >= 0.5 and c.v >= 0.25 and (c.h <= 0.06 or c.h >= 0.95) # ritual blood keeps its meaning on both teams
	if kind == "blood_tower" and (Rect2(0.17,0.20,0.59,0.34).has_point(uv) or Rect2(0.78,0.40,0.16,0.24).has_point(uv)): return false # reservoirs, not cloth
	if kind == "castle_wall" and Rect2(0.48,0.55,0.26,0.45).has_point(uv): return false # recessed timber gate
	if kind == "catapult": return uv.x > 0.73 and uv.y < 0.28 and c.a >= 0.05 and c.s >= 0.35 and c.v >= 0.20 and (c.h <= 0.08 or c.h >= 0.95)
	if kind == "bonewall": return (uv.x < 0.30 or uv.x > 0.80) and c.a >= 0.05 and c.s >= 0.60 and c.v >= 0.30 and (c.h <= 0.075 or c.h >= 0.95)
	if kind in ["farm","farmer","harvest","rain","fire","teleport_trap","blast_trap"]: return false
	if kind == "ox" and not Rect2(0.30,0.20,0.26,0.36).has_point(uv): return false
	if kind == "ram" and uv.y > 0.55: return false
	# Architecture's weathered red paint is less saturated than character cloth.
	if kind in ["castle_red","castle_blue","castle_wall"]:
		return c.a >= 0.05 and c.s >= 0.33 and c.v >= 0.18 and (c.h <= 0.07 or c.h >= 0.93)
	return c.a >= 0.05 and c.s >= 0.55 and c.v >= 0.25 and (c.h <= 0.035 or c.h >= 0.965)

static func recolor_blue(source: Texture2D, max_size: int, kind: String = "") -> Texture2D:
	if kind in ["farm","farmer","harvest","rain","fire"]: return source
	var key := str(source.get_instance_id())+":"+str(max_size)+":"+kind
	if recolor_cache.has(key): return recolor_cache[key]
	# Build-time derivatives of the single source set; no per-pixel work on normal startup.
	if palette_manifest.is_empty() and FileAccess.file_exists("res://assets/generated-palette/manifest.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated-palette/manifest.json"))
		if parsed is Dictionary: palette_manifest = parsed
	var entry: Dictionary = palette_manifest.get(kind,{})
	var generated := "res://assets/generated-palette/"+kind+".png"
	if entry.get("revision","") == PALETTE_REVISION and entry.get("source","") == source.resource_path and int(entry.get("size",-1)) == max_size and ResourceLoader.exists(generated):
		# Original source files can be remapped inside exports; the build manifest remains valid there.
		if not FileAccess.file_exists(source.resource_path) or entry.get("sha256","") == FileAccess.get_sha256(source.resource_path):
			var texture: Texture2D = load(generated)
			recolor_cache[key] = texture
			return texture
	# Read the source file itself when it exists: the imported texture can be stale right after the
	# art was edited (that once left the blue bandit facing the old way). Exports fall back to it.
	var img: Image = Image.load_from_file(source.resource_path) if FileAccess.file_exists(source.resource_path) else source.get_image()
	if img == null: img = source.get_image()
	if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var scale := minf(1.0,float(max_size)/maxf(img.get_width(),img.get_height())) if max_size > 0 else 1.0
	if scale < 1.0: img.resize(maxi(1,roundi(img.get_width()*scale)),maxi(1,roundi(img.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c := img.get_pixel(x,y)
			if not team_material(kind,Vector2(float(x)/img.get_width(),float(y)/img.get_height()),c): continue
			c.h = 0.6
			c.s = minf(1.0,c.s*0.95)
			c.v *= 0.9
			img.set_pixel(x,y,c)
	var result := ImageTexture.create_from_image(img)
	recolor_cache[key] = result
	return result

static func fitted_rect(source_size: Vector2, box: Rect2, bottom: bool = false) -> Rect2:
	var size := source_size*minf(box.size.x/source_size.x,box.size.y/source_size.y)
	var pos := box.position+(box.size-size)*0.5
	if bottom: pos.y = box.end.y-size.y
	return Rect2(pos,size)

func draw_fitted(texture: Texture2D, box: Rect2, shade: Color = Color.WHITE, bottom: bool = false) -> void:
	draw_texture_rect(texture,fitted_rect(texture.get_size(),box,bottom),false,shade)

# Same as draw_fitted, mirrored left-right when face < 0. Unit art faces right (toward blue).
func draw_fitted_facing(texture: Texture2D, box: Rect2, face: float, shade: Color = Color.WHITE) -> void:
	if field_mirror: face = -face
	var r := fitted_rect(texture.get_size(),box,false)
	if face >= 0:
		draw_texture_rect(texture,r,false,shade)
		return
	var c := r.get_center()
	tf(c,0,Vector2(-1,1))
	draw_texture_rect(texture,Rect2(r.position-c,r.size),false,shade)
	tf()

func actor_rect(kind: String) -> Rect2:
	if kind == "pouch_beast": return fitted_rect(art(kind).get_size(),Rect2(-58,-62,116,92),true)
	if B.CARDS.get(kind,{}).get("series","") == "magic" and B.CARDS[kind].type == "unit": return fitted_rect(art(kind).get_size(),Rect2(-65,-95,130,112),true)
	if kind == "glutton_nest": return fitted_rect(art(kind).get_size(),Rect2(-45,-28,90,62),true)
	if B.CARDS.get(kind,{}).has("trap"): return fitted_rect(art(kind).get_size(),Rect2(-45,-8,90,46),true)
	if B.CARDS.get(kind,{}).get("series","") == "beast":
		var box: Rect2 = {"long_dragon":Rect2(-85,-50,170,67),"thorn_dragon":Rect2(-75,-75,150,92),"belly_eye":Rect2(-66,-72,132,89)}.get(kind,Rect2(-58,-75,116,92))
		return fitted_rect(art(kind).get_size(),box,true)
	if kind == "arcane_tower": return fitted_rect(art(kind).get_size(),Rect2(-40,-65,80,100),true)
	if kind == "corpse_giant": return fitted_rect(art(kind).get_size(),Rect2(-52,-85,104,104),true)
	if kind == "lord_adventure": return fitted_rect(get_adventure_frame(0,0).get_size(),Rect2(-57,-75,114,102),true)
	if kind.begins_with("lord_"): return fitted_rect(art(kind).get_size(),Rect2(-47,-67,94,94),true)
	if kind in ["catapult"] or B.CARDS.get(kind,{}).get("type","") == "building": return fitted_rect(art(kind).get_size(),Rect2(-45,-39,90,78),true)
	var width := 112.0 if kind in ["ox","ram"] else 80.0
	return fitted_rect(art(kind).get_size(),Rect2(-width/2,-63,width,80),true)

func draw_actor(kind: String, team: int, pos: Vector2, face: float, shade: Color = Color.WHITE) -> void:
	if field_mirror: face = -face # the mirror flips the art; flip it back so troops face their way
	tf(pos,0,Vector2(face,1))
	draw_texture_rect(art(kind,team),actor_rect(kind),false,shade)
	tf()

func draw_combat_actor(kind: String, actor: Dictionary, pos: Vector2, face: float, shade: Color = Color.WHITE) -> void:
	if kind == "glutton_nest":
		preload("res://glutton_nest.gd").draw(self,actor,pos)
		return
	if kind == "farm": shade *= Color(0.90,0.88,0.82)
	if kind == "crystal":
		var brightness := lerpf(0.30,1.0,clampf(actor.hp/actor.max_hp,0,1))
		shade *= Color(brightness,brightness,brightness,1)
	if B.CARDS.get(kind,{}).has("trap"):
		draw_arc(pos+Vector2(0,17),35,0,TAU,32,RED if actor.team == 0 else BLUE,2,true)
		var max_charges: int = B.CARDS[kind].get("charges",0)
		if max_charges > 0: # every trap with uses left shows them as dots (teleport, blast, summon...)
			var charges: int = actor.get("charges",max_charges)
			for i in range(max_charges):
				var p_col: Color = (Color("00e5ff") if i < charges else Color("555555",0.5))
				draw_circle(pos+Vector2((i-(max_charges-1)/2.0)*12,42),4.0,p_col)
	var pose: Dictionary = attack_animation.pose(actor,model.actor_time(actor)) if fx_enabled else {}
	if pose.is_empty():
		draw_actor(kind,actor.team,pos,face,shade)
		return
	var offset: Vector2 = pose.offset
	offset.x *= face
	var rect := actor_rect(kind)
	var center := rect.get_center()
	var angle: float = pose.angle*face
	var scale: Vector2 = pose.scale
	# Pivot around the sprite centre; keep large actors inside the battlefield's top edge.
	var pivot := pos+Vector2(center.x*face,center.y)+offset
	var extent: float = absf(sin(angle))*rect.size.x*scale.x/2+absf(cos(angle))*rect.size.y*scale.y/2
	pivot.y = maxf(pivot.y,L.GRID_ORIGIN.y+6+extent)
	tf(pivot,angle,Vector2(face,1)*scale)
	var tex := art(kind,actor.team)
	if kind == "lord_adventure" and pose.has("frame"):
		tex = get_adventure_frame(pose.frame,actor.team)
	draw_texture_rect(tex,Rect2(-rect.size/2,rect.size),false,shade)
	tf(pos,0,Vector2(face,1))
	var ink := Color(INK,pose.strength*0.8)
	match pose.style:
		"cleave":
			if pose.get("frame",0) in [2,3]:
				var slash_ink := Color(INK,pose.strength*0.85)
				draw_arc(Vector2(20,-22),34.0,-1.3,0.8,14,slash_ink,2.8,true)
				draw_line(Vector2(14,-36),Vector2(40,-6),slash_ink,2.4,true)
		"heavy", "thrust":
			var radius := 28.0 if pose.style == "heavy" else 17.0
			draw_arc(Vector2(18,-25),radius,-1.15,0.9,12,ink,2.2,true)
			draw_line(Vector2(15,-25),Vector2(34+12*pose.strength,-25),ink,2,true)
		"bow", "tower":
			for i: int in range(3): draw_line(Vector2(12,-28+i*5),Vector2(27+8*pose.progress,-28+i*5),Color(INK,pose.strength*(0.6-i*0.1)),1.5,true)
		"cast":
			var magic := Color("a28cba")
			magic.a = pose.strength
			draw_arc(Vector2(22,-35),9+pose.progress*17,0,TAU,18,magic,2,true)
			for i: int in range(4):
				var p: Vector2 = Vector2(22,-35)+Vector2.from_angle(i*PI/2+pose.progress)*(13+pose.progress*20)
				draw_line(p-Vector2(3,0),p+Vector2(3,0),magic,1.5,true)
		"ram", "siege":
			for i: int in range(4): draw_circle(Vector2(-15-i*7,19-pose.progress*9),2.5*pose.strength,Color(0.48,0.37,0.23,pose.strength*0.6))
		"peck":
			draw_line(Vector2(19,-20),Vector2(30,-14),ink,2,true)
			draw_line(Vector2(20,-12),Vector2(31,-8),ink,1.5,true)
		"drum":
			draw_arc(Vector2(15,-18),10+pose.progress*18,-1.4,1.4,12,Color(0.8,0.6,0.2,pose.strength),2,true)
	tf()

func card_art_kinds(kind: String) -> Array:
	var reference: Variant = B.CARDS[kind].get("art",[kind])
	if reference is String:
		return [kind] if textures.has(kind) else [reference]
	return reference

func draw_card_art(kind: String, box: Rect2, team: int = 0, shade: Color = Color.WHITE) -> void:
	var kinds := card_art_kinds(kind)
	for i: int in range(kinds.size()):
		var part := box
		if kinds.size() > 1:
			part.size.x = box.size.x*0.58
			part.position.x += i*box.size.x*0.42
		draw_fitted(art(kinds[i],team),part,shade,true)

func draw_card(kind: String, rect: Rect2, slot: int = -1) -> void:
	var data: Dictionary = B.CARDS[kind]
	if card_shake.has(slot): rect.position.x += sin(card_shake[slot]*55)*5*clampf(card_shake[slot]/0.45,0,1)
	var s := rect.size
	var short: bool = screen == "battle" and model.ink[me] < data.cost
	draw_texture_rect(ART.card(selected == slot and slot >= 0),rect,false,preload("res://command_style.gd").card_tint(kind))
	preload("res://command_style.gd").type_frame(self,rect,data.type)
	preload("res://command_style.gd").faction_frame(self,rect,kind,selected == slot and slot >= 0)
	# No countdowns or shortfall numbers on cards (producer 2026-11-03). Not enough gold: a still
	# grey mask. Cooling: a grey curtain that slowly parts from the middle (drawn further down).
	var cooling: bool = slot >= 0 and screen == "battle" and model.slot_cd(me,slot) > 0
	var blocked: bool = short and slot >= 0
	var art_box := Rect2(rect.position+s*Vector2(0.08,0.13),s*Vector2(0.84,0.5))
	var shade := Color(0.45,0.45,0.45) if short else Color.WHITE
	draw_card_art(kind,art_box,0,shade)
	if blocked: draw_rect(rect.grow(-3),Color(0.40,0.40,0.40,0.50))
	# Name and type sit above the frame's bottom corner flowers (they start ~83% down).
	draw_string(font,rect.position+Vector2(0,s.y*0.74),data.name,HORIZONTAL_ALIGNMENT_CENTER,s.x,17,Color("2e2219") if blocked else INK)
	draw_string(font,rect.position+Vector2(0,s.y*0.83),data.role,HORIZONTAL_ALIGNMENT_CENTER,s.x,13,Color("33261a") if blocked else Color("5a4630"))
	if screen == "battle" and model != null and me < model.card_upgrades.size():
		var lv: int = preload("res://card_upgrades.gd").level(model.card_upgrades[me].get(kind,{}))
		if lv > 0: # roguelike shop upgrade
			draw_circle(rect.position+Vector2(19,s.y*0.66),13,RED)
			draw_string(font,rect.position+Vector2(6,s.y*0.66+6),"+%d" % lv,HORIZONTAL_ALIGNMENT_CENTER,26,15,Color("fff0ca"))
	if screen != "battle":
		# Outside battle the top-left corner shows the card's cooldown (in battle it shows the hand slot).
		draw_rect(Rect2(rect.position+Vector2(7,7),Vector2(34,20)),Color("725138"))
		draw_string(font,rect.position+Vector2(7,22),"%ss" % B.number(data.cooldown),HORIZONTAL_ALIGNMENT_CENTER,34,13,Color("efdfb9"))
		# Faction tag (經典／黑暗／中立) between the cooldown and the cost.
		var faction: String = B.card_faction(kind)
		var tag := Rect2(rect.position+Vector2(s.x*0.5-18,8),Vector2(36,17))
		draw_rect(tag,preload("res://command_style.gd").tag_color(kind))
		draw_string(font,tag.position+Vector2(0,13),B.FACTIONS[faction],HORIZONTAL_ALIGNMENT_CENTER,tag.size.x,12,Color("f3e6c4"))
	if cooling: curtain(rect.grow(-3),clampf(model.slot_cd(me,slot)/maxf(0.1,data.cooldown),0,1))
	# Ink cost badge, top right.
	var badge := rect.position+Vector2(s.x-19,19)
	draw_circle(badge,15,Color("2f3f5c"))
	draw_arc(badge,15,0,TAU,24,Color("cfaa60"),2)
	draw_string(font,badge+Vector2(-15,6),("-" if data.get("summon_only",false) else str(data.cost)),HORIZONTAL_ALIGNMENT_CENTER,30,16,Color("f3e6c4"))
	if slot >= 0:
		var key := "F" if slot == Battle.FARM_SLOT else str(slot+1)
		draw_rect(Rect2(rect.position+Vector2(7,7),Vector2(22,22)),Color("3f5a2c") if slot == Battle.FARM_SLOT else Color("725138"))
		draw_string(font,rect.position+Vector2(7,24),key,HORIZONTAL_ALIGNMENT_CENTER,22,14,Color("efdfb9"))

# A grey stage curtain over r: two halves that part from the middle as `closed` goes 1 -> 0.
# Soft folds (light and shade bands) and a pale hem on the leading edge, like drawn cloth.
func curtain(r: Rect2, closed: float) -> void:
	var half := r.size.x*0.5*closed
	if half < 0.5: return
	for side: int in range(2):
		var cloth := Rect2(r.position.x if side == 0 else r.end.x-half,r.position.y,half,r.size.y)
		draw_rect(cloth,Color(0.38,0.37,0.36,0.82))
		var fold := 0
		var x := cloth.position.x
		while x < cloth.end.x:
			var w := minf(7.0,cloth.end.x-x)
			draw_rect(Rect2(x,cloth.position.y,w,cloth.size.y),Color(1,1,1,0.07) if fold%2 == 0 else Color(0,0,0,0.10))
			x += 7.0
			fold += 1
		var edge: float = cloth.end.x if side == 0 else cloth.position.x
		draw_line(Vector2(edge,r.position.y),Vector2(edge,r.end.y),Color(0.80,0.78,0.72,0.9),2)

func _draw() -> void:
	if font == null or model == null: return
	draw_texture_rect(PAPER,Rect2(Vector2.ZERO,L.VIEWPORT_SIZE),false,PAPER_TINT)
	if screen != "battle": draw_landscape(L.PAGE_FRAME.grow(-7),0.46)
	panel(L.PAGE_FRAME,Color(0.85,0.74,0.53,0.15))
	if screen == "battle": draw_battle()
	elif screen == "adventure": adventure.paint(self)
	elif screen == "rogue": rogue.paint(self)
	elif screen == "adventure_finale": adventure.finale.paint(self)
	elif screen == "adventure_ending": adventure.ending.paint(self)
	elif screen == "road_toll_story": adventure.active_story().paint(self)
	elif screen == "recap":
		panel(Rect2(100,70,1400,700))
		label_at(Vector2(140,128),"戰局復盤",38)
	elif screen == "codex": library.draw_catalog()
	elif screen == "battle_info": library.draw_battle_info()
	elif screen == "deck": draw_deck()
	elif screen == "watch": draw_watch()
	elif screen == "net": draw_net()
	elif screen == "help": draw_help()
	elif screen == "settings": preload("res://settings_screen.gd").paint(self)
	else: draw_title()
	if ui_time_locked(): draw_time_stop()

func ui_time_locked() -> bool:
	return model != null and model.time_stopped()

# Handle before GUI controls, so mouse, keyboard and hotkeys all remain frozen.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed)):
		set_fullscreen(not fullscreen)
		if screen == "settings": show_settings()
		get_viewport().set_input_as_handled()
		return
	if ui_time_locked(): get_viewport().set_input_as_handled()

func draw_time_stop() -> void:
	var age: float = B.LORDS.mage.freeze_duration-model.time_stop_left
	var fade: float = minf(1.0,model.time_stop_left*2.0)
	draw_rect(Rect2(Vector2.ZERO,L.VIEWPORT_SIZE),Color(0.16,0.19,0.34,0.16*fade))
	# Concentric space ripples expand from the caster over the whole page, including UI.
	for i: int in range(3):
		var wave: float = age*1100-i*95
		if wave > 0 and wave < 2100:
			draw_arc(model.time_stop_origin,wave,0,TAU,128,Color(0.7,0.77,0.95,0.65*fade),4,true)
	panel(Rect2(590,102,420,44),Color("d9d9df"),Color("666681"))
	draw_string(font,Vector2(590,132),"時空凝滯 · %.1f 秒" % model.time_stop_left,HORIZONTAL_ALIGNMENT_CENTER,420,24,Color("46435f"))

# Flat manuscript pigments over paper; deterministic strokes never consume battle RNG.
static func scenery_noise(index: int, salt: int) -> float:
	return fposmod(sin(index*127.1+salt*311.7)*43758.5453,1.0)

func ground_wash(center: Vector2, size: Vector2, pigment: Color, seed_value: int, opacity: float) -> void:
	for layer: int in range(3):
		var points := PackedVector2Array()
		for n: int in range(20):
			var angle := n*TAU/20
			var radius := (1.0-layer*0.15)*(0.85+scenery_noise(n,seed_value+5)*0.15)
			points.append(center+Vector2(cos(angle),sin(angle))*size*radius)
		draw_colored_polygon(points,Color(pigment,opacity))

func draw_battle_landscape(field: Rect2) -> void:
	draw_rect(field,Color("81975e"))
	# Stable pigment washes and ground details; never touch the simulation RNG.
	for i: int in range(42):
		var center := field.position+Vector2(60+scenery_noise(i,1)*(field.size.x-120),35+scenery_noise(i,2)*(field.size.y-70))
		ground_wash(center,Vector2(35+scenery_noise(i,3)*65,14+scenery_noise(i,4)*22),Color("566f40") if i%3 == 0 else Color("bcc78a"),i,0.035)
	for lane: int in range(5):
		var path := PackedVector2Array()
		for i: int in range(33):
			path.append(Vector2(220+i*36.25,L.cell_center(Vector2i(0,lane)).y+25+sin(i*0.34+lane)*5))
		draw_polyline(path,Color(0.68,0.60,0.40,0.09),20,true)
		draw_polyline(path,Color(0.74,0.67,0.45,0.07),9,true)
	for b: Dictionary in model.buildings:
		if b.hp <= 0: continue
		if b.hp > 0: ground_wash(b.pos+Vector2(0,26),Vector2(53,17),Color("8f7952"),int(b.cell.x+b.cell.y*9),0.13)
	draw_texture_rect(PAPER,field,false,Color(1,1,1,0.08))

func draw_landscape(rect: Rect2, horizon: float) -> void:
	draw_rect(rect,Color("8db7cb"))
	var top := rect.position
	var line_y := top.y+rect.size.y*horizon
	# Faint geometric sky ornament, like the painted diaper patterns in manuscripts.
	for x: int in range(int(top.x)+22,int(rect.end.x)-20,58):
		for y: int in range(int(top.y)+14,int(line_y)-10,42):
			draw_polyline(PackedVector2Array([Vector2(x,y-9),Vector2(x+15,y),Vector2(x,y+9),Vector2(x-15,y),Vector2(x,y-9)]),Color(0.85,0.92,0.89,0.22),1.4,true)
	if fx_enabled: draw_sky_life(rect,line_y)
	for layer: int in range(3):
		var points := PackedVector2Array()
		for i: int in range(65):
			var x := rect.size.x*i/64.0
			var y := line_y+layer*rect.size.y*0.12+sin(i*0.12+layer*1.7)*rect.size.y*0.025
			points.append(top+Vector2(x,y-top.y))
		points.append(rect.end)
		points.append(Vector2(top.x,rect.end.y))
		draw_colored_polygon(points,[Color("7e9661"),Color("708a51"),Color("81965b")][layer])
	for i: int in range(95 if rect.size.y > 200 else 0):
		var x := top.x+12+fposmod(i*137.39,rect.size.x-24)
		var y := line_y+32+fposmod(i*79.73,maxf(1,rect.end.y-line_y-46))
		tuft(Vector2(x,y),Color(0.77,0.80,0.49,0.34),7+float(i%5))
	# Let the existing parchment grain show through the painted pigments.
	draw_texture_rect(PAPER,rect,false,Color(1,1,1,0.19))

# Slow painted clouds and a few birds, so no menu page is a still picture. Real time only.
# Both fade in and out near the page edge instead of sliding over the frame.
func draw_sky_life(rect: Rect2, line_y: float) -> void:
	var span := rect.size.x+120.0
	for i: int in range(6):
		var speed := 5.0+scenery_noise(i,201)*7.0
		var x := rect.position.x-60.0+fposmod(scenery_noise(i,202)*span+clock*speed,span)
		var y := rect.position.y+40.0+scenery_noise(i,203)*maxf(20.0,line_y-rect.position.y-160.0)
		var size := 0.7+scenery_noise(i,204)*0.7
		var edge := clampf(minf(x-rect.position.x-70.0*size,rect.end.x-x-70.0*size)/90.0,0.0,1.0)
		if edge <= 0.0: continue
		for puff: Array in [[-46.0,6.0,26.0],[-18.0,-8.0,34.0],[18.0,-4.0,30.0],[46.0,8.0,22.0],[0.0,10.0,30.0]]:
			tf(Vector2(x+puff[0]*size,y+puff[1]*size),0,Vector2(1.25,0.62))
			draw_circle(Vector2.ZERO,puff[2]*size,Color(0.97,0.96,0.90,0.30*edge))
			tf()
	for i: int in range(3):
		var lap := 46.0+i*17.0 # seconds for one crossing
		var k := fposmod(clock/lap+scenery_noise(i,211),1.0)
		var at := Vector2(rect.position.x+20+k*(rect.size.x-40),rect.position.y+70+scenery_noise(i,212)*120+sin(clock*0.7+i*2.0)*10)
		var flap := sin(clock*7.0+i*1.7)*5.0
		draw_polyline(PackedVector2Array([at+Vector2(-9,-flap),at,at+Vector2(9,-flap)]),Color(INK,0.55*clampf(minf(k,1.0-k)*12.0,0.0,1.0)),1.8,true)

func draw_battle() -> void:
	if adventure.is_opening():
		adventure.opening.paint(self)
		return
	field_mirror = mirror_view
	tf()
	var field: Rect2 = L.FIELD_FRAME
	draw_texture_rect_region(PAPER,field,Rect2(field.position*0.6,field.size*0.6),FIELD_TINT)
	draw_battle_landscape(field.grow(-7))
	ink_frame(field)
	var corner := Vector2(96,86)
	draw_texture_rect(ART.ornament(0),Rect2(field.position+Vector2(8,8),corner),false,Color(1,1,1,0.85))
	draw_texture_rect(ART.ornament(1),Rect2(Vector2(field.end.x-8-corner.x,field.position.y+8),corner),false,Color(1,1,1,0.85))
	draw_texture_rect(ART.ornament(2),Rect2(Vector2(field.position.x+8,field.end.y-8-corner.y),corner),false,Color(1,1,1,0.85))
	draw_texture_rect(ART.ornament(3),Rect2(field.end-Vector2(8,8)-corner,corner),false,Color(1,1,1,0.85))
	# The castles are scenery: drawn a little muted so the gates and troops lead the eye.
	draw_texture_rect(art("castle_wall",0),L.CASTLE_RECTS[0],false,CASTLE_SHADE)
	draw_mirrored(art("castle_wall",1),L.CASTLE_RECTS[1],CASTLE_SHADE)
	var grid := Rect2(L.GRID_ORIGIN,L.GRID_SIZE)
	draw_ground(grid)
	for row: int in range(L.GRID_ROWS):
		for col: int in range(L.GRID_COLUMNS):
			var cell := Vector2i(col,row)
			var owner: int = model.territory_owner(cell)
			if owner < 0: continue
			var r := Rect2(L.GRID_ORIGIN+Vector2(cell)*L.CELL_SIZE,L.CELL_SIZE)
			draw_rect(r, Color(RED if owner == 0 else BLUE, 0.13))
	for row: int in range(L.GRID_ROWS):
		for col: int in range(L.GRID_COLUMNS):
			var cell := Vector2i(col,row)
			var owner: int = model.territory_owner(cell)
			if owner < 0: continue
			var r := Rect2(L.GRID_ORIGIN+Vector2(cell)*L.CELL_SIZE,L.CELL_SIZE)
			var color := Color(RED if owner == 0 else BLUE,0.65)
			for side: int in range(4):
				var delta: Vector2i = [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN][side]
				if model.territory_owner(cell+delta) == owner: continue
				var corners := [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]
				var edge: int = [3,0,1,2][side]
				ink_line(corners[edge],corners[(edge+1)%4],row*37+col*11+side,color,1.7)
	if selected >= 0:
		var sel_kind: String = model.kind_at(me,selected)
		var is_spell: bool = B.CARDS.get(sel_kind,{}).get("type","") == "spell"
		if not is_spell or B.CARDS[sel_kind].get("rolling",false):
			for row: int in range(5):
				for col: int in range(9):
					var cell := Vector2i(col,row)
					if model.can_play(me,selected,L.cell_center(cell)):
						var r := Rect2(L.GRID_ORIGIN+Vector2(cell)*L.CELL_SIZE,L.CELL_SIZE).grow(-5)
						var glow := 0.0 if place_flash <= 0 else 0.5+0.5*sin(place_flash*18)
						draw_rect(r,Color(1.0,0.93,0.55,0.22+0.30*glow))
						draw_rect(r,Color(0.85,0.65,0.15,0.7+0.3*glow),false,2+3*glow)
	for lane: int in range(6):
		if not lane in model.active_lanes and not lane-1 in model.active_lanes: continue
		var y := grid.position.y+lane*L.CELL_SIZE.y
		ink_line(Vector2(grid.position.x,y),Vector2(grid.end.x,y),lane,Color(INK,0.55 if lane == 0 or lane == 5 else 0.38),2.0)
	for lane: int in model.active_lanes:
		var tab := Rect2((grid.end.x-34) if mirror_view else (grid.position.x+4),grid.position.y+lane*L.CELL_SIZE.y+5,30,20)
		draw_rect(tab,Color(0.95,0.90,0.78,0.85))
		draw_rect(tab,Color(INK,0.5),false,1)
		field_text(tab.position+Vector2(0,15),ROMAN[model.active_lanes.find(lane)],HORIZONTAL_ALIGNMENT_CENTER,tab.size.x,14,INK)
	review.draw_pressure(self) # danger glow sits on the ground, under the troops
	for b: Dictionary in model.buildings:
		team_shadow(b.pos+Vector2(0,30),40,Color(0.25,0.17,0.08))
		draw_combat_actor(b.kind,b,b.pos,1.0 if b.team == 0 else -1.0)
		if b.hp < b.max_hp and not preload("res://glutton_nest.gd").hidden(b): bar(Rect2(b.pos-Vector2(30,43),Vector2(60,5)),b.hp,b.max_hp,RED if b.team == 0 else BLUE)
		# Farm progress toward the next gold drop; brighter while doubled (farmer or 豐收).
		if b.kind == "farm":
			var doubled: bool = maxf(b.boost_until,b.harvest_until) > model.elapsed
			bar(Rect2(b.pos+Vector2(-30,36),Vector2(60,5)),b.production,B.FARM_INTERVAL,Color("f2c230") if doubled else Color("c8962c"))
		elif b.kind == "grave":
			bar(Rect2(b.pos+Vector2(-30,36),Vector2(60,5)),b.production,B.CARDS.grave.period,Color("a885af"))
		elif b.kind == "crystal":
			bar(Rect2(b.pos+Vector2(-30,36),Vector2(60,5)),b.production,Arcane.crystal_period(b),Color("4fc3f7"))
		preload("res://faction_cards.gd").draw_bar(self,b)
		if fx_enabled and b.kind == "blood_tower": preload("res://blood_tower_fx.gd").tower(self,b)
		if b.boost_until > model.elapsed:
			tf(b.pos+Vector2(0,22),0,Vector2(1,0.38))
			draw_circle(Vector2.ZERO,46+3*sin(model.elapsed*4),Color(1.0,0.82,0.30,0.30))
			tf()
	draw_relations()
	for zone: Dictionary in model.zones:
		draw_circle(zone.pos,zone.radius,Color(0.35,0.42,0.19,0.20))
		draw_arc(zone.pos,zone.radius,0,TAU,40,Color(0.28,0.35,0.16,0.65),1.5,true)
		draw_fitted(art("plague"),Rect2(zone.pos-Vector2.ONE*zone.radius*0.65,Vector2.ONE*zone.radius*1.3),Color(1,1,1,0.42))
	preload("res://faction_cards.gd").draw(self)
	layout_formations()
	var ordered: Array = model.units.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.draw.y < b.draw.y)
	for u: Dictionary in ordered: draw_unit(u)
	preload("res://faction_cards.gd").draw_over(self)
	var pulse := 0.5+0.5*sin(model.elapsed*10.0)
	for lane: int in model.active_lanes:
		var y := L.cell_center(Vector2i(0,lane)).y
		for team: int in range(2):
			var x := L.gate_icon_x(team)
			var standing: bool = model.gates[team][lane] > 0
			draw_wall_section(team,lane,not standing)
			if standing and model.gates[team][lane] < B.GATE_HP:
				bar(Rect2(x-22,y+45,44,4),model.gates[team][lane],B.GATE_HP,RED if team == 0 else BLUE)
		var gx := L.gate_icon_x(0)
		if me != 0: continue
		if model.alarm[lane] > 0: draw_arc(Vector2(gx,y-8),40+4*pulse,0,TAU,28,Color(RED,0.5+0.4*pulse),3)
		elif model.building_alarm[lane] > 0: draw_arc(Vector2(gx,y-8),40,0,TAU,28,Color(0.85,0.6,0.1,0.7),2)
	for lord: Dictionary in model.lords: draw_lord(lord)
	for arrow: Dictionary in model.projectiles:
		if arrow.get("rolling",false):
			var stone_pos: Vector2 = arrow.pos-Vector2(0,32)
			tf(arrow.pos+Vector2(0,6),0,Vector2(1,0.25))
			draw_circle(Vector2.ZERO,37,Color(0.2,0.16,0.10,0.25))
			tf()
			for i: int in range(4):
				draw_circle(arrow.pos-Vector2(arrow.direction*(35+i*12),-4),6-i,Color(0.65,0.55,0.38,0.3-i*0.05))
			tf(stone_pos,arrow.angle)
			draw_texture_rect(art("rolling_boulder"),Rect2(-50,-50,100,100),false)
			tf()
		elif arrow.kind == "axe_thrower":
			tf(arrow.pos,(1-arrow.remaining/B.ARROW_TIME)*TAU*2*arrow.get("direction",1.0))
			draw_line(Vector2(-9,0),Vector2(9,0),Color("78512d"),3,true)
			draw_colored_polygon(PackedVector2Array([Vector2(3,-8),Vector2(12,-5),Vector2(12,5),Vector2(3,8)]),Color("a9a8a0"))
			draw_polyline(PackedVector2Array([Vector2(3,-8),Vector2(12,-5),Vector2(12,5),Vector2(3,8)]),INK,1.5,true)
			tf()
		elif arrow.has("impact"):
			var flight: float = clampf(1-arrow.remaining/arrow.flight,0,1)
			var shadow_pos: Vector2 = arrow.start.lerp(arrow.impact,flight)
			draw_circle(shadow_pos,5.0*flight,Color(0.2,0.16,0.10,0.35))
			draw_arc(arrow.impact,arrow.radius,0,TAU,24,Color(0.8,0.35,0.15,0.3+0.15*sin(model.elapsed*12)),1.5)
			var stone: Vector2 = arrow.pos-Vector2(0,sin(flight*PI)*65)
			var shell_c := Color("3d3835") if arrow.kind in ["funeral_grenadier","dog_cannon"] else Color("86745c")
			draw_circle(stone,6,shell_c)
			draw_arc(stone,6,0,TAU,12,INK,1.5,true)
			if arrow.kind in ["funeral_grenadier","dog_cannon"]:
				draw_circle(stone+Vector2(3,-5),2.5,Color("f6a636"))
		elif arrow.get("piercing",false) and arrow.kind == "long_dragon":
			# Fire breath: a widening tongue of flame from the mouth to the front of the blast.
			var mouth: Vector2 = arrow.start+Vector2(arrow.direction*40,8)
			var front: Vector2 = arrow.pos+Vector2(0,8)
			var flicker := sin(model.elapsed*40)*2
			draw_polygon(PackedVector2Array([mouth+Vector2(0,-3),front+Vector2(0,-10-flicker),front+Vector2(arrow.direction*8,0),front+Vector2(0,10+flicker),mouth+Vector2(0,3)]),PackedColorArray([Color(0.85,0.30,0.08,0.75)]))
			draw_polygon(PackedVector2Array([mouth,front+Vector2(-arrow.direction*6,-5),front,front+Vector2(-arrow.direction*6,5)]),PackedColorArray([Color(1.0,0.82,0.35,0.85)]))
		elif arrow.get("piercing",false):
			var tip: Vector2 = arrow.pos
			var tail := Vector2(arrow.direction*24,0)
			var beam := [Color("c4a75f",0.4),Color("e5c158"),Color("fff1b8")] if arrow.kind == "orrery_walker" else [Color("8966b8",0.35),Color("c5a4eb"),Color("ead7ff")]
			draw_line(tip-tail*1.6,tip,beam[0],5)
			draw_line(tip-tail,tip,beam[1],2)
			draw_polyline(PackedVector2Array([tip-Vector2(arrow.direction*6,4),tip,tip-Vector2(arrow.direction*6,-4)]),beam[2],2)
		elif arrow.kind == "dark_wizard":
			draw_line(arrow.pos-Vector2(18*arrow.get("direction",1.0),0),arrow.pos,Color(0.48,0.22,0.65,0.7),5,true)
			draw_circle(arrow.pos,6,Color("aa6bce"))
			draw_circle(arrow.pos,2.5,Color("f0deff"))
		elif arrow.get("curse_splash",false):
			draw_line(arrow.pos-Vector2(16*arrow.get("direction",1.0),0),arrow.pos,Color("4f6642",0.65),4,true)
			draw_circle(arrow.pos,5.5,Color("6c8a53"))
			draw_arc(arrow.pos,5.5,0,TAU,12,INK,1.4,true)
			draw_circle(arrow.pos,2.0,Color("d9e6b2"))
		else: draw_line(arrow.pos-Vector2(12*arrow.get("direction",1.0),0),arrow.pos,INK,2)
	draw_preview()
	draw_effects()
	DayCycle.light(self,L.FIELD_FRAME.grow(-7))
	field_mirror = false
	tf()
	draw_hud()
	Ceremony.intro(self)
	if net != null: draw_net_status()
	panel(library.INFO_RECT,Color("ecdcb6"))
	draw_string(font,library.INFO_RECT.position+Vector2(0,21),"戰局資料",HORIZONTAL_ALIGNMENT_CENTER,library.INFO_RECT.size.x,16,INK)
	draw_string(font,library.INFO_RECT.position+Vector2(0,39),["簡單","普通","困難"][model.difficulty],HORIZONTAL_ALIGNMENT_CENTER,library.INFO_RECT.size.x,13,Color("6f5a3e"))
	if model.ended and not model.time_stopped(): draw_result()
	elif model.paused:
		panel(L.OVERLAY_RECT,Color("efe0bd"))
		draw_string(font,L.OVERLAY_RECT.position+Vector2(0,58),"戰局暫停" if not model.ended else result_title(),HORIZONTAL_ALIGNMENT_CENTER,L.OVERLAY_RECT.size.x,30,INK)
		for item: Array in overlay_buttons():
			panel(item[0],Color("fbf1d8") if item[0].has_point(get_global_mouse_position()) else Color("f3e6c6"))
			draw_string(font,item[0].position+Vector2(0,27),item[1],HORIZONTAL_ALIGNMENT_CENTER,item[0].size.x,20,INK)

func result_title() -> String:
	return Ceremony.title(self)+"　"+Ceremony.story(self)

# The closing page: who won and how, with both sides' figures (battle_ceremony.gd).
func draw_result() -> void:
	Ceremony.result(self)

func result_value(team: int, key: String) -> float:
	if key == "breaches": return model.gates[1-team].filter(func(hp: float) -> bool: return hp <= 0).size()
	return float(model.stats[team].get(key,0))

# Ground under a soldier: a dark shadow with a ring in the team's colour, so sides read at a glance.
func team_base(center: Vector2, radius: float, color: Color) -> void:
	# A filled disc in the team colour (not just a thin ring): sides read at a glance even for
	# brown or white troops such as farmers, bandits, oxen, rams and skeletons.
	tf(center,0,Vector2(1,0.36))
	draw_circle(Vector2.ZERO,radius+2,Color(0.15,0.10,0.05,0.35))
	draw_circle(Vector2.ZERO,radius,Color(color,0.62))
	draw_circle(Vector2.ZERO,radius,Color(color.darkened(0.35),0.95),false,3.0)
	tf()

# The battlefield floor: tinted zones, alternating lane shade, grass and pebbles, darker edges.
func draw_ground(grid: Rect2) -> void:
	var cw: float = L.CELL_SIZE.x
	var ch: float = L.CELL_SIZE.y
	for lane: int in range(5):
		var row := Rect2(grid.position+Vector2(0,lane*ch),Vector2(grid.size.x,ch))
		if lane % 2 == 1: draw_rect(row,Color(0.25,0.16,0.06,0.06))
	# Irregular clumps rather than identical decorations in every grid cell.
	for i: int in range(175):
		var p := grid.position+Vector2(10+scenery_noise(i,11)*(grid.size.x-20),14+scenery_noise(i,12)*(grid.size.y-28))
		var lane_y := fposmod(p.y-grid.position.y,ch)
		if absf(lane_y-ch*0.5-25) < 14: continue # leave worn paths sparse
		var height := 3.5+scenery_noise(i,13)*6
		var shade := Color("4f683b") if i%3 == 0 else Color("c2cb8d")
		tuft(p,Color(shade,0.36),height)
		if i%4 == 0:
			tuft(p+Vector2(5,-2),Color(shade,0.30),height*0.65)
		if i%19 == 0:
			draw_circle(p-Vector2(0,height),1.5,Color(0.92,0.86,0.62,0.7))
		elif i%13 == 0:
			draw_line(p+Vector2(8,2),p+Vector2(12,1),Color(0.39,0.38,0.28,0.35),2,true)
	draw_texture_rect(vignette,L.FIELD_FRAME.grow(-4),false)

# Three ink strokes fanning up from one point: a grass tuft.
func tuft(base: Vector2, color: Color, height: float) -> void:
	for a: float in [-0.5,0.0,0.45]:
		draw_line(base,base+Vector2(sin(a)*height*0.8,-cos(a)*height),color,1.3,true)

func team_shadow(center: Vector2, radius: float, color: Color) -> void:
	tf(center,0,Vector2(1,0.32))
	draw_circle(Vector2.ZERO,radius,Color(color,0.45))
	tf()

func draw_unit(u: Dictionary) -> void:
	if u.hp <= 0: return
	var pos: Vector2 = u.draw-Vector2(u.face*4,0) if fx_enabled and u.flash > 0 else u.draw # small knockback on hit
	var bounce := sin(model.actor_time(u)*8+u.phase)*2
	if u.get("flying",false): bounce = -20+sin(model.actor_time(u)*10+u.phase)*5
	var top: float = actor_rect(u.kind).position.y+bounce
	var is_cursed: bool = u.get("cursed",false) or u.get("cursed_until",0.0) > model.elapsed
	if is_cursed: top = minf(top,-78)
	if u.hp < u.max_hp: top = minf(top,-69)
	pos.y = maxf(pos.y,L.GRID_ORIGIN.y-top+6)
	if u.get("stealthed",false):
		draw_arc(pos+Vector2(0,16),27,0,PI,16,Color("a8b5c7"),2)
	team_base(pos+Vector2(0,16),24,RED if u.team == 0 else BLUE)
	var tint := Color(1.6,1.6,1.6) if fx_enabled and u.flash > 0 else Color.WHITE
	if u.get("phased",false):
		draw_combat_actor(u.kind,u,pos+Vector2(-u.face*12,bounce),u.face,Color(0.65,0.55,1.0,0.16))
		tint = Color(0.8,0.75,1.0,0.5)
	draw_combat_actor(u.kind,u,pos+Vector2(0,bounce),u.face,tint)
	if B.CARDS[u.kind].has("resonance"):
		var strength: float = model.Arcane.resonance(model,u)/B.CARDS[u.kind].resonance_max
		var center := pos+Vector2(0,-32)
		draw_colored_polygon(PackedVector2Array([center+Vector2(0,-7),center+Vector2(5,0),center+Vector2(0,7),center+Vector2(-5,0)]),Color(0.55+0.4*strength,0.4+0.4*strength,0.8+0.2*strength,0.8))
	if model.LordExpansion.active(model,u):
		draw_arc(pos+Vector2(0,-30),25,0,TAU,24,Color(0.65,0.08,0.18,0.7),2)
		var left: float = (model.vampire_until[u.team]-model.elapsed)/B.LORDS.vampire.blood_duration
		draw_arc(pos+Vector2(0,16),25,-PI/2,-PI/2+TAU*left,24,Color("bd3d66"),2)
	if is_cursed:
		var halo_pos := pos-Vector2(0,50)
		draw_arc(halo_pos,12,0,TAU,20,Color("926c9d"),2,true)
		draw_circle(halo_pos,4,Color("5e3772"))
		for i: int in range(4):
			var a: float = model.elapsed*3.5+i*PI*0.5
			draw_circle(halo_pos+Vector2(cos(a),sin(a))*12,2,Color("c89fe0"))
	if u.get("inspired",false):
		var trail_c := Color(1.0,0.82,0.28,0.7)
		var dir: float = u.face
		draw_line(pos-Vector2(dir*16,10),pos-Vector2(dir*32,10),trail_c,2.0)
		draw_line(pos-Vector2(dir*12,22),pos-Vector2(dir*26,22),trail_c,1.5)
		var chev := pos+Vector2(0,top-6)
		draw_polyline(PackedVector2Array([chev-Vector2(dir*5,4),chev+Vector2(dir*3,0),chev-Vector2(dir*5,-4)]),trail_c,2.0)
		draw_arc(pos+Vector2(0,16),18+2*sin(model.elapsed*10),0,TAU,16,Color(1.0,0.85,0.3,0.35),1.5)
	if u.get("stun_left",0.0) > 0:
		var stun_pos := pos-Vector2(0,48)
		draw_polyline(PackedVector2Array([stun_pos+Vector2(-5,-7),stun_pos+Vector2(5,-7),stun_pos+Vector2(-5,7),stun_pos+Vector2(5,7),stun_pos+Vector2(-5,-7)]),Color("d8b9f3"),2)
		for i: int in range(3):
			var a: float = model.elapsed*6.0+i*TAU/3.0
			draw_circle(stun_pos+Vector2(cos(a)*10,sin(a)*4),2.5,Color("f6d354"))
	if u.get("slow_left",0.0) > 0:
		draw_arc(pos+Vector2(0,16),20,0,TAU,16,Color("64b5f6",0.6),1.5)
	if u.get("root_left",0.0) > 0:
		draw_arc(pos+Vector2(0,16),22,0,TAU,16,Color("3d2c3e",0.85),2.5)
		for i: int in range(4):
			var rp := pos+Vector2(0,16)+Vector2.from_angle(i*PI*0.5+PI*0.25)*22
			draw_line(rp,rp+Vector2(0,6),Color("3d2c3e",0.85),2.0)
	if u.get("hex_ticks",0) > 0:
		draw_arc(pos+Vector2(0,16),19,0,TAU,16,Color("6c8a53",0.75),2.0)
		for i: int in range(3):
			var ha: float = model.elapsed*4.0+i*TAU/3.0
			draw_circle(pos+Vector2(cos(ha)*11,-18-fmod(model.elapsed*16+i*6,14)),2.2,Color("8ba86b",0.8))
	if u.get("armor_until",0.0) > model.elapsed:
		draw_arc(pos+Vector2(0,16),21,0,PI,16,Color("c4a75f",0.85),2.5)
	if u.get("shroud_until",0.0) > model.elapsed:
		draw_circle(pos+Vector2(0,-20),24,Color("5e4b73",0.14))
		draw_arc(pos+Vector2(0,-20),24,0,TAU,24,Color("9f86c0",0.5),1.8)
	if u.get("borrowed_until",-1.0) >= 0:
		draw_arc(pos+Vector2(0,16),16,0,TAU,16,Color("b9a3d6",0.55),1.5)
	if u.hp < u.max_hp: bar(Rect2(pos-Vector2(24,68),Vector2(48,5)),u.hp,u.max_hp,RED if u.team == 0 else BLUE)

# Each lane renders a seamlessly tileable fortified stone curtain-wall section (or matching breach).
func draw_wall_section(team: int, lane: int, broken: bool) -> void:
	preload("res://wall_art.gd").section(self,team,lane,broken)

func draw_lord(lord: Dictionary) -> void:
	if lord.hp <= 0: return
	team_shadow(lord.pos+Vector2(0,24),30,Color(0.25,0.17,0.08))
	draw_arc(lord.pos+Vector2(0,24),30,0,TAU,32,Color(0.8,0.6,0.15,0.8),2) # gold ring marks the lords
	# The art faces right; the blue lord is mirrored so both lords face the enemy.
	draw_combat_actor("lord_"+lord.lord,lord,lord.pos,1.0 if lord.team == 0 else -1.0)
	if lord.hp < lord.max_hp: bar(Rect2(lord.pos-Vector2(30,72),Vector2(60,4)),lord.hp,lord.max_hp,RED if lord.team == 0 else BLUE)

func layout_formations() -> void:
	# Units may overlap (producer decision 2026-10-29). Each one keeps the small up/down offset it got
	# when it was placed, so a crowd still reads as several soldiers. Drawing only; combat uses `pos`.
	for u: Dictionary in model.units: u.draw = u.pos+Vector2(0,u.get("dy",0.0))

func draw_preview() -> void:
	if selected < 0: return
	var pos := field_mouse()
	var kind: String = model.kind_at(me,selected)
	var data: Dictionary = B.CARDS[kind]
	var color := Color(0.2,0.7,0.3,0.35) if model.can_play(me,selected,pos) else Color(0.8,0.1,0.1,0.35)
	if data.type == "spell":
		if data.get("rolling",false):
			var lane := clampi(floori((pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,4)
			var start := Vector2(Frontier.start_x(0),L.cell_center(Vector2i(0,lane)).y)
			var finish := Vector2(L.gate_stop(1),start.y)
			draw_line(start,finish,Color(0.8,0.3,0.1,0.18),data.radius*2)
			draw_line(start,finish,color,3)
			for actor: Dictionary in model.units+model.buildings+model.lords:
				if actor.hp > 0 and actor.team == me and (actor.pos.x-start.x)*(1.0 if me == 0 else -1.0) >= -data.radius and absf(actor.pos.y-start.y) <= data.radius:
					draw_arc(actor.pos,32,0,TAU,24,Color(1,0.15,0.1,0.85),3,true)
			draw_circle(start,data.radius,color,false,2)
			return
		draw_circle(pos,data.radius,color)
		return
	var cell: Vector2i = model.cell_at(pos)
	if cell.x < 0: return
	draw_card_art(kind,Rect2(L.cell_center(cell)-Vector2(45,40),Vector2(90,80)),0,Color(1,1,1,0.5))
	if data.type == "unit":
		if data.get("patrol",false):
			var left := cell.x
			var right := cell.x
			while left > 0 and model.territory_owner(Vector2i(left-1,cell.y)) == 0: left -= 1
			while right < L.GRID_COLUMNS-1 and model.territory_owner(Vector2i(right+1,cell.y)) == 0: right += 1
			var y: float = L.cell_center(cell).y
			draw_line(Vector2(L.GRID_ORIGIN.x+left*L.CELL_SIZE.x+12,y),Vector2(L.GRID_ORIGIN.x+(right+1)*L.CELL_SIZE.x-12,y),color,4)
			return
		var lanes: Array = [cell.y]
		if data.get("spread",false):
			var middle := clampi(cell.y,1,3)
			lanes = [middle-1,middle,middle+1]
		for lane: int in lanes:
			var col: int = model.deployment_column(me,lane,cell.x)
			if col >= 0: draw_line(L.cell_center(Vector2i(col,lane)),Vector2(L.gate_stop(1),L.cell_center(Vector2i(0,lane)).y),color,3)
		if kind == "farmer":
			for b: Dictionary in model.buildings:
				if b.kind == "farm" and b.team == me and b.cell.y == cell.y and (b.cell.x-cell.x)*(1 if me == 0 else -1) >= 0: draw_circle(b.pos,40,color,false,3)

# Colours of the cause-and-effect links (battle.gd link()): one family per relation.
const LINK_COLORS := {"repair":Color("c4a75f"),"soul":Color("b9a3d6"),"devour":Color("9b2f2f"),"summon":Color("7b4fa0"),"heal":Color("4f9a4a"),"harvest":Color("e2b23a"),"curse":Color("926c9d"),"mana":Color("4fc3f7"),"lightning":Color("cfe8ff")}

# A light travelling from cause to effect along a shallow arc, with a fading trail and a ring where
# it lands, so the player sees what fed what.
func draw_link(from: Vector2, to: Vector2, color: Color, progress: float) -> void:
	var lift := Vector2(0,-minf(40.0,from.distance_to(to)*0.25))
	var travel := clampf(progress/0.75,0.0,1.0)
	var points := PackedVector2Array()
	for i: int in range(13):
		var t := travel*i/12.0
		points.append(from.lerp(to,t)+lift*sin(t*PI))
	if points.size() > 1:
		draw_polyline(points,Color(color,0.25*(1-progress)),7.0,true) # soft glow
		draw_polyline(points,Color(color,0.75*(1-progress)),2.5,true)
	var head: Vector2 = points[points.size()-1]
	draw_circle(head,13.0,Color(color,0.30))
	draw_circle(head,7.0,Color(color,0.95*(1-progress*0.4)))
	draw_circle(head,3.0,Color(1,1,1,0.8*(1-progress)))
	if progress > 0.75: draw_arc(to,10+(progress-0.75)*80,0,TAU,24,Color(color,(1-progress)*3.0),2.0,true)

# Standing relations, drawn every frame: a mill's dashed gold line to the farms it boosts, and a
# scarecrow's dashed red line to the enemies it is pulling in.
func draw_relations() -> void:
	# Catapult aiming trajectory line
	for cat: Dictionary in model.units:
		if cat.hp <= 0 or cat.kind != "catapult" or cat.spawn_delay > 0: continue
		var target: Dictionary = model.catapult_target(cat)
		if not target.is_empty():
			dashed(cat.pos,target.pos,Color(0.85,0.50,0.20,0.45))
			draw_arc(target.pos,14,0,TAU,16,Color(0.85,0.50,0.20,0.55),1.5)
	# Buffed units already carry gold markers; avoid a web of field-wide lines.
	for b: Dictionary in model.buildings:
		if b.hp <= 0 or field_mouse().distance_to(b.pos) > 75: continue
		if b.kind == "mill":
			for farm: Dictionary in model.buildings:
				if farm.hp > 0 and farm.kind == "farm" and farm.team == b.team and farm.cell.y == b.cell.y: dashed(b.pos,farm.pos,Color("e2b23a",0.55))
		elif b.kind == "scarecrow":
			for u: Dictionary in model.units:
				if u.hp > 0 and u.team != b.team and is_same(model.taunting_scarecrow(u),b): dashed(b.pos,u.draw if u.has("draw") else u.pos,Color("b34a3a",0.5))

# The reaper's vertical slash: a curved blade stroke over the three lanes it hits.
func draw_slash(x: float, lane: int, progress: float, team: int) -> void:
	var top: float = L.GRID_ORIGIN.y+maxi(0,lane-1)*L.CELL_SIZE.y+8
	var bottom: float = L.GRID_ORIGIN.y+mini(5,lane+2)*L.CELL_SIZE.y-8
	var points := PackedVector2Array()
	for i: int in range(17):
		var t := i/16.0
		points.append(Vector2(x+sin(t*PI)*18.0*(1.0 if team == 0 else -1.0),lerpf(top,bottom,t)))
	draw_polyline(points,Color(0.85,0.85,0.95,0.35*(1-progress)),10.0,true)
	draw_polyline(points,Color(0.25,0.18,0.30,0.9*(1-progress)),3.0,true)

func dashed(a: Vector2, b: Vector2, color: Color) -> void:
	var length := a.distance_to(b)
	var d := 0.0
	while d < length:
		draw_line(a.lerp(b,d/length),a.lerp(b,minf(d+7.0,length)/length),color,1.6,true)
		d += 12.0

func draw_effects() -> void:
	if not fx_enabled: return
	for e: Dictionary in effects:
		var progress: float = 1-e.life/e.duration
		if FactionVisuals.event(self,e,progress): continue
		match e.kind:
			"hero_slash":
				var direction := 1.0 if e.team == 0 else -1.0
				var reach: float = e.length*minf(1.0,progress*4.0)
				var start: Vector2 = e.pos+Vector2(0,-20)
				var tip: Vector2 = start+Vector2(direction*reach,0)
				var glow := Color("e7bd62",(1-progress)*0.75)
				draw_colored_polygon(PackedVector2Array([start+Vector2(0,-e.width*0.35),tip,start+Vector2(0,e.width*0.35)]),Color(glow,glow.a*0.3))
				draw_line(start,tip,glow,12*(1-progress)+2,true)
				draw_line(start,tip,Color("fff1c0",1-progress),3,true)
				for i: int in range(3):
					var center := start+Vector2(direction*reach*(i+1)/3.0,0)
					draw_arc(center,20+progress*22,-1.1 if direction > 0 else PI-1.1,1.1 if direction > 0 else PI+1.1,18,glow,3,true)
			"teleport":
				if e.has("afterimage"): draw_actor(e.afterimage,e.team,e.pos,1.0 if e.team == 0 else -1.0,Color(0.7,0.5,1.0,(1-progress)*0.5))
				for p: Vector2 in [e.pos,e.to]: draw_arc(p,12+progress*30,0,TAU,32,Color(0.5,0.4,0.8,1-progress),3,true)
				dashed(e.pos,e.to,Color(0.5,0.4,0.8,(1-progress)*0.6))
			"arcane_impact":
				if e.get("clock",false):
					var clock_color := Color(0.8,0.65,1.0,1-progress)
					for hour in range(12):
						var direction := Vector2.from_angle(hour*TAU/12)
						draw_line(e.pos+direction*e.radius*.8,e.pos+direction*e.radius,clock_color,2)
					draw_line(e.pos,e.pos+Vector2.from_angle(progress*TAU)*e.radius*.6,clock_color,2)
				draw_line(e.from,e.pos,Color(0.55,0.55,0.9,1-progress),3,true)
				draw_arc(e.pos,e.radius*progress,0,TAU,32,Color(0.6,0.5,0.9,1-progress),3,true)
			"trap_blast":
				draw_arc(e.pos,e.radius*progress,0,TAU,32,Color(0.85,0.35,0.12,1-progress),4,true)
			"rune_summon":
				draw_arc(e.pos,20+progress*35,0,TAU,24,Color(0.65,0.45,0.9,1-progress),3)
				for i in range(6):
					var v := Vector2.from_angle(i*TAU/6)*30
					draw_line(e.pos+v*.7,e.pos+v,Color(0.8,0.65,1.0,1-progress),3)
			"soul_absorb":
				for i: int in range(3):
					var travel: float = clampf(progress*1.4-i*0.14,0,1)
					var mote: Vector2 = e.pos.lerp(e.to,travel)+Vector2(0,-sin(travel*PI)*24)
					draw_circle(mote,7-i,Color(0.65,0.38,0.85,1-progress))
					draw_circle(mote,3,Color(0.95,0.85,1.0,1-progress))
				draw_arc(e.to,10+progress*24,0,TAU,24,Color(0.7,0.4,0.9,1-progress),3,true)
			"blood_transfer": preload("res://blood_tower_fx.gd").transfer(self,e,progress)
			"blood_gain":
				draw_circle(e.pos+Vector2(0,-20-progress*25),3,Color(0.65,0.05,0.15,1-progress))
			"repair":
				draw_line(e.pos+Vector2(-6,-20-progress*15),e.pos+Vector2(6,-20-progress*15),Color(0.8,0.7,0.3,1-progress),3,true)
				draw_line(e.pos+Vector2(0,-26-progress*15),e.pos+Vector2(0,-14-progress*15),Color(0.8,0.7,0.3,1-progress),3,true)
			"roar":
				for i: int in range(3):
					var rr: float = e.radius*clampf(progress*1.2-i*0.15,0,1)
					if rr > 0: draw_arc(e.pos+Vector2(0,-20),rr,0,TAU,32,Color(0.75,0.25,0.12,(1-progress)*0.8),3.0-i*0.6,true)
			"drum":
				var r: float = progress*220.0
				draw_arc(e.pos,r,0,TAU,36,Color(1.0,0.82,0.28,(1-progress)*0.8),3.0,true)
				draw_arc(e.pos,r*0.65,0,TAU,28,Color(1.0,0.95,0.6,(1-progress)*0.5),2.0,true)
				for i in range(8):
					var ang: float = i*TAU/8.0+progress*0.5
					draw_line(e.pos+Vector2(cos(ang),sin(ang))*(r*0.75),e.pos+Vector2(cos(ang),sin(ang))*(r*1.05),Color(1.0,0.85,0.3,(1-progress)*0.7),2.0,true)
			"catapult_fire":
				draw_arc(e.pos,12+progress*24,0,TAU,20,Color(0.65,0.55,0.40,1-progress),2.0,true)
				for i in range(5):
					draw_circle(e.pos+Vector2((i-2)*6,-sin(progress*PI)*18-i*2),2.5*(1-progress),Color(0.5,0.4,0.3,1-progress))
			"curse_rise":
				draw_arc(e.pos,10+progress*36,0,TAU,24,Color("926c9d",1-progress),2.5,true)
				draw_circle(e.pos-Vector2(0,progress*28),5*(1-progress),Color("c89fe0",1-progress))
			"witch_curse":
				var wr: float = e.get("radius",75.0)*(0.3+progress*0.7)
				draw_circle(e.pos,wr,Color("5c7548",(1-progress)*0.18))
				draw_arc(e.pos,wr,0,TAU,28,Color("7b965f",(1-progress)*0.85),2.5,true)
				for i: int in range(6):
					var wa: float = i*TAU/6.0+progress*0.6
					draw_circle(e.pos+Vector2(cos(wa)*wr*0.68,sin(wa)*wr*0.28-progress*14),2.6*(1-progress),Color("a37fb8",1-progress))
			"stone_impact":
				draw_arc(e.pos,e.radius*progress,0,TAU,28,Color(0.40,0.30,0.18,1-progress),3,true)
				for i in range(8):
					var a: float = i*TAU/8.0
					draw_circle(e.pos+Vector2(cos(a),sin(a))*(progress*e.radius*0.8),3*(1-progress),Color(0.45,0.35,0.22,1-progress))
			"summoned", "boneburst": draw_arc(e.pos,12+progress*36,0,TAU,24,Color(0.55,0.38,0.60,1-progress),2,true)
			"skill": draw_skill_effect(e,progress)
			"levy_summon": FactionVisuals.summon(self,e.pos,progress)
			"levy_dust": FactionVisuals.dust(self,e.pos,progress)
			"link":
				if e.style == "lightning": FactionVisuals.lightning(self,e,progress)
				else: draw_link(e.pos,e.to,LINK_COLORS.get(e.style,INK),progress)
			"slash": draw_slash(e.pos.x,e.lane,progress,e.team)
			"ink": draw_circle(e.pos.lerp(to_model(Vector2(80,765) if e.team == me else Vector2(1322,35)),progress),7,Color("d9a62e"))
			"spell":
				if not FactionVisuals.spell(self,e,progress): draw_circle(e.pos,e.get("radius",50.0)*progress,Color(0.7,0.3,0.1,e.life*0.4))
			"cultivate", "hoe":
				for i: int in range(6): draw_circle(e.pos+Vector2((i-3)*8*progress,-sin(progress*PI)*28),3,Color("8a642c"))
			"play":
				var source := to_model(card_rect(e.get("slot",0)).get_center() if e.team == me else Vector2(1240,40))
				if progress < 0.6: draw_card_art(e.card,Rect2(source.lerp(e.pos,progress/0.6)-Vector2(35,30),Vector2(70,60)),e.team,Color(1,1,1,0.75))
				else: draw_circle(e.pos,(progress-0.6)*90,Color(0.2,0.15,0.1,(1-progress)*0.3))
			"death":
				var kind: String = e.get("art_kind",e.card)
				var death_pos: Vector2 = e.pos
				death_pos.y = maxf(death_pos.y,L.GRID_ORIGIN.y-actor_rect(kind).position.y+6)
				var face: float = e.get("face",1.0 if e.team == 0 else -1.0)
				if B.CARDS.has(kind) and B.CARDS[kind].type == "building": face = 1.0 if e.team == 0 else -1.0
				if adventure.is_opening() and e.team == 1 and kind == "bandit":
					draw_fitted_facing(adventure.opening.BANDIT,Rect2(death_pos-Vector2(43,73),Vector2(86,104)),-1.0,Color(1,1,1,1-progress))
				else: draw_actor(kind,e.team,death_pos,face,Color(1,1,1,1-progress))
				for i: int in range(5): draw_circle(e.pos+Vector2(cos(i*2),sin(i*2))*progress*24,3*(1-progress),INK)
			"burn":
				draw_circle(e.pos,35,Color(0.15,0.07,0.02,0.35*(1-progress)))
				if progress < 0.3:
					for i: int in range(5): draw_circle(e.pos+Vector2((i-2)*10,-15-10*sin(e.life*12+i)),8,Color(0.9,0.4,0.05,0.6))
			"breach":
				for i: int in range(8): draw_line(e.pos+Vector2(cos(i),sin(i))*progress*55,e.pos+Vector2(cos(i),sin(i))*progress*65,Color("6e4825"),3)
				# The whole lane flashes: red when it is our gate, gold when we broke theirs.
				var ours: bool = e.team == 1
				var flash := Color(RED if ours else Color("e0b02c"),(1-progress)*(0.22+0.16*sin(progress*40)))
				var lane_y: float = L.GRID_ORIGIN.y+e.lane*L.CELL_SIZE.y
				draw_rect(Rect2(L.FIELD_FRAME.position.x+6,lane_y,L.FIELD_FRAME.size.x-12,L.CELL_SIZE.y),flash)
				var gate := Vector2(L.gate_icon_x(0 if ours else 1),L.cell_center(Vector2i(0,e.lane)).y)
				for k: int in range(3): draw_arc(gate,30+fmod(progress*2+k/3.0,1.0)*110,0,TAU,40,Color(flash,(1-progress)*0.8),4)
			"ramp":
				var dial := L.CLOCK_FRAME.get_center()
				for k: int in range(3): draw_arc(dial,40+fmod(progress*1.5+k/3.0,1.0)*70,0,TAU,40,Color(0.88,0.69,0.17,(1-progress)*0.7),3)
			"nightfall": DayCycle.toll(self,e,progress)
			"heal": label_at(e.pos+Vector2(-10,-30-progress*20),"+",20,Color(0.2,0.5,0.25,1-progress))
			"fail":
				var c := Color(0.75,0.12,0.1,1-progress)
				draw_line(e.pos+Vector2(-14,-14),e.pos+Vector2(14,14),c,4)
				draw_line(e.pos+Vector2(-14,14),e.pos+Vector2(14,-14),c,4)
	for spell: Dictionary in model.spells:
		var height: float = spell.delay/B.SPELL_DELAY*160
		draw_texture_rect(art(spell.kind),Rect2(spell.pos-Vector2(22,30+height),Vector2(44,60)),false)

# Visual-only skill cues: positions were captured at cast time, no battle state is changed.
func draw_skill_effect(e: Dictionary, progress: float) -> void:
	var strength := sin(clampf(progress,0.0,1.0)*PI)
	var gold := Color(1.0,0.82,0.30,strength*0.85)
	var direction := 1.0 if e.team == 0 else -1.0
	for point: Vector2 in e.get("targets",[]):
		match e.lord:
			"lion", "underworld", "rune", "vampire", "beast":
				draw_circle(point+Vector2(0,-20),18+progress*30,Color(1.0,0.85,0.45,strength*0.22))
				draw_arc(point+Vector2(0,-20),14+progress*35,0,TAU,32,gold,2.0,true)
				var tip := point+Vector2(direction*(25+progress*100),-18)
				draw_line(tip-Vector2(direction*65,0),tip,gold,3.0,true)
				draw_line(tip-Vector2(direction*14,9),tip,gold,3.0,true)
				draw_line(tip-Vector2(direction*14,-9),tip,gold,3.0,true)
			"harvest":
				draw_circle(point,42,Color(1.0,0.76,0.20,strength*0.22))
				draw_arc(point,27+progress*18,0,TAU,32,gold,2.5,true)
				for i: int in range(5):
					var spark := point+Vector2((i-2)*14,-12-progress*36-sin(i*2.0)*9)
					draw_line(spark-Vector2(3,0),spark+Vector2(3,0),gold,2.0,true)
					draw_line(spark-Vector2(0,5),spark+Vector2(0,5),gold,2.0,true)
			"iron":
				var frame := Rect2(point-Vector2(33,38),Vector2(66,66))
				draw_rect(frame,Color(1.0,0.86,0.48,strength*0.20))
				draw_rect(frame,gold,false,3.0)
				for i: int in range(4):
					var y := point.y+25-progress*60-i*7
					draw_line(Vector2(point.x-24,y),Vector2(point.x+24,y),Color(gold,strength*(1.0-i*0.2)),2.0,true)

func draw_hud(single_lane: bool = false) -> void:
	# Lighter band and fainter diamonds: the red and blue team text needs the contrast.
	draw_rect(L.HUD_FRAME,Color("c4dbe7"))
	for x: int in range(48,1550,58):
		draw_polyline(PackedVector2Array([Vector2(x,24),Vector2(x+16,34),Vector2(x,44),Vector2(x-16,34),Vector2(x,24)]),Color(0.92,0.97,1,0.12),1.2,true)
	draw_texture_rect(PAPER,L.HUD_FRAME,false,Color(1,1,1,0.06))
	ink_frame(L.HUD_FRAME)
	if not single_lane:
		for team: int in range(2):
			var x := 95.0 if team == me else 1070.0
			draw_texture_rect(art("crest",team),Rect2(x-58,21,48,50),false)
			draw_texture_rect(ART.object_icon(0),Rect2(x+238,20,28,30),false)
			var standing: int = model.active_lanes.filter(func(lane: int) -> bool: return model.gates[team][lane] > 0).size()
			label_at(Vector2(x,43),("紅獅" if team == 0 else "藍旗")+"  城牆 %d / %d" % [standing,model.active_lanes.size()],23,RED if team == 0 else BLUE)
			for lane: int in model.active_lanes: bar(Rect2(x+model.active_lanes.find(lane)*70,53,62,10),model.gates[team][lane],B.GATE_HP,RED if team == 0 else BLUE)
			label_at(Vector2(x+270,43),"%d / 50" % model.ink[team],18)
	panel(Rect2(712,24,140,58),Color("f2e3c0"))
	var time := int(model.elapsed)
	label_at(Vector2(725,58),"%02d:%02d" % [time/60,time%60],30,RED if model.multiplier() > 1 else INK)
	# Faster income shows as coins beside the clock: one for x1.5, two for x2, three for the night's x3.
	var coins: int = 0 if model.multiplier() <= 1.0 else (1 if model.multiplier() < 2.0 else (2 if model.multiplier() < 3.0 else 3))
	for i: int in range(coins):
		draw_texture_rect(preload("res://economy_hud.gd").coin_texture(),Rect2(824,(49-coins*8)+i*16,20,20),false)
	if not single_lane: DayCycle.track(self)
	panel(L.PAUSE_RECT)
	label_at(L.PAUSE_RECT.position+Vector2(10,27),"Ⅱ",23)
	preload("res://command_style.gd").stone(self,L.COMMAND_FRAME)
	preload("res://economy_hud.gd").draw(self)
	if not single_lane: panel(LORD_PLATE,Color(0.92,0.86,0.72,0.92),Color("8a6f4a")) # plain backing for the lord text
	# Permanent farmland slot: green-washed frame and a "常駐" tag so it reads apart from the hand.
	var farm_rect := card_rect(Battle.FARM_SLOT)
	panel(farm_rect.grow(6),Color("cfdcae"),Color("3f5a2c"))
	var fr := farm_rect
	if selected == Battle.FARM_SLOT: fr.position.y -= 16
	elif hover_slot == Battle.FARM_SLOT: fr.position.y -= 8
	draw_card(model.kind_at(me,Battle.FARM_SLOT),fr,Battle.FARM_SLOT)
	var tag := Rect2(farm_rect.position.x+farm_rect.size.x/2-24,farm_rect.end.y-22,48,18)
	draw_rect(tag,Color("3f5a2c"))
	draw_string(font,tag.position+Vector2(0,14),"常駐",HORIZONTAL_ALIGNMENT_CENTER,tag.size.x,13,Color("efdfb9"))
	draw_line(Vector2(551,728),Vector2(551,888),Color(INK,0.35),2)
	for i: int in range(4):
		var r := card_rect(i)
		if i == selected: r.position.y -= 16
		elif i == hover_slot: r.position.y -= 8
		draw_card(model.decks[me][i],r,i)
	# Next card: smaller, faded, labelled.
	draw_line(Vector2(1093,728),Vector2(1093,888),Color(INK,0.35),2)
	draw_string(font,Vector2(NEXT_RECT.position.x,742),"下一張",HORIZONTAL_ALIGNMENT_CENTER,NEXT_RECT.size.x,15,INK)
	draw_card(model.decks[me][4],NEXT_RECT)
	# It cannot be played yet, so it recedes: a parchment wash keeps it readable but quiet.
	draw_rect(NEXT_RECT.grow(-3),Color(0.86,0.81,0.70,0.55))
	if spectating:
		for i: int in range(SPEEDS.size()):
			panel(SPEED_RECTS[i],Color("c9a96a") if speed == SPEEDS[i] else Color("e8d5ab"))
			draw_string(font,SPEED_RECTS[i].position+Vector2(0,25),"×%d" % SPEEDS[i],HORIZONTAL_ALIGNMENT_CENTER,SPEED_RECTS[i].size.x,18,INK)
	var mouse := get_global_mouse_position()
	if dragging and selected >= 0 and card_at(mouse) < 0 and model.cell_at(mouse).x < 0:
		draw_card_art(model.kind_at(me,selected),Rect2(mouse-Vector2(40,36),Vector2(80,72)),me,Color(1,1,1,0.7))
	if single_lane: return
	if spectating: label_at(Vector2(1220,766),"雙方領主",20)
	else: draw_skill_button()
	for lord: Dictionary in model.lords:
		var y: float = 814+lord.team*42
		var info: Dictionary = B.lord_data(lord.lord)
		var color: Color = RED if lord.team == 0 else BLUE
		label_at(Vector2(1220,y),"%s · %s" % ["紅" if lord.team == 0 else "藍",info.name],16,color)
		bar(Rect2(1220,y+8,170,6),lord.hp,lord.max_hp,color)
		label_at(Vector2(1400,y+14),"%d / %d" % [maxi(0,int(lord.hp)),int(lord.max_hp)],14)
		skill_mark(lord.team,Vector2(1500,y+6))

# Our lord's skill: Q or click. Lit when it can be cast; shows the cooldown otherwise.
func draw_skill_button() -> void:
	var info: Dictionary = B.LORDS[model.lords[me].lord]
	var ready: bool = model.skill_error(0).is_empty()
	panel(SKILL_RECT,Color("f2e3c0") if ready else Color("e3d2aa"),RED if ready else INK)
	if ready: draw_rect(SKILL_RECT.grow(2),RED,false,3)
	draw_rect(Rect2(SKILL_RECT.position+Vector2(8,10),Vector2(24,24)),Color("725138"))
	draw_string(font,SKILL_RECT.position+Vector2(8,28),"Q",HORIZONTAL_ALIGNMENT_CENTER,24,15,Color("efdfb9"))
	label_at(SKILL_RECT.position+Vector2(42,24),"領主技能：%s" % info.skill,17,RED if ready else INK)
	# Ready: a slow golden glow. Cooling: the same parting curtain as the cards. Otherwise greyed.
	if ready:
		var glow := 0.5+0.5*sin(Time.get_ticks_msec()/260.0)
		draw_rect(SKILL_RECT.grow(4+glow*2),Color(0.95,0.75,0.25,0.25+0.35*glow),false,3)
	elif model.skill_cd[me] > 0: curtain(SKILL_RECT.grow(-2),clampf(model.skill_cd[me]/B.skill_cooldown(model.lords[me].lord),0,1))
	else: draw_rect(SKILL_RECT.grow(-2),Color(0.40,0.40,0.40,0.35))

# A lord row's skill state as a small mark, no words: a glowing gem when it can be cast, a dial
# filling up while it cools, a dull coin when gold is short, an empty ring when the lord is down.
func skill_mark(team: int, at: Vector2) -> void:
	var state := skill_state_text(team)
	var color: Color = RED if team == 0 else BLUE
	match state:
		"可發動":
			var glow := 0.5+0.5*sin(Time.get_ticks_msec()/260.0)
			draw_circle(at,10+glow*2,Color(0.95,0.75,0.25,0.35))
			draw_circle(at,7,color.lightened(0.25))
			draw_arc(at,7,0,TAU,16,Color("e8c25a"),2,true)
		"冷卻中":
			var done := 1.0-clampf(model.skill_cd[team]/B.skill_cooldown(model.lords[team].lord),0,1)
			draw_circle(at,8,Color(0.30,0.30,0.31,0.8))
			if done > 0: draw_colored_polygon(PackedVector2Array([at]+range(25).map(func(i: int) -> Vector2: return at+Vector2.from_angle(-PI/2+TAU*done*i/24.0)*8)),Color(color,0.85))
		"金幣不足":
			draw_texture_rect(preload("res://economy_hud.gd").coin_texture(),Rect2(at-Vector2(9,9),Vector2(18,18)),false,Color(0.45,0.45,0.45,0.8))
		_:
			draw_arc(at,7,0,TAU,16,Color(0.35,0.35,0.35,0.8),2,true)

# The skill's state in words only (producer 2026-11-03: no countdowns or gold numbers on screen).
# Hovering the button lights the coins it costs in the purse.
func skill_state_text(team: int) -> String:
	var lord: Dictionary = model.lords[team]
	if not B.has_skill(lord.lord): return "沒有技能"
	if lord.hp <= 0: return "領主倒下中"
	if model.skill_cd[team] > 0: return "冷卻中"
	if lord.lord == "underworld" and model.count_buildings(team,"grave") == 0: return "沒有墓碑"
	if model.ink[team] < B.skill_cost(lord.lord): return "金幣不足"
	return "可發動"

func try_skill() -> bool:
	if adventure.is_opening() and adventure.opening.active: return false
	var reason: String = model.skill_error(me)
	if reason.is_empty() and net != null:
		net.queue(["s"])
		return true
	if reason.is_empty() and model.cast_skill(me): return true
	say(reason)
	skill_shake = 0.45
	if model.skill_cd[me] <= 0 and model.ink[me] < B.skill_cost(model.lords[me].lord):
		purse_alarm = 0.9
		purse_need = B.skill_cost(model.lords[me].lord)
	if sound != null: sound.cue("fail")
	return false


func leave_net() -> void:
	if net != null: net.close()
	net = null
	me = 0
	mirror_view = false
	field_mirror = false

# Lobby: host (show my addresses) or join an address. Uses the saved deck and lord.
func show_net() -> void:
	if not DeckStore.valid(player_deck,player_lord):
		show_deck()
		return
	if net == null: net = NetMatch.new()
	screen = "net"
	clear_ui()
	button(Rect2(300,330,300,56),"開房（我當紅方）",func():
		net.host(player_deck,player_lord)
		show_net())
	var edit := LineEdit.new()
	edit.position = Vector2(820,330)
	edit.size = Vector2(300,56)
	edit.text = net_ip
	edit.add_theme_font_override("font",font)
	edit.add_theme_font_size_override("font_size",22)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("f6ead0")
	box.border_color = Color("846539")
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	edit.add_theme_stylebox_override("normal",box)
	edit.add_theme_stylebox_override("focus",box)
	edit.add_theme_color_override("font_color",INK)
	edit.text_changed.connect(func(t: String): net_ip = t)
	add_child(edit)
	ui.append(edit)
	button(Rect2(1140,330,160,56),"加入",func():
		net.join(net_ip,player_deck,player_lord)
		show_net())
	button(Rect2(120,805,220,50),"回到標題",show_title)
	button(Rect2(370,805,220,50),"更換牌組",func():
		leave_net()
		show_deck())
	queue_redraw()

func draw_net() -> void:
	label_at(Vector2(120,110),"連線對戰",48)
	label_at(Vector2(120,160),"雙方各用自己存好的牌組與領主。一方開房，另一方輸入開房者的 IP 加入。",20,Color("5a4a36"))
	label_at(Vector2(120,190),"同一個 Wi-Fi 直接可連；跨網路需開房方的路由器轉發連接埠 %d，或用 Radmin VPN、ZeroTier 等虛擬區網。" % NetMatch.PORT,17,Color("6f5a3e"))
	panel(Rect2(260,250,380,180))
	label_at(Vector2(290,300),"開房",28)
	panel(Rect2(780,250,560,180))
	label_at(Vector2(810,300),"加入：輸入對方 IP",28)
	label_at(Vector2(120,500),"我的牌組：%s · %s" % [B.LORDS[player_lord].name,"、".join(player_deck.map(func(k): return B.CARDS[k].name))],20)
	var y := 560.0
	if net != null and net.state == "hosting":
		label_at(Vector2(120,y),"已開房，請對方輸入以下任一個 IP：",22,RED)
		for ip: String in net.local_ips():
			y += 34
			label_at(Vector2(150,y),ip,26)
	if net != null and not net.message.is_empty():
		label_at(Vector2(120,y+60),net.message,22,RED if net.state in ["error","lost"] else INK)

func start_net_battle() -> void:
	me = net.local_team
	mirror_view = me == 1
	spectating = false
	adventure.index = -1
	model = net.make_battle()
	enter_battle("連線對戰")

# Waiting for the peer, peer lost, or the two simulations disagree.
func draw_net_status() -> void:
	var text := ""
	if net.state == "lost": text = "對手已離線"
	elif net.desync: text = "警告：雙方戰況不同步（版本或設定可能不同）"
	elif net.state == "playing" and net.stalled_for > 0.5 and not model.ended: text = "等待對手…"
	if text.is_empty(): return
	panel(Rect2(560,104,480,44),Color("efe0bd"))
	draw_string(font,Vector2(560,134),text,HORIZONTAL_ALIGNMENT_CENTER,480,22,RED)

func show_title() -> void:
	leave_net()
	rogue.in_battle = false
	adventure_deck_mode = false
	screen = "title"
	clear_ui()
	preload("res://main_menu.gd").build(self)
	queue_redraw()

# Title controls have their own parchment / vermilion states and keyboard focus.
func title_button(rect: Rect2, caption: String, action: Callable, primary: bool = false) -> Button:
	var control := button(rect,caption,action)
	control.focus_mode = Control.FOCUS_ALL
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.add_theme_font_size_override("font_size",28 if primary else 21)
	for state: String in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("963f30") if primary else Color("e8d6af")
		if state == "hover": style.bg_color = Color("b1533b") if primary else Color("f6e8c9")
		if state == "pressed": style.bg_color = Color("733426") if primary else Color("cdb88f")
		if state == "focus": style.bg_color = Color.TRANSPARENT
		style.border_color = Color("d2ad58") if primary or state == "focus" else Color("92734b")
		style.set_border_width_all(3 if state == "focus" else 2)
		style.set_corner_radius_all(2)
		control.add_theme_stylebox_override(state,style)
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		control.add_theme_color_override(state,Color("fff0ca") if primary else INK)
	return control

# The blue castle faces the red one: draw it flipped left-right inside the same rect.
const CASTLE_SHADE := Color(0.80,0.78,0.74)
func draw_mirrored(tex: Texture2D, r: Rect2, shade: Color = Color.WHITE) -> void:
	tf(Vector2(2*r.position.x+r.size.x,0),0,Vector2(-1,1))
	draw_texture_rect(tex,r,false,shade)
	tf()

func draw_title() -> void:
	preload("res://main_menu.gd").paint(self)

func title_soldier(kind: String, pos: Vector2, team: int, size_scale: float) -> void:
	ground_wash(pos+Vector2(0,14),Vector2(25*size_scale,7*size_scale),Color("3f442e"),int(pos.x),0.13)
	var facing := 1.0 if team == 0 else -1.0
	# Marching on the spot: each soldier steps to its own beat.
	var step := sin(clock*6.0+pos.x*0.05+pos.y*0.03) if fx_enabled else 0.0
	tf(pos+Vector2(0,-absf(step)*3.0),(-0.09+0.025*step)*facing,Vector2(facing,1)*size_scale)
	draw_texture_rect(art(kind,team),actor_rect(kind),false)
	tf()
	for i: int in range(2):
		var dash := 15.0+5.0*sin(clock*5.0+i*1.3+pos.x*0.02) if fx_enabled else 15.0
		draw_line(pos+Vector2(-facing*(32+i*8),-8+i*9),pos+Vector2(-facing*(32+dash+i*8),-8+i*9),Color(INK,0.3),1.4,true)

func show_deck() -> void:
	screen = "deck"
	clear_ui()
	if not deck_tab in deck_tabs(): deck_tab = "all"
	var tabs := deck_tabs()
	for i: int in range(tabs.size()):
		var tab: String = tabs[i]
		var t := button(tab_rect(i),"",func(): deck_tab = tab; deck_page = 0; show_deck())
		t.modulate = Color(1,1,1,0.01)
	var pages := ceili(tab_size()/float(POOL_PAGE))
	deck_page = clampi(deck_page,0,maxi(0,pages-1))
	if pages > 1:
		button(Rect2(POOL_X-70,POOL_Y+110,50,120),"‹",func(): deck_page = (deck_page+pages-1)%pages; show_deck())
		button(Rect2(POOL_X+8*POOL_STEP.x,POOL_Y+110,50,120),"›",func(): deck_page = (deck_page+1)%pages; show_deck())
	var items := page_items()
	for i: int in range(items.size()):
		var kind: String = items[i]
		var b: Button
		if deck_tab == "lord":
			b = button(pool_rect(i,items.size()),"",func(): choose_lord(kind))
			b.tooltip_text = lord_tooltip(kind)
		else:
			b = button(pool_rect(i,items.size()),"",func(): toggle_deck_card(kind))
			b.tooltip_text = card_description(kind)
		b.modulate = Color(1,1,1,0.01)
	# Cards in the deck frame: click one to take it out again.
	var shown: Array = B.menu_sorted(player_deck)
	for i: int in range(shown.size()):
		var kind: String = shown[i]
		var b := button(deck_slot_rect(i+1),"",func(): toggle_deck_card(kind))
		b.tooltip_text = card_description(kind)
		b.modulate = Color(1,1,1,0.01)
	if "lord" in deck_tabs():
		var p := button(PORTRAIT,"",func(): deck_tab = "lord"; deck_page = 0; show_deck())
		p.tooltip_text = lord_tooltip(player_lord)
		p.modulate = Color(1,1,1,0.01)
	if adventure_deck_mode:
		button(Rect2(120,820,220,50),"返回地圖",func():
			if DeckStore.valid(player_deck,player_lord):
				adventure.custom_deck = player_deck.duplicate()
				adventure.save_progress()
			adventure_deck_mode = false
			show_adventure()
		)
		start_button = button(Rect2(1260,820,240,50),"儲存並出征",func():
			adventure.custom_deck = player_deck.duplicate()
			adventure.save_progress()
			adventure_deck_mode = false
			spectating = false
			adventure.start(self,adventure.selected)
		)
	elif watch_edit >= 0:
		button(Rect2(120,820,220,50),"取消",func(): finish_watch_edit(false))
		start_button = button(Rect2(1260,820,240,50),"完成",func(): finish_watch_edit(true))
	else:
		button(Rect2(120,820,220,50),"回到標題",show_title)
		start_button = button(Rect2(1260,820,240,50),"儲存並開戰",func(): spectating = false; start_battle())
	start_button.disabled = not DeckStore.valid(player_deck,player_lord)
	queue_redraw()

# Deck screen (producer 2026-11-05, "army" layout): a frame on top with the lord portrait and the
# deck (home card + 8 slots), a tab bar, then the collection in two rows of eight.
const ARMY := Rect2(50,28,1500,300)
const PORTRAIT := Rect2(72,46,196,212)
const SLOT_X := 300.0
const SLOT_Y := 116.0
const SLOT_SIZE := Vector2(128,162)
const SLOT_STEP := 136.0
const TAB_Y := 342.0
const TAB_W := 176.0
const POOL_X := 211.0
const POOL_Y := 410.0
const POOL_STEP := Vector2(150,178)
const POOL_CARD := Vector2(128,162)
const POOL_PAGE := 16
const TAB_NAMES := {"all":"全部","melee":"近戰","ranged":"遠程","spell":"法術","building":"建築","lord":"領主"}
const TAB_GROUP := {"melee":0,"ranged":1,"spell":2,"building":3}

func deck_tabs() -> Array:
	var tabs := ["all","melee","ranged","spell","building"]
	if not adventure_deck_mode or adventure.unlocked_lords().size() > 1: tabs.append("lord")
	return tabs

func tab_rect(i: int) -> Rect2:
	var n := deck_tabs().size()
	return Rect2(800-n*TAB_W/2+i*TAB_W,TAB_Y,TAB_W-8,48)

func deck_slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(SLOT_X+i*SLOT_STEP,SLOT_Y),SLOT_SIZE)

# Every tab lists melee, ranged, spells, then buildings (cheaper first inside a group).
func tab_items(tab: String) -> Array:
	if tab == "lord": return adventure.unlocked_lords() if adventure_deck_mode else B.lord_menu_order()
	var pool: Array = adventure.card_pool() if adventure_deck_mode else DeckStore.pool(player_lord)
	var kinds: Array = B.CARDS.keys().filter(func(kind: String) -> bool:
		if not kind in pool: return false
		if tab == "all": return true
		if TAB_GROUP.has(tab): return B.card_group(kind) == TAB_GROUP[tab]
		return B.CARDS[kind].type == tab) # "unit" etc. from older tools
	return B.menu_sorted(kinds)

func page_items() -> Array:
	return tab_items(deck_tab).slice(deck_page*POOL_PAGE,(deck_page+1)*POOL_PAGE)

func tab_size() -> int:
	return tab_count(deck_tab)

func tab_count(tab: String) -> int:
	return tab_items(tab).size()

func lord_tooltip(kind: String) -> String:
	var info: Dictionary = B.LORDS[kind]
	return "%s（%s）\n%d 血 · 普攻 %d\n%s" % [info.name,info.role,int(info.hp),int(info.damage),B.skill_text(kind)]

# Lords are picked from the 領主 tab, in the same grid as the cards.
func lord_rect(index: int) -> Rect2:
	return pool_rect(index,B.LORDS.size())

func save_choice() -> void:
	if watch_edit >= 0: return # a spectate side, not the player's deck
	if adventure_deck_mode:
		if DeckStore.valid(player_deck,player_lord):
			adventure.custom_deck = player_deck.duplicate()
			adventure.save_progress()
	else:
		if DeckStore.valid(player_deck,player_lord):
			DeckStore.save_deck(player_deck,deck_path,player_lord)

# Collection grid: two rows of eight, centred.
func pool_rect(index: int, _count: int = 0) -> Rect2:
	var i := index%POOL_PAGE
	return Rect2(Vector2(POOL_X+(i%8)*POOL_STEP.x,POOL_Y+(i/8)*POOL_STEP.y),POOL_CARD)

# Switching lords keeps the deck but swaps out cards of the other faction.
func choose_lord(lord: String) -> void:
	if adventure_deck_mode: # each adventure lord keeps its own deck
		save_choice()
		adventure.choose_lord(lord)
		adventure.open_adventure_deck(self)
		return
	var fitted: Array = DeckStore.fit_to_lord(player_deck,lord)
	if fitted != player_deck: menu_notice = "已換掉%s不能用的卡牌。" % B.LORDS[lord].name
	player_lord = lord
	player_deck = fitted
	save_choice()
	show_deck()

func toggle_deck_card(kind: String) -> void:
	menu_notice = ""
	if kind in player_deck: player_deck.erase(kind)
	elif player_deck.size() < 8: player_deck.append(kind)
	else: menu_notice = "牌組已滿，先點上方牌組裡的一張卡移除。"
	save_choice()
	show_deck()

func draw_check(at: Vector2) -> void:
	draw_circle(at,13,RED)
	draw_arc(at,13,0,TAU,24,Color(1,0.95,0.85),2,true)
	draw_polyline(PackedVector2Array([at+Vector2(-6,0),at+Vector2(-1,5),at+Vector2(7,-5)]),Color.WHITE,3,true)

func draw_lord_card(kind: String, r: Rect2, chosen: bool) -> void:
	var info: Dictionary = B.LORDS[kind]
	var tint: Color = preload("res://command_style.gd").TINTS.get(B.lord_faction(kind),Color("efe3c8"))
	panel(r,tint.lerp(Color.WHITE,0.55 if chosen else 0.25),RED if chosen else Color("8a6f4a"))
	draw_fitted(lord_art(kind),Rect2(r.position+Vector2(8,24),Vector2(r.size.x-16,r.size.y-86)),Color.WHITE,true)
	draw_string(font,Vector2(r.position.x,r.end.y-44),info.name,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,17,INK)
	draw_string(font,Vector2(r.position.x,r.end.y-27),info.role,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,13,Color("5a4a36"))
	draw_string(font,Vector2(r.position.x,r.end.y-10),"%s %d" % [info.skill,int(B.skill_cost(kind))],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,12,RED)
	var faction: String = B.lord_faction(kind)
	var tag := Rect2(r.position+Vector2(6,6),Vector2(36,17))
	draw_rect(tag,preload("res://command_style.gd").TAGS.get(faction,Color("7d7466")))
	draw_string(font,tag.position+Vector2(0,13),B.FACTIONS[faction],HORIZONTAL_ALIGNMENT_CENTER,tag.size.x,12,Color("f3e6c4"))
	if chosen:
		draw_rect(r.grow(3),RED,false,4)
		draw_check(r.position+Vector2(r.size.x-10,10))

func draw_deck() -> void:
	var muted := Color("5a4a36")
	# Army frame.
	panel(ARMY,Color("e6d3a8"),Color("6a5236"))
	draw_rect(ARMY.grow(-6),Color("8a6f4a"),false,1)
	var lord: String = player_lord
	var info: Dictionary = B.LORDS[lord]
	panel(PORTRAIT,Color("f6e9c8"),RED)
	draw_fitted(lord_art(lord,maxi(watch_edit,0)),PORTRAIT.grow(-10),Color.WHITE,true)
	draw_string(font,Vector2(PORTRAIT.position.x,PORTRAIT.end.y+28),info.name,HORIZONTAL_ALIGNMENT_CENTER,PORTRAIT.size.x,22,INK)
	draw_string(font,Vector2(PORTRAIT.position.x,PORTRAIT.end.y+50),"%s · 點頭像換領主" % info.role if "lord" in deck_tabs() else "%s · 征服首府可換領主" % info.role,HORIZONTAL_ALIGNMENT_CENTER,PORTRAIT.size.x,13,muted)
	var title := "出征牌組" if adventure_deck_mode else "村莊牌組"
	if watch_edit >= 0: title = "觀戰 · 紅方牌組" if watch_edit == 0 else "觀戰 · 藍方牌組"
	label_at(Vector2(SLOT_X,80),title,30,INK if watch_edit < 0 else (RED if watch_edit == 0 else BLUE))
	var tx: float = SLOT_X+font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,30).x+18
	label_at(Vector2(tx,78),"%d / 8 · 平均 %.1f 金幣" % [player_deck.size(),DeckStore.average(player_deck)],20,RED if player_deck.size() < 8 else muted)
	label_at(Vector2(SLOT_X,104),B.skill_text(lord),14,muted)
	# Home card (fixed) + eight slots.
	var home := deck_slot_rect(0)
	panel(home.grow(4),Color("cfdcae"),Color("3f5a2c"))
	draw_card(B.home_card(lord),home)
	draw_string(font,Vector2(home.position.x,home.end.y+22),"常駐",HORIZONTAL_ALIGNMENT_CENTER,home.size.x,14,Color("3f5a2c"))
	var shown: Array = B.menu_sorted(player_deck)
	for i: int in range(8):
		var r := deck_slot_rect(i+1)
		if i < shown.size():
			draw_card(shown[i],r)
		else:
			draw_rect(r,Color(0.35,0.27,0.16,0.12))
			draw_rect(r.grow(-4),Color(0.42,0.32,0.2,0.45),false,2)
			draw_string(font,Vector2(r.position.x,r.get_center().y+12),"+",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,36,Color(0.42,0.32,0.2,0.5))
	# Tab bar.
	var tabs := deck_tabs()
	var bar := Rect2(tab_rect(0).position-Vector2(8,6),Vector2(tabs.size()*TAB_W+8,60))
	panel(bar,Color("c9b083"),Color("6a5236"))
	for i: int in range(tabs.size()):
		var r := tab_rect(i)
		var on: bool = tabs[i] == deck_tab
		draw_rect(r,RED if on else Color("e6d3a8"))
		draw_rect(r,Color("6a5236"),false,1.5)
		draw_string(font,Vector2(r.position.x,r.position.y+33),"%s（%d）" % [TAB_NAMES[tabs[i]],tab_count(tabs[i])],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,19,Color("fbf1dc") if on else INK)
	# Collection.
	var items := page_items()
	for i: int in range(items.size()):
		var r := pool_rect(i)
		if deck_tab == "lord":
			draw_lord_card(items[i],r,items[i] == player_lord)
			continue
		draw_card(items[i],r)
		if items[i] in player_deck:
			draw_rect(r,Color(0.25,0.18,0.10,0.35))
			draw_rect(r.grow(3),RED,false,4)
			draw_check(Vector2(r.get_center().x,r.end.y))
	var pages := ceili(tab_size()/float(POOL_PAGE))
	if pages > 1:
		for p: int in range(pages):
			draw_circle(Vector2(800+(p-(pages-1)/2.0)*20,POOL_Y+2*POOL_STEP.y+4),6 if p == deck_page else 4,RED if p == deck_page else Color(INK,0.35))
	# Status line between the two bottom buttons.
	var note := menu_notice
	if note.is_empty() and not DeckStore.valid(player_deck,player_lord): note = "還差 %d 張才能%s" % [8-player_deck.size(),"出征" if adventure_deck_mode else "開戰"]
	if not note.is_empty(): draw_string(font,Vector2(360,853),note,HORIZONTAL_ALIGNMENT_CENTER,880,20,RED)
	elif watch_edit >= 0: draw_string(font,Vector2(360,853),"只改這場觀戰，不影響你的牌組",HORIZONTAL_ALIGNMENT_CENTER,880,18,muted)

# Random spectate deck (rules live in DeckStore so the balance tools share them).
static func random_deck(rng: RandomNumberGenerator, lord: String = "") -> Array:
	return DeckStore.random_deck(rng,lord)

func set_watch_source(team: int, source: int) -> void:
	watch_source[team] = source
	if source == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		watch_lords[team] = B.LORDS.keys()[rng.randi_range(0,B.LORDS.size()-1)]
		watch_decks[team] = random_deck(rng,watch_lords[team])
	else:
		watch_lords[team] = player_lord
		watch_decks[team] = player_deck.duplicate() if DeckStore.valid(player_deck,player_lord) else DeckStore.fit_to_lord(B.DEFAULT_DECK,player_lord)

# Spectate side editing reuses the deck screen on that side's deck and lord.
func edit_watch_side(team: int) -> void:
	watch_stash = {"deck":player_deck.duplicate(),"lord":player_lord,"tab":deck_tab}
	player_deck = watch_decks[team].duplicate()
	player_lord = watch_lords[team]
	watch_edit = team
	menu_notice = ""
	deck_tab = "all"
	deck_page = 0
	show_deck()

func finish_watch_edit(keep: bool) -> void:
	if keep and DeckStore.valid(player_deck,player_lord):
		watch_decks[watch_edit] = player_deck.duplicate()
		watch_lords[watch_edit] = player_lord
		watch_source[watch_edit] = -1
	player_deck = watch_stash.deck
	player_lord = watch_stash.lord
	deck_tab = watch_stash.tab
	watch_edit = -1
	menu_notice = ""
	show_watch()

# Clicking a card swaps it for the next card (in pool order) that this side doesn't hold yet (kept for tools).
func cycle_watch_card(team: int, index: int) -> void:
	var pool: Array = DeckStore.pool(watch_lords[team])
	var at: int = pool.find(watch_decks[team][index])
	for step: int in range(1,pool.size()):
		var next: String = pool[(at+step)%pool.size()]
		if not next in watch_decks[team]:
			watch_decks[team][index] = next
			break
	watch_source[team] = -1
	show_watch()

# Spectate setup (producer 2026-11-05): the deck screen's "army" frame, one per side —
# header with the deck source, a row of lord chips, then the lord portrait and two rows of four cards.
func watch_x(team: int) -> float:
	return 40.0+team*780.0

func watch_army(team: int) -> Rect2:
	return Rect2(watch_x(team),282,740,372)

func watch_portrait(team: int) -> Rect2:
	return Rect2(watch_x(team)+18,300,178,250)

func watch_card_rect(team: int, index: int) -> Rect2:
	return Rect2(watch_x(team)+214+(index%4)*130,300+(index/4)*170,120,152)

func watch_lord_rect(team: int, index: int) -> Rect2:
	var step: float = 740.0/maxi(8,B.LORDS.size()) # the row is as wide as the army frame below it
	return Rect2(watch_x(team)+index*step,170,step-6.5,100)

func show_watch() -> void:
	screen = "watch"
	clear_ui()
	for team: int in range(2):
		if watch_decks[team].is_empty(): set_watch_source(team,0)
		var side := team
		var x := watch_x(team)
		var source: int = watch_source[team]
		button(Rect2(x+352,108,220,46),"牌組：%s ▸" % ("自訂" if source < 0 else WATCH_SOURCES[source]),func(): set_watch_source(side,(maxi(source,0)+1)%WATCH_SOURCES.size()); show_watch())
		button(Rect2(x+582,108,158,46),"重新隨機",func(): set_watch_source(side,0); show_watch())
		var index := 0
		for lord_kind: String in B.lord_menu_order():
			var choice := lord_kind
			var b := button(watch_lord_rect(team,index),"",func(): watch_lords[side] = choice; watch_decks[side] = DeckStore.fit_to_lord(watch_decks[side],choice); show_watch())
			b.tooltip_text = lord_tooltip(lord_kind)
			b.modulate = Color(1,1,1,0.01)
			index += 1
		var edit := button(watch_army(team),"",func(): edit_watch_side(side))
		edit.tooltip_text = "點一下編輯這一方的牌組"
		edit.modulate = Color(1,1,1,0.01)
	button(Rect2(120,805,220,50),"回到標題",show_title)
	button(Rect2(690,805,220,50),"互換雙方",swap_watch)
	button(Rect2(1260,805,220,50),"開始觀戰",func(): spectating = true; start_battle())
	queue_redraw()

func swap_watch() -> void:
	watch_decks.reverse()
	watch_lords.reverse()
	watch_source.reverse()
	show_watch()

func draw_watch() -> void:
	var muted := Color("5a4a36")
	label_at(Vector2(60,78),"觀戰設定",40)
	label_at(Vector2(260,74),"點領主頭像更換 · 點牌組進入編輯",18,muted)
	for team: int in range(2):
		var x := watch_x(team)
		var color: Color = RED if team == 0 else BLUE
		label_at(Vector2(x,140),"紅方" if team == 0 else "藍方",30,color)
		label_at(Vector2(x+76,138),"平均 %.1f 金幣" % DeckStore.average(watch_decks[team]),18,muted)
		# Lord chips.
		var index := 0
		for lord_kind: String in B.lord_menu_order():
			var r := watch_lord_rect(team,index)
			var chosen: bool = watch_lords[team] == lord_kind
			panel(r,Color("f6e9c8") if chosen else Color("e3d2aa"),color if chosen else Color("8a6f4a"))
			draw_fitted(lord_art(lord_kind,team),Rect2(r.position+Vector2(6,5),Vector2(r.size.x-12,r.size.y-30)),Color.WHITE if chosen else Color(0.8,0.78,0.74),true)
			draw_string(font,Vector2(r.position.x,r.end.y-8),B.LORDS[lord_kind].name.trim_suffix("領主"),HORIZONTAL_ALIGNMENT_CENTER,r.size.x,14,INK if chosen else muted)
			if chosen: draw_rect(r.grow(3),color,false,4)
			index += 1
		# Army frame: portrait + eight cards.
		var army := watch_army(team)
		panel(army,Color("e6d3a8"),Color("6a5236"))
		draw_rect(army.grow(-6),Color("8a6f4a"),false,1)
		var portrait := watch_portrait(team)
		var lord: String = watch_lords[team]
		panel(portrait,Color("f6e9c8"),color)
		draw_fitted(lord_art(lord,team),portrait.grow(-10),Color.WHITE,true)
		draw_string(font,Vector2(portrait.position.x,portrait.end.y+30),B.LORDS[lord].name,HORIZONTAL_ALIGNMENT_CENTER,portrait.size.x,22,INK)
		draw_string(font,Vector2(portrait.position.x,portrait.end.y+54),"%s %d 金幣" % [B.LORDS[lord].skill,int(B.skill_cost(lord))],HORIZONTAL_ALIGNMENT_CENTER,portrait.size.x,14,color)
		var shown: Array = B.menu_sorted(watch_decks[team])
		for i: int in range(shown.size()): draw_card(shown[i],watch_card_rect(team,i))
		var hover := army.has_point(get_global_mouse_position())
		var tag := Rect2(army.end.x-150,army.end.y-4,150,36)
		panel(tag,color if hover else Color("f6e9c8"),color)
		draw_string(font,Vector2(tag.position.x,tag.position.y+25),"編輯牌組 ▸",HORIZONTAL_ALIGNMENT_CENTER,tag.size.x,17,Color("fbf1dc") if hover else color)
		if hover: draw_rect(army.grow(3),color,false,3)
	draw_line(Vector2(800,120),Vector2(800,660),Color(INK,0.25),2)

func card_description(kind: String) -> String:
	return B.card_description(kind)

func help_columns() -> Array[String]:
	return [
		"[b]選牌與放置[/b]\n1–4 選手牌，F 選常駐牌；點卡再點戰場，或拖曳放置。右鍵取消選牌。Esc 取消選牌或切換暫停。\n空白鍵暫停；暫停或結束後按 R 重玩。F11 切換全螢幕。\n\n[b]牌組與領主[/b]\n選一位領主與 8 張輪轉牌，另有一張常駐經濟牌。依領主陣營使用經典、黑暗、魔法與中立牌。\n領主由 AI 移動防守；按 Q 發動技能，費用與效果見技能按鈕及圖鑑。\n\n[b]種田與防守[/b]\n農田自己產金幣；農民從田後方出發，順路耕田加速並回血。相同建築覆蓋自己的舊建築可補滿生命。\n部隊只往前走，不追身後範圍外的敵人；城牆不反擊，靠領主、部隊與建築防守。",
		"[b]一日戰役[/b]\n上方日晷的太陽走完一天：白天 3 分鐘（正常）；03:00 正午（×1.5）；04:30 黃昏（×2）。\n%d 分鐘入夜（×%d，雙方城牆持續掉血，每分鐘加倍）。\n%d 分鐘天亮仍未分勝負，領地較大的一方獲勝。肉鴿模式不入夜，改在 %d 分鐘比城牆血量。\n\n[b]破門與勝負[/b]\n建築與部隊限己方領地：建築、城牆周圍八格先佔先得，失去所有己方建築覆蓋就釋出。城牆損毀後，敵兵直接穿過缺口，不需拆除殘垣。\n任何敵兵走進家門就輸。\n\n[b]觀戰模式[/b]\n開戰前調整雙方牌組與領主（預設隨機），AI 出牌；1–4 切換 ×1／×2／×4／×8，＋／－ 逐級調速。" % [int(B.NIGHT_START/60),int(B.NIGHT_GOLD),int(B.DAWN/60),int(preload("res://roguelike_catalog.gd").TIME_LIMIT/60)]
	]

func show_help() -> void:
	screen = "help"
	clear_ui()
	var columns := help_columns()
	for i: int in range(columns.size()):
		var text := RichTextLabel.new()
		text.name = "HelpColumn%d" % i
		text.position = L.HELP_TEXT_RECTS[i].position
		text.size = L.HELP_TEXT_RECTS[i].size
		text.bbcode_enabled = true
		text.text = columns[i]
		text.scroll_active = false
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_theme_font_override("normal_font",font)
		text.add_theme_font_override("bold_font",font)
		text.add_theme_font_size_override("normal_font_size",L.HELP_FONT_SIZE)
		text.add_theme_font_size_override("bold_font_size",L.HELP_FONT_SIZE)
		text.add_theme_color_override("default_color",INK)
		add_child(text)
		ui.append(text)
	button(L.HELP_BACK,"回到標題",show_title)
	queue_redraw()

func draw_help() -> void:
	panel(L.HELP_PANEL)
	label_at(L.HELP_TITLE,"操作與勝負",44)

var settings_path := "user://settings.json"
var settings_return := "title" # "battle" while the settings were opened from the pause banner

func save_settings() -> void:
	var file := FileAccess.open(settings_path,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"effects":fx_enabled,"shake":shake_enabled,"sound":sfx_volume > 0.001,"music_volume":music_volume,"sfx_volume":sfx_volume,"fullscreen":fullscreen}))

func load_settings() -> void:
	if not FileAccess.file_exists(settings_path): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if data is Dictionary:
		fx_enabled = bool(data.get("effects",true))
		shake_enabled = bool(data.get("shake",true))
		# Files from before the volume sliders only know sound on / off.
		sfx_volume = clampf(float(data.get("sfx_volume",0.8 if bool(data.get("sound",true)) else 0.0)),0.0,1.0)
		music_volume = clampf(float(data.get("music_volume",0.7)),0.0,1.0)
		fullscreen = bool(data.get("fullscreen",false))

# Slider positions are squared into gain, so the middle of the slider sounds like half as loud.
func apply_audio_settings() -> void:
	Music.set_bus_volume("Music",music_volume*music_volume)
	Music.set_bus_volume("SFX",sfx_volume*sfx_volume)
	sound_enabled = sfx_volume > 0.001
	if sound != null: sound.enabled = sound_enabled

# A window larger than the desktop (1600 x 900 on a small laptop) is shrunk to fit, then centred.
func fit_window() -> void:
	if DisplayServer.get_name() == "headless": return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := DisplayServer.window_get_size()
	var room := Vector2(area.size)-Vector2(24,64) # window borders and title bar
	if size.x <= room.x and size.y <= room.y: return
	var k := minf(room.x/L.VIEWPORT_SIZE.x,room.y/L.VIEWPORT_SIZE.y)
	size = Vector2i(L.VIEWPORT_SIZE*k)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(area.position+(area.size-size)/2)

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	save_settings()
	if DisplayServer.get_name() == "headless": return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if not on: fit_window()

func show_settings() -> void:
	preload("res://settings_screen.gd").build(self)

func show_review() -> void:
	screen = "recap"
	clear_ui()
	library.text_box(Rect2(140,161,1320,555),review.report(model),24)
	title_button(Rect2(100,804,250,48),"返回結算",close_review)
	if rogue.in_battle: title_button(Rect2(1250,804,250,48),"肉鴿進度",func(): rogue.leave_battle(self))
	else: title_button(Rect2(1250,804,250,48),"再次挑戰" if adventure.index >= 0 else "再戰一局",restart)
	queue_redraw()

func close_review() -> void:
	clear_ui()
	screen = "battle"
	queue_redraw()

func show_adventure() -> void:
	rogue.in_battle = false
	adventure.show(self)

func show_rogue() -> void:
	rogue.show(self)
