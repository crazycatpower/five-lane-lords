extends RefCounted
# 冒險模式＝新手教學（2026-11-21 重新設計）：5 章 × 10 關，第 5、10 關為小考／大考（特殊關）。
# 第一章「新兵訓練」每關一個基本規則，逐步指引在 tutorial_lessons.gd；之後每關教一件事：
#   rule_tag / rule_desc  本關教學（標題／說明）
#   rewards               本關新卡：這一場自動加入出征牌組，過關後永久解鎖
#   new_enemy / enemy_note 本關新敵人：第一次出現時跳出說明；"skill" = 敵方領主技能
#   tip                   對策：新敵人提示與失敗時的提示
# 只用正式對戰也會遇到的狀況（路數、守城倒數、敵方預築、提早入夜），不放水道、順風、古碑這類只在冒險出現的機關。
const B = preload("res://balance.gd")
const DeckStore = preload("res://deck_store.gd")

const STAGES_PER_WORLD := 10
const STARTER_CARDS := ["militia"]
const GOAL := "攻入敵方底線獲勝；敵軍攻入我方底線則失敗。"
const PREMISE := "五域古碑崩裂，強盜趁亂搶到邊境。新立的領主還不會打仗，只好跟著老隊長邊打邊學，一路學到五路決戰。"

const WORLDS := [
	{"id":"meadow","name":"一・晨麥古道","short":"新兵訓練","biome":"meadow","color":Color("7a9442"),"subtitle":"新手教學 · 出兵、金幣、農田、領地、防守、法術、多路與領主"},
	{"id":"river","name":"二・運河渡口","short":"兵種相剋","biome":"river","color":Color("3b758c"),"subtitle":"經典兵種 · 重甲、肉盾、治療、衝鋒、攻城、鼓舞、軍團與偵查"},
	{"id":"spire","name":"三・星軌高塔","short":"魔法陣營","biome":"spire","color":Color("4f5d96"),"subtitle":"魔法陣營 · 水晶、護盾、陷阱、閃現、力場與連鎖閃電"},
	{"id":"marsh","name":"四・冥霧墓澤","short":"黑暗陣營","biome":"marsh","color":Color("6d4f7a"),"subtitle":"黑暗陣營 · 墓碑、骷髏、瘟疫、烏鴉、骨牆與長夜"},
	{"id":"crater","name":"五・巨獸王城","short":"魔物與決戰","biome":"crater","color":Color("a85232"),"subtitle":"魔物陣營 · 吞噬、厚血、反傷、飛行、巨獸，最後攻下王都"},
]
const CHAPTERS := WORLDS

const WORLD_NODES := [
	Vector2(165, 358),
	Vector2(355, 336),
	Vector2(545, 362),
	Vector2(735, 336),
	Vector2(925, 366),
	Vector2(925, 614),
	Vector2(735, 644),
	Vector2(545, 614),
	Vector2(355, 644),
	Vector2(165, 616),
]

const ALL_LANES := [0,1,2,3,4]
const MIDDLE_LANES := [1,2,3]
const ONE_LANE := [2]

const UNLOCK_LORDS := {
	"w1_10":"harvest",
	"w2_10":"lion",
	"w3_5":"rune",
	"w3_10":"mage",
	"w4_5":"underworld",
	"w4_10":"vampire",
	"w5_5":"beast",
	"w5_10":"iron",
}

# 難度（使用者 2026-11-21）：簡單＝敵人經濟 ×0.75、普通＝關卡原設定、困難＝AI 困難、極難＝AI 困難＋敵人多一項被動。
# ai = -1 用關卡自己的 AI 等級；stars = 過關可得的 ★（每關記最高難度）。新存檔預設簡單。
const DIFFICULTIES := [
	{"name":"簡單","stars":1,"ai":-1,"enemy_mods":{"gold_gain_mult":0.75},"desc":"敵人所有收入 ×0.75。第一次玩選這個。"},
	{"name":"普通","stars":2,"ai":-1,"enemy_mods":{},"desc":"照關卡原本的設定。"},
	{"name":"困難","stars":3,"ai":2,"enemy_mods":{},"desc":"敵方 AI 一律困難。"},
	{"name":"極難","stars":4,"ai":2,"enemy_mods":{},"passives":true,"desc":"敵方 AI 困難，而且每關多一項被動效果（大考兩項）。"},
]
const MAX_STARS_PER_STAGE := 4

# 極難的敵方被動：每關依關卡順序輪到一項，大考再加一項；敵方領主沒上場的關卡跳過領主類。
const EXTREME_PASSIVES := [
	{"id":"iron_hide","name":"鐵甲","desc":"敵方全軍生命升一檔","mods":{"toughen":["*"]}},
	{"id":"war_chest","name":"軍餉","desc":"敵方開局金幣 +15","mods":{"start_ink":15.0}},
	{"id":"forced_march","name":"急行軍","desc":"敵方全軍移速與攻速升一檔","mods":{"haste":["*"]}},
	{"id":"stout_walls","name":"堅城","desc":"敵方城牆受到的傷害減少 25%","mods":{"gate_armor":0.25}},
	{"id":"rapid_orders","name":"急令","desc":"敵方手牌冷卻快 30%","mods":{"cd_speed_mult":1.3}},
	{"id":"champion","name":"強將","desc":"敵方領主生命與傷害升一檔","mods":{"lord_boost":1},"lord":true},
	{"id":"rich_soil","name":"沃土","desc":"敵方農田產出 ×1.4","mods":{"farm_mult":1.4}},
	{"id":"bounty","name":"懸賞","desc":"敵方每擊殺一名部隊 +1 金幣","mods":{"kill_bounty":1.0}},
	{"id":"thorn_walls","name":"棘城","desc":"敵方城牆被近身攻擊時反傷 30","mods":{"thorns_gate":30.0}},
	{"id":"heroic_surge","name":"英魂","desc":"敵方領主技能充能 ×1.5","mods":{"skill_charge_mult":1.5},"lord":true},
]

# The extreme passives stage i gives the enemy: one by turn, a second on the chapter exams.
static func extreme_passives(i: int) -> Array:
	var list := stages()
	if i < 0 or i >= list.size(): return []
	var d: Dictionary = list[i]
	var lord_on: bool = bool(d.get("enemy_lord_active",true)) and B.LORDS.has(String(d.get("enemy_lord","")))
	var picks: Array = []
	var want := 2 if bool(d.get("boss",false)) else 1
	var n := EXTREME_PASSIVES.size()
	for step: int in range(n):
		if picks.size() >= want: break
		var p: Dictionary = EXTREME_PASSIVES[(i * 3 + step * 7) % n]
		if bool(p.get("lord",false)) and not lord_on: continue
		if not picks.any(func(q: Dictionary) -> bool: return q.id == p.id): picks.append(p)
	return picks

