extends RefCounted
# 肉鴿模式 content (2026-11-06). Authoring data only: no battle, UI or save files.
# A run is 8 battles: floors 1-7 against 小怪領主 (B.MINION_LORDS) of rising tier, floor 8 against a
# normal lord as the boss. One loss ends the run. Each win offers 3 cards; the player swaps one in.
const B = preload("res://balance.gd")
const DeckStore = preload("res://deck_store.gd")

const FLOORS := 8
const FLOOR_TIER := [1,1,2,2,2,3,3] # floors 1-7; floor 8 is the boss
const AI_LEVEL := [0,0,1,1,1,2,2,2] # 簡單／普通／困難 per floor; the final boss plays 困難 with upgraded cards & boss passives
const OFFER_SIZE := 3
# A roguelike battle still undecided after this many seconds goes to the side whose gates have more
# health left; a tie counts as a loss (producer 2026-11-07: stalemates must end).
const TIME_LIMIT := 480.0
# Shop (producer 2026-11-07): gold for each win by the floor's tier; card upgrades (card_upgrades.gd)
# and relics are bought with it and last for the run.
const GOLD_BY_TIER := {1:100,2:200,3:300}
const RELIC_PRICES := [200,400,600]
# Relics use the same passive keys as the 內政 lords (B.MINION_LORDS) and stack with them.
const RELICS := {
	"coin_purse":{"name":"錢袋","price":200,"mods":{"start_ink":10.0}},
	"hourglass":{"name":"沙漏","price":200,"mods":{"cycle_speed":{"*":1.15}}},
	"mid_stakes":{"name":"中路拒馬","price":200,"mods":{"start_buildings":[[2,2,"barricade"]]}},
	"mason_trowel":{"name":"工匠泥刀","price":200,"mods":{"post_heal":{"gate":250.0,"lord":80.0}}},
	"signet_ring":{"name":"紋章戒","price":200,"mods":{"skill_discount":15.0}},
	"mercenary_ledger":{"name":"傭兵帳冊","price":200,"mods":{"gold_bonus":0.3}},
	"border_horn":{"name":"邊境號角","price":200,"mods":{"start_buildings":[[0,2,"farm"]],"start_ink":5.0}},
	"iron_rivets":{"name":"鐵鉚釘","price":200,"mods":{"gate_armor":0.2}},
	"artisan_blueprint":{"name":"名匠鍛圖","price":200,"mods":{"targeted_upgrade":true}},
	"river_sluice":{"name":"護城鑿渠令","price":200,"mods":{"field_mutators":[{"water_cols":[4]}],"start_ink":4.0}},
	"gold_chest":{"name":"藏金箱","price":400,"mods":{"income_mult":1.25}},
	"deft_gloves":{"name":"巧手手套","price":400,"mods":{"cycle_speed":{"*":1.3}}},
	"twin_towers":{"name":"雙哨塔","price":400,"mods":{"start_buildings":[[0,0,"watchtower"],[0,4,"watchtower"]]}},
	"bounty_pouch":{"name":"獵頭賞袋","price":400,"mods":{"kill_bounty":1.0}},
	"royal_medallion":{"name":"王室勳章","price":400,"mods":{"lord_boost":1}},
	"chrono_pendulum":{"name":"時光鐘擺","price":400,"mods":{"skill_haste":1.4,"start_ink":5.0}},
	"spiked_battlement":{"name":"荊棘雉堞","price":400,"mods":{"gate_armor":0.25,"thorns_gate":35.0}},
	"harvest_sickle":{"name":"豐饒金鐮","price":400,"mods":{"farm_mult":1.35,"start_ink":8.0}},
	"trench_engineer":{"name":"前線工兵營","price":400,"mods":{"field_mutators":[{"periodic":{"interval":24.0,"kind":"blast_trap","min_col":2,"max_col":6}}]}},
	"spirit_graveyard":{"name":"英靈喚魂碑","price":400,"mods":{"field_mutators":[{"periodic":{"interval":26.0,"kind":"grave","min_col":1,"max_col":5,"fallback_unit":"skeleton","fallback_count":3}}]}},
	"sky_volley_seal":{"name":"蒼穹箭雨印","price":400,"mods":{"field_mutators":[{"periodic_spell":{"interval":20.0,"kind":"rain"}}]}},
	"war_banner":{"name":"戰旗","price":600,"mods":{"haste":["*"]}},
	"muster_horn":{"name":"集結號","price":600,"mods":{"swarm":{"*":1}}},
	"holy_grail":{"name":"聖杯","price":600,"mods":{"toughen":["*"]}},
	"crown_of_valor":{"name":"英靈王冠","price":600,"mods":{"lord_boost":2,"skill_discount":20.0}},
	"philosopher_stone":{"name":"賢者之石","price":600,"mods":{"income_mult":1.35,"start_ink":15.0}},
	"imperial_bastion":{"name":"帝國稜堡","price":600,"mods":{"start_buildings":[[0,1,"tower"],[0,3,"tower"],[1,2,"barricade"]]}},
	"blood_chalice":{"name":"血誓聖爵","price":600,"mods":{"kill_bounty":1.5,"post_heal":{"gate":350.0,"lord":150.0}}},
	"astral_compass":{"name":"星象羅盤","price":600,"mods":{"cycle_speed":{"*":1.25},"skill_haste":1.5}},
	"aegis_obelisk":{"name":"聖盾方尖碑","price":600,"mods":{"field_mutators":[{"periodic_spell":{"interval":22.0,"kind":"arcane_shield"}}]}},
	"fertile_floodplain":{"name":"沃野墾殖詔","price":600,"mods":{"field_mutators":[{"double_home_rows":true}],"farm_mult":1.2}},
}
const BOARD_REROLL_PRICE := 40
const SKIP_REWARD_GOLD := 35
const OFFER_REROLL_PRICE := 25
const CONTRACTS := [
	{"name":"標準征途","desc":"標準肉鴿規則：敵方開局 10 金（精英 20 金）。","enemy_ink":0.0,"ai_boost":0,"enemy_toughen":false,"gold_mult":1.0},
	{"name":"強敵壓境","desc":"敵方開局金幣 +8；每戰勝利金幣獎勵 +20%。","enemy_ink":8.0,"ai_boost":0,"enemy_toughen":false,"gold_mult":1.2},
	{"name":"鐵血遠征","desc":"敵方開局金幣 +14、AI 提升一階；戰勝金幣獎勵 +40%。","enemy_ink":14.0,"ai_boost":1,"enemy_toughen":false,"gold_mult":1.4},
	{"name":"絕境王權","desc":"敵方開局金幣 +20、AI 提升一階、敵軍全體生命升一檔；戰勝金幣 +60%。","enemy_ink":20.0,"ai_boost":1,"enemy_toughen":true,"gold_mult":1.6},
]
const EVENTS := {
	"wandering_smith":{
		"name":"流亡宮廷鐵匠","art":"field_smithy",
		"story":"一名帶著皇家烙鐵的流亡鐵匠在路旁架起風箱，聲稱只要給足酒錢或廢鐵，就能把你的兵刃鍛上王城規格。",
		"choices":[
			{"label":"重金精鍛（60 金）","desc":"花費 60 金幣：將牌組中 2 張不同卡牌各升一階（+1）","cost":60,"effect":"upgrade_2"},
			{"label":"拆解舊甲","desc":"獲得 110 金幣，並將牌組隨機 1 張卡牌升一階（+1）","cost":0,"effect":"gold_and_up"},
			{"label":"修補城防","desc":"免費修復所有城牆 35% 缺失血量，領主回復 30% 生命","cost":0,"effect":"mend_both"},
		]
	},
	"mercenary_tavern":{
		"name":"十字路傭兵酒館","art":"twin_gambler",
		"story":"喧鬧的驛站酒館裡坐滿了各國潰兵與賞金獵人。桌上的羊皮懸賞令寫著周遭敵將的人頭價碼。",
		"choices":[
			{"label":"張貼重賞（全盤加賞）","desc":"獲得 70 金幣；場上其餘戰鬥選項全部附加「懸賞 +60 金」","cost":0,"effect":"board_bounty"},
			{"label":"招募精銳（50 金）","desc":"花費 50 金幣：立即進入選卡獎勵換入 1 張新卡，且隨機 1 張卡 +1 強化","cost":50,"effect":"draft_plus"},
			{"label":"擲骰豪賭","desc":"免費獲得 1 件未持有的 200 金遺物（若已集滿則改得 160 金幣）","cost":0,"effect":"free_relic_low"},
		]
	},
	"ancient_altar":{
		"name":"荒原血誓古壇","art":"blood_altar",
		"story":"刻滿古老符文的石壇仍在滲出微光。石碑記載：凡獻上鮮血或城石者，皆可換取古代王權的遺物。",
		"choices":[
			{"label":"領主血誓","desc":"領主損耗 30% 當前生命：免費獲得 1 件未持有的遺物","cost":0,"effect":"blood_relic"},
			{"label":"拆牆獻石","desc":"每座城牆損耗 15% 當前血量：獲得 200 金幣與隨機 1 張卡 +1 強化","cost":0,"effect":"wall_gold"},
			{"label":"淨化邪壇","desc":"恢復領主 45% 最大生命，並獲得 90 金幣","cost":0,"effect":"cleanse_altar"},
		]
	},
	"scout_watchtower":{
		"name":"前線斥候烽火台","art":"observatory",
		"story":"登上高聳的觀測塔，四周敵軍的動向一覽無遺。你可以點燃烽火改變行軍路線，或引誘強敵出擊。",
		"choices":[
			{"label":"吹響強襲號（全盤升階）","desc":"將場上所有「一般戰鬥」升階為「精英討伐（附 +50 懸賞金）」，並得 80 金","cost":0,"effect":"board_all_elite"},
			{"label":"改道奇襲（全盤重洗）","desc":"刷新全部 4 個遭遇選項，並為所有新戰鬥附加 +45 懸賞金","cost":0,"effect":"board_reroll_plus"},
			{"label":"據塔休整","desc":"修復所有城牆 30% 缺失血量、領主回復 40% 生命，並獲得 70 金幣","cost":0,"effect":"tower_rest"},
		]
	},
	"royal_caravan":{
		"name":"受困的王室商隊","art":"mule_cart",
		"story":"一隊滿載金條與軍火的王室騾車陷在泥沼中。押運官承諾只要幫他們脫困，車上的軍需任你挑選。",
		"choices":[
			{"label":"收下軍餉","desc":"獲得 160 金幣，並修復城牆 20% 缺失血量","cost":0,"effect":"caravan_gold"},
			{"label":"開啟遺物匣","desc":"免費獲得 1 件未持有的 200～400 金階級遺物","cost":0,"effect":"caravan_relic"},
			{"label":"全軍換裝","desc":"牌組中隨機 2 張卡牌各升一階（+1）","cost":0,"effect":"upgrade_2_free"},
		]
	},
	"cursed_grimoire":{
		"name":"泥金禁書殘卷","art":"rune_workshop",
		"story":"廢棄修道院的書架上留著一冊尚未乾涸的泥金手抄本，書頁上的墨水似乎能直接改寫軍隊的編制。",
		"choices":[
			{"label":"臨摹主力（40 金）","desc":"花費 40 金幣：將牌組第 1 張可強化卡牌連升兩階（+2）","cost":40,"effect":"focus_up_2"},
			{"label":"改寫命途（全盤支援）","desc":"將場上其它非戰鬥或一般戰轉為高價值營火／古祠／懸賞，並得 80 金","cost":0,"effect":"board_blessing"},
			{"label":"變賣手稿","desc":"獲得 135 金幣","cost":0,"effect":"sell_book"},
		]
	},
	"stonemason_guild":{
		"name":"皇家石匠行會","art":"granary",
		"story":"留守邊境的老石匠們還保有一批上等砂岩與軍糧。他們願意為討伐叛軍的領主加固要塞。",
		"choices":[
			{"label":"全面築城（50 金）","desc":"花費 50 金幣：所有城牆回滿血量，且隨機 1 張卡 +1 強化","cost":50,"effect":"full_walls"},
			{"label":"御醫隨行","desc":"領主回滿生命，修復城牆 25% 缺失血量，並獲得 60 金幣","cost":0,"effect":"full_lord"},
			{"label":"徵收工程款","desc":"獲得 140 金幣","cost":0,"effect":"guild_gold"},
		]
	},
	"deserter_camp":{
		"name":"投誠的邊防軍營","art":"supply_depot",
		"story":"一整隊邊防士兵厭倦了各地領主的混戰，帶著軍械庫鑰匙前來投奔你的麾下。",
		"choices":[
			{"label":"整編入伍","desc":"免費進入選卡獎勵挑選 1 張新卡替換入牌組，並獲得 80 金幣","cost":0,"effect":"free_draft"},
			{"label":"接收軍械庫","desc":"隨機 2 張卡牌各升一階（+1），並獲得 60 金幣","cost":0,"effect":"armory_up"},
			{"label":"遣散領賞","desc":"獲得 150 金幣，並重置本層支援行動次數","cost":0,"effect":"reset_march"},
		]
	},
	"alchemist_wagon":{
		"name":"鍊金術士的坩堝車","art":"corrosive_bile",
		"story":"冒著翠綠煙霧的馬車停在溪畔，古怪的鍊金術士正把戰場拾來的鐵器煉成純金與秘藥。",
		"choices":[
			{"label":"點石成金（全盤化戰）","desc":"獲得 90 金幣；場上其餘非戰鬥格全部轉為附 +75 懸賞金的遭遇戰","cost":0,"effect":"transmute_bounty"},
			{"label":"飲下秘藥","desc":"領主回滿生命，且隨機 2 張卡牌各升一階（+1）","cost":0,"effect":"elixir_up"},
			{"label":"兜售空瓶","desc":"獲得 130 金幣","cost":0,"effect":"sell_vials"},
		]
	},
	"mirror_sanctum":{
		"name":"鏡像奧術迴廊","art":"mirror_clone",
		"story":"步入荒廢的法師迴廊，巨大的水銀鏡面映照出你麾下軍團的倒影，鏡中魔力可折射武器上的強化銘文。",
		"choices":[
			{"label":"折射強化（45 金）","desc":"花費 45 金幣：強化等級最高的卡牌再升一階，並令另 1 張卡 +1 強化","cost":45,"effect":"mirror_upgrade"},
			{"label":"鏡像聖域（全盤賜福）","desc":"刷新全場 4 格，保底出現 1 座戰地營火與 1 座秘寶古祠，並得 65 金","cost":0,"effect":"sanctuary_board"},
			{"label":"汲取奧術","desc":"獲得 125 金幣，並修復所有城牆 25% 缺失血量","cost":0,"effect":"arcane_mend"},
		]
	},
	"vanguard_outpost":{
		"name":"先鋒斷後哨站","art":"ballista_tower",
		"story":"前線哨站的弩砲手正準備撤離，哨長詢問你是否願意接手防務，或是立下重賞軍令迎擊追兵。",
		"choices":[
			{"label":"立下軍令狀（懸賞翻倍）","desc":"獲得 80 金幣；場上所有戰鬥格懸賞金翻倍（最低 +60 金）","cost":0,"effect":"double_bounty"},
			{"label":"加固鹿砦","desc":"修復所有城牆 50% 缺失血量，並隨機強化 1 張卡牌 +1","cost":0,"effect":"fortify_up"},
			{"label":"徵用箭匣","desc":"免費獲得 1 件未持有的 200～400 金階級遺物","cost":0,"effect":"caravan_relic"},
		]
	},
	"phantom_bazaar":{
		"name":"迷霧黑市","art":"twin_gambler",
		"story":"濃霧籠罩的古道旁亮起一排油燈，蒙面商販正低聲叫賣從王城寶庫流出的高階聖物與走私軍火。",
		"choices":[
			{"label":"黑市聖物（90 金）","desc":"花費 90 金幣：直接獲得 1 件未持有的 600 金最高階遺物","cost":90,"effect":"buy_high_relic"},
			{"label":"走私軍火","desc":"免費進入選卡獎勵換入 1 張新卡，且隨機 1 張卡 +1 強化","cost":0,"effect":"draft_plus"},
			{"label":"勒索保護費","desc":"獲得 155 金幣","cost":0,"effect":"bazaar_gold"},
		]
	},
}
# Path choice (2026-11-09): before each of floors 1-7 the player may pick an elite instead, a 小怪
# from the next tier up (tier 3 stays tier 3) opening with more gold, for 1.5x the gold reward.
const ELITE_START_INK := 20.0
const BOSS_START_INK := 25.0
const BOSS_CARD_UPGRADES := 4
const BOSS_LORD_BOOST := 2
const ELITE_GOLD_MULT := 1.5
const REROLL_PRICE := 50 # shop: draw a fresh set of relics
# Our gates and lord keep their wounds from battle to battle (2026-11-09); the shop mends them.
const GATE_HP_PER_GOLD := 50.0
const LORD_HP_PER_GOLD := 10.0
const FALLEN_LORD_SHARE := 0.25 # a lord who is down when the battle is won starts the next at 25%
const ENEMY_START_INK := 10.0 # floors 1-7 standard foe opening gold

