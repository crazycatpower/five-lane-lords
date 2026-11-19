extends RefCounted
# Unified keyword system for all cards and lords: canonical names, manuscript/combat colours,
# automatic extraction from card data, BBCode colourising, and canvas pill/tooltip rendering.

# Keyword definitions:
# - color: text colour on parchment (and border colour on pills)
# - fill: soft background fill for pills on parchment
# - fx: vivid combat/dark-background colour (e.g. light green for heal, deep green for poison)
# - desc: concise rule explanation shown in the codex and hover card
# - terms: phrases highlighted with this keyword's colour inside card descriptions
const KEYWORDS := {
	"毒蝕": {
		"color": Color("115224"),
		"fill": Color("b8dec2"),
		"fx": Color("1b6e32"),
		"desc": "使目標中毒或腐蝕防禦，在數秒內持續受到毒性傷害（可被治療減輕或被淨化解除）。",
		"terms": ["毒蝕","毒霧","小毒霧","毒死","持續傷害","咒彈","毒蜂","腐蝕酸雨","清除敵軍護盾與護甲"]
	},
	"治療": {
		"color": Color("2e9e44"),
		"fill": Color("d4f5da"),
		"fx": Color("5ce675"),
		"desc": "為範圍內友方部隊恢復生命值，並同時減輕 1 層毒蝕。",
		"terms": ["治療友軍","治療","療傷","回復","平均治療"]
	},
	"再生": {
		"color": Color("3cb354"),
		"fill": Color("daf5df"),
		"fx": Color("6ef086"),
		"desc": "隨時間或咀嚼自動恢復自身生命；脫戰持續移動 3 秒後再生效率提升 ×1.5。",
		"terms": ["再生","恢復","回滿生命","回滿血"]
	},
	"吸血": {
		"color": Color("9e1c28"),
		"fill": Color("f2c9cd"),
		"fx": Color("d93848"),
		"desc": "攻擊造成傷害或獻血時汲取生命，轉化為自身續航或戰力。",
		"terms": ["吸血","回復自身生命","鮮血盟約","儲血","獻血","換血"]
	},
	"灼燒": {
		"color": Color("c24214"),
		"fill": Color("f7d4c4"),
		"fx": Color("f26422"),
		"desc": "以烈焰或火海燒灼目標區域，對部隊與建築造成高溫傷害。",
		"terms": ["火海","吐出火焰","燒田","火罐","燃燒火油"]
	},
	"護盾": {
		"color": Color("1f6ea3"),
		"fill": Color("c9e3f5"),
		"fx": Color("4fc3f7"),
		"desc": "賦予臨時護盾或法術抗性，優先吸收受到的傷害。",
		"terms": ["護盾","受到法術傷害","共鳴"]
	},
	"護甲": {
		"color": Color("485e6e"),
		"fill": Color("d3dde3"),
		"fx": Color("8fa8b8"),
		"desc": "減少每次受到的傷害（最低仍受 1 點傷害），或構築高耐久防線。",
		"terms": ["護甲","受到傷害減少","減傷"]
	},
	"破甲": {
		"color": Color("9e4b16"),
		"fill": Color("f2d8c4"),
		"fx": Color("e07a38"),
		"desc": "攻擊直接穿透目標的護甲減傷效果。",
		"terms": ["破甲","無視護甲減傷"]
	},
	"維修": {
		"color": Color("7d591e"),
		"fill": Color("efe0c2"),
		"fx": Color("d9a74a"),
		"desc": "修補受損的友方建築或構裝（奧術魔像、結界護衛），恢復其生命與運作效率。",
		"terms": ["維修","修復友方建築","修補"]
	},
	"反傷": {
		"color": Color("852454"),
		"fill": Color("f0cadc"),
		"fx": Color("d14788"),
		"desc": "受到攻擊時將荊棘刺傷或法術傷害反彈給攻擊者。",
		"terms": ["反傷","荊棘","反彈","刺傷"]
	},
	"暈眩": {
		"color": Color("73369e"),
		"fill": Color("e3cef2"),
		"fx": Color("b66ee8"),
		"desc": "使敵軍暫時失去行動能力，期間無法移動與攻擊。",
		"terms": ["暈眩","時空凝滯","凍結時間"]
	},
	"定身": {
		"color": Color("543269"),
		"fill": Color("dccfe6"),
		"fx": Color("9564b3"),
		"desc": "束縛敵方地面部隊使其無法移動，但仍可原地攻擊。",
		"terms": ["定身"]
	},
	"遲緩": {
		"color": Color("265b8c"),
		"fill": Color("c9def2"),
		"fx": Color("5da5e8"),
		"desc": "降低敵軍的移動速度與攻擊速度。",
		"terms": ["遲緩","減速","移速與攻速減半","被網住"]
	},
	"恐懼": {
		"color": Color("522669"),
		"fill": Color("dbc9e6"),
		"fx": Color("9b59b6"),
		"desc": "使敵方部隊驚恐逃往自家城牆，期間不會發動攻擊。",
		"terms": ["恐懼","轉身往自己城牆逃跑","吼叫"]
	},
	"淨化": {
		"color": Color("8a6d1b"),
		"fill": Color("f5eac4"),
		"fx": Color("f0cf65"),
		"desc": "解除周圍友軍身上的暈眩、減速、恐懼、定身與毒蝕狀態。",
		"terms": ["淨化","解除"]
	},
	"擊退": {
		"color": Color("1e6e70"),
		"fill": Color("c4e6e6"),
		"fx": Color("45b8ba"),
		"desc": "以強風或衝擊波將敵方部隊向後推開，打斷其推進陣線。",
		"terms": ["擊退","推敵"]
	},
	"衝鋒": {
		"color": Color("b54618"),
		"fill": Color("f5d2c2"),
		"fx": Color("eb6b34"),
		"desc": "高速突進敵軍，首擊造成高額傷害並附帶擊退或暈眩；脫戰持續移動 3 秒後再次進入衝鋒。",
		"terms": ["衝鋒","衝刺","首次攻擊","首擊傷害","再次衝鋒","撲向"]
	},
	"加速": {
		"color": Color("9e6810"),
		"fill": Color("f5e2be"),
		"fx": Color("f0ad32"),
		"desc": "鼓舞友軍，使移動速度與攻擊速度提升檔次。",
		"terms": ["移速與攻速各提高一檔","移速與攻速各升一檔","移速與攻速升一檔","移速與攻速升檔","擊鼓","鼓舞"]
	},
	"潛行": {
		"color": Color("32485c"),
		"fill": Color("cbd6e0"),
		"fx": Color("7494b3"),
		"desc": "隱匿行蹤無法被敵軍直接鎖定；攻擊後現形，若未被偵查揭露則脫戰持續移動 3 秒後再次潛行。",
		"terms": ["潛行","再次潛行","無法被敵方直接鎖定"]
	},
	"偵查": {
		"color": Color("186b59"),
		"fill": Color("c4e8df"),
		"fx": Color("38b89c"),
		"desc": "揭露範圍內的潛行敵軍使其永久現形，或提升友方遠程射程。",
		"terms": ["偵查","偵察","揭露","現形","射程升一檔","射程提高一檔"]
	},
	"相位": {
		"color": Color("5e3ca3"),
		"fill": Color("ddd0f5"),
		"fx": Color("996ee8"),
		"desc": "穿梭空間或閃現突進，可越過地面阻擋且不觸發地面陷阱。",
		"terms": ["相位","閃現","折躍"]
	},
	"飛行": {
		"color": Color("24688c"),
		"fill": Color("c7e2f0"),
		"fx": Color("56b2e0"),
		"desc": "空中單位，地面近戰部隊與陷阱無法命中，僅遠程與領主可攻擊。",
		"terms": ["飛行單位","飛行","飛越近戰"]
	},
	"召喚": {
		"color": Color("683082"),
		"fill": Color("e2ccf0"),
		"fx": Color("ad5cd1"),
		"desc": "周期性、觸發後或於死亡時在戰場上召喚部隊助戰。",
		"terms": ["召喚","爬出","縫出","爆出","孵化","分裂","變成我方骷髏兵","複製"]
	},
	"死志": {
		"color": Color("7d2436"),
		"fill": Color("edc7cf"),
		"fx": Color("cf4662"),
		"desc": "受到致命傷時保留 1 點生命、吞噬友軍續命，或於臨死前自爆。",
		"terms": ["致命傷時保留 1 生命","致命傷害時吞噬","自爆"]
	},
	"貫穿": {
		"color": Color("334996"),
		"fill": Color("ccd5f2"),
		"fx": Color("6682e0"),
		"desc": "投射物或閃電沿直線貫穿多名敵人，或在敵陣間連鎖彈跳。",
		"terms": ["貫穿","跳向附近"]
	},
	"橫掃": {
		"color": Color("9c2628"),
		"fill": Color("f2c9ca"),
		"fx": Color("de474a"),
		"desc": "攻擊或部署同時涵蓋本路與相鄰路線，或沿整路直線碾壓。",
		"terms": ["橫掃","三路","滾完整路","揮鐮直劈"]
	},
	"爆破": {
		"color": Color("a6361e"),
		"fill": Color("f5cfc6"),
		"fx": Color("e65a3c"),
		"desc": "對落點或觸發區域內的所有敵軍造成範圍傷害。",
		"terms": ["範圍傷害","拋射","爆炸"]
	},
	"產金": {
		"color": Color("8f630e"),
		"fill": Color("f5e5be"),
		"fx": Color("e8af30"),
		"desc": "定時產出金幣、提升農田產量、返還費用或透過戰場傷亡換取金幣。",
		"terms": ["產出","金幣","耕田","產出加倍","退還","返還"]
	},
	"偷金": {
		"color": Color("874d15"),
		"fill": Color("f2dac2"),
		"fx": Color("db8535"),
		"desc": "攻擊或施法時從敵方奪取金幣，或處決敵兵換取賞金。",
		"terms": ["偷走","抽取","吞殺"]
	},
	"獵殺": {
		"color": Color("962436"),
		"fill": Color("f0c7ce"),
		"fx": Color("d9455d"),
		"desc": "針對特定陣營、領主或殘血目標造成額外倍率傷害。",
		"terms": ["擊殺","傷害 ×","換路尋找","隨機"]
	},
	"攻城": {
		"color": Color("73391c"),
		"fill": Color("ebcfc2"),
		"fx": Color("c46a3d"),
		"desc": "專司破壞敵方建築與城牆，對結構物造成巨額威脅。",
		"terms": ["只打建築與城牆","只攻擊建築與城牆","城牆","城門","建築"]
	},
	"巡邏": {
		"color": Color("3d5c35"),
		"fill": Color("cfe0ca"),
		"fx": Color("6da15f"),
		"desc": "在己方領地內來回巡守，或吸引周圍敵軍優先攻擊自己。",
		"terms": ["巡邏","吸引至同一路"]
	},
	"重裝": {
		"color": Color("66492e"),
		"fill": Color("e6d6c6"),
		"fx": Color("b0855b"),
		"desc": "高生命值的堅實前排部隊，能穩固扛住敵軍正面火力。",
		"terms": ["主坦","厚血"]
	},
	"遠射": {
		"color": Color("325869"),
		"fill": Color("c9dce6"),
		"fx": Color("5d9cb8"),
		"desc": "在安全距離外發射箭矢或彈丸支援前線。",
		"terms": ["箭矢飛行","射程"]
	},
	"人海": {
		"color": Color("80402c"),
		"fill": Color("edd1c7"),
		"fx": Color("c76b4e"),
		"desc": "以多名低費士兵快速鋪場，靠數量優勢纏鬥擋路。",
		"terms": ["循環","纏鬥"]
	}
}