const DECREES := [
	{"id":"rations","name":"軍糧先遣","stars":3,"desc":"開局金幣 +6","mods":{"start_ink":6.0}},
	{"id":"tillage","name":"豐土深耕","stars":8,"desc":"我方農田產出 ×1.25","mods":{"farm_mult":1.25}},
	{"id":"rampart","name":"厚築城垣","stars":15,"desc":"我方城牆減傷 20%、城牆反傷 20","mods":{"gate_armor":0.2,"thorns_gate":20.0}},
	{"id":"war_drums","name":"戰鼓軍令","stars":24,"desc":"我方手牌冷卻速度 ×1.15","mods":{"cd_speed_mult":1.15}},
	{"id":"heroic_surge","name":"英魂聚能","stars":35,"desc":"我方領主技能充能 ×1.25","mods":{"skill_charge_mult":1.25}},
	{"id":"vanguard","name":"百戰精銳","stars":45,"desc":"我方領主生命與傷害升 1 檔、擊殺賞金 +0.5","mods":{"lord_boost":1,"kill_bounty":0.5}},
]

static func _stage(id: String, code: String, world: int, node_idx: int, name: String, ruler: String, ai: int, enemy_deck: Array, rewards: Array, story: String, rule_tag: String, rule_desc: String, opts: Dictionary = {}) -> Dictionary:
	var prev_id: String = String(opts.get("prev",""))
	var goal_txt: String = "撐過倒數守住城牆，或直接攻破敵方底線皆算獲勝。" if float(opts.get("survive_time",0.0)) > 0.0 else GOAL
	return {
		"id":id,
		"code":code,
		"world":world,
		"chapter":world,
		"name":name,
		"lord":String(opts.get("lord","adventure")),
		"kind":"conquer",
		"ai":ai,
		"enemy_lord":ruler,
		"story":story,
		"goal":goal_txt,
		"rule_tag":rule_tag,
		"rule_desc":rule_desc,
		"tip":String(opts.get("tip","")),
		"new_enemy":String(opts.get("new_enemy","")),
		"enemy_note":String(opts.get("enemy_note","")),
		"card_note":String(opts.get("card_note","")),
		"deck_lesson":bool(opts.get("deck_lesson",false)),
		"camp":bool(opts.get("camp",false)), # the enemy base is a bandit camp (camp_art.gd), not a castle
		"biome":WORLDS[world].biome,
		"deck":opts.get("deck","player"),
		"allow_duplicates":bool(opts.get("allow_duplicates",opts.get("deck","player") is Array)),
		"conveyor":opts.get("conveyor",{}),
		"enemy_deck":enemy_deck,
		"rows":int(opts.get("rows",5)), # field rows: 5, or 6 for a six-lane stage
		"active_lanes":opts.get("active_lanes",ALL_LANES),
		"buildings":opts.get("buildings",[]),
		"mutators":opts.get("mutators",[]),
		"both_mods":opts.get("both_mods",{}),
		"enemy_mods":opts.get("enemy_mods",{}),
		"survive_time":float(opts.get("survive_time",0.0)),
		"night_start_override":float(opts.get("night_start_override",-1.0)),
		"night_decay":bool(opts.get("night_decay",true)),
		"map":WORLD_NODES[node_idx],
		"links":[] if prev_id.is_empty() else [prev_id],
		"rewards":rewards,
		"enemy_lord_active":bool(opts.get("enemy_lord_active",true)),
		"enemy_camp":bool(opts.get("enemy_camp",false)),
		"opening":false,
		"dialogue":true,
		"special":node_idx == 4 or node_idx == 9,
		"boss":node_idx == 9,
		"capital":node_idx == 9,
	}

# First-chapter lessons share these: a fixed hand, no enemy lord, no nightfall.
static func _lesson(extra: Dictionary) -> Dictionary:
	var o := {"enemy_lord_active":false,"night_decay":false,"active_lanes":ONE_LANE}
	o.merge(extra,true)
	return o

static var cache: Array = []
static func stages() -> Array:
	if not cache.is_empty(): return cache
	cache = build_stages()
	for d: Dictionary in cache: preload("res://adventure_terrain.gd").apply(d) # 路數、季節、地形、肉鴿守將
	return cache

