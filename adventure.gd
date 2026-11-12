extends RefCounted
# 冒險模式：大地圖征服 (2026-11-12 remake). Runs the battles, keeps the progress and draws the map.
# The territories, their roads, rulers and rewards live in campaign_catalog.gd; the scenes in
# campaign_story_data.gd. A territory can be attacked once a neighbour is ours (the royal seat needs
# all four capitals), so the route is the player's choice.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Battle = preload("res://battle.gd")
const DeckStore = preload("res://deck_store.gd")
const Catalog = preload("res://campaign_catalog.gd")
const CHAPTERS = Catalog.CHAPTERS
const STARTER_CARDS = Catalog.STARTER_CARDS
var STAGES: Array = Catalog.stages()
var index := -1 # the territory being fought over, -1 outside adventure battles
var selected := 0 # the territory shown on the map panel
var opening := preload("res://farm_opening.gd").new()
var finale := preload("res://adventure_finale.gd").new()
var ending := preload("res://adventure_ending.gd").new()
var road_story := preload("res://road_toll_story.gd").new()
var recruit := ""
var outcome := ""
var cleared: Dictionary = {}
var custom_deck: Array = [] # the deck built for `lord`
var lord := "adventure" # who leads the army: the border lord, or a lord won with a capital
var decks: Dictionary = {} # lord -> the deck last built for it
var progress_path := "user://adventure.json"

# Lords the player may take to war: the border lord, then one per conquered capital.
func unlocked_lords() -> Array:
	var result: Array = ["adventure"]
	for i: int in range(STAGES.size()):
		var won: String = Catalog.UNLOCK_LORDS.get(STAGES[i].id,"")
		if is_cleared(i) and B.LORDS.has(won) and not won in result: result.append(won)
	return result

# Cards a lord may put in the adventure deck: the unlocked ones it is allowed, plus (for a lord of
# another faction) that faction's own cards, which come with the lord.
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

# Eight cards for the current lord when none were chosen: troops first, so the deck can attack.
func auto_deck() -> Array:
	var pool := card_pool()
	pool.sort_custom(func(a: String, b: String) -> bool: return not B.card_faction(a).is_empty() and B.card_faction(b).is_empty()) # the lord's own faction first
	var troops: Array = pool.filter(func(k: String) -> bool: return B.CARDS[k].type == "unit")
	var rest: Array = pool.filter(func(k: String) -> bool: return B.CARDS[k].type != "unit")
	return (troops.slice(0,5)+rest+troops.slice(5)).slice(0,8)

func unlocked_cards() -> Array:
	var result: Array = STARTER_CARDS.duplicate()
	if not recruit.is_empty() and not recruit in result:
		result.append(recruit)
	for i: int in range(STAGES.size()):
		if is_cleared(i):
			for k: String in STAGES[i].rewards:
				if not k in result:
					result.append(k)
	return result

func custom_deck_valid() -> bool:
	if custom_deck.size() != 8: return false
	var pool: Array = card_pool()
	for k in custom_deck:
		if not k is String or not k in pool: return false
	return DeckStore.valid(custom_deck,lord)

func load_progress() -> void:
	cleared = {}
	recruit = ""
	custom_deck = []
	lord = "adventure"
	decks = {}
	if not FileAccess.file_exists(progress_path): return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(progress_path))
	if parsed is Dictionary and parsed.get("cleared") is Array:
		for id in parsed.cleared:
			if Catalog.index_of(str(id)) >= 0: cleared[str(id)] = true # saves from the old ten-stage campaign keep only what still exists
		if parsed.get("recruit", "") in ["bandit","knight"]: recruit = parsed.recruit
		if parsed.get("custom_deck") is Array:
			var valid_list: Array = []
			for c in parsed.custom_deck:
				if c is String and B.CARDS.has(c): valid_list.append(c)
			if valid_list.size() == 8: custom_deck = valid_list
		if parsed.get("decks") is Dictionary:
			for who in parsed.decks:
				if B.LORDS.has(who) and parsed.decks[who] is Array: decks[who] = parsed.decks[who].filter(func(c) -> bool: return c is String and B.CARDS.has(c))
		if parsed.get("lord","") in unlocked_lords(): lord = parsed.lord