# Explicit primary keywords per card where special rules live in battle.gd / faction_cards.gd,
# supplemented automatically by data fields below so every card in B.CARDS has 1-3 keywords.
const CARD_OVERRIDES := {
	"old_witch": ["毒蝕","爆破"],
	"plague": ["毒蝕","爆破"],
	"corrosive_bile": ["毒蝕","破甲"],
	"healer": ["治療"],
	"guard": ["治療","重裝"],
	"bellbearer": ["治療"],
	"blood_tower": ["治療","吸血"],
	"farmer": ["產金","治療"],
	"bog_troll": ["再生","重裝"],
	"dire_hydra": ["再生","橫掃","重裝"],
	"sky_scavenger": ["飛行","再生"],
	"ghoul": ["再生","獵殺"],
	"glutton_nest": ["產金","再生"],
	"blood_attendant": ["吸血"],
	"leech_vine": ["吸血","遲緩"],
	"blood_altar": ["吸血","產金","加速"],
	"berserk_blood": ["吸血","加速"],
	"blood_cauldron": ["治療","獵殺"],
	"fire": ["灼燒","擊退"],
	"flaming_pitch": ["灼燒","爆破"],
	"long_dragon": ["灼燒","貫穿"],
	"arcane_shield": ["護盾"],
	"sigil_weaver": ["護盾"],
	"spellbreaker": ["護盾","獵殺"],
	"rune_sentinel": ["護盾","巡邏"],
	"arcane_golem": ["護盾","爆破"],
	"shieldguard": ["護甲"],
	"field_smithy": ["護甲"],
	"barricade": ["護甲"],
	"bonewall": ["護甲","召喚"],
	"artificer": ["維修"],
	"rune_workshop": ["維修"],
	"macebreaker": ["破甲"],
	"axe_thrower": ["破甲","遠射"],
	"ballista_tower": ["破甲","遠射"],
	"thorn_hound": ["反傷","衝鋒"],
	"thorn_dragon": ["反傷","重裝"],
	"bramble_wall": ["反傷","護甲"],
	"spell_mirror": ["反傷","遠射"],
	"chronomancer": ["暈眩","爆破"],
	"renegade_artificer": ["暈眩","爆破"],
	"gravity_well": ["暈眩","擊退"],
	"teleport_trap": ["暈眩","遲緩"],
	"sealed_coffin": ["暈眩"],
	"web_spinner": ["定身","遠射"],
	"net_hunter": ["遲緩","遠射"],
	"beekeeper": ["毒蝕","遲緩"],
	"mourning_maid": ["遲緩"],
	"time_field": ["遲緩"],
	"dread_howl": ["恐懼","加速"],
	"eyewing_dragon": ["恐懼","重裝"],
	"sleepless_belfry": ["淨化"],
	"counter_charge": ["擊退","暈眩","加速"],
	"wing_gust": ["擊退","爆破"],
	"warp_beacon": ["擊退"],
	"disgraced_lancer": ["衝鋒","暈眩"],
	"tusk_boar": ["衝鋒","暈眩"],
	"ox": ["衝鋒","攻城"],
	"pack_ambush": ["衝鋒"],
	"drummer": ["加速"],
	"charge_horn": ["加速"],
	"war_lodge": ["加速"],
	"levy": ["召喚","加速"],
	"assassin": ["潛行","獵殺"],
	"bandit": ["潛行","人海"],
	"phase_rider": ["潛行","相位"],
	"watchtower": ["偵查"],
	"observatory": ["偵查"],
	"astrolabe_surveyor": ["偵查","遠射"],
	"belly_eye": ["偵查","重裝"],
	"prism_mage": ["偵查","爆破"],
	"ward_guard": ["護盾","維修"],
	"ward_phalanx": ["護盾","爆破"],
	"aether_hound": ["相位","獵殺"],
	"blink_blade": ["相位"],
	"phase_shift": ["相位"],
	"hooknose_flyer": ["飛行"],
	"raven": ["飛行","攻城"],
	"hive_nest": ["召喚","飛行"],
	"necromancer": ["召喚","遠射"],
	"pallbearer": ["召喚","重裝"],
	"corpse_stitcher": ["召喚","治療"],
	"corpse_giant": ["召喚","重裝"],
	"mass_grave": ["召喚"],
	"ossuary": ["召喚"],
	"borrowed_bones": ["召喚"],
	"curse": ["召喚"],
	"monster_hatchery": ["召喚"],
	"mimic_egg": ["召喚","爆破"],
	"summon_trap": ["召喚"],
	"parasite_mite": ["召喚","人海"],
	"swarm_eruption": ["召喚","爆破"],
	"mirror_clone": ["召喚"],
	"chimera": ["召喚"],
	"oathless_imp": ["死志"],
	"mourning_shroud": ["死志"],
	"dark_wizard": ["死志","遠射"],
	"imp_bomb_runner": ["死志","爆破"],
	"arcane_archer": ["貫穿","偵查"],
	"orrery_walker": ["貫穿","遠射"],
	"chain_lightning": ["貫穿"],
	"reaper": ["橫掃"],
	"seal_bearer": ["橫掃","遠射"],
	"mob": ["橫掃","人海"],
	"rolling_boulder": ["橫掃","攻城"],
	"spearbow": ["遠射","人海"],
	"catapult": ["爆破","遠射"],
	"funeral_grenadier": ["爆破","遠射"],
	"dog_cannon": ["爆破","遠射"],
	"powder_barrel": ["爆破"],
	"blast_trap": ["爆破"],
	"arcane_tower": ["爆破","遠射"],
	"rain": ["爆破"],
	"farm": ["產金"],
	"mill": ["產金"],
	"harvest": ["產金"],
	"granary": ["產金"],
	"crystal": ["產金"],
	"mana_spring": ["產金","再生"],
	"grave": ["產金"],
	"mule_cart": ["產金"],
	"hook_collector": ["產金","獵殺"],
	"funeral_cottage": ["產金"],
	"soul_well": ["治療","加速"],
	"sacrifice": ["產金"],
	"grave_exchange": ["產金","召喚"],
	"mana_battery": ["產金","爆破"],
	"supply_depot": ["產金"],
	"bearded_imp": ["偷金"],
	"imp_burrow": ["召喚","偷金"],
	"mana_drain": ["偷金","爆破"],
	"devouring_maw": ["獵殺"],
	"vampire_hunter": ["獵殺","遠射"],
	"monster_hunter": ["獵殺"],
	"runaway_thrall": ["獵殺","人海"],
	"halberdier": ["獵殺"],
	"fishbeak": ["獵殺"],
	"twin_gambler": ["獵殺"],
	"seal_altar": ["召喚","恐懼"],
	"plague_bishop": ["遲緩","毒蝕","恐懼","重裝"],
	"funeral_monk": ["治療"],
	"spell_tide_magus": ["遠射"],
	"thorn_mother": ["反傷","重裝"],
	"gold_monster": ["重裝","人海"],
	"feral_mutation": ["重裝","獵殺"],
	"ram": ["攻城","重裝"],
	"gatebreaker": ["攻城","重裝"],
	"manor_retainer": ["巡邏","重裝"],
	"scarecrow": ["巡邏","護甲"],
	"knight": ["重裝"],
	"pouch_beast": ["重裝"],
	"hunter": ["遠射"],
	"arquebusier": ["遠射"],
	"shroud_arbalist": ["遠射"],
	"tower": ["遠射"],
	"militia": ["人海"],
	"skeleton": ["人海"]
}

