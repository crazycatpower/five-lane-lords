extends Node2D
const B = preload("res://balance.gd")
const Frontier = preload("res://frontier_cards.gd")
const L = preload("res://layout.gd")
const DeckStore = preload("res://deck_store.gd")
const Battle = preload("res://battle.gd")
const Arcane = preload("res://arcane_mechanics.gd")
const ART = preload("res://manuscript_art.gd")
const Keywords = preload("res://card_keywords.gd")
const AttackAnimation = preload("res://attack_animation.gd")
const CardSort = preload("res://card_sort.gd")
var attack_animation := AttackAnimation.new()
var polish = preload("res://ui_polish.gd").new()
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
static var art_sources: Dictionary = {}
static var art_aliases: Dictionary = {}
# Bump only when team_material or palette conversion changes, not for UI/gameplay edits.
const PALETTE_REVISION := "team-material-v2"
const ROMAN := ["I","II","III","IV","V","VI"]
var selected := -1
var notice := "1–4 選牌 · 點戰場放置 · 右鍵取消 · 空白鍵暫停"
# No text prompts in battle (producer 2026-11-03): events and refusals show as visual cues.
# notice still records the last message for the review log and tests.
var purse_alarm := 0.0 # missing coins flash and the heap shakes (not enough gold)
var purse_need := 0.0 # gold the refused card or skill wanted
var card_shake := {} # hand slot -> seconds left of a "still cooling" shake
var place_flash := 0.0 # valid cells pulse after a placement on a wrong cell
var skill_shake := 0.0
var cursor_hint_text := ""
var cursor_hint_left := 0.0
var cursor_hint_color := RED
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
var net_room_code := ""
var net_server_url := NetMatch.default_url()
var net_auto_ai := true
var vs_ai_matched_name := ""
var watch_edit := -1 # >= 0: the deck screen is editing this spectate side (nothing is saved to disk)
var watch_stash := {} # the player's own deck and lord while a spectate side is being edited
var deck_tab := "all"
var deck_page := 0
var deck_sort := "group"
var deck_faction := "all"
var deck_in_first := false
var difficulty := 1
var enemy_mode := 0 # 0: 經典冥府領主對手，1: 依難度選擇預設對手
var practice_lord := "random" # "random" or a key in B.LORDS
var practice_ratio_id := "lord_best" # "lord_best", "random", or an id in DeckStore.PRACTICE_RATIOS
var practice_foe_lord := ""
var practice_foe_ratio_id := "lord_best"
var practice_foe_deck: Array = []
var spectating := false
var menu_notice := ""
# Spectate setup: each side's deck, lord and where the deck came from (WATCH_SOURCES index, -1 = edited by hand).
var watch_decks: Array = [[],[]]
var watch_lords: Array = ["lion","lion"]
var watch_source: Array = [0,0]
var watch_lord_decks: Array = [{},{}] # per side: lord_kind -> saved 8-card deck
var watch_lord_sources: Array = [{},{}] # per side: lord_kind -> WATCH_SOURCES index or -1
var watch_path := "user://watch_decks.json"
const WATCH_SOURCES := ["隨機","我的牌組"] # recommended presets removed from the menus (producer 2026-11-05)
var start_button: Button
var effects: Array[Dictionary] = []
const FactionVisuals = preload("res://faction_visuals.gd")
const FxPolish = preload("res://fx_polish.gd")
const DayCycle = preload("res://day_cycle.gd")
const Ceremony = preload("res://battle_ceremony.gd")
const Cinematic = preload("res://cinematic_director.gd")
const Details = preload("res://battle_details.gd")
const Recorder = preload("res://match_recorder.gd")
var cinematic := Cinematic.new()
var recorder := Recorder.new()
var recording_presenter := preload("res://recording_mode.gd").new()
var lord_cast_left := [0.0, 0.0]
var lord_cast_duration := [0.42, 0.42]
var lord_cast_spell := ["", ""]
var skill_flash_left := 0.0
var levy_visuals := {} # last visible positions; scoped to this model
var levy_visual_model: RefCounted
const ADVENTURE_FRAME_PATHS := [
	"res://assets/manuscript-v1/adventure-lord-attack/frame-0.png",
	"res://assets/manuscript-v1/adventure-lord-attack/frame-1.png",
	"res://assets/manuscript-v1/adventure-lord-attack/frame-2.png",
	"res://assets/manuscript-v1/adventure-lord-attack/frame-3.png",
	"res://assets/manuscript-v1/adventure-lord-attack/frame-4.png",
	"res://assets/manuscript-v1/adventure-lord-attack/frame-5.png",
]
var adventure_attack_frames: Array = [null,null,null,null,null,null]
var adventure_attack_frames_blue: Array = [null,null,null,null,null,null]

func get_adventure_frame(f: int, team: int = 0) -> Texture2D:
	var idx := clampi(f, 0, ADVENTURE_FRAME_PATHS.size() - 1)
	if adventure_attack_frames[idx] == null:
		var path: String = ADVENTURE_FRAME_PATHS[idx]
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			adventure_attack_frames[idx] = ResourceLoader.load_threaded_get(path)
		else:
			adventure_attack_frames[idx] = load(path)
	if team == 1:
		if adventure_attack_frames_blue[idx] == null:
			adventure_attack_frames_blue[idx] = recolor_blue(adventure_attack_frames[idx], 384, "lord_adventure")
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
var replay_enabled := false
var clock := 0.0 # seconds of real time since launch: drives menu and overlay animation
var veil: ColorRect # parchment wash that fades out after every screen change
var result_age := 0.0 # seconds since the match ended (the result panel and its ceremony ease in)
var result_seen: RefCounted # the model whose ending has been announced
var intro_left := 0.0 # seconds left of the "who fights whom" banner at the start of a battle
const INTRO_TIME := 2.4
const VERSION := "0.4.0"
var hover_slot := -1
var dragging := false
var press_pos := Vector2.ZERO
var press_was_selected := false
var speed := 1
const RESULT_RECT := Rect2(310,110,980,506) # the closing page (battle_ceremony.gd PANEL)
const SPEEDS := [1,2,4,8]
const SPEED_RECTS := [Rect2(1380,734,42,30),Rect2(1426,734,42,30),Rect2(1472,734,42,30),Rect2(1518,734,42,30)]
const NEXT_RECT := Rect2(1102,748,96,128)
const SKILL_RECT := Rect2(1334,722,226,74) # battle_hud.gd: right of the lord's portrait
const LORD_PLATE := Rect2(1210,712,356,166)

const TITLE_ART_KEYS := ["militia","farm","hunter","grave","skeleton","ghoul","reaper"]
const PRIORITY_BATTLE_KEYS := ["castle_red","castle_blue","castle_wall","gate","gate_broken","crest","farmer"]
var prewarm_keys: Array[String] = []
var prewarm_inflight: Array[Dictionary] = []

static func load_manifest() -> void:
	if palette_manifest.is_empty() and FileAccess.file_exists("res://assets/generated-palette/manifest.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated-palette/manifest.json"))
		if parsed is Dictionary: palette_manifest = parsed

static func blue_max_size(kind: String) -> int:
	return 0 if kind in ["castle_red","castle_wall","gate","gate_broken"] else 384

static func generated_blue_path(source_path: String, max_size: int, kind: String) -> String:
	if kind in ["farm","farmer","harvest","rain","fire"]: return ""
	load_manifest()
	var entry: Dictionary = palette_manifest.get(kind,{})
	var generated := "res://assets/generated-palette/"+kind+".png"
	if entry.get("revision","") == PALETTE_REVISION and entry.get("source","") == source_path and int(entry.get("size",-1)) == max_size and ResourceLoader.exists(generated):
		return generated
	return ""

static func build_art_index() -> void:
	if not art_sources.is_empty(): return
	for pair: Array in [["militia","manuscript-v1/militia-red.png"],["farmer","farmer.png"],["farm","farmland.png"],["castle_red","manuscript-v1/castle-red.png"]]:
		art_sources[pair[0]] = "res://assets/"+pair[1]
	art_aliases["castle_blue"] = "castle_red"
	for kind: String in B.CARDS:
		var file := "res://assets/manuscript-v1/"+kind+".png"
		if ResourceLoader.exists(file): art_sources[kind] = file
	for pair: Array in [["glutton_nest_closed","glutton_nest_closed"],["gate","lane-wall"],["gate_broken","lane-wall-broken"],["crest","crown"],["castle_wall","castle-wall"]]:
		art_sources[pair[0]] = "res://assets/manuscript-v1/"+pair[1]+".png"
	for lord_kind: String in B.LORDS:
		art_sources["lord_"+lord_kind] = "res://assets/manuscript-v1/lord-"+lord_kind+".png"
	for kind: String in B.CARDS:
		var reference: Variant = B.CARDS[kind].get("art",[kind])
		var borrow: String = reference if reference is String else reference[0]
		if not art_sources.has(kind) and art_sources.has(borrow): art_aliases[kind] = borrow
	for lord_kind: String in B.MINION_LORDS:
		var card: String = B.MINION_LORDS[lord_kind].card
		if art_sources.has(card) or art_aliases.has(card): art_aliases["lord_"+lord_kind] = art_aliases.get(card,card)

static func take_texture(path: String) -> Texture2D:
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		var loaded = ResourceLoader.load_threaded_get(path)
		if loaded is Texture2D: return loaded
	return load(path)

static func ensure_static_art(kind: String, need_blue: bool = false) -> Texture2D:
	build_art_index()
	if prepared_art.is_empty(): prepared_art = {"textures":{},"blue":{}}
	var tex_map: Dictionary = prepared_art.textures
	var blue_map: Dictionary = prepared_art.blue
	var canonical: String = art_aliases.get(kind,kind)
	if not art_sources.has(canonical): canonical = "militia"
	if not tex_map.has(canonical):
		tex_map[canonical] = take_texture(art_sources[canonical])
	if kind != canonical and not tex_map.has(kind):
		tex_map[kind] = tex_map[canonical]
	if need_blue:
		if not blue_map.has(canonical):
			blue_map[canonical] = recolor_blue(tex_map[canonical],blue_max_size(canonical),canonical)
		if kind != canonical and not blue_map.has(kind):
			blue_map[kind] = blue_map[canonical]
		return blue_map.get(kind,tex_map[kind])
	return tex_map.get(kind,tex_map.militia)

# Shared by the asset preflight and the game; prepared palettes load all art on demand or via prepare_art.
static func prepare_art(progress: Callable = Callable()) -> void:
	build_art_index()
	var total := art_sources.size()
	var done := 0
	for kind: String in art_sources:
		ensure_static_art(kind,true)
		done += 1
		if progress.is_valid(): progress.call(done,total)
	for alias: String in art_aliases:
		ensure_static_art(alias,true)

func sync_art_entry(kind: String) -> void:
	var canonical: String = art_aliases.get(kind,kind)
	if not art_sources.has(canonical): canonical = "militia"
	if prepared_art.textures.has(canonical):
		textures[canonical] = prepared_art.textures[canonical]
		if kind != canonical: textures[kind] = prepared_art.textures[canonical]
	if prepared_art.blue.has(canonical):
		blue_art[canonical] = prepared_art.blue[canonical]
		if kind != canonical: blue_art[kind] = prepared_art.blue[canonical]

func ensure_art(kind: String, need_blue: bool = false) -> Texture2D:
	var result := ensure_static_art(kind,need_blue)
	sync_art_entry(kind)
	return result

func load_all_art() -> void:
	prepare_art()
	textures = prepared_art.textures.duplicate()
	blue_art = prepared_art.blue.duplicate()
	prewarm_keys.clear()
	prewarm_inflight.clear()

func queue_art_prewarm() -> void:
	prewarm_keys.clear()
	var seen := {}
	for k: String in PRIORITY_BATTLE_KEYS:
		var ck := str(art_aliases.get(k,k))
		if art_sources.has(ck) and not seen.has(ck) and not blue_art.has(ck):
			seen[ck] = true
			prewarm_keys.append(ck)
	for deck_card: Variant in player_deck:
		var ck := str(art_aliases.get(str(deck_card),str(deck_card)))
		if art_sources.has(ck) and not seen.has(ck) and not blue_art.has(ck):
			seen[ck] = true
			prewarm_keys.append(ck)
	for kind: String in art_sources:
		if not seen.has(kind) and not blue_art.has(kind):
			seen[kind] = true
			prewarm_keys.append(kind)
	for path: String in ADVENTURE_FRAME_PATHS:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path)

static func thread_done(path: String) -> bool:
	if path.is_empty(): return true
	var status := ResourceLoader.load_threaded_get_status(path)
	return status != ResourceLoader.THREAD_LOAD_IN_PROGRESS

func step_art_prewarm(budget_ms: int = 3) -> void:
	if DisplayServer.get_name() == "headless": return
	if prewarm_keys.is_empty() and prewarm_inflight.is_empty(): return
	var deadline := Time.get_ticks_msec()+budget_ms
	var still_inflight: Array[Dictionary] = []
	for item: Dictionary in prewarm_inflight:
		if thread_done(item.src) and thread_done(item.gen):
			if Time.get_ticks_msec() <= deadline:
				ensure_art(item.kind,true)
			else:
				still_inflight.append(item)
		else:
			still_inflight.append(item)
	prewarm_inflight = still_inflight
	while prewarm_inflight.size() < 4 and not prewarm_keys.is_empty():
		var kind: String = prewarm_keys.pop_front()
		if blue_art.has(kind): continue
		var src: String = art_sources[kind]
		ResourceLoader.load_threaded_request(src)
		var gen := generated_blue_path(src,blue_max_size(kind),kind)
		if not gen.is_empty(): ResourceLoader.load_threaded_request(gen)
		prewarm_inflight.append({"kind":kind,"src":src,"gen":gen})

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
	var saved: Dictionary = DeckStore.load_full(deck_path)
	player_deck = saved.cards
	player_lord = saved.lord
	build_art_index()
	if not prepared_art.is_empty():
		textures = prepared_art.textures.duplicate()
		blue_art = prepared_art.blue.duplicate()
	for kind: String in TITLE_ART_KEYS:
		ensure_art(kind,true)
	if player_lord == "adventure": get_adventure_frame(0,0)
	else: ensure_art("lord_"+player_lord,true)
	if DisplayServer.get_name() != "headless": queue_art_prewarm()
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
	seed_value = int(Time.get_unix_time_from_system())
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.substr(7))
	load_settings()
	load_watch()
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
	model = Battle.new(seed_value,player_deck,[],player_lord)
	show_title()

func start_battle() -> void:
	vs_ai_matched_name = ""
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
		ensure_practice_opponent()
		model = Battle.new(seed_value,player_deck,practice_foe_deck.duplicate(),player_lord,practice_foe_lord)
	model.difficulty = difficulty
	model.ai_enabled = [spectating,true]
	enter_battle("觀戰中：AI 操控雙方。1–4 或 + / − 調整速度，空白鍵暫停。" if spectating else "拖曳卡牌到戰場，或按 1–4／F 選牌再點格子 · 右鍵取消 · 空白鍵暫停")

func restart() -> void:
	if net != null or rogue.in_battle: return # a roguelike battle cannot be replayed
	if adventure.index >= 0: adventure.start(self,adventure.index)
	else:
		if not spectating: roll_practice_opponent()
		start_battle()

func enter_battle(message: String) -> void:
	review.clear()
	attack_animation.clear()
	cinematic.reset()
	polish.reset_battle()
	recording_presenter = preload("res://recording_mode.gd").new()
	recorder.start(self, model)
	lord_cast_left = [0.0, 0.0]
	lord_cast_spell = ["", ""]
	selected = -1
	dragging = false
	cursor_hint_text = ""
	cursor_hint_left = 0.0
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

var ui_xform := Transform2D.IDENTITY # a tilted or lifted hand card: helpers that call tf() stay inside it
func tf(pos: Vector2 = Vector2.ZERO, rot: float = 0.0, scl: Vector2 = Vector2.ONE) -> void:
	var t := Transform2D(rot,scl,0.0,pos)
	draw_set_transform_matrix(ui_xform*cinematic.field_transform(self)*t)

# Screen point -> battle point (and back: the mirror is its own inverse).
func to_model(p: Vector2) -> Vector2:
	return cinematic.screen_to_field(self,p)

func field_mouse() -> Vector2:
	return to_model(get_global_mouse_position())

# Text on the mirrored field stays readable: drawn unmirrored at the mirrored spot.
func field_text(pos: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, color: Color) -> void:
	if not field_mirror:
		draw_string(font,pos,text,align,width,size,color)
		return
	var w: float = width if width > 0 else font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	field_mirror = false
	tf()
	draw_string(font,Vector2(L.VIEWPORT_SIZE.x-pos.x-w,pos.y),text,align,width,size,color)
	field_mirror = true
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

func _net_ui_bucket(s: String) -> String:
	return "searching" if s in ["connecting","searching"] else s

