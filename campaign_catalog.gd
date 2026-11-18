extends RefCounted
# 冒險模式：大地圖征服 (2026-11-15 meta remake). Authoring data only: no battle, UI, save files or
# resource loading. Fifteen territories rebuilt for gate heavy armor, enlarged frontline radii,
# lord-targeting sieges, unified status effects, and all 49 adventure-pool cards + 8 unlockable lords.
const B = preload("res://balance.gd")
const DeckStore = preload("res://deck_store.gd")
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
# Conquer regional strongholds and capitals to recruit all 8 other playable lords.
const UNLOCK_LORDS := {
	"granary_keep":"harvest",
	"lion_keep":"lion",
	"arcane_observatory":"rune",
	"clock_tower":"mage",
	"bone_crypt":"underworld",
	"blood_chapel":"vampire",
	"dragon_vale":"beast",
	"royal_seat":"iron",
}

static func land(id: String, chapter: int, name: String, ruler: String, ai: int, at: Vector2, links: Array, enemy_deck: Array, rewards: Array, story: String, lanes: Array = ALL_LANES, buildings: Array = []) -> Dictionary:
	return {"id":id,"chapter":chapter,"name":name,"lord":"adventure","kind":"conquer","ai":ai,"enemy_lord":ruler,"story":story,"goal":GOAL,
		"deck":"player","enemy_deck":enemy_deck,"active_lanes":lanes,"buildings":buildings,"map":at,"links":links,"rewards":rewards,
		"enemy_lord_active":true,"enemy_camp":false,"opening":false,"dialogue":true,"capital":id in CAPITALS}