const LORD_KEYWORDS := {
	"adventure": ["衝鋒","爆破"],
	"lion": ["召喚","重裝"],
	"iron": ["護甲","維修"],
	"harvest": ["產金","再生"],
	"mage": ["遠射","暈眩","遲緩"],
	"rune": ["遠射","召喚","爆破"],
	"underworld": ["遠射","召喚","人海"],
	"vampire": ["吸血","加速"],
	"beast": ["召喚","重裝"]
}

static func for_card(kind: String) -> Array[String]:
	if CARD_OVERRIDES.has(kind):
		var res: Array[String] = []
		for k: String in CARD_OVERRIDES[kind]: res.append(k)
		return res
	var B = load("res://balance.gd")
	if not B.CARDS.has(kind): return []
	var d: Dictionary = B.CARDS[kind]
	var out: Array[String] = []
	if d.has("dot_damage"): out.append("毒蝕")
	if d.get("support","") == "heal": out.append("治療")
	if d.has("regen_amount") or d.get("scavenger",false): out.append("再生")
	if d.has("lifesteal") or d.get("support","") == "tithe": out.append("吸血")
	if d.get("support","") == "shield" or d.has("shield") or d.has("spell_resist"): out.append("護盾")
	if d.get("support","") == "armor" or d.has("armor"): out.append("護甲")
	if d.get("ignore_armor",false): out.append("破甲")
	if d.get("support","") == "repair" or d.has("repair_amount"): out.append("維修")
	if d.has("thorns") or d.has("reflect_damage"): out.append("反傷")
	if d.has("stun_on_hit") or d.has("charge_stun"): out.append("暈眩")
	if d.has("root") or d.has("root_on_hit"): out.append("定身")
	if d.has("net_slow") or d.get("support","") == "slow": out.append("遲緩")
	if d.has("roar_fear"): out.append("恐懼")
	if d.get("support","") == "cleanse": out.append("淨化")
	if d.has("knockback") or d.has("pushback"): out.append("擊退")
	if d.has("charge_damage") or d.get("grant_charge",false): out.append("衝鋒")
	if d.get("support","") == "haste" or d.has("inspire_duration"): out.append("加速")
	if d.get("stealth",false): out.append("潛行")
	if d.has("reveal_radius") or d.get("support","") == "range": out.append("偵查")
	if d.get("phase",false) or d.has("blink_step") or d.has("phase_shift"): out.append("相位")
	if d.get("flying",false): out.append("飛行")
	if d.has("spawn_kind") or d.has("on_death_spawn") or d.has("ally_death_spawn") or d.get("split_on_kill",false): out.append("召喚")
	if d.get("last_stand",false) or d.get("soul_bargain",false) or d.get("suicide_blast",false): out.append("死志")
	if d.get("pierce",false) or d.has("hops"): out.append("貫穿")
	if d.get("splash","") == "column" or d.get("spread",false) or d.get("rolling",false): out.append("橫掃")
	if d.has("area_damage") or d.has("explosion_damage") or d.get("lob",false): out.append("爆破")
	if d.has("income") or d.get("shuttle",false) or d.has("kill_income") or d.has("death_income") or d.has("depot_refund"): out.append("產金")
	if d.has("steal_gold") or d.has("drain_gold_per_hit") or d.has("execute_hp"): out.append("偷金")
	if d.has("bonus_vs") or d.has("damage_roll") or d.get("hunt_nearest",false): out.append("獵殺")
	if d.has("structure_mult") or d.get("hits","") == "buildings": out.append("攻城")
	if d.get("patrol",false): out.append("巡邏")
	if out.is_empty():
		if d.get("projectile",false) or d.get("range",47.0) >= 140.0: out.append("遠射")
		elif d.get("count",1) >= 4: out.append("人海")
		else: out.append("重裝")
	return out.slice(0, 3)