func _physics_process(dt: float) -> void:
	if net != null:
		var prev_bucket := _net_ui_bucket(net.state)
		if net.poll(dt) and screen == "net":
			start_net_battle()
			return
		if screen == "net":
			if _net_ui_bucket(net.state) != prev_bucket: show_net()
			else: queue_redraw()
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
		if not model.paused and not model.ended:
			recorder.dispatch_replay(model)
		model.step(dt)
		if adventure.is_opening(): adventure.opening.observe(self)
		attack_animation.observe(model)
		if not model.paused and not model.ended:
			recorder.observe_tick(model, self)
			recorder.tick += 1
		consume_events()
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
	var hit_fx_count := 0
	for existing_fx: Dictionary in effects:
		if existing_fx.kind == "hit": hit_fx_count += 1
	for event_index: int in range(model.events.size()):
		var e: Dictionary = model.events[event_index]
		if e.kind == "spell":
			hop = 0
			sacrifice_team = e.team if e.get("card","") == "sacrifice" else -1
		if e.kind == "breach": say(("我方第 %d 路城牆被攻破！敵兵走進來就輸了" % (e.lane+1)) if e.team != me else ("攻破%s第 %d 路城牆！派兵走進去就贏" % [Ceremony.side_name(self,1-me),e.lane+1]),e.team != me)
		if e.kind == "skill": say("%s%s發動「%s」" % ["紅方" if e.team == 0 else "藍方",B.lord_name(e.lord),B.lord_data(e.lord).get("skill","技能")])
		if e.kind == "ramp": say("金幣產出與卡牌冷卻加快 ×%.1f" % e.multiplier)
		if e.kind == "nightfall" and e.get("first",false): say("入夜：金幣 ×%s，雙方城牆開始朽壞" % B.number(B.NIGHT_GOLD))
		if e.kind == "overflow" and e.team == me and not spectating: say("金幣袋滿了，繼續產出的金幣會浪費")
		if sound != null:
			if sound.has_method("cue_event"): sound.cue_event(e)
			else: sound.cue(e.kind)
		if e.kind == "play" and B.CARDS.get(e.get("card",""),{}).get("type","") == "spell":
			lord_cast_duration[e.team] = 0.42
			lord_cast_left[e.team] = 0.42
			lord_cast_spell[e.team] = e.get("card","")
		elif e.kind in ["skill","hero_slash"]:
			lord_cast_duration[e.team] = 1.15
			lord_cast_left[e.team] = 1.15
			lord_cast_spell[e.team] = "skill:" + String(e.get("lord",""))
			if e.kind == "skill" and e.team == me:
				skill_flash_left = 1.15
		cinematic.on_event(self,e)
		recording_presenter.observe(self,e)
		if fx_enabled:
			if e.kind == "hit":
				if hit_fx_count >= 18: continue
				hit_fx_count += 1
			var copy := e.duplicate()
			copy.life = {"nightfall":2.6 if e.get("first",false) else 1.2,"breach":2.0,"ramp":1.4,"burn":5.0,"death":0.35,"play":0.45,"ink":0.6,"skill":1.0,"link":0.6,"slash":0.35,"drum":0.6,"stone_impact":0.6,"catapult_fire":0.4,"curse_rise":0.5,"spell":1.0,"trap_blast":0.8,"boneburst":0.7,"hit":0.24}.get(e.kind,0.7)
			if e.kind == "link" and e.style == "lightning":
				copy.hop = hop
				hop += 1
				copy.life = 0.3
			if e.kind == "link" and e.style == "devour" and e.team == sacrifice_team and event_index+1 < model.events.size() and model.events[event_index+1].kind == "hit" and model.events[event_index+1].pos == e.pos:
				# Sacrifice links end at the cast point; blood-tower links retain their target.
				for cast_event: Dictionary in model.events:
					if cast_event.kind == "spell" and cast_event.get("card","") == "sacrifice" and cast_event.team == e.team and cast_event.pos == e.to:
						copy.to = to_model(preload("res://economy_hud.gd").PURSE.get_center() if e.team == me else preload("res://battle_hud.gd").gold_anchor(1)+Vector2(0,14))
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
func present(dt: float) -> void:
	clock += dt
	polish.step_transitions(self,dt)
	if model == null: return
	var fighting := in_battle()
	if fighting and not model.paused and not model.ended: intro_left = maxf(0.0,intro_left-dt)
	if fighting and model.ended:
		if result_seen != model:
			result_seen = model
			result_age = 0.0
			recorder.finish(self, model)
			if music != null: music.play_sting("victory" if Ceremony.mood(self) > 0 else "defeat")
		recorder.poll_export()
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
	var real_dt := dt
	step_art_prewarm()
	present(dt)
	if ui_time_locked():
		queue_redraw()
		return
	if model != null and model.paused: dt = 0
	if screen == "battle" and model != null:
		polish.observe_battle(self,real_dt,dt)
	shake_left = maxf(0,shake_left-dt)
	purse_alarm = maxf(0,purse_alarm-dt)
	place_flash = maxf(0,place_flash-dt)
	skill_shake = maxf(0,skill_shake-dt)
	skill_flash_left = maxf(0.0,skill_flash_left-real_dt)
	cursor_hint_left = maxf(0.0,cursor_hint_left-real_dt)
	for k: int in card_shake.keys():
		card_shake[k] -= dt
		if card_shake[k] <= 0: card_shake.erase(k)
	position = Vector2(0,0.0 if screen == "battle" else polish.page_offset(self)) # menu pages rise into place
	cinematic.step(self,dt)
	var fx_step: float = cinematic.fx_dt(dt)
	for t_idx: int in range(2): lord_cast_left[t_idx] = maxf(0.0, lord_cast_left[t_idx] - fx_step)
	for e: Dictionary in effects:
		e.life -= fx_step
		if e.life <= 0.0 and e.kind == "ink" and int(e.get("team", -1)) == me:
			polish.purse_flash = 0.32
	effects = effects.filter(func(e: Dictionary) -> bool: return e.life > 0)
	queue_redraw()

# Hand area: the permanent farmland slot, the four rotating cards, then the next-card preview.
func card_rect(slot: int) -> Rect2:
	if slot == Battle.FARM_SLOT: return Rect2(418,730,124,158)
	return Rect2(560+slot*134,730,124,158)

func card_at(pos: Vector2) -> int:
	if adventure.is_opening() and adventure.opening.active: return -1
	for i: int in [0,1,2,3,Battle.FARM_SLOT]:
		if card_rect(i).has_point(pos): return i
	return -1

func toggle_pause() -> void:
	if ui_time_locked() or net != null: return
	if not model.ended:
		model.paused = not model.paused
		if sound != null: sound.cue("pause")

func set_speed(value: int) -> void:
	speed = value
	say("觀戰速度 ×%d" % speed)

# Buttons on the pause banner / closing page: [rect, caption, action], centred as a row.
func overlay_buttons() -> Array:
	var entries: Array = []
	if not model.ended: entries.append(["繼續",toggle_pause])
	else: entries.append(["戰局復盤",show_review])
	if model.ended and recorder.has_saved_replay() and not OS.has_feature("web"):
		match recorder.export_state:
			"done": entries.append(["開啟錄影夾", func(): recorder.open_recordings_folder()])
			"rendering": entries.append(["MP4 轉檔中", func(): recorder.open_recordings_folder()])
			"error": entries.append(["重試 MP4", func(): recorder.export_mp4()])
			_: entries.append(["輸出 MP4", func(): recorder.export_mp4()])
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
		recorder.record_cmd("play", me, slot, pos)
		selected = -1
		return true
	say(reason)
	match model.play_check(me,slot,pos):
		Battle.Refusal.GOLD:
			purse_alarm = 0.9
			purse_need = B.CARDS[model.kind_at(me,slot)].cost
			show_cursor_hint("金幣不足（還差 %d）" % ceili(purse_need - model.ink[me]), RED)
		Battle.Refusal.COOLDOWN:
			card_shake[slot] = 0.45
			show_cursor_hint("冷卻中 %.1f秒" % model.slot_cd(me,slot), Color("7d4f1c"))
		Battle.Refusal.NOT_OURS, Battle.Refusal.OFF_GRID, Battle.Refusal.OCCUPIED, Battle.Refusal.WATER, Battle.Refusal.BLOCKED:
			place_flash = 1.0
			show_cursor_hint(reason, Color("7d4f1c"))
	effects.append({"kind":"fail","pos":pos,"life":0.5,"duration":0.5})
	if sound != null: sound.cue("fail")
	return false