# Single lord leads a roguelike run: its fighting stats, skill, home card, and faction passive
# (from LORD_ROLES[lord].passive). Starting deck is 8 unique random cards of the lord's own faction.
const STARTER_CORE := {
	"normal":["ox","net_hunter"],
	"magic":["arcane_golem","arcane_archer"],
	"dark":["skeleton","dark_wizard"],
	"beast":["fishbeak","long_dragon"],
}
const LORD_ROLES := {
	"adventure":{"domestic":{"card":"farmer","passive":{"lord_boost":1,"skill_haste":1.35,"kill_bounty":0.5,"gold_bonus":0.20,"post_heal":{"gate":150.0,"lord":80.0}}},"combat":{"card":"knight"}},
	"lion":{"domestic":{"card":"charge_horn","passive":{"haste":["*"],"start_ink":6.0}},"combat":{"card":"mob"}},
	"iron":{"domestic":{"card":"watchtower","passive":{"gate_armor":0.2,"thorns_gate":20.0,"start_buildings":[[1,1,"barricade"],[1,3,"barricade"]]}},"combat":{"card":"manor_retainer"}},
	"harvest":{"domestic":{"card":"harvest","passive":{"income_mult":1.25,"farm_mult":1.3}},"combat":{"card":"levy"}},
	"mage":{"domestic":{"card":"teleport_trap","passive":{"cycle_speed":{"*":1.25},"skill_haste":1.2}},"combat":{"card":"blink_blade"}},
	"rune":{"domestic":{"card":"artificer","passive":{"start_buildings":[[2,1,"teleport_trap"],[2,3,"blast_trap"]],"start_ink":10.0,"cycle_speed":{"*":1.15}}},"combat":{"card":"summon_trap"}},
	"underworld":{"domestic":{"card":"bonewall","passive":{"start_buildings":[[0,2,"grave"]],"skill_haste":1.25,"skill_discount":10.0}},"combat":{"card":"ghoul"}},
	"beast":{"domestic":{"card":"bearded_imp","passive":{"toughen":["*"],"start_buildings":[[0,2,"glutton_nest"]]}},"combat":{"card":"thorn_dragon"}},
	"vampire":{"domestic":{"card":"blood_tower","passive":{"lord_boost":1,"kill_bounty":0.6,"skill_haste":1.25,"post_heal":{"lord":100.0}}},"combat":{"card":"reaper"}},
}

