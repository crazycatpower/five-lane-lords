extends RefCounted
# 冒險模式：五路遠征記，也是新手教學（2026-11-21）。第一章十課逐步指引，之後每關教一件事：
# 本關新卡在出征時自動放進牌組、過關永久解鎖；新敵人第一次出現時跳說明（tutorial_coach.gd）。
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Battle = preload("res://battle.gd")
const DeckStore = preload("res://deck_store.gd")
const Catalog = preload("res://campaign_catalog.gd")
const Lessons = preload("res://tutorial_lessons.gd")
const WORLDS = Catalog.WORLDS
const CHAPTERS = Catalog.CHAPTERS
const STARTER_CARDS = Catalog.STARTER_CARDS

var STAGES: Array = Catalog.stages()
var index := -1 # active battle stage index, -1 outside adventure battles
var world := 0 # active world tab 0..4
var selected := -1 # selected stage index 0..49 (-1 picks frontier on first show)
var opening := preload("res://farm_opening.gd").new() # kept for safety with legacy callers
var finale := preload("res://adventure_finale.gd").new()
var ending := preload("res://adventure_ending.gd").new()
var road_story := preload("res://road_toll_story.gd").new()
var coach := preload("res://tutorial_coach.gd").new()
var recruit := ""
var outcome := ""
var cleared: Dictionary = {} # cleared in current cycle
var ever_cleared: Dictionary = {} # preserves unlocked cards & lords across NG+
var stars: Dictionary = {} # stage_id -> best 1..3 stars
var difficulty := 0 # index into Catalog.DIFFICULTIES: 0 簡單（新存檔預設）、1 普通、2 困難、3 極難
var decrees: Array = [] # active decree IDs
var ng_plus := 0
var show_decrees := false
var reset_confirm := 0 # 0 idle, 1 awaiting confirmation
var custom_deck: Array = []
var lord := "adventure"
var decks: Dictionary = {}
var progress_path := "user://adventure.json"

func is_ever_cleared(i: int) -> bool:
	var id: String = STAGES[i].id
	return cleared.has(id) or ever_cleared.has(id)

func unlocked_lords() -> Array:
	var result: Array = ["adventure"]
	for i: int in range(STAGES.size()):
		var won: String = Catalog.UNLOCK_LORDS.get(STAGES[i].id,"")
		if is_ever_cleared(i) and B.LORDS.has(won) and not won in result:
			result.append(won)
	return result

func card_pool(who: String = "") -> Array:
	if who.is_empty(): who = lord
	var result: Array = unlocked_cards().filter(func(k: String) -> bool: return B.card_allowed(k,who) and not B.is_home_card(k,who))
	if B.lord_faction(who) != B.lord_faction("adventure"):
		for k: String in DeckStore.pool(who):
			if not B.card_faction(k).is_empty() and not k in result: result.append(k)
	return result

func choose_lord(who: String) -> void:
	if not who in unlocked_lords(): return
	if custom_deck_valid(): decks[lord] = custom_deck.duplicate()
	lord = who
	custom_deck = decks.get(who,[]).duplicate()
	if not custom_deck_valid(): custom_deck = []
	save_progress()

func cycle_lord() -> void:
	var list := unlocked_lords()
	if list.size() <= 1: return
	var pos := list.find(lord)
	choose_lord(list[(pos + 1) % list.size()])

# A first deck shaped like the deck lesson's advice: 1 farmer, troops, 2 buildings, 2 spells, in unlock order.
func auto_deck() -> Array:
	var pool := card_pool()
	var out: Array = []
	if "farmer" in pool: out.append("farmer")
	var want := {"building":2,"spell":2}
	for kind: String in pool:
		var t: String = B.CARDS[kind].type
		if kind in out or not want.has(t) or want[t] <= 0: continue
		out.append(kind)
		want[t] -= 1
	for kind: String in pool: # troops fill the rest; anything left tops it up
		if out.size() >= 8: break
		if not kind in out and B.CARDS[kind].type == "unit": out.append(kind)
	for kind: String in pool:
		if out.size() >= 8: break
		if not kind in out: out.append(kind)
	return out.slice(0,8)

func unlocked_cards() -> Array:
	var result: Array = STARTER_CARDS.duplicate()
	for i: int in range(STAGES.size()):
		if is_ever_cleared(i):
			for k: String in STAGES[i].rewards:
				if not k in result: result.append(k)
	return result

func custom_deck_valid() -> bool:
	if custom_deck.size() != 8: return false
	var pool: Array = card_pool()
	for k in custom_deck:
		if not k is String or not k in pool: return false
	return DeckStore.valid(custom_deck,lord)

func total_stars() -> int:
	var n := 0
	for k in stars: n += int(stars[k])
	return n

func max_stars() -> int:
	return STAGES.size() * Catalog.MAX_STARS_PER_STAGE

func world_stars(w: int) -> int:
	var n := 0
	var per := Catalog.STAGES_PER_WORLD
	for i: int in range(w * per, mini((w + 1) * per, STAGES.size())):
		n += int(stars.get(STAGES[i].id, 0))
	return n

func world_cleared_count(w: int) -> int:
	var n := 0
	var per := Catalog.STAGES_PER_WORLD
	for i: int in range(w * per, mini((w + 1) * per, STAGES.size())):
		if is_cleared(i): n += 1
	return n

func world_unlocked(w: int) -> bool:
	return w == 0 or is_cleared(w * Catalog.STAGES_PER_WORLD - 1)

func decree_unlocked(id: String) -> bool:
	for dec: Dictionary in Catalog.DECREES:
		if dec.id == id: return total_stars() >= int(dec.stars)
	return false

func toggle_decree(id: String) -> void:
	if not decree_unlocked(id): return
	if id in decrees: decrees.erase(id)
	else: decrees.append(id)
	save_progress()

func active_decree_mods() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dec: Dictionary in Catalog.DECREES:
		if dec.id in decrees and total_stars() >= int(dec.stars):
			out.append(dec.mods)
	return out