func save_progress() -> bool:
	var file := FileAccess.open(progress_path,FileAccess.WRITE)
	if file == null: return false
	if custom_deck.size() == 8: decks[lord] = custom_deck.duplicate()
	file.store_string(JSON.stringify({"cleared":cleared.keys(),"recruit":recruit,"custom_deck":custom_deck,"lord":lord,"decks":decks}))
	file.flush()
	return file.get_error() == OK

func is_cleared(i: int) -> bool:
	return cleared.has(STAGES[i].id)

# Open to attack: the first farm, or a territory with a conquered neighbour (and, for the royal
# seat, every capital it names).
func unlocked(i: int) -> bool:
	if i == 0: return true
	var d: Dictionary = STAGES[i]
	if d.get("needs",[]).any(func(id: String) -> bool: return not cleared.has(id)): return false
	return d.links.any(func(id: String) -> bool: return cleared.has(id))

func cleared_count() -> int:
	return range(STAGES.size()).filter(func(i: int) -> bool: return is_cleared(i)).size()

# The first territory that can be attacked now (the royal seat when the whole map is ours).
func frontier() -> int:
	for i: int in range(STAGES.size()):
		if unlocked(i) and not is_cleared(i): return i
	return STAGES.size()-1

# The first lesson is always fought by the border lord; everywhere else the chosen lord leads.
func stage_lord(_game, i: int) -> String:
	return lord if STAGES[i].deck is String else STAGES[i].lord

func stage_deck(game, i: int) -> Array:
	if STAGES[i].deck is String:
		if custom_deck_valid(): return custom_deck.duplicate()
		if card_pool().size() >= 8: return auto_deck()
		if game.player_deck.size() == 8 and DeckStore.valid(game.player_deck,stage_lord(game,i)):
			return game.player_deck.duplicate()
		return ["farmer","hunter","militia","mob","ram","rain","mill","healer"]
	return STAGES[i].deck.duplicate()

func open_adventure_deck(game) -> void:
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
	outcome = ""
	var d: Dictionary = STAGES[index]
	var lord := stage_lord(game,index)
	var deck := stage_deck(game,index)
	if not DeckStore.valid(deck,lord,d.get("allow_duplicates",false) and not d.deck is String):
		index = -1
		open_adventure_deck(game)
		return
	game.spectating = false
	var ai: int = d.get("ai",1)
	var enemy: Array = d.get("enemy_deck",B.PRESETS[ai]).duplicate()
	game.model = Battle.new(7300+index,deck,enemy,lord,d.get("enemy_lord","iron"))
	game.model.active_lanes.assign(d.get("active_lanes",[0,1,2,3,4]))
	if not d.enemy_lord_active:
		game.model.lord_active[1] = false
		game.model.lords[1].hp = 0
	if d.enemy_camp:
		game.model.home_cards[1] = ""
		game.model.buildings = game.model.buildings.filter(func(b): return b.team == 0)
	game.model.refresh_territory()
	game.model.difficulty = ai
	game.model.ai_enabled = [false,true]
	game.model.invasion_victory.assign([true,true])
	for b: Array in d.get("buildings",[]): game.model.add_building(1,Vector2i(b[0],b[1]),b[2])
	game.model.night_decay = not d.opening # the first lesson has no clock to beat
	opening.active = false
	if d.opening: opening.start(game)
	game.enter_battle("%s · %s" % [d.name,d.goal])
	if d.dialogue: road_story.begin(game)