static func for_lord(lord: String) -> Array[String]:
	if LORD_KEYWORDS.has(lord):
		var res: Array[String] = []
		for k: String in LORD_KEYWORDS[lord]: res.append(k)
		return res
	var B = load("res://balance.gd")
	if B.is_minion(lord):
		return for_card(B.MINION_LORDS[lord].card)
	return ["重裝"]

static func color_of(kw: String) -> Color:
	return KEYWORDS.get(kw, {}).get("color", Color("5a4630"))

static func fill_of(kw: String) -> Color:
	return KEYWORDS.get(kw, {}).get("fill", Color("e6d8b8"))

static func fx_of(kw: String) -> Color:
	return KEYWORDS.get(kw, {}).get("fx", Color("8a6f4a"))

static func hex_of(kw: String) -> String:
	return color_of(kw).to_html(false)

static func desc_of(kw: String) -> String:
	return KEYWORDS.get(kw, {}).get("desc", "")

# One-line summary of a card's keywords for plain-text tooltips.
static func tag_line(kind: String) -> String:
	var kws := for_card(kind)
	if kws.is_empty(): return ""
	return "關鍵詞：" + "".join(kws.map(func(k: String) -> String: return "【%s】" % k))

# Glossary block explaining each keyword on a card or lord.
static func glossary_lines(kws: Array[String]) -> Array[String]:
	var lines: Array[String] = []
	for k: String in kws:
		if KEYWORDS.has(k):
			lines.append("【%s】%s" % [k, KEYWORDS[k].desc])
	return lines

