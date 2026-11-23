extends RefCounted
# 肉鴿模式 content (2026-11-06). Authoring data only: no battle, UI or save files.
# A run is 8 battles: floors 1-7 against 小怪領主 (B.MINION_LORDS) of rising tier, floor 8 against a
# normal lord as the boss. One loss ends the run. Each win offers 3 cards; the player swaps one in.
const B = preload("res://balance.gd")
const Terrain = preload("res://rogue_terrain.gd") # 每個怪的戰場與精英名單
const DeckStore = preload("res://deck_store.gd")

const FLOORS := 8 # difficulty index 0..7: the seasons climb 0..6 (SEASON_FLOORS); 7 is the final 魔王
# 四季（使用者 2026-11-23）：春夏秋冬各一疊牌庫，牌陣一次亮 4 面旗、從牌庫補旗。翻出季節 BOSS 時其他旗全部變成
# BOSS，打倒後換下一季的新牌庫；四季都過了才出魔王（第 8 檔）。
const SEASONS := ["spring","summer","autumn","winter"]
const SEASON_NAMES := ["春","夏","秋","冬"]
const SEASON_SIZE := 10
const SEASON_FIXED := {"battle":4,"elite":2}
const SEASON_RANDOM_COUNT := 3
const SEASON_RANDOM_KINDS := ["event","camp","shrine"]
const SEASON_PILE := {"battle":4,"elite":2,"event":1,"camp":1,"shrine":1} # allowed non-boss flag kinds
const SEASON_FLOORS := [[0,1],[2,3],[4,5],[6,6]] # difficulty per season: [early, after SEASON_LATE_WINS wins]
const SEASON_LATE_WINS := 2
const SEASON_GOLD_SHARE := 0.80 # 10-card seasons have fewer battles per season than 20-card ones
const SEASON_BOSS_GOLD_MULT := 3.0
const SEASON_BOSS_START_INK := 20.0
const ENEMY_LORD_STEP_PCT := 0.05 # +5% additive enemy lord HP & damage per card cleared across the run
const SEASON_BOSS_LORD_PCT := 0.50
const BOSS_LORD_PCT := 0.80
# 季節 BOSS：本人生命與傷害 +SEASON_BOSS_LORD_PCT（與過牌加成加算）並帶射擊，並將牌組中的 1 張代表卡強化為
# 專屬 2×2 單體巨獸（blood tier SSS = 6666）。每季從該季的兩位裡依種子挑一位。
const SEASON_BOSSES := {
	"sealed_golem":{"name":"春雷魔像匠","season":0,"base":"golem_smith","replace":"arcane_golem","giant":"giant_arcane_golem"},
	"sealed_catapult":{"name":"破城攻城匠","season":0,"base":"catapult_engineer","replace":"catapult","giant":"giant_catapult","skill":{"escort":"shieldguard"}},
	"sealed_dragon":{"name":"烈日荊棘龍王","season":1,"base":"dragon_lord","replace":"thorn_dragon","giant":"giant_thorn_dragon"},
	"sealed_corpse_giant":{"name":"腐土屍巨人","season":1,"base":"card_enemy_corpse_giant","replace":"corpse_giant","giant":"giant_corpse_giant","skill":{"summon_count":2}},
	"sealed_thorn_mother":{"name":"甦醒的荊棘母獸","season":2,"base":"card_enemy_thorn_mother","replace":"thorn_mother","giant":"giant_thorn_mother"},
	"sealed_hydra":{"name":"沼澤九頭蛇","season":2,"base":"card_enemy_dire_hydra","replace":"dire_hydra","giant":"giant_dire_hydra"},
	"sealed_knight":{"name":"叛誓騎士團長","season":3,"base":"knight_commander","replace":"knight","giant":"giant_knight","skill":{"summon_count":2}},
	"sealed_plague_bishop":{"name":"被封印的瘟疫祭司","season":3,"base":"card_enemy_plague_bishop","replace":"seal_altar","giant":"giant_plague_bishop","skill":{"summon_count":1,"skill_cost":35.0},"deck_swap":["plague","skeleton"]},
}
# 季節 BOSS 版的「親衛」技能與牌組：除 deck_swap 外，另將 replace 代表卡換成對應的 2×2 巨獸卡 giant。
static func season_boss_deck(key: String) -> Array:
	var d: Dictionary = SEASON_BOSSES[key]
	var deck: Array = foe_deck(String(d.base))
	var swap: Array = d.get("deck_swap",[])
	if swap.size() == 2 and swap[0] in deck: deck[deck.find(swap[0])] = swap[1]
	var rep: String = String(d.get("replace",""))
	var gkind: String = String(d.get("giant",""))
	if not rep.is_empty() and not gkind.is_empty() and rep in deck: deck[deck.find(rep)] = gkind
	return deck

static func season_boss_skill_text(key: String) -> String:
	var d: Dictionary = SEASON_BOSSES[key]
	var base: String = d.base
	var info: Dictionary = B.lord_data(base)
	var over: Dictionary = d.get("skill",{})
	var cost: float = float(over.get("skill_cost",info.get("skill_cost",B.SKILL_COST)))
	var card: String = String(info.get("skill_card",""))
	if String(info.get("skill_kind","")) != "unit" or not B.CARDS.has(card): return B.skill_text(base)
	var escort := ("，前面先站一隊%s" % B.CARDS[over.escort].name) if over.has("escort") else ""
	return "%s（充能 %d，冷卻 %d 秒）：於前線召喚 %d 隊%s%s。" % [info.get("skill",""),int(cost*B.SKILL_CHARGE_MULT+B.SKILL_CHARGE_BASE),int(info.get("skill_cooldown",40.0)),int(over.get("summon_count",info.get("summon_count",1))),B.CARDS[card].name,escort]

const SEASON_BOSS_SHOT := {"name":"首領魔彈","style":"bomb","mult":0.6,"interval":1.9,"radius":100.0,"flight":0.8,"range":413.0,"look":"rune","desc":"拋射落地爆炸，範圍傷害"}