func update(game) -> void:
	if index < 0 or game.model.paused or not outcome.is_empty(): return
	var m = game.model
	if not m.ended: return
	var won: bool = m.winner == 0
	if won and is_opening() and recruit.is_empty():
		ending.begin(game)
		return
	var first_crowning: bool = won and STAGES[index].id == "royal_seat" and not is_cleared(index)
	settle(won,"")
	if first_crowning:
		finale.show(game)
		return
	if won and STAGES[index].dialogue: road_story.begin(game, true)

func is_opening() -> bool:
	return index >= 0 and index < STAGES.size() and STAGES[index].opening

func active_story():
	return road_story

func settle(won: bool, reason: String) -> void:
	outcome = ("征服「%s」！" % STAGES[index].name) if won else "進攻失敗"+reason
	if won and not is_cleared(index):
		cleared[STAGES[index].id] = true
		save_progress()
	if won: selected = frontier()

# ---- the conquest map ---------------------------------------------------------------------------
const MAP := Rect2(70,150,960,650)
const SIDE := Rect2(1060,150,470,650)
const WASH := [Vector2(150,150),Vector2(215,95),Vector2(215,80),Vector2(215,80),Vector2(215,95),Vector2(95,150)]
const LABEL := [Vector2(100,330),Vector2(372,196),Vector2(808,336),Vector2(808,640),Vector2(372,778),Vector2(880,385)]

func ruler_name(i: int) -> String:
	return "強盜" if STAGES[i].enemy_camp else B.lord_name(STAGES[i].enemy_lord)

func show(game) -> void:
	load_progress()
	index = -1
	if selected < 0 or selected >= STAGES.size(): selected = frontier()
	game.screen = "adventure"
	game.clear_ui()
	for i: int in range(STAGES.size()):
		var choice := i
		var b: Button = seal_button(game,Rect2(STAGES[i].map-Vector2(34,34),Vector2(68,68)),func(): selected = choice; show(game))
		b.tooltip_text = "%s · %s" % [STAGES[i].name,ruler_name(i)]
	var d: Dictionary = STAGES[selected]
	var words: String = d.story
	if B.is_minion(d.enemy_lord) and not d.enemy_camp: words += "\n守將特性："+B.minion_text(d.enemy_lord)
	elif not d.enemy_camp: words += "\n守將技能："+B.LORDS[d.enemy_lord].skill
	game.library.text_box(Rect2(SIDE.position.x+30,SIDE.position.y+236,SIDE.size.x-60,118),words,18)
	if unlocked(selected):
		var caption := "再打一次" if is_cleared(selected) else "出征"
		if d.deck is String:
			game.title_button(Rect2(SIDE.position.x+60,SIDE.position.y+516,SIDE.size.x-120,44),"%s · 編成牌組（%d 張可選）" % [B.lord_name(lord).trim_suffix("領主"),card_pool().size()],func(): open_adventure_deck(game))
			game.title_button(Rect2(SIDE.position.x+60,SIDE.end.y-72,SIDE.size.x-120,52),caption,func():
				if stage_deck(game,selected).size() != 8: open_adventure_deck(game)
				else: start(game,selected)
			,true)
		else:
			game.title_button(Rect2(SIDE.position.x+60,SIDE.end.y-72,SIDE.size.x-120,52),caption,func(): start(game,selected),true)
	game.title_button(Rect2(100,820,230,46),"返回標題",game.show_title)
	game.queue_redraw()

func seal_button(game, rect: Rect2, action: Callable) -> Button:
	var b: Button = game.button(rect,"",action)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1,0.9,0.6,0.18) if state == "hover" else Color.TRANSPARENT
		style.set_corner_radius_all(34)
		if state == "focus":
			style.border_color = Color("d2ad58")
			style.set_border_width_all(2)
		b.add_theme_stylebox_override(state,style)
	return b