func load_progress() -> void:
	cleared = {}
	ever_cleared = {}
	stars = {}
	decrees = []
	difficulty = 0
	ng_plus = 0
	recruit = ""
	custom_deck = []
	lord = "adventure"
	decks = {}
	if not FileAccess.file_exists(progress_path): return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(progress_path))
	if not parsed is Dictionary: return
	if parsed.get("cleared") is Array:
		for id in parsed.cleared:
			if Catalog.index_of(str(id)) >= 0:
				cleared[str(id)] = true
				ever_cleared[str(id)] = true
	if parsed.get("ever_cleared") is Array:
		for id in parsed.ever_cleared:
			if Catalog.index_of(str(id)) >= 0:
				ever_cleared[str(id)] = true
	if parsed.get("stars") is Dictionary:
		for id in parsed.stars:
			if Catalog.index_of(str(id)) >= 0:
				stars[str(id)] = clampi(int(parsed.stars[id]), 0, Catalog.MAX_STARS_PER_STAGE)
	ng_plus = maxi(0, int(parsed.get("ng_plus", 0)))
	difficulty = clampi(int(parsed.get("difficulty", 0)), 0, Catalog.DIFFICULTIES.size() - 1)
	if parsed.get("decrees") is Array:
		var tot := total_stars()
		for did in parsed.decrees:
			var s_id := str(did)
			for dec: Dictionary in Catalog.DECREES:
				if dec.id == s_id and tot >= int(dec.stars) and not s_id in decrees:
					decrees.append(s_id)
	if parsed.get("custom_deck") is Array:
		var valid_list: Array = []
		for c in parsed.custom_deck:
			if c is String and B.CARDS.has(c): valid_list.append(c)
		if valid_list.size() == 8: custom_deck = valid_list
	if parsed.get("decks") is Dictionary:
		for who in parsed.decks:
			if B.LORDS.has(who) and parsed.decks[who] is Array:
				decks[who] = parsed.decks[who].filter(func(c) -> bool: return c is String and B.CARDS.has(c))
	if parsed.get("lord","") in unlocked_lords(): lord = parsed.lord

func save_progress() -> bool:
	var file := FileAccess.open(progress_path,FileAccess.WRITE)
	if file == null: return false
	if custom_deck.size() == 8: decks[lord] = custom_deck.duplicate()
	var payload := {
		"cleared":cleared.keys(),
		"ever_cleared":ever_cleared.keys(),
		"stars":stars,
		"difficulty":difficulty,
		"decrees":decrees,
		"ng_plus":ng_plus,
		"custom_deck":custom_deck,
		"lord":lord,
		"decks":decks,
	}
	file.store_string(JSON.stringify(payload))
	file.flush()
	return file.get_error() == OK

func is_cleared(i: int) -> bool:
	return cleared.has(STAGES[i].id)

func unlocked(i: int) -> bool:
	return i == 0 or is_cleared(i - 1)

func cleared_count() -> int:
	return range(STAGES.size()).filter(func(i: int) -> bool: return is_cleared(i)).size()

func frontier() -> int:
	for i: int in range(STAGES.size()):
		if unlocked(i) and not is_cleared(i): return i
	return STAGES.size() - 1

func stage_lord(_game, i: int) -> String:
	return lord if STAGES[i].deck is String else STAGES[i].lord

func stage_deck(game, i: int) -> Array:
	if not STAGES[i].deck is String: return STAGES[i].deck.duplicate()
	var base: Array = []
	if custom_deck_valid(): base = custom_deck.duplicate()
	elif card_pool().size() >= 8: base = auto_deck()
	elif game.player_deck.size() == 8 and DeckStore.valid(game.player_deck,stage_lord(game,i)): base = game.player_deck.duplicate()
	else: base = ["farmer","hunter","militia","mob","ram","rain","mill","healer"]
	return with_featured(base,i)

# 本關新卡（這關的獎勵）：出征領主能用的才放進牌組。
func featured_cards(i: int) -> Array:
	if i < 0 or i >= STAGES.size(): return []
	var allowed: Array = DeckStore.pool(lord)
	return STAGES[i].rewards.filter(func(k: String) -> bool: return k in allowed)

# The stage's new cards replace a card of the same type (economy cards last), so the lesson's card is
# always in hand. The saved deck is untouched; an invalid result keeps the original deck.
func with_featured(deck: Array, i: int) -> Array:
	var out: Array = deck.duplicate()
	var feat := featured_cards(i)
	for k: String in feat:
		if k in out: continue
		var pick := -1
		for pass_i: int in range(3):
			for j: int in range(out.size()-1,-1,-1):
				var old: String = out[j]
				if old in feat: continue
				if pass_i < 2 and (old == "farmer" or B.is_economy_building(old)): continue
				if pass_i == 0 and B.CARDS[old].type != B.CARDS[k].type: continue
				pick = j
				break
			if pick >= 0: break
		if pick >= 0: out[pick] = k
	return out if DeckStore.valid(out,lord) else deck

# A first-chapter lesson whose enemy only sends the script's troops (no AI, no hand to show).
func scripted_foe(i: int) -> bool:
	return false # the enemy always plays its own hand now (使用者 2026-11-22)

func is_lesson(i: int) -> bool:
	return i >= 0 and i < STAGES.size() and int(STAGES[i].world) == 0

# 第一章「新兵訓練」學完才開放王國詔令。
func tutorial_done() -> bool:
	return is_ever_cleared(Catalog.STAGES_PER_WORLD-1)

