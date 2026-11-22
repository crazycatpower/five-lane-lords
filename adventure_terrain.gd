extends RefCounted
# 冒險五十關的地形與守將（使用者 2026-11-21：盡量設計各種地形，搭配肉鴿模式的敵人）。
# campaign_catalog.gd 建好關卡後呼叫 apply()，用這裡的資料蓋掉路數、季節、地形與敵人牌組；
# 關卡的劇情、教學文字與新卡仍寫在 campaign_catalog.gd。
# 每關欄位（都可省略）：
#   name      地形名稱（關卡資訊顯示）
#   rows      戰場列數 5 或 6；lanes 開放的路
#   season    spring / summer / autumn / winter（season.gd）
#   water_lanes / water_cols / water_cells / wind_lanes / blocked   地形（battle.apply_field_mutator）
#             water_cells、blocked 是 [欄, 路]，欄從我方（左）數起
#   foe_buildings  敵方預築 [欄, 路, 卡]，欄從敵方後排數起（0＝敵方城牆前那欄）
#   ruler     守將：肉鴿模式的小怪領主（roguelike_catalog.MINIONS），牌組直接用他在肉鴿的牌組；
#             省略則沿用 campaign_catalog 的守將。守將是正式領主（LORDS）時沿用關卡自己寫的牌組。
#   night     入夜時間（秒），讓天黑得比平常早
const SIX := [0,1,2,3,4,5]
const MAX_FEATURES := 2
const FIVE := [0,1,2,3,4]
const MID := [1,2,3]