# Pure same-faction draftable pool (excluding home cards, summon_only and unreleased).
static func faction_pool(lord: String) -> Array:
	var fac: String = B.lord_faction(lord)
	return DeckStore.pool(lord).filter(func(k: String) -> bool: return B.card_faction(k) == fac)

# Deterministic 8-card random same-faction starter deck with balanced troop/spell/building shape
# and guaranteed early-game playability (at least 4 units and at least 2 low-cost cards).
static func starter_deck(lord: String, seed_value: int = 0) -> Array:
	var pool: Array = faction_pool(lord)
	var buckets := {0: [], 1: [], 2: [], 3: []}
	for k: String in pool:
		buckets[B.card_group(k)].append(k)
	var rng := RandomNumberGenerator.new()
	var lord_idx: int = maxi(0, B.LORDS.keys().find(lord))
	rng.seed = abs(seed_value) * 131 + lord_idx * 977 + 17
	var ratio := {0: 3, 1: 1, 2: 2, 3: 2}
	var deck: Array = []
	for group_id: int in [0, 1, 2, 3]:
		var bucket: Array = buckets[group_id]
		var need := mini(int(ratio.get(group_id, 0)), bucket.size())
		for _i: int in range(need):
			deck.append(bucket.pop_at(rng.randi_range(0, bucket.size() - 1)))
	var spare: Array = pool.filter(func(k: String) -> bool: return not k in deck)
	while deck.size() < 8 and not spare.is_empty():
		deck.append(spare.pop_at(rng.randi_range(0, spare.size() - 1)))
	# Ensure at least 4 units and 2 low-cost (<= 7) cards by swapping excess high-cost non-units.
	var cheap_count: int = deck.filter(func(k: String) -> bool: return int(B.CARDS[k].cost) <= 7).size()
	var cheap_spare: Array = pool.filter(func(k: String) -> bool: return not k in deck and int(B.CARDS[k].cost) <= 7)
	while cheap_count < 2 and not cheap_spare.is_empty():
		var rep_idx := -1
		for i: int in range(deck.size() - 1, -1, -1):
			if int(B.CARDS[deck[i]].cost) > 7:
				rep_idx = i
				break
		if rep_idx < 0: break
		deck[rep_idx] = cheap_spare.pop_at(rng.randi_range(0, cheap_spare.size() - 1))
		cheap_count += 1
	return B.menu_sorted(deck)

static func passive(lord: String) -> Dictionary:
	return LORD_ROLES[lord].domestic.passive

# Cards the lord's deck may draft after battle (faction + neutral); home card stays in its own slot.
static func card_pool(lord: String) -> Array:
	return DeckStore.pool(lord).filter(func(k: String) -> bool: return k != B.home_card(lord))

static func deck_allowed(deck: Array, lord: String) -> bool:
	return DeckStore.valid(deck, lord)