const STAT_TERMS := [
	["生命", "24783c"],
	["傷害", "962436"],
	["方格區域", "325869"],
	["橫向直線", "325869"],
	["縱向直線", "325869"],
	["範圍半徑", "325869"],
	["半徑", "325869"],
	["距離", "325869"],
	["移速", "9e6810"],
	["攻速", "9e6810"],
	["速度", "9e6810"],
	["落下時間", "485e6e"],
	["攻擊間隔", "485e6e"],
	["冷卻", "485e6e"],
]

# Convert plain text into BBCode with coloured 【關鍵詞】 badges, mechanic terms, and stat labels.
static func colorize_bbcode(text: String) -> String:
	var out := text
	# First colourise explicit 【關鍵詞】 tags.
	for kw: String in KEYWORDS:
		var tag := "【%s】" % kw
		if out.contains(tag):
			out = out.replace(tag, "[color=#%s]%s[/color]" % [hex_of(kw), tag])
	# Next colourise mechanic phrases inside the lines (skipping already-coloured tags and card names).
	for kw: String in KEYWORDS:
		var hex := hex_of(kw)
		for term: String in KEYWORDS[kw].get("terms", []):
			if term.length() < 2: continue
			out = _highlight_term(out, term, hex)
	for pair: Array in STAT_TERMS:
		out = _highlight_term(out, pair[0], pair[1])
	return out