func paint(g) -> void:
	g.label_at(Vector2(90,88),"征服地圖",44)
	g.label_at(Vector2(290,88),"領地 %d / %d" % [cleared_count(),STAGES.size()],22)
	g.label_at(Vector2(450,88),"已解鎖卡牌：%d" % unlocked_cards().size(),22)
	g.label_at(Vector2(680,88),"出征領主：%s（%d 位可選）" % [B.lord_name(lord),unlocked_lords().size()],22)
	g.label_at(Vector2(90,126),Catalog.PREMISE,20)
	paint_map(g)
	paint_side(g)

func paint_map(g) -> void:
	g.panel(MAP,Color(0.93,0.86,0.70,0.62))
	for i: int in range(CHAPTERS.size()):
		g.ground_wash(CHAPTERS[i].at+Vector2(0,80),WASH[i],CHAPTERS[i].color,11+i*12,0.10)
		g.draw_string(g.font,LABEL[i],CHAPTERS[i].name,HORIZONTAL_ALIGNMENT_LEFT,-1,22,CHAPTERS[i].color)
	# Roads: inked red between two of our territories, a marching dotted line along a road we can
	# attack down, faint dots elsewhere.
	for i: int in range(STAGES.size()):
		for other: String in STAGES[i].links:
			var j := Catalog.index_of(other)
			if j <= i: continue
			var a: Vector2 = STAGES[i].map
			var b: Vector2 = STAGES[j].map
			if is_cleared(i) and is_cleared(j):
				g.ink_line(a,b,i*7+j,Color(g.RED,0.85),4.5)
				continue
			var open: bool = (is_cleared(i) and unlocked(j)) or (is_cleared(j) and unlocked(i))
			var steps := int(a.distance_to(b)/13)
			var march := fposmod(g.clock*1.2,2.0) if open else 0.0
			for s: int in range(1,steps):
				if fposmod(s+march,2.0) < 1.0: g.draw_circle(a.lerp(b,float(s)/steps),3.2 if open else 2.4,Color("b8862b") if open else Color(g.INK,0.32))
	for i: int in range(STAGES.size()): paint_seal(g,i)

func paint_seal(g, i: int) -> void:
	var d: Dictionary = STAGES[i]
	var p: Vector2 = d.map
	var open := unlocked(i)
	var ours := is_cleared(i)
	var radius := 32.0 if d.capital or i == STAGES.size()-1 else 26.0
	var region: Color = CHAPTERS[d.chapter].color
	if i == selected: g.draw_circle(p,radius+8,Color("d2ad58",0.95))
	elif open and not ours: g.draw_arc(p,radius+6+2.5*sin(g.clock*4.0),0,TAU,40,Color("d2ad58",0.9),3,true) # can be attacked now
	g.draw_circle(p+Vector2(3,4),radius,Color(0.2,0.12,0.06,0.25))
	g.draw_circle(p,radius,g.RED if ours else (region if open else Color("a89a80")))
	g.draw_arc(p,radius,0,TAU,40,Color(g.INK,0.85),2.5,true)
	g.draw_arc(p,radius-6,0,TAU,40,Color(1,0.94,0.8,0.5 if open else 0.25),1.5,true)
	if d.capital or i == STAGES.size()-1:
		for k: int in range(5): g.draw_circle(p+Vector2((k-2)*9,-radius+9-absf(k-2)*-2.0),2.4,Color("f4d78c")) # a little crown
	# Who holds it: our crest once conquered, otherwise its ruler looking out over the seal.
	if ours: g.draw_fitted(g.art("crest",0),Rect2(p-Vector2(19,20),Vector2(38,40)))
	else:
		var portrait: Texture2D = g.art("bandit",1) if d.enemy_camp else g.lord_art(d.enemy_lord,1)
		g.draw_fitted(portrait,Rect2(p+Vector2(-27,-radius-46),Vector2(54,62)),Color(1,1,1,1.0 if open else 0.45),true)
	g.draw_string(g.font,p+Vector2(-90,radius+24),d.name,HORIZONTAL_ALIGNMENT_CENTER,180,18,g.INK if open else Color(g.INK,0.5))