# The stage's battle before any presentation: shared by start() and the headless checks.
func make_battle(i: int, deck: Array, lead_lord: String) -> Battle:
	var d: Dictionary = STAGES[i]
	var diff := difficulty
	var plus := ng_plus
	var diff_cfg: Dictionary = Catalog.DIFFICULTIES[diff]
	var ai := stage_ai(i)
	var enemy: Array = d.get("enemy_deck",B.PRESETS[1]).duplicate()
	L.pending_rows = int(d.get("rows",5)) # a six-lane stage lays the field out in six rows
	var m := Battle.new(7500 + i + plus * 100 + diff * 31, deck, enemy, lead_lord, d.get("enemy_lord","iron"))
	m.biome = String(d.get("biome","meadow"))
	m.stage_rule_tag = String(d.get("rule_tag",""))
	m.survive_time = float(d.get("survive_time",0.0))
	m.night_start_override = float(d.get("night_start_override",-1.0))
	m.night_decay = bool(d.get("night_decay",true))
	preload("res://season.gd").apply(m,String(d.get("season",""))) # 春夏秋冬：外觀＋一條小規則
	if not d.enemy_lord_active:
		m.lord_active[1] = false
		m.lords[1].hp = 0
	if d.enemy_camp:
		m.home_cards[1] = ""
		m.buildings = m.buildings.filter(func(b): return b.team == 0)
	m.set_active_lanes(d.get("active_lanes",[0,1,2,3,4]))
	if bool(d.get("camp",false)): m.set_meta("camp_team",1) # drawn as a bandit camp (camp_art.gd)
	m.difficulty = ai
	m.ai_enabled = [false,true]
	m.invasion_victory.assign([true,true])
	for b: Array in d.get("buildings",[]):
		m.add_building(1,Vector2i(b[0],b[1]),b[2])
	for mut: Dictionary in d.get("mutators",[]):
		m.apply_field_mutator(mut, 1)
	var both: Dictionary = d.get("both_mods",{})
	if not both.is_empty():
		m.apply_campaign_mods(0, both)
		m.apply_campaign_mods(1, both)
	for dec_mods: Dictionary in active_decree_mods():
		m.apply_campaign_mods(0, dec_mods)
	m.apply_campaign_mods(1, d.get("enemy_mods",{}))
	m.apply_campaign_mods(1, diff_cfg.get("enemy_mods",{}))
	for p: Dictionary in difficulty_passives(i):
		m.apply_campaign_mods(1, p.mods)
	if plus > 0:
		m.apply_campaign_mods(1, {"start_ink":float(5 * plus),"cd_speed_mult":1.0 + 0.1 * mini(plus, 3)})
	if not d.get("conveyor",{}).is_empty():
		preload("res://conveyor.gd").setup(m, d.conveyor)
	return m

# The enemy AI level for stage i: the stage's own, unless the difficulty sets one; a new cycle adds one.
func stage_ai(i: int) -> int:
	var cfg: Dictionary = Catalog.DIFFICULTIES[difficulty]
	var base: int = int(STAGES[i].get("ai",1)) if int(cfg.get("ai",-1)) < 0 else int(cfg.ai)
	return clampi(base + (1 if ng_plus > 0 else 0), 0, 2)

# 極難 gives the enemy extra passives; the other difficulties none.
func difficulty_passives(i: int) -> Array:
	return Catalog.extreme_passives(i) if bool(Catalog.DIFFICULTIES[difficulty].get("passives",false)) else []

# The deck screen's line for this stage: the first self-built deck, or the card the stage adds.
func deck_tip() -> String:
	if selected < 0 or selected >= STAGES.size(): return ""
	if bool(STAGES[selected].get("deck_lesson",false)):
		return "第一次自己組牌：從 %d 張挑 8 張。建議農民 1、部隊 3–4、防守 1–2、法術 1–2。" % card_pool().size()
	var feat := featured_cards(selected)
	if feat.is_empty(): return ""
	return "本關新卡「%s」會在出征時自動放進牌組。" % "、".join(feat.map(func(k: String) -> String: return B.CARDS[k].name))

func open_adventure_deck(game) -> void:
	if not game.adventure_deck_mode:
		game.adventure_deck_stash = {"deck":game.player_deck.duplicate(),"lord":game.player_lord,"tab":game.deck_tab}
	game.adventure_deck_mode = true
	game.player_lord = lord
	if custom_deck_valid(): game.player_deck = custom_deck.duplicate()
	elif card_pool().size() >= 8: game.player_deck = auto_deck()
	else: game.player_deck = card_pool()
	game.deck_tab = "all"
	game.deck_page = 0
	game.show_deck()

func start(game, choice: int) -> void:
	index = choice
	selected = choice
	world = STAGES[choice].world
	outcome = ""
	var d: Dictionary = STAGES[index]
	var lead_lord := stage_lord(game,index)
	var deck := stage_deck(game,index)
	if not DeckStore.valid(deck,lead_lord,d.get("allow_duplicates",false) and not d.deck is String):
		index = -1
		open_adventure_deck(game)
		return
	game.spectating = false
	game.model = make_battle(index,deck,lead_lord)
	opening.active = false
	coach.begin(game,d)
	var first_clear := not is_cleared(choice)
	game.enter_battle("%s %s · %s" % [d.code, d.name, d.goal])
	if d.dialogue and first_clear: road_story.begin(game)

func update(game) -> void:
	if index < 0 or game.model.paused or not outcome.is_empty(): return
	coach.update(game)
	var m = game.model
	if not m.ended: return
	var won: bool = m.winner == 0
	var was_first: bool = not is_cleared(index)
	var first_crowning: bool = won and index == STAGES.size() - 1 and was_first
	settle(won,"（天亮平手）" if m.winner < 0 else "")
	if first_crowning:
		finale.show(game)
		return
	if won and was_first and STAGES[index].dialogue: road_story.begin(game, true)

func is_opening() -> bool:
	return false

func active_story():
	return road_story

func settle(won: bool, reason: String) -> void:
	var d: Dictionary = STAGES[index]
	var earn_stars: int = Catalog.DIFFICULTIES[difficulty].stars
	outcome = ("突破「%s %s」！（★ %d）" % [d.code, d.name, earn_stars]) if won else ("挑戰「%s %s」失利%s" % [d.code, d.name, reason])
	if won:
		cleared[d.id] = true
		ever_cleared[d.id] = true
		stars[d.id] = maxi(int(stars.get(d.id, 0)), earn_stars)
		save_progress()
		selected = frontier()
		world = STAGES[selected].world

func start_ng_plus(game) -> void:
	ng_plus += 1
	cleared = {}
	reset_confirm = 0
	world = 0
	selected = 0
	save_progress()
	show(game)