const STAGES := {
	# ---- 一・晨麥古道：新兵訓練（地形保持單純，教學腳本照常） ----
	"w1_1":{"name":"麥田小徑","lanes":[2],"season":"spring"},
	"w1_2":{"name":"麥田小徑","lanes":[2],"season":"spring"},
	"w1_3":{"name":"自家麥田","lanes":[2],"season":"spring"},
	"w1_4":{"name":"木拒馬隘口","lanes":[2],"season":"spring"},
	"w1_5":{"name":"稻草人田","lanes":[2],"season":"summer","ruler":"card_enemy_scarecrow"},
	"w1_6":{"name":"三岔城門","lanes":MID,"season":"summer"},
	"w1_7":{"name":"強盜糧道","lanes":MID,"season":"summer"},
	"w1_8":{"name":"三岔路口","lanes":MID,"season":"autumn"},
	"w1_9":{"name":"攻城坡道","lanes":MID,"season":"autumn","slope":{"high":1}},
	"w1_10":{"name":"豐收大道","lanes":FIVE,"season":"autumn","wind_lanes":[2],"wind_shift":{"interval":50.0}},
	# ---- 二・運河渡口：水路與渡河 ----
	"w2_1":{"name":"單橋渡口","lanes":MID,"season":"summer","water_cells":[[4,1],[4,3]],"ruler":"shield_sergeant"},
	"w2_2":{"name":"雙塔哨口","lanes":[0,1,3,4],"season":"summer","foe_buildings":[[2,1,"tower"],[2,3,"tower"]],"ruler":"tower_warden"},
	"w2_3":{"name":"沼澤兩翼","lanes":FIVE,"season":"autumn","water_lanes":[0,4],"ruler":"hunter_master"},
	"w2_4":{"name":"河灘快道","rows":6,"lanes":SIX,"season":"summer","wind_lanes":[1],"wind_left_lanes":[4],"ruler":"card_enemy_granary","wind_shift":{"interval":40.0}},
	"w2_5":{"name":"渡口要塞","lanes":MID,"season":"autumn","blocked":[[3,1],[3,3]],"foe_buildings":[[1,1,"tower"],[1,3,"tower"],[2,1,"barricade"],[2,2,"barricade"],[2,3,"barricade"]],"ruler":"knight_commander"},
	"w2_6":{"name":"三道長堤","lanes":FIVE,"season":"summer","night":270.0,"ruler":"drummer_major","sluice":{"lanes":[1,3,2],"interval":35.0}},
	"w2_7":{"name":"槍弓校場","lanes":MID,"season":"autumn","ruler":"mob_foreman"},
	"w2_8":{"name":"水車大河","lanes":FIVE,"season":"summer","water_cols":[4],"ruler":"card_enemy_mill"},
	"w2_9":{"name":"蘆葦沼","rows":6,"lanes":SIX,"season":"summer","water_cells":[[3,0],[4,1],[5,3],[3,4],[4,5],[5,2]],"ruler":"bandit_chief","gusts":{"interval":30.0}},
	"w2_10":{"name":"紅獅水門","lanes":FIVE,"season":"autumn","sluice":{"lanes":[0,4,2],"interval":40.0}},
	# ---- 三・星軌高塔：岩石、雪與窄廊 ----
	"w3_1":{"name":"水晶礦脈","rows":6,"lanes":SIX,"season":"winter","blocked":[[4,1],[4,4],[3,2]],"foe_buildings":[[1,0,"crystal"],[1,5,"crystal"]],"ruler":"card_enemy_crystal"},
	"w3_2":{"name":"護盾迴廊","lanes":[1,2,3,4],"season":"spring","ruler":"card_enemy_arcane_shield","portals":[[[3,1],[5,4]],[[3,4],[5,1]]]},
	"w3_3":{"name":"法陣棋盤","lanes":FIVE,"season":"spring","blocked":[[3,0],[5,0],[4,1],[3,2],[5,2],[4,3],[3,4],[5,4]],"foe_buildings":[[3,1,"blast_trap"],[3,3,"blast_trap"]],"ruler":"trap_weaver"},
	"w3_4":{"name":"閃影雙廊","lanes":[1,3],"season":"winter","ruler":"card_enemy_blink_blade"},
	"w3_5":{"name":"符文禁苑","lanes":MID,"season":"winter","foe_buildings":[[3,1,"blast_trap"],[3,3,"teleport_trap"]],"rune_cells":[[2,1],[2,3]],"portals":[[[4,1],[4,3]]]},
	"w3_6":{"name":"箭塔長階","rows":6,"lanes":[1,2,3,4],"season":"spring","wind_left_lanes":[3],"ruler":"card_enemy_arcane_archer","slope":{"high":1},"rune_cells":[[2,2],[2,3]],"wind_shift":{"interval":35.0}},
	"w3_7":{"name":"凝滯雪廊","lanes":FIVE,"season":"winter","ruler":"card_enemy_time_field"},
	"w3_8":{"name":"魔像鍛爐","lanes":MID,"season":"winter","blocked":[[4,1],[4,3]],"ruler":"golem_smith"},
	"w3_9":{"name":"雷鳴尖頂","rows":6,"lanes":SIX,"season":"spring","wind_lanes":[0],"wind_left_lanes":[5],"ruler":"card_enemy_chain_lightning","slope":{"high":1},"wind_shift":{"interval":35.0},"storm":{"interval":16.0}},
	"w3_10":{"name":"星軌鐘頂","lanes":FIVE,"season":"winter","blocked":[[4,2]],"slope":{"high":1},"rune_cells":[[3,1],[3,3]],"storm":{"interval":22.0}},
	# ---- 四・冥霧墓澤：泥沼與長夜 ----
	"w4_1":{"name":"墓碑野地","lanes":MID,"season":"autumn","water_cells":[[3,1],[5,3]],"ruler":"card_enemy_grave","mud_cells":[[4,1],[4,2],[4,3]]},
	"w4_2":{"name":"白骨行軍","rows":6,"lanes":[1,2,3,4],"season":"autumn","ruler":"skeleton_king","fog":5,"fog_drift":true},
	"w4_3":{"name":"瘟疫泥沼","lanes":FIVE,"season":"autumn","water_lanes":[1,3],"ruler":"card_enemy_plague","mud_cells":[[3,0],[5,2],[3,4]]},
	"w4_4":{"name":"鴉群枯林","rows":6,"lanes":SIX,"season":"winter","ruler":"raven_mother"},
	"w4_5":{"name":"冥府雙塚","lanes":MID,"season":"autumn","foe_buildings":[[1,1,"grave"],[1,3,"grave"]]},
	"w4_6":{"name":"早降的夜","lanes":FIVE,"season":"winter","ruler":"necro_adept","fog":4,"fog_drift":true},
	"w4_7":{"name":"骨牆渡口","lanes":FIVE,"season":"autumn","water_lanes":[1,3],"ruler":"card_enemy_bonewall"},
	"w4_8":{"name":"屍山","lanes":MID,"season":"autumn","ruler":"card_enemy_corpse_giant","fog":5,"mud_cells":[[4,2]],"fog_drift":true},
	"w4_9":{"name":"血霧孤塔","rows":6,"lanes":[1,2,3,4],"season":"autumn","water_cells":[[4,1],[4,4]],"ruler":"blood_prior","fog":4,"fog_drift":true},
	"w4_10":{"name":"血月尖塔","lanes":FIVE,"season":"winter","slope":{"high":1}},
	# ---- 五・巨獸王城：峽谷與城牆 ----
	"w5_1":{"name":"貪食河谷","lanes":MID,"season":"summer","water_cols":[4],"ruler":"card_enemy_glutton_nest"},
	"w5_2":{"name":"厚皮獸道","lanes":MID,"season":"summer","blocked":[[4,1],[4,3]],"ruler":"card_enemy_pouch_beast"},
	"w5_3":{"name":"峽谷獸道","lanes":[2],"season":"summer","ruler":"card_enemy_thorn_hound"},
	"w5_4":{"name":"飛魔斷崖","rows":6,"lanes":SIX,"season":"autumn","blocked":[[4,0],[4,5]],"ruler":"card_enemy_hooknose_flyer","slope":{"high":1},"gusts":{"interval":28.0}},
	"w5_5":{"name":"龍脊獸巢","lanes":FIVE,"season":"summer","lava_cells":[[4,0],[4,4],[5,2]],"eruption":{"interval":24.0}},
	"w5_6":{"name":"巨魔沼澤","lanes":MID,"season":"autumn","water_cells":[[3,1],[4,2],[5,3]],"ruler":"card_enemy_bog_troll"},
	"w5_7":{"name":"龍吼峽谷","rows":6,"lanes":SIX,"season":"summer","wind_lanes":[2],"wind_left_lanes":[3],"ruler":"card_enemy_eyewing_dragon","eruption":{"interval":20.0},"wind_shift":{"interval":30.0}},
	"w5_8":{"name":"狂蜥巢","lanes":MID,"season":"autumn","ruler":"card_enemy_dire_hydra","lava_cells":[[4,1],[4,3]]},
	"w5_9":{"name":"王城外廓","rows":6,"lanes":SIX,"season":"winter","water_cols":[5],"foe_buildings":[[1,1,"ballista_tower"],[1,4,"ballista_tower"]],"ruler":"catapult_engineer","slope":{"high":1}},
	"w5_10":{"name":"王都鐵壁","lanes":FIVE,"season":"winter","slope":{"high":1},"eruption":{"interval":30.0}},
}