static func build_stages() -> Array:
	return [
		# ---- 一・晨麥古道：新兵訓練（逐步指引見 tutorial_lessons.gd） ----
		_stage("w1_1","1-1",0,0,"第一道命令","bandit_chief",0,
			["bandit","bandit","bandit","bandit","bandit","bandit","bandit","bandit"],
			[],
			"強盜在麥田邊紮了營，老隊長說：正好拿他們練手。",
			"出兵與勝負","選一張牌、放在我方領地，部隊就會自己往前打。打破強盜營地的木柵，再讓任何一名士兵走進營地，就贏了。",
			_lesson({"deck":["militia","militia","militia","militia","militia","militia","militia","militia"],"camp":true,"tip":"選民兵、點亮起的格子，部隊會自己往前打。"})),
		_stage("w1_2","1-2",0,1,"金幣與手牌","bandit_chief",0,
			["bandit","bandit","bandit","bandit","bandit","bandit","bandit","bandit"],
			["archer"],
			"強盜又來了一批。老隊長叫來弓手：前排擋、後排射。",
			"金幣、冷卻與手牌","每張牌都要花金幣，金幣會隨時間增加（上限 50）。手上只有四張，出掉一張就換上「下一張」，新牌要先冷卻。",
			_lesson({"prev":"w1_1","deck":["archer","militia","militia","archer","militia","archer","militia","archer"],"camp":true,"tip":"民兵擋在前面，弓手才能安心在後面射。"})),
		_stage("w1_3","1-3",0,2,"自家麥田","bandit_chief",0,
			["bandit","bandit","bandit","bandit","bandit","bandit","bandit","bandit"],
			["farmer"],
			"打仗打的是錢。錢從哪來？種田。",
			"農田與農民","常駐的農田卡永遠在手上，每塊田每 20 秒產 4 金幣、沒有數量上限。農民經過農田會停下來耕田，接下來 15 秒產量加倍。",
			_lesson({"prev":"w1_2","deck":["farmer","militia","farmer","archer","farmer","militia","farmer","archer"],"camp":true,"tip":"先種田、派農民耕田，錢滾起來再出兵。"})),
		_stage("w1_4","1-4",0,3,"插旗推進","bandit_chief",0,
			["bandit","bandit","bandit","bandit","bandit","bandit","bandit","bandit"],
			["barricade"],
			"強盜在路中間架起木拒馬，把地盤劃了過去。",
			"領地與建築","只能在我方領地出兵和蓋建築；城牆和每座建築周圍八格都是領地，先佔先得。往前蓋建築，領地就往前推。",
			_lesson({"prev":"w1_3","deck":["barricade","militia","barricade","archer","militia","barricade","militia","archer"],"camp":true,"buildings":[[6,2,"barricade"]],"tip":"在領地最前緣蓋建築，就能從更前面出兵。"})),
		_stage("w1_5","1-5",0,4,"小考：麥田演習","card_enemy_scarecrow",0,
			["militia","farmer","archer","barricade","scarecrow","militia","farmer","archer"],
			["fire"],
			"老隊長的兵這回會自己出牌，還在路上插滿稻草人。",
			"小考：單路實戰","對手會自己種田、出兵、蓋稻草人擋路。用前四課學的出兵、種田、推領地，再用新拿到的火罐（對建築 600 傷害）燒開他的防線。",
			_lesson({"prev":"w1_4","deck":["militia","archer","farmer","barricade","militia","archer","farmer","fire"],"tip":"稻草人擋路就丟火罐；開局先種兩塊田、派農民。"})),
		_stage("w1_6","1-6",0,5,"守住城門","mob_foreman",0,
			["mob","mob","militia","militia","mob","militia","hunter","militia"],
			["scarecrow","tower"],
			"暴民頭領煽動鄉民，拿著乾草叉分三路撲向城門，只能靠你守住。",
			"防守：部隊不回頭","部隊只會往前走，漏過去的敵兵不會回頭追。防守要靠建築：稻草人把上下三路的敵兵吸到同一路，箭樓射周圍兩格。守滿倒數就算贏。",
			_lesson({"prev":"w1_5","deck":["tower","scarecrow","militia","archer","tower","militia","scarecrow","archer"],"camp":true,"survive_time":90.0,"tip":"箭樓蓋在城牆前，稻草人擺在它前面擋。"})),
		_stage("w1_7","1-7",0,6,"箭雨與火罐","card_enemy_mill",0,
			["militia","militia","farmer","militia","militia","farmer","militia","hunter"],
			["rain"],
			"磨坊莊園囤糧抗稅，莊上的鄉兵三路並排擠過來，糧食就堆在莊裡。",
			"法術","法術可以丟在戰場任何地方，不必在自己領地。箭雨（2×3 格）一次蓋住三路清人群，火罐（2×2 格）專燒建築。",
			_lesson({"prev":"w1_6","deck":["rain","fire","militia","archer","rain","militia","fire","archer"],"camp":true,"buildings":[[7,2,"granary"]],"tip":"箭雨清人群，火罐燒建築。"})),
		_stage("w1_8","1-8",0,7,"三岔路口","militia_captain",0,
			["militia","militia","militia","hunter","militia","militia","hunter","militia"],
			["hunter"],
			"叛變的民兵隊長帶著人馬分三路包抄，領主終於親自上陣。",
			"三路與領主","每一路都有一段城牆，任何一段被打破敵兵就能走進來。你的領主會自己去攔最深入的敵兵，倒下後 12 秒重生。",
			_lesson({"prev":"w1_7","deck":["hunter","militia","archer","farmer","hunter","militia","tower","rain"],"active_lanes":MIDDLE_LANES,"camp":true,"tip":"看上方城牆血條，哪一路有敵人就補哪一路。"})),
		_stage("w1_9","1-9",0,8,"破陣斬","ram_marshal",0,
			["ram","militia","militia","shieldguard","ram","militia","militia","shieldguard"],
			["recruit_camp"],
			"攻城槌元帥推出了攻城槌，普通的兵砍不動它。",
			"領主技能","花出去的每一枚金幣都會替領主技能充能。充滿後按 Q：邊境領主的破陣斬向前斬出 5 格長、3 路寬的劍氣。",
			_lesson({"prev":"w1_8","deck":["militia","hunter","archer","farmer","militia","hunter","archer","rain"],"active_lanes":MIDDLE_LANES,"camp":true,"tip":"等攻城槌走近領主再按 Q，劍氣才砍得到。","card_note":"新兵營：蓋好後每 24 秒在這一路訓練 2 名民兵。"})),
		_stage("w1_10","1-10",0,9,"畢業考：豐收莊園","harvest",0,
			["farmer","militia","hunter","mob","barricade","scarecrow","rain","tower"],
			["mob"],
			"豐收領主打開糧倉閘門，補給車源源不斷駛向五路前線。",
			"畢業考：傳送帶","本關沒有金幣與農田，改由底部傳送帶免費送出農民軍團與法術（最多存 8 張）；直接出牌不花錢並替領主大招充能。日晷走到入夜城牆會崩，天亮還沒分勝負就比領地。",
			{"prev":"w1_9",
			"deck":["militia","archer","hunter","mob","barricade","scarecrow","tower","rain"],
			"allow_duplicates":false,
			"conveyor":{
				"capacity":8,
				"interval":2.8,
				"min_interval":1.7,
				"start_count":3,
				"opening":["militia","archer","hunter","barricade","mob","rain"],
				"pool":["militia","militia","archer","archer","hunter","hunter","mob","mob","mob","barricade","scarecrow","tower","recruit_camp","rain","rain","fire"],
			},
			"tip":"免費出牌不用省金幣，傳送帶快滿 8 張就趕快傾瀉兵力；打不贏就把難度調成簡單。"}),

		# ---- 二・運河渡口：經典兵種相剋 ----
		_stage("w2_1","2-1",1,0,"盾牆渡口","shield_sergeant",0,
			["shieldguard","militia","farmer","hunter","barricade","scarecrow","rain","mob"],
			["macebreaker"],
			"渡口守軍舉起一整排大盾，箭射上去叮叮噹噹。",
			"重甲與破甲","盾衛每次受到傷害先減 20：獵戶的箭只剩 30，民兵也砍得很慢。釘錘破甲兵的攻擊無視護甲，專拆硬殼。",
			{"prev":"w1_10","deck_lesson":true,"active_lanes":MIDDLE_LANES,"new_enemy":"shieldguard","enemy_note":"每次受到傷害減少 20；小傷害打它幾乎沒用。","tip":"釘錘破甲兵無視護甲；火罐、領主這種大傷害也不怕盾。"}),
		_stage("w2_2","2-2",1,1,"雙塔哨口","tower_warden",0,
			["tower","militia","hunter","farmer","shieldguard","barricade","rain","scarecrow"],
			["knight"],
			"兩座箭樓守著渡口，誰先靠近誰先挨箭。",
			"肉盾","箭樓會射周圍兩格內的敵人。讓 900 生命的騎士走在前面吸收火力，後面的部隊才拆得到塔。",
			{"prev":"w2_1","active_lanes":MIDDLE_LANES,"new_enemy":"tower","enemy_note":"射擊周圍兩格內的敵人；沒有敵兵時改打建築。","tip":"騎士打頭陣、民兵和獵戶跟在後面拆塔；火罐也能直接燒塔。"}),
		_stage("w2_3","2-3",1,2,"草藥婆的帳篷","field_prior",0,
			["healer","militia","shieldguard","knight","farmer","hunter","rain","barricade"],
			["healer"],
			"敵陣後面有人不停替傷兵包紮，怎麼打都打不死。",
			"治療","草藥婆每 2.4 秒替附近友軍回 50 生命。先點掉對面躲在後排的草藥婆；自己的大軍也帶一個。",
			{"prev":"w2_2","active_lanes":MIDDLE_LANES,"new_enemy":"healer","enemy_note":"每 2.4 秒替附近友軍回 50 生命，躲在後排。","tip":"用箭雨或獵戶先打後排的草藥婆。"}),
		_stage("w2_4","2-4",1,3,"奔牛河灘","ox_herder",1,
			["ox","militia","farmer","hunter","knight","barricade","rain","mob"],
			["ox"],
			"河灘上牛群低頭刨地，眼看就要衝過來。",
			"衝鋒","耕牛跑得快，衝鋒的第一下雙倍傷害並撞退、撞暈，打建築與城牆再 ×1.5。用木拒馬或稻草人先吃掉第一撞。",
			{"prev":"w2_3","new_enemy":"ox","enemy_note":"衝鋒第一擊雙倍並撞暈；打建築與城牆 ×1.5。","tip":"在牛前面擺木拒馬或稻草人，讓它撞在便宜的東西上。"}),
		_stage("w2_5","2-5",1,4,"小考：渡口要塞","knight_commander",1,
			["knight","tower","barricade","shieldguard","healer","militia","hunter","rain"],
			["ram"],
			"騎士團長把渡口修成了要塞：箭樓、拒馬一應俱全。",
			"小考：攻城戰","敵人開局就蓋好箭樓與拒馬。攻城槌只打建築、城牆與領主，一下 360 傷害；身邊 4 名民兵負責擋人。",
			{"prev":"w2_4","mutators":[{"enemy_buildings":[[1,1,"tower"],[1,3,"tower"],[2,0,"barricade"],[2,2,"barricade"],[2,4,"barricade"]]}],"tip":"攻城槌很慢：先讓騎士或木拒馬替它擋箭，再一路推到城牆。"}),
		_stage("w2_6","2-6",1,5,"鼓聲長堤","drummer_major",1,
			["drummer","militia","ox","knight","farmer","hunter","rain","mob"],
			["drummer"],
			"鼓聲一響，對面整支軍隊就快了一截。",
			"鼓舞","戰鼓手每 10 秒擊鼓，全場友軍移速、攻速升一檔 3 秒。敵軍會一陣一陣變快——在鼓聲之間反擊，也讓自己的大軍帶一個。",
			{"prev":"w2_5","new_enemy":"drummer","enemy_note":"每 10 秒擊鼓：全場友軍移速、攻速升一檔 3 秒。","tip":"戰鼓手躲在民兵後面，用箭雨或獵戶從遠處點掉他。"}),
		_stage("w2_7","2-7",1,6,"槍弓校場","card_enemy_spearbow",1,
			["spearbow","militia","hunter","healer","farmer","tower","rain","shieldguard"],
			["spearbow"],
			"教頭把長槍兵和弓手編成一隊，前後排一起推進。",
			"軍團","槍弓混編一張牌出 4 名民兵加 2 名弓手，佔 2×2 格——四格都要是我方領地才放得下。",
			{"prev":"w2_6","new_enemy":"spearbow","enemy_note":"一張牌出 4 名民兵加 2 名弓手，前後排一起來。","tip":"軍團擠在一起：一發箭雨能同時打到前後排。"}),
		_stage("w2_8","2-8",1,7,"磨坊水車","card_enemy_mill",1,
			["mill","farmer","militia","hunter","knight","tower","rain","scarecrow"],
			["mill"],
			"兩座磨坊嘎吱轉個不停，對面的錢越滾越多。",
			"經濟建築","磨坊讓同一路的農田產出 ×2。敵人開局就有兩座磨坊——錢會滾得很快，越晚越難打。",
			{"prev":"w2_7","new_enemy":"mill","enemy_note":"同一路的農田產出 ×2；拖越久對面越有錢。","tip":"趁早用火罐或耕牛拆磨坊；自己的磨坊蓋在農田多的那一路。"}),
		_stage("w2_9","2-9",1,8,"蘆葦盜影","bandit_chief",1,
			["bandit","militia","mob","ox","hunter","rain","fire","barricade"],
			["watchtower"],
			"蘆葦叢裡有人影晃動，一眨眼田就被砸了。",
			"潛行與偵查","強盜登場時潛行：潛行中只有法術打得到，部隊、建築和領主都傷不了他，直到他出手。瞭望塔範圍內的潛行者會永久現形。",
			{"prev":"w2_8","new_enemy":"bandit","enemy_note":"潛行：看不見、只有法術打得到，出手後才現形。","tip":"在農田附近蓋瞭望塔揭露它們；箭雨等法術也打得到潛行者。領主會去攔，但打不到。"}),
		_stage("w2_10","2-10",1,9,"大考：紅獅水門","lion",1,
			["knight","militia","ox","drummer","ram","hunter","charge_horn","rain"],
			["charge_horn"],
			"紅獅領主親率騎士團把守水門。",
			"大考：領主技能","紅獅領主的「獅王號令」會從每一路城牆召出騎士。準備破甲兵與箭樓，把騎士擋在半路，再反推。",
			{"prev":"w2_9","new_enemy":"skill","tip":"騎士很硬但很慢：釘錘破甲兵、火罐、破陣斬都很有效。","card_note":"衝鋒號令：一整路我方部隊移速、攻速升一檔 15 秒。"}),

		# ---- 三・星軌高塔：魔法陣營 ----
		_stage("w3_1","3-1",2,0,"水晶礦脈","card_enemy_crystal",1,
			["rune_sentinel","artificer","prism_mage","arcane_shield","time_field","hunter","militia","rain"],
			["bandit"],
			"高塔腳下的水晶嗡嗡作響，替法師們源源不絕地供錢。",
			"陣營與常駐牌","每個陣營的常駐經濟牌不一樣：魔法陣營用水晶，每次產 2 金幣但會耗損自己。水晶比農田脆，適合偷襲。",
			{"prev":"w2_10","new_enemy":"crystal","enemy_note":"魔法陣營的常駐經濟：每次產 2 金幣並損失生命。","tip":"派強盜潛行繞過前線，專拆後排的水晶。"}),
		_stage("w3_2","3-2",2,1,"護盾迴廊","card_enemy_arcane_shield",1,
			["arcane_shield","rune_sentinel","blink_blade","prism_mage","artificer","arcane_golem","mana_drain","militia"],
			["spellbreaker"],
			"法師們替前排一層層加上光盾。",
			"護盾","奧術護盾給範圍內部隊 180 點護盾，先吸收傷害、可以累加。破法者打魔法陣營傷害 ×2，受到的法術傷害減半。",
			{"prev":"w3_1","new_enemy":"arcane_shield","enemy_note":"範圍內部隊獲得 180 點護盾，重複施放可累加。","tip":"破法者是魔法陣營的剋星；護盾很厚時用火罐一口氣打穿。"}),
		_stage("w3_3","3-3",2,2,"法陣棋盤","trap_weaver",1,
			["blast_trap","teleport_trap","rune_sentinel","prism_mage","artificer","blink_blade","arcane_shield","time_field"],
			["twin_gambler"],
			"地上畫滿發光的法陣，踩錯一格就炸。",
			"陷阱","法陣是埋在地上的陷阱，敵兵踩上去才觸發；爆炸法陣可以炸 3 次。新來的雙刃賭徒一張牌 6 金、跑得快，最適合先去把陣踩掉，主力再跟上。",
			{"prev":"w3_2","new_enemy":"blast_trap","enemy_note":"踩上去才爆，可以炸 3 次；只有 80 生命。","tip":"先派雙刃賭徒探路；箭雨也能直接炸掉陷阱。"}),
		_stage("w3_4","3-4",2,3,"閃影長廊","card_enemy_blink_blade",1,
			["blink_blade","rune_sentinel","prism_mage","arcane_shield","artificer","time_field","mana_drain","militia"],
			["powder_barrel"],
			"兩條雪廊又窄又直，劍士一挨打就往前閃，成群擠過來。",
			"閃現與炸藥","閃現劍士每次受傷就往前閃 0.25 格，會鑽過前排，一路衝到你埋好的東西上。炸藥桶被踩到就炸九宮格 600 傷害——只有兩條路，他們一定會經過。",
			{"prev":"w3_3","new_enemy":"blink_blade","enemy_note":"每次受傷向前閃現 0.25 格，會穿過前排。","tip":"在兩條路各埋一個炸藥桶，前面放少量部隊讓劍士閃過去踩。"}),
		_stage("w3_5","3-5",2,4,"小考：符文禁苑","rune",1,
			["teleport_trap","summon_trap","blast_trap","rune_sentinel","arcane_golem","artificer","arcane_shield","time_field"],
			["net_hunter"],
			"符文領主在每一條路的盡頭都畫好了陣。",
			"小考：探路","符文領主的技能會在每一路領地最前緣放一個隨機法陣，開局也已經埋了兩個。主力出發前，先想想讓誰去踩。",
			{"prev":"w3_4","new_enemy":"skill","mutators":[{"enemy_buildings":[[3,1,"blast_trap"],[3,3,"teleport_trap"]]}],"tip":"派雙刃賭徒去踩陣；新來的投網獵人網住魔像，3 秒內移速、攻速減半。"}),
		_stage("w3_6","3-6",2,5,"貫星箭塔","card_enemy_arcane_archer",1,
			["arcane_archer","rune_sentinel","prism_mage","arcane_shield","artificer","time_field","blink_blade","mana_drain"],
			["assassin"],
			"光箭從高塔射下，一箭貫穿整條路。",
			"遠程與刺客","奧術射手的光箭會貫穿一整路，身前還有結界護衛替他擋傷害。刺客潛行衝刺、只打部隊，專門切後排。",
			{"prev":"w3_5","new_enemy":"arcane_archer","enemy_note":"光箭貫穿本路 6 格，前面有結界護衛擋傷害。","tip":"刺客繞過結界護衛直取射手；或用火罐一次炸掉後排。"}),
		_stage("w3_7","3-7",2,6,"凝滯時廊","card_enemy_time_field",1,
			["time_field","arcane_golem","rune_sentinel","prism_mage","arcane_shield","artificer","blink_blade","chain_lightning"],
			["arquebusier"],
			"走進那片光裡，連眨眼都變慢了。",
			"緩速力場","時空力場讓範圍內敵軍移速、攻速減半 8 秒，建築也會變慢。射程 3.5 格的火繩槍兵可以站在力場外開火。",
			{"prev":"w3_6","new_enemy":"time_field","enemy_note":"3×3 格內移速、攻速減半 8 秒，建築也變慢。","tip":"別把部隊擠進同一塊力場；分路出兵，火槍兵遠遠射。"}),
		_stage("w3_8","3-8",2,7,"魔像鍛爐","golem_smith",1,
			["arcane_golem","artificer","rune_sentinel","prism_mage","arcane_shield","time_field","chain_lightning","blink_blade"],
			["axe_thrower"],
			"鍛爐裡走出一尊尊石像，每一尊都比城牆還硬。",
			"重裝與破甲","奧術魔像有 1500 生命，每座水晶再減傷 10%，死亡時還會爆炸。投斧手一斧 180 傷害、無視護甲，站在後面砍。",
			{"prev":"w3_7","new_enemy":"arcane_golem","enemy_note":"1500 生命，每座水晶減傷 10%，死時爆炸。","tip":"投斧手站在後面砍魔像；先拆水晶，魔像的減傷就會消失。"}),
		_stage("w3_9","3-9",2,8,"雷鳴尖頂","card_enemy_chain_lightning",1,
			["chain_lightning","prism_mage","arcane_archer","rune_sentinel","artificer","arcane_shield","time_field","arcane_golem"],
			["manor_retainer"],
			"雷光在擠成一團的士兵之間來回跳。",
			"連鎖與分散","連鎖閃電先打 360，再跳到附近的敵人，每跳弱一檔。擠成一團最吃虧——分路出兵，少量多血的部隊比較耐打。",
			{"prev":"w3_8","new_enemy":"chain_lightning","enemy_note":"打中後跳向附近的目標，最多再跳 4 次。","tip":"把部隊分散到不同路；莊園扈從人少血厚，閃電劈不了幾個。"}),
		_stage("w3_10","3-10",2,9,"大考：星軌鐘頂","mage",2,
			["arcane_golem","blink_blade","arcane_archer","gravity_well","chain_lightning","time_field","mirror_clone","arcane_shield"],
			["levy"],
			"法師領主撥動星軌，整片戰場的時間為他停下。",
			"大考：時空凝滯","法師領主的技能會凍住你全軍 6 秒、停止產金。凍結結束時敵軍多半已壓到家門口——緊急徵召會替領地裡每名敵兵招來一名民兵。",
			{"prev":"w3_9","new_enemy":"skill","tip":"凍結一解除就用緊急徵召或箭雨守家；平時別把金幣花光。","card_note":"緊急徵召：領地裡每有 1 名敵兵，就在它前方召喚 1 名民兵。"}),

		# ---- 四・冥霧墓澤：黑暗陣營 ----
		_stage("w4_1","4-1",3,0,"墓碑野地","card_enemy_grave",1,
			["skeleton","ghoul","shroud_arbalist","mourning_maid","pallbearer","bellbearer","curse","plague"],
			["vampire_hunter"],
			"墓碑一座接一座，每倒下一個人，它們就亮一下。",
			"墓碑與亡者","黑暗陣營用墓碑賺錢：每 60 秒產 6 金幣，這一路每死一個人就提前 5 秒——戰鬥越激烈，他們賺越多。",
			{"prev":"w3_10","new_enemy":"grave","enemy_note":"黑暗陣營的常駐經濟：本路每死一人提前 5 秒產金。","tip":"吸血鬼獵人打黑暗陣營傷害 ×2；別在墓碑旁邊打消耗戰。"}),
		_stage("w4_2","4-2",3,1,"白骨行軍","skeleton_king",1,
			["skeleton","ghoul","necromancer","mourning_maid","raven","curse","shroud_arbalist","bonewall"],
			["flaming_pitch"],
			"骷髏兵一群一群爬出來，砍倒一批又來一批。",
			"人海與範圍","骷髏兵一張牌 6 隻、每隻只有 50 生命。範圍法術是人海的剋星：燃燒火油在地上燒 8 秒，每秒 35 傷害。",
			{"prev":"w4_1","new_enemy":"skeleton","enemy_note":"一張牌 6 隻，每隻 50 生命，靠數量取勝。","tip":"在骷髏必經之路丟燃燒火油或箭雨。"}),
		_stage("w4_3","4-3",3,2,"瘟疫泥沼","card_enemy_plague",1,
			["plague","skeleton","ghoul","pallbearer","mourning_maid","shroud_arbalist","raven","corpse_giant"],
			["catapult"],
			"綠霧在泥沼上翻滾，吸一口就渾身發軟。",
			"毒與機械","瘟疫毒霧每秒疊一層毒，毒死的人還會冒出小毒霧。建築和機械單位不怕毒；草藥婆每次治療會減一層。",
			{"prev":"w4_2","new_enemy":"plague","enemy_note":"毒霧每秒疊一層毒；毒死的人會冒出小毒霧。","tip":"帶草藥婆跟著大軍；投石車是機械，站在毒霧裡也沒事。"}),
		_stage("w4_4","4-4",3,3,"鴉群枯林","raven_mother",1,
			["raven","skeleton","ghoul","shroud_arbalist","mourning_maid","plague","curse","bonewall"],
			["beekeeper"],
			"黑壓壓的鴉群越過前線，直撲後方的農田。",
			"飛行","烏鴉群會飛：近戰部隊和建築打不到牠，只有遠程、箭樓和領主打得到。牠們專挑農田和城牆啄。",
			{"prev":"w4_3","new_enemy":"raven","enemy_note":"飛越近戰部隊，只啄建築、城牆和領主，優先農田。","tip":"農田旁邊放箭樓或遠程部隊；養蜂人的蜂群能射下鴉群。"}),
		_stage("w4_5","4-5",3,4,"小考：冥府雙塚","underworld",2,
			["skeleton","ghoul","necromancer","reaper","bonewall","plague","raven","shroud_arbalist"],
			["gatebreaker"],
			"冥府領主站在墓碑之間，等著亡者大軍甦醒。",
			"小考：拆掉源頭","冥府領主的技能：每座墓碑各召喚 4 隻骷髏，開局他還多立了兩座。墓碑越多亡者越多——先拆墓碑。",
			{"prev":"w4_4","new_enemy":"skill","mutators":[{"enemy_buildings":[[1,0,"grave"],[1,4,"grave"]]}],"tip":"破門錘手打建築傷害 ×3，一路拆過去。"}),
		_stage("w4_6","4-6",3,5,"早降的夜","necro_adept",2,
			["necromancer","skeleton","ghoul","corpse_giant","curse","mourning_maid","shroud_arbalist","raven"],
			["harvest"],
			"墓澤的夜來得特別早，兩點半天就黑了。",
			"長夜","這裡 2:30 就入夜：入夜後金幣 ×3、雙方城牆每秒自己掉血，而且每分鐘加倍。入夜前存好錢，趁夜色一口氣總攻。",
			{"prev":"w4_5","night_start_override":150.0,"new_enemy":"necromancer","enemy_note":"每 10 秒在三路各召喚 1 名骷髏兵。","tip":"豐收讓農田產量加倍；入夜前存好金幣，夜裡一口氣推。"}),
		_stage("w4_7","4-7",3,6,"骨牆渡口","card_enemy_bonewall",2,
			["bonewall","skeleton","ghoul","necromancer","shroud_arbalist","curse","plague","reaper"],
			["rolling_boulder"],
			"兩道白骨巨牆橫在路中央，敲一下就掉出骷髏。",
			"繞路與穿透","骨牆有 3000 生命，每掉 20% 就召出 2 隻骷髏。硬拆很虧——改走沒有骨牆的路，或用巨石滾滾撞穿整路。",
			{"prev":"w4_6","new_enemy":"bonewall","enemy_note":"3000 生命、不會攻擊，每掉 20% 召出 2 隻骷髏。","tip":"骨牆不會攻擊：繞到沒有骨牆的路進攻。"}),
		_stage("w4_8","4-8",3,7,"屍山巨影","card_enemy_corpse_giant",2,
			["corpse_giant","skeleton","ghoul","necromancer","pallbearer","shroud_arbalist","plague","raven"],
			["old_witch"],
			"腐屍巨人每挨一刀，肚子裡就掉出一窩骷髏。",
			"拆成小兵的大個子","腐屍巨人每掉 25% 生命就爆出 4 隻骷髏。老巫婆的咒彈有十字範圍毒，專清爆出來的小兵。",
			{"prev":"w4_7","new_enemy":"corpse_giant","enemy_note":"每掉 25% 生命就爆出 4 隻骷髏兵。","tip":"老巫婆和箭雨清骷髏，破甲兵和投斧手專打巨人。"}),
		_stage("w4_9","4-9",3,8,"血霧孤塔","blood_prior",2,
			["blood_tower","blood_attendant","ghoul","reaper","shroud_arbalist","raven","sacrifice","mourning_shroud"],
			["guard"],
			"孤塔裡的血池咕嘟作響，替同一路的亡者補血。",
			"治療建築","鮮血塔平時存血，本路每死一人再 +50，用來治療同一路的友軍。在塔旁邊打消耗戰會越打越吃虧。",
			{"prev":"w4_8","new_enemy":"blood_tower","enemy_note":"存血治療同一路友軍，本路每死一人多存 50。","tip":"先用火罐、投石車或破門錘手拆掉鮮血塔。","card_note":"聖堂護衛：兩名騎士加兩名草藥婆的重裝軍團。"}),
		_stage("w4_10","4-10",3,9,"大考：血月尖塔","vampire",2,
			["blood_attendant","ghoul","reaper","shroud_arbalist","raven","blood_tower","mourning_shroud","sacrifice"],
			["counter_charge"],
			"血月在三點就升起，吸血領主舔了舔嘴唇。",
			"大考：撐過爆發","3:00 就入夜。吸血領主的「鮮血盟約」讓全軍攻速、移速升一檔 16 秒，還越打越肥。他施放時用反衝號令把敵軍整群撞回去。",
			{"prev":"w4_9","night_start_override":180.0,"new_enemy":"skill","tip":"鮮血盟約只有 16 秒：撐過去再反攻；反衝號令能打斷衝進來的大軍。","card_note":"反衝號令：3×3 格內敵軍擊退、暈眩 1 秒，我方部隊加速並獲得衝鋒。"}),

		# ---- 五・巨獸王城：魔物陣營與最終決戰 ----
		_stage("w5_1","5-1",4,0,"貪食河谷","card_enemy_glutton_nest",2,
			["pouch_beast","thorn_hound","web_spinner","tusk_boar","parasite_mite","wing_gust","corrosive_bile","fishbeak"],
			["shieldguard"],
			"草叢裡藏著會張嘴的巢穴，走過去的人一個都沒回來。",
			"吞噬巢穴","貪食巢穴平時隱藏、打不到；地面部隊一靠近就張嘴吞掉最多 4 名。牠消化時（約 10 秒）閉著嘴，這時才打得到。",
			{"prev":"w4_10","new_enemy":"glutton_nest","enemy_note":"隱藏時打不到；有人靠近就張嘴吞掉最多 4 名。","tip":"先送一兩隊便宜的盾衛讓牠吞，趁牠消化時大軍衝過去拆掉。"}),
		_stage("w5_2","5-2",4,1,"厚皮獸道","card_enemy_pouch_beast",2,
			["pouch_beast","tusk_boar","thorn_hound","web_spinner","bog_troll","corrosive_bile","wing_gust","monster_hatchery"],
			["monster_hunter"],
			"三枚金幣就能叫來一頭 900 生命的囊腹獸。",
			"厚血與剋星","魔物陣營血厚：囊腹獸 3 金幣就有 900 生命。怪物獵人打魔物陣營傷害 ×2，是對付牠們的專家。",
			{"prev":"w5_1","new_enemy":"pouch_beast","enemy_note":"3 金幣、900 生命的肉牆。","tip":"怪物獵人跟在前排後面，專打魔物。"}),
		_stage("w5_3","5-3",4,2,"荊棘獵場","card_enemy_thorn_hound",2,
			["thorn_hound","bramble_wall","pouch_beast","web_spinner","tusk_boar","leech_vine","corrosive_bile","thorn_mother"],
			["ballista_tower"],
			"獵犬背上長滿倒刺，咬牠的人反而先流血。",
			"反傷","棘刺獵犬和荊棘高牆被近戰打中時會反傷攻擊者。遠程、法術和領主不會被刺。",
			{"prev":"w5_2","new_enemy":"thorn_hound","enemy_note":"被近戰攻擊時反傷攻擊者 36 點。","tip":"用重弩塔、獵戶、投斧手從遠處打；近戰打荊棘會自己掉血。"}),
		_stage("w5_4","5-4",4,3,"飛魔斷崖","card_enemy_hooknose_flyer",2,
			["hooknose_flyer","hive_nest","pouch_beast","web_spinner","thorn_hound","sky_scavenger","wing_gust","corrosive_bile"],
			["field_smithy"],
			"崖頂的巢穴裡，一隻接一隻的飛魔撲下來。",
			"飛行突擊","鉤鼻飛魔會飛、會攻擊地面部隊，近戰和建築打不到牠。野戰鐵匠鋪給附近友軍 26 點護甲：飛魔每下 50 只剩 24。",
			{"prev":"w5_3","new_enemy":"hooknose_flyer","enemy_note":"飛行：近戰與建築打不到，牠卻會攻擊地面部隊。","tip":"箭樓與遠程部隊對空；鐵匠鋪的護甲讓飛魔咬不痛。"}),
		_stage("w5_5","5-5",4,4,"小考：龍脊獸巢","beast",2,
			["pouch_beast","tusk_boar","bog_troll","thorn_hound","web_spinner","monster_hatchery","pack_ambush","feral_mutation"],
			["disgraced_lancer"],
			"馴獸領主吹響號角，每一條路都有魔獸應聲而出。",
			"小考：獸群","馴獸領主的技能會在每一路最前緣放出囊腹獸，開局還有兩座巨獸孵巢不停產獸。先拆孵巢，再擋獸群。",
			{"prev":"w5_4","new_enemy":"skill","mutators":[{"enemy_buildings":[[1,1,"monster_hatchery"],[1,3,"monster_hatchery"]]}],"tip":"孵巢只有 560 生命：用叛逃槍騎的衝鋒或火罐快速拆掉。"}),
		_stage("w5_6","5-6",4,5,"巨魔沼澤","card_enemy_bog_troll",2,
			["bog_troll","pouch_beast","tusk_boar","web_spinner","thorn_hound","corrosive_bile","feral_mutation","leech_vine"],
			["halberdier"],
			"巨魔泡在泥裡，傷口一邊打一邊長回來。",
			"再生與集火","沼澤巨魔每 2.4 秒回 70 生命，脫戰回得更多。零零星星送兵打不死它——集中火力一口氣壓上去。",
			{"prev":"w5_5","new_enemy":"bog_troll","enemy_note":"1500 生命，每 2.4 秒回 70，脫戰回更多。","tip":"長戟兵四人一起上、搭配破甲兵集中輸出，別零星送兵。"}),
		_stage("w5_7","5-7",4,6,"龍吼峽谷","card_enemy_eyewing_dragon",2,
			["eyewing_dragon","pouch_beast","thorn_hound","hooknose_flyer","web_spinner","tusk_boar","wing_gust","berserk_blood"],
			["mule_cart","hook_collector"],
			"龍一開口，前排的士兵就丟下武器往回跑。",
			"恐懼與長期戰","眼翼龍每 5 秒吼一聲，附近敵軍轉身逃回城牆 2.5 秒、不能攻擊。遠程站遠一點就不會被嚇跑；仗會拖長，記得顧經濟。",
			{"prev":"w5_6","new_enemy":"eyewing_dragon","enemy_note":"每 5 秒吼叫，附近敵軍逃跑 2.5 秒、不能攻擊。","tip":"獵戶、火繩槍兵、重弩塔遠遠打龍；騾馬貨車在後方賺錢。","card_note":"騾馬貨車往返領地邊界賺錢；鉤鐮收債人每親手殺一個敵人得 1 金幣。"}),
		_stage("w5_8","5-8",4,7,"三頭狂蜥","card_enemy_dire_hydra",2,
			["dire_hydra","pouch_beast","thorn_hound","web_spinner","tusk_boar","bog_troll","corrosive_bile","feral_mutation"],
			["gold_monster"],
			"三個頭、三千生命，一口氣掃過三條路。",
			"存錢一擊","三頭狂蜥 3000 生命、三連擊並橫掃三路。金幣怪物會花光你所有金幣：存到 50 一次召出 5 隻 900 生命的怪物。",
			{"prev":"w5_7","new_enemy":"dire_hydra","enemy_note":"3000 生命，每次攻擊三連擊並橫掃三路。","tip":"存滿 50 金幣再出金幣怪物，正面扛住狂蜥。"}),
		_stage("w5_9","5-9",4,8,"王城外廓","catapult_engineer",2,
			["catapult","ballista_tower","knight","arquebusier","shieldguard","healer","tower","counter_charge"],
			["supply_depot"],
			"王城外廓架滿重弩與投石車，城門前堆著拒馬。",
			"攻城總複習","外廓前排有木拒馬、後排有重弩塔和投石車。攻城槌、破門錘手拆牆，騎士在前面擋箭；重弩塔只打本路前方，從旁邊的路繞過去。",
			{"prev":"w5_8","new_enemy":"ballista_tower","mutators":[{"enemy_buildings":[[1,1,"ballista_tower"],[1,3,"ballista_tower"]]}],"enemy_note":"沿本路直射前方 4 格，無視護甲。","tip":"從沒有重弩塔的路進攻；補給站讓同一路出兵返還 1 金幣。"}),
		_stage("w5_10","5-10",4,9,"大考：王都鐵壁","iron",2,
			["knight","macebreaker","guard","arquebusier","healer","ram","tower","counter_charge"],
			["granary"],
			"鐵壁領主站在城頭：五域的最後一道門。",
			"最終決戰","鐵壁領主有 3000 生命，技能會在他的領地蓋兩座箭樓。五路齊攻、往前推領地，別讓他把箭樓蓋滿。",
			{"prev":"w5_9","new_enemy":"skill","tip":"箭樓只能蓋在他的領地裡：先推領地，他就沒地方蓋。","card_note":"糧倉：每次農田產出就存 1 金幣，存滿 10 一次放出。"}),
	]