func reset_all(game) -> void:
	cleared = {}
	ever_cleared = {}
	stars = {}
	decrees = []
	difficulty = 0
	ng_plus = 0
	lord = "adventure"
	custom_deck = []
	decks = {}
	reset_confirm = 0
	show_decrees = false
	world = 0
	selected = 0
	save_progress()
	show(game)

# ---- PVZ2-style 5-World Linear Expedition Map ----------------------------------------------------
const MAP := Rect2(70, 180, 960, 620)
const SIDE := Rect2(1060, 180, 470, 620)
const MODAL := Rect2(240, 130, 1120, 640)
const LESSON_Y := 182.0 # side panel rows, from SIDE.position.y
const CHIP_Y := 308.0
const ENEMY_Y := 386.0

# Side panel chips: 0 = the stage's new enemy, 1 = its new card(s).
func chip_rect(i: int) -> Rect2:
	return Rect2(SIDE.position.x + 20 + i * 219, SIDE.position.y + CHIP_Y, 211, 52)

# An invisible hover area that only carries a tooltip.
func tip_spot(game, rect: Rect2, text: String) -> void:
	var b: Button = game.button(rect, "", func(): pass)
	b.modulate.a = 0.01
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = text

func ruler_name(i: int) -> String:
	return "強盜" if STAGES[i].enemy_camp and STAGES[i].enemy_lord == "bandit_chief" else B.lord_name(STAGES[i].enemy_lord)

func show(game) -> void:
	load_progress()
	index = -1
	if selected < 0 or selected >= STAGES.size():
		selected = frontier()
		world = STAGES[selected].world
	world = clampi(world, 0, WORLDS.size() - 1)
	if STAGES[selected].world != world:
		selected = world * Catalog.STAGES_PER_WORLD
	game.screen = "adventure"
	game.clear_ui()
	if show_decrees:
		_build_decree_buttons(game)
		game.queue_redraw()
		return
	# Top right action buttons: difficulty always (點一下換下一段); decrees once the training chapter is done.
	var diff_cfg: Dictionary = Catalog.DIFFICULTIES[difficulty]
	var db: Button = game.title_button(Rect2(745,52,235,44),"難度：%s (%d★)" % [diff_cfg.name,diff_cfg.stars],func():
		difficulty = (difficulty + 1) % Catalog.DIFFICULTIES.size()
		reset_confirm = 0
		save_progress()
		show(game))
	db.add_theme_font_size_override("font_size", 18)
	db.tooltip_text = "點一下切換難度：
" + "
".join(Catalog.DIFFICULTIES.map(func(c: Dictionary) -> String: return "%s（%d★）：%s" % [c.name,c.stars,c.desc]))
	if tutorial_done():
		var decb: Button = game.title_button(Rect2(995,52,270,44),"王國詔令（已啟用 %d）" % decrees.size(),func():
			show_decrees = true
			reset_confirm = 0
			show(game))
		decb.add_theme_font_size_override("font_size", 18)
	var all_done: bool = cleared_count() == STAGES.size()
	var ng_caption := ("確定開第 %d 周目？" % (ng_plus + 2) if reset_confirm == 1 else "開啟第 %d 周目" % (ng_plus + 2)) if all_done else ("確定重置全部進度？" if reset_confirm == 1 else "重置遠征進度")
	var ngb: Button = game.title_button(Rect2(1280,52,250,44),ng_caption,func():
		if reset_confirm == 0:
			reset_confirm = 1
			show(game)
		elif all_done:
			start_ng_plus(game)
		else:
			reset_all(game))
	ngb.add_theme_font_size_override("font_size", 18)
	# 5 World selector tabs
	var per := Catalog.STAGES_PER_WORLD
	for w: int in range(WORLDS.size()):
		var widx := w
		var tab_r := Rect2(70 + w * 294, 122, 282, 44)
		var w_mark := "✓ " if world_cleared_count(w) == per else ("" if world_unlocked(w) else "[鎖] ")
		var label_txt := "%s%s (%d★)" % [w_mark, WORLDS[w].short, world_stars(w)]
		var tb: Button = game.title_button(tab_r, label_txt, func():
			world = widx
			reset_confirm = 0
			var first_in_w := widx * per
			var pick := first_in_w
			for si: int in range(first_in_w, first_in_w + per):
				if unlocked(si) and not is_cleared(si):
					pick = si
					break
			selected = pick
			show(game), w == world)
		tb.add_theme_font_size_override("font_size", 18)
		tb.tooltip_text = "%s · %s · 過關 %d/%d · ★ %d/%d" % [WORLDS[w].name, WORLDS[w].subtitle, world_cleared_count(w), per, world_stars(w), per * Catalog.MAX_STARS_PER_STAGE]
	# 10 Stage node hitboxes inside current world
	var base := world * per
	for local_i: int in range(per):
		var si := base + local_i
		var sd: Dictionary = STAGES[si]
		var btn: Button = seal_button(game, Rect2(sd.map - Vector2(32,32), Vector2(64,64)), func():
			selected = si
			reset_confirm = 0
			show(game))
		btn.tooltip_text = "%s %s · 本關教學：%s" % [sd.code, sd.name, sd.rule_tag]
	# Briefing panel interactive buttons: hover the enemy cards and the two lesson chips for details.
	var d: Dictionary = STAGES[selected]
	if not scripted_foe(selected):
		for ei: int in range(d.enemy_deck.size()):
			tip_spot(game, Rect2(SIDE.position.x + 22 + ei * 53, SIDE.position.y + ENEMY_Y, 48, 50), game.card_description(d.enemy_deck[ei]))
	var foe_kind := String(d.get("new_enemy",""))
	if B.CARDS.has(foe_kind): tip_spot(game, chip_rect(0), game.card_description(foe_kind))
	var terrain_tip := preload("res://adventure_terrain.gd").details(d)
	if not terrain_tip.is_empty(): tip_spot(game, Rect2(SIDE.position.x + 120, SIDE.position.y + 144, 340, 24), terrain_tip)
	var card_chip := card_chip_of(selected)
	if B.CARDS.has(card_chip[1]): tip_spot(game, chip_rect(1), "\n\n".join((d.rewards if card_chip[1] in d.rewards else [card_chip[1]]).map(func(k: String) -> String: return game.card_description(k))))
	if d.deck is String:
		if unlocked_lords().size() > 1:
			game.title_button(Rect2(SIDE.position.x+24,SIDE.position.y+482,200,40),"切換：%s" % B.lord_name(lord).trim_suffix("領主"),func():
				cycle_lord()
				show(game))
		if card_pool().size() > 8:
			var deck_rect := Rect2(SIDE.position.x+232,SIDE.position.y+482,214,40) if unlocked_lords().size() > 1 else Rect2(SIDE.position.x+24,SIDE.position.y+482,SIDE.size.x-48,40)
			game.title_button(deck_rect,"編成出征牌組（%d張）" % card_pool().size(),func(): open_adventure_deck(game))
	if unlocked(selected):
		var caption := "再戰「%s」" % d.name if is_cleared(selected) else ("開始上課 %s" % d.code if is_lesson(selected) and d.deck is Array else "出征 %s" % d.code)
		if d.deck is String:
			game.title_button(Rect2(SIDE.position.x+24,SIDE.end.y-68,SIDE.size.x-48,50),caption,func():
				# The graduation exam opens the deck screen first: the player's first self-built eight.
				if (card_pool().size() > 8 and stage_deck(game,selected).size() != 8) or (bool(d.get("deck_lesson",false)) and not custom_deck_valid()): open_adventure_deck(game)
				else: start(game,selected), true)
		else:
			game.title_button(Rect2(SIDE.position.x+24,SIDE.end.y-68,SIDE.size.x-48,50),caption,func(): start(game,selected), true)
	game.title_button(Rect2(70,816,220,46),"返回標題",func(): reset_confirm = 0; game.show_title())
	game.queue_redraw()

