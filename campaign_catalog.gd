extends RefCounted
# 冒險模式：大地圖征服 (2026-11-12 remake). Authoring data only: no battle, UI, save files or
# resource loading. Fifteen territories joined by roads; a territory can be attacked once a
# neighbouring one is ours, so the player picks the order. Each is held by its own ruler (the
# roguelike's 小怪領主 with their passives, real lords in the capitals) and pays out cards.
const B = preload("res://balance.gd")
const DeckStore = preload("res://deck_store.gd")
const RogueCatalog = preload("res://roguelike_catalog.gd")
# Regions of the map (a stage's "chapter" is its region).
const CHAPTERS := [
	{"name":"邊境","color":Color("6f8a45"),"at":Vector2(225,400)},
	{"name":"麥田諸侯","color":Color("a8842c"),"at":Vector2(595,170)},
	{"name":"高塔學院","color":Color("3f6a9a"),"at":Vector2(615,335)},
	{"name":"墓園沼澤","color":Color("6a5277"),"at":Vector2(615,635)},
	{"name":"魔物荒原","color":Color("b0602c"),"at":Vector2(595,800)},
	{"name":"王都","color":Color("963f30"),"at":Vector2(935,400)},
]
const STARTER_CARDS := ["farmer","hunter","militia"]
const GOAL := "攻入敵方底線獲勝；敵軍攻入我方底線則失敗。"
const PREMISE := "老王駕崩，遺詔只有一句：史官的地圖上，哪個顏色塗得最多，誰就是新王。"
const ALL_LANES := [0,1,2,3,4]
const MIDDLE_LANES := [1,2,3]
# The four capitals whose fall opens the road to the royal seat.
const CAPITALS := ["lion_keep","clock_tower","blood_chapel","dragon_vale"]
# Side roads pay in lords (producer 2026-11-12): conquer a capital and its lord may lead our army,
# bringing that faction's cards. A lord not in B.LORDS (yet) is simply not offered.
const UNLOCK_LORDS := {"lion_keep":"lion","clock_tower":"mage","blood_chapel":"vampire","dragon_vale":"beast","royal_seat":"iron"}

# One territory. The enemy's deck is its ruler's roguelike deck unless one is given.
static func land(id: String, chapter: int, name: String, ruler: String, ai: int, at: Vector2, links: Array, rewards: Array, story: String, lanes: Array = ALL_LANES, buildings: Array = []) -> Dictionary:
	return {"id":id,"chapter":chapter,"name":name,"lord":"adventure","kind":"conquer","ai":ai,"enemy_lord":ruler,"story":story,"goal":GOAL,
		"deck":"player","enemy_deck":RogueCatalog.foe_deck(ruler),"active_lanes":lanes,"buildings":buildings,"map":at,"links":links,"rewards":rewards,
		"enemy_lord_active":true,"enemy_camp":false,"opening":false,"dialogue":true,"capital":id in CAPITALS}

static var cache: Array = []
static func stages() -> Array:
	if not cache.is_empty(): return cache
	cache = [
		# The first lesson keeps its scripted farm raid: one lane, a bandit camp, no lords.
		{"id":"first_farm","chapter":0,"name":"第一塊農田","lord":"adventure","kind":"conquer","ai":0,"enemy_lord":"iron",
			"story":"史官記：邊境小領主只想種田。可惜強盜把他的田也算成了自己的領地。","goal":GOAL,
			"deck":["farmer","hunter","farmer","hunter","militia","farmer","hunter","militia"],
			"enemy_deck":["bandit","bandit","bandit","bandit","bandit","bandit","bandit","bandit"],
			"active_lanes":[2],"buildings":[],"allow_duplicates":true,"map":Vector2(150,480),"links":["crossroads"],
			"rewards":["mob","barricade","rain","scarecrow"],"enemy_lord_active":false,"enemy_camp":true,"opening":true,"dialogue":false,"capital":false},
		land("crossroads",0,"十字驛站","bandit_chief",0,Vector2(300,480),["first_farm","ox_hill","rune_fields","raven_roost","fishbeak_shore"],["spearbow","shieldguard"],"史官記：四條路在此交會，每一條的盡頭都有人想當王。驛站目前歸一個嗓門很大的強盜。",MIDDLE_LANES),
		land("ox_hill",1,"牧牛坡","ox_herder",1,Vector2(440,272),["crossroads","militia_pass"],["ox","harvest"],"史官記：此地的牛比人多，脾氣也比人大。"),
		land("militia_pass",1,"民兵關","militia_captain",1,Vector2(590,240),["ox_hill","lion_keep","golem_works"],["levy","tower"],"史官記：守關的隊長已經忘了替誰守關，但他守得很認真。",MIDDLE_LANES,[[7,2,"tower"]]),
		land("lion_keep",1,"紅獅堡","lion",2,Vector2(750,272),["militia_pass","royal_seat"],["knight","charge_horn","ram"],"史官記：紅獅領主自稱正統。他的理由是他的旗子最大。"),
		land("rune_fields",2,"法陣原","trap_weaver",1,Vector2(460,400),["crossroads","golem_works"],["rolling_boulder","watchtower"],"史官記：原野上畫滿法陣。畫的人自己也不記得哪些會爆炸。"),
		land("golem_works",2,"魔像工坊","golem_smith",1,Vector2(610,385),["rune_fields","clock_tower","militia_pass"],["manor_retainer"],"史官記：工坊日夜敲打，造出不吃不睡不領薪水的士兵。"),
		land("clock_tower",2,"時鐘塔","mage",2,Vector2(770,400),["golem_works","royal_seat"],["mill"],"史官記：法師領主算出自己會當王。他沒算到有人不按時間表來。"),
		land("raven_roost",3,"鴉巢","raven_mother",1,Vector2(460,560),["crossroads","bone_ford"],["bandit"],"史官記：鴉群專啄農田。牠們的巢裡有全國一半的湯匙。"),
		land("bone_ford",3,"骸骨渡口","skeleton_king",1,Vector2(610,575),["raven_roost","blood_chapel","imp_market"],["healer"],"史官記：骷髏王主張論資排輩。他確實比誰都資深。",MIDDLE_LANES),
		land("blood_chapel",3,"血契禮拜堂","vampire",2,Vector2(770,560),["bone_ford","royal_seat"],["drummer","guard"],"史官記：吸血領主的契約很公道：你出血，他出力。"),
		land("fishbeak_shore",4,"魚喙灘","fishbeak_boss",1,Vector2(440,690),["crossroads","imp_market"],["net_hunter"],"史官記：灘上的怪物說不清是魚是鳥，但牠們沒繳過稅。"),
		land("imp_market",4,"鬍子魔集市","imp_thief",1,Vector2(590,712),["fishbeak_shore","dragon_vale","bone_ford"],["axe_thrower"],"史官記：集市今日特價——你的錢袋。"),
		land("dragon_vale",4,"龍骨谷","dragon_lord",2,Vector2(750,690),["imp_market","royal_seat"],["catapult","fire"],"史官記：骨刺龍王不說話。牠背上的每一根刺都替牠說了。"),
		land("royal_seat",5,"王都","iron",2,Vector2(935,480),["lion_keep","clock_tower","blood_chapel","dragon_vale"],[],"史官記：鐵壁領主守著空王座。四座首府都換了顏色，城門才會為人打開。"),
	]
	cache[cache.size()-1].needs = CAPITALS
	return cache