# The four season bosses of a run, one per season, fixed by the seed.
static func season_boss_schedule(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*71+29
	var out: Array = []
	for s: int in range(SEASONS.size()):
		var pool: Array = SEASON_BOSSES.keys().filter(func(k: String) -> bool: return int(SEASON_BOSSES[k].season) == s)
		pool.sort()
		out.append(pool[rng.randi_range(0,pool.size()-1)])
	return out

# A season's shuffled 10-card pile: 4 battles, 2 elites, 3 random support flags, boss always last.
static func season_pile(seed_value: int, season: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*97+season*1931+7
	var pile: Array = []
	for kind: String in SEASON_FIXED:
		for i: int in range(int(SEASON_FIXED[kind])): pile.append(kind)
	for _i: int in range(SEASON_RANDOM_COUNT):
		pile.append(SEASON_RANDOM_KINDS[rng.randi_range(0,SEASON_RANDOM_KINDS.size()-1)])
	for i: int in range(pile.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var tmp = pile[i]
		pile[i] = pile[j]
		pile[j] = tmp
	pile.append("sboss") # 使用者：BOSS 最後必定出現——牌庫的最後一張
	return pile

static func season_floor(season: int, wins: int) -> int:
	if season >= SEASONS.size(): return FLOORS-1
	return int(SEASON_FLOORS[season][1 if wins >= SEASON_LATE_WINS else 0])

static func season_boss_slot(r: Dictionary) -> Dictionary:
	var key: String = r.sbosses[clampi(int(r.get("season",0)),0,SEASONS.size()-1)]
	return {"kind":"sboss","foe":SEASON_BOSSES[key].base,"sboss":key,"mutator":"","event_id":"","bounty":0,"age":0}

# Once the season's boss card turns up, every flag on the board becomes that boss.
static func boss_takes_board(r: Dictionary) -> bool:
	if not bool(r.get("boss_out",false)) or int(r.get("season",0)) >= SEASONS.size(): return false
	var board: Array = r.get("board",[])
	for i: int in range(board.size()): board[i] = season_boss_slot(r)
	return true
const FLOOR_TIER := [1,1,2,2,2,3,3] # floors 1-7; floor 8 is the boss
const AI_LEVEL := [0,0,1,1,1,2,2,2] # 簡單／普通／困難 per floor; the final boss plays 困難 with upgraded cards & boss passives
const OFFER_SIZE := 3
# A roguelike battle still undecided after this many seconds goes to the side whose gates have more
# health left; a tie counts as a loss (producer 2026-11-07: stalemates must end).
const TIME_LIMIT := 480.0
# Shop (producer 2026-11-07): gold for each win by the floor's tier; card upgrades (card_upgrades.gd)
# and relics are bought with it and last for the run.
# 2026-11-22：勝利金幣逐層提高（舊版依小怪階級 100／200／300 三段跳）。
const GOLD_BY_FLOOR := [200,280,360,460,560,660,780]
# 2026-11-22：敵方卡牌強化逐層提高，每張牌各自在 [低, 高] 之間隨機；精英兩端各 +1；魔王另見 BOSS_CARD_UPGRADES_*。
const ENEMY_UPS_BY_FLOOR := [[0,0],[0,0],[0,1],[0,1],[1,1],[1,2],[2,2]] # 隨層數溫和攀升；精英再 +1
const ELITE_UPS_BONUS := 1
const RELIC_PRICES := [200,400,600]
# Relics use the same passive keys as the 內政 lords (B.MINION_LORDS) and stack with them.
const RELICS := {
	"coin_purse":{"name":"錢袋","price":200,"mods":{"start_ink":10.0}},
	"hourglass":{"name":"沙漏","price":200,"mods":{"cycle_speed":{"*":1.15}}},
	"mid_stakes":{"name":"中路拒馬","price":200,"mods":{"start_buildings":[[2,"mid","barricade"]]}},
	"mason_trowel":{"name":"工匠泥刀","price":200,"mods":{"post_heal":{"gate":0.15,"lord":0.10}}},
	"signet_ring":{"name":"紋章戒","price":200,"mods":{"skill_discount":0.20}},
	"mercenary_ledger":{"name":"傭兵帳冊","price":200,"mods":{"gold_bonus":0.3}},
	"border_horn":{"name":"邊境號角","price":200,"mods":{"start_buildings":[[1,"mid","farm"]],"start_ink":5.0}},
	"iron_rivets":{"name":"鐵鉚釘","price":200,"mods":{"gate_armor":0.2}},
	"artisan_blueprint":{"name":"名匠鍛圖","price":200,"mods":{"targeted_upgrade":true,"upgrade_discount":0.25}},
	"river_sluice":{"name":"護城鑿渠令","price":200,"mods":{"field_mutators":[{"water_cols":[4]}],"start_ink":4.0}},
	"gold_chest":{"name":"藏金箱","price":400,"mods":{"income_mult":1.25}},
	"deft_gloves":{"name":"巧手手套","price":400,"mods":{"cycle_speed":{"*":1.3}}},
	"twin_towers":{"name":"雙哨塔","price":400,"mods":{"start_buildings":[[0,"outer","watchtower"]]}},
	"bounty_pouch":{"name":"獵頭賞袋","price":400,"mods":{"kill_bounty":1.0}},
	"royal_medallion":{"name":"王室勳章","price":400,"mods":{"lord_pct":0.35}},
	"chrono_pendulum":{"name":"時光鐘擺","price":400,"mods":{"skill_charge_mult":1.25,"start_ink":5.0}},
	"spiked_battlement":{"name":"荊棘雉堞","price":400,"mods":{"gate_armor":0.25,"thorns_gate":35.0}},
	"harvest_sickle":{"name":"豐饒金鐮","price":400,"mods":{"farm_mult":1.35,"start_ink":8.0}},
	"trench_engineer":{"name":"前線工兵營","price":400,"mods":{"field_mutators":[{"periodic":{"interval":24.0,"kind":"blast_trap","min_col":2,"max_col":6}}]}},
	"spirit_graveyard":{"name":"英靈喚魂碑","price":400,"mods":{"field_mutators":[{"periodic":{"interval":26.0,"kind":"grave","min_col":1,"max_col":5,"fallback_unit":"skeleton","fallback_count":3}}]}},
	"sky_volley_seal":{"name":"蒼穹箭雨印","price":400,"mods":{"field_mutators":[{"periodic_spell":{"interval":20.0,"kind":"rain"}}]}},
	"war_banner":{"name":"戰旗","price":600,"mods":{"haste":{"*":0.30}}},
	"muster_horn":{"name":"集結號","price":600,"mods":{"swarm":{"*":1}}},
	"holy_grail":{"name":"聖杯","price":600,"mods":{"toughen":{"*":0.35}}},
	"crown_of_valor":{"name":"英靈王冠","price":600,"mods":{"lord_pct":0.70,"skill_discount":0.25}},
	"philosopher_stone":{"name":"賢者之石","price":600,"mods":{"income_mult":1.35,"start_ink":15.0}},
	"imperial_bastion":{"name":"帝國稜堡","price":600,"mods":{"start_buildings":[[1,"outer","tower"],[2,"outer","barricade"]]}},
	"blood_chalice":{"name":"血誓聖爵","price":600,"mods":{"kill_bounty":1.5,"post_heal":{"gate":0.25,"lord":0.20}}},
	"astral_compass":{"name":"星象羅盤","price":600,"mods":{"cycle_speed":{"*":1.25},"skill_charge_mult":1.3}},
	"aegis_obelisk":{"name":"聖盾方尖碑","price":600,"mods":{"field_mutators":[{"periodic_spell":{"interval":22.0,"kind":"arcane_shield"}}]}},
	"fertile_floodplain":{"name":"沃野墾殖詔","price":600,"mods":{"field_mutators":[{"double_home_rows":true}],"farm_mult":1.2}},
	"flint_spark":{"name":"引火燧石","price":200,"mods":{"skill_start_charge":0.3}},
	"soul_lantern":{"name":"拘魂燈","price":200,"mods":{"kill_charge":3.0}},
	"tithe_bowl":{"name":"什一缽","price":200,"mods":{"skill_echo_gold":6.0}},
	"rally_bugle":{"name":"守城軍號","price":200,"mods":{"gate_fall_spell":{"kind":"charge_horn"}}},
	"storm_core":{"name":"風暴晶核","price":400,"mods":{"skill_charge_mult":1.3}},
	"last_ward":{"name":"最後結界","price":400,"mods":{"gate_fall_spell":{"kind":"arcane_shield"},"gate_armor":0.1}},
	"scavenger_hook":{"name":"拾荒鉤","price":400,"mods":{"kill_bounty":0.5,"kill_charge":2.0}},
	"echo_bell":{"name":"迴響戰鐘","price":400,"mods":{"skill_echo_gold":10.0,"skill_start_charge":0.2}},
	"phoenix_ash":{"name":"鳳凰餘燼","price":600,"mods":{"gate_fall_spell":{"kind":"flaming_pitch"},"post_heal":{"gate":0.20,"lord":0.15}}},
	"warlord_seal":{"name":"霸主印璽","price":600,"mods":{"skill_charge_mult":1.5,"skill_start_charge":0.5}},
	"golden_echo":{"name":"金鳴法典","price":600,"mods":{"skill_echo_gold":15.0,"income_mult":1.15}},
	"night_terror":{"name":"夜魘鈴","price":600,"mods":{"gate_fall_spell":{"kind":"dread_howl"},"kill_charge":3.0}},
}
const BOARD_REROLL_PRICE := 25
const SKIP_REWARD_GOLD := 130
const OFFER_REROLL_PRICE := 15
const CONTRACTS := [
	{"name":"標準征途","desc":"標準肉鴿規則：敵方開局 10 金（精英 15 金）。","enemy_ink":0.0,"ai_boost":0,"enemy_toughen":false,"gold_mult":1.0},
	{"name":"強敵壓境","desc":"敵方開局金幣 +8；每戰勝利金幣獎勵 +20%。","enemy_ink":8.0,"ai_boost":0,"enemy_toughen":false,"gold_mult":1.2},
	{"name":"鐵血遠征","desc":"敵方開局金幣 +14、AI 提升一階；戰勝金幣獎勵 +40%。","enemy_ink":14.0,"ai_boost":1,"enemy_toughen":false,"gold_mult":1.4},
	{"name":"絕境王權","desc":"敵方開局金幣 +20、AI 提升一階、敵軍全體生命 +35%；戰勝金幣 +60%。","enemy_ink":20.0,"ai_boost":1,"enemy_toughen":true,"gold_mult":1.6},
]
const EVENTS := {
	"wandering_smith":{
		"name":"流亡宮廷鐵匠","art":"field_smithy",
		"story":"一名帶著皇家烙鐵的流亡鐵匠在路旁架起風箱，聲稱只要給足酒錢或廢鐵，就能把你的兵刃鍛上王城規格。",
		"choices":[
			{"label":"重金精鍛（60 金）","desc":"花費 60 金幣：將牌組中 3 張不同卡牌各升一階（+1）","cost":60,"effect":"upgrade_3"},
			{"label":"拆解舊甲","desc":"獲得 110 金幣，並將牌組隨機 1 張卡牌升一階（+1）","cost":0,"effect":"gold_and_up"},
			{"label":"修補城防","desc":"免費修復所有城牆 35% 缺失血量，領主回復 30% 生命","cost":0,"effect":"mend_both"},
		]
	},
	"mercenary_tavern":{
		"name":"十字路傭兵酒館","art":"twin_gambler",
		"story":"喧鬧的驛站酒館裡坐滿了各國潰兵與賞金獵人。桌上的羊皮懸賞令寫著周遭敵將的人頭價碼。",
		"choices":[
			{"label":"張貼重賞（全盤加賞）","desc":"獲得 70 金幣；場上其餘戰鬥選項全部附加「懸賞 +120 金」","cost":0,"effect":"board_bounty"},
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
			{"label":"吹響強襲號（全盤升階）","desc":"將場上所有「一般戰鬥」升階為「精英討伐（附 +100 懸賞金）」，並得 80 金","cost":0,"effect":"board_all_elite"},
			{"label":"改道奇襲（全盤重洗）","desc":"刷新全部 4 個遭遇選項，並為所有新戰鬥附加 +90 懸賞金","cost":0,"effect":"board_reroll_plus"},
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
			{"label":"臨摹主力（40 金）","desc":"花費 40 金幣：將牌組最高費的可強化主力連升兩階（+2）","cost":40,"effect":"focus_up_2"},
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
			{"label":"點石成金（全盤化戰）","desc":"獲得 90 金幣；場上其餘非戰鬥格全部轉為附 +150 懸賞金的遭遇戰","cost":0,"effect":"transmute_bounty"},
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
			{"label":"立下軍令狀（懸賞翻倍）","desc":"獲得 80 金幣；場上所有戰鬥格懸賞金翻倍（最低 +120 金）","cost":0,"effect":"double_bounty"},
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
	"gambler_den":{
		"name":"地窖骰局","art":"twin_gambler",
		"story":"酒館地窖裡一張桌子擲著灌鉛骰子，莊家拍著一只鑲寶石的匣子：「領主大人，敢不敢賭上點血？」",
		"choices":[
			{"label":"孤注一擲","desc":"五五波：贏得 1 件未持有的 600 金遺物；輸了領主損耗 35% 當前生命","cost":0,"effect":"gamble_relic"},
			{"label":"小賭怡情（30 金）","desc":"花費 30 金：五五波贏回 180 金幣，輸了分文不剩","cost":30,"effect":"gamble_gold"},
			{"label":"冷眼旁觀","desc":"順手牽走桌上的賭注：獲得 60 金幣","cost":0,"effect":"walk_away"},
		]
	},
	"quartermaster_pact":{
		"name":"軍需官的密約","art":"supply_depot",
		"story":"敵營的軍需官趁夜溜進你的帳篷，願意出賣情報或替你預支軍費——只是他兩邊都收錢。",
		"choices":[
			{"label":"預支軍費","desc":"獲得 200 金幣；但下一場戰鬥敵方開局金幣 +15","cost":0,"effect":"dark_pact"},
			{"label":"買下佈陣圖（40 金）","desc":"花費 40 金：下一場戰鬥我方開局金幣 +15","cost":40,"effect":"war_chest"},
			{"label":"策反敵營","desc":"下一場戰鬥敵方開局金幣 -10（最低 0），並獲得 40 金幣","cost":0,"effect":"scout_next"},
		]
	},
	"veteran_drill":{
		"name":"老兵操練場","art":"shieldguard",
		"story":"退役百夫長願意替你操練新兵，只是他的操法出了名的狠：不流點血，練不出真本事。",
		"choices":[
			{"label":"地獄操練","desc":"隨機 3 張卡牌各升一階（+1）；領主損耗 20% 當前生命、城牆損耗 10%","cost":0,"effect":"drill"},
			{"label":"穩紮穩打","desc":"隨機 1 張卡牌升一階（+1），領主回復 25% 生命","cost":0,"effect":"steady_drill"},
			{"label":"變賣器械","desc":"獲得 110 金幣","cost":0,"effect":"sell_gear"},
		]
	},
	"plague_village":{
		"name":"染疫的村落","art":"plague",
		"story":"村口掛著黑布，井水泛著腥味。倖存者跪在路旁求你帶他們走，村長卻偷偷指了指地窖裡的稅金。",
		"choices":[
			{"label":"焚村取金","desc":"獲得 170 金幣；疫火延燒，所有城牆損耗 12%","cost":0,"effect":"burn_village"},
			{"label":"救治村民","desc":"恢復領主 45% 最大生命，並獲得 90 金幣","cost":0,"effect":"cleanse_altar"},
			{"label":"收留倖存者","desc":"免費進入選卡獎勵挑選 1 張新卡替換入牌組，並獲得 80 金幣","cost":0,"effect":"free_draft"},
		]
	},
	"hermit_seer":{
		"name":"隱士占星師","art":"astrolabe_surveyor",
		"story":"山頂的隱士轉動星盤，說星象已經寫好你下一場仗的結局——不過星象也收學費。",
		"choices":[
			{"label":"窺探敵勢","desc":"下一場戰鬥敵方開局金幣 -10（最低 0），並獲得 40 金幣","cost":0,"effect":"scout_next"},
			{"label":"星象祝福（40 金）","desc":"花費 40 金：下一場戰鬥我方開局金幣 +15","cost":40,"effect":"war_chest"},
			{"label":"討教陣法（40 金）","desc":"花費 40 金幣：將牌組最高費的可強化主力連升兩階（+2）","cost":40,"effect":"focus_up_2"},
		]
	},
	"bandit_toll":{
		"name":"山賊關卡","art":"bandit",
		"story":"峽谷口橫著一排拒馬，山賊頭子坐在箱子上數著過路費：「留下買路財，或者留下腦袋。」",
		"choices":[
			{"label":"強行突破","desc":"搶下山賊的財箱獲得 140 金幣；領主損耗 15% 當前生命","cost":0,"effect":"bandit_raid"},
			{"label":"收編山賊","desc":"免費進入選卡獎勵挑選 1 張新卡替換入牌組，並獲得 80 金幣","cost":0,"effect":"free_draft"},
			{"label":"繳費通行（40 金）","desc":"花費 40 金：山賊順道帶路，重置本層支援行動次數並修復城牆 20% 缺失血量","cost":40,"effect":"paid_passage"},
		]
	},
	"ruined_chapel":{
		"name":"廢棄禮拜堂","art":"mourning_shroud",
		"story":"斷了頂的禮拜堂仍有燭火，祭壇上供著一只沒人敢碰的聖骸匣。",
		"choices":[
			{"label":"虔誠祈禱","desc":"免費修復所有城牆 35% 缺失血量，領主回復 30% 生命","cost":0,"effect":"mend_both"},
			{"label":"獻上供奉（50 金）","desc":"花費 50 金：免費獲得 1 件未持有的 200～400 金階級遺物","cost":50,"effect":"caravan_relic"},
			{"label":"搜刮燭台","desc":"獲得 130 金幣","cost":0,"effect":"sell_vials"},
		]
	},
	"deserter_engineers":{
		"name":"逃亡工兵隊","art":"renegade_artificer",
		"story":"一隊帶著工具箱的逃兵躲在橋下，他們會築牆、會挖坑，也會替出價最高的人帶路。",
		"choices":[
			{"label":"加固城防（30 金）","desc":"花費 30 金幣：所有城牆回滿血量，且隨機 1 張卡 +1 強化","cost":30,"effect":"full_walls"},
			{"label":"預埋工事","desc":"下一場戰鬥我方開局金幣 +15","cost":0,"effect":"war_chest"},
			{"label":"雇用帶路","desc":"獲得 150 金幣，並重置本層支援行動次數","cost":0,"effect":"reset_march"},
		]
	},
}
# Path choice (2026-11-09): before each of floors 1-7 the player may pick an elite instead, a 小怪
# from the next tier up (tier 3 stays tier 3) opening with more gold, for 1.5x the gold reward.
const ELITE_START_INK := 15.0
const BOSS_START_INK := 20.0
# 魔王沒有固定的全軍加成：每張牌各自隨機強化 +MIN～+MAX 階，屬性也隨機（依存檔種子，開戰前就看得到）。
const BOSS_CARD_UPGRADES_MIN := 3
const BOSS_CARD_UPGRADES_MAX := 5
# 魔王射擊（2026-11-22，使用者：魔王的子彈要有屬性，像投彈手的範圍傷害）：第八層的魔王本人改成遠程，
# 每位一種招牌彈。style：bomb 拋射落地爆炸（radius 範圍內全部受傷）、pierce 貫穿整路、curse 命中炸開並持續毒傷。
# mult 乘在魔王（已升檔的）傷害上；interval、radius、range 都取 B.TIERS 的檔次。
const BOSS_SHOTS := {
	"adventure":{"name":"劍氣波","style":"pierce","mult":1.0,"interval":1.4,"range":413.0,"look":"sword","desc":"貫穿整路的劍氣"},
	"lion":{"name":"獅心火彈","style":"bomb","mult":0.6,"interval":1.9,"radius":100.0,"flight":0.8,"range":472.0,"look":"fire","desc":"拋射落地爆炸，範圍傷害"},
	"iron":{"name":"攻城重弩","style":"pierce","mult":1.0,"interval":1.9,"range":472.0,"look":"iron","desc":"貫穿整路的重弩矢"},
	"harvest":{"name":"麥束炸彈","style":"bomb","mult":0.6,"interval":1.9,"radius":100.0,"flight":0.8,"range":472.0,"look":"harvest","desc":"拋射落地爆炸，範圍傷害"},
	"mage":{"name":"時空彈","style":"bomb","mult":0.7,"interval":1.4,"radius":75.0,"flight":0.6,"range":413.0,"look":"time","desc":"拋射落地爆炸，範圍傷害"},
	"rune":{"name":"符文爆彈","style":"bomb","mult":0.8,"interval":1.9,"radius":100.0,"flight":0.7,"range":472.0,"look":"rune","desc":"拋射落地爆炸，範圍傷害"},
	"underworld":{"name":"瘟疫骨彈","style":"curse","mult":0.7,"interval":1.4,"radius":75.0,"dot":20.0,"dot_interval":1.1,"dot_ticks":4,"range":413.0,"look":"plague","desc":"命中炸開並留下毒傷"},
	"vampire":{"name":"血矛","style":"pierce","mult":1.0,"interval":1.4,"range":413.0,"look":"blood","desc":"貫穿整路的血矛"},
	"beast":{"name":"酸液吐息","style":"curse","mult":0.6,"interval":1.4,"radius":100.0,"dot":26.0,"dot_interval":1.1,"dot_ticks":3,"range":413.0,"look":"acid","desc":"命中炸開並留下毒傷"},
}

# 小怪領主的射擊（使用者：小怪領主也要）：本來就遠程的小怪領主，依代表卡換成帶屬性的彈，威力比魔王低。
# 會爆炸或拋射的卡＝投彈；貫穿的卡＝貫穿；黑暗／魔物陣營（或帶毒的卡）＝毒彈；其餘照舊單發（只換外觀）。
const MINION_BOMB_CARDS := ["fire","rain","flaming_pitch","chain_lightning","time_field","gravity_well","mana_drain","counter_charge","wing_gust","catapult","arcane_tower","chronomancer","prism_mage","sigil_weaver","warp_beacon","funeral_grenadier","dog_cannon","bellbearer","funeral_monk","mourning_maid"]
const MINION_PIERCE_CARDS := ["arcane_archer","long_dragon","orrery_walker","ballista_tower","rolling_boulder"]
const MINION_SHOT_MULT := {"bomb":0.5,"pierce":0.8,"curse":0.5}

static func minion_shot(lord: String) -> Dictionary:
	if not B.is_minion(lord) or not B.lord_is_ranged(lord): return {}
	var card: String = B.MINION_LORDS[lord].card
	var d: Dictionary = B.CARDS.get(card,{})
	var faction: String = d.get("faction","")
	var reach: float = B.lord_attack_range(lord)
	var style := ""
	if card in MINION_PIERCE_CARDS or d.has("pierce_range_multiplier"): style = "pierce"
	elif card in MINION_BOMB_CARDS or bool(d.get("lob",false)): style = "bomb"
	elif faction in ["dark","beast"] or d.has("dot_damage"): style = "curse"
	if style.is_empty(): return {}
	var shot := {"style":style,"mult":MINION_SHOT_MULT[style],"range":reach,"interval":1.9 if style == "bomb" else 1.4}
	match style:
		"bomb":
			var look: String = {"magic":"rune","dark":"bone","beast":"acid"}.get(faction,"fire")
			if card in ["time_field","chronomancer"]: look = "time"
			shot.merge({"name":"%s彈" % B.CARDS[card].name,"radius":75.0,"flight":0.7,"look":look,"desc":"拋射落地爆炸，範圍傷害"})
		"pierce":
			shot.merge({"name":"%s貫射" % B.CARDS[card].name,"look":{"beast":"fire_beam","magic":"sword"}.get(faction,"iron"),"desc":"貫穿整路"})
		_:
			shot.merge({"name":"%s毒彈" % B.CARDS[card].name,"radius":75.0,"dot":20.0,"dot_interval":1.1,"dot_ticks":3,"look":"acid" if faction == "beast" else "plague","desc":"命中炸開並留下毒傷"})
	return shot
const ELITE_GOLD_MULT := 1.5
const REROLL_PRICE := 35 # shop: draw a fresh set of relics
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
	"adventure":{"domestic":{"card":"farmer","passive":{"swarm":{"knight":1},"haste":{"knight":0.30},"kill_bounty":0.5}},"combat":{"card":"knight"}},
	"lion":{"domestic":{"card":"charge_horn","passive":{"haste":{"*":0.25},"skill_charge_mult":1.2}},"combat":{"card":"mob"}},
	"iron":{"domestic":{"card":"watchtower","passive":{"start_buildings":[[1,"inner","barricade"]],"gate_armor":0.2,"skill_start_charge":0.5}},"combat":{"card":"manor_retainer"}},
	"harvest":{"domestic":{"card":"harvest","passive":{"income_mult":1.25,"farm_mult":1.3}},"combat":{"card":"levy"}},
	"mage":{"domestic":{"card":"teleport_trap","passive":{"cycle_speed":{"*":1.25},"lord_pct":0.30,"skill_charge_mult":1.2}},"combat":{"card":"blink_blade"}},
	"rune":{"domestic":{"card":"artificer","passive":{"start_buildings":[[2,"inner1","teleport_trap"],[2,"inner2","blast_trap"]],"start_ink":10.0,"cycle_speed":{"*":1.15}}},"combat":{"card":"summon_trap"}},
	"underworld":{"domestic":{"card":"bonewall","passive":{"start_buildings":[[0,"mid","grave"]],"skill_charge_mult":1.2,"skill_discount":0.15}},"combat":{"card":"ghoul"}},
	"beast":{"domestic":{"card":"bearded_imp","passive":{"toughen":{"*":0.35},"skill_charge_mult":1.2}},"combat":{"card":"thorn_dragon"}},
	"vampire":{"domestic":{"card":"blood_tower","passive":{"lord_pct":0.30,"kill_charge":2.0,"post_heal":{"lord":0.15}}},"combat":{"card":"reaper"}},
}

# Pure same-faction draftable pool (excluding home cards, summon_only and unreleased).
static func faction_pool(lord: String) -> Array:
	var fac: String = B.lord_faction(lord)
	return DeckStore.pool(lord).filter(func(k: String) -> bool: return B.card_faction(k) == fac)

# Deterministic 8-card random same-faction starter deck with signature combat card, balanced shape,
# and guaranteed early-game playability (at least 4 units and 2 low-cost cards).
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
	var sig_card: String = String(LORD_ROLES.get(lord, {}).get("combat", {}).get("card", ""))
	var sig_group := -1
	if not sig_card.is_empty() and sig_card in pool:
		sig_group = B.card_group(sig_card)
		deck.append(sig_card)
		buckets[sig_group].erase(sig_card)
	for group_id: int in [0, 1, 2, 3]:
		var bucket: Array = buckets[group_id]
		var need := mini(int(ratio.get(group_id, 0)) - (1 if group_id == sig_group else 0), bucket.size())
		for _i: int in range(maxi(0, need)):
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
			if deck[i] != sig_card and int(B.CARDS[deck[i]].cost) > 7:
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
	"card_enemy_mana_spring":{"tier":1,"deck":["mana_spring","blink_blade","arcane_golem","rune_sentinel","arcane_archer","militia","militia","arcane_shield"]},
	"card_enemy_chain_lightning":{"tier":2,"deck":["chain_lightning","chain_lightning","chronomancer","arcane_archer","arcane_golem","rune_sentinel","blink_blade","arcane_shield"]},
	"card_enemy_arcane_shield":{"tier":2,"deck":["arcane_shield","arcane_shield","arcane_golem","blink_blade","militia","militia","artificer","hunter"]},
	"card_enemy_time_field":{"tier":2,"deck":["time_field","time_field","arcane_archer","blink_blade","chronomancer","rune_sentinel","shieldguard","hunter"]},
	"card_enemy_charge_horn":{"tier":1,"deck":["charge_horn","charge_horn","ox","ox","mob","shieldguard","knight","drummer"]},
	"card_enemy_levy":{"tier":1,"deck":["levy","levy","militia","militia","hunter","hunter","manor_retainer","watchtower"]},
	"card_enemy_watchtower":{"tier":1,"deck":["watchtower","watchtower","hunter","hunter","net_hunter","net_hunter","militia","militia"]},
	"card_enemy_sacrifice":{"tier":1,"deck":["sacrifice","shroud_arbalist","skeleton","skeleton","skeleton","ghoul","mass_grave","dark_wizard"]},
	"card_enemy_dread_howl":{"tier":2,"deck":["dread_howl","dread_howl","reaper","ghoul","ghoul","skeleton","raven","hunter"]},
	"card_enemy_mass_grave":{"tier":2,"deck":["mass_grave","mass_grave","skeleton","reaper","necromancer","ghoul","dark_wizard","curse"]},
	"card_enemy_manor_retainer":{"tier":1,"deck":["manor_retainer","manor_retainer","manor_retainer","hunter","hunter","watchtower","farmer","levy"]},
	"card_enemy_rolling_boulder":{"tier":2,"deck":["rolling_boulder","rolling_boulder","catapult","catapult","hunter","hunter","knight","shieldguard"]},
	"card_enemy_dark_wizard":{"tier":2,"deck":["dark_wizard","dark_wizard","skeleton","skeleton","skeleton","mass_grave","ghoul","curse"]},
	"card_enemy_summon_trap":{"tier":3,"deck":["summon_trap","summon_trap","arcane_golem","artificer","hunter","hunter","militia","arcane_shield"]},
	"card_enemy_chimera":{"tier":2,"deck":["summon_trap","summon_trap","arcane_golem","artificer","arcane_shield","hunter","hunter","militia"]},
	"card_enemy_blink_blade":{"tier":3,"deck":["blink_blade","blink_blade","blink_blade","phase_rider","arcane_shield","hunter","hunter","time_field"]},
	"card_enemy_arcane_archer":{"tier":3,"deck":["arcane_archer","arcane_archer","arcane_archer","shieldguard","shieldguard","time_field","artificer","arcane_golem"]},
	"card_enemy_artificer":{"tier":1,"deck":["artificer","rune_sentinel","arcane_golem","arcane_golem","arcane_tower","arcane_shield","arcane_archer","hunter"]},
	"card_enemy_crystal":{"tier":1,"deck":["artificer","rune_sentinel","arcane_golem","mana_spring","blink_blade","arcane_archer","militia","militia"]},
	"card_enemy_teleport_trap":{"tier":2,"deck":["teleport_trap","teleport_trap","blink_blade","arcane_archer","hunter","hunter","arcane_golem","time_field"]},
	"card_enemy_arcane_tower":{"tier":3,"deck":["arcane_tower","arcane_tower","artificer","arcane_archer","arcane_golem","blink_blade","hunter","chain_lightning"]},
	"card_enemy_eyewing_dragon":{"tier":3,"deck":["eyewing_dragon","eyewing_dragon","eyewing_dragon","fishbeak","fishbeak","hooknose_flyer","dread_howl","belly_eye"]},
	"card_enemy_belly_eye":{"tier":3,"deck":["belly_eye","belly_eye","belly_eye","net_hunter","net_hunter","hunter","hunter","fishbeak"]},
	"card_enemy_hooknose_flyer":{"tier":3,"deck":["hooknose_flyer","hooknose_flyer","hooknose_flyer","raven","raven","fishbeak","militia","rain"]},
	"card_enemy_long_dragon":{"tier":3,"deck":["long_dragon","long_dragon","fishbeak","belly_eye","belly_eye","fishbeak","chronomancer","time_field"]},
	"card_enemy_barricade":{"tier":1,"deck":["barricade","barricade","hunter","hunter","hunter","militia","militia","net_hunter"]},
	"card_enemy_corpse_giant":{"tier":2,"deck":["corpse_giant","corpse_giant","necromancer","skeleton","skeleton","ghoul","blood_tower","plague"]},
	"card_enemy_curse":{"tier":2,"deck":["curse","ghoul","dark_wizard","dark_wizard","skeleton","skeleton","reaper","plague"]},
	"card_enemy_grave":{"tier":2,"deck":["skeleton","skeleton","reaper","necromancer","ghoul","ghoul","mass_grave","curse"]},
	"card_enemy_reaper":{"tier":3,"deck":["reaper","reaper","reaper","skeleton","skeleton","ghoul","dread_howl","plague"]},
	"card_enemy_plague":{"tier":2,"deck":["plague","plague","corpse_giant","skeleton","skeleton","ghoul","ghoul","reaper"]},
	"card_enemy_bonewall":{"tier":1,"deck":["bonewall","bonewall","necromancer","necromancer","skeleton","skeleton","hunter","curse"]},
	"card_enemy_farmer":{"tier":1,"deck":["farmer","farmer","militia","militia","shieldguard","hunter","hunter","ox"]},
	"card_enemy_harvest":{"tier":1,"deck":["harvest","farmer","farmer","militia","militia","hunter","ox","knight"]},
	"card_enemy_scarecrow":{"tier":1,"deck":["scarecrow","ox","farmer","shieldguard","hunter","hunter","militia","militia"]},
	"card_enemy_spearbow":{"tier":2,"deck":["spearbow","spearbow","spearbow","drummer","healer","hunter","militia","levy"]},
	"card_enemy_farm":{"tier":1,"deck":["farmer","militia","militia","militia","hunter","hunter","spearbow","scarecrow"]},
	"card_enemy_rain":{"tier":1,"deck":["rain","rain","hunter","hunter","spearbow","shieldguard","militia","watchtower"]},
	"card_enemy_fire":{"tier":3,"deck":["fire","fire","bandit","bandit","raven","raven","shieldguard","hunter"]},
	"card_enemy_guard":{"tier":3,"deck":["guard","guard","spearbow","knight","healer","shieldguard","hunter","charge_horn"]},
	"card_enemy_mill":{"tier":2,"deck":["mill","mill","farmer","farmer","ox","militia","hunter","spearbow"]},
	"mob_foreman":{"tier":2,"deck":["mob","mob","mob","militia","militia","hunter","hunter","drummer"]},
	"net_poacher":{"tier":1,"deck":["net_hunter","net_hunter","net_hunter","hunter","bandit","bandit","militia","barricade"]},
	"field_prior":{"tier":1,"deck":["healer","healer","militia","militia","militia","shieldguard","shieldguard","hunter"]},
	"axe_raider":{"tier":3,"deck":["axe_thrower","axe_thrower","axe_thrower","shieldguard","shieldguard","bandit","drummer","rain"]},
	"phase_stalker":{"tier":3,"deck":["phase_rider","phase_rider","phase_rider","blink_blade","bandit","bandit","arcane_shield","time_field"]},
	"ghoul_feaster":{"tier":2,"deck":["ghoul","ghoul","ghoul","skeleton","skeleton","skeleton","mass_grave","plague"]},
	"blood_prior":{"tier":2,"deck":["blood_tower","ghoul","ghoul","dark_wizard","blood_attendant","skeleton","reaper","corpse_giant"]},
	"clock_warden":{"tier":3,"deck":["chronomancer","chronomancer","chronomancer","arcane_archer","arcane_golem","time_field","teleport_trap","arcane_shield"]},
	"ram_marshal":{"tier":3,"deck":["ram","ram","ram","shieldguard","shieldguard","healer","net_hunter","charge_horn"]},
	"bandit_chief":{"tier":1,"deck":["bandit","bandit","bandit","bandit","militia","militia","hunter","hunter"]},
	"militia_captain":{"tier":2,"deck":["militia","militia","militia","militia","militia","hunter","hunter","rain"]},
	"hunter_master":{"tier":2,"deck":["hunter","hunter","hunter","hunter","militia","militia","barricade","barricade"]},
	"card_enemy_archer":{"tier":2,"deck":["archer","archer","archer","militia","militia","shieldguard","barricade","farmer"]},
	"raven_mother":{"tier":3,"deck":["raven","raven","raven","bandit","bandit","bandit","skeleton","skeleton"]},
	"card_enemy_pouch_beast":{"tier":3,"deck":["pouch_beast","pouch_beast","pouch_beast","fishbeak","fishbeak","bearded_imp","net_hunter","monster_hatchery"]},
	"fishbeak_boss":{"tier":3,"deck":["fishbeak","fishbeak","fishbeak","fishbeak","bearded_imp","bearded_imp","militia","militia"]},
	"ox_herder":{"tier":2,"deck":["ox","ox","ox","farmer","farmer","militia","militia","militia"]},
	"shield_sergeant":{"tier":2,"deck":["shieldguard","shieldguard","shieldguard","knight","hunter","hunter","spearbow","drummer"]},
	"drummer_major":{"tier":3,"deck":["drummer","drummer","mob","mob","militia","militia","bandit","bandit"]},
	"skeleton_king":{"tier":3,"deck":["skeleton","skeleton","skeleton","skeleton","ghoul","ghoul","bonewall","plague"]},
	"trap_weaver":{"tier":1,"deck":["blast_trap","blast_trap","teleport_trap","teleport_trap","hunter","hunter","militia","militia"]},
	"imp_thief":{"tier":3,"deck":["bearded_imp","bearded_imp","bearded_imp","bearded_imp","hooknose_flyer","hooknose_flyer","barricade","barricade"]},
	"knight_commander":{"tier":3,"deck":["knight","knight","knight","healer","spearbow","shieldguard","shieldguard","hunter"]},
	"tower_warden":{"tier":2,"deck":["hunter","hunter","arquebusier","tower","barricade","knight","shieldguard","militia"]},
	"necro_adept":{"tier":1,"deck":["necromancer","necromancer","skeleton","skeleton","skeleton","bonewall","curse","ghoul"]},
	"golem_smith":{"tier":2,"deck":["arcane_golem","arcane_golem","artificer","artificer","arcane_shield","arcane_shield","militia","militia"]},
	"catapult_engineer":{"tier":2,"deck":["catapult","catapult","shieldguard","shieldguard","shieldguard","barricade","hunter","spearbow"]},
	"dragon_lord":{"tier":3,"deck":["thorn_dragon","thorn_dragon","eyewing_dragon","eyewing_dragon","belly_eye","belly_eye","long_dragon","long_dragon"]},
	"card_enemy_mule_cart":{"tier":3,"deck":["mule_cart","mule_cart","manor_retainer","halberdier","hunter","healer","watchtower","rain"]},
	"card_enemy_hook_collector":{"tier":3,"deck":["hook_collector","hook_collector","charge_horn","ox","militia","arquebusier","rain","drummer"]},
	"card_enemy_twin_gambler":{"tier":3,"deck":["twin_gambler","twin_gambler","drummer","healer","shieldguard","hunter","counter_charge","rain"]},
	"card_enemy_seal_altar":{"tier":1,"deck":["seal_altar","skeleton","skeleton","sacrifice","mass_grave","ghoul","necromancer","bellbearer"]},
	"card_enemy_plague_bishop":{"tier":3,"deck":["seal_altar","plague","plague","skeleton","mourning_maid","bellbearer","funeral_cottage","ossuary"]},
	"card_enemy_funeral_monk":{"tier":1,"deck":["seal_altar","bellbearer","ghoul","mourning_maid","pallbearer","skeleton","raven","sealed_coffin"]},
	"card_enemy_gold_monster":{"tier":3,"deck":["gold_monster","gold_monster","farmer","shieldguard","hunter","harvest","rain","drummer"]},
	"card_enemy_spell_tide_magus":{"tier":3,"deck":["spell_tide_magus","spell_tide_magus","arcane_shield","phase_shift","gravity_well","time_field","rune_sentinel","chain_lightning"]},
	"card_enemy_thorn_mother":{"tier":3,"deck":["thorn_mother","thorn_mother","thorn_hound","thorn_hound","bramble_wall","pouch_beast","halberdier","thorn_dragon"]},
	"card_enemy_gatebreaker":{"tier":2,"deck":["gatebreaker","gatebreaker","militia","healer","shieldguard","hunter","ox","rain"]},
	"card_enemy_disgraced_lancer":{"tier":2,"deck":["disgraced_lancer","disgraced_lancer","charge_horn","ox","manor_retainer","hunter","healer","counter_charge"]},
	"card_enemy_runaway_thrall":{"tier":1,"deck":["runaway_thrall","runaway_thrall","bandit","ox","militia","hunter","fire","rain"]},
	"card_enemy_renegade_artificer":{"tier":2,"deck":["renegade_artificer","renegade_artificer","shieldguard","healer","net_hunter","hunter","tower","rain"]},
	"card_enemy_oathless_imp":{"tier":3,"deck":["oathless_imp","oathless_imp","healer","drummer","militia","net_hunter","spearbow","rain"]},
	"card_enemy_assassin":{"tier":2,"deck":["assassin","assassin","bandit","ox","militia","hunter","charge_horn","fire"]},
	"card_enemy_vampire_hunter":{"tier":3,"deck":["vampire_hunter","vampire_hunter","shieldguard","militia","net_hunter","healer","barricade","rain"]},
	"card_enemy_monster_hunter":{"tier":3,"deck":["monster_hunter","monster_hunter","halberdier","shieldguard","hunter","healer","net_hunter","rain"]},
	"card_enemy_spellbreaker":{"tier":2,"deck":["spellbreaker","spellbreaker","knight","shieldguard","healer","hunter","barricade","spearbow"]},
	"card_enemy_powder_barrel":{"tier":3,"deck":["powder_barrel","powder_barrel","scarecrow","net_hunter","hunter","militia","barricade","counter_charge"]},
	"card_enemy_pallbearer":{"tier":3,"deck":["pallbearer","pallbearer","skeleton","ossuary","funeral_cottage","shroud_arbalist","ghoul","curse"]},
	"card_enemy_mourning_maid":{"tier":3,"deck":["mourning_maid","mourning_maid","shroud_arbalist","skeleton","bonewall","ghoul","reaper","plague"]},
	"card_enemy_corpse_stitcher":{"tier":2,"deck":["corpse_stitcher","corpse_stitcher","skeleton","pallbearer","borrowed_bones","ghoul","mass_grave","funeral_cottage"]},
	"card_enemy_blood_attendant":{"tier":2,"deck":["blood_attendant","blood_attendant","blood_tower","blood_altar","mourning_shroud","dark_wizard","ghoul","reaper"]},
	"card_enemy_funeral_cottage":{"tier":1,"deck":["funeral_cottage","funeral_cottage","skeleton","borrowed_bones","pallbearer","ghoul","shroud_arbalist","sacrifice"]},
	"card_enemy_sleepless_belfry":{"tier":2,"deck":["sleepless_belfry","sleepless_belfry","blood_attendant","ghoul","reaper","shroud_arbalist","pallbearer","corpse_giant"]},
	"card_enemy_blood_altar":{"tier":2,"deck":["blood_altar","blood_altar","pallbearer","skeleton","blood_attendant","corpse_giant","ghoul","mourning_shroud"]},
	"card_enemy_borrowed_bones":{"tier":1,"deck":["borrowed_bones","borrowed_bones","sacrifice","skeleton","corpse_stitcher","dark_wizard","ghoul","soul_well"]},
	"card_enemy_grave_exchange":{"tier":1,"deck":["grave_exchange","grave_exchange","funeral_cottage","ossuary","skeleton","shroud_arbalist","ghoul","dark_wizard"]},
	"card_enemy_mourning_shroud":{"tier":1,"deck":["mourning_shroud","pallbearer","blood_attendant","reaper","ghoul","shroud_arbalist","skeleton","sealed_coffin"]},
	"card_enemy_sealed_coffin":{"tier":1,"deck":["sealed_coffin","sealed_coffin","shroud_arbalist","dog_cannon","funeral_grenadier","skeleton","ghoul","reaper"]},
	"card_enemy_arquebusier":{"tier":3,"deck":["arquebusier","arquebusier","shieldguard","manor_retainer","field_smithy","healer","net_hunter","barricade"]},
	"card_enemy_funeral_grenadier":{"tier":3,"deck":["funeral_grenadier","funeral_grenadier","bonewall","sleepless_belfry","skeleton","ghoul","sealed_coffin","plague"]},
	"card_enemy_dog_cannon":{"tier":2,"deck":["dog_cannon","dog_cannon","skeleton","pallbearer","raven","reaper","dread_howl","soul_well"]},
	"card_enemy_orrery_walker":{"tier":3,"deck":["orrery_walker","orrery_walker","observatory","arcane_golem","arcane_shield","artificer","chronomancer","time_field"]},
	"card_enemy_seal_bearer":{"tier":2,"deck":["seal_bearer","seal_bearer","arcane_golem","sigil_weaver","chronomancer","arcane_shield","blast_trap","artificer"]},
	"card_enemy_imp_bomb_runner":{"tier":3,"deck":["imp_bomb_runner","imp_bomb_runner","pack_ambush","fishbeak","pouch_beast","bearded_imp","hooknose_flyer","corrosive_bile"]},
	"card_enemy_macebreaker":{"tier":3,"deck":["macebreaker","macebreaker","healer","drummer","shieldguard","hunter","ox","counter_charge"]},
	"card_enemy_beekeeper":{"tier":3,"deck":["beekeeper","beekeeper","net_hunter","shieldguard","healer","militia","scarecrow","barricade"]},
	"card_enemy_bellbearer":{"tier":1,"deck":["bellbearer","bellbearer","skeleton","skeleton","pallbearer","ghoul","soul_well","curse"]},
	"card_enemy_shroud_arbalist":{"tier":3,"deck":["shroud_arbalist","shroud_arbalist","bonewall","skeleton","mourning_maid","ghoul","sealed_coffin","plague"]},
	"card_enemy_sigil_weaver":{"tier":2,"deck":["sigil_weaver","sigil_weaver","prism_mage","arcane_golem","arcane_shield","chronomancer","rune_sentinel","mana_drain"]},
	"card_enemy_astrolabe_surveyor":{"tier":3,"deck":["astrolabe_surveyor","astrolabe_surveyor","observatory","arcane_archer","arcane_golem","chronomancer","teleport_trap","arcane_shield"]},
	"card_enemy_bog_troll":{"tier":3,"deck":["bog_troll","bog_troll","pouch_beast","blood_cauldron","web_spinner","pack_ambush","fishbeak","corrosive_bile"]},
	"card_enemy_tusk_boar":{"tier":2,"deck":["tusk_boar","tusk_boar","pack_ambush","war_lodge","pouch_beast","fishbeak","web_spinner","wing_gust"]},
	"card_enemy_granary":{"tier":1,"deck":["granary","militia","farmer","harvest","ox","shieldguard","hunter","barricade"]},
	"card_enemy_field_smithy":{"tier":1,"deck":["field_smithy","field_smithy","militia","manor_retainer","halberdier","arquebusier","healer","hunter"]},
	"card_enemy_ossuary":{"tier":2,"deck":["ossuary","ossuary","corpse_stitcher","ghoul","necromancer","dark_wizard","sacrifice","funeral_cottage"]},
	"card_enemy_soul_well":{"tier":1,"deck":["soul_well","soul_well","blood_attendant","reaper","ghoul","shroud_arbalist","skeleton","dread_howl"]},
	"card_enemy_observatory":{"tier":2,"deck":["observatory","observatory","arcane_archer","astrolabe_surveyor","prism_mage","orrery_walker","arcane_golem","time_field"]},
	"card_enemy_rune_workshop":{"tier":2,"deck":["rune_workshop","rune_workshop","arcane_tower","warp_beacon","rune_sentinel","arcane_golem","arcane_archer","chain_lightning"]},
	"card_enemy_monster_hatchery":{"tier":3,"deck":["monster_hatchery","monster_hatchery","pouch_beast","pack_ambush","berserk_blood","web_spinner","fishbeak","feral_mutation"]},
	"card_enemy_war_lodge":{"tier":1,"deck":["war_lodge","fishbeak","tusk_boar","bog_troll","thorn_hound","web_spinner","pouch_beast","corrosive_bile"]},
	"card_enemy_old_witch":{"tier":3,"deck":["old_witch","old_witch","shieldguard","net_hunter","barricade","healer","militia","rain"]},
	"card_enemy_halberdier":{"tier":3,"deck":["halberdier","halberdier","field_smithy","shieldguard","hunter","healer","barricade","counter_charge"]},
	"card_enemy_ballista_tower":{"tier":3,"deck":["ballista_tower","ballista_tower","barricade","shieldguard","manor_retainer","net_hunter","healer","rain"]},
	"card_enemy_recruit_camp":{"tier":1,"deck":["recruit_camp","recruit_camp","militia","farmer","hunter","shieldguard","barricade","rain"]},
	"card_enemy_supply_depot":{"tier":1,"deck":["supply_depot","supply_depot","militia","bandit","ox","halberdier","hunter","charge_horn"]},
	"card_enemy_counter_charge":{"tier":1,"deck":["counter_charge","counter_charge","knight","halberdier","arquebusier","healer","ox","barricade"]},
	"card_enemy_flaming_pitch":{"tier":1,"deck":["flaming_pitch","flaming_pitch","scarecrow","shieldguard","net_hunter","hunter","barricade","militia"]},
	"card_enemy_rune_sentinel":{"tier":2,"deck":["rune_sentinel","rune_sentinel","arcane_shield","chronomancer","prism_mage","sigil_weaver","mana_spring","arcane_tower"]},
	"card_enemy_ward_guard":{"tier":2,"deck":["ward_phalanx","spell_tide_magus","rune_sentinel","arcane_shield","prism_mage","sigil_weaver","mana_spring","arcane_tower"]},
	"card_enemy_ward_phalanx":{"tier":3,"deck":["ward_phalanx","ward_phalanx","arcane_archer","seal_bearer","arcane_shield","time_field","chronomancer","artificer"]},
	"card_enemy_prism_mage":{"tier":3,"deck":["prism_mage","prism_mage","observatory","arcane_golem","arcane_shield","time_field","chronomancer","artificer"]},
	"card_enemy_aether_hound":{"tier":3,"deck":["aether_hound","aether_hound","arcane_shield","phase_shift","blink_blade","chronomancer","prism_mage","time_field"]},
	"card_enemy_spell_mirror":{"tier":3,"deck":["spell_mirror","spell_mirror","chain_lightning","gravity_well","time_field","mana_battery","arcane_golem","arcane_archer"]},
	"card_enemy_mana_battery":{"tier":3,"deck":["mana_battery","mana_battery","chain_lightning","arcane_shield","rune_sentinel","arcane_archer","arcane_golem","prism_mage"]},
	"card_enemy_warp_beacon":{"tier":3,"deck":["warp_beacon","warp_beacon","arcane_archer","prism_mage","astrolabe_surveyor","chronomancer","arcane_golem","time_field"]},
	"card_enemy_mana_drain":{"tier":1,"deck":["mana_drain","mana_drain","gravity_well","chronomancer","arcane_golem","arcane_archer","arcane_shield","prism_mage"]},
	"card_enemy_phase_shift":{"tier":2,"deck":["phase_shift","phase_shift","blink_blade","phase_rider","aether_hound","arcane_shield","chronomancer","time_field"]},
	"card_enemy_gravity_well":{"tier":2,"deck":["gravity_well","gravity_well","chain_lightning","rolling_boulder","chronomancer","prism_mage","arcane_golem","arcane_tower"]},
	"card_enemy_mirror_clone":{"tier":1,"deck":["mirror_clone","blink_blade","arcane_golem","phase_rider","aether_hound","arcane_shield","rune_sentinel","chronomancer"]},
	"card_enemy_parasite_mite":{"tier":2,"deck":["parasite_mite","parasite_mite","swarm_eruption","feral_mutation","pack_ambush","pouch_beast","web_spinner","fishbeak"]},
	"card_enemy_thorn_hound":{"tier":3,"deck":["thorn_hound","thorn_hound","blood_cauldron","berserk_blood","pouch_beast","web_spinner","tusk_boar","pack_ambush"]},
	"card_enemy_web_spinner":{"tier":3,"deck":["web_spinner","web_spinner","tusk_boar","bog_troll","long_dragon","corrosive_bile","war_lodge","pouch_beast"]},
	"card_enemy_sky_scavenger":{"tier":3,"deck":["sky_scavenger","sky_scavenger","hooknose_flyer","eyewing_dragon","imp_bomb_runner","fishbeak","corrosive_bile","wing_gust"]},
	"card_enemy_dire_hydra":{"tier":3,"deck":["dire_hydra","dire_hydra","war_lodge","blood_cauldron","web_spinner","pouch_beast","corrosive_bile","pack_ambush"]},
	"card_enemy_mimic_egg":{"tier":3,"deck":["mimic_egg","mimic_egg","pouch_beast","pack_ambush","feral_mutation","web_spinner","fishbeak","corrosive_bile"]},
	"card_enemy_bramble_wall":{"tier":1,"deck":["bramble_wall","bramble_wall","thorn_hound","thorn_dragon","long_dragon","web_spinner","blood_cauldron","leech_vine"]},
	"card_enemy_blood_cauldron":{"tier":1,"deck":["blood_cauldron","blood_cauldron","tusk_boar","dire_hydra","pouch_beast","thorn_hound","web_spinner","pack_ambush"]},
	"card_enemy_hive_nest":{"tier":3,"deck":["hive_nest","hive_nest","hooknose_flyer","sky_scavenger","eyewing_dragon","wing_gust","belly_eye","bearded_imp"]},
	"card_enemy_leech_vine":{"tier":3,"deck":["leech_vine","leech_vine","bramble_wall","pouch_beast","web_spinner","long_dragon","blood_cauldron","corrosive_bile"]},
	"card_enemy_imp_burrow":{"tier":3,"deck":["imp_burrow","imp_burrow","bearded_imp","fishbeak","bearded_imp","pack_ambush","wing_gust","pouch_beast"]},
	"card_enemy_berserk_blood":{"tier":2,"deck":["berserk_blood","berserk_blood","pouch_beast","bog_troll","blood_cauldron","thorn_hound","tusk_boar","web_spinner"]},
	"card_enemy_corrosive_bile":{"tier":3,"deck":["corrosive_bile","corrosive_bile","fishbeak","tusk_boar","hooknose_flyer","imp_bomb_runner","pouch_beast","web_spinner"]},
	"card_enemy_pack_ambush":{"tier":2,"deck":["pack_ambush","pack_ambush","tusk_boar","pouch_beast","bog_troll","fishbeak","thorn_hound","war_lodge"]},
	"card_enemy_devouring_maw":{"tier":2,"deck":["devouring_maw","devouring_maw","fishbeak","tusk_boar","web_spinner","pouch_beast","bog_troll","corrosive_bile"]},
	"card_enemy_wing_gust":{"tier":3,"deck":["wing_gust","wing_gust","long_dragon","web_spinner","hooknose_flyer","sky_scavenger","hive_nest","pouch_beast"]},
	"card_enemy_feral_mutation":{"tier":2,"deck":["feral_mutation","feral_mutation","parasite_mite","pouch_beast","thorn_hound","bearded_imp","blood_cauldron","pack_ambush"]},
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
		var choices: Array = MINIONS.keys().filter(func(k: String) -> bool: return MINIONS[k].get("enabled",true) and MINIONS[k].tier == tier and not k in result and not Terrain.is_elite(k))
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
		var choices: Array = MINIONS.keys().filter(func(k: String) -> bool: return MINIONS[k].get("enabled",true) and MINIONS[k].tier == elite_tier(i) and not k in foes and not k in result and Terrain.is_elite(k))
		if choices.is_empty(): choices = MINIONS.keys().filter(func(k: String) -> bool: return MINIONS[k].get("enabled",true) and MINIONS[k].tier == elite_tier(i) and not k in foes and not k in result)
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
	var fac: String = B.lord_faction(lord)
	var result: Array = []
	var groups: Array = []
	# Prefer unseen cards, then unrepresented roles; at least 1 card leans own-faction when available.
	while result.size() < OFFER_SIZE and not pool.is_empty():
		var fresh: Array = pool.filter(func(k: String) -> bool: return not k in deck)
		var candidates: Array = fresh if not fresh.is_empty() else pool
		if result.is_empty():
			var fac_cands: Array = candidates.filter(func(k: String) -> bool: return B.card_faction(k) == fac)
			if not fac_cands.is_empty(): candidates = fac_cands
		var diverse: Array = candidates.filter(func(k: String) -> bool: return not B.card_group(k) in groups)
		if not diverse.is_empty(): candidates = diverse
		var chosen: String = candidates[rng.randi_range(0,candidates.size()-1)]
		result.append(chosen)
		groups.append(B.card_group(chosen))
		pool.erase(chosen)
	return result

static func gold_for(floor_index: int) -> int:
	return GOLD_BY_FLOOR[floor_index] if floor_index < GOLD_BY_FLOOR.size() else 0

# [低, 高] card upgrade range the enemy's cards roll in on this floor.
static func enemy_ups_range(floor_index: int, kind: String) -> Array:
	if kind == "boss": return [BOSS_CARD_UPGRADES_MIN,BOSS_CARD_UPGRADES_MAX]
	var r: Array = ENEMY_UPS_BY_FLOOR[clampi(floor_index,0,ENEMY_UPS_BY_FLOOR.size()-1)]
	var bonus := ELITE_UPS_BONUS if kind == "elite" else 0
	return [int(r[0])+bonus,int(r[1])+bonus]

static func enemy_floor_scale(floor_index: int) -> float:
	var t := clampf(float(floor_index)/float(maxi(1,FLOORS-1)),0.0,1.0)
	return 1.0 + pow(t, 1.6)

# One relic of each price the run does not own yet, fixed by seed and floor.
static func relic_offer(seed_value: int, floor_index: int, owned: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*53+floor_index*389
	var result: Array = []
	for price: int in RELIC_PRICES:
		var choices: Array = RELICS.keys().filter(func(k: String) -> bool: return RELICS[k].price == price and not k in owned)
		choices.sort()
		if not choices.is_empty(): result.append(choices[rng.randi_range(0,choices.size()-1)])
	while result.size() < RELIC_PRICES.size():
		var extra: Array = RELICS.keys().filter(func(k: String) -> bool: return not k in owned and not k in result)
		extra.sort()
		if extra.is_empty(): break
		result.append(extra[rng.randi_range(0,extra.size()-1)])
	return result

static func _norm_pct_map(val: Variant, fallback: float) -> Dictionary:
	var out: Dictionary = {}
	if val is Dictionary:
		for k: String in val: out[k] = float(val[k])
	elif val is Array:
		for k in val: out[String(k)] = float(out.get(String(k),0.0))+fallback
	return out

# Stack passive rule sets additively: percentage bonuses add on top of base 1.0.
static func merge_mods(base: Dictionary, extra: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for key: String in extra:
		var value = extra[key]
		if not result.has(key):
			if key in ["toughen","haste"]: result[key] = _norm_pct_map(value,B.TOUGHEN_PCT if key == "toughen" else B.HASTE_PCT)
			else: result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
		elif key.ends_with("_mult") or key == "skill_haste": result[key] = maxf(0.1,float(result[key])+(float(value)-1.0))
		elif key == "skill_discount": result[key] = minf(0.6,float(result[key])+float(value))
		elif key in ["start_ink","lord_boost","lord_pct","thorns_gate","kill_bounty","gold_bonus","skill_echo_gold","kill_charge"]: result[key] += value
		elif key == "skill_start_charge": result[key] = minf(1.0,result[key]+value)
		elif key == "gate_armor": result[key] = minf(0.6,result[key]+value)
		elif key == "post_heal":
			for k: String in value: result[key][k] = float(result[key].get(k,0.0))+float(value[k])
		elif key == "cycle_speed":
			for k: String in value: result[key][k] = maxf(0.1,float(result[key].get(k,1.0))+(float(value[k])-1.0))
		elif key in ["toughen","haste"]:
			var fb: float = B.TOUGHEN_PCT if key == "toughen" else B.HASTE_PCT
			var dst := _norm_pct_map(result[key],fb)
			var src := _norm_pct_map(value,fb)
			for k: String in src: dst[k] = float(dst.get(k,0.0))+float(src[k])
			result[key] = dst
		elif key == "swarm":
			for k: String in value: result[key][k] = result[key].get(k,0)+value[k]
		elif key == "targeted_upgrade": result[key] = result.get(key,false) or bool(value)
		elif key == "upgrade_discount": result[key] = minf(0.5,float(result.get(key,0.0))+float(value))
		elif key == "start_buildings":
			for b: Array in value:
				if not result[key].any(func(o: Array) -> bool: return o[0] == b[0] and str(o[1]) == str(b[1])): result[key].append(b)
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

# elite: draw from the 精英怪 (rogue_terrain.ELITES) only; otherwise from the ordinary foes only.
static func pick_minion(tier: int, seed_value: int, salt: int, avoid: Array, elite: bool = false) -> String:
	var pool: Array = MINIONS.keys().filter(func(k: String) -> bool: return MINIONS[k].get("enabled",true) and MINIONS[k].tier == tier and not k in avoid and Terrain.is_elite(k) == elite)
	if pool.is_empty(): pool = MINIONS.keys().filter(func(k: String) -> bool: return MINIONS[k].get("enabled",true) and MINIONS[k].tier == tier)
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value*61+salt*313+tier*17
	return pool[rng.randi_range(0,pool.size()-1)]

const BOSS_MUTATORS := {
	"harvest":{"id":"harvest_fields","name":"萬頃良田","desc":"開局前 2 排蓋滿 10 座農田，且魔王農田產出 +50%","double_home_rows":true,"mods":{"farm_mult":1.5}},
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
	"blood_frenzy":{"id":"blood_frenzy","name":"狂暴突襲","desc":"敵軍全體移速與攻速 +25%，且開局金幣額外 +12","mods":{"haste":{"*":0.25}},"extra_ink":12.0},
	"iron_hide":{"id":"iron_hide","name":"鐵皮重甲","desc":"敵軍全體生命 +35%","mods":{"toughen":{"*":0.35}}},
	"arrow_storm":{"id":"arrow_storm","name":"箭雨覆蓋","desc":"每隔 20 秒，敵方朝我軍隨機降下一陣箭雨","periodic_spell":{"interval":20.0,"kind":"rain"}},
	"plague_fog":{"id":"plague_fog","name":"瘟疫瘴氣","desc":"每隔 30 秒，敵方朝我軍隨機散播一團瘟疫","periodic_spell":{"interval":30.0,"kind":"plague"}},
	"tower_line":{"id":"tower_line","name":"箭樓防線","desc":"敵方第 I、III、V 路後排各預築一座箭樓","enemy_buildings":[[1,0,"tower"],[1,2,"tower"],[1,4,"tower"]]},
	"war_chest":{"id":"war_chest","name":"敵軍金庫","desc":"敵方基本產金 +50%，且開局金幣額外 +10","mods":{"income_mult":1.5},"extra_ink":10.0},
	"rapid_muster":{"id":"rapid_muster","name":"急行徵兵","desc":"敵方出牌冷卻速度 +50%","mods":{"cd_speed_mult":1.5}},
	"thorn_bastion":{"id":"thorn_bastion","name":"荊棘堡壘","desc":"敵方城牆減傷 25%，且攻城者每下反受 40 傷害","mods":{"gate_armor":0.25,"thorns_gate":40.0}},
	"vanguard_wave":{"id":"vanguard_wave","name":"先鋒壓境","desc":"開局已有騎士自第 II、IV 路、民兵自第 III 路壓境，且開局金幣額外 +6","enemy_units":[[2,1,"knight"],[2,3,"knight"],[2,2,"militia"]],"extra_ink":6.0},
}

# Light twists for ordinary fights on floors 3-7 (2026-11-19): about 60% of them carry one.
const BATTLE_MUTATORS := {
	"scout_party":{"id":"scout_party","name":"斥候先行","desc":"開局已有兩隊民兵自第 II、IV 路出發","enemy_units":[[3,1,"militia"],[3,3,"militia"]]},
	"lone_tower":{"id":"lone_tower","name":"孤塔哨站","desc":"敵方中路後排預築一座箭樓","enemy_buildings":[[1,2,"tower"]]},
	"fat_purse":{"id":"fat_purse","name":"肥羊錢袋","desc":"敵方開局金幣額外 +8","extra_ink":8.0},
	"quick_hands":{"id":"quick_hands","name":"手腳俐落","desc":"敵方出牌冷卻速度 +25%","mods":{"cd_speed_mult":1.25}},
	"stone_gates":{"id":"stone_gates","name":"石砌城牆","desc":"敵方城牆減傷 15%","mods":{"gate_armor":0.15}},
	"head_hunters":{"id":"head_hunters","name":"人頭懸賞","desc":"敵方每擊殺我方 1 名部隊得 1 金","mods":{"kill_bounty":1.0}},
	"muddy_ford":{"id":"muddy_ford","name":"泥濘渡口","desc":"中央縱列化為水路（無法建築，除飛行單位外緩速 60%）","water_cols":[4]},
	"barricade_line":{"id":"barricade_line","name":"拒馬陣地","desc":"敵方第 II、IV 路前排預築木拒馬","enemy_buildings":[[2,1,"barricade"],[2,3,"barricade"]]},
}
const BATTLE_MUTATOR_FROM_FLOOR := 2 # floor index: floors 3-7
const BATTLE_MUTATOR_CHANCE := 0.6

# Each boss also has a second face (2026-11-19); a run meets one of the two, fixed by its seed.
const BOSS_VARIANTS := {
	"harvest_ii":{"id":"harvest_ii","boss":"harvest","name":"饑荒征糧","desc":"魔王基本產金 +40%、開局金幣 +10，且每 30 秒對自家農田施放一次豐收","mods":{"income_mult":1.4},"extra_ink":10.0,"periodic_spell":{"interval":30.0,"kind":"harvest"}},
	"iron_ii":{"id":"iron_ii","boss":"iron","name":"千塔要塞","desc":"開局五路後排共預築 5 座箭樓，城牆減傷 20%","enemy_buildings":[[1,0,"tower"],[1,2,"tower"],[1,4,"tower"],[2,1,"tower"],[2,3,"tower"]],"mods":{"gate_armor":0.2}},
	"lion_ii":{"id":"lion_ii","boss":"lion","name":"王旗號角","desc":"每 25 秒魔王對自軍吹響一次衝鋒號令，開局金幣 +10","periodic_spell":{"interval":25.0,"kind":"charge_horn"},"extra_ink":10.0},
	"underworld_ii":{"id":"underworld_ii","boss":"underworld","name":"瘟疫墓園","desc":"每 25 秒朝我軍散播一團瘟疫，開局第 II、IV 路先立墓碑","periodic_spell":{"interval":25.0,"kind":"plague"},"enemy_buildings":[[1,1,"grave"],[1,3,"grave"]]},
	"beast_ii":{"id":"beast_ii","boss":"beast","name":"獸潮夜襲","desc":"魔王每張部隊卡多 1 名單位，每 40 秒在後方浮現一座巨獸孵巢","mods":{"swarm":{"*":1}},"periodic":{"interval":40.0,"kind":"monster_hatchery","min_col":6,"max_col":8}},
	"mage_ii":{"id":"mage_ii","boss":"mage","name":"雷霆奧術","desc":"每 20 秒朝我軍降下一道連鎖閃電，開局金幣 +10","periodic_spell":{"interval":20.0,"kind":"chain_lightning"},"extra_ink":10.0},
	"rune_ii":{"id":"rune_ii","boss":"rune","name":"祕法塔陣","desc":"開局後排預築 3 座祕法塔，每 30 秒戰場隨機浮現一座召喚法陣","enemy_buildings":[[1,0,"arcane_tower"],[1,2,"arcane_tower"],[1,4,"arcane_tower"]],"periodic":{"interval":30.0,"kind":"summon_trap","min_col":2,"max_col":6}},
	"vampire_ii":{"id":"vampire_ii","boss":"vampire","name":"血債血償","desc":"魔王每擊殺我方 1 名部隊得 2 金，且每 25 秒朝我軍降下一道詛咒","mods":{"kill_bounty":2.0},"periodic_spell":{"interval":25.0,"kind":"curse"}},
	"adventure_ii":{"id":"adventure_ii","boss":"adventure","name":"冒險者公會","desc":"開局獵戶、騎士與民兵各自三路出發，魔王出牌冷卻速度 +30%、開局金幣 +10","enemy_units":[[2,1,"hunter"],[2,2,"knight"],[2,3,"militia"]],"mods":{"cd_speed_mult":1.3},"extra_ink":10.0},
}
# Every event effect roguelike.gd event_action() handles; validate() catches typos.
const EVENT_EFFECTS := ["upgrade_2","upgrade_3","gold_and_up","mend_both","board_bounty","draft_plus","free_relic_low","blood_relic","wall_gold","cleanse_altar","board_all_elite","board_reroll_plus","tower_rest","caravan_gold","caravan_relic","upgrade_2_free","focus_up_2","board_blessing","sell_book","full_walls","full_lord","guild_gold","free_draft","armory_up","reset_march","transmute_bounty","elixir_up","sell_vials","mirror_upgrade","sanctuary_board","arcane_mend","double_bounty","fortify_up","buy_high_relic","bazaar_gold","gamble_relic","gamble_gold","walk_away","dark_pact","war_chest","scout_next","drill","steady_drill","sell_gear","burn_village","bandit_raid","paid_passage"]

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
		return BOSS_VARIANTS.get(fk,BOSS_MUTATORS.get(fk,{}))
	# 一般戰與精英戰不再有異變（使用者 2026-11-22）；精英改帶固定的精英特性（rogue_terrain.ELITE_TRAITS）。
	return {}

# The boss's face for this run: its classic mutator or its second variant, fixed by the seed.
static func boss_mutator_id(boss: String, seed_val: int) -> String:
	var variant := boss+"_ii"
	if not BOSS_VARIANTS.has(variant): return boss
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val*151+hash(boss)
	return variant if rng.randf() < 0.5 else boss

static func roll_battle_mutator(fl: int, seed_val: int, salt: int) -> String:
	if fl < BATTLE_MUTATOR_FROM_FLOOR: return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val*59+salt*211+fl*7
	if rng.randf() >= BATTLE_MUTATOR_CHANCE: return ""
	var keys: Array = BATTLE_MUTATORS.keys()
	keys.sort()
	return String(keys[rng.randi_range(0,keys.size()-1)])

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
		return {"kind":"boss","foe":b_foe,"mutator":boss_mutator_id(b_foe,seed_val),"event_id":"","bounty":0,"age":0}
	if kind == "sboss": return season_boss_slot(r)
	used_foes.append_array(r.get("fought",[]))
	if kind == "battle":
		var foe: String = pick_minion(FLOOR_TIER[fl],seed_val,draws+salt+fl*11,used_foes)
		return {"kind":"battle","foe":foe,"mutator":"","event_id":"","bounty":0,"age":0}
	if kind == "elite":
		var e_foe: String = pick_minion(elite_tier(fl),seed_val,draws+salt+fl*19,used_foes,true)
		return {"kind":"elite","foe":e_foe,"mutator":"","event_id":"","bounty":0,"age":0}
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
	var board: Array = []
	for i: int in range(4): board.append(draw_replacement_slot(r,i))
	return board

static func boss_board(r: Dictionary) -> Array:
	return [make_slot("boss",r,1),make_slot("camp",r,2),make_slot("shrine",r,3),make_slot("event",r,4)]

# The next flag from the season's pile (the final throne keeps offering the 魔王). Drawing the boss card
# marks the season's boss as out: the caller then turns the whole board over (boss_takes_board).
static func draw_replacement_slot(r: Dictionary, slot_index: int) -> Dictionary:
	r.draws = int(r.get("draws",0))+1
	if int(r.get("floor",0)) >= FLOORS-1:
		return make_slot("boss",r,slot_index+r.draws)
	var pile: Array = r.get("pile",[])
	if pile.is_empty() or bool(r.get("boss_out",false)):
		r.boss_out = true
		return season_boss_slot(r)
	var kind: String = pile.pop_front()
	r.pile = pile
	if kind == "sboss":
		r.boss_out = true
		return season_boss_slot(r)
	return make_slot(kind,r,slot_index+r.draws)

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
		var gfs: Dictionary = RELICS[r].mods.get("gate_fall_spell",{})
		if not gfs.is_empty() and B.CARDS.get(String(gfs.get("kind","")),{}).get("type","") != "spell": problems.append("relic %s gate_fall_spell is not a spell" % r)
		if B.passive_text(RELICS[r].mods).length() < 3: problems.append("relic %s has no effect" % r)
	for price: int in RELIC_PRICES:
		if RELICS.values().filter(func(d: Dictionary) -> bool: return d.price == price).size() < 2: problems.append("fewer than two relics at %d" % price)
	var used_giants := SEASON_BOSSES.values().map(func(d: Dictionary) -> String: return String(d.get("giant","")))
	for card: String in B.CARDS:
		if B.CARDS[card].get("boss_only",false):
			if not card in used_giants: problems.append("unused boss_only card: "+card)
			continue
		var matching: Array = MINIONS.keys().filter(func(k: String) -> bool: return B.MINION_LORDS.has(k) and B.MINION_LORDS[k].card == card)
		if matching.size() != 1: problems.append("card needs exactly one enemy: "+card)
		elif B.CARDS[card].get("unreleased",false) and MINIONS[matching[0]].get("enabled",true): problems.append("unreleased enemy must stay disabled: "+card)
	for ev: String in EVENTS:
		var ed: Dictionary = EVENTS[ev]
		if not B.CARDS.has(ed.get("art","")): problems.append("event %s uses unknown art card" % ev)
		if ed.get("choices",[]).size() != 3: problems.append("event %s must have 3 choices" % ev)
	if CONTRACTS.size() < 4: problems.append("fewer than 4 contracts")
	for table: Dictionary in [BOSS_MUTATORS,BOSS_VARIANTS,ELITE_MUTATORS,BATTLE_MUTATORS]:
		for id: String in table:
			var mut: Dictionary = table[id]
			if String(mut.get("name","")).is_empty() or String(mut.get("desc","")).is_empty(): problems.append("mutator %s needs a name and a description" % id)
			for spec: Array in mut.get("enemy_buildings",[]) + mut.get("enemy_units",[]):
				if not B.CARDS.has(String(spec[2])): problems.append("mutator %s places unknown %s" % [id,str(spec[2])])
			for key: String in ["periodic","periodic_spell"]:
				if mut.has(key) and not B.CARDS.has(String(mut[key].get("kind",""))): problems.append("mutator %s periodic kind is unknown" % id)
	for id: String in BOSS_VARIANTS:
		if not BOSSES.has(String(BOSS_VARIANTS[id].get("boss",""))): problems.append("boss variant %s names no boss" % id)
	for ev: String in EVENTS:
		for choice: Dictionary in EVENTS[ev].choices:
			if not String(choice.get("effect","")) in EVENT_EFFECTS: problems.append("event %s uses unhandled effect %s" % [ev,str(choice.get("effect",""))])
	for sb: String in SEASON_BOSSES:
		var d: Dictionary = SEASON_BOSSES[sb]
		var gkind := String(d.get("giant",""))
		var sb_deck := season_boss_deck(sb)
		if not MINIONS.has(String(d.base)) or not B.CARDS.has(gkind) or not B.CARDS[gkind].get("giant",false) or not B.CARDS[gkind].get("boss_only",false) or not int(d.season) in range(SEASONS.size()) or sb_deck.size() != 8 or not gkind in sb_deck: problems.append("season boss %s: invalid base, giant or season" % sb)
	for s_i: int in range(SEASONS.size()):
		if not SEASON_BOSSES.values().any(func(d: Dictionary) -> bool: return int(d.season) == s_i): problems.append("no season boss for season %d" % s_i)
	return problems