func _build_decree_buttons(game) -> void:
	for i: int in range(Catalog.DECREES.size()):
		var dec: Dictionary = Catalog.DECREES[i]
		var did: String = dec.id
		var col := i % 2
		var row := i / 2
		var card_r := Rect2(MODAL.position.x + 40 + col * 530, MODAL.position.y + 115 + row * 145, 510, 128)
		var open := decree_unlocked(did)
		var active := did in decrees
		var btn_label := ("✓ 已啟用" if active else "啟用詔令") if open else ("需 ★ %d 解鎖" % int(dec.stars))
		var b: Button = game.title_button(Rect2(card_r.end.x - 165, card_r.end.y - 50, 148, 36), btn_label, func():
			toggle_decree(did)
			show(game), active and open)
		b.disabled = not open
	game.title_button(Rect2(MODAL.end.x - 200, MODAL.end.y - 64, 160, 44), "關閉", func():
		show_decrees = false
		show(game), true).grab_focus()

func seal_button(game, rect: Rect2, action: Callable) -> Button:
	var b: Button = game.button(rect,"",action)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1,0.9,0.6,0.18) if state == "hover" else Color.TRANSPARENT
		style.set_corner_radius_all(36)
		if state == "focus":
			style.border_color = Color("d2ad58")
			style.set_border_width_all(2)
		b.add_theme_stylebox_override(state,style)
	return b

func paint(g) -> void:
	var title_txt := "五路遠征記" + (" · 第 %d 周目" % (ng_plus + 1) if ng_plus > 0 else "")
	g.label_at(Vector2(70,82),title_txt,40)
	var diff_name: String = Catalog.DIFFICULTIES[difficulty].name
	var card_total: int = DeckStore.pool("adventure").size()
	if tutorial_done():
		g.label_at(Vector2(70,108),"關卡 %d / %d · 累計 ★ %d / %d · 卡牌 %d/%d · 難度：%s" % [cleared_count(), STAGES.size(), total_stars(), max_stars(), unlocked_cards().size(), card_total, diff_name], 18, Color("5a4632"))
	else:
		g.label_at(Vector2(70,108),"新兵訓練 %d / %d 課 · 卡牌 %d/%d · 難度：%s" % [world_cleared_count(0), Catalog.STAGES_PER_WORLD, unlocked_cards().size(), card_total, diff_name], 18, Color("5a4632"))
		g.draw_string(g.font,Vector2(995,82),"學完第一章後開放王國詔令",HORIZONTAL_ALIGNMENT_CENTER,270,15,Color("7a6446"))
	paint_world_tabs_badges(g)
	paint_world_road(g)
	paint_side(g)
	g.label_at(Vector2(315,846),"當前出征領主：%s（%d 位已解鎖） · 牌組 %d 張" % [B.lord_name(stage_lord(g, selected) if selected >= 0 else lord), unlocked_lords().size(), stage_deck(g, selected).size()], 18, Color("5a4632"))
	if show_decrees: paint_decrees_modal(g)

func paint_world_tabs_badges(g) -> void:
	for w: int in range(WORLDS.size()):
		var tab_r := Rect2(70 + w * 294, 122, 282, 44)
		if w == world:
			g.draw_rect(tab_r.grow(3), Color("d2ad58"), false, 2.5)
		var bar_w := tab_r.size.x * float(world_cleared_count(w)) / float(Catalog.STAGES_PER_WORLD)
		if bar_w > 0.0:
			g.draw_line(Vector2(tab_r.position.x + 2, tab_r.end.y + 3), Vector2(tab_r.position.x + bar_w - 2, tab_r.end.y + 3), WORLDS[w].color, 3.0, true)

