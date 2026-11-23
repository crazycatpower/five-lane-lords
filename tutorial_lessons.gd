extends RefCounted
# 冒險模式第一章「新兵訓練」的逐步指引（2026-11-21）。純資料：tutorial_coach.gd 讀這裡執行。
# 每堂課一份腳本，鍵為關卡 ID：
#   setup  開局設定
#     enemy_gate   藍方各路城牆起始生命（滿血是 B.GATE_HP）
#     ink          我方開局金幣
#     our_farms    只留幾塊我方開局農田
#     enemy_farms  只留幾塊藍方開局農田（演習：敵陣只有腳本派出的兵）
#     lord         我方領主是否上陣（false = 坐鎮城中，右下角改成說明）
#     enemy_ai     （已不使用：藍方 AI 一律照難度出牌，腳本敵軍另外加派；使用者 2026-11-22）
#     enemy_ink    藍方開局金幣
#     enemy_income 藍方基本產金倍率（1.0＝正常；前幾課調低，讓新手跟得上，難度倍率另外疊加）
#     skill_charge 我方領主技能預先充能比例 0..1
#     compact      五路關卡：提示改用頂端精簡一列，不擋戰場
#     phase_notes  日晷換時辰時提示金幣倍率
#     ward_until   藍方城牆在第幾步之前有「教學結界」（打不壞），免得還沒學完就破城獲勝
#     our_ward     我方城牆最多被打到一半（前幾課不會輸）
#   每一步最多等 STEP_MAX 秒，沒做到也會往下走，不會卡關。
#   waves  腳本敵軍（第一章是強盜，派出時就現形，潛行留到 2-9 再教）：after = 第幾步完成後才開始計時（-1 = 開戰就計），delay 秒後從藍方城牆前派出 kind；
#          lane = 路（-1 = 依序輪流各路），every > 0 每隔幾秒再派，until = 第幾步完成後停止
#   steps  步驟：text 說明；hint 高亮目標（可用 + 連接）；done 完成條件；min 至少顯示秒數
#   loss   這一課失敗時的提示
# 高亮目標：card:<卡>、home、purse、next、skill、sundial、walls、clock、own_cells、front_cells、
#           behind_farm、our_farm、enemy_wall、enemy_units、enemy_building、enemy_farm、building:<卡>、lord
# 完成條件：selected、play:<卡>[:<次>]、plays:<次>、farms:<塊>、drops:<次>、cultivate:<次>、
#           build:<卡>:<最小欄>、front:<欄>、kills:<隻>、burn:<塊>、enemy_down:<卡>、skill_ready、
#           skill、gate_down、time:<秒>、win（只在勝利時結束）

const HINTS := ["card","home","purse","next","skill","sundial","walls","clock","own_cells","front_cells","behind_farm","our_farm","enemy_wall","enemy_units","enemy_building","enemy_farm","building","lord"]
const STEP_MAX := 90.0
const DONES := ["selected","play","plays","farms","drops","cultivate","build","front","kills","burn","enemy_down","skill_ready","skill","gate_down","time","win"]