func paint_side(g) -> void:
	var d: Dictionary = STAGES[selected]
	var x: float = SIDE.position.x
	var y: float = SIDE.position.y
	var w: float = SIDE.size.x
	g.panel(SIDE,Color("efe0bd"))
	g.ink_frame(SIDE.grow(-8))
	var chapter: Dictionary = CHAPTERS[d.chapter]
	g.draw_string(g.font,Vector2(x,y+46),chapter.name+("首府" if d.capital else ""),HORIZONTAL_ALIGNMENT_CENTER,w,20,chapter.color)
	g.draw_string(g.font,Vector2(x,y+94),d.name,HORIZONTAL_ALIGNMENT_CENTER,w,36,g.INK)
	var portrait: Texture2D = g.art("bandit",1) if d.enemy_camp else g.lord_art(d.enemy_lord,1)
	g.draw_fitted(portrait,Rect2(x+34,y+108,110,120),Color.WHITE,true)
	g.label_at(Vector2(x+164,y+146),"守將　"+ruler_name(selected),22)
	g.label_at(Vector2(x+164,y+178),"強度　"+["簡單","普通","困難"][d.ai],20,Color("6f5a3e"))
	g.label_at(Vector2(x+164,y+208),"戰場　%d 路" % d.active_lanes.size(),20,Color("6f5a3e"))
	# The ruler's eight cards.
	g.label_at(Vector2(x+30,y+378),"守軍",18)
	for i: int in range(d.enemy_deck.size()):
		var cell := Rect2(x+30+i*51,y+388,47,50)
		g.panel(cell,Color("f6ead0"))
		g.draw_fitted(g.art(B.CARDS[d.enemy_deck[i]].get("art",[d.enemy_deck[i]])[0],1),cell.grow(-3),Color.WHITE,true)
	# What conquering it pays.
	g.label_at(Vector2(x+30,y+466),"征服獎勵",18,g.RED)
	if d.rewards.is_empty(): g.label_at(Vector2(x+124,y+466),"王座" if selected == STAGES.size()-1 else "無",18)
	for i: int in range(d.rewards.size()):
		var cell := Rect2(x+124+i*104,y+446,98,50)
		g.panel(cell,Color("f6ead0") if not is_cleared(selected) else Color("e4d6b4"))
		g.draw_fitted(g.art(B.CARDS[d.rewards[i]].get("art",[d.rewards[i]])[0]),Rect2(cell.position+Vector2(3,2),Vector2(42,46)),Color.WHITE,true)
		var name: String = B.CARDS[d.rewards[i]].name
		g.draw_string(g.font,cell.position+Vector2(46,31),name,HORIZONTAL_ALIGNMENT_CENTER,50,12 if name.length() > 3 else 15,g.INK)
	var prize: String = Catalog.UNLOCK_LORDS.get(d.id,"")
	if B.LORDS.has(prize): g.label_at(Vector2(x+30,y+498) if d.rewards.is_empty() else Vector2(x+124+d.rewards.size()*104+6,y+466),("可出戰：" if is_cleared(selected) else "解鎖領主：")+B.lord_name(prize),16,g.RED)
	if not unlocked(selected):
		var needs: Array = d.get("needs",[])
		var held: int = needs.filter(func(id: String) -> bool: return cleared.has(id)).size()
		var why: String = ("征服四座首府後開放（%d / %d）" % [held,needs.size()]) if not needs.is_empty() and held < needs.size() else "先征服相鄰的領地"
		g.draw_string(g.font,Vector2(x,SIDE.end.y-44),why,HORIZONTAL_ALIGNMENT_CENTER,w,22,Color(g.INK,0.6))
	elif is_cleared(selected):
		g.draw_string(g.font,Vector2(x,y+548) if not d.deck is String else Vector2(x,y+508),"已是我方領地",HORIZONTAL_ALIGNMENT_CENTER,w,17,g.RED)