func _unhandled_input(event: InputEvent) -> void:
	if ui_time_locked(): return
	if screen == "recap" and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_review()
		return
	if screen == "deck":
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
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
			if event.keycode in [KEY_LEFT, KEY_PAGEUP]: step_deck_page(-1, false)
			elif event.keycode in [KEY_RIGHT, KEY_PAGEDOWN]: step_deck_page(1, false)
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: step_deck_page(-1, false)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: step_deck_page(1, false)
		return
	if screen in ["codex","battle_info"]:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				if screen == "codex": library.back()
				else: library.close_battle_info()
			elif screen == "codex":
				if event.keycode == KEY_LEFT: library.step_entry(-1)
				elif event.keycode == KEY_RIGHT: library.step_entry(1)
				elif event.keycode == KEY_PAGEUP: library.step_page(-1)
				elif event.keycode == KEY_PAGEDOWN: library.step_page(1)
		elif screen == "codex" and event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: library.step_page(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: library.step_page(1)
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
		if event.keycode == KEY_F9:
			cinematic.theater_mode = not cinematic.theater_mode
			cinematic.theater_hint_left = 2.4 if cinematic.theater_mode else 0.0
			queue_redraw()
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
	if rect.size.x > 140 and rect.size.y > 70 and fill.a > 0.5:
		draw_rect(Rect2(rect.position+Vector2(4,6),rect.size),Color(0.12,0.08,0.04,0.16*fill.a))
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(border,0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	draw_style_box(style,rect)
	# Large panels (2026-11-21 restyle): a drop shadow, paper grain, a fine inner rule and ink corner marks.
	var big := rect.size.x > 140 and rect.size.y > 70 and fill.a > 0.5
	if big:
		draw_texture_rect(PAPER,rect.grow(-2),false,Color(1,1,1,0.10*fill.a))
	if rect.size.x > 30 and rect.size.y > 20: draw_rect(rect.grow(-4),Color(border,0.3),false,1)
	if big:
		for c: Vector2 in [rect.position+Vector2(9,9),Vector2(rect.end.x-9,rect.position.y+9),rect.end-Vector2(9,9),Vector2(rect.position.x+9,rect.end.y-9)]:
			draw_colored_polygon(PackedVector2Array([c+Vector2(0,-3.5),c+Vector2(3.5,0),c+Vector2(0,3.5),c+Vector2(-3.5,0)]),Color(border,0.55*border.a))

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
	if kind == "lord_adventure": return get_adventure_frame(0, team)
	if team == 1:
		var btex: Variant = blue_art.get(kind)
		if btex != null: return btex
		return ensure_art(kind,true)
	var rtex: Variant = textures.get(kind)
	if rtex != null: return rtex
	return ensure_art(kind,false)

func lord_art(kind: String, team: int = 0) -> Texture2D:
	var key := kind if kind.begins_with("lord_") else "lord_"+kind
	if team == 1:
		var btex: Variant = blue_art.get(key)
		if btex != null: return btex
		return ensure_art(key,true)
	var rtex: Variant = textures.get(key)
	if rtex != null: return rtex
	return ensure_art(key,false)

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
	load_manifest()
	var entry: Dictionary = palette_manifest.get(kind,{})
	var generated := "res://assets/generated-palette/"+kind+".png"
	if entry.get("revision","") == PALETTE_REVISION and entry.get("source","") == source.resource_path and int(entry.get("size",-1)) == max_size and ResourceLoader.exists(generated):
		# Original source files can be remapped inside exports; the build manifest remains valid there.
		if not FileAccess.file_exists(source.resource_path) or entry.get("sha256","") == FileAccess.get_sha256(source.resource_path):
			var texture: Texture2D = take_texture(generated)
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
	var r := fitted_rect(texture.get_size(),box,false)
	if face >= 0:
		draw_texture_rect(texture,r,false,shade)
		return
	var c := r.get_center()
	tf(c,0,Vector2(-1,1))
	draw_texture_rect(texture,Rect2(r.position-c,r.size),false,shade)
	tf()

func actor_rect(kind: String) -> Rect2:
	if kind == "pouch_beast": return fitted_rect(art(kind).get_size(),Rect2(-68,-75,136,108),true)
	if kind == "arcane_golem": return fitted_rect(art(kind).get_size(),Rect2(-83,-126,166,143),true)
	if B.CARDS.get(kind,{}).get("series","") == "magic" and B.CARDS[kind].type == "unit": return fitted_rect(art(kind).get_size(),Rect2(-65,-95,130,112),true)
	if kind == "glutton_nest": return fitted_rect(art(kind).get_size(),Rect2(-45,-28,90,62),true)
	if B.CARDS.get(kind,{}).has("trap"): return fitted_rect(art(kind).get_size(),Rect2(-45,-8,90,46),true)
	if B.CARDS.get(kind,{}).get("series","") == "beast" or kind in ["bog_troll","tusk_boar","dire_hydra","war_lodge","bramble_wall"]:
		var box: Rect2 = {"thorn_dragon":Rect2(-101,-107,202,124),"dire_hydra":Rect2(-140,-88,280,111),"long_dragon":Rect2(-98,-60,196,77),"belly_eye":Rect2(-82,-94,164,111),"bog_troll":Rect2(-76,-104,152,121),"eyewing_dragon":Rect2(-76,-104,152,121),"tusk_boar":Rect2(-70,-93,140,110),"bramble_wall":Rect2(-68,-64,136,84),"war_lodge":Rect2(-51,-44,102,88)}.get(kind,Rect2(-58,-75,116,92))
		return fitted_rect(art(kind).get_size(),box,true)
	if kind == "arcane_tower": return fitted_rect(art(kind).get_size(),Rect2(-40,-65,80,100),true)
	if kind == "corpse_giant": return fitted_rect(art(kind).get_size(),Rect2(-72,-125,144,144),true)
	if kind == "plague_bishop": return fitted_rect(art(kind).get_size(),Rect2(-70,-132,140,150),true) # 封印祭壇's boss: towers over his monks
	if kind == "lord_adventure": return fitted_rect(get_adventure_frame(0,0).get_size(),Rect2(-62,-81,124,110),true)
	if kind.begins_with("lord_"):
		var lk := kind.trim_prefix("lord_")
		var ls := 112.0 if lk == "iron" else (104.0 if B.lord_data(lk).get("hp",0.0) >= 1500.0 else 96.0)
		return fitted_rect(art(kind).get_size(),Rect2(-ls*0.5,27.0-ls,ls,ls),true)
	if kind in ["catapult"] or B.CARDS.get(kind,{}).get("type","") == "building":
		var b_box: Rect2 = {"bonewall":Rect2(-56,-49,112,98),"barricade":Rect2(-54,-47,108,94),"scarecrow":Rect2(-51,-44,102,88),"mill":Rect2(-51,-44,102,88)}.get(kind,Rect2(-45,-39,90,78))
		return fitted_rect(art(kind).get_size(),b_box,true)
	if kind == "ram": return fitted_rect(art(kind).get_size(),Rect2(-76,-91,152,108),true)
	var width := 112.0 if kind in ["ox","disgraced_lancer"] else 80.0
	return fitted_rect(art(kind).get_size(),Rect2(-width/2,-63,width,80),true)

func draw_actor(kind: String, team: int, pos: Vector2, face: float, shade: Color = Color.WHITE) -> void:
	# tf() mirrors both position and facing for the guest; keep world-space facing here.
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
	var extra_offset := Vector2.ZERO
	var extra_scale := Vector2.ONE
	var final_shade := shade
	if fx_enabled and actor.has("cell") and actor.has("id"):
		var bid: int = int(actor.id)
		var b_sp: float = polish.bldg_spawn_progress(bid)
		if b_sp < 1.0:
			var b_ease: float = polish.ease_out(b_sp)
			extra_scale = Vector2(1.0 + 0.14 * sin(b_sp * PI), lerpf(0.70, 1.0, b_ease))
			extra_offset.y = (1.0 - b_ease) * -10.0
			final_shade.a *= clampf(b_sp * 2.5, 0.0, 1.0)
		var b_hit: float = polish.bldg_flash(bid)
		if b_hit > 0.0:
			final_shade = final_shade.lerp(Color(1.55, 1.50, 1.40, final_shade.a), b_hit * 0.85)
			if shake_enabled: extra_offset.x += sin(clock * 90.0) * 2.5 * b_hit
	if pose.is_empty():
		if extra_offset != Vector2.ZERO or extra_scale != Vector2.ONE:
			tf(pos + extra_offset, 0.0, Vector2(face, 1.0) * extra_scale)
			draw_texture_rect(art(kind, actor.team), actor_rect(kind), false, final_shade)
			tf()
		else:
			draw_actor(kind,actor.team,pos,face,final_shade)
		return
	var offset: Vector2 = pose.offset
	offset.x *= face
	offset += extra_offset
	var rect := actor_rect(kind)
	var center := rect.get_center()
	var angle: float = pose.angle*face
	var scale: Vector2 = pose.scale * extra_scale
	# Pivot around the sprite centre. Tall actors in the top lane keep their lane and full size; their head
	# may run under the top frame (producer 2026-11-18: no shrinking or pushing down, lords included).
	var pivot := pos+Vector2(center.x*face,center.y)+offset
	tf(pivot,angle,Vector2(face,1)*scale)
	var tex := art(kind,actor.team)
	if kind == "lord_adventure" and pose.has("frame"):
		tex = get_adventure_frame(pose.frame,actor.team)
	draw_texture_rect(tex,Rect2(-rect.size/2,rect.size),false,final_shade)
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
	build_art_index()
	var reference: Variant = B.CARDS.get(kind,{}).get("art",[kind])
	if reference is String:
		return [kind] if (textures.has(kind) or art_sources.has(kind)) else [reference]
	return reference

func draw_card_art(kind: String, box: Rect2, team: int = 0, shade: Color = Color.WHITE, gray: bool = false) -> void:
	var Style = preload("res://command_style.gd")
	var kinds := card_art_kinds(kind)
	for i: int in range(kinds.size()):
		var part := box
		if kinds.size() > 1:
			part.size.x = box.size.x*0.58
			part.position.x += i*box.size.x*0.42
		var tex := art(kinds[i],team)
		if gray: tex = Style.gray_texture(tex)
		draw_fitted(tex,part,shade,true)

func draw_card(kind: String, rect: Rect2, slot: int = -1) -> void:
	var data: Dictionary = B.CARDS[kind]
	if card_shake.has(slot): rect.position.x += sin(card_shake[slot]*55)*5*clampf(card_shake[slot]/0.45,0,1)
	var s := rect.size
	var scale_k := clampf(s.x/124.0, 0.76, 1.30)
	var Ornament = preload("res://interface_ornament.gd")
	var Style = preload("res://command_style.gd")
	var short: bool = screen == "battle" and model.ink[me] < data.cost
	var cooling: bool = slot >= 0 and screen == "battle" and model.slot_cd(me,slot) > 0
	var blocked: bool = short or cooling
	var sel: bool = selected == slot and slot >= 0
	# Soft vellum drop shadow grounds the card on stone or parchment.
	draw_rect(Rect2(rect.position+Vector2(2,3),s),Color("1e150d",0.22))
	var card_tex: Texture2D = ART.card(sel)
	draw_texture_rect(Style.gray_texture(card_tex) if blocked else card_tex,rect,false,Color(0.68,0.68,0.68) if blocked else Style.card_tint(kind))
	Style.type_frame(self,rect,data.type,blocked)
	Style.faction_frame(self,rect,kind,sel,blocked)
	# No countdowns or shortfall numbers on cards (producer 2026-11-03). Any unready card
	# (cooling or short on gold) stays gray; cooling also shows a parting curtain.
	var art_box := Rect2(rect.position+s*Vector2(0.08,0.125),s*Vector2(0.84,0.485))
	var shade := Color(0.76,0.76,0.76) if blocked else Color.WHITE
	draw_card_art(kind,art_box,0,shade,blocked)
	if blocked: draw_rect(rect.grow(-4),Color(0.24,0.24,0.24,0.26))
	if cooling: curtain(art_box,clampf(model.slot_cd(me,slot)/maxf(0.1,data.cooldown),0,1))
	var cap_rect := Rect2(rect.position+Vector2(s.x*0.074,s.y*0.614),Vector2(s.x*0.852,s.y*0.256))
	Ornament.card_caption(self,cap_rect,Style.card_tint(kind),blocked)
	# Name and keyword cartouches sit comfortably inside cap_rect, separated by an ink hairline.
	var name_fsize := maxi(12, roundi(17.0 * scale_k))
	draw_string(font,Vector2(rect.position.x,rect.position.y+s.y*0.735),data.name,HORIZONTAL_ALIGNMENT_CENTER,s.x,name_fsize,Color("2e2e2e") if blocked else INK)
	Keywords.draw_card_pills(self,rect,kind,blocked)
	var up_map: Dictionary = model.card_upgrades[me] if (screen in ["battle","battle_info"] and model != null and me < model.card_upgrades.size()) else (rogue.run.get("upgrades",{}) if screen == "rogue" and not rogue.run.is_empty() else {})
	if not up_map.is_empty():
		var lv: int = preload("res://card_upgrades.gd").level(up_map.get(kind,{}))
		if lv > 0: # roguelike shop upgrade
			Ornament.wax_upgrade_seal(self,rect.position+Vector2(18*scale_k,s.y*0.625),12.5*scale_k,lv)
	if screen != "battle":
		# Outside battle the top-left corner shows the card's cooldown (in battle it shows the hand slot).
		var cd_rect := Rect2(rect.position+Vector2(6*scale_k,6*scale_k),Vector2(36*scale_k,19*scale_k))
		Ornament.corner_seal(self,cd_rect,"%ss" % B.number(data.cooldown),Color("6b4c33"),maxi(10,roundi(11.5*scale_k)))
		# Faction tag (經典／黑暗／魔導／怪獸／中立) between the cooldown and the cost.
		var faction: String = B.card_faction(kind)
		var tag := Rect2(rect.position+Vector2(s.x*0.53-16*scale_k,7*scale_k),Vector2(32*scale_k,16.5*scale_k))
		Ornament.ribbon_tag(self,tag,B.FACTIONS[faction],Style.tag_color(kind),maxi(10,roundi(11.0*scale_k)))
	# Ink cost medallion, top right.
	var badge := rect.position+Vector2(s.x-18.5*scale_k,18.5*scale_k)
	var cost_txt := "-" if data.get("summon_only",false) else preload("res://gold_monster.gd").cost_text(kind,data)
	Ornament.cost_medallion(self,badge,14.8*scale_k,cost_txt,blocked)
	if slot >= 0:
		var key := "F" if slot == Battle.FARM_SLOT else str(slot+1)
		var seal_col := Color("5e5e5e") if blocked else (Style.tag_color(kind).darkened(0.08) if slot == Battle.FARM_SLOT else Color("6b4c33"))
		var key_rect := Rect2(rect.position+Vector2(6.5*scale_k,6.5*scale_k),Vector2(22*scale_k,22*scale_k))
		Ornament.corner_seal(self,key_rect,key,seal_col,maxi(11,roundi(13.5*scale_k)),slot == Battle.FARM_SLOT and not blocked)

# A gray stage curtain over r: two halves that part from the middle as `closed` goes 1 -> 0.
func curtain(r: Rect2, closed: float) -> void:
	var half := r.size.x*0.5*closed
	if half < 0.5: return
	for side: int in range(2):
		var cloth := Rect2(r.position.x if side == 0 else r.end.x-half,r.position.y,half,r.size.y)
		draw_rect(cloth,Color(0.24,0.24,0.24,0.76))
		var fold := 0
		var x := cloth.position.x
		while x < cloth.end.x:
			var w := minf(7.0,cloth.end.x-x)
			draw_rect(Rect2(x,cloth.position.y,w,cloth.size.y),Color(0.85,0.85,0.85,0.08) if fold%2 == 0 else Color(0.10,0.10,0.10,0.14))
			x += 7.0
			fold += 1
		draw_line(cloth.position,Vector2(cloth.end.x,cloth.position.y),Color("7a7a7a",0.72),1.2)
		draw_line(Vector2(cloth.position.x,cloth.end.y),cloth.end,Color("7a7a7a",0.72),1.2)
		var edge: float = cloth.end.x if side == 0 else cloth.position.x
		draw_line(Vector2(edge,r.position.y),Vector2(edge,r.end.y),Color("a8a8a8",0.88),2.0)

func _draw() -> void:
	if font == null or model == null: return
	# The page, its sky and frame hold still while a menu page's content rises in (see _process).
	ui_xform = Transform2D(0.0,Vector2(0,-position.y)) # tf() inside the landscape keeps this offset
	draw_set_transform_matrix(ui_xform)
	draw_texture_rect(PAPER,Rect2(Vector2.ZERO,L.VIEWPORT_SIZE),false,PAPER_TINT)
	if screen != "battle": draw_landscape(L.PAGE_FRAME.grow(-7),0.46)
	panel(L.PAGE_FRAME,Color(0.85,0.74,0.53,0.15))
	ui_xform = Transform2D.IDENTITY
	draw_set_transform_matrix(ui_xform)
	if screen == "battle": draw_battle()
	elif screen == "adventure": adventure.paint(self)
	elif screen == "rogue": rogue.paint(self)
	elif screen == "adventure_finale": adventure.finale.paint(self)
	elif screen == "adventure_ending": adventure.ending.paint(self)
	elif screen == "road_toll_story": adventure.active_story().paint(self)
	elif screen == "recap":
		panel(Rect2(100,70,1400,700))
		label_at(Vector2(140,128),"戰局復盤",38)
		review.draw_charts(self)
	elif screen == "codex": library.draw_catalog()
	elif screen == "battle_info": library.draw_battle_info()
	elif screen == "deck": draw_deck()
	elif screen == "watch": draw_watch()
	elif screen == "net": draw_net()
	elif screen == "help": draw_help()
	elif screen == "settings": preload("res://settings_screen.gd").paint(self)
	else: draw_title()
	if screen == "battle" and model != null and model.time_stopped(): draw_time_stop()

# 時空凝滯 no longer stops the player's hands (2026-11-19): only the caster's enemies freeze.
func ui_time_locked() -> bool:
	return false

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
	draw_rect(Rect2(Vector2.ZERO,L.VIEWPORT_SIZE),Color(0.16,0.19,0.34,0.08*fade))
	# Concentric space ripples expand from the caster over the whole page, including UI.
	for i: int in range(3):
		var wave: float = age*1100-i*95
		if wave > 0 and wave < 2100:
			draw_arc(model.time_stop_origin,wave,0,TAU,128,Color(0.7,0.77,0.95,0.65*fade),4,true)
	panel(Rect2(590,102,420,44),Color("d9d9df"),Color("666681"))
	draw_string(font,Vector2(590,132),("時空凝滯 · 敵軍凍結 %.1f 秒" if model.time_stop_team == me else "時空凝滯 · 我軍被凍結 %.1f 秒") % model.time_stop_left,HORIZONTAL_ALIGNMENT_CENTER,420,24,Color("46435f"))

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

func biome_palette() -> Array:
	return preload("res://season.gd").tint(base_biome_palette(),model.season if model != null else "")

func base_biome_palette() -> Array:
	var bm: String = model.biome if model != null else ""
	match bm:
		"river": return [Color("7c9268"), Color("4a7378"), Color("c6bc8c"), Color("446858"), Color("c5bf8a")]
		"spire": return [Color("7a828f"), Color("4c5b7c"), Color("b6b3c7"), Color("4c5875"), Color("b2b7ce")]
		"marsh": return [Color("686670"), Color("4b3e5a"), Color("7d856a"), Color("483f57"), Color("7d8968")]
		"crater": return [Color("8d745a"), Color("6b4532"), Color("c29b68"), Color("6b4832"), Color("c49f6c")]
	return [Color("81975e"), Color("566f40"), Color("bcc78a"), Color("4f683b"), Color("c2cb8d")]

func draw_battle_landscape(field: Rect2) -> void:
	var pal := biome_palette()
	draw_rect(field,pal[0])
	# Stable pigment washes and ground details; never touch the simulation RNG.
	for i: int in range(42):
		var center := field.position+Vector2(60+scenery_noise(i,1)*(field.size.x-120),35+scenery_noise(i,2)*(field.size.y-70))
		ground_wash(center,Vector2(35+scenery_noise(i,3)*65,14+scenery_noise(i,4)*22),pal[1] if i%3 == 0 else pal[2],i,0.035)
	for lane: int in range(L.GRID_ROWS):
		var path := PackedVector2Array()
		for i: int in range(33):
			path.append(Vector2(220+i*36.25,L.cell_center(Vector2i(0,lane)).y+25+sin(i*0.34+lane)*5))
		draw_polyline(path,Color(0.68,0.60,0.40,0.09),20,true)
		draw_polyline(path,Color(0.74,0.67,0.45,0.07),9,true)
	preload("res://season.gd").ground(self,Rect2(L.GRID_ORIGIN,L.GRID_SIZE)) # 春花、夏草、秋葉、冬雪
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
	cinematic.begin_field(self)
	var field: Rect2 = L.FIELD_FRAME
	draw_texture_rect_region(PAPER,field.grow(24),Rect2(field.position*0.6,field.size*0.6),FIELD_TINT)
	draw_battle_landscape(field.grow(20))
	cinematic.paint_ground(self,field)
	var corner := Vector2(96,86)
	draw_texture_rect(ART.ornament(0),Rect2(field.position+Vector2(8,8),corner),false,Color(1,1,1,0.85))
	draw_texture_rect(ART.ornament(1),Rect2(Vector2(field.end.x-8-corner.x,field.position.y+8),corner),false,Color(1,1,1,0.85))
	draw_texture_rect(ART.ornament(2),Rect2(Vector2(field.position.x+8,field.end.y-8-corner.y),corner),false,Color(1,1,1,0.85))
	draw_texture_rect(ART.ornament(3),Rect2(field.end-Vector2(8,8)-corner,corner),false,Color(1,1,1,0.85))
	# The castles are scenery: drawn a little muted so the gates and troops lead the eye.
	draw_texture_rect(art("castle_wall",0),L.CASTLE_RECTS[0],false,CASTLE_SHADE)
	if not preload("res://camp_art.gd").backdrop(self,1): draw_mirrored(art("castle_wall",1),L.CASTLE_RECTS[1],CASTLE_SHADE) # 強盜關畫營地（camp_art.gd）
	var grid := Rect2(L.GRID_ORIGIN,L.GRID_SIZE)
	draw_ground(grid)
	for lane: int in model.water_lanes:
		draw_water_band(Rect2(grid.position.x,grid.position.y+lane*L.CELL_SIZE.y,grid.size.x,L.CELL_SIZE.y),false)
	for col: int in model.water_cols:
		draw_water_band(Rect2(grid.position.x+col*L.CELL_SIZE.x,grid.position.y,L.CELL_SIZE.x,grid.size.y),true)
	preload("res://terrain_art.gd").mechanics(self) # 上坡、泥沼、熔岩、符文、傳送門、水閘、落石
	for wcell: Vector2i in model.water_cells:
		if wcell.y in model.active_lanes: preload("res://terrain_art.gd").pond(self,Rect2(L.GRID_ORIGIN+Vector2(wcell)*L.CELL_SIZE,L.CELL_SIZE))
	for lane: int in model.wind_lanes:
		draw_wind_band(Rect2(grid.position.x,grid.position.y+lane*L.CELL_SIZE.y,grid.size.x,L.CELL_SIZE.y),int(model.wind_dir.get(lane,1)))
	for bcell: Vector2i in model.blocked_cells:
		if bcell.y in model.active_lanes:
			preload("res://terrain_art.gd").outcrop(self,Rect2(L.GRID_ORIGIN+Vector2(bcell)*L.CELL_SIZE,L.CELL_SIZE))
	preload("res://closed_lanes.gd").draw(self) # 未開放的路：五段城牆照畫，路面封死（closed_lanes.gd）
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
			for row: int in range(L.GRID_ROWS):
				for col: int in range(9):
					var cell := Vector2i(col,row)
					if model.can_play(me,selected,L.cell_center(cell)):
						var r := Rect2(L.GRID_ORIGIN+Vector2(cell)*L.CELL_SIZE,L.CELL_SIZE).grow(-5)
						var glow := 0.0 if place_flash <= 0 else 0.5+0.5*sin(place_flash*18)
						draw_rect(r,Color(1.0,0.93,0.55,0.22+0.30*glow))
						draw_rect(r,Color(0.85,0.65,0.15,0.7+0.3*glow),false,2+3*glow)
	for lane: int in range(L.GRID_ROWS+1):
		if not lane in model.active_lanes and not lane-1 in model.active_lanes: continue
		var y := grid.position.y+lane*L.CELL_SIZE.y
		ink_line(Vector2(grid.position.x,y),Vector2(grid.end.x,y),lane,Color(INK,0.55 if lane == 0 or lane == L.GRID_ROWS else 0.38),2.0)
	for lane: int in model.active_lanes:
		var tab := Rect2((grid.end.x-34) if mirror_view else (grid.position.x+4),grid.position.y+lane*L.CELL_SIZE.y+5,30,20)
		draw_rect(tab,Color(0.95,0.90,0.78,0.85))
		draw_rect(tab,Color(INK,0.5),false,1)
		field_text(tab.position+Vector2(0,15),ROMAN[model.active_lanes.find(lane)],HORIZONTAL_ALIGNMENT_CENTER,tab.size.x,14,INK)
	review.draw_pressure(self) # danger glow sits on the ground, under the troops
	for lane: int in model.active_lanes:
		for team: int in range(2):
			if model.gates[team][lane] <= 0: draw_wall_section(team,lane,true)
	for b: Dictionary in model.buildings:
		team_shadow(b.pos+Vector2(0,30),40,Color(0.25,0.17,0.08))
		draw_combat_actor(b.kind,b,b.pos,1.0 if b.team == 0 else -1.0)
		if b.hp < b.max_hp and not preload("res://glutton_nest.gd").hidden(b): bar(Rect2(b.pos-Vector2(30,43),Vector2(60,5)),b.hp,b.max_hp,RED if b.team == 0 else BLUE)
		# Farm progress toward the next gold drop; brighter while doubled (farmer or 豐收).
		if b.kind == "farm": draw_farm_overlay(b)
		elif b.kind == "grave":
			bar(Rect2(b.pos+Vector2(-30,36),Vector2(60,5)),b.production,B.CARDS.grave.period,Color("a885af"))
		elif b.kind == "crystal":
			bar(Rect2(b.pos+Vector2(-30,36),Vector2(60,5)),b.production,Arcane.crystal_period(b),Color("4fc3f7"))
		elif b.kind == "granary":
			bar(Rect2(b.pos+Vector2(-30,36),Vector2(60,5)),b.get("stored_gold",0.0),B.CARDS.granary.store_max,Color("e5b93b"))
		elif b.kind == "blood_altar":
			bar(Rect2(b.pos+Vector2(-30,36),Vector2(60,5)),b.get("tithe_blood",0.0),B.CARDS.blood_altar.tithe_goal,Color("9b2f2f"))
		preload("res://faction_cards.gd").draw_bar(self,b)
		preload("res://seal_altar.gd").draw_bar(self,b)
		if fx_enabled and b.kind == "blood_tower": preload("res://blood_tower_fx.gd").tower(self,b)
	draw_relations()
	for zone: Dictionary in model.zones:
		var zrect: Rect2 = zone.get("rect",Rect2())
		if zrect.size != Vector2.ZERO:
			draw_rect(zrect,Color("115224",0.22))
			draw_rect(zrect,Color("1b6e32",0.80),false,2.2)
			draw_fitted(art("plague"),Rect2(zrect.get_center()-Vector2(64,64),Vector2(128,128)),Color(0.75,1.0,0.80,0.45))
		else:
			draw_circle(zone.pos,zone.radius,Color("115224",0.24))
			draw_arc(zone.pos,zone.radius,0,TAU,40,Color("1b6e32",0.75),2.0,true)
			draw_fitted(art("plague"),Rect2(zone.pos-Vector2.ONE*zone.radius*0.65,Vector2.ONE*zone.radius*1.3),Color(0.75,1.0,0.80,0.45))
	for pool: Dictionary in model.get_meta("pitch_pools",[]):
		var prect: Rect2 = pool.get("rect",Rect2())
		if prect.size != Vector2.ZERO:
			draw_rect(prect,Color(0.95,0.38,0.08,0.24))
			draw_rect(prect,Color(1.0,0.52,0.14,0.82),false,2.4)
	preload("res://faction_cards.gd").draw(self)
	layout_formations()
	var ordered: Array = model.units.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.draw.y < b.draw.y)
	for u: Dictionary in ordered:
		if not model.mech.is_empty() and preload("res://map_mech.gd").hidden(model,u,me): continue # 濃霧裡的敵兵
		draw_unit(u)
	preload("res://faction_cards.gd").draw_over(self)
	var pulse := 0.5+0.5*sin(model.elapsed*10.0)
	for lane: int in model.active_lanes:
		var y := L.cell_center(Vector2i(0,lane)).y
		for team: int in range(2):
			var x := L.gate_icon_x(team)
			var standing: bool = model.gates[team][lane] > 0
			if standing: draw_wall_section(team,lane,false)
			if standing and model.gates[team][lane] < B.GATE_HP:
				bar(Rect2(x-22,y+45,44,4),model.gates[team][lane],B.GATE_HP,RED if team == 0 else BLUE)
		var gx := L.gate_icon_x(0)
		if me != 0: continue
		if model.alarm[lane] > 0: draw_arc(Vector2(gx,y-8),40+4*pulse,0,TAU,28,Color(RED,0.5+0.4*pulse),3)
		elif model.building_alarm[lane] > 0: draw_arc(Vector2(gx,y-8),40,0,TAU,28,Color(0.85,0.6,0.1,0.7),2)
	Details.draw_breach_smoke(self)
	for lord: Dictionary in model.lords: draw_lord(lord)
	for arrow: Dictionary in model.projectiles:
		Details.draw_projectile(self,arrow)
	draw_preview()
	if selected < 0: preload("res://grid_rules.gd").draw_hover(self,field_mouse()) # a damage building's reach
	draw_effects()
	preload("res://season.gd").weather(self,Rect2(L.GRID_ORIGIN,L.GRID_SIZE)) # 飄落的花瓣、落葉、雪
	preload("res://terrain_art.gd").storms(self)
	preload("res://terrain_art.gd").fog(self)
	DayCycle.light(self,L.FIELD_FRAME.grow(-7))
	cinematic.paint_atmosphere(self,field)
	cinematic.end_field(self)
	mask_field_margins(field)
	ink_frame(field)
	cinematic.paint_screen_overlay(self,field)
	if not cinematic.theater_mode:
		draw_hud() # includes the 戰局資料 seal beside the dial
		draw_hud_effects()
	Ceremony.intro(self)
	if net != null: draw_net_status()
	if model.ended and not model.time_stopped(): draw_result()
	else: draw_pause_overlay()
	adventure.coach.paint(self) # 冒險教學：步驟提示、高亮、新敵人說明、失敗提示（tutorial_coach.gd）

# Pause (2026-11-21 restyle): the field dims and a walnut banner unrolls from the middle, its
# buttons slanted vellum plates that rise under the mouse.
func draw_pause_overlay() -> void:
	if model.ended and not model.time_stopped(): return
	var pf: float = polish.get_pause_fade(self)
	if pf <= 0.01: return
	var ease_pf: float = polish.ease_out(pf)
	draw_rect(Rect2(Vector2.ZERO,L.VIEWPORT_SIZE),Color(0.10,0.07,0.04,0.36*pf))
	var box := L.OVERLAY_RECT
	var half := (box.size.x*0.5+70.0)*ease_pf
	var cx := box.get_center().x
	var y0 := box.position.y-6.0
	var y1 := box.end.y+6.0
	var notch := 26.0*ease_pf
	var banner := PackedVector2Array([Vector2(cx-half,y0),Vector2(cx+half,y0),Vector2(cx+half-notch,(y0+y1)*0.5),Vector2(cx+half,y1),Vector2(cx-half,y1),Vector2(cx-half+notch,(y0+y1)*0.5)])
	var shadow := PackedVector2Array()
	for p: Vector2 in banner: shadow.append(p+Vector2(4,7))
	draw_colored_polygon(shadow,Color(0,0,0,0.30*pf))
	draw_colored_polygon(banner,Color(Color("3a2a1c"),0.97*pf))
	draw_texture_rect(PAPER,Rect2(cx-half,y0,half*2.0,y1-y0),false,Color(1,0.9,0.75,0.06*pf))
	for y: float in [y0+7.0,y1-7.0]: draw_line(Vector2(cx-half+12,y),Vector2(cx+half-12,y),Color(Color("d2ad58"),0.85*pf),1.6,true)
	var rim := banner.duplicate()
	rim.append(banner[0])
	draw_polyline(rim,Color(0.08,0.05,0.03,pf),2.0,true)
	if ease_pf < 0.6: return
	var ta := (ease_pf-0.6)/0.4*pf
	draw_fitted(ART.ornament(4),Rect2(cx-90,box.position.y+4,180,24),Color(1,0.9,0.7,ta))
	draw_string(font,Vector2(box.position.x,box.position.y+62),"戰局暫停",HORIZONTAL_ALIGNMENT_CENTER,box.size.x,32,Color(Color("fff0ca"),ta))
	draw_string(font,Vector2(box.position.x,y1+28),"空白鍵繼續",HORIZONTAL_ALIGNMENT_CENTER,box.size.x,16,Color(1.0,0.96,0.86,0.85*ta))
	var mouse := get_global_mouse_position()
	for item: Array in overlay_buttons():
		var br: Rect2 = item[0]
		var hv: float = polish.hover_val("pause_"+String(item[1]),br.has_point(mouse),is_processing())
		br.position.y -= 3.0*hv
		var plate := PackedVector2Array([br.position+Vector2(8,0),Vector2(br.end.x,br.position.y),Vector2(br.end.x-8,br.end.y),Vector2(br.position.x,br.end.y)])
		var ps := PackedVector2Array()
		for p: Vector2 in plate: ps.append(p+Vector2(2,4+2*hv))
		draw_colored_polygon(ps,Color(0,0,0,0.35*ta))
		draw_colored_polygon(plate,Color(Color("eedfba").lerp(Color("fff6de"),hv),ta))
		var pr := plate.duplicate()
		pr.append(plate[0])
		draw_polyline(pr,Color(Color("d2ad58") if hv > 0.01 else INK,ta),1.6+hv,true)
		draw_string(font,br.position+Vector2(0,27),item[1],HORIZONTAL_ALIGNMENT_CENTER,br.size.x,20,Color(RED if hv > 0.5 else INK,ta))

func draw_hud_effects() -> void:
	if not fx_enabled: return
	for e: Dictionary in effects:
		var progress: float = 1.0 - e.life / e.duration
		match e.kind:
			"ink": Details.draw_ink_hud(self,e,progress)
			"ramp":
				var dial: Vector2 = preload("res://battle_hud.gd").DIAL
				for k: int in range(3):
					draw_arc(dial,34+fmod(progress*1.5+k/3.0,1.0)*64,0,TAU,40,Color(0.88,0.69,0.17,(1-progress)*0.7),3)
			"nightfall": DayCycle.toll_hud(self,e,progress)

func mask_field_margins(field: Rect2) -> void:
	var scale := PAPER.get_size()/L.VIEWPORT_SIZE
	var strips := [
		Rect2(0,0,L.VIEWPORT_SIZE.x,field.position.y),
		Rect2(0,field.end.y,L.VIEWPORT_SIZE.x,L.VIEWPORT_SIZE.y-field.end.y),
		Rect2(0,field.position.y,field.position.x,field.size.y),
		Rect2(field.end.x,field.position.y,L.VIEWPORT_SIZE.x-field.end.x,field.size.y),
	]
	for r: Rect2 in strips:
		draw_texture_rect_region(PAPER,r,Rect2(r.position*scale,r.size*scale),PAPER_TINT)
		var inner := r.intersection(L.PAGE_FRAME)
		if inner.has_area(): draw_rect(inner,Color(0.85,0.74,0.53,0.15))
	panel(L.PAGE_FRAME,Color(0,0,0,0))

func draw_farm_overlay(b: Dictionary) -> void:
	var doubled: bool = maxf(b.boost_until,b.harvest_until) > model.elapsed
	bar(Rect2(b.pos+Vector2(-30,36),Vector2(60,5)),b.production,B.FARM_INTERVAL,Color("f2c230") if doubled else Color("c8962c"))
	if b.boost_until > model.elapsed:
		tf(b.pos+Vector2(0,22),0,Vector2(1,0.38))
		draw_circle(Vector2.ZERO,46+3*sin(model.elapsed*4),Color(1.0,0.82,0.30,0.30))
		tf()

func result_title() -> String:
	return Ceremony.title(self)+"　"+Ceremony.story(self)

# The closing page: who won and how, with both sides' figures (battle_ceremony.gd).
func draw_result() -> void:
	Ceremony.result(self)
	if result_age >= Ceremony.PANEL_DELAY + Ceremony.PANEL_IN and recorder.has_saved_replay() and not OS.has_feature("web"):
		var msg := ""
		var col := Color("4f4331")
		match recorder.export_state:
			"done":
				msg = "已儲存 MP4 與剪輯筆記：%s" % recorder.mp4_path.get_file()
				col = Color("2d5f2e")
			"rendering":
				msg = "正在背景渲染 60fps MP4（完成將自動開啟資料夾）· 剪輯筆記已就緒"
				col = Color("7d4f1c")
			"error":
				msg = "MP4 轉檔失敗（重播檔與剪輯筆記已保存於 recordings/）"
				col = RED
			_:
				msg = "已自動保存重播與 YT 剪輯筆記：%s（點「輸出 MP4」即可產片）" % recorder.notes_path.get_file()
		draw_string(font, Vector2(RESULT_RECT.position.x + 24, RESULT_RECT.end.y + 24), msg, HORIZONTAL_ALIGNMENT_CENTER, RESULT_RECT.size.x - 48, 15, col)

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

# Water lanes (horizontal) or water columns (vertical): non-buildable, slows ground units by 60%.
func draw_water_band(lr: Rect2, vertical: bool) -> void:
	draw_rect(lr,Color("2f6c96",0.44))
	if vertical:
		draw_rect(Rect2(lr.position,Vector2(6.0,lr.size.y)),Color("1f4663",0.48))
		draw_rect(Rect2(Vector2(lr.end.x-6.0,lr.position.y),Vector2(6.0,lr.size.y)),Color("1f4663",0.48))
		var flow := fmod(clock*38.0,88.0)
		for wi: int in range(10):
			var wx := lr.position.x + 18.0 + float((wi*29)%62)
			var wy := lr.position.y + fmod(wi*68.0 + flow, lr.size.y - 36.0) + 10.0
			draw_line(Vector2(wx,wy),Vector2(wx,wy+24.0),Color("c8ecff",0.50),1.8,true)
			draw_line(Vector2(wx+7.0,wy+10.0),Vector2(wx+7.0,wy+30.0),Color("8bc9ea",0.38),1.3,true)
		field_text(Vector2(lr.position.x+4.0,lr.position.y+20.0),"水路 禁建/-60%",HORIZONTAL_ALIGNMENT_CENTER,lr.size.x-8.0,12,Color("e8f6ff",0.88))
	else:
		draw_rect(Rect2(lr.position,Vector2(lr.size.x,6.0)),Color("1f4663",0.48))
		draw_rect(Rect2(Vector2(lr.position.x,lr.end.y-6.0),Vector2(lr.size.x,6.0)),Color("1f4663",0.48))
		var flow := fmod(clock*38.0,88.0)
		for wi: int in range(14):
			var wx := lr.position.x + fmod(wi*88.0 + flow, lr.size.x - 42.0) + 12.0
			var wy := lr.position.y + 18.0 + float((wi*29)%52)
			draw_line(Vector2(wx,wy),Vector2(wx+26.0,wy),Color("c8ecff",0.50),1.8,true)
			draw_line(Vector2(wx+10.0,wy+6.0),Vector2(wx+32.0,wy+6.0),Color("8bc9ea",0.38),1.3,true)
		field_text(lr.position+Vector2(44.0,22.0),"水路 · 禁建／非飛行 -60% 速",HORIZONTAL_ALIGNMENT_LEFT,320.0,13,Color("e8f6ff",0.86))

func draw_wind_band(lr: Rect2, dir: int = 1) -> void:
	draw_rect(lr,Color("d8a93e",0.16))
	var flow := fmod(clock*95.0,96.0)
	for wi: int in range(12):
		var wx := lr.position.x + fmod(wi*96.0 + flow, lr.size.x - 42.0) + 12.0
		if dir < 0: wx = lr.end.x - (wx - lr.position.x)
		var wy := lr.position.y + 18.0 + float((wi*23)%48)
		draw_polyline(PackedVector2Array([Vector2(wx,wy-5),Vector2(wx+9*dir,wy),Vector2(wx,wy+5)]),Color("fff2c4",0.58),2.0,true)
	var tag := "順風 → 往右走的部隊移速升一檔" if dir > 0 else "← 順風 · 往左走的部隊移速升一檔"
	field_text(lr.position+Vector2(44.0,22.0),tag,HORIZONTAL_ALIGNMENT_LEFT,360.0,13,Color("6e4a10",0.88))

# The battlefield floor: tinted zones, alternating lane shade, grass and pebbles, darker edges.
func draw_ground(grid: Rect2) -> void:
	var pal := biome_palette()
	var cw: float = L.CELL_SIZE.x
	var ch: float = L.CELL_SIZE.y
	for lane: int in range(L.GRID_ROWS):
		var row := Rect2(grid.position+Vector2(0,lane*ch),Vector2(grid.size.x,ch))
		if lane % 2 == 1: draw_rect(row,Color(0.25,0.16,0.06,0.06))
	# Irregular clumps rather than identical decorations in every grid cell.
	for i: int in range(175):
		var p := grid.position+Vector2(10+scenery_noise(i,11)*(grid.size.x-20),14+scenery_noise(i,12)*(grid.size.y-28))
		var lane_y := fposmod(p.y-grid.position.y,ch)
		if absf(lane_y-ch*0.5-25) < 14: continue # leave worn paths sparse
		var height := 3.5+scenery_noise(i,13)*6
		var shade: Color = pal[3] if i%3 == 0 else pal[4]
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
	var uid: int = int(u.get("id",0))
	var moving: bool = bool(polish.unit_moving.get(uid,true))
	var u_spawn: float = polish.unit_spawn_progress(uid) if fx_enabled else 1.0
	var bounce := (sin(model.actor_time(u)*8+u.phase)*2.4) if moving else (sin(model.actor_time(u)*3.4+u.phase)*0.6)
	if u.get("flying",false): bounce = -20+sin(model.actor_time(u)*10+u.phase)*5
	if u_spawn < 1.0:
		bounce -= (1.0 - polish.ease_out(u_spawn)) * 14.0
	var rect_top: float = actor_rect(u.kind).position.y
	var ring_r: float = 24.0+(B.actor_radius(u)-B.UNIT_BODY_RADIUS)*0.75
	var hp_y: float = minf(-68.0,rect_top-6.0)
	var top: float = rect_top+bounce
	var is_cursed: bool = u.get("cursed",false) or u.get("cursed_until",0.0) > model.elapsed
	if is_cursed: top = minf(top,-78)
	if u.hp < u.max_hp: top = minf(top,hp_y-1.0)
	# No push-down for tall troops (producer 2026-11-18): they stay in their lane; the top frame may cover them.
	if u.get("stealthed",false):
		draw_arc(pos+Vector2(0,16),ring_r+3.0,0,PI,16,Color("a8b5c7"),2)
	team_base(pos+Vector2(0,16),ring_r,RED if u.team == 0 else BLUE)
	var tint := Color(1.6,1.6,1.6) if fx_enabled and u.flash > 0 else Color.WHITE
	if u_spawn < 1.0:
		tint.a *= clampf(u_spawn * 2.2, 0.0, 1.0)
	if u.get("phased",false):
		draw_combat_actor(u.kind,u,pos+Vector2(-u.face*12,bounce),u.face,Color(0.65,0.55,1.0,0.16))
		tint = Color(0.8,0.75,1.0,0.5)
	draw_combat_actor(u.kind,u,pos+Vector2(0,bounce),u.face,tint)
	if B.CARDS[u.kind].has("resonance"):
		var strength: float = model.Arcane.resonance(model,u)/B.CARDS[u.kind].resonance_max
		var center := pos+Vector2(0,-32)
		draw_colored_polygon(PackedVector2Array([center+Vector2(0,-7),center+Vector2(5,0),center+Vector2(0,7),center+Vector2(-5,0)]),Color(0.55+0.4*strength,0.4+0.4*strength,0.8+0.2*strength,0.8))
	if model.LordExpansion.active(model,u):
		draw_arc(pos+Vector2(0,-30),ring_r+1.0,0,TAU,24,Color(0.65,0.08,0.18,0.7),2)
		var left: float = (model.vampire_until[u.team]-model.elapsed)/B.LORDS.vampire.blood_duration
		draw_arc(pos+Vector2(0,16),ring_r+1.0,-PI/2,-PI/2+TAU*left,24,Color("bd3d66"),2)
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
		draw_arc(pos+Vector2(0,16),ring_r-4.0,0,TAU,16,Color("64b5f6",0.6),1.5)
	if u.get("root_left",0.0) > 0:
		draw_arc(pos+Vector2(0,16),ring_r-2.0,0,TAU,16,Color("3d2c3e",0.85),2.5)
		for i: int in range(4):
			var rp := pos+Vector2(0,16)+Vector2.from_angle(i*PI*0.5+PI*0.25)*(ring_r-2.0)
			draw_line(rp,rp+Vector2(0,6),Color("3d2c3e",0.85),2.0)
	if (B.CARDS[u.kind].get("charge",false) and not u.get("charged",false) and not u.get("expansion_charged",false)) or u.get("granted_charge",false):
		var c_dir: float = u.face
		var c_col := Color("eb6b34",0.82)
		draw_line(pos-Vector2(c_dir*18,14),pos-Vector2(c_dir*36,14),c_col,2.2)
		draw_line(pos-Vector2(c_dir*14,24),pos-Vector2(c_dir*30,24),c_col,1.8)
		var spear := pos+Vector2(c_dir*18,-20)
		draw_polyline(PackedVector2Array([spear-Vector2(c_dir*6,5),spear+Vector2(c_dir*3,0),spear-Vector2(c_dir*6,-5)]),c_col,2.4)
	var total_poison: int = int(u.get("hex_stacks",0))+int(u.get("poison_stacks",0))
	if total_poison > 0:
		draw_arc(pos+Vector2(0,16),ring_r-4.0,0,TAU,16,Color("115224",0.88),2.4)
		for i: int in range(mini(3+int(total_poison/3),6)):
			var ha: float = model.elapsed*4.0+i*TAU/float(mini(3+int(total_poison/3),6))
			draw_circle(pos+Vector2(cos(ha)*11,-18-fmod(model.elapsed*16+i*6,14)),2.6,Color("1b6e32",0.9))
		field_text(pos+Vector2(-8,-50),("毒×%d" % total_poison) if total_poison > 1 else "毒",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("115224"))
	if u.get("armor",0.0) > 0 or u.get("armor_until",0.0) > model.elapsed:
		draw_arc(pos+Vector2(0,16),ring_r-3.0,0,PI,16,Color("c4a75f",0.85),2.5)
	if u.get("shroud_until",0.0) > model.elapsed:
		draw_circle(pos+Vector2(0,-20),ring_r,Color("5e4b73",0.14))
		draw_arc(pos+Vector2(0,-20),ring_r,0,TAU,24,Color("9f86c0",0.5),1.8)
	if u.get("borrowed_until",-1.0) >= 0:
		draw_arc(pos+Vector2(0,16),ring_r-8.0,0,TAU,16,Color("b9a3d6",0.55),1.5)
	if u.hp < u.max_hp:
		var bar_w: float = maxf(48.0,ring_r*1.8)
		bar(Rect2(pos+Vector2(-bar_w*0.5,hp_y),Vector2(bar_w,5)),u.hp,u.max_hp,RED if u.team == 0 else BLUE)

# Each lane renders a seamlessly tileable fortified stone curtain-wall section (or matching breach).
func draw_wall_section(team: int, lane: int, broken: bool) -> void:
	preload("res://wall_art.gd").section(self,team,lane,broken)

func draw_lord(lord: Dictionary) -> void:
	if lord.hp <= 0: return
	var face := 1.0 if lord.team == 0 else -1.0
	var ring_r: float = 30.0+(B.actor_radius(lord)-B.LORD_BODY_RADIUS)*0.8
	team_shadow(lord.pos+Vector2(0,24),ring_r,Color(0.25,0.17,0.08))
	draw_arc(lord.pos+Vector2(0,24),ring_r,0,TAU,32,Color(0.8,0.6,0.15,0.8),2) # gold ring marks the lords
	var cast_left: float = lord_cast_left[lord.team] if fx_enabled else 0.0
	var cast_dur: float = maxf(0.1, lord_cast_duration[lord.team])
	var cast_k: float = sin(clampf(1.0-cast_left/cast_dur,0.0,1.0)*PI) if cast_left > 0.0 else 0.0
	var ult_cast: bool = lord_cast_spell[lord.team].begins_with("skill:")
	var l_hit: float = polish.lord_flash(lord.team) if fx_enabled else 0.0
	var l_moving: bool = bool(polish.lord_moving.get(lord.team,false))
	var step_bob: float = -absf(sin(model.actor_time(lord)*7.5))*2.5 if (fx_enabled and l_moving) else (sin(model.actor_time(lord)*2.6)*0.7 if fx_enabled else 0.0)
	var draw_pos: Vector2 = lord.pos+Vector2(face*((9.0 if ult_cast else 5.0)*cast_k - 3.0*l_hit),-(14.0 if ult_cast else 6.0)*cast_k + step_bob)
	var l_shade: Color = Color.WHITE.lerp(Color(1.5,1.45,1.35), l_hit*0.85)
	# The art faces right; the blue lord is mirrored so both lords face the enemy.
	draw_combat_actor("lord_"+lord.lord,lord,draw_pos,face,l_shade)
	if cast_left > 0.0: Details.draw_lord_cast_aura(self,lord,cast_left,lord_cast_spell[lord.team])
	if lord.hp < lord.max_hp:
		var bar_y: float = minf(-72.0,actor_rect("lord_"+lord.lord).position.y-6.0)
		bar(Rect2(lord.pos+Vector2(-30,bar_y),Vector2(60,4)),lord.hp,lord.max_hp,RED if lord.team == 0 else BLUE)

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
			var lane := clampi(floori((pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,L.GRID_ROWS-1)
			var start := Vector2(Frontier.start_x(0),L.cell_center(Vector2i(0,lane)).y)
			var finish := Vector2(L.gate_stop(1),start.y)
			draw_line(start,finish,Color(0.8,0.3,0.1,0.18),data.radius*2)
			draw_line(start,finish,color,3)
			for actor: Dictionary in model.units+model.buildings+model.lords:
				if actor.hp > 0 and actor.team == me and (actor.pos.x-start.x)*(1.0 if me == 0 else -1.0) >= -data.radius and absf(actor.pos.y-start.y) <= data.radius:
					draw_arc(actor.pos,32,0,TAU,24,Color(1,0.15,0.1,0.85),3,true)
			draw_circle(start,data.radius,color,false,2)
			return
		var srect: Rect2 = B.spell_rect(pos,data)
		var sh: Vector2i = B.spell_shape(data)
		var legal: bool = model.can_play(me,selected,pos)
		var stroke := Color(0.28,0.85,0.42,0.92) if legal else Color(0.92,0.22,0.18,0.92)
		draw_rect(srect,color)
		for gc: int in range(1,sh.x):
			var lx: float = srect.position.x+float(gc)*L.CELL_SIZE.x
			draw_line(Vector2(lx,srect.position.y),Vector2(lx,srect.end.y),Color(stroke,0.50),1.4)
		for gr: int in range(1,sh.y):
			var ly: float = srect.position.y+float(gr)*L.CELL_SIZE.y
			draw_line(Vector2(srect.position.x,ly),Vector2(srect.end.x,ly),Color(stroke,0.50),1.4)
		draw_rect(srect,stroke,false,2.8)
		field_text(srect.position+Vector2(6,16),"%d×%d %s" % [sh.x,sh.y,B.spell_shape_tag(sh)],HORIZONTAL_ALIGNMENT_LEFT,160.0,12,Color(1,0.98,0.90,0.95))
		return
	var cell: Vector2i = model.cell_at(pos)
	if cell.x < 0: return
	var Grid = preload("res://grid_rules.gd")
	if data.type == "building":
		draw_card_art(kind,Rect2(L.cell_center(cell)-Vector2(45,40),Vector2(90,80)),0,Color(1,1,1,0.5))
		Grid.draw_reach(self,kind,cell,me) # cells it will shoot at
	if data.type == "unit" and Grid.footprint(kind) != Vector2i(1,1):
		var fits: bool = model.can_play(me,selected,pos)
		Grid.draw_cells(self,Grid.footprint_cells(kind,cell,me,model.active_lanes),Color(0.2,0.7,0.3,0.22) if fits else Color(0.8,0.1,0.1,0.22),Color(0.28,0.85,0.42,0.9) if fits else Color(0.92,0.22,0.18,0.9))
		if fits: Grid.draw_spawn_preview(self,kind,cell,me) # ghosts where the squads will stand
		return
	if data.type == "unit" and model.can_play(me,selected,pos): Grid.draw_spawn_preview(self,kind,cell,me)
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
			if not lane in model.active_lanes: continue
			var col: int = model.deployment_column(me,lane,cell.x)
			if col >= 0: draw_line(L.cell_center(Vector2i(col,lane)),Vector2(L.gate_stop(1),L.cell_center(Vector2i(0,lane)).y),color,3)
		if kind == "farmer":
			for b: Dictionary in model.buildings:
				if b.kind == "farm" and b.team == me and b.cell.y == cell.y and (b.cell.x-cell.x)*(1 if me == 0 else -1) >= 0: draw_circle(b.pos,40,color,false,3)

# Colours of the cause-and-effect links (battle.gd link()): one family per relation.
const LINK_COLORS := {"repair":Color("c4a75f"),"soul":Color("b9a3d6"),"devour":Color("9b2f2f"),"summon":Color("7b4fa0"),"heal":Color("5ce675"),"harvest":Color("e2b23a"),"curse":Color("926c9d"),"mana":Color("4fc3f7"),"lightning":Color("cfe8ff")}

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
			"trap_blast": FxPolish.explosion(self,e,progress)
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
			"blood_gain": FxPolish.blood_gain(self,e,progress)
			"repair": FxPolish.repair(self,e,progress)
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
			"catapult_fire": FxPolish.catapult_fire(self,e,progress)
			"curse_rise": FxPolish.curse_rise(self,e,progress)
			"witch_curse":
				var wr: float = e.get("radius",75.0)*(0.3+progress*0.7)
				draw_circle(e.pos,wr,Color("115224",(1-progress)*0.24))
				draw_arc(e.pos,wr,0,TAU,28,Color("1b6e32",(1-progress)*0.90),2.8,true)
				for i: int in range(6):
					var wa: float = i*TAU/6.0+progress*0.6
					draw_circle(e.pos+Vector2(cos(wa)*wr*0.68,sin(wa)*wr*0.28-progress*14),3.0*(1-progress),Color("298a43",1-progress))
			"stone_impact": FxPolish.stone_impact(self,e,progress)
			"summoned": FxPolish.summon(self,e,progress,(RED if e.team == 0 else BLUE).lightened(0.35))
			"boneburst": FxPolish.boneburst(self,e,progress)
			"skill": draw_skill_effect(e,progress)
			"levy_summon": FactionVisuals.summon(self,e.pos,progress)
			"levy_dust": FactionVisuals.dust(self,e.pos,progress)
			"link":
				if e.style == "lightning": FactionVisuals.lightning(self,e,progress)
				else: draw_link(e.pos,e.to,LINK_COLORS.get(e.style,INK),progress)
			"slash": draw_slash(e.pos.x,e.lane,progress,e.team)
			"ink": pass # drawn in draw_hud_effects() so coins fly cleanly into the HUD purse
			"hit": FxPolish.hit_spark(self,e,progress)
			"wall_chip": FxPolish.wall_chip(self,e,progress)
			"spell":
				if not FxPolish.spell(self,e,progress) and not FactionVisuals.spell(self,e,progress):
					var srect: Rect2 = e.get("rect",Rect2())
					if srect.size != Vector2.ZERO:
						draw_rect(srect,Color(0.82,0.34,0.12,(1.0-progress)*0.24))
						draw_rect(srect,Color(0.96,0.55,0.18,(1.0-progress)*0.88),false,3.0)
					else:
						draw_circle(e.pos,e.get("radius",50.0)*progress,Color(0.7,0.3,0.1,e.life*0.4))
			"cultivate", "hoe": FxPolish.cultivate(self,e,progress)
			"play": Details.draw_play(self,e,progress)
			"death": Details.draw_death(self,e,progress)
			"burn": FxPolish.burn(self,e,progress)
			"breach":
				for i: int in range(8):
					var ba := TAU * float(i) / 8.0 + 0.35
					var bp: Vector2 = e.pos + Vector2(cos(ba)*progress*64.0, sin(ba)*progress*28.0 - sin(progress*PI)*34.0)
					draw_circle(bp, 3.8*(1.0-progress*0.5), Color("6e4825", 1.0-progress))
				# The whole lane flashes: red when it is our gate, gold when we broke theirs.
				var ours: bool = e.team != me
				var flash := Color(RED if ours else Color("e0b02c"),(1-progress)*(0.22+0.16*sin(progress*40)))
				var lane_y: float = L.GRID_ORIGIN.y+e.lane*L.CELL_SIZE.y
				draw_rect(Rect2(L.FIELD_FRAME.position.x+6,lane_y,L.FIELD_FRAME.size.x-12,L.CELL_SIZE.y),flash)
				var gate := Vector2(L.gate_icon_x(0 if ours else 1),L.cell_center(Vector2i(0,e.lane)).y)
				for k: int in range(3): draw_arc(gate,30+fmod(progress*2+k/3.0,1.0)*110,0,TAU,40,Color(flash,(1-progress)*0.8),4)
			"ramp": pass # drawn in draw_hud_effects() around the top clock
			"nightfall": DayCycle.toll_field(self,e,progress)
			"heal": FxPolish.heal(self,e,progress)
			"fail":
				var c := Color(0.75,0.12,0.1,1-progress)
				draw_line(e.pos+Vector2(-14,-14),e.pos+Vector2(14,14),c,4)
				draw_line(e.pos+Vector2(-14,14),e.pos+Vector2(14,-14),c,4)
	Details.draw_spells(self)

# Visual-only skill cues: positions were captured at cast time, no battle state is changed.
func draw_skill_effect(e: Dictionary, progress: float) -> void:
	var strength := sin(clampf(progress,0.0,1.0)*PI)
	var team_col: Color = RED if int(e.team) == 0 else BLUE
	var gold := Color(1.0,0.84,0.32,strength*0.92)
	var direction := 1.0 if e.team == 0 else -1.0
	var origin: Vector2 = e.pos + Vector2(0.0,-22.0)
	draw_circle(origin,28.0+progress*56.0,Color(1.0,0.86,0.42,strength*0.26))
	draw_arc(origin,22.0+progress*82.0,0.0,TAU,36,gold,3.2,true)
	draw_arc(origin,14.0+progress*52.0,0.0,TAU,28,Color(team_col.lightened(0.35),strength*0.75),2.2,true)
	for point: Vector2 in e.get("targets",[]):
		var beam_t := clampf(progress*1.65,0.0,1.0)
		var dest := point+Vector2(0.0,-18.0)
		var head := origin.lerp(dest,beam_t)
		var ctrl := origin.lerp(dest,0.5)+Vector2(0.0,-32.0)
		var arc_mid := origin.lerp(ctrl,beam_t).lerp(ctrl.lerp(dest,beam_t),beam_t)
		draw_line(origin,arc_mid,Color(1.0,0.92,0.58,strength*0.72),2.4,true)
		draw_line(arc_mid,head,Color(team_col.lightened(0.45),strength*0.65),2.0,true)
		draw_circle(head,4.5*strength,Color(1.0,0.96,0.82,strength*0.9))
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
			_:
				draw_circle(point+Vector2(0,-16),20.0+progress*36.0,Color(team_col.lightened(0.35),strength*0.24))
				draw_arc(point+Vector2(0,-16),16.0+progress*42.0,0.0,TAU,32,gold,2.4,true)

# The whole battle HUD lives in battle_hud.gd (redone 2026-11-21); this stays as the hook.
func draw_hud(single_lane: bool = false, hide_bottom: bool = false) -> void:
	preload("res://battle_hud.gd").draw(self,single_lane,hide_bottom)

func draw_skill_button() -> void:
	preload("res://battle_hud.gd").skill_button(self)

# A lord row's skill state as a small mark, no words: a glowing gem when it can be cast, a dial
# filling up while it cools, a gold dial filling while it charges, an empty ring when the lord is down.
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
		"充能中":
			var charged := clampf(model.skill_charge[team]/maxf(1.0,model.skill_need(team)),0,1)
			draw_circle(at,8,Color(0.30,0.30,0.31,0.8))
			if charged > 0: draw_colored_polygon(PackedVector2Array([at]+range(25).map(func(i: int) -> Vector2: return at+Vector2.from_angle(-PI/2+TAU*charged*i/24.0)*8)),Color("d9a62e"))
		_:
			draw_arc(at,7,0,TAU,16,Color(0.35,0.35,0.35,0.8),2,true)

# The skill's state in words only (producer 2026-11-03: no countdowns or gold numbers on screen).
func skill_state_text(team: int) -> String:
	var lord: Dictionary = model.lords[team]
	if not B.has_skill(lord.lord): return "沒有技能"
	if lord.hp <= 0: return "領主倒下中"
	if model.skill_cd[team] > 0: return "冷卻中"
	if lord.lord == "underworld" and model.count_buildings(team,"grave") == 0: return "沒有墓碑"
	if not model.skill_charged(team): return "充能中"
	return "可發動"

func try_skill() -> bool:
	if adventure.is_opening() and adventure.opening.active: return false
	var reason: String = model.skill_error(me)
	if reason.is_empty() and net != null:
		net.queue(["s"])
		return true
	if reason.is_empty() and model.cast_skill(me):
		recorder.record_cmd("skill", me)
		return true
	say(reason)
	skill_shake = 0.45
	if model.skill_cd[me] > 0.00001:
		show_cursor_hint("技能冷卻 %.1f秒" % model.skill_cd[me], Color("7d4f1c"))
	elif not model.skill_charged(me):
		show_cursor_hint("充能不足（還差 %d）" % ceili(model.skill_need(me) - model.skill_charge[me]), Color("7d4f1c"))
	else:
		show_cursor_hint(reason, Color("7d4f1c"))
	if sound != null: sound.cue("fail")
	return false

func show_cursor_hint(text: String, color: Color = RED) -> void:
	if text.is_empty(): return
	cursor_hint_text = text
	cursor_hint_color = color
	cursor_hint_left = 1.25

func cursor_status_hint(mouse: Vector2) -> Dictionary:
	if model == null or model.paused or model.ended: return {}
	if selected >= 0 and card_at(mouse) < 0 and (L.FIELD_FRAME.has_point(mouse) or dragging):
		var kind: String = model.kind_at(me,selected)
		if B.CARDS.has(kind):
			var code: int = model.play_check(me,selected,to_model(mouse))
			if code == Battle.Refusal.GOLD:
				var cost: float = float(B.CARDS[kind].cost)
				return {"text": "金幣不足（還差 %d）" % ceili(cost - model.ink[me]), "color": RED}
			elif code == Battle.Refusal.COOLDOWN:
				return {"text": "冷卻中 %.1f秒" % model.slot_cd(me,selected), "color": Color("7d4f1c")}
	if hover_slot >= 0 and card_at(mouse) == hover_slot:
		var hkind: String = model.kind_at(me,hover_slot)
		if B.CARDS.has(hkind):
			var cd: float = model.slot_cd(me,hover_slot)
			var hcost: float = float(B.CARDS[hkind].cost)
			if cd > 0.00001:
				return {"text": "冷卻中 %.1f秒" % cd, "color": Color("7d4f1c")}
			elif model.ink[me] < hcost:
				return {"text": "金幣不足（還差 %d）" % ceili(hcost - model.ink[me]), "color": RED}
	if SKILL_RECT.has_point(mouse) and B.has_skill(model.lords[me].lord) and (model.lord_active[me] or model.lords[me].hp > 0): # no hint over an empty lord plate
		if model.skill_cd[me] > 0.00001:
			return {"text": "技能冷卻 %.1f秒" % model.skill_cd[me], "color": Color("7d4f1c")}
		if not model.skill_charged(me):
			return {"text": "充能 %d / %d（花費或溢出金幣時充能）" % [int(model.skill_charge[me]), roundi(model.skill_need(me))], "color": Color("7d4f1c")}
	if cursor_hint_left > 0.0 and not cursor_hint_text.is_empty():
		return {"text": cursor_hint_text, "color": cursor_hint_color, "timed": true}
	return {}

func draw_cursor_hint(mouse: Vector2) -> void:
	if adventure.is_opening() and adventure.opening.active: return
	var info: Dictionary = cursor_status_hint(mouse)
	if info.is_empty(): return
	var alpha: float = clampf(cursor_hint_left / 0.30, 0.0, 1.0) if info.get("timed", false) else 1.0
	if alpha <= 0.01: return
	var text: String = info.text
	var col: Color = info.color
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var w: float = sz.x + 22.0
	var h: float = 28.0
	var pos := mouse + (Vector2(24.0, -54.0) if dragging else Vector2(18.0, -34.0))
	if pos.x + w > L.VIEWPORT_SIZE.x - 10.0: pos.x = mouse.x - w - 14.0
	if pos.y < 10.0: pos.y = mouse.y + (42.0 if dragging else 24.0)
	var box := Rect2(pos, Vector2(w, h))
	draw_rect(Rect2(box.position + Vector2(1.5, 2.0), box.size), Color("1e150d", 0.28 * alpha))
	panel(box, Color(0.97, 0.92, 0.81, 0.96 * alpha), Color(col, alpha))
	draw_circle(box.position + Vector2(10.0, h * 0.5), 3.2, Color(col, alpha))
	label_at(box.position + Vector2(17.0, 19.5), text, 14, Color(col, alpha))


func leave_net() -> void:
	if net != null: net.close()
	net = null
	me = 0
	mirror_view = false
	field_mirror = false

func _net_input(rect: Rect2, value: String, placeholder: String, on_change: Callable, on_submit: Callable = Callable()) -> LineEdit:
	var edit := LineEdit.new()
	edit.position = rect.position
	edit.size = rect.size
	edit.text = value
	edit.placeholder_text = placeholder
	edit.add_theme_font_override("font",font)
	edit.add_theme_font_size_override("font_size",20)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("f6ead0")
	box.border_color = Color("846539")
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	edit.add_theme_stylebox_override("normal",box)
	edit.add_theme_stylebox_override("focus",box)
	edit.add_theme_color_override("font_color",INK)
	edit.add_theme_color_override("font_placeholder_color",Color("8c7758"))
	edit.text_changed.connect(on_change)
	if on_submit.is_valid(): edit.text_submitted.connect(func(_t: String): on_submit.call())
	add_child(edit)
	ui.append(edit)
	return edit

func practice_lord_options() -> Array:
	return ["random"] + B.lord_menu_order()

func practice_ratio_options() -> Array:
	return ["lord_best"] + DeckStore.practice_ratio_ids() + ["random"]

func _cycle_option(options: Array, current: String, step: int) -> String:
	var idx := options.find(current)
	if idx < 0: idx = 0
	return String(options[(idx + step + options.size()) % options.size()])

func roll_practice_opponent() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool_lords: Array = B.lord_menu_order()
	if practice_lord == "random" or not B.LORDS.has(practice_lord):
		practice_foe_lord = String(pool_lords[rng.randi_range(0,pool_lords.size()-1)])
	else:
		practice_foe_lord = practice_lord
	var ratio_ids := DeckStore.practice_ratio_ids()
	if practice_ratio_id == "lord_best":
		practice_foe_ratio_id = "lord_best"
		practice_foe_deck = DeckStore.balanced_random_deck(rng,practice_foe_lord)
		return
	if practice_ratio_id == "random" or not practice_ratio_id in ratio_ids:
		practice_foe_ratio_id = String(ratio_ids[rng.randi_range(0,ratio_ids.size()-1)])
	else:
		practice_foe_ratio_id = practice_ratio_id
	var ratio_entry := DeckStore.practice_ratio_entry(practice_foe_ratio_id)
	practice_foe_deck = DeckStore.balanced_random_deck(rng,practice_foe_lord,ratio_entry.ratio)

func ensure_practice_opponent() -> void:
	var lord_mismatch := practice_lord != "random" and B.LORDS.has(practice_lord) and practice_foe_lord != practice_lord
	var ratio_mismatch := (practice_ratio_id == "lord_best" and practice_foe_ratio_id != "lord_best") or (practice_ratio_id != "random" and practice_ratio_id != "lord_best" and practice_ratio_id in DeckStore.practice_ratio_ids() and practice_foe_ratio_id != practice_ratio_id)
	if lord_mismatch or ratio_mismatch or practice_foe_lord.is_empty() or not B.LORDS.has(practice_foe_lord) or not DeckStore.valid(practice_foe_deck,practice_foe_lord):
		roll_practice_opponent()

func cycle_practice_lord(step: int) -> void:
	practice_lord = _cycle_option(practice_lord_options(),practice_lord,step)
	roll_practice_opponent()

func cycle_practice_ratio(step: int) -> void:
	practice_ratio_id = _cycle_option(practice_ratio_options(),practice_ratio_id,step)
	roll_practice_opponent()

# Battle Hub: online matchmaking (with optional AI fallback), private room code, and local practice.
func show_net() -> void:
	if not DeckStore.valid(player_deck,player_lord):
		show_deck()
		return
	vs_ai_matched_name = ""
	ensure_practice_opponent()
	if net == null: net = NetMatch.new()
	screen = "net"
	clear_ui()
	var searching: bool = net.state in ["connecting","searching"]
	var waiting_room: bool = net.state == "room_waiting"
	title_button(Rect2(146,298,280,56),"取消搜尋" if searching else "開始搜尋對手",func():
		if searching: net.close()
		else: net.search_match(player_deck,player_lord,difficulty,net_server_url,net_auto_ai)
		show_net(),not searching)
	button(Rect2(442,304,350,44),"無人時自動補 AI：" + ("開啟" if net_auto_ai else "關閉（純真人）"),func():
		net_auto_ai = not net_auto_ai
		show_net())
	button(Rect2(146,542,190,50),"關閉房間" if waiting_room else "建立房間",func():
		if waiting_room: net.close()
		else: net.host_room(player_deck,player_lord,net_server_url)
		show_net())
	var join_action := func():
		net.join_room(net_room_code,player_deck,player_lord,net_server_url)
		show_net()
	_net_input(Rect2(360,542,230,50),net_room_code,"輸入 4 碼房號",func(t: String): net_room_code = t.to_upper(),join_action)
	button(Rect2(604,542,188,50),"加入房間",join_action)
	button(Rect2(896,264,152,44),"難度：" + ["簡單","普通","困難"][difficulty],func():
		difficulty = (difficulty+1)%3
		show_net())
	button(Rect2(1060,264,44,44),"◀",func():
		cycle_practice_lord(-1)
		show_net())
	button(Rect2(1108,264,198,44),"隨機領主" if practice_lord == "random" else B.lord_name(practice_lord),func():
		cycle_practice_lord(1)
		show_net())
	button(Rect2(1310,264,44,44),"▶",func():
		cycle_practice_lord(1)
		show_net())
	button(Rect2(1366,264,106,44),"重抽牌組",func():
		roll_practice_opponent()
		show_net())
	var ratio_btn_text := "配比：領主最佳（隨領主自動配比）" if practice_ratio_id == "lord_best" else ("配比：隨機配比（4 選 1）" if practice_ratio_id == "random" else "配比：%s（%s）" % [DeckStore.practice_ratio_entry(practice_ratio_id).name,DeckStore.practice_ratio_label(DeckStore.practice_ratio_entry(practice_ratio_id).ratio)])
	button(Rect2(896,316,44,42),"◀",func():
		cycle_practice_ratio(-1)
		show_net())
	button(Rect2(944,316,480,42),ratio_btn_text,func():
		cycle_practice_ratio(1)
		show_net())
	button(Rect2(1428,316,44,42),"▶",func():
		cycle_practice_ratio(1)
		show_net())
	title_button(Rect2(896,538,576,58),"立即開始人機對戰",func():
		leave_net()
		spectating = false
		start_battle())
	button(Rect2(1290,678,190,50),"更換牌組",func():
		leave_net()
		show_deck())
	button(Rect2(100,766,200,52),"回到標題",show_title)
	var apply_server := func():
		net_server_url = NetMatch.save_server_url(net_server_url)
		if net != null: net.close()
		show_net()
	_net_input(Rect2(630,768,530,46),net_server_url,"ws:// 或 wss:// 配對伺服器",func(t: String): net_server_url = t,apply_server)
	button(Rect2(1174,768,110,46),"套用",apply_server)
	button(Rect2(1296,768,110,46),"重設",func():
		net_server_url = NetMatch.save_server_url("")
		if net != null: net.close()
		show_net())
	queue_redraw()

func draw_net() -> void:
	label_at(Vector2(100,96),"對戰大廳",44)
	label_at(Vector2(100,132),"搜尋線上真人對手、建立好友房碼，或立即進行單人練習。",19,Color("5a4a36"))
	panel(Rect2(100,152,740,496))
	panel(Rect2(124,174,692,238),Color("f3e5c4"))
	label_at(Vector2(146,212),"線上配對 · 搜尋對手",26)
	label_at(Vector2(146,240),"自動配對目前在線玩家；開啟補 AI 時，若 %d 秒內無真人對手將自動配對 AI。" % int(NetMatch.SEARCH_AI_FALLBACK_SEC),16,Color("5a4a36"))
	var searching: bool = net != null and net.state in ["connecting","searching"]
	if searching:
		var dots := ".".repeat(1 + (int(clock * 3.0) % 3))
		var stats_txt := (" · 在線 %d 人 · 排隊 %d 人" % [net.online_count, net.queued_count]) if net.online_count > 0 else ""
		label_at(Vector2(146,274),"%s%s%s" % [net.message, dots, stats_txt],19,RED)
		var bar := Rect2(146,374,646,16)
		draw_rect(bar,Color("d9c497"))
		var frac := clampf(net.search_elapsed / NetMatch.SEARCH_AI_FALLBACK_SEC,0.0,1.0) if net_auto_ai else fmod(clock * 0.45, 1.0)
		if net_auto_ai:
			draw_rect(Rect2(bar.position,Vector2(bar.size.x * frac,bar.size.y)),Color("963f30"))
		else:
			var seg_w := 140.0
			draw_rect(Rect2(bar.position.x + (bar.size.x - seg_w) * frac,bar.position.y,seg_w,bar.size.y),Color("963f30"))
		draw_rect(bar,Color("846539"),false,1.5)
	elif net != null and not net.message.is_empty() and net.state in ["error","lost"]:
		label_at(Vector2(146,274),net.message,18,RED)
	else:
		label_at(Vector2(146,274),"準備就緒 · 點擊下方按鈕開始配對",18,Color("4f4331"))
	panel(Rect2(124,428,692,198),Color("efe0bd"))
	label_at(Vector2(146,464),"好友私人房（房間代碼）",24)
	label_at(Vector2(146,492),"產生 4 碼房號分享給朋友，或輸入對方的房間代碼加入對戰。",16,Color("5a4a36"))
	if net != null and net.state == "room_waiting":
		label_at(Vector2(146,522),"房間代碼：%s（等待好友加入…）" % net.room_code,20,RED)
	elif net != null and net.state == "joining":
		label_at(Vector2(146,522),net.message,18,Color("7d4f1c"))
	panel(Rect2(868,152,632,496))
	label_at(Vector2(896,206),"單人練習（自由對戰）",26)
	label_at(Vector2(896,236),"可指定或隨機對手領主，並切換領主最佳、4 種編隊配比或隨機配比。",15,Color("5a4a36"))
	panel(Rect2(896,368,576,158),Color("efe0bd"))
	ensure_practice_opponent()
	draw_fitted(lord_art(practice_foe_lord,1),Rect2(912,378,104,138))
	var tag := "（隨機領主）" if practice_lord == "random" else "（指定領主）"
	label_at(Vector2(1034,396),"練習領主：" + B.lord_name(practice_foe_lord) + tag,20)
	label_at(Vector2(1034,424),"技能：%s · 平均費 %.1f" % [B.LORDS[practice_foe_lord].skill,DeckStore.average(practice_foe_deck)],15,Color("5a4a36"))
	label_at(Vector2(1034,454),"、".join(practice_foe_deck.slice(0,4).map(func(k): return B.CARDS[k].name)),16)
	label_at(Vector2(1034,480),"、".join(practice_foe_deck.slice(4,8).map(func(k): return B.CARDS[k].name)),16)
	if practice_foe_ratio_id == "lord_best":
		var best_entry := DeckStore.lord_best_entry(practice_foe_lord)
		label_at(Vector2(1034,510),"領主最佳 · %s：%s" % [best_entry.name,DeckStore.practice_ratio_label(best_entry.ratio)],15,Color("6f5a3e"))
	else:
		var ratio_entry := DeckStore.practice_ratio_entry(practice_foe_ratio_id)
		label_at(Vector2(1034,510),"%s：%s" % [ratio_entry.name,DeckStore.practice_ratio_label(ratio_entry.ratio)],15,Color("6f5a3e"))
	panel(Rect2(100,666,1400,74),Color("efe0bd"))
	var sorted_mine: Array = B.menu_sorted(player_deck)
	draw_string(font,Vector2(124,711),"我的牌組：%s · %s" % [B.LORDS[player_lord].name,"、".join(sorted_mine.map(func(k): return B.CARDS[k].name))],HORIZONTAL_ALIGNMENT_LEFT,1145,19,INK)
	label_at(Vector2(526,798),"配對伺服器",17,Color("6f5a3e"))

func start_net_battle() -> void:
	spectating = false
	adventure.index = -1
	rogue.in_battle = false
	if net.is_ai_match:
		vs_ai_matched_name = net.ai_opponent_name
		me = 0
		mirror_view = false
		field_mirror = false
		model = net.make_battle()
		leave_net()
		enter_battle("已配對對手：" + vs_ai_matched_name)
		return
	vs_ai_matched_name = ""
	me = net.local_team
	mirror_view = me == 1
	model = net.make_battle()
	enter_battle("線上對戰")

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
	vs_ai_matched_name = ""
	adventure.index = -1
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
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("963f30") if primary else Color("e8d6af")
		if state == "hover": style.bg_color = Color("b1533b") if primary else Color("f6e8c9")
		if state == "pressed": style.bg_color = Color("733426") if primary else Color("cdb88f")
		if state == "focus": style.bg_color = Color.TRANSPARENT
		if state == "disabled": style.bg_color = Color("b69c84",0.72) if primary else Color("d8c8a6",0.72)
		style.border_color = Color("d2ad58") if primary or state == "focus" else (Color("9e8864",0.6) if state == "disabled" else Color("92734b"))
		style.set_border_width_all(3 if state == "focus" else 2)
		style.set_corner_radius_all(2)
		control.add_theme_stylebox_override(state,style)
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		control.add_theme_color_override(state,Color("fff0ca") if primary else INK)
	control.add_theme_color_override("font_disabled_color",Color("efe1be",0.75) if primary else Color(INK,0.42))
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

func _deck_filter_button(rect: Rect2, caption: String, action: Callable, active: bool, active_fill: Color) -> Button:
	var b := title_button(rect, caption, action, active)
	b.add_theme_font_size_override("font_size", 14)
	if active:
		for state: String in ["normal","hover","pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = active_fill.lightened(0.12) if state == "hover" else (active_fill.darkened(0.12) if state == "pressed" else active_fill)
			style.border_color = Color("d2ad58")
			style.set_border_width_all(2)
			style.set_corner_radius_all(2)
			b.add_theme_stylebox_override(state, style)
	return b

func _valid_deck_faction() -> String:
	if deck_tab == "lord":
		return deck_faction if deck_faction in ["all","normal","magic","dark","beast"] else "all"
	var lf: String = B.lord_faction(player_lord)
	return deck_faction if deck_faction in ["all",lf,"neutral"] else "all"

func deck_shown_cards() -> Array:
	return CardSort.sort_cards(player_deck, deck_sort, B.lord_faction(player_lord))

func step_deck_page(delta: int, wrap: bool = true) -> void:
	var pages := ceili(tab_size()/float(POOL_PAGE))
	if pages <= 1: return
	var next := ((deck_page + delta + pages) % pages) if wrap else clampi(deck_page + delta, 0, pages - 1)
	if next != deck_page:
		deck_page = next
		if sound != null: sound.cue("page_turn")
		show_deck()

func show_deck() -> void:
	screen = "deck"
	clear_ui()
	if not deck_tab in deck_tabs(): deck_tab = "all"
	deck_faction = _valid_deck_faction()
	var tabs := deck_tabs()
	for i: int in range(tabs.size()):
		var tab: String = tabs[i]
		var t := button(tab_rect(i),"",func(): deck_tab = tab; deck_page = 0; show_deck())
		t.modulate = Color(1,1,1,0.01)
	var Style = preload("res://command_style.gd")
	if deck_tab == "lord":
		var lord_filters := [["all","全陣營"],["normal","經典"],["magic","魔法"],["dark","黑暗"],["beast","魔物"]]
		for i: int in range(lord_filters.size()):
			var fk: String = lord_filters[i][0]
			var fcol: Color = Style.TAGS.get(fk, Color("963f30")) if fk != "all" else Color("963f30")
			_deck_filter_button(Rect2(POOL_X + i * 98.0, FILTER_Y, 92.0, 28.0), lord_filters[i][1], func(): deck_faction = fk; deck_page = 0; show_deck(), deck_faction == fk, fcol)
	else:
		var lf: String = B.lord_faction(player_lord)
		var card_filters := [["all","全部"],[lf,B.FACTIONS[lf]],["neutral","中立"]]
		for i: int in range(card_filters.size()):
			var fk: String = card_filters[i][0]
			var fcol: Color = Style.TAGS.get(fk if fk != "neutral" else "", Color("963f30")) if fk != "all" else Color("963f30")
			_deck_filter_button(Rect2(POOL_X + i * 106.0, FILTER_Y, 98.0, 28.0), card_filters[i][1], func(): deck_faction = fk; deck_page = 0; show_deck(), deck_faction == fk, fcol)
		var pin_btn := title_button(Rect2(1018.0, FILTER_Y, 134.0, 28.0), "已編入優先", func(): deck_in_first = not deck_in_first; deck_page = 0; show_deck(), deck_in_first)
		pin_btn.add_theme_font_size_override("font_size", 14)
		var sort_btn := title_button(Rect2(1162.0, FILTER_Y, 227.0, 28.0), "排序：%s ▾" % CardSort.mode_label(deck_sort), func(): deck_sort = CardSort.next_mode(deck_sort); deck_page = 0; show_deck())
		sort_btn.add_theme_font_size_override("font_size", 14)
	var pages := ceili(tab_size()/float(POOL_PAGE))
	deck_page = clampi(deck_page,0,maxi(0,pages-1))
	if pages > 1:
		title_button(Rect2(POOL_X-70,POOL_Y+110,50,120),"‹",func(): step_deck_page(-1, true))
		title_button(Rect2(POOL_X+8*POOL_STEP.x,POOL_Y+110,50,120),"›",func(): step_deck_page(1, true))
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
	var shown: Array = deck_shown_cards()
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
		title_button(Rect2(120,822,220,50),"返回地圖",func():
			if DeckStore.valid(player_deck,player_lord):
				adventure.custom_deck = player_deck.duplicate()
				adventure.save_progress()
			adventure_deck_mode = false
			show_adventure()
		)
		start_button = title_button(Rect2(1260,822,240,50),"儲存並出征",func():
			adventure.custom_deck = player_deck.duplicate()
			adventure.save_progress()
			adventure_deck_mode = false
			spectating = false
			adventure.start(self,adventure.selected)
		,true)
	elif watch_edit >= 0:
		title_button(Rect2(120,822,220,50),"取消",func(): finish_watch_edit(false))
		start_button = title_button(Rect2(1260,822,240,50),"完成",func(): finish_watch_edit(true),true)
	else:
		title_button(Rect2(120,822,220,50),"回到標題",show_title)
		start_button = title_button(Rect2(1260,822,240,50),"儲存並開戰",func(): spectating = false; start_battle(),true)
	start_button.disabled = not DeckStore.valid(player_deck,player_lord)
	queue_redraw()

# Deck screen (producer 2026-11-05, "army" layout): a frame on top with the lord portrait and the
# deck (home card + 8 slots), a tab bar, filter/sort bar, then the collection in two rows of eight.
const ARMY := Rect2(50,22,1500,298)
const PORTRAIT := Rect2(72,38,196,212)
const SLOT_X := 300.0
const SLOT_Y := 112.0
const SLOT_SIZE := Vector2(128,162)
const SLOT_STEP := 136.0
const TAB_Y := 330.0
const TAB_W := 176.0
const FILTER_Y := 382.0
const POOL_X := 211.0
const POOL_Y := 420.0
const POOL_STEP := Vector2(150,172)
const POOL_CARD := Vector2(128,158)
const POOL_PAGE := 16
const TAB_NAMES := {"all":"全部","melee":"近戰","ranged":"遠程","spell":"法術","building":"建築","lord":"領主"}
const TAB_GROUP := {"melee":0,"ranged":1,"spell":2,"building":3}

func deck_tabs() -> Array:
	var tabs := ["all","melee","ranged","spell","building"]
	if not adventure_deck_mode or adventure.unlocked_lords().size() > 1: tabs.append("lord")
	return tabs

func tab_rect(i: int) -> Rect2:
	var n := deck_tabs().size()
	return Rect2(800-n*TAB_W/2+i*TAB_W,TAB_Y,TAB_W-8,40)

func deck_slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(SLOT_X+i*SLOT_STEP,SLOT_Y),SLOT_SIZE)

func tab_items(tab: String) -> Array:
	if tab == "lord":
		var lords: Array = adventure.unlocked_lords() if adventure_deck_mode else B.lord_menu_order()
		var lf_filter := deck_faction if deck_faction in ["all","normal","magic","dark","beast"] else "all"
		return CardSort.sort_lords(lords, lf_filter)
	var pool: Array = adventure.card_pool() if adventure_deck_mode else DeckStore.pool(player_lord)
	var active_faction := deck_faction if deck_faction in ["all", B.lord_faction(player_lord), "neutral"] else "all"
	var kinds: Array = B.CARDS.keys().filter(func(kind: String) -> bool:
		if not kind in pool: return false
		return CardSort.matches_category(kind, tab) and CardSort.matches_faction(kind, active_faction, false))
	return CardSort.sort_cards(kinds, deck_sort, B.lord_faction(player_lord), player_deck if deck_in_first else [])

func page_items() -> Array:
	return tab_items(deck_tab).slice(deck_page*POOL_PAGE,(deck_page+1)*POOL_PAGE)

func tab_size() -> int:
	return tab_count(deck_tab)

func tab_count(tab: String) -> int:
	return tab_items(tab).size()

func lord_tooltip(kind: String) -> String:
	var info: Dictionary = B.LORDS[kind]
	var atk := "遠程普攻 %d（射程 %d）" % [int(info.damage),int(B.lord_attack_range(kind))] if B.lord_is_ranged(kind) else "普攻 %d" % int(info.damage)
	return "%s（%s）\n%d 血 · %s\n%s" % [info.name,info.role,int(info.hp),atk,B.skill_text(kind)]

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
	if deck_faction != "all" and deck_faction != "neutral" and deck_faction != B.lord_faction(lord):
		deck_faction = "all"
	if adventure_deck_mode: # each adventure lord keeps its own deck
		save_choice()
		adventure.choose_lord(lord)
		adventure.open_adventure_deck(self)
		return
	if watch_edit >= 0: # each watch lord keeps its own deck separately
		if DeckStore.valid(player_deck,player_lord):
			watch_lord_decks[watch_edit][player_lord] = player_deck.duplicate()
			watch_lord_sources[watch_edit][player_lord] = -1
		player_lord = lord
		if watch_lord_decks[watch_edit].has(lord) and DeckStore.valid(watch_lord_decks[watch_edit][lord],lord):
			player_deck = watch_lord_decks[watch_edit][lord].duplicate()
		else:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			player_deck = random_deck(rng,lord)
			watch_lord_decks[watch_edit][lord] = player_deck.duplicate()
			watch_lord_sources[watch_edit][lord] = 0
		menu_notice = ""
		show_deck()
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
	preload("res://interface_ornament.gd").portrait(self,r,tint,chosen)
	draw_fitted(lord_art(kind),Rect2(r.position+Vector2(8,24),Vector2(r.size.x-16,r.size.y-88)),Color.WHITE,true)
	draw_string(font,Vector2(r.position.x,r.end.y-41),info.name,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,19,INK)
	draw_string(font,Vector2(r.position.x,r.end.y-27),info.role,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,16,Color("5a4a36"))
	draw_string(font,Vector2(r.position.x,r.end.y-10),"%s 充能%d" % [info.skill,int(B.skill_charge_need(kind))],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,16,RED)
	var faction: String = B.lord_faction(kind)
	var tag := Rect2(r.position+Vector2(9,7),Vector2(36,17))
	preload("res://interface_ornament.gd").ribbon_tag(self,tag,B.FACTIONS[faction],preload("res://command_style.gd").TAGS.get(faction,Color("7d7466")),12)
	if chosen:
		draw_rect(r.grow(3),RED,false,4)
		draw_check(r.position+Vector2(r.size.x-10,10))

func draw_deck() -> void:
	var muted := Color("5a4a36")
	var mouse := get_global_mouse_position()
	# Army frame.
	panel(ARMY,Color("e6d3a8"),Color("6a5236"))
	draw_rect(ARMY.grow(-6),Color("8a6f4a"),false,1)
	var lord: String = player_lord
	var info: Dictionary = B.LORDS[lord]
	var p_hover := "lord" in deck_tabs() and PORTRAIT.has_point(mouse)
	panel(PORTRAIT,Color("fcf1d5") if p_hover else Color("f6e9c8"),Color("d2ad58") if p_hover else RED)
	draw_fitted(lord_art(lord,maxi(watch_edit,0)),PORTRAIT.grow(-10),Color.WHITE,true)
	draw_string(font,Vector2(PORTRAIT.position.x,PORTRAIT.end.y+26),info.name,HORIZONTAL_ALIGNMENT_CENTER,PORTRAIT.size.x,22,INK)
	draw_string(font,Vector2(PORTRAIT.position.x,PORTRAIT.end.y+47),"%s · 點頭像換領主" % info.role if "lord" in deck_tabs() else "%s · 征服首府可換領主" % info.role,HORIZONTAL_ALIGNMENT_CENTER,PORTRAIT.size.x,13,muted)
	var title := "出征牌組" if adventure_deck_mode else "村莊牌組"
	if watch_edit >= 0: title = "觀戰 · 紅方牌組" if watch_edit == 0 else "觀戰 · 藍方牌組"
	label_at(Vector2(SLOT_X,68),title,30,INK if watch_edit < 0 else (RED if watch_edit == 0 else BLUE))
	var tx: float = SLOT_X+font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,30).x+18
	var comp := CardSort.deck_composition(player_deck)
	label_at(Vector2(tx,66),"%d / 8 · 平均 %.1f 金幣 · 近%d 遠%d 法%d 建%d" % [player_deck.size(),DeckStore.average(player_deck),comp[0],comp[1],comp[2],comp[3]],19,RED if player_deck.size() < 8 else muted)
	draw_string(font,Vector2(SLOT_X,96),B.skill_text(lord),HORIZONTAL_ALIGNMENT_LEFT,1210,17,INK)
	# Home card (fixed) + eight slots.
	var home := deck_slot_rect(0)
	var home_kind: String = B.home_card(lord)
	var home_col: Color = preload("res://command_style.gd").tag_color(home_kind)
	panel(home.grow(4),Color("e8d9b5").lerp(home_col,0.22),home_col.darkened(0.18))
	draw_card(home_kind,home)
	var htag := Rect2(home.position.x+home.size.x*0.5-22,home.end.y-12,44,16)
	preload("res://interface_ornament.gd").ribbon_tag(self,htag,"常駐",home_col.darkened(0.10),12)
	var shown: Array = deck_shown_cards()
	for i: int in range(8):
		var r := deck_slot_rect(i+1)
		if i < shown.size():
			var hv: float = polish.hover_val("deck_slot_%d_%s" % [i, shown[i]], r.has_point(mouse), is_processing())
			r.position.y -= 8.0 * hv
			r = r.grow(3.0 * hv)
			if hv > 0.01: polish.draw_card_hover_glow(self, r, hv)
			draw_card(shown[i],r)
		else:
			draw_rect(r,Color(0.35,0.27,0.16,0.12))
			draw_rect(r.grow(-4),Color(0.42,0.32,0.2,0.45),false,2)
			draw_string(font,Vector2(r.position.x,r.get_center().y+12),"+",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,36,Color(0.42,0.32,0.2,0.5))
	# Tab bar.
	var tabs := deck_tabs()
	var bar := Rect2(tab_rect(0).position-Vector2(8,5),Vector2(tabs.size()*TAB_W+8,50))
	panel(bar,Color("c9b083"),Color("6a5236"))
	for i: int in range(tabs.size()):
		var r := tab_rect(i)
		var on: bool = tabs[i] == deck_tab
		var thv: float = polish.hover_val("deck_tab_%d" % i,not on and r.has_point(mouse),is_processing())
		var lift := -3.0 if on else -2.0*thv
		var tab_pts := PackedVector2Array([r.position+Vector2(7,lift),Vector2(r.end.x,r.position.y+lift),Vector2(r.end.x-7,r.end.y),Vector2(r.position.x,r.end.y)])
		draw_colored_polygon(tab_pts,RED if on else Color("e6d3a8").lerp(Color("f6ead0"),thv))
		var tab_rim := tab_pts.duplicate()
		tab_rim.append(tab_pts[0])
		draw_polyline(tab_rim,Color("d2ad58") if on else Color("6a5236"),1.6 if on else 1.2,true)
		if on: draw_line(Vector2(r.position.x+10,r.end.y-3),Vector2(r.end.x-10,r.end.y-3),Color("d2ad58"),2.0,true)
		draw_string(font,Vector2(r.position.x,r.position.y+28),"%s（%d）" % [TAB_NAMES[tabs[i]],tab_count(tabs[i])],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,18,Color("fbf1dc") if on else INK)
	# Collection.
	var items := page_items()
	if items.is_empty():
		draw_string(font,Vector2(POOL_X,POOL_Y+145),"目前篩選條件下沒有可用卡牌",HORIZONTAL_ALIGNMENT_CENTER,8*POOL_STEP.x-22,22,muted)
	for i: int in range(items.size()):
		var r := pool_rect(i)
		var hv: float = polish.hover_val("deck_pool_%s_%s" % [deck_tab, items[i]], r.has_point(mouse), is_processing())
		r.position.y -= 8.0 * hv
		r = r.grow(3.0 * hv)
		if deck_tab == "lord":
			if hv > 0.01 and items[i] != player_lord: polish.draw_card_hover_glow(self, r, hv)
			draw_lord_card(items[i],r,items[i] == player_lord)
			continue
		if hv > 0.01: polish.draw_card_hover_glow(self, r, hv)
		draw_card(items[i],r)
		if items[i] in player_deck:
			draw_rect(r,Color(0.25,0.18,0.10,0.35))
			draw_rect(r.grow(3),RED,false,4)
			draw_check(Vector2(r.get_center().x,r.end.y))
	var pages := ceili(tab_size()/float(POOL_PAGE))
	if pages > 1:
		for p: int in range(pages):
			draw_circle(Vector2(800+(p-(pages-1)/2.0)*20,POOL_Y+2*POOL_STEP.y+8),6 if p == deck_page else 4,RED if p == deck_page else Color(INK,0.35))
		draw_string(font,Vector2(360,804),"第 %d / %d 頁 · 滾輪／← → 翻頁" % [deck_page+1,pages],HORIZONTAL_ALIGNMENT_CENTER,880,15,muted)
	# Status line between the two bottom buttons.
	var note := menu_notice
	if note.is_empty() and not DeckStore.valid(player_deck,player_lord): note = "還差 %d 張才能%s" % [8-player_deck.size(),"出征" if adventure_deck_mode else "開戰"]
	if not note.is_empty(): draw_string(font,Vector2(360,855),note,HORIZONTAL_ALIGNMENT_CENTER,880,20,RED)
	elif watch_edit >= 0: draw_string(font,Vector2(360,855),"只改這場觀戰，不影響你的牌組",HORIZONTAL_ALIGNMENT_CENTER,880,18,muted)
	elif adventure_deck_mode: draw_string(font,Vector2(360,855),adventure.deck_tip(),HORIZONTAL_ALIGNMENT_CENTER,880,18,Color("3c6e2e"))

# Random spectate deck (per-lord optimal ratios live in DeckStore).
static func random_deck(rng: RandomNumberGenerator, lord: String = "") -> Array:
	return DeckStore.balanced_random_deck(rng,lord)

func save_watch_lord(team: int) -> void:
	var lord: String = watch_lords[team]
	if B.LORDS.has(lord) and DeckStore.valid(watch_decks[team],lord):
		watch_lord_decks[team][lord] = watch_decks[team].duplicate()
		watch_lord_sources[team][lord] = watch_source[team]

func randomize_watch_deck(team: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	watch_source[team] = 0
	watch_decks[team] = random_deck(rng,watch_lords[team])
	save_watch_lord(team)
	save_watch()

func select_watch_lord(team: int, choice: String) -> void:
	save_watch_lord(team)
	watch_lords[team] = choice
	if watch_lord_decks[team].has(choice) and DeckStore.valid(watch_lord_decks[team][choice],choice):
		watch_decks[team] = watch_lord_decks[team][choice].duplicate()
		watch_source[team] = int(watch_lord_sources[team].get(choice,0))
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		watch_decks[team] = random_deck(rng,choice)
		watch_source[team] = 0
		save_watch_lord(team)
	save_watch()

func set_watch_source(team: int, source: int) -> void:
	if source == 0:
		if watch_decks[team].is_empty():
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			watch_lords[team] = B.LORDS.keys()[rng.randi_range(0,B.LORDS.size()-1)]
		randomize_watch_deck(team)
	else:
		save_watch_lord(team)
		watch_source[team] = source
		watch_lords[team] = player_lord
		watch_decks[team] = player_deck.duplicate() if DeckStore.valid(player_deck,player_lord) else DeckStore.fit_to_lord(B.DEFAULT_DECK,player_lord)
		save_watch_lord(team)
		save_watch()

# Spectate side editing reuses the deck screen on that side's deck and lord.
func edit_watch_side(team: int) -> void:
	save_watch_lord(team)
	watch_stash = {
		"deck":player_deck.duplicate(),
		"lord":player_lord,
		"tab":deck_tab,
		"lord_decks":watch_lord_decks[team].duplicate(true),
		"lord_sources":watch_lord_sources[team].duplicate(true),
	}
	player_deck = watch_decks[team].duplicate()
	player_lord = watch_lords[team]
	watch_edit = team
	menu_notice = ""
	deck_tab = "all"
	deck_faction = "all"
	deck_page = 0
	show_deck()

func finish_watch_edit(keep: bool) -> void:
	if keep and DeckStore.valid(player_deck,player_lord):
		watch_decks[watch_edit] = player_deck.duplicate()
		watch_lords[watch_edit] = player_lord
		watch_source[watch_edit] = -1
		save_watch_lord(watch_edit)
		save_watch()
	else:
		watch_lord_decks[watch_edit] = watch_stash.lord_decks.duplicate(true)
		watch_lord_sources[watch_edit] = watch_stash.lord_sources.duplicate(true)
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
	save_watch_lord(team)
	save_watch()
	show_watch()

func save_watch() -> void:
	if watch_path.is_empty(): return
	var data := {
		"decks":watch_decks,
		"lords":watch_lords,
		"source":watch_source,
		"lord_decks":watch_lord_decks,
		"lord_sources":watch_lord_sources,
	}
	var file := FileAccess.open(watch_path,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data))

func load_watch() -> void:
	if watch_path.is_empty() or not FileAccess.file_exists(watch_path): return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(watch_path))
	if not parsed is Dictionary: return
	var decks = parsed.get("decks",[])
	var lords = parsed.get("lords",[])
	var sources = parsed.get("source",[])
	var lord_decks = parsed.get("lord_decks",[])
	var lord_sources = parsed.get("lord_sources",[])
	for team: int in range(2):
		if lord_decks is Array and team < lord_decks.size() and lord_decks[team] is Dictionary:
			var clean_decks := {}
			for k in lord_decks[team]:
				var lk := str(k)
				if B.LORDS.has(lk) and lord_decks[team][k] is Array and DeckStore.valid(lord_decks[team][k],lk):
					clean_decks[lk] = lord_decks[team][k].duplicate()
			watch_lord_decks[team] = clean_decks
		if lord_sources is Array and team < lord_sources.size() and lord_sources[team] is Dictionary:
			var clean_src := {}
			for k in lord_sources[team]:
				var lk := str(k)
				if B.LORDS.has(lk): clean_src[lk] = clampi(int(lord_sources[team][k]),-1,WATCH_SOURCES.size()-1)
			watch_lord_sources[team] = clean_src
		if lords is Array and team < lords.size() and B.LORDS.has(str(lords[team])):
			watch_lords[team] = str(lords[team])
		if decks is Array and team < decks.size() and decks[team] is Array and DeckStore.valid(decks[team],watch_lords[team]):
			watch_decks[team] = decks[team].duplicate()
		elif watch_lord_decks[team].has(watch_lords[team]):
			watch_decks[team] = watch_lord_decks[team][watch_lords[team]].duplicate()
		if sources is Array and team < sources.size():
			watch_source[team] = clampi(int(sources[team]),-1,WATCH_SOURCES.size()-1)
		save_watch_lord(team)

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
		var rand_btn := button(Rect2(x+582,108,158,46),"重新隨機",func(): randomize_watch_deck(side); show_watch())
		rand_btn.tooltip_text = "僅隨機目前領主的 8 張牌組，其他領主陣容維持不變"
		var index := 0
		for lord_kind: String in B.lord_menu_order():
			var choice := lord_kind
			var b := button(watch_lord_rect(team,index),"",func(): select_watch_lord(side,choice); show_watch())
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
	save_watch_lord(0)
	save_watch_lord(1)
	watch_decks.reverse()
	watch_lords.reverse()
	watch_source.reverse()
	watch_lord_decks.reverse()
	watch_lord_sources.reverse()
	save_watch()
	show_watch()

func draw_watch() -> void:
	var muted := Color("5a4a36")
	label_at(Vector2(60,78),"觀戰設定",40)
	label_at(Vector2(260,74),"點領主頭像切換（各自保留陣容）· 點牌組進入編輯",18,muted)
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
		draw_string(font,Vector2(portrait.position.x,portrait.end.y+54),"%s 充能 %d" % [B.LORDS[lord].skill,int(B.skill_charge_need(lord))],HORIZONTAL_ALIGNMENT_CENTER,portrait.size.x,14,color)
		var shown: Array = B.menu_sorted(watch_decks[team])
		for i: int in range(shown.size()): draw_card(shown[i],watch_card_rect(team,i))
		var hover := army.has_point(get_global_mouse_position())
		var tag := Rect2(army.end.x-150,army.end.y-4,150,36)
		panel(tag,color if hover else Color("f6e9c8"),color)
		draw_string(font,Vector2(tag.position.x,tag.position.y+25),"編輯牌組 ▸",HORIZONTAL_ALIGNMENT_CENTER,tag.size.x,17,Color("fbf1dc") if hover else color)
		if hover: draw_rect(army.grow(3),color,false,3)
	draw_line(Vector2(800,120),Vector2(800,660),Color(INK,0.25),2)

func card_description(kind: String) -> String:
	var up_map: Dictionary = {}
	if screen in ["battle","battle_info"] and model != null and me < model.card_upgrades.size():
		up_map = model.card_upgrades[me]
	elif screen == "rogue" and rogue != null and not rogue.run.is_empty():
		up_map = rogue.run.get("upgrades",{})
	var ups: Dictionary = up_map.get(kind,{})
	if not ups.is_empty():
		var Up = preload("res://card_upgrades.gd")
		return "【+%d 強化：%s】\n%s" % [Up.level(ups),Up.text(ups),B.card_description(kind,Up.table({kind:ups}))]
	return B.card_description(kind)

func help_columns() -> Array[String]:
	return [
		"[b]選牌與放置[/b]\n1–4 選手牌，F 選常駐牌；點卡再點戰場，或拖曳放置。右鍵取消選牌。Esc 取消選牌或切換暫停。\n空白鍵暫停；暫停或結束後按 R 重玩。F11 切換全螢幕。\n\n[b]牌組與領主[/b]\n選一位領主與 8 張輪轉牌，另有一張常駐經濟牌。依領主陣營使用經典、黑暗、魔法與中立牌。\n領主由 AI 移動防守；按 Q 發動技能，費用與效果見技能按鈕及圖鑑。\n\n[b]種田與防守[/b]\n農田自己產金幣；農民從田後方出發，順路耕田加速並回血。相同建築覆蓋自己的舊建築可補滿生命。\n部隊只往前走，不追身後範圍外的敵人；城牆無固定減傷（僅遠程非魔法攻擊對城牆傷害減半）且不反擊，靠領主、部隊與建築防守。",
		"[b]一日戰役[/b]\n上方日晷的太陽走完一天：白天 3 分鐘（×1.5）；03:00 正午（×2）；04:30 黃昏（×2.5）。\n%d 分鐘入夜（×%d，雙方城牆持續掉血，每分鐘加倍）。\n%d 分鐘天亮仍未分勝負，領地較大的一方獲勝。肉鴿模式不入夜，改在 %d 分鐘比城牆血量。\n\n[b]破門與勝負[/b]\n建築與部隊限己方領地：建築、城牆周圍八格先佔先得，失去所有己方建築覆蓋就釋出。城牆損毀後，敵兵直接穿過缺口，不需拆除殘垣。\n任何敵兵走進家門就輸。\n\n[b]觀戰模式[/b]\n開戰前調整雙方牌組與領主（預設隨機），AI 出牌；1–4 切換 ×1／×2／×4／×8，＋／－ 逐級調速。" % [int(B.NIGHT_START/60),int(B.NIGHT_GOLD),int(B.DAWN/60),int(preload("res://roguelike_catalog.gd").TIME_LIMIT/60)]
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
		text.text = columns[i].replace("[b]","[font_size=24][color=#763825]").replace("[/b]","[/color][/font_size]")
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
	title_button(L.HELP_BACK,"回到標題",show_title)
	queue_redraw()

func draw_help() -> void:
	panel(L.HELP_PANEL)
	ink_frame(L.HELP_PANEL.grow(-8))
	draw_fitted(ART.ornament(4),Rect2(L.HELP_PANEL.position.x+L.HELP_PANEL.size.x*0.5-150.0,L.HELP_PANEL.position.y+16.0,300.0,32.0))
	preload("res://interface_ornament.gd").vertical_rule(self,795.0,208.0,702.0,INK)
	label_at(L.HELP_TITLE,"操作與勝負",44)

var settings_path := "user://settings.json"
var settings_return := "title" # "battle" while the settings were opened from the pause banner

func save_settings() -> void:
	var file := FileAccess.open(settings_path,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"effects":fx_enabled,"shake":shake_enabled,"cinematic":cinematic.enabled,"replay":replay_enabled,"sound":sfx_volume > 0.001,"music_volume":music_volume,"sfx_volume":sfx_volume,"fullscreen":fullscreen}))

func load_settings() -> void:
	if not FileAccess.file_exists(settings_path): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if data is Dictionary:
		fx_enabled = bool(data.get("effects",true))
		shake_enabled = bool(data.get("shake",true))
		cinematic.enabled = bool(data.get("cinematic",true))
		replay_enabled = bool(data.get("replay",false))
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
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"): return
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
	library.text_box(Rect2(140,493,1320,240),review.report(model,[Ceremony.side_name(self,0),Ceremony.side_name(self,1)]),20)
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