const SCRIPTS := {
	"w1_1":{
		"setup":{"enemy_income":0.25,"enemy_ink":0.0,"lord":false,"enemy_ai":false,"ward_until":3,"our_ward":true,"enemy_farms":0},
		"waves":[
			{"after":1,"delay":3.0,"kind":"bandit","lane":2},
			{"after":1,"delay":5.0,"kind":"bandit","lane":2},
			{"after":2,"delay":6.0,"kind":"bandit","lane":2,"every":14.0},
		],
		"steps":[
			{"text":"這是你的第一張牌：民兵隊，一次派出 5 名步兵。點一下下方的卡牌，或按數字鍵 1 選取它。","hint":"card:militia","done":"selected","min":0.5},
			{"text":"亮起來的格子就是能出兵的地方——我方領地。點一下格子，派出民兵！","hint":"own_cells","done":"play:militia"},
			{"text":"部隊會自己沿著這一路往前走，遇到敵人就開打。看，強盜衝過來了！","hint":"enemy_units","done":"kills:4","min":3.0},
			{"text":"打到底就會攻擊強盜營地的木柵。把它打到 0——金幣夠了就再派一隊幫忙！","hint":"enemy_wall","done":"gate_down"},
			{"text":"木柵倒了！只要有任何一名士兵走進營地，這一仗就贏了。","hint":"enemy_wall","done":"win"},
		],
		"loss":"選民兵、點亮起的格子，部隊會自己往前打。",
	},
	"w1_2":{
		"setup":{"enemy_income":0.4,"enemy_ink":0.0,"lord":false,"enemy_ai":false,"ward_until":4,"our_ward":true,"enemy_farms":0},
		"waves":[
			{"after":0,"delay":6.0,"kind":"bandit","lane":2},
			{"after":2,"delay":4.0,"kind":"bandit","lane":2,"every":20.0},
		],
		"steps":[
			{"text":"左下角是金幣。每張牌都標著價錢，金幣會隨時間自己增加，最多存 50。","hint":"purse","done":"time:6"},
			{"text":"弓手是遠程部隊，站在後面放箭（射程 3.5 格）。一張牌 4 人、佔前後兩格，兩格都要是我方領地。選弓手，派到戰場上。","hint":"card:archer+own_cells","done":"play:archer"},
			{"text":"出掉的牌會換成右邊的「下一張」。剛進手的牌要先冷卻——卡面灰色倒數，數完才能出。","hint":"next","done":"time:7"},
			{"text":"民兵在前面擋，弓手在後面射。兩種一起出，擋下來襲的強盜！","hint":"card:militia+enemy_units","done":"kills:8"},
			{"text":"很好！金幣夠就繼續出兵，打破木柵、走進營地。","hint":"enemy_wall","done":"win"},
		],
		"loss":"民兵擋在前面，弓手才能安心在後面射。",
	},
	"w1_3":{
		"setup":{"enemy_income":0.5,"enemy_ink":0.0,"lord":false,"enemy_ai":false,"our_farms":0,"ink":20.0,"ward_until":4,"our_ward":true,"enemy_farms":0},
		"waves":[
			{"after":3,"delay":6.0,"kind":"bandit","lane":2,"every":26.0},
		],
		"steps":[
			{"text":"左邊這張「常駐」農田卡永遠不會被換掉。按 F 或點它，種在我方領地的空格。","hint":"home+own_cells","done":"farms:1"},
			{"text":"農田種下 3 秒後啟動，之後每 20 秒產出 4 金幣——看田上的進度條。","hint":"our_farm","done":"drops:1"},
			{"text":"派農民到田的同一格或更後面（左邊）。他經過農田會停下來耕田，接下來 15 秒產量加倍。","hint":"card:farmer+behind_farm","done":"cultivate:1"},
			{"text":"農田沒有數量上限，越早種越賺。冷卻好了就在亮起的空格再種一塊（種在舊田上只會補血）。","hint":"home+own_cells","done":"farms:2"},
			{"text":"錢多了就能出更多兵。種田、耕田、出兵——打破強盜的木柵！","hint":"enemy_wall","done":"win"},
		],
		"loss":"先種田、派農民耕田，錢滾起來再出兵。",
	},
	"w1_4":{
		"setup":{"enemy_income":0.6,"enemy_ink":0.0,"lord":false,"enemy_ai":false,"ward_until":4,"our_ward":true,"enemy_farms":0},
		"waves":[
			{"after":2,"delay":5.0,"kind":"bandit","lane":2,"every":24.0},
		],
		"steps":[
			{"text":"淡紅色的是我方領地：城牆和建築周圍八格（含斜角）都算。出兵、蓋建築都只能放在這裡。","hint":"own_cells","done":"time:7"},
			{"text":"選木拒馬（3 金幣、1500 生命），蓋在領地最前緣的格子。","hint":"card:barricade+front_cells","done":"build:barricade:2"},
			{"text":"領地往前推了！在新的最前緣再蓋一座，把領地推到中線。","hint":"front_cells","done":"front:4"},
			{"text":"藍色是強盜的地盤，靠路中間那座木拒馬撐著。拆掉它，那片地就會空出來。","hint":"enemy_building","done":"enemy_down:barricade"},
			{"text":"從最前緣出兵，部隊更快打到敵陣。打破木柵，走進營地！","hint":"front_cells+enemy_wall","done":"win"},
		],
		"loss":"在領地最前緣蓋建築，就能從更前面出兵。",
	},
	"w1_5":{
		"setup":{"lord":false,"enemy_ai":true},
		"steps":[
			{"text":"小考：這次對手會自己出牌！用學過的四招——出兵、種田、耕田、推領地——打贏他。","hint":"","done":"time:9"},
			{"text":"提示：開局先種田、派農民耕田，錢滾起來再出兵比較穩。","hint":"home","done":"time:14"},
			{"text":"敵方的稻草人會把附近的部隊吸過去打它。新拿到的火罐對建築 600 傷害——對準它丟下去！","hint":"card:fire+enemy_building","done":"time:14"},
		],
		"loss":"稻草人擋路就丟火罐；開局先種兩塊田、派農民。",
	},
	"w1_6":{
		"setup":{"enemy_income":0.6,"lord":false,"enemy_ai":false,"ink":40.0,"ward_until":4,"enemy_farms":0},
		"waves":[
			{"after":0,"delay":16.0,"kind":"mob","lane":-1,"every":12.0},
			{"after":0,"delay":52.0,"kind":"militia","lane":1},
			{"after":0,"delay":52.0,"kind":"militia","lane":3},
		],
		"steps":[
			{"text":"暴民要分三路進攻了，守住 1 分 30 秒（上方倒數）。記住：部隊只會往前走，漏過去的敵兵不會回頭追！","hint":"clock","done":"time:7"},
			{"text":"在城牆前蓋一座箭樓：它會射擊周圍兩格內的敵人，敵兵繞不過去。","hint":"card:tower+own_cells","done":"play:tower"},
			{"text":"稻草人會把上下三路的敵兵都吸到它這一路，正好進箭樓的射程。蓋在中路、箭樓前面。","hint":"card:scarecrow+front_cells","done":"play:scarecrow"},
			{"text":"撐住！這一課暴民的木柵有結界，只有守滿倒數才算贏。","hint":"clock","done":"win"},
		],
		"loss":"箭樓蓋在城牆前，稻草人擺在它前面擋。",
	},
	"w1_7":{
		"setup":{"enemy_income":0.7,"lord":false,"enemy_ai":false,"ink":30.0,"ward_until":3},
		"waves":[
			{"after":1,"delay":2.0,"kind":"militia","lane":1},
			{"after":1,"delay":2.0,"kind":"militia","lane":2},
			{"after":1,"delay":2.0,"kind":"militia","lane":3},
			{"after":2,"delay":6.0,"kind":"militia","lane":-1,"every":16.0},
		],
		"steps":[
			{"text":"法術不必放在自己的領地，整片戰場哪裡都能丟。","hint":"","done":"time:5"},
			{"text":"先用小考學會的火罐，燒掉莊裡那座囤糧的糧倉。","hint":"card:fire+building:granary","done":"enemy_down:granary"},
			{"text":"三路鄉兵並排擠過來了！箭雨是 2×3 格，丟在中路就能一次蓋住三路。","hint":"card:rain+enemy_units","done":"kills:6"},
			{"text":"糧倉燒了，莊園撐不久。乘勝追擊，打破木柵！","hint":"enemy_wall","done":"win"},
		],
		"loss":"箭雨清人群，火罐燒建築。",
	},
	"w1_8":{
		"setup":{"enemy_income":0.8,"lord":true,"enemy_ai":false,"enemy_gate":600.0,"ward_until":4},
		"waves":[
			{"after":1,"delay":4.0,"kind":"militia","lane":1},
			{"after":1,"delay":12.0,"kind":"militia","lane":3},
			{"after":2,"delay":6.0,"kind":"militia","lane":-1,"every":15.0},
		],
		"steps":[
			{"text":"現在有三路！每一路都有一段城牆（上方血條），任何一段被打破，敵兵就能從那裡走進來。","hint":"walls","done":"time:7"},
			{"text":"獵戶一張牌在三路各站 1 人放箭（射程 3 格），一次守住三路。派出去！","hint":"card:hunter","done":"play:hunter"},
			{"text":"這位是你的領主，這次親自上陣！他會自己去攔最深入的敵兵；倒下後 12 秒會在城堡重生。","hint":"lord","done":"time:8"},
			{"text":"敵軍會從不同路進攻。哪一路有敵人，就往那一路出兵或蓋箭樓。","hint":"enemy_units","done":"kills:12"},
			{"text":"打破任何一路木柵、走進營地就贏。","hint":"enemy_wall","done":"win"},
		],
		"loss":"看上方城牆血條，哪一路有敵人就補哪一路。",
	},
	"w1_9":{
		"setup":{"enemy_income":0.9,"lord":true,"enemy_ai":false,"skill_charge":0.5,"ward_until":3},
		"waves":[
			{"after":0,"delay":2.0,"kind":"ram","lane":2},
			{"after":1,"delay":5.0,"kind":"militia","lane":-1,"every":16.0},
			{"after":1,"delay":14.0,"kind":"ram","lane":1,"every":34.0},
		],
		"steps":[
			{"text":"右下角是領主技能。每花 1 金幣出牌，技能就充能一點；整塊亮起來就能施放。","hint":"skill","done":"skill_ready"},
			{"text":"攻城槌來了！等它走近按 Q 放破陣斬：向前 5 格、3 路寬，1200 傷害。","hint":"skill+enemy_units","done":"skill"},
			{"text":"技能放完要冷卻，之後再花金幣充能。大傢伙交給技能，小兵交給部隊！","hint":"skill","done":"kills:6"},
			{"text":"最後一步：打破木柵，走進營地。","hint":"enemy_wall","done":"win"},
		],
		"loss":"等攻城槌走近領主再按 Q，劍氣才砍得到。",
	},
	"w1_10":{
		"setup":{"compact":true,"phase_notes":true},
		"steps":[
			{"text":"畢業考特殊規則：本關沒有金幣與農田，改由下方傳送帶免費送牌，最多存 8 張！","hint":"","done":"time:8"},
			{"text":"直接點擊傳送帶上的卡牌（或按 1–8），免費部署到五路戰場，同時替領主大招充能。","hint":"","done":"time:10"},
			{"text":"上方日晷是一天：3:00 正午、4:30 黃昏，6:00 入夜後雙方城牆開始崩塌；天亮比領地大小。","hint":"sundial","done":"time:10"},
			{"text":"傳送帶一有空位就會持續送牌：五路輪流顧好，哪一路告急就補兵或放雨熄火。","hint":"walls","done":"time:10"},
		],
		"loss":"傳送帶免費出牌，別囤到滿格 8 張——持續往優勢路推進、替領主充能開大。",
	},
}