# Each 小怪領主's tier (which floors it may appear on) and its deck. Repeats are the point: the
# deck leans on the card the lord is named after.
const MINIONS := {
	"card_enemy_glutton_nest":{"tier":3,"deck":["fishbeak","fishbeak","bearded_imp","bearded_imp","belly_eye","hooknose_flyer","long_dragon","thorn_dragon"]},
	"card_enemy_mana_spring":{"tier":1,"deck":["mana_spring","mana_spring","arcane_golem","artificer","arcane_archer","militia","militia","arcane_shield"]},
	"card_enemy_chain_lightning":{"tier":2,"deck":["chain_lightning","chain_lightning","chronomancer","arcane_archer","arcane_archer","arcane_golem","shieldguard","artificer"]},
	"card_enemy_arcane_shield":{"tier":2,"deck":["arcane_shield","arcane_shield","arcane_golem","blink_blade","militia","militia","artificer","hunter"]},
	"card_enemy_time_field":{"tier":2,"deck":["time_field","time_field","arcane_archer","arcane_archer","chronomancer","shieldguard","shieldguard","hunter"]},
	"card_enemy_charge_horn":{"tier":1,"deck":["charge_horn","charge_horn","ox","ox","mob","mob","knight","drummer"]},
	"card_enemy_levy":{"tier":1,"deck":["levy","levy","militia","militia","hunter","hunter","manor_retainer","watchtower"]},
	"card_enemy_watchtower":{"tier":1,"deck":["watchtower","watchtower","hunter","hunter","net_hunter","net_hunter","militia","militia"]},
	"card_enemy_sacrifice":{"tier":1,"deck":["sacrifice","sacrifice","skeleton","skeleton","skeleton","ghoul","mass_grave","dark_wizard"]},
	"card_enemy_dread_howl":{"tier":1,"deck":["dread_howl","dread_howl","reaper","ghoul","ghoul","skeleton","raven","hunter"]},
	"card_enemy_mass_grave":{"tier":3,"deck":["mass_grave","mass_grave","skeleton","skeleton","necromancer","ghoul","dark_wizard","curse"]},
	"card_enemy_manor_retainer":{"tier":1,"deck":["manor_retainer","manor_retainer","manor_retainer","hunter","hunter","watchtower","farmer","levy"]},
	"card_enemy_rolling_boulder":{"tier":3,"deck":["rolling_boulder","rolling_boulder","catapult","catapult","hunter","hunter","barricade","shieldguard"]},
	"card_enemy_dark_wizard":{"tier":3,"deck":["dark_wizard","dark_wizard","skeleton","skeleton","skeleton","mass_grave","ghoul","curse"]},
	"card_enemy_summon_trap":{"tier":2,"deck":["summon_trap","summon_trap","arcane_golem","artificer","hunter","hunter","militia","arcane_shield"]},
	"card_enemy_chimera":{"tier":2,"deck":["summon_trap","summon_trap","arcane_golem","artificer","arcane_shield","hunter","hunter","militia"]},
	"card_enemy_blink_blade":{"tier":3,"deck":["blink_blade","blink_blade","blink_blade","phase_rider","arcane_shield","hunter","hunter","time_field"]},
	"card_enemy_arcane_archer":{"tier":2,"deck":["arcane_archer","arcane_archer","arcane_archer","shieldguard","shieldguard","time_field","artificer","arcane_golem"]},
	"card_enemy_artificer":{"tier":2,"deck":["artificer","artificer","arcane_golem","arcane_golem","arcane_tower","arcane_shield","militia","hunter"]},
	"card_enemy_crystal":{"tier":1,"deck":["artificer","artificer","arcane_golem","mana_spring","mana_spring","arcane_archer","militia","militia"]},
	"card_enemy_teleport_trap":{"tier":3,"deck":["teleport_trap","teleport_trap","teleport_trap","arcane_archer","hunter","hunter","militia","time_field"]},
	"card_enemy_arcane_tower":{"tier":3,"deck":["arcane_tower","arcane_tower","artificer","artificer","arcane_golem","shieldguard","hunter","chain_lightning"]},
	"card_enemy_eyewing_dragon":{"tier":2,"deck":["eyewing_dragon","eyewing_dragon","eyewing_dragon","fishbeak","fishbeak","hooknose_flyer","dread_howl","belly_eye"]},
	"card_enemy_belly_eye":{"tier":2,"deck":["belly_eye","belly_eye","belly_eye","net_hunter","net_hunter","hunter","hunter","fishbeak"]},
	"card_enemy_hooknose_flyer":{"tier":3,"deck":["hooknose_flyer","hooknose_flyer","hooknose_flyer","raven","raven","fishbeak","militia","rain"]},
	"card_enemy_long_dragon":{"tier":3,"deck":["long_dragon","long_dragon","long_dragon","belly_eye","belly_eye","fishbeak","chronomancer","time_field"]},
	"card_enemy_barricade":{"tier":1,"deck":["barricade","barricade","hunter","hunter","hunter","militia","militia","net_hunter"]},
	"card_enemy_corpse_giant":{"tier":2,"deck":["corpse_giant","corpse_giant","necromancer","skeleton","skeleton","ghoul","blood_tower","plague"]},
	"card_enemy_curse":{"tier":2,"deck":["curse","ghoul","dark_wizard","dark_wizard","skeleton","skeleton","reaper","plague"]},
	"card_enemy_grave":{"tier":3,"deck":["skeleton","skeleton","skeleton","necromancer","ghoul","ghoul","mass_grave","curse"]},
	"card_enemy_reaper":{"tier":2,"deck":["reaper","reaper","reaper","skeleton","skeleton","ghoul","dread_howl","plague"]},
	"card_enemy_plague":{"tier":2,"deck":["plague","plague","corpse_giant","skeleton","skeleton","ghoul","ghoul","bonewall"]},
	"card_enemy_bonewall":{"tier":2,"deck":["bonewall","bonewall","necromancer","necromancer","skeleton","skeleton","hunter","curse"]},
	"card_enemy_farmer":{"tier":1,"deck":["farmer","farmer","militia","militia","militia","hunter","hunter","ox"]},
	"card_enemy_harvest":{"tier":1,"deck":["harvest","farmer","farmer","militia","militia","hunter","ox","knight"]},
	"card_enemy_scarecrow":{"tier":1,"deck":["scarecrow","scarecrow","farmer","farmer","hunter","hunter","militia","militia"]},
	"card_enemy_spearbow":{"tier":3,"deck":["spearbow","spearbow","spearbow","drummer","healer","hunter","militia","levy"]},
	"card_enemy_farm":{"tier":1,"deck":["farmer","militia","militia","militia","hunter","hunter","spearbow","scarecrow"]},
	"card_enemy_rain":{"tier":2,"deck":["rain","rain","hunter","hunter","spearbow","shieldguard","militia","watchtower"]},
	"card_enemy_fire":{"tier":2,"deck":["fire","fire","bandit","bandit","raven","raven","shieldguard","hunter"]},
	"card_enemy_guard":{"tier":2,"deck":["guard","guard","guard","knight","healer","shieldguard","hunter","charge_horn"]},
	"card_enemy_mill":{"tier":1,"deck":["mill","mill","farmer","farmer","ox","militia","hunter","spearbow"]},
	"mob_foreman":{"tier":1,"deck":["mob","mob","mob","militia","militia","hunter","hunter","drummer"]},
	"net_poacher":{"tier":1,"deck":["net_hunter","net_hunter","net_hunter","hunter","bandit","bandit","militia","barricade"]},
	"field_prior":{"tier":1,"deck":["healer","healer","militia","militia","militia","shieldguard","shieldguard","hunter"]},
	"axe_raider":{"tier":3,"deck":["axe_thrower","axe_thrower","axe_thrower","shieldguard","shieldguard","bandit","drummer","rain"]},
	"phase_stalker":{"tier":3,"deck":["phase_rider","phase_rider","phase_rider","blink_blade","bandit","bandit","arcane_shield","time_field"]},
	"ghoul_feaster":{"tier":2,"deck":["ghoul","ghoul","ghoul","skeleton","skeleton","skeleton","mass_grave","plague"]},
	"blood_prior":{"tier":3,"deck":["blood_tower","ghoul","ghoul","dark_wizard","skeleton","skeleton","reaper","corpse_giant"]},
	"clock_warden":{"tier":2,"deck":["chronomancer","chronomancer","chronomancer","arcane_archer","arcane_golem","time_field","teleport_trap","arcane_shield"]},
	"ram_marshal":{"tier":2,"deck":["ram","ram","ram","shieldguard","shieldguard","healer","net_hunter","charge_horn"]},
	"bandit_chief":{"tier":1,"deck":["bandit","bandit","bandit","bandit","militia","militia","hunter","hunter"]},
	"militia_captain":{"tier":1,"deck":["militia","militia","militia","militia","militia","hunter","hunter","rain"]},
	"hunter_master":{"tier":3,"deck":["hunter","hunter","hunter","hunter","militia","militia","barricade","barricade"]},
	"raven_mother":{"tier":2,"deck":["raven","raven","raven","bandit","bandit","bandit","skeleton","skeleton"]},
	"card_enemy_pouch_beast":{"tier":3,"deck":["pouch_beast","pouch_beast","pouch_beast","fishbeak","fishbeak","bearded_imp","net_hunter","monster_hatchery"]},
	"fishbeak_boss":{"tier":3,"deck":["fishbeak","fishbeak","fishbeak","fishbeak","bearded_imp","bearded_imp","militia","militia"]},
	"ox_herder":{"tier":1,"deck":["ox","ox","ox","farmer","farmer","militia","militia","militia"]},
	"shield_sergeant":{"tier":3,"deck":["shieldguard","shieldguard","shieldguard","shieldguard","hunter","hunter","drummer","drummer"]},
	"drummer_major":{"tier":1,"deck":["drummer","drummer","mob","mob","militia","militia","bandit","bandit"]},
	"skeleton_king":{"tier":2,"deck":["skeleton","skeleton","skeleton","skeleton","ghoul","ghoul","bonewall","plague"]},
	"trap_weaver":{"tier":2,"deck":["blast_trap","blast_trap","teleport_trap","teleport_trap","hunter","hunter","militia","militia"]},
	"imp_thief":{"tier":3,"deck":["bearded_imp","bearded_imp","bearded_imp","bearded_imp","hooknose_flyer","hooknose_flyer","barricade","barricade"]},
	"knight_commander":{"tier":3,"deck":["knight","knight","knight","healer","healer","shieldguard","shieldguard","shieldguard"]},
	"tower_warden":{"tier":3,"deck":["hunter","hunter","hunter","tower","barricade","barricade","militia","militia"]},
	"necro_adept":{"tier":2,"deck":["necromancer","necromancer","skeleton","skeleton","skeleton","bonewall","curse","ghoul"]},
	"golem_smith":{"tier":3,"deck":["arcane_golem","arcane_golem","artificer","artificer","arcane_shield","arcane_shield","militia","militia"]},
	"catapult_engineer":{"tier":3,"deck":["catapult","catapult","shieldguard","shieldguard","shieldguard","barricade","barricade","barricade"]},
	"dragon_lord":{"tier":3,"deck":["thorn_dragon","thorn_dragon","eyewing_dragon","eyewing_dragon","belly_eye","belly_eye","long_dragon","long_dragon"]},
	"card_enemy_mule_cart":{"tier":2,"deck":["mule_cart","mule_cart","manor_retainer","halberdier","hunter","healer","watchtower","rain"]},
	"card_enemy_hook_collector":{"tier":1,"deck":["hook_collector","hook_collector","charge_horn","ox","militia","arquebusier","rain","drummer"]},
	"card_enemy_twin_gambler":{"tier":2,"deck":["twin_gambler","twin_gambler","drummer","healer","shieldguard","hunter","counter_charge","rain"]},
	"card_enemy_seal_altar":{"tier":2,"deck":["seal_altar","skeleton","skeleton","sacrifice","mass_grave","ghoul","necromancer","bellbearer"]},
	"card_enemy_plague_bishop":{"tier":3,"deck":["seal_altar","plague","plague","skeleton","mourning_maid","bellbearer","corpse_giant","ossuary"]},
	"card_enemy_funeral_monk":{"tier":1,"deck":["seal_altar","bellbearer","bellbearer","mourning_maid","pallbearer","skeleton","raven","sealed_coffin"]},
	"card_enemy_gold_monster":{"tier":2,"deck":["gold_monster","gold_monster","farmer","shieldguard","hunter","harvest","rain","drummer"]},
	"card_enemy_spell_tide_magus":{"tier":2,"deck":["spell_tide_magus","spell_tide_magus","arcane_shield","phase_shift","gravity_well","time_field","rune_sentinel","chain_lightning"]},
	"card_enemy_thorn_mother":{"tier":2,"deck":["thorn_mother","thorn_mother","thorn_hound","thorn_hound","bramble_wall","pouch_beast","halberdier","thorn_dragon"]},
	"card_enemy_gatebreaker":{"tier":1,"deck":["gatebreaker","gatebreaker","militia","healer","shieldguard","hunter","ox","rain"]},
	"card_enemy_disgraced_lancer":{"tier":1,"deck":["disgraced_lancer","disgraced_lancer","charge_horn","ox","manor_retainer","hunter","healer","counter_charge"]},
	"card_enemy_runaway_thrall":{"tier":1,"deck":["runaway_thrall","runaway_thrall","bandit","ox","militia","hunter","fire","rain"]},
	"card_enemy_renegade_artificer":{"tier":1,"deck":["renegade_artificer","renegade_artificer","shieldguard","healer","net_hunter","hunter","tower","rain"]},
	"card_enemy_oathless_imp":{"tier":1,"deck":["oathless_imp","oathless_imp","healer","drummer","militia","net_hunter","spearbow","rain"]},
	"card_enemy_assassin":{"tier":1,"deck":["assassin","assassin","bandit","ox","militia","hunter","charge_horn","fire"]},
	"card_enemy_vampire_hunter":{"tier":3,"deck":["vampire_hunter","vampire_hunter","shieldguard","militia","net_hunter","healer","barricade","rain"]},
	"card_enemy_monster_hunter":{"tier":2,"deck":["monster_hunter","monster_hunter","halberdier","shieldguard","hunter","healer","net_hunter","rain"]},
	"card_enemy_spellbreaker":{"tier":1,"deck":["spellbreaker","spellbreaker","knight","shieldguard","healer","hunter","barricade","spearbow"]},
	"card_enemy_powder_barrel":{"tier":3,"deck":["powder_barrel","powder_barrel","scarecrow","net_hunter","hunter","militia","barricade","counter_charge"]},
	"card_enemy_pallbearer":{"tier":2,"deck":["pallbearer","pallbearer","skeleton","ossuary","funeral_cottage","shroud_arbalist","ghoul","curse"]},
	"card_enemy_mourning_maid":{"tier":3,"deck":["mourning_maid","mourning_maid","shroud_arbalist","skeleton","bonewall","ghoul","reaper","plague"]},
	"card_enemy_corpse_stitcher":{"tier":3,"deck":["corpse_stitcher","corpse_stitcher","skeleton","pallbearer","borrowed_bones","ghoul","mass_grave","funeral_cottage"]},
	"card_enemy_blood_attendant":{"tier":2,"deck":["blood_attendant","blood_attendant","blood_tower","blood_altar","mourning_shroud","dark_wizard","ghoul","reaper"]},
	"card_enemy_funeral_cottage":{"tier":1,"deck":["funeral_cottage","funeral_cottage","skeleton","borrowed_bones","pallbearer","ghoul","shroud_arbalist","sacrifice"]},
	"card_enemy_sleepless_belfry":{"tier":2,"deck":["sleepless_belfry","sleepless_belfry","blood_attendant","ghoul","reaper","shroud_arbalist","mourning_shroud","corpse_giant"]},
	"card_enemy_blood_altar":{"tier":1,"deck":["blood_altar","blood_altar","pallbearer","skeleton","blood_attendant","corpse_giant","ghoul","mourning_shroud"]},
	"card_enemy_borrowed_bones":{"tier":1,"deck":["borrowed_bones","borrowed_bones","sacrifice","skeleton","corpse_stitcher","dark_wizard","ghoul","soul_well"]},
	"card_enemy_grave_exchange":{"tier":1,"deck":["grave_exchange","grave_exchange","funeral_cottage","ossuary","bonewall","mass_grave","ghoul","dark_wizard"]},
	"card_enemy_mourning_shroud":{"tier":1,"deck":["mourning_shroud","mourning_shroud","blood_attendant","reaper","ghoul","shroud_arbalist","skeleton","sealed_coffin"]},
	"card_enemy_sealed_coffin":{"tier":1,"deck":["sealed_coffin","sealed_coffin","shroud_arbalist","dog_cannon","funeral_grenadier","skeleton","ghoul","reaper"]},
	"card_enemy_arquebusier":{"tier":3,"deck":["arquebusier","arquebusier","shieldguard","manor_retainer","field_smithy","healer","net_hunter","barricade"]},
	"card_enemy_funeral_grenadier":{"tier":2,"deck":["funeral_grenadier","funeral_grenadier","bonewall","sleepless_belfry","skeleton","ghoul","sealed_coffin","plague"]},
	"card_enemy_dog_cannon":{"tier":3,"deck":["dog_cannon","dog_cannon","skeleton","pallbearer","raven","reaper","dread_howl","soul_well"]},
	"card_enemy_orrery_walker":{"tier":3,"deck":["orrery_walker","orrery_walker","observatory","arcane_golem","arcane_shield","artificer","chronomancer","time_field"]},
	"card_enemy_seal_bearer":{"tier":2,"deck":["seal_bearer","seal_bearer","arcane_golem","sigil_weaver","chronomancer","arcane_shield","blast_trap","artificer"]},
	"card_enemy_imp_bomb_runner":{"tier":3,"deck":["imp_bomb_runner","imp_bomb_runner","pack_ambush","fishbeak","pouch_beast","bearded_imp","hooknose_flyer","corrosive_bile"]},
	"card_enemy_macebreaker":{"tier":1,"deck":["macebreaker","macebreaker","healer","drummer","shieldguard","hunter","ox","counter_charge"]},
	"card_enemy_beekeeper":{"tier":1,"deck":["beekeeper","beekeeper","net_hunter","shieldguard","healer","militia","scarecrow","barricade"]},
	"card_enemy_bellbearer":{"tier":1,"deck":["bellbearer","bellbearer","skeleton","skeleton","pallbearer","ghoul","soul_well","curse"]},
	"card_enemy_shroud_arbalist":{"tier":2,"deck":["shroud_arbalist","shroud_arbalist","bonewall","skeleton","mourning_maid","ghoul","sealed_coffin","plague"]},
	"card_enemy_sigil_weaver":{"tier":3,"deck":["sigil_weaver","sigil_weaver","prism_mage","arcane_golem","arcane_shield","chronomancer","rune_sentinel","mana_drain"]},
	"card_enemy_astrolabe_surveyor":{"tier":3,"deck":["astrolabe_surveyor","astrolabe_surveyor","observatory","arcane_archer","arcane_golem","chronomancer","teleport_trap","arcane_shield"]},
	"card_enemy_bog_troll":{"tier":3,"deck":["bog_troll","bog_troll","war_lodge","blood_cauldron","web_spinner","pack_ambush","fishbeak","corrosive_bile"]},
	"card_enemy_tusk_boar":{"tier":1,"deck":["tusk_boar","tusk_boar","pack_ambush","war_lodge","pouch_beast","fishbeak","web_spinner","wing_gust"]},
	"card_enemy_granary":{"tier":1,"deck":["granary","granary","farmer","harvest","mill","shieldguard","hunter","barricade"]},
	"card_enemy_field_smithy":{"tier":1,"deck":["field_smithy","field_smithy","militia","manor_retainer","halberdier","arquebusier","healer","hunter"]},
	"card_enemy_ossuary":{"tier":2,"deck":["ossuary","ossuary","corpse_stitcher","ghoul","necromancer","dark_wizard","sacrifice","funeral_cottage"]},
	"card_enemy_soul_well":{"tier":1,"deck":["soul_well","soul_well","blood_attendant","reaper","ghoul","shroud_arbalist","skeleton","dread_howl"]},
	"card_enemy_observatory":{"tier":3,"deck":["observatory","observatory","arcane_archer","astrolabe_surveyor","prism_mage","orrery_walker","arcane_golem","time_field"]},
	"card_enemy_rune_workshop":{"tier":1,"deck":["rune_workshop","rune_workshop","arcane_tower","warp_beacon","mana_battery","arcane_golem","artificer","chain_lightning"]},
	"card_enemy_monster_hatchery":{"tier":3,"deck":["monster_hatchery","monster_hatchery","pouch_beast","pack_ambush","berserk_blood","web_spinner","fishbeak","feral_mutation"]},
	"card_enemy_war_lodge":{"tier":2,"deck":["war_lodge","war_lodge","tusk_boar","bog_troll","dire_hydra","web_spinner","pouch_beast","corrosive_bile"]},
	"card_enemy_old_witch":{"tier":1,"deck":["old_witch","old_witch","shieldguard","net_hunter","barricade","healer","tower","rain"]},
	"card_enemy_halberdier":{"tier":1,"deck":["halberdier","halberdier","field_smithy","shieldguard","hunter","healer","barricade","counter_charge"]},
	"card_enemy_ballista_tower":{"tier":2,"deck":["ballista_tower","ballista_tower","barricade","shieldguard","manor_retainer","net_hunter","healer","rain"]},
	"card_enemy_supply_depot":{"tier":1,"deck":["supply_depot","supply_depot","militia","bandit","ox","halberdier","hunter","charge_horn"]},
	"card_enemy_counter_charge":{"tier":1,"deck":["counter_charge","counter_charge","knight","halberdier","arquebusier","healer","ox","barricade"]},
	"card_enemy_flaming_pitch":{"tier":2,"deck":["flaming_pitch","flaming_pitch","scarecrow","shieldguard","net_hunter","hunter","barricade","militia"]},
	"card_enemy_rune_sentinel":{"tier":1,"deck":["rune_sentinel","rune_sentinel","arcane_shield","chronomancer","prism_mage","sigil_weaver","mana_spring","arcane_tower"]},
	"card_enemy_ward_guard":{"tier":1,"deck":["ward_phalanx","spell_tide_magus","rune_sentinel","arcane_shield","prism_mage","sigil_weaver","mana_spring","arcane_tower"]},
	"card_enemy_ward_phalanx":{"tier":2,"deck":["ward_phalanx","ward_phalanx","arcane_archer","seal_bearer","arcane_shield","time_field","chronomancer","artificer"]},
	"card_enemy_prism_mage":{"tier":2,"deck":["prism_mage","prism_mage","observatory","arcane_golem","arcane_shield","time_field","chronomancer","artificer"]},
	"card_enemy_aether_hound":{"tier":2,"deck":["aether_hound","aether_hound","arcane_shield","phase_shift","blink_blade","chronomancer","prism_mage","time_field"]},
	"card_enemy_spell_mirror":{"tier":3,"deck":["spell_mirror","spell_mirror","chain_lightning","gravity_well","time_field","mana_battery","arcane_golem","arcane_archer"]},
	"card_enemy_mana_battery":{"tier":2,"deck":["mana_battery","mana_battery","chain_lightning","arcane_shield","time_field","gravity_well","arcane_golem","prism_mage"]},
	"card_enemy_warp_beacon":{"tier":3,"deck":["warp_beacon","warp_beacon","arcane_archer","prism_mage","astrolabe_surveyor","chronomancer","arcane_golem","time_field"]},
	"card_enemy_mana_drain":{"tier":2,"deck":["mana_drain","mana_drain","gravity_well","chronomancer","arcane_golem","arcane_archer","arcane_shield","prism_mage"]},
	"card_enemy_phase_shift":{"tier":3,"deck":["phase_shift","phase_shift","blink_blade","phase_rider","aether_hound","arcane_shield","chronomancer","time_field"]},
	"card_enemy_gravity_well":{"tier":2,"deck":["gravity_well","gravity_well","chain_lightning","rolling_boulder","chronomancer","prism_mage","arcane_golem","arcane_tower"]},
	"card_enemy_mirror_clone":{"tier":2,"deck":["mirror_clone","mirror_clone","arcane_golem","phase_rider","aether_hound","arcane_shield","artificer","chronomancer"]},
	"card_enemy_parasite_mite":{"tier":2,"deck":["parasite_mite","parasite_mite","swarm_eruption","feral_mutation","pack_ambush","pouch_beast","web_spinner","fishbeak"]},
	"card_enemy_thorn_hound":{"tier":2,"deck":["thorn_hound","thorn_hound","blood_cauldron","berserk_blood","pouch_beast","web_spinner","tusk_boar","pack_ambush"]},
	"card_enemy_web_spinner":{"tier":2,"deck":["web_spinner","web_spinner","tusk_boar","bog_troll","long_dragon","corrosive_bile","war_lodge","pouch_beast"]},
	"card_enemy_sky_scavenger":{"tier":3,"deck":["sky_scavenger","sky_scavenger","hooknose_flyer","eyewing_dragon","imp_bomb_runner","fishbeak","corrosive_bile","wing_gust"]},
	"card_enemy_dire_hydra":{"tier":3,"deck":["dire_hydra","dire_hydra","war_lodge","blood_cauldron","web_spinner","pouch_beast","corrosive_bile","pack_ambush"]},
	"card_enemy_mimic_egg":{"tier":3,"deck":["mimic_egg","mimic_egg","pouch_beast","pack_ambush","feral_mutation","web_spinner","fishbeak","corrosive_bile"]},
	"card_enemy_bramble_wall":{"tier":1,"deck":["bramble_wall","bramble_wall","thorn_hound","thorn_dragon","long_dragon","web_spinner","blood_cauldron","leech_vine"]},
	"card_enemy_blood_cauldron":{"tier":2,"deck":["blood_cauldron","blood_cauldron","tusk_boar","dire_hydra","pouch_beast","thorn_hound","web_spinner","pack_ambush"]},
	"card_enemy_hive_nest":{"tier":3,"deck":["hive_nest","hive_nest","hooknose_flyer","sky_scavenger","eyewing_dragon","wing_gust","belly_eye","bearded_imp"]},
	"card_enemy_leech_vine":{"tier":1,"deck":["leech_vine","leech_vine","bramble_wall","pouch_beast","web_spinner","long_dragon","blood_cauldron","corrosive_bile"]},
	"card_enemy_imp_burrow":{"tier":3,"deck":["imp_burrow","imp_burrow","bearded_imp","fishbeak","hooknose_flyer","pack_ambush","wing_gust","pouch_beast"]},
	"card_enemy_berserk_blood":{"tier":3,"deck":["berserk_blood","berserk_blood","pouch_beast","bog_troll","blood_cauldron","thorn_hound","tusk_boar","web_spinner"]},
	"card_enemy_corrosive_bile":{"tier":2,"deck":["corrosive_bile","corrosive_bile","fishbeak","tusk_boar","hooknose_flyer","imp_bomb_runner","pouch_beast","web_spinner"]},
	"card_enemy_pack_ambush":{"tier":2,"deck":["pack_ambush","pack_ambush","tusk_boar","pouch_beast","bog_troll","fishbeak","thorn_hound","war_lodge"]},
	"card_enemy_devouring_maw":{"tier":3,"deck":["devouring_maw","devouring_maw","fishbeak","tusk_boar","web_spinner","pouch_beast","bog_troll","corrosive_bile"]},
	"card_enemy_wing_gust":{"tier":3,"deck":["wing_gust","wing_gust","long_dragon","web_spinner","hooknose_flyer","sky_scavenger","hive_nest","pouch_beast"]},
	"card_enemy_feral_mutation":{"tier":3,"deck":["feral_mutation","feral_mutation","parasite_mite","pouch_beast","thorn_hound","bearded_imp","blood_cauldron","pack_ambush"]},
	"card_enemy_swarm_eruption":{"tier":2,"deck":["swarm_eruption","swarm_eruption","parasite_mite","corrosive_bile","imp_bomb_runner","web_spinner","pouch_beast","fishbeak"]},
}