# Lay this stage's terrain and garrison over the catalog entry.
static func apply(d: Dictionary) -> void:
	var t: Dictionary = STAGES.get(d.id,{})
	if t.is_empty(): return
	var Rogue = load("res://roguelike_catalog.gd")
	d.rows = int(t.get("rows",5))
	if t.has("lanes"): d.active_lanes = t.lanes.duplicate()
	d.season = String(t.get("season",""))
	d.terrain = String(t.get("name",""))
	if t.has("night"): d.night_start_override = float(t.night)
	var ruler := String(t.get("ruler",""))
	if not ruler.is_empty():
		d.enemy_lord = ruler
		if Rogue.MINIONS.has(ruler): d.enemy_deck = Rogue.foe_deck(ruler)
	var field := {}
	for key: String in ["water_lanes","water_cols","water_cells","wind_lanes","wind_left_lanes","rune_cells","portals","mud_cells","lava_cells"]:
		if t.has(key): field[key] = t[key].duplicate(true)
	for key: String in ["slope","sluice","eruption","wind_shift","gusts","storm","blizzard"]:
		if t.has(key): field[key] = t[key].duplicate(true)
	if t.has("fog"): field.fog = int(t.fog)
	if t.has("fog_drift"): field.fog_drift = true
	# 同一關最多兩種地圖機制（使用者 2026-11-22），其餘依重要性刪掉；季節規則照常。
	field = preload("res://map_mech.gd").trim(field,MAX_FEATURES)
	if t.has("blocked"): field.blocked_cells = t.blocked.duplicate(true)
	if t.has("foe_buildings"): field.enemy_buildings = t.foe_buildings.duplicate(true)
	if not field.is_empty():
		# The terrain replaces the catalog's own field layout so the two never pile up.
		d.mutators = [field]