func paint_world_road(g) -> void:
	var winfo: Dictionary = WORLDS[world]
	var per := Catalog.STAGES_PER_WORLD
	var bg_col: Color = Color(winfo.color.r * 0.25 + 0.72, winfo.color.g * 0.25 + 0.68, winfo.color.b * 0.25 + 0.56, 0.52)
	g.panel(MAP, bg_col, Color("7d623b"))
	g.ink_frame(MAP.grow(-8))
	g.ground_wash(MAP.position + Vector2(240, 390), Vector2(210, 140), winfo.color, 31 + world * 17, 0.14)
	g.ground_wash(MAP.position + Vector2(720, 230), Vector2(210, 140), winfo.color, 71 + world * 19, 0.14)
	g.label_at(MAP.position + Vector2(28, 42), winfo.name, 28, winfo.color.darkened(0.18))
	g.label_at(MAP.position + Vector2(28, 68), winfo.subtitle + ("　[已解放]" if world_cleared_count(world) == per else ("" if world_unlocked(world) else "　[需先通關前域]")), 18, Color("5a4632"))
	var base := world * per
	# Draw 9 snake road segments 0->1->...->9 (with a right-hand bend from 4->5)
	for k: int in range(per - 1):
		var i0 := base + k
		var i1 := base + k + 1
		var p0: Vector2 = STAGES[i0].map
		var p1: Vector2 = STAGES[i1].map
		var cleared_seg := is_cleared(i0) and is_cleared(i1)
		var open: bool = is_cleared(i0) and unlocked(i1)
		var march := fposmod(g.clock * 1.4, 2.0) if open else 0.0
		if k == 4:
			var ctrl := Vector2(1058, (p0.y + p1.y) * 0.5)
			var curve := PackedVector2Array()
			for bi: int in range(17):
				var t := float(bi) / 16.0
				var omt := 1.0 - t
				curve.append(omt * omt * p0 + 2.0 * omt * t * ctrl + t * t * p1)
			if cleared_seg:
				g.draw_polyline(curve, Color(g.RED, 0.85), 5.0, true)
			else:
				for s: int in range(1, 16):
					if fposmod(s + march, 2.0) < 1.0:
						g.draw_circle(curve[s], 3.6 if open else 2.5, Color("b8862b") if open else Color(g.INK, 0.28))
			continue
		if cleared_seg:
			g.ink_line(p0, p1, i0 * 11 + k, Color(g.RED, 0.85), 5.0)
			continue
		var steps := int(p0.distance_to(p1) / 14.0)
		for s: int in range(1, steps):
			if fposmod(s + march, 2.0) < 1.0:
				g.draw_circle(p0.lerp(p1, float(s) / steps), 3.6 if open else 2.5, Color("b8862b") if open else Color(g.INK, 0.28))
	for local_i: int in range(per):
		paint_stage_node(g, base + local_i)

func paint_stage_node(g, i: int) -> void:
	var d: Dictionary = STAGES[i]
	var p: Vector2 = d.map
	var open := unlocked(i)
	var ours := is_cleared(i)
	var is_boss: bool = bool(d.get("boss", false))
	var is_special: bool = bool(d.get("special", false))
	var radius := 29.0 if is_boss else (26.0 if is_special else 21.0)
	var region: Color = WORLDS[d.world].color
	if i == selected:
		g.draw_circle(p, radius + 8, Color("d2ad58", 0.95))
	elif open and not ours:
		g.draw_arc(p, radius + 6 + 2.2 * sin(g.clock * 4.0), 0, TAU, 40, Color("d2ad58", 0.92), 2.8, true)
	g.draw_circle(p + Vector2(2.5, 3.5), radius, Color(0.2, 0.12, 0.06, 0.26))
	var fill_col: Color = g.RED if ours else (Color("6b3fa0") if (open and is_special and not is_boss) else (region if open else Color("a89a80")))
	g.draw_circle(p, radius, fill_col)
	g.draw_arc(p, radius, 0, TAU, 40, Color(g.INK, 0.88), 2.4, true)
	g.draw_arc(p, radius - 5, 0, TAU, 40, Color(1, 0.94, 0.8, 0.52 if open else 0.22), 1.4, true)
	if is_boss:
		g.draw_arc(p, radius + 3.2, 0, TAU, 40, Color("f4d78c", 0.95 if open else 0.45), 2.2, true)
		for k: int in range(5):
			g.draw_circle(p + Vector2((k - 2) * 8, -radius + 8 + absf(k - 2) * 1.8), 2.3, Color("f4d78c"))
	elif is_special:
		g.draw_arc(p, radius + 3.0, 0, TAU, 36, Color("e6b830", 0.90 if open else 0.42), 2.0, true)
		for a_idx: int in range(4):
			var ang := float(a_idx) * PI * 0.5
			var pip := p + Vector2(cos(ang), sin(ang)) * (radius + 3.0)
			g.draw_circle(pip, 2.8, Color("f4d78c", 0.95 if open else 0.45))
	if ours:
		g.draw_fitted(g.art("crest", 0), Rect2(p - Vector2(14, 15), Vector2(28, 30)))
	else:
		var portrait: Texture2D = g.art("bandit", 1) if d.enemy_camp else g.lord_art(d.enemy_lord, 1)
		g.draw_fitted(portrait, Rect2(p + Vector2(-21, -radius - 42), Vector2(42, 46)), Color(1, 1, 1, 1.0 if open else 0.42), true)
	# Stage code + name + star strip + rule/special pill below node
	g.draw_string(g.font, p + Vector2(-87, radius + 19), "%s %s" % [d.code, d.name], HORIZONTAL_ALIGNMENT_CENTER, 174, 15, g.INK if open else Color("665640"))
	var st := int(stars.get(d.id, 0))
	for k: int in range(Catalog.MAX_STARS_PER_STAGE):
		var sx := p.x + (k - 1.5) * 13.0
		var sy := p.y + radius + 32.0
		g.draw_circle(Vector2(sx, sy), 4.6, Color("e6b830") if k < st else Color(0.35, 0.28, 0.18, 0.25))
		g.draw_arc(Vector2(sx, sy), 4.6, 0, TAU, 16, Color(g.INK, 0.55), 1.0, true)
	var tag_r := Rect2(p + Vector2(-62, radius + 42), Vector2(124, 20))
	if is_boss:
		g.panel(tag_r, Color("8c271d") if open else Color("b68c82"), Color("e6b830") if open else Color(g.INK, 0.35))
		g.draw_string(g.font, tag_r.position + Vector2(3, 15), "★ 畢業考" if d.world == 0 else "★ 大考", HORIZONTAL_ALIGNMENT_CENTER, tag_r.size.x - 6, 11, Color("fff3cf") if open else Color(g.INK, 0.5))
	elif is_special:
		g.panel(tag_r, Color("57317f") if open else Color("9a88ad"), Color("e6b830") if open else Color(g.INK, 0.35))
		g.draw_string(g.font, tag_r.position + Vector2(3, 15), "★ 小考", HORIZONTAL_ALIGNMENT_CENTER, tag_r.size.x - 6, 11, Color("fff3cf") if open else Color(g.INK, 0.5))
	else:
		g.panel(tag_r, Color("f6ead0") if open else Color("dcd1b8"), Color("8a5a2b") if open else Color(g.INK, 0.35))
		g.draw_string(g.font, tag_r.position + Vector2(3, 15), d.rule_tag, HORIZONTAL_ALIGNMENT_CENTER, tag_r.size.x - 6, 11, Color("5a3818") if open else Color(g.INK, 0.45))