# Floor 8: a normal lord with a full-strength, fighting deck.
const BOSSES := {
	"adventure":["knight","hunter","militia","ram","rain","healer","tower","spearbow"],
	"lion":["knight","drummer","ox","charge_horn","militia","hunter","spearbow","ram"],
	"iron":["knight","shieldguard","hunter","tower","manor_retainer","rain","spearbow","healer"],
	"harvest":["farmer","knight","mob","hunter","spearbow","rain","healer","ox"],
	"mage":["arcane_golem","arcane_shield","chronomancer","blast_trap","blink_blade","arcane_archer","phase_rider","time_field"],
	"rune":["arcane_tower","blast_trap","teleport_trap","summon_trap","artificer","seal_bearer","chronomancer","arcane_archer"],
	"underworld":["skeleton","ghoul","necromancer","reaper","bonewall","plague","raven","shroud_arbalist"],
	"vampire":["ghoul","dark_wizard","blood_tower","corpse_giant","mourning_shroud","sealed_coffin","sacrifice","blood_attendant"],
	"beast":["fishbeak","bearded_imp","hooknose_flyer","long_dragon","thorn_dragon","eyewing_dragon","pack_ambush","corrosive_bile"],
}

# Seven 小怪領主 for floors 1-7 (no repeats) and a boss for floor 8, fixed by the run's seed.
static func schedule(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array = []
	for tier: int in FLOOR_TIER:
		var choices: Array = MINIONS.keys().filter(func(k: String) -> bool: return MINIONS[k].get("enabled",true) and MINIONS[k].tier == tier and not k in result)
		result.append(choices[rng.randi_range(0,choices.size()-1)])
	var bosses: Array = BOSSES.keys()
	result.append(bosses[rng.randi_range(0,bosses.size()-1)])
	return result

static func elite_tier(floor_index: int) -> int:
	return mini(3,FLOOR_TIER[floor_index]+1)

# One elite per floor 1-7, never one of the run's normal foes and never twice; fixed by the seed.
static func elite_schedule(seed_value: int, foes: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*17+5
	var result: Array = []
	for i: int in range(FLOOR_TIER.size()):
		var choices: Array = MINIONS.keys().filter(func(k: String) -> bool: return MINIONS[k].get("enabled",true) and MINIONS[k].tier == elite_tier(i) and not k in foes and not k in result)
		choices.sort()
		result.append(choices[rng.randi_range(0,choices.size()-1)])
	return result

static func foe_deck(foe: String) -> Array:
	return (MINIONS[foe].deck if MINIONS.has(foe) else BOSSES[foe]).duplicate()

# Three different cards the lord may use, fixed by the run's seed and floor.
static func offer(lord: String, seed_value: int, floor_index: int, deck: Array = []) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*31+floor_index*977
	var pool: Array = card_pool(lord)
	var result: Array = []
	var groups: Array = []
	# Prefer unseen cards, then unrepresented roles; seeded choices remain stable on reload.
	while result.size() < OFFER_SIZE and not pool.is_empty():
		var fresh: Array = pool.filter(func(k: String) -> bool: return not k in deck)
		var candidates: Array = fresh if not fresh.is_empty() else pool
		var diverse: Array = candidates.filter(func(k: String) -> bool: return not B.card_group(k) in groups)
		if not diverse.is_empty(): candidates = diverse
		var chosen: String = candidates[rng.randi_range(0,candidates.size()-1)]
		result.append(chosen)
		groups.append(B.card_group(chosen))
		pool.erase(chosen)
	return result

static func gold_for(floor_index: int) -> int:
	return GOLD_BY_TIER[FLOOR_TIER[floor_index]] if floor_index < FLOOR_TIER.size() else 0

static func enemy_floor_scale(floor_index: int) -> float:
	var t := clampf(float(floor_index)/float(maxi(1,FLOORS-1)),0.0,1.0)
	return lerpf(1.0,2.0,t)

# One relic of each price the run does not own yet, fixed by seed and floor.
static func relic_offer(seed_value: int, floor_index: int, owned: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*53+floor_index*389
	var result: Array = []
	for price: int in RELIC_PRICES:
		var choices: Array = RELICS.keys().filter(func(k: String) -> bool: return RELICS[k].price == price and not k in owned)
		choices.sort()
		if not choices.is_empty(): result.append(choices[rng.randi_range(0,choices.size()-1)])
	return result

# Stack passive rule sets: multipliers multiply, gold adds, lists join, start buildings skip taken cells.
static func merge_mods(base: Dictionary, extra: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for key: String in extra:
		var value = extra[key]
		if not result.has(key): result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
		elif key.ends_with("_mult") or key == "skill_haste": result[key] *= value
		elif key in ["start_ink","skill_discount","lord_boost","thorns_gate","kill_bounty","gold_bonus"]: result[key] += value
		elif key == "gate_armor": result[key] = minf(0.6,result[key]+value)
		elif key == "post_heal":
			for k: String in value: result[key][k] = result[key].get(k,0.0)+value[k]
		elif key == "cycle_speed":
			for k: String in value: result[key][k] = result[key].get(k,1.0)*value[k]
		elif key == "swarm":
			for k: String in value: result[key][k] = result[key].get(k,0)+value[k]
		elif key in ["toughen","haste"]:
			for k in value:
				if not k in result[key]: result[key].append(k)
		elif key == "targeted_upgrade": result[key] = result.get(key,false) or bool(value)
		elif key == "start_buildings":
			for b: Array in value:
				if not result[key].any(func(o: Array) -> bool: return o[0] == b[0] and o[1] == b[1]): result[key].append(b)
		elif key == "field_mutators":
			result[key].append_array(value.duplicate(true))
	return result

static func side_mods(lord: String, relics: Array) -> Dictionary:
	var mods: Dictionary = passive(lord)
	for r: String in relics: mods = merge_mods(mods,RELICS[r].mods)
	return mods

# Pick one unowned relic (optionally filtered by max_price), seeded deterministically.
static func pick_free_relic(seed_value: int, salt: int, owned: Array, max_price: int = 600) -> String:
	var choices: Array = RELICS.keys().filter(func(k: String) -> bool: return not k in owned and RELICS[k].price <= max_price)
	choices.sort()
	if choices.is_empty(): return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*97+salt*521+owned.size()*31
	return choices[rng.randi_range(0,choices.size()-1)]

# ---- 4-slot encounter board (四選一命運牌陣：觸發單格遞補、特殊情況連鎖變異) -------------------------

static func pick_minion(tier: int, seed_value: int, salt: int, avoid: Array) -> String:
	var pool: Array = MINIONS.keys().filter(func(k: String) -> bool: return MINIONS[k].get("enabled",true) and MINIONS[k].tier == tier and not k in avoid)
	if pool.is_empty(): pool = MINIONS.keys().filter(func(k: String) -> bool: return MINIONS[k].get("enabled",true) and MINIONS[k].tier == tier)
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*61+salt*313+tier*17
	return pool[rng.randi_range(0,pool.size()-1)]

const BOSS_MUTATORS := {
	"harvest":{"id":"harvest_fields","name":"萬頃良田","desc":"開局前 2 排蓋滿 10 座農田，且魔王農田產出 ×1.5","double_home_rows":true,"mods":{"farm_mult":1.5}},
	"iron":{"id":"steel_citadel","name":"不朽鋼城","desc":"全 5 路前線預築木拒馬與 2 座箭樓，城牆減傷 35%、反傷 35","enemy_buildings":[[2,0,"barricade"],[2,1,"barricade"],[2,2,"barricade"],[2,3,"barricade"],[2,4,"barricade"],[1,1,"tower"],[1,3,"tower"]],"mods":{"gate_armor":0.35,"thorns_gate":35.0}},
	"lion":{"id":"royal_charge","name":"獅王鐵騎","desc":"開局已派遣 3 名騎士自三路壓境，且開局金幣額外 +15","enemy_units":[[2,1,"knight"],[2,2,"knight"],[2,3,"knight"]],"extra_ink":15.0},
	"underworld":{"id":"living_graveyard","name":"百鬼夜行","desc":"每隔 30 秒戰場隨機浮現一座墓碑（滿格改招 4 骷髏），開局中路先立 2 座墓碑","enemy_buildings":[[1,2,"grave"],[2,2,"grave"]],"periodic":{"interval":30.0,"kind":"grave","team":1,"min_col":1,"max_col":6,"fallback_unit":"skeleton","fallback_count":4}},
	"beast":{"id":"flooded_beasts","name":"怒濤澤國","desc":"中央三條縱向戰區化為水路（無法建築，除飛行單位外緩速 60%），開局預藏 2 座巨獸孵巢","water_cols":[3,4,5],"enemy_buildings":[[0,0,"monster_hatchery"],[0,4,"monster_hatchery"]]},
	"mage":{"id":"chrono_storm","name":"時空風暴","desc":"每隔 25 秒戰場隨機降下時空力場減速，第 I、V 路化為禁建水路（非飛行 -60% 速）","water_lanes":[0,4],"periodic_spell":{"interval":25.0,"kind":"time_field","team":1}},
	"rune":{"id":"rune_minefield","name":"萬法迷陣","desc":"開局前線鋪設 5 座傳送／爆破法陣，每 25 秒戰場隨機再浮現一座爆破法陣","enemy_buildings":[[2,0,"blast_trap"],[2,1,"teleport_trap"],[2,2,"blast_trap"],[2,3,"teleport_trap"],[2,4,"blast_trap"]],"periodic":{"interval":25.0,"kind":"blast_trap","team":1,"min_col":1,"max_col":5}},
	"vampire":{"id":"blood_moon","name":"血月永祭","desc":"開局前線預立 3 座鮮血塔，每 30 秒戰場隨機再浮現一座血誓祭壇","enemy_buildings":[[1,1,"blood_tower"],[1,2,"blood_tower"],[1,3,"blood_tower"]],"periodic":{"interval":30.0,"kind":"blood_altar","team":1,"min_col":0,"max_col":4,"fallback_unit":"skeleton","fallback_count":5}},
	"adventure":{"id":"legend_vanguard","name":"傳奇遠征","desc":"開局騎士、盾衛與猛牛先鋒直接登場進軍，且開局金幣額外 +20","enemy_units":[[2,1,"shieldguard"],[2,2,"knight"],[2,3,"ox"]],"extra_ink":20.0},
}

const ELITE_MUTATORS := {
	"water_mid":{"id":"water_mid","name":"中庭洪氾水路","desc":"中央三條縱列化為水路（無法建築，除飛行單位外緩速 60%）","water_cols":[3,4,5]},
	"water_flanks":{"id":"water_flanks","name":"兩翼沼澤水路","desc":"第 I、V 路變成水路（無法建築，除飛行單位外緩速 60%）","water_lanes":[0,4]},
	"double_economy":{"id":"double_economy","name":"雙排狂築莊園","desc":"精英開局前 2 排築滿共 10 座敵方常駐經濟建築","double_home_rows":true},
	"periodic_grave":{"id":"periodic_grave","name":"靈塚湧現","desc":"每隔 30 秒戰場隨機浮現一座墓碑（無空位則召喚 3 隻骷髏兵）","periodic":{"interval":30.0,"kind":"grave","team":1,"min_col":1,"max_col":6,"fallback_unit":"skeleton","fallback_count":3}},
	"periodic_trap":{"id":"periodic_trap","name":"秘術亂陣","desc":"每隔 25 秒戰場隨機浮現一座爆破法陣","periodic":{"interval":25.0,"kind":"blast_trap","team":1,"min_col":1,"max_col":6}},
	"iron_barricade":{"id":"iron_barricade","name":"鋼鐵先鋒壁壘","desc":"敵方全 5 路前排預築木拒馬，城牆減傷 25%","enemy_buildings":[[2,0,"barricade"],[2,1,"barricade"],[2,2,"barricade"],[2,3,"barricade"],[2,4,"barricade"]],"mods":{"gate_armor":0.25}},
	"swarm_surge":{"id":"swarm_surge","name":"兵海狂潮","desc":"敵方每張部隊卡額外多出 1 名單位","mods":{"swarm":{"*":1}}},
	"blood_frenzy":{"id":"blood_frenzy","name":"狂暴突襲","desc":"敵軍全體移速與攻速升一檔，且開局金幣額外 +12","mods":{"haste":["*"]},"extra_ink":12.0},
}

static func roll_elite_mutator(foe: String, seed_val: int, salt: int) -> String:
	var keys: Array = ELITE_MUTATORS.keys()
	keys.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val*73+salt*199+hash(foe)
	var card_kind := String(B.MINION_LORDS.get(foe,{}).get("card",""))
	var cdata: Dictionary = B.CARDS.get(card_kind,{})
	# Thematic affinity so flying elites flood lanes, undead elites raise graves, etc. 70% of the time.
	if rng.randf() < 0.70:
		if bool(cdata.get("flying",false)) or card_kind in ["wing_gust"]:
			return "water_mid" if rng.randf() < 0.75 else "water_flanks"
		if card_kind in ["farmer","harvest","mill","granary","crystal","glutton_nest","supply_depot"]:
			return "double_economy"
		if B.card_faction(card_kind) == "dark":
			return "periodic_grave"
		if card_kind in ["blast_trap","teleport_trap","warp_beacon","rune_workshop","gravity_well"]:
			return "periodic_trap"
		if card_kind in ["barricade","tower","ballista_tower","shieldguard","wall"]:
			return "iron_barricade"
	return String(keys[rng.randi_range(0,keys.size()-1)])

static func mutator_data(slot: Dictionary) -> Dictionary:
	var k := String(slot.get("kind","battle"))
	var mid := String(slot.get("mutator",""))
	if k == "boss":
		var fk := String(slot.get("foe","")) if mid.is_empty() else mid
		return BOSS_MUTATORS.get(fk,{})
	if k == "elite":
		return ELITE_MUTATORS.get(mid,{})
	return {}

static func make_slot(kind: String, r: Dictionary, salt: int = 0) -> Dictionary:
	var fl := clampi(int(r.get("floor",0)),0,FLOORS-1)
	var draws := int(r.get("draws",0))
	var seed_val := int(r.get("seed",1))
	var used_foes: Array = []
	var used_events: Array = []
	for s in r.get("board",[]):
		if s is Dictionary:
			if not s.get("foe","").is_empty(): used_foes.append(s.foe)
			if not s.get("event_id","").is_empty(): used_events.append(s.event_id)
	if kind == "boss" or (kind in ["battle","elite"] and fl >= FLOORS-1):
		var b_foe: String = r.foes[FLOORS-1]
		return {"kind":"boss","foe":b_foe,"mutator":b_foe,"event_id":"","bounty":0,"age":0}
	if kind == "battle":
		var foe: String = r.foes[fl]
		if foe in used_foes: foe = pick_minion(FLOOR_TIER[fl],seed_val,draws+salt+fl*11,used_foes)
		return {"kind":"battle","foe":foe,"event_id":"","bounty":0,"age":0}
	if kind == "elite":
		var e_foe: String = r.elites[fl] if r.get("elites",[]).size() > fl else pick_minion(elite_tier(fl),seed_val,draws+salt,used_foes)
		if e_foe in used_foes: e_foe = pick_minion(elite_tier(fl),seed_val,draws+salt+fl*19,used_foes)
		return {"kind":"elite","foe":e_foe,"mutator":roll_elite_mutator(e_foe,seed_val,draws+salt+fl*37),"event_id":"","bounty":0,"age":0}
	if kind == "event":
		var keys: Array = EVENTS.keys().filter(func(k: String) -> bool: return not k in used_events)
		if keys.is_empty(): keys = EVENTS.keys()
		keys.sort()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val*43+draws*197+salt*73+fl*29
		var ev: String = keys[rng.randi_range(0,keys.size()-1)]
		return {"kind":"event","foe":"","event_id":ev,"bounty":0,"age":0}
	return {"kind":kind,"foe":"","event_id":"","bounty":0,"age":0}

static func initial_board(r: Dictionary) -> Array:
	if int(r.get("floor",0)) >= FLOORS-1: return boss_board(r)
	return [make_slot("battle",r,1),make_slot("elite",r,2),make_slot("event",r,3),make_slot("camp",r,4)]

static func boss_board(r: Dictionary) -> Array:
	return [make_slot("boss",r,1),make_slot("camp",r,2),make_slot("shrine",r,3),make_slot("event",r,4)]

static func draw_replacement_slot(r: Dictionary, slot_index: int) -> Dictionary:
	r.draws = int(r.get("draws",0))+1
	var fl := clampi(int(r.get("floor",0)),0,FLOORS-1)
	if fl >= FLOORS-1:
		return make_slot("boss",r,slot_index+r.draws)
	var board: Array = r.get("board",[])
	var combat_count := 0
	var elite_count := 0
	var non_combat_kinds: Array = []
	for i: int in range(board.size()):
		if i == slot_index or not board[i] is Dictionary: continue
		var k: String = board[i].get("kind","battle")
		if k in ["battle","elite","boss"]:
			combat_count += 1
			if k == "elite": elite_count += 1
		else: non_combat_kinds.append(k)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(r.get("seed",1))*89+r.draws*353+slot_index*47+fl*13
	# Ensure at least 2 combat slots on the board, or force combat when march_steps runs out.
	if combat_count < 2 or int(r.get("march_steps",2)) <= 0:
		var want_elite := elite_count == 0 and rng.randf() < 0.45
		return make_slot("elite" if want_elite else "battle",r,slot_index+r.draws)
	var candidates: Array = ["battle","elite","event","camp","shrine"]
	if elite_count >= 2: candidates.erase("elite")
	for nk: String in non_combat_kinds:
		if nk in ["camp","shrine"]: candidates.erase(nk)
	var chosen: String = candidates[rng.randi_range(0,candidates.size()-1)]
	return make_slot(chosen,r,slot_index+r.draws)

# Everything wrong with the tables ([] = fine). quick_test fails on any problem.
static func validate() -> Array[String]:
	var problems: Array[String] = []
	for lord: String in B.LORDS:
		if not LORD_ROLES.has(lord): problems.append("no roguelike roles for "+lord)
		if not BOSSES.has(lord): problems.append("no boss deck for "+lord)
	for lord: String in LORD_ROLES:
		var roles: Dictionary = LORD_ROLES[lord]
		if not STARTER_CORE.has(B.lord_faction(lord)): problems.append("no starter troops for %s's faction" % lord)
		var mods: Dictionary = roles.get("domestic",{}).get("passive",{})
		if mods.is_empty() or B.passive_text(mods).length() < 3: problems.append("%s has no passive" % lord)
		var cards := starter_deck(lord, 42)
		if cards.size() != 8 or not deck_allowed(cards,lord): problems.append("starter %s is not a legal 8-card deck" % lord)
		var fac: String = B.lord_faction(lord)
		if not cards.all(func(k: String) -> bool: return B.card_faction(k) == fac): problems.append("starter %s contains off-faction card" % lord)
	for faction: String in STARTER_CORE:
		for k: String in STARTER_CORE[faction]:
			if B.card_faction(k) != faction: problems.append("starter core %s: %s is not that faction's card" % [faction,k])
		if B.card_group(STARTER_CORE[faction][0]) != 0 or B.card_group(STARTER_CORE[faction][1]) != 1: problems.append("starter core %s must be one melee then one ranged troop" % faction)
	for foe: String in MINIONS:
		if not B.MINION_LORDS.has(foe): problems.append("minion deck for unknown lord "+foe)
		if not DeckStore.valid(MINIONS[foe].deck,"",true): problems.append("minion %s deck is not legal" % foe)
		if B.home_card(foe) in MINIONS[foe].deck: problems.append("minion %s deck holds its home card" % foe)
	for foe: String in B.MINION_LORDS:
		if not MINIONS.has(foe): problems.append("minion lord %s has no deck" % foe)
	for tier: int in [1,2,3]:
		var need: int = FLOOR_TIER.count(tier)
		if MINIONS.values().filter(func(d: Dictionary) -> bool: return d.get("enabled",true) and d.tier == tier).size() < need: problems.append("not enough tier %d minions" % tier)
	for lord: String in BOSSES:
		if not DeckStore.valid(BOSSES[lord],lord): problems.append("boss deck %s is not legal" % lord)
	for tier: int in [1,2,3]:
		var need: int = FLOOR_TIER.count(tier)+range(FLOOR_TIER.size()).filter(func(i: int) -> bool: return elite_tier(i) == tier).size()
		if MINIONS.values().filter(func(d: Dictionary) -> bool: return d.get("enabled",true) and d.tier == tier).size() < need: problems.append("not enough tier %d 小怪 for normal foes plus elites" % tier)
	for r: String in RELICS:
		if not RELICS[r].price in RELIC_PRICES: problems.append("relic %s has an off-list price" % r)
		if B.passive_text(RELICS[r].mods).length() < 3: problems.append("relic %s has no effect" % r)
	for price: int in RELIC_PRICES:
		if RELICS.values().filter(func(d: Dictionary) -> bool: return d.price == price).size() < 2: problems.append("fewer than two relics at %d" % price)
	for card: String in B.CARDS:
		var matching: Array = MINIONS.keys().filter(func(k: String) -> bool: return B.MINION_LORDS.has(k) and B.MINION_LORDS[k].card == card)
		if matching.size() != 1: problems.append("card needs exactly one enemy: "+card)
		elif B.CARDS[card].get("unreleased",false) and MINIONS[matching[0]].get("enabled",true): problems.append("unreleased enemy must stay disabled: "+card)
	for ev: String in EVENTS:
		var ed: Dictionary = EVENTS[ev]
		if not B.CARDS.has(ed.get("art","")): problems.append("event %s uses unknown art card" % ev)
		if ed.get("choices",[]).size() != 3: problems.append("event %s must have 3 choices" % ev)
	if CONTRACTS.size() < 4: problems.append("fewer than 4 contracts")
	return problems