# One line for the stage panel: rows, season and the notable ground.
static func summary(d: Dictionary) -> String:
	var parts: Array = []
	var name := String(d.get("terrain",""))
	if not name.is_empty(): parts.append(name)
	var Season = preload("res://season.gd")
	var s: String = Season.label(String(d.get("season","")))
	if not s.is_empty(): parts.append(s)
	for m: Dictionary in d.get("mutators",[]):
		if not m.get("water_lanes",[]).is_empty() or not m.get("water_cols",[]).is_empty() or not m.get("water_cells",[]).is_empty(): parts.append("水路")
		if not m.get("wind_lanes",[]).is_empty() or not m.get("wind_left_lanes",[]).is_empty(): parts.append("順風道")
		if not m.get("blocked_cells",[]).is_empty(): parts.append("巨石")
		parts.append_array(preload("res://map_mech.gd").labels(m))
	return " · ".join(parts)

# The hover text: the season's rule and what each kind of ground does.
static func details(d: Dictionary) -> String:
	var lines: Array = []
	var rule: String = preload("res://season.gd").rule_text(String(d.get("season","")))
	if not rule.is_empty(): lines.append(rule)
	lines.append("%d 路開放（戰場 %d 列）。" % [d.get("active_lanes",[]).size(),int(d.get("rows",5))])
	for m: Dictionary in d.get("mutators",[]):
		if not m.get("water_lanes",[]).is_empty() or not m.get("water_cols",[]).is_empty() or not m.get("water_cells",[]).is_empty(): lines.append("水路：不能蓋建築，地面部隊經過時移速 -60%（飛行不受影響）。")
		if not m.get("wind_lanes",[]).is_empty(): lines.append("順風道（→）：往右走的部隊（我方）移速升一檔。")
		if not m.get("wind_left_lanes",[]).is_empty(): lines.append("順風道（←）：往左走的部隊（敵方）移速升一檔。")
		if not m.get("blocked_cells",[]).is_empty(): lines.append("巨石：那一格不能蓋建築，部隊照樣能走。")
		if not m.get("enemy_buildings",[]).is_empty(): lines.append("敵方開局已經蓋好幾座建築。")
		lines.append_array(preload("res://map_mech.gd").explain(m))
	return "
".join(lines)

# Errors for quick_test: unknown stages, rulers, cards, seasons or cells off the field.
static func validate(stage_ids: Array) -> Array[String]:
	var B = preload("res://balance.gd")
	var Rogue = load("res://roguelike_catalog.gd")
	var Season = preload("res://season.gd")
	var errors: Array[String] = []
	for id: String in STAGES:
		var t: Dictionary = STAGES[id]
		if not id in stage_ids: errors.append("terrain for unknown stage "+id)
		var rows := int(t.get("rows",5))
		if not rows in [5,6]: errors.append(id+": rows must be 5 or 6")
		for lane in t.get("lanes",[]):
			if not int(lane) in range(rows): errors.append(id+": lane off the field "+str(lane))
		if not Season.valid(String(t.get("season",""))): errors.append(id+": unknown season")
		var ruler := String(t.get("ruler",""))
		if not ruler.is_empty() and not Rogue.MINIONS.has(ruler) and not B.LORDS.has(ruler): errors.append(id+": unknown ruler "+ruler)
		for key: String in ["water_cells","blocked","rune_cells","mud_cells","lava_cells"]:
			for c in t.get(key,[]):
				if c.size() != 2 or not int(c[0]) in range(9) or not int(c[1]) in range(rows): errors.append(id+": bad cell "+str(c))
		for b in t.get("foe_buildings",[]):
			if b.size() != 3 or not B.CARDS.has(b[2]) or B.CARDS[b[2]].type != "building": errors.append(id+": bad building "+str(b))
	for id in stage_ids:
		if not STAGES.has(id): errors.append("stage without terrain "+str(id))
	return errors
