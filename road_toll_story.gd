extends RefCounted
var lord_portrait: Texture2D

var lines: Array = []
var step := 0
var victory := false
var heading := ""
var opening_caption := ""
var victory_caption := ""
var next_caption := ""
var foe := "" # the territory's ruler: the "foe" portrait
var camp := false

func begin(g, won: bool = false) -> void:
	victory = won
	step = 0
	var idx: int = g.adventure.index
	var recruit: String = g.adventure.recruit
	setup_stage_story(idx, recruit, won)
	show(g)

func setup_stage_story(idx: int, recruit: String, won: bool) -> void:
	var catalog = preload("res://campaign_catalog.gd")
	var cards = preload("res://balance.gd")
	var stage: Dictionary = catalog.stages()[idx]
	foe = stage.enemy_lord
	camp = stage.enemy_camp
	heading = "%s · %s" % [stage.get("code",""), stage.name]
	opening_caption = ("新兵訓練 · 本課：%s" % stage.rule_tag) if stage.world == 0 else ("%s · 本關教學：%s" % [catalog.WORLDS[stage.world].name,stage.rule_tag])
	victory_caption = "凱旋 · "+catalog.WORLDS[stage.world].name
	next_caption = "返回遠征地圖"
	lines = preload("res://campaign_story_data.gd").dialogue(stage.id,recruit,won)
	if won and not stage.rewards.is_empty():
		# One line per new card: what it is for, in the stage's own words when it has them.
		var names: Array = stage.rewards.map(func(k): return "「%s」（%s）" % [cards.CARDS[k].name,cards.CARDS[k].role])
		var note: String = stage.get("card_note","")
		lines.append(["新卡入庫","、".join(names)+"正式加入你的卡池。"+("\n"+note if not note.is_empty() else "\n往後可以放進出征牌組。"),"lord",stage.rewards[0]])
	var prize: String = catalog.UNLOCK_LORDS.get(stage.id,"")
	if won and cards.LORDS.has(prize): lines.append(["新的領主",cards.lord_name(prize)+"願意為你出戰。\n在遠征畫面或「編成牌組」換上，就能率領"+cards.FACTIONS[cards.lord_faction(prize)]+"陣營出征。","foe","lord"])

func advance(g) -> void:
	if g.screen != "road_toll_story": return
	step += 1
	if step < lines.size(): show(g)
	elif victory: g.show_adventure()
	else: g.enter_battle(g.adventure.STAGES[g.adventure.index].goal)

func skip(g) -> void:
	if g.screen != "road_toll_story": return
	if victory: g.show_adventure()
	else: g.enter_battle(g.adventure.STAGES[g.adventure.index].goal)

func show(g) -> void:
	g.screen = "road_toll_story"
	g.clear_ui()
	var line: Array = lines[step]
	g.library.text_box(Rect2(115,610,1370,48),line[0],30)
	var text = g.library.text_box(Rect2(115,666,1370,100),line[1],26)
	text.scroll_active = false
	var caption := "繼續"
	if step == lines.size()-1: caption = next_caption if victory else "開始戰鬥"
	g.title_button(Rect2(1010,784,170,54),"跳過",func(): skip(g))
	g.title_button(Rect2(1200,784,280,54),caption,func(): advance(g),true).grab_focus()
	g.queue_redraw()

# A portrait by its key: the ruler ("foe", in blue), one of the fixed cast, or any card's art.
func texture(g, kind: String) -> Texture2D:
	if kind == "foe": return g.art("bandit",1) if camp else g.lord_art(foe,1)
	if kind == "lord": return g.lord_art(g.adventure.lord,0)
	if kind == "guard": return g.art("militia")
	if g.B.LORDS.has(kind): return g.lord_art(kind,0)
	if g.B.CARDS.has(kind): return g.art(kind)
	if lord_portrait == null: lord_portrait = load("res://assets/manuscript-v1/adventure-lord.png")
	return lord_portrait

func paint(g) -> void:
	g.draw_rect(Rect2(28,28,1544,844),Color(0.18,0.15,0.10,0.18))
	g.label_at(Vector2(80,85),heading,36)
	g.label_at(Vector2(80,123),victory_caption if victory else opening_caption,22)
	var line: Array = lines[step]
	var actor: Texture2D = texture(g,line[2])
	var other: Texture2D = texture(g,line[3])
	var rect: Rect2 = g.fitted_rect(actor.get_size(),Rect2(125,150,600,430),true)
	g.draw_texture_rect(actor,rect,false) # all portraits face right (the bandit art was turned 2026-11-03)
	var right: Rect2 = g.fitted_rect(other.get_size(),Rect2(875,135,600,445),true)
	g.draw_set_transform(Vector2(right.position.x*2+right.size.x,0),0,Vector2(-1,1))
	g.draw_texture_rect(other,right,false,Color(0.65,0.62,0.56,0.8))
	g.draw_set_transform(Vector2.ZERO)
	g.panel(Rect2(80,590,1440,270),Color("eddfbc"))
	g.draw_line(Vector2(110,655),Vector2(1490,655),Color("ad8b50"),2)
	g.label_at(Vector2(115,819),"%d / %d" % [step+1,lines.size()],20)