static func _highlight_term(src: String, term: String, hex: String) -> String:
	var lines := src.split("\n")
	for i: int in range(lines.size()):
		if lines[i].begins_with("關鍵詞："): continue
		if lines[i].begins_with("[color=#") and lines[i].contains("】[/color]"): continue
		if i == 0 and lines[i].contains(" 金幣 · 冷卻 "):
			lines[i] = _highlight_in_segment(lines[i], term, hex)
			continue
		lines[i] = _highlight_in_segment(lines[i], term, hex)
	return "\n".join(lines)

static func _highlight_in_segment(segment: String, term: String, hex: String) -> String:
	var line := segment
	var search_from := 0
	while true:
		var idx := line.find(term, search_from)
		if idx < 0: break
		var before := line.substr(0, idx)
		if before.count("[color=") == before.count("[/color]"):
			var rep := "[color=#%s]%s[/color]" % [hex, term]
			line = before + rep + line.substr(idx + term.length())
			search_from = idx + rep.length()
		else:
			search_from = idx + term.length()
	return line

# Draw compact illuminated-manuscript keyword cartouches on a card face.
static func draw_card_pills(g, rect: Rect2, kind: String, blocked: bool = false) -> void:
	var kws := for_card(kind).slice(0, 2)
	if kws.is_empty(): return
	var s: Vector2 = rect.size
	var scale_k: float = clampf(s.x / 124.0, 0.76, 1.25)
	var cy: float = rect.position.y + s.y * 0.814
	var pill_h: float = clampf(s.y * 0.094, 12.5, 18.0)
	var fsize: int = maxi(10, roundi(12.0 * scale_k))
	var pad_x: float = 13.0 * scale_k
	var gap: float = 4.5 * scale_k
	var widths: Array[float] = []
	var total_w := 0.0
	for k: String in kws:
		var tw: float = g.font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + pad_x
		widths.append(tw)
		total_w += tw
	total_w += gap * float(kws.size() - 1)
	var x: float = rect.position.x + (s.x - total_w) * 0.5
	for i: int in range(kws.size()):
		var kw: String = kws[i]
		var w: float = widths[i]
		var pr := Rect2(x, cy - pill_h * 0.5, w, pill_h)
		var col := Color("3b3b3b") if blocked else color_of(kw)
		var base_fill := Color("efe1be").lerp(fill_of(kw), 0.46)
		var fill := Color("a8a8a8", 0.78) if blocked else Color(base_fill, 0.94)
		_draw_cartouche(g, pr, fill, col, kw, fsize, 2.4 * scale_k, not blocked)
		x += w + gap