static func index_of(id: String) -> int:
	var list := stages()
	for i: int in range(list.size()):
		if list[i].id == id: return i
	return -1

# Returns actionable authoring errors without instantiating a game or touching saves.
static func validate(list: Array = stages()) -> Array[String]:
	var errors: Array[String] = []
	var ids: Dictionary = {}
	for d: Dictionary in list:
		if d.get("id","").is_empty() or ids.has(d.id): errors.append("duplicate or empty stage id: "+str(d.get("id","")))
		ids[d.get("id","")] = true
	var pool: Array = DeckStore.pool("adventure")
	var story: Dictionary = preload("res://campaign_story_data.gd").SCENES
	for d: Dictionary in list:
		var id: String = d.get("id","")
		for key: String in ["name","story","goal"]:
			if not d.get(key) is String or d.get(key,"").is_empty(): errors.append(id+": missing text "+key)
		for key: String in ["opening","dialogue","enemy_camp","enemy_lord_active","capital"]:
			if not d.get(key) is bool: errors.append(id+": missing boolean "+key)
		if not d.get("chapter") is int or not d.get("chapter",-1) in range(CHAPTERS.size()): errors.append(id+": invalid region")
		if not d.get("ai") is int or not d.get("ai",-1) in range(3): errors.append(id+": invalid AI difficulty")
		if not d.get("map") is Vector2: errors.append(id+": missing map position")
		if not B.LORDS.has(d.get("lord","")): errors.append(id+": unknown lord")
		if not B.LORDS.has(d.get("enemy_lord","")) and not B.MINION_LORDS.has(d.get("enemy_lord","")): errors.append(id+": unknown ruler")
		var deck = d.get("deck")
		if not (deck is String and deck == "player") and not (deck is Array and DeckStore.valid(deck,d.lord,d.get("allow_duplicates",false))): errors.append(id+": invalid player deck")
		var foe = d.get("enemy_deck")
		if not foe is Array or foe.size() != 8 or foe.any(func(k) -> bool: return not B.CARDS.has(k)): errors.append(id+": invalid enemy deck")
		var lanes: Array = d.get("active_lanes",[])
		if lanes.is_empty() or lanes.any(func(lane) -> bool: return not lane in range(5)): errors.append(id+": invalid lanes")
		for card in d.get("rewards",[]):
			if not card in pool: errors.append(id+": reward %s is not a card the adventure lord can use" % str(card))
		for b in d.get("buildings",[]):
			if not b is Array or b.size() != 3 or not b[0] in range(9) or not b[1] in lanes or not B.CARDS.has(b[2]) or B.CARDS[b[2]].type != "building": errors.append(id+": invalid building")
		for other in d.get("links",[])+d.get("needs",[]):
			if not ids.has(other): errors.append(id+": road to unknown territory "+str(other))
			elif other in d.get("links",[]) and not id in list[index_of(other)].links: errors.append(id+": road to %s is one-way" % other)
		if d.get("dialogue",false) and (not story.has(id) or story[id].size() != 2): errors.append(id+": needs an opening and a closing scene")
	# Every territory can be reached from the first farm.
	var reached := {list[0].id:true}
	var grew := true
	while grew:
		grew = false
		for d: Dictionary in list:
			if reached.has(d.id): continue
			if d.get("links",[]).any(func(other) -> bool: return reached.has(other)):
				reached[d.id] = true
				grew = true
	for d: Dictionary in list:
		if not reached.has(d.id): errors.append(d.id+": cannot be reached")
	return errors