# Data errors for quick_test: unknown hints, conditions or cards, waves pointing at missing steps.
static func validate(stage_ids: Array) -> Array[String]:
	var B = preload("res://balance.gd")
	var errors: Array[String] = []
	for id: String in SCRIPTS:
		if not id in stage_ids: errors.append("lesson for unknown stage "+id)
		var lesson: Dictionary = SCRIPTS[id]
		var steps: Array = lesson.get("steps",[])
		if steps.is_empty(): errors.append(id+": no steps")
		if String(lesson.get("loss","")).is_empty(): errors.append(id+": no loss tip")
		for s: Dictionary in steps:
			if String(s.get("text","")).is_empty(): errors.append(id+": empty step text")
			var done: PackedStringArray = String(s.get("done","")).split(":")
			if not done[0] in DONES: errors.append(id+": unknown condition "+String(s.get("done","")))
			if done[0] in ["play","build","enemy_down"] and (done.size() < 2 or not B.CARDS.has(done[1])): errors.append(id+": unknown card in "+String(s.done))
			for h: String in String(s.get("hint","")).split("+",false):
				var head := h.split(":")[0]
				if not head in HINTS: errors.append(id+": unknown hint "+h)
				if head in ["card","building"] and not B.CARDS.has(h.get_slice(":",1)): errors.append(id+": unknown hint card "+h)
		for w: Dictionary in lesson.get("waves",[]):
			if not B.CARDS.has(String(w.get("kind",""))) or B.CARDS[w.kind].type != "unit": errors.append(id+": wave must send a unit card "+str(w))
			if int(w.get("after",-1)) >= steps.size(): errors.append(id+": wave waits for a missing step "+str(w))
	return errors