func paint_side(g) -> void:
	var d: Dictionary = STAGES[selected]
	var x: float = SIDE.position.x
	var y: float = SIDE.position.y
	var w: float = SIDE.size.x
	g.panel(SIDE,Color("efe0bd"))
	g.ink_frame(SIDE.grow(-8))
	var winfo: Dictionary = WORLDS[d.world]
	var is_boss: bool = bool(d.get("boss", false))
	var is_special: bool = bool(d.get("special", false))
	var exam := ("畢業考" if d.world == 0 else "大考") if is_boss else ("小考" if is_special else "")
	var status := " · ★ %d/%d" % [int(stars.get(d.id, 0)), Catalog.MAX_STARS_PER_STAGE] if int(stars.get(d.id, 0)) > 0 else (" · 未解鎖" if not unlocked(selected) else "")
	g.draw_string(g.font,Vector2(x,y+34),winfo.name+(" · ★ "+exam if not exam.is_empty() else "")+status,HORIZONTAL_ALIGNMENT_CENTER,w,17,Color("9b2f2f") if is_boss else (Color("6b3fa0") if is_special else winfo.color))
	g.draw_string(g.font,Vector2(x,y+70),"%s %s" % [d.code, d.name],HORIZONTAL_ALIGNMENT_CENTER,w,30,g.INK)
	var portrait: Texture2D = g.art("bandit",1) if d.enemy_camp else g.lord_art(d.enemy_lord,1)
	g.draw_fitted(portrait,Rect2(x+24,y+84,88,94),Color.WHITE,true)
	var lesson := is_lesson(selected)
	var eff_ai := stage_ai(selected)
	g.label_at(Vector2(x+126,y+108),("對手　" if lesson else "守將　")+ruler_name(selected),20)
	var foe_line := "照教學腳本出兵" if scripted_foe(selected) else "AI %s" % ["簡單","普通","困難"][eff_ai]
	g.label_at(Vector2(x+126,y+134),"%s · %d 路%s" % [foe_line, d.active_lanes.size(), " · 守城 %d 秒" % int(d.survive_time) if d.survive_time > 0.0 else ""],17,Color("6f5a3e"))
	var terrain_line := preload("res://adventure_terrain.gd").summary(d)
	if not d.get("conveyor",{}).is_empty():
		var cv_line := "傳送帶 · " + terrain_line if not terrain_line.is_empty() else "牌組　補給傳送帶（免費送牌）"
		g.label_at(Vector2(x+126,y+160),cv_line,15 if not terrain_line.is_empty() else 17,Color("8e4a1e"))
	elif terrain_line.is_empty(): g.label_at(Vector2(x+126,y+160),"牌組　" + ("教學固定牌組" if d.deck is Array else ("自己挑 8 張" if bool(d.get("deck_lesson",false)) else "自組＋本關新卡")),17,Color("6f5a3e"))
	else: g.label_at(Vector2(x+126,y+160),"地形　" + terrain_line,16,Color("3c6e2e"))
	# The lesson: what this stage teaches.
	var rule_r := Rect2(x + 20, y + LESSON_Y, w - 40, 118)
	var rule_bd := Color("a62b20") if is_boss else (Color("6b3fa0") if is_special else Color("b8862b"))
	g.panel(rule_r, Color("f8e5d8") if is_boss else (Color("efe6fa") if is_special else Color("f7ebd0")), rule_bd)
	g.label_at(rule_r.position + Vector2(12, 24), "【本關教學】" + d.rule_tag, 17, rule_bd.darkened(0.25))
	var rule_para := TextParagraph.new()
	rule_para.width = rule_r.size.x - 24.0
	rule_para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	rule_para.max_lines_visible = 4
	rule_para.add_string(d.rule_desc, g.font, 14)
	rule_para.draw(g.get_canvas_item(), rule_r.position + Vector2(12, 32), g.INK)
	# Two chips: the new enemy you meet here, and the new card you play here.
	var foe_kind := String(d.get("new_enemy",""))
	paint_chip(g, chip_rect(0), "新敵人", foe_kind, g.BLUE, ("敵方領主技能" if foe_kind == "skill" else ""))
	var fresh: Array = d.rewards
	var fresh_name := "、".join(fresh.map(func(k: String) -> String: return B.CARDS[k].name)) if not fresh.is_empty() else ""
	var card_chip := card_chip_of(selected)
	paint_chip(g, chip_rect(1), card_chip[0], card_chip[1], Color("3c6e2e"), fresh_name if card_chip[1] in fresh else "")
	# The enemy hand, except in scripted lessons where the script sends the troops.
	if not scripted_foe(selected):
		g.label_at(Vector2(x+22,y+ENEMY_Y-8),"敵軍陣容（懸停看說明）",15)
		for i: int in range(d.enemy_deck.size()):
			var cell := Rect2(x+22+i*53,y+ENEMY_Y,48,50)
			g.panel(cell,Color("f6ead0"))
			g.draw_fitted(g.art(g.card_art_kinds(d.enemy_deck[i])[0],1),cell.grow(-3),Color.WHITE,true)
	else:
		var hand: Array = []
		for k in d.deck:
			if not k in hand: hand.append(k)
		g.label_at(Vector2(x+22,y+ENEMY_Y-8),"這一課的手牌",15)
		for i: int in range(hand.size()):
			var cell := Rect2(x+22+i*53,y+ENEMY_Y,48,50)
			g.panel(cell,Color("f6ead0"))
			g.draw_fitted(g.art(g.card_art_kinds(hand[i])[0]),cell.grow(-3),Color.WHITE,true)
	# What the first clear keeps.
	var got_ever := is_ever_cleared(selected)
	var prize: String = Catalog.UNLOCK_LORDS.get(d.id,"")
	var keeps: Array = []
	if not fresh.is_empty(): keeps.append("卡牌 " + fresh_name)
	if B.LORDS.has(prize): keeps.append("領主 " + B.lord_name(prize))
	var keep_line := ("首通獎勵：" + "、".join(keeps) + ("（已取得）" if got_ever else "")) if not keeps.is_empty() else ("全破：王都凱旋與新周目" if selected == STAGES.size() - 1 else "")
	# The chosen difficulty, and on 極難 the enemy's extra passives for this stage.
	var cfg: Dictionary = Catalog.DIFFICULTIES[difficulty]
	var passives := difficulty_passives(selected)
	var diff_line := ("極難被動：" + "、".join(passives.map(func(p: Dictionary) -> String: return "%s（%s）" % [p.name,p.desc]))) if not passives.is_empty() else ("難度　%s：%s" % [cfg.name,cfg.desc])
	var Lib = preload("res://card_library.gd")
	g.draw_string(g.font,Vector2(x+22,y+452),Lib.clip_line(g.font,diff_line,14,w-44.0),HORIZONTAL_ALIGNMENT_LEFT,w-44,14,Color("8c271d") if not passives.is_empty() else Color("6f5a3e"))
	g.draw_string(g.font,Vector2(x+22,y+474),Lib.clip_line(g.font,keep_line,16,w-44.0),HORIZONTAL_ALIGNMENT_LEFT,w-44,16,Color("6f5a3e") if got_ever else g.RED)
	if not unlocked(selected):
		var prev: Dictionary = STAGES[maxi(0, selected - 1)]
		g.draw_string(g.font,Vector2(x,SIDE.end.y-34),"先通過上一關「%s %s」" % [prev.code, prev.name],HORIZONTAL_ALIGNMENT_CENTER,w,20,Color(g.INK,0.62))