static func index_of(id: String) -> int:
	var list := stages()
	for i: int in range(list.size()):
		if list[i].id == id: return i
	return -1

static func validate(list: Array = stages()) -> Array[String]:
	var errors: Array[String] = []
	if WORLDS.size() != 5: errors.append("campaign must define 5 worlds")
	var want_count := WORLDS.size() * STAGES_PER_WORLD
	if list.size() != want_count: errors.append("campaign must define %d stages, got %d" % [want_count, list.size()])
	var ids: Dictionary = {}
	for d: Dictionary in list:
		if d.get("id","").is_empty() or ids.has(d.id): errors.append("duplicate or empty stage id: "+str(d.get("id","")))
		ids[d.get("id","")] = true
	var pool: Array = DeckStore.pool("adventure")
	var story: Dictionary = preload("res://campaign_story_data.gd").SCENES
	var granted: Dictionary = {}
	for k: String in STARTER_CARDS: granted[k] = true
	for i: int in range(list.size()):
		var d: Dictionary = list[i]
		var id: String = d.get("id","")
		for key: String in ["code","name","story","goal","rule_tag","rule_desc","biome","tip"]:
			if not d.get(key) is String or d.get(key,"").is_empty(): errors.append(id+": missing text "+key)
		for key: String in ["opening","dialogue","enemy_camp","enemy_lord_active","capital","boss","special","night_decay"]:
			if not d.get(key) is bool: errors.append(id+": missing boolean "+key)
		if int(d.get("world",-1)) != i / STAGES_PER_WORLD: errors.append(id+": invalid world index")
		var local_i := i % STAGES_PER_WORLD
		if bool(d.get("special",false)) != (local_i == 4 or local_i == 9): errors.append(id+": invalid special flag")
		if bool(d.get("boss",false)) != (local_i == 9): errors.append(id+": invalid boss flag")
		if not d.get("ai") is int or not d.get("ai",-1) in range(3): errors.append(id+": invalid AI difficulty")
		if not d.get("map") is Vector2: errors.append(id+": missing map position")
		if not B.LORDS.has(d.get("lord","")): errors.append(id+": unknown lord")
		if not B.LORDS.has(d.get("enemy_lord","")) and not B.MINION_LORDS.has(d.get("enemy_lord","")): errors.append(id+": unknown ruler")
		var deck = d.get("deck")
		if not (deck is String and deck == "player") and not (deck is Array and DeckStore.valid(deck,d.lord,d.get("allow_duplicates",false))): errors.append(id+": invalid player deck")
		var foe = d.get("enemy_deck")
		if not foe is Array or foe.size() != 8 or foe.any(func(k) -> bool: return not B.CARDS.has(k)): errors.append(id+": invalid enemy deck")
		var lanes: Array = d.get("active_lanes",[])
		var rows: int = int(d.get("rows",5))
		if not rows in [5,6]: errors.append(id+": rows must be 5 or 6")
		if lanes.is_empty() or lanes.any(func(lane) -> bool: return not lane in range(rows)): errors.append(id+": invalid lanes")
		for card in d.get("rewards",[]):
			if not card in pool: errors.append(id+": reward %s is not a card the adventure lord can use" % str(card))
			if granted.has(card): errors.append(id+": reward %s is already given earlier" % str(card))
			granted[card] = true
		# A fixed lesson hand only uses cards taught by this stage or before it.
		if deck is Array:
			for card in deck:
				if not granted.has(card): errors.append(id+": lesson hand uses %s before it is taught" % str(card))
		var cv: Dictionary = d.get("conveyor",{})
		if not cv.is_empty():
			var cv_pool = cv.get("pool",[])
			if not cv_pool is Array or cv_pool.is_empty(): errors.append(id+": conveyor pool cannot be empty")
			for src_key: String in ["opening","pool"]:
				for card in cv.get(src_key,[]):
					if not B.CARDS.has(card): errors.append(id+": conveyor unknown card "+str(card))
					elif not granted.has(card): errors.append(id+": conveyor uses %s before it is taught" % str(card))
		var foe_kind: String = d.get("new_enemy","")
		if not foe_kind.is_empty() and foe_kind != "skill" and not B.CARDS.has(foe_kind): errors.append(id+": unknown new enemy "+foe_kind)
		if foe_kind == "skill" and not B.LORDS.has(d.get("enemy_lord","")): errors.append(id+": a skill callout needs a real lord")
		for b in d.get("buildings",[]):
			if b.size() != 3 or not b[0] in range(9) or not b[1] in lanes or not B.CARDS.has(b[2]) or B.CARDS[b[2]].type != "building": errors.append(id+": invalid building "+str(b))
		if d.dialogue and (not story.has(id) or not story[id] is Array or story[id].size() != 2 or story[id][0].is_empty() or story[id][1].is_empty()): errors.append(id+": missing campaign story scene")
		for link in d.get("links",[]):
			if not ids.has(link): errors.append(id+": unknown link "+str(link))
	for id: String in UNLOCK_LORDS:
		if not ids.has(id) or not B.LORDS.has(UNLOCK_LORDS[id]): errors.append("invalid lord reward "+id)
	for diff: Dictionary in DIFFICULTIES:
		if String(diff.get("name","")).is_empty() or not int(diff.get("stars",0)) in range(1,MAX_STARS_PER_STAGE+1) or not int(diff.get("ai",-1)) in range(-1,3): errors.append("invalid difficulty "+str(diff))
	for p: Dictionary in EXTREME_PASSIVES:
		if String(p.get("name","")).is_empty() or String(p.get("desc","")).is_empty() or p.get("mods",{}).is_empty(): errors.append("invalid extreme passive "+str(p))
	for dec: Dictionary in DECREES:
		if String(dec.get("id","")).is_empty() or String(dec.get("name","")).is_empty() or dec.get("mods",{}).is_empty(): errors.append("invalid decree "+str(dec))
	var stage_ids: Array = list.map(func(d: Dictionary) -> String: return d.id)
	errors.append_array(preload("res://tutorial_lessons.gd").validate(stage_ids))
	errors.append_array(preload("res://adventure_terrain.gd").validate(stage_ids))
	return errors