static var cache: Array = []
static func stages() -> Array:
	if not cache.is_empty(): return cache
	cache = [
		# 0. Opening scripted raid: teaches farming, defending and breaking the gate; awards armor-piercing & control tools.
		{"id":"first_farm","chapter":0,"name":"第一塊農田","lord":"adventure","kind":"conquer","ai":0,"enemy_lord":"iron",
			"story":"史官記：邊境小領主只想種田。可惜強盜把他的田也算成了自己的領地。","goal":GOAL,
			"deck":["farmer","hunter","farmer","hunter","militia","farmer","hunter","militia"],
			"enemy_deck":["bandit","farmer","militia","farmer","farmer","bandit","farmer","militia"],
			"active_lanes":[2],"buildings":[],"allow_duplicates":true,"map":Vector2(150,480),"links":["crossroads"],
			"rewards":["mob","scarecrow","gatebreaker","rain"],"enemy_lord_active":false,"enemy_camp":true,"opening":true,"dialogue":false,"capital":false},
		# 1. Frontier hub: introduces 3-lane combat with pitchfork mob swarms and lane-switching threats (fishbeak & scarecrow).
		land("crossroads",0,"哨堡十字路","militia_captain",0,Vector2(300,480),
			["first_farm","smithy_ridge","beacon_ford","belfry_fen","nest_wastes"],
			["farmer","hunter","mob","fishbeak","scarecrow","drummer","watchtower","supply_depot"],
			["macebreaker","watchtower","shieldguard","barricade"],
			"史官記：哨堡前分出三路：乾草叉暴民三路齊衝，稻草人與魚喙怪逼人換路支援。守住三路才能出關。",
			MIDDLE_LANES),
		# Region 1: North Wheatlands (Armor, Firearms, Economy & Heavy Sieges)
		land("smithy_ridge",1,"鐵匠坡","card_enemy_field_smithy",1,Vector2(440,272),
			["crossroads","granary_keep"],
			["field_smithy","shieldguard","militia","arquebusier","hunter","farmer","healer","counter_charge"],
			["field_smithy","arquebusier","counter_charge","mule_cart"],
			"史官記：鐵匠鋪的爐火日夜不熄，敲出的鎧甲連弓箭都彈得開，只有重錘與破甲火器咬得動。"),
		land("granary_keep",1,"豐收莊園","harvest",1,Vector2(590,240),
			["smithy_ridge","lion_keep","arcane_observatory"],
			["farmer","granary","militia","manor_retainer","hunter","watchtower","harvest","rain"],
			["granary","harvest","manor_retainer","ox"],
			"史官記：豐收領主坐擁滿倉麥糧與守備高塔，最擅長拖成一場比誰口袋更深的消耗戰。",
			MIDDLE_LANES,[[7,2,"granary"]]),
		land("lion_keep",1,"紅獅堡","lion",2,Vector2(750,272),
			["granary_keep","royal_seat"],
			["knight","disgraced_lancer","charge_horn","militia","arquebusier","ram","supply_depot","spearbow"],
			["knight","disgraced_lancer","charge_horn"],
			"史官記：紅獅領主統率重裝騎士與攻城槌。破門之後，連領主本人都是攻城槌的目標。",
			ALL_LANES,[[6,2,"supply_depot"]]),
		# Region 2: Magic Spire (Displacement, Traps, Anti-Magic & Time Freeze)
		land("beacon_ford",2,"折躍哨所","card_enemy_warp_beacon",1,Vector2(460,400),
			["crossroads","arcane_observatory"],
			["warp_beacon","rune_sentinel","prism_mage","teleport_trap","summon_trap","blink_blade","mana_drain","arcane_shield"],
			["spellbreaker","flaming_pitch","drummer","spearbow"],
			"史官記：折躍信標每隔片刻便把前排震退，地上還畫滿傳送與召獸法陣，專治衝得太急的部隊。",
			ALL_LANES,[[7,1,"teleport_trap"],[7,3,"summon_trap"]]),
		land("arcane_observatory",2,"符文觀測台","rune",1,Vector2(610,385),
			["beacon_ford","clock_tower","granary_keep"],
			["artificer","arcane_golem","orrery_walker","arcane_archer","spell_mirror","observatory","rune_workshop","chain_lightning"],
			["rolling_boulder","tower","supply_depot","twin_gambler"],
			"史官記：符文領主在每一路前緣布滿法陣，星儀光束與貫星箭矢能一路穿死整排後排。",
			ALL_LANES,[[7,2,"observatory"]]),
		land("clock_tower",2,"時鐘塔","mage",2,Vector2(770,400),
			["arcane_observatory","royal_seat"],
			["arcane_golem","blink_blade","arcane_archer","gravity_well","chain_lightning","time_field","mirror_clone","aether_hound"],
			["mill","levy","assassin","ballista_tower"],
			"史官記：法師領主用重力井聚敵、鏡像複製重裝魔像，並在鐘響時凝滯全場時間。",
			ALL_LANES),
		# Region 3: Dark Marsh (Poison/Cleanse, Giant Bonewall, Ravens & Blood Pacts)
		land("belfry_fen",3,"疫沼鐘樓","card_enemy_sleepless_belfry",1,Vector2(460,560),
			["crossroads","bone_crypt"],
			["skeleton","pallbearer","mourning_maid","funeral_grenadier","ossuary","sleepless_belfry","sealed_coffin","raven"],
			["healer","old_witch","vampire_hunter","net_hunter"],
			"史官記：沼澤裡鐘聲不斷，不眠鐘樓替亡者淨化毒霧，喪鐘侍女則讓來犯者舉步維艱。"),
		land("bone_crypt",3,"白骨冥府","underworld",1,Vector2(610,575),
			["belfry_fen","blood_chapel","nest_market"],
			["skeleton","corpse_giant","pallbearer","mourning_maid","bandit","farmer","barricade","rain"],
			["bandit","hook_collector","ram"],
			"史官記：三千血的巨型骨牆擋在渡口，身後是腐屍巨人與源源不絕的骷髏亡者。",
			ALL_LANES,[[7,2,"bonewall"]]),
		land("blood_chapel",3,"血契禮拜堂","vampire",2,Vector2(770,560),
			["bone_crypt","royal_seat"],
			["blood_attendant","ghoul","reaper","shroud_arbalist","raven","blood_tower","mourning_shroud","sacrifice"],
			["guard","axe_thrower"],
			"史官記：吸血領主簽下鮮血盟約後愈戰愈厚，烏鴉群還會繞過防線直撲我方領主。",
			ALL_LANES,[[7,1,"blood_altar"],[7,3,"blood_tower"]]),
		# Region 4: Beast Wastes (Glutton Nests, Giant Bodies, Thorns & Anti-Beast)
		land("nest_wastes",4,"貪食荒灘","card_enemy_glutton_nest",1,Vector2(440,690),
			["crossroads","nest_market"],
			["pouch_beast","parasite_mite","web_spinner","fishbeak","hooknose_flyer","imp_bomb_runner","monster_hatchery","wing_gust"],
			["halberdier","monster_hunter"],
			"史官記：荒灘上的巢穴會忍住貪慾，等孤軍自己走進嘴裡才張口；只有足夠火力能趁張嘴時劈碎它。"),
		land("nest_market",4,"野豬戰寨","card_enemy_tusk_boar",0,Vector2(590,712),
			["nest_wastes","dragon_vale","bone_crypt"],
			["tusk_boar","bramble_wall","corrosive_bile","farmer","hunter","militia","scarecrow","barricade"],
			["powder_barrel","beekeeper","gold_monster"],
			"史官記：野豬人撞暈前排、地刺高牆帶反傷，酸雨還會腐蝕護盾與護甲。",
			ALL_LANES),
		land("dragon_vale",4,"龍骨谷","beast",2,Vector2(750,690),
			["nest_market","royal_seat"],
			["thorn_dragon","bog_troll","dire_hydra","eyewing_dragon","long_dragon","belly_eye","devouring_maw","feral_mutation"],
			["catapult","fire"],
			"史官記：巨大化的魔物佔滿視線：骨刺龍鎮守前排、眼翼龍吼退兵線再疾馳追殺。",
			ALL_LANES),
		# 5. Finale: Iron Fortress
		land("royal_seat",5,"王都","iron",2,Vector2(935,480),
			["lion_keep","clock_tower","blood_chapel","dragon_vale"],
			["knight","macebreaker","manor_retainer","arquebusier","healer","ram","barricade","counter_charge"],
			[],
			"史官記：重甲城牆、鐵匠鋪與雙座重弩塔守護著空王座。四座首府換上紅旗，最後的決戰才算開始。",
			ALL_LANES,[[7,1,"ballista_tower"],[7,2,"field_smithy"],[7,3,"ballista_tower"]]),
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