# The side panel's card chip: [caption, card]. A lesson without a reward names the card it drills;
# a lesson whose reward is not in its own hand says the card comes after the lesson.
func card_chip_of(i: int) -> Array:
	var d: Dictionary = STAGES[i]
	var fresh: Array = d.rewards
	if d.deck is Array:
		if fresh.is_empty(): return ["本課用牌", d.deck[0]]
		if not fresh[0] in d.deck: return ["過關獲得", fresh[0]]
	return ["本關新卡", fresh[0] if not fresh.is_empty() else ""]

# A labelled chip with a card picture: the stage's new enemy or new card ("" kind = none this stage).
func paint_chip(g, r: Rect2, caption: String, kind: String, color: Color, label: String = "") -> void:
	g.panel(r, Color("f6ead0"), color)
	g.draw_string(g.font, r.position + Vector2(8, 18), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	var name := label
	if B.CARDS.has(kind):
		g.draw_fitted(g.art(g.card_art_kinds(kind)[0], 1 if caption == "新敵人" else 0), Rect2(r.end.x - 50, r.position.y + 3, 46, 46), Color.WHITE, true)
		if name.is_empty(): name = B.CARDS[kind].name
	elif kind == "skill":
		var foe: String = STAGES[selected].enemy_lord
		g.draw_fitted(g.lord_art(foe, 1), Rect2(r.end.x - 50, r.position.y + 3, 46, 46), Color.WHITE, true)
		name = B.lord_data(foe).get("skill", label)
	if name.is_empty(): name = "—"
	g.draw_string(g.font, r.position + Vector2(8, 42), name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 64, 16, g.INK)

func paint_decrees_modal(g) -> void:
	g.draw_rect(Rect2(Vector2.ZERO, L.VIEWPORT_SIZE), Color(0.10, 0.08, 0.05, 0.55))
	g.panel(MODAL, Color("f0e2c2"))
	g.ink_frame(MODAL.grow(-8))
	g.label_at(MODAL.position + Vector2(40, 52), "王國詔令（局外加成）", 32)
	g.label_at(MODAL.position + Vector2(40, 82), "每關記最高難度的 ★（簡單 1★／普通 2★／困難 3★／極難 4★），累計 ★ 達標即可永久解鎖並自由開關。", 17, Color("5a4632"))
	g.label_at(Vector2(MODAL.end.x - 240, MODAL.position.y + 52), "目前累計：★ %d / %d" % [total_stars(), max_stars()], 22, Color("8a5a2b"))
	for i: int in range(Catalog.DECREES.size()):
		var dec: Dictionary = Catalog.DECREES[i]
		var col := i % 2
		var row := i / 2
		var card_r := Rect2(MODAL.position.x + 40 + col * 530, MODAL.position.y + 115 + row * 145, 510, 128)
		var open := decree_unlocked(dec.id)
		var active: bool = String(dec.id) in decrees
		var bg := Color("e6f0d8") if (open and active) else (Color("f8eed6") if open else Color("dfd5bd"))
		var bd := Color("3c7a3e") if (open and active) else (Color("8a5a2b") if open else Color(g.INK, 0.4))
		g.panel(card_r, bg, bd)
		g.label_at(card_r.position + Vector2(18, 34), dec.name, 22, g.INK if open else Color(g.INK, 0.55))
		g.draw_multiline_string(g.font, card_r.position + Vector2(18, 64), dec.desc, HORIZONTAL_ALIGNMENT_LEFT, 320, 17, 2, Color("5a4632") if open else Color(g.INK, 0.48))
		g.label_at(card_r.position + Vector2(18, 106), ("已解鎖（需要 ★%d）" if open else "未解鎖（需 ★%d）") % int(dec.stars), 14, Color("3c7a3e") if open else Color("7a2b22"))
