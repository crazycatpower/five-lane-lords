extends RefCounted
# 冒險模式劇情 (2026-11-12 rewrite): 「誰來繼位」. The old king died without an heir; his will says
# whoever's colour covers most of the chronicler's map is king. A border lord who only wanted to
# farm ends up painting the whole map. Dry humour, one joke per scene, no hidden plot threads.
# Each territory: [before the battle, after the victory]. Each row: speaker, words, the portrait
# speaking, the portrait listening. Portrait keys: "lord" (ours), "mob" (the villager), "foe" (the
# territory's ruler), "bandit", "knight".
const SCENES := {
	"crossroads": [
		[["村民","大人，老王駕崩了！遺詔只有一句：\n史官的地圖上，哪個顏色塗得最多，誰就是新王。","mob","lord"],
		["領主","所以強盜才把我的農田算成他的領地？我只想種田。","lord","mob"],
		["強盜頭子","驛站是我的，路是我的，路過的雞也是我的。\n想塗顏色？先問過我的刀。","foe","lord"]],
		[["村民","驛站拿下了！史官已經在地圖上替您塗了一小塊紅。","mob","lord"],
		["領主","從這裡有四條路。走哪條都行，反正每一條的盡頭都有人想當王。","lord","mob"]]
	],
	"ox_hill": [
		[["牧牛人","我的牛一天吃三座山。你的田看起來很下飯。","foe","lord"],
		["領主","牛可以留下耕田，人請回去。","lord","foe"]],
		[["村民","牛群歸我們了！牠們好像不在乎主人是誰，只在乎草。","mob","lord"],
		["領主","比多數領主誠實。","lord","mob"]]
	],
	"militia_pass": [
		[["民兵隊長","站住！此關奉……奉誰的命令來著？算了，總之不准過。","foe","lord"],
		["領主","老王都不在了，你替誰守關？","lord","foe"],
		["民兵隊長","替關守關。沒有關，我就只是個隊長。","foe","lord"]],
		[["村民","隊長說他願意換一面旗子繼續守，只要准他留著哨子。","mob","lord"],
		["領主","准。哨子比忠誠好養。","lord","mob"]]
	],
	"lion_keep": [
		[["紅獅領主","小領主，我騎士的馬蹄印都比你的領地大。\n回去種田，我封你做糧官。","foe","lord"],
		["領主","謝謝，不過我的麥子不喜歡被馬踩。","lord","foe"],
		["紅獅領主","那就讓獅王號令告訴你，什麼叫正統！","foe","lord"]],
		[["紅獅領主","……輸給種田的。史官，這一段可以寫小字嗎？","foe","lord"],
		["領主","騎士你留著。麥田諸侯從今天起，秋收之前不准打仗。","lord","foe"]]
	],
	"rune_fields": [
		[["法陣師","小心腳下。我也不記得哪些法陣是傳送、哪些會爆炸。","foe","lord"],
		["村民","大人，他說的是真的。剛剛有隻雞不見了又回來，還是熟的。","mob","lord"]],
		[["法陣師","你們居然全踩過去了……這在學術上叫「暴力驗證」。","foe","lord"],
		["領主","把還沒爆的標上記號。之後我的農民要從這裡過。","lord","foe"]]
	],
	"golem_works": [
		[["魔像匠","我的魔像不吃、不睡、不領薪水。你的民兵呢？","foe","lord"],
		["領主","會抱怨。所以我知道他們還活著。","lord","foe"]],
		[["村民","工坊歸我們了。魔像還在走，只是現在幫忙搬麥子。","mob","lord"],
		["魔像匠","輕一點！那一尊的膝蓋還沒付清尾款！","foe","mob"]]
	],
	"clock_tower": [
		[["法師領主","我算過了。你會輸，而且輸在天亮以前。慶功茶我都泡好了。","foe","lord"],
		["領主","你算過茶會涼嗎？","lord","foe"],
		["法師領主","……時空凝滯，就是為了這種事發明的。","foe","lord"]],
		[["法師領主","奇怪，沙漏明明是我的。","foe","lord"],
		["領主","學院照舊教書。只是以後算命之前，先算算田裡要多少人手。","lord","foe"]]
	],
	"raven_roost": [
		[["鴉群之母","我的孩子們餓了。你們的田，聞起來像早餐。","foe","lord"],
		["村民","大人，稻草人說它不幹了！","mob","lord"]],
		[["村民","烏鴉飛走了。鴉巢裡全是亮晶晶的東西……還有三把我家的湯匙。","mob","lord"],
		["領主","湯匙還你。其餘充公。","lord","mob"]]
	],
	"bone_ford": [
		[["骷髏王","我當王的時候，你們的老王還沒出生。\n論資排輩，這張地圖該塗白色。","foe","lord"],
		["領主","史官說死人不能繼位。","lord","foe"],
		["骷髏王","那是歧視。全軍……呃，全骨，進攻！","foe","lord"]],
		[["骷髏王","好吧。能幫我把下巴撿回來嗎？在你左腳邊。","foe","lord"],
		["領主","渡口照常通行。亡者夜裡擺渡，活人白天過河，誰也別嚇誰。","lord","foe"]]
	],
	"blood_chapel": [
		[["吸血領主","歡迎。本堂的契約一向公道：你出血，我出力。","foe","lord"],
		["領主","我只帶了麥子。","lord","foe"],
		["吸血領主","真遺憾。麥子不會尖叫。","foe","lord"]],
		[["吸血領主","天亮了？……你是故意拖到天亮的。","foe","lord"],
		["領主","禮拜堂留給你，契約全部作廢。以後要血，自己去養鵝。","lord","foe"]]
	],
	"fishbeak_shore": [
		[["村民","那是魚還是鳥？牠在啄我們的田！","mob","lord"],
		["領主","不管是什麼，牠沒繳稅。","lord","mob"]],
		[["村民","魚喙怪退回水裡了。牠們留下一地貝殼，史官說可以磨成顏料。","mob","lord"],
		["領主","那就替荒原塗上第一筆。","lord","mob"]]
	],
	"imp_market": [
		[["鬍子魔王","歡迎光臨！今日特價：你的錢袋。原價歸你，現在歸我。","foe","lord"],
		["領主","我的金幣剛剛是不是少了兩枚？","lord","mob"],
		["村民","三枚，大人。他說第三枚是手續費。","mob","lord"]],
		[["鬍子魔王","生意失敗。這樣吧，偷來的都還你，打九折。","foe","lord"],
		["領主","全額。外加這座集市的攤位稅。","lord","foe"]]
	],
	"dragon_vale": [
		[["骨刺龍王","……","foe","lord"],
		["村民","牠沒說話，可是牠背上每一根刺都在看我們。","mob","lord"],
		["領主","近戰打牠會被刺傷。弓手往前，其他人離牠的背遠一點。","lord","mob"]],
		[["村民","龍王趴下了！牠……好像只是想找個地方曬太陽。","mob","lord"],
		["領主","谷地留給牠曬。荒原從今天起不吃人，人也不拔牠的刺。","lord","mob"]]
	],
	"royal_seat": [
		[["鐵壁領主","我守著這座空王座三個月了。四面來的人都說自己是正統。","foe","lord"],
		["領主","我不是。我只是不想再有人踩我的田。","lord","foe"],
		["鐵壁領主","這是我聽過最像國王的理由。但規矩是規矩：\n城牆沒倒，王座不讓。","foe","lord"]],
		[["鐵壁領主","城牆倒了，地圖也紅了。史官，寫吧。","foe","lord"],
		["村民","大人……不，陛下！加冕之後第一道命令是什麼？","mob","lord"],
		["領主","秋收。所有人，回去種田。","lord","mob"]]
	]
}

# The scene for a territory, with one line from the companion recruited after the first farm.
const COMPANION := {
	"bandit":["強盜","這條路我搶……我是說，我走過。跟著我的腳印就不會踩到陷阱。","bandit","lord"],
	"knight":["騎士","王座空著的時候，路上每個人都覺得自己該坐上去。請小心，大人。","knight","lord"],
}
static func dialogue(stage: String, recruit: String, won: bool) -> Array:
	var result: Array = SCENES[stage][1 if won else 0].duplicate(true)
	if not won and stage == "crossroads" and COMPANION.has(recruit): result.insert(result.size()-1,COMPANION[recruit])
	return result