# Draw larger manuscript keyword cartouches in the Codex / Battle Info / Battle Hand strip.
static func draw_badges(g, pos: Vector2, kws: Array[String], fsize: int = 15) -> float:
	var x := pos.x
	var h := float(fsize) + 8.0
	for kw: String in kws:
		var label := "· %s ·" % kw
		var w: float = g.font.get_string_size(kw, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + 20.0
		var r := Rect2(x, pos.y - h + 4.5, w, h)
		var col := color_of(kw)
		var fill := Color("efe1be").lerp(fill_of(kw), 0.50)
		_draw_cartouche(g, r, fill, col, kw, fsize, 3.0, true)
		x += w + 6.0
	return x - pos.x

static func _draw_cartouche(g, r: Rect2, fill: Color, col: Color, text: String, fsize: int, cut: float, ornate: bool) -> void:
	var p := r.position
	var s := r.size
	var pts := PackedVector2Array([
		p+Vector2(cut,0), p+Vector2(s.x-cut,0), p+Vector2(s.x,cut), p+Vector2(s.x,s.y-cut),
		p+Vector2(s.x-cut,s.y), p+Vector2(cut,s.y), p+Vector2(0,s.y-cut), p+Vector2(0,cut)
	])
	if ornate:
		var sh := PackedVector2Array()
		for pt: Vector2 in pts: sh.append(pt + Vector2(0.8, 1.2))
		g.draw_colored_polygon(sh, Color("261b11", 0.16))
	g.draw_colored_polygon(pts, fill)
	if ornate:
		g.draw_line(p+Vector2(cut+1,1.2), p+Vector2(s.x-cut-1,1.2), Color("fff7df",0.58), 1.0, true)
	var rim := pts.duplicate()
	rim.append(rim[0])
	g.draw_polyline(rim, Color(col, 0.76), 1.1, true)
	if ornate:
		var my := p.y + s.y * 0.5
		for dx: float in [3.2, s.x - 3.2]:
			var cx := p.x + dx
			g.draw_colored_polygon(PackedVector2Array([
				Vector2(cx-1.5,my), Vector2(cx,my-1.5), Vector2(cx+1.5,my), Vector2(cx,my+1.5)
			]), Color(col, 0.82))
	var by := p.y + s.y * 0.5 + float(fsize) * 0.36 + 0.5
	g.draw_string(g.font, Vector2(p.x, by), text, HORIZONTAL_ALIGNMENT_CENTER, s.x, fsize, col)
