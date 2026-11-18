extends SceneTree
## Director screenplay for Classic Red Lion vs Classic Underworld showcase video.
## Runs in two modes:
##   --verify : fast headless rule-check + prints exact timestamps & writes cue sheet
##   (default): live 60fps SceneTree render for Godot Movie Maker (--write-movie --fixed-fps 60)
const Battle = preload("res://battle.gd")
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Recorder = preload("res://match_recorder.gd")

const MATCH_SEED := 12

var verify_only := false
var game
var model
var ready := false
var tick := 0
var cue_idx := 0
var post_end_frames := 330 # 5.5s after victory for finisher slow-mo + full animated victory stats page
var cues: Array = []
var executed_log: Array = []

static func cell_pos(col: float, lane: int) -> Vector2:
	return L.GRID_ORIGIN + Vector2((col + 0.5) * L.CELL_SIZE.x, (float(lane) + 0.5) * L.CELL_SIZE.y)

static func build_screenplay() -> Array:
	return [
		{"t": 0.4, "kind": "chapter", "title": "經典對決｜紅獅王國 × 冥府領主", "sub": "100% 原生規則實戰編劇 · 高密度攻防節奏示範", "dur": 2.0},
		{"t": 1.8, "kind": "play", "team": 0, "card": "farm", "pos": cell_pos(1, 2),
			"spot": "常駐經濟核心 · 產出金幣並將我方領地向前推進至第 2 欄", "zoom": 1.22,
			"sub": "開局搶佔中路農田：種田不只產金，更是搶占前線部署格！"},
		{"t": 3.4, "kind": "play", "team": 0, "card": "farmer", "pos": cell_pos(0, 2),
			"spot": "順路耕耘農田回血 100，並讓產金效率翻倍 15 秒！", "zoom": 1.22},
		{"t": 4.8, "kind": "play", "team": 1, "card": "grave", "pos": cell_pos(7, 2),
			"spot": "冥府常駐經濟 · 本路每有單位陣亡皆會加速產金", "zoom": 1.22,
			"sub": "冥府領主立刻立起前線墓碑，準備用死亡加速幽冥經濟"},
		{"t": 6.5, "kind": "play", "team": 0, "card": "healer", "pos": cell_pos(0, 2),
			"spot": "後排治療支援單位，持續維持前排血線與淨化減傷", "zoom": 1.20},
		{"t": 8.5, "kind": "play", "team": 1, "card": "skeleton", "pos": cell_pos(7, 2),
			"spot": "低費六隻骷髏兵海中路壓境，試探紅獅正面防線", "zoom": 1.20},
		{"t": 10.5, "kind": "play", "team": 0, "card": "shieldguard", "pos": cell_pos(1, 2),
			"spot": "每次受擊減傷 10 點！三人重盾穩穩頂住中線骷髏海", "zoom": 1.24},
		{"t": 13.5, "kind": "play", "team": 0, "card": "hunter", "pos": cell_pos(0, 2),
			"spot": "三名遠程獵戶站位農田後方，火力覆蓋地面與空中來襲", "zoom": 1.24},
		{"t": 15.0, "kind": "play", "team": 1, "card": "raven", "pos": cell_pos(8, 2),
			"spot": "高速飛行單位無視近戰阻擋，直撲我方中路農田！", "zoom": 1.25,
			"sub": "空襲警報！冥府烏鴉群高速俯衝，鎖定我方中路農田！"},
		{"t": 19.2, "kind": "play", "team": 0, "card": "rain", "pos": cell_pos(1.6, 2),
			"spot": "獵戶齊射後紅獅領主親甩箭雨！140 傷瞬間殲滅剩餘烏鴉群", "zoom": 1.26,
			"sub": "獵戶迎空攔截＋領主精準箭雨補刀！烏鴉全滅、農田穩穩守住！"},
		{"t": 22.0, "kind": "chapter", "title": "第一幕 · 紅獅鐵三角 × 幽冥毒霧", "sub": "戰鼓加速推進 · 食屍鬼與毒霧正面交鋒", "dur": 2.0},
		{"t": 23.0, "kind": "play", "team": 1, "card": "plague", "pos": cell_pos(2.5, 2),
			"spot": "藍方領主擲出瘟疫毒霧，企圖腐蝕我方前排並擴散毒傷", "zoom": 1.22,
			"sub": "冥府領主擲出劇毒瘟疫！草藥婆持續淨化回血穩住盾衛陣線"},
		{"t": 25.5, "kind": "play", "team": 0, "card": "drummer", "pos": cell_pos(0, 2),
			"spot": "登場與每 10 秒擊鼓！全體友軍移速攻速同步升檔", "zoom": 1.24},
		{"t": 28.0, "kind": "play", "team": 1, "card": "grave", "pos": cell_pos(8, 2),
			"spot": "", "zoom": 1.0, "silent_card": true},
		{"t": 30.0, "kind": "play", "team": 0, "card": "farm", "pos": cell_pos(0, 0),
			"spot": "", "zoom": 1.0, "silent_card": true,
			"sub": "趁戰鼓壓線在上路開闢第二塊農田，雙田加速金幣滾動"},
		{"t": 32.5, "kind": "play", "team": 0, "card": "farmer", "pos": cell_pos(0, 0),
			"spot": "", "zoom": 1.0, "silent_card": true},
		{"t": 37.0, "kind": "play", "team": 1, "card": "curse", "pos": cell_pos(3.8, 2),
			"spot": "死亡詛咒籠罩戰團：陣亡者將轉為藍方骷髏重新站起", "zoom": 1.22},
		{"t": 39.5, "kind": "play", "team": 0, "card": "shieldguard", "pos": cell_pos(1, 2),
			"spot": "", "zoom": 1.0, "silent_card": true},
		{"t": 44.0, "kind": "play", "team": 0, "card": "healer", "pos": cell_pos(0, 2),
			"spot": "", "zoom": 1.0, "silent_card": true,
			"sub": "鐵三角站位成形，前排承傷兼治療穩住中線節奏"},
		{"t": 46.5, "kind": "chapter", "title": "第二幕 · 死靈雙法與火罐爆破", "sub": "招魂法師 × 黑暗巫師進逼 · 高爆火罐正面轟殺敵陣", "dur": 2.0},
		{"t": 47.5, "kind": "play", "team": 1, "card": "necromancer", "pos": cell_pos(7, 2),
			"spot": "登場即召喚 3 名骷髏，且每 10 秒自動再招魂推進", "zoom": 1.24},
		{"t": 50.5, "kind": "play", "team": 0, "card": "farm", "pos": cell_pos(0, 4),
			"spot": "", "zoom": 1.0, "silent_card": true,
			"sub": "下路第三塊農田落成，三田產金供給即將展開的猛攻"},
		{"t": 54.0, "kind": "play", "team": 0, "card": "hunter", "pos": cell_pos(0, 2),
			"spot": "", "zoom": 1.0, "silent_card": true},
		{"t": 60.5, "kind": "play", "team": 1, "card": "dark_wizard", "pos": cell_pos(7, 2),
			"spot": "噬魂暗影巫師參戰！遭致命傷會吞噬友軍續命再生", "zoom": 1.24},
		{"t": 67.0, "kind": "play", "team": 0, "card": "fire", "pos": cell_pos(6.9, 2),
			"spot": "紅獅王牌爆破法術！370 高傷轟殺雙法師與前線骨架", "zoom": 1.25,
			"sub": "抓準敵軍法師與骷髏齊聚，火罐精準轟爆重創冥府陣線！"},
		{"t": 70.0, "kind": "play", "team": 0, "card": "farmer", "pos": cell_pos(0, 4),
			"spot": "", "zoom": 1.0, "silent_card": true},
		{"t": 74.0, "kind": "play", "team": 0, "card": "drummer", "pos": cell_pos(0, 2),
			"spot": "", "zoom": 1.0, "silent_card": true},
		{"t": 78.5, "kind": "play", "team": 0, "card": "shieldguard", "pos": cell_pos(1, 2),
			"spot": "", "zoom": 1.0, "silent_card": true,
			"sub": "紅獅穩步補充前排，藍方正在後方蓄積終極組合能量！"},
		{"t": 84.0, "kind": "play", "team": 0, "card": "rain", "pos": cell_pos(7.0, 2),
			"spot": "", "zoom": 1.12, "silent_card": true},
		{"t": 90.0, "kind": "chapter", "title": "第三幕 · 冥府雙重總攻 × 紅獅奧義", "sub": "腐屍巨人配亡者大軍壓境 · 玩家啟動【Q】領主大招絕地反攻", "dur": 2.0},
		{"t": 92.0, "kind": "play", "team": 1, "card": "corpse_giant", "pos": cell_pos(7, 2),
			"spot": "1500 血冥府巨獸緩步前壓！每損 25% 生命爆出 4 名骷髏", "zoom": 1.26,
			"sub": "冥府終極推線組合！腐屍巨人領銜前頂，後方醞釀亡者大軍夾擊！"},
		{"t": 103.0, "kind": "play", "team": 0, "card": "healer", "pos": cell_pos(0, 2),
			"spot": "", "zoom": 1.0, "silent_card": true,
			"sub": "草藥婆全力治療前線，但腐屍巨人已帶著壓迫感一步步逼近！"},
		{"t": 110.0, "kind": "play", "team": 0, "card": "farmer", "pos": cell_pos(0, 4),
			"spot": "", "zoom": 1.0, "silent_card": true},
		{"t": 116.5, "kind": "play", "team": 0, "card": "drummer", "pos": cell_pos(0, 2),
			"spot": "", "zoom": 1.0, "silent_card": true},
		{"t": 124.0, "kind": "skill", "team": 1, "pos": cell_pos(7.5, 2),
			"sub": "冥府領主配合巨人發動【亡者大軍】！雙墓碑齊爆八名骷髏夾擊！"},
		{"t": 135.0, "kind": "play", "team": 1, "card": "plague", "pos": cell_pos(1.8, 2),
			"spot": "", "zoom": 1.0, "silent_card": true,
			"sub": "巨人殺到紅獅門前加上劇毒瘟疫！中路防線全面告急！"},
		{"t": 136.5, "kind": "ult_cue", "team": 0, "pos": cell_pos(0.5, 2),
			"sub": "危急時刻！玩家點擊右下角【Q】——紅獅領主準備發動奧義！"},
		{"t": 138.3, "kind": "skill", "team": 0, "pos": cell_pos(0.5, 2),
			"sub": "★ 玩家領主大招【獅王號令】發動！金輝光束貫穿五路，重裝騎士齊降！"},
		{"t": 141.5, "kind": "chapter", "title": "終　幕 · 攻城槌重裝突破破門", "sub": "五路騎士護航清場 · 攻城槌粉碎冥府城門迎來絕殺", "dur": 2.0},
		{"t": 143.5, "kind": "play", "team": 0, "card": "ram", "pos": cell_pos(0, 2),
			"spot": "紅獅終結王牌！四名民兵護航攻城槌直搗藍方中路城門", "zoom": 1.24,
			"sub": "王牌「攻城槌」重裝進軍！乘著騎士大軍清出的坦途直逼冥府城門！"},
		{"t": 166.0, "kind": "play", "team": 0, "card": "shieldguard", "pos": cell_pos(0, 2),
			"spot": "", "zoom": 1.0, "silent_card": true,
			"sub": "重裝盾衛與民兵並肩護衛攻城槌全速推進！"},
		{"t": 182.0, "kind": "play", "team": 1, "card": "ghoul", "pos": cell_pos(8, 2),
			"spot": "", "zoom": 1.0, "silent_card": true},
		{"t": 184.5, "kind": "play", "team": 0, "card": "fire", "pos": cell_pos(6.5, 2),
			"spot": "", "zoom": 1.18, "silent_card": true,
			"sub": "火罐正中轟碎藍方增援食屍鬼群！替攻城槌徹底清掃破門障礙！"},
	]

static func find_card_slot(m, team: int, card_kind: String) -> int:
	if m.home_cards[team] == card_kind:
		return Battle.FARM_SLOT
	for s: int in range(4):
		if m.kind_at(team, s) == card_kind:
			return s
	return -1

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--verify":
			verify_only = true
	cues = build_screenplay()
	if verify_only:
		run_headless_verify()
		quit(0)
		return

	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	call_deferred("_prepare_movie")

func _prepare_movie() -> void:
	game.spectating = false
	game.me = 0
	game.mirror_view = false
	game.field_mirror = false
	game.cinematic.enabled = true
	model = Battle.new(MATCH_SEED, B.DEFAULT_DECK.duplicate(), B.CLASSIC_UNDERWORLD_DECK.duplicate(), "lion", "underworld")
	model.difficulty = 1
	model.ai_enabled = [false, false]
	game.model = model
	game.enter_battle("")
	game.recorder.reset(false)
	ready = true

func try_advance_director() -> void:
	if model == null or model.ended:
		return
	var sec := float(tick) / 60.0
	if cue_idx < cues.size():
		var c: Dictionary = cues[cue_idx]
		if sec < float(c.t):
			return
		var k: String = String(c.kind)
		if k == "chapter":
			if not verify_only:
				game.cinematic.trigger_chapter(String(c.title), String(c.get("sub", "")), float(c.get("dur", 2.6)))
			executed_log.append({"tick": tick, "t": sec, "cue": c, "status": "chapter"})
			cue_idx += 1
			return
		elif k == "play":
			var team: int = int(c.team)
			var card: String = String(c.card)
			var slot: int = find_card_slot(model, team, card)
			var pos: Vector2 = c.pos
			if slot != -1 and model.can_play(team, slot, pos):
				var ink_before: float = model.ink[team]
				model.play(team, slot, pos)
				if not verify_only:
					var spot: String = String(c.get("spot", ""))
					if not spot.is_empty() and not bool(c.get("silent_card", false)):
						game.cinematic.trigger_spotlight(game, pos, team, card, spot, float(c.get("zoom", 1.24)), 2.3, 3.2)
					elif float(c.get("zoom", 1.0)) > 1.02:
						game.cinematic.trigger_focus(game, pos, float(c.get("zoom", 1.18)), 1.6)
					var sub: String = String(c.get("sub", ""))
					if not sub.is_empty():
						game.cinematic.trigger_subtitle(sub, team, 3.6)
				executed_log.append({
					"tick": tick, "t": sec, "cue": c, "slot": slot,
					"ink_before": ink_before, "ink_after": model.ink[team], "status": "ok"
				})
				cue_idx += 1
				return
			# Allow generous grace wait for gold/cooldown
			if sec > float(c.t) + 32.0:
				var reason: String = "NOT_IN_HAND" if slot == -1 else String(model.play_error(team, slot, pos))
				executed_log.append({"tick": tick, "t": sec, "cue": c, "slot": slot, "reason": reason, "status": "timeout"})
				cue_idx += 1
		elif k == "ult_cue":
			var team: int = int(c.team)
			if not verify_only:
				game.cinematic.trigger_focus(game, model.lords[team].pos + Vector2(140.0 if team == 0 else -140.0, 0.0), 1.26, 1.6)
				var sub: String = String(c.get("sub", ""))
				if not sub.is_empty():
					game.cinematic.trigger_subtitle(sub, team, 2.2)
				if team == 0:
					game.skill_flash_left = maxf(game.skill_flash_left, 0.65)
			executed_log.append({"tick": tick, "t": sec, "cue": c, "status": "ult_cue"})
			cue_idx += 1
			return
		elif k == "skill":
			var team: int = int(c.team)
			if model.skill_error(team).is_empty() and model.cast_skill(team):
				if not verify_only:
					var sub: String = String(c.get("sub", ""))
					if not sub.is_empty():
						game.cinematic.trigger_subtitle(sub, team, 3.8)
				executed_log.append({"tick": tick, "t": sec, "cue": c, "status": "skill_ok"})
				cue_idx += 1
				return
			if sec > float(c.t) + 32.0:
				executed_log.append({"tick": tick, "t": sec, "cue": c, "reason": model.skill_error(team), "status": "timeout"})
				cue_idx += 1
	else:
		# Keep natural Lane III & nearby reinforcements pushing after scripted cues until gate breaks
		if tick % 90 == 0 and not model.ended:
			for c_kind: String in ["shieldguard", "ram", "hunter", "drummer", "healer", "rain"]:
				var slot: int = find_card_slot(model, 0, c_kind)
				if slot >= 0:
					var p := cell_pos(6.5 if c_kind == "rain" else 0.0, 2)
					if model.can_play(0, slot, p):
						model.play(0, slot, p)
						break

func _physics_process(_dt: float) -> bool:
	if verify_only or not ready:
		return false
	try_advance_director()
	if not model.paused and not model.ended:
		tick += 1
	return false

func _process(_dt: float) -> bool:
	if verify_only or not ready:
		return false
	if model.ended:
		post_end_frames -= 1
		if post_end_frames <= 0:
			return true
	return false

func run_headless_verify() -> void:
	model = Battle.new(MATCH_SEED, B.DEFAULT_DECK.duplicate(), B.CLASSIC_UNDERWORLD_DECK.duplicate(), "lion", "underworld")
	model.difficulty = 1
	model.ai_enabled = [false, false]
	print("[INIT DECK 0] ", model.decks[0], " gold=", model.ink[0])
	print("[INIT DECK 1] ", model.decks[1], " gold=", model.ink[1])
	var dt := 1.0 / 60.0
	var max_ticks := 60 * 300
	var farm_alive_after_raven := false
	var raven_checked := false
	var giant_checked := false
	var max_play_gap := 0.0
	var last_play_t := 0.0
	var blue_breaches := 0
	var red_breaches := 0
	var prev_rain_dmg := 0.0
	var prev_fire_dmg := 0.0
	var active_spells: Array = [] # [{t, team, card}]
	while tick < max_ticks and not model.ended:
		try_advance_director()
		model.step(dt)
		var sec := float(tick) / 60.0
		var step_deaths := {0: [], 1: []}
		var step_spells: Array = []
		for ev: Dictionary in model.events:
			var ek := String(ev.kind)
			if ek == "breach":
				if int(ev.team) == 1:
					blue_breaches += 1
				else:
					red_breaches += 1
			elif ek == "death":
				step_deaths[int(ev.team)].append(String(ev.get("card", "")))
			elif ek == "spell":
				step_spells.append({"t": sec, "team": int(ev.team), "card": String(ev.get("card", ""))})
		for sp: Dictionary in step_spells:
			var steam := int(sp.team)
			var sc := String(sp.card)
			var s_dmg := float(model.stats[steam].damage.get(sc, 0.0))
			print("[SPELL %05.2fs] team=%d card=%s total_dmg=%.0f kills=%s" % [sec, steam, sc, s_dmg, str(step_deaths[1 - steam])])
		model.events.clear()
		if not raven_checked and sec >= 23.5:
			raven_checked = true
			var ravens_left := 0
			for u: Dictionary in model.units:
				if u.hp > 0 and u.team == 1 and u.kind == "raven":
					ravens_left += 1
			var farm_hp := 0.0
			for b: Dictionary in model.buildings:
				if b.hp > 0 and b.team == 0 and b.kind == "farm" and b.cell.y == 2:
					farm_hp = b.hp
			farm_alive_after_raven = ravens_left == 0 and farm_hp > 0.0
			print("[AUDIT @23.5s] ravens_left=%d lane2_farm_hp=%.1f defense_ok=%s" % [ravens_left, farm_hp, str(farm_alive_after_raven)])
		if not giant_checked and sec >= 105.0:
			giant_checked = true
			var red_l2 := 0
			var blue_l2 := 0
			var giant_hp := 0.0
			for u: Dictionary in model.units:
				if u.hp > 0 and u.lane == 2:
					if u.team == 0: red_l2 += 1
					else: blue_l2 += 1
					if u.kind == "corpse_giant": giant_hp = u.hp
			print("[AUDIT @105.0s] red_l2=%d blue_l2=%d giant_hp=%.0f red_gate2=%.0f blue_gold=%.1f red_gold=%.1f" % [
				red_l2, blue_l2, giant_hp, float(model.gates[0][2]), model.ink[1], model.ink[0]
			])
		tick += 1

	for entry: Dictionary in executed_log:
		if String(entry.status) in ["ok", "skill_ok"]:
			var gap := float(entry.t) - last_play_t
			if last_play_t > 0.0 and gap > max_play_gap:
				max_play_gap = gap
			last_play_t = float(entry.t)
	print("[AUDIT SUMMARY] max_gap=%.2fs fire_dmg=%.0f rain_dmg=%.0f red_gate2_hp=%.0f blue_breaches=%d red_breaches=%d" % [
		max_play_gap,
		float(model.stats[0].damage.get("fire", 0.0)),
		float(model.stats[0].damage.get("rain", 0.0)),
		float(model.gates[0][2]),
		blue_breaches, red_breaches
	])

	var failures := 0
	var lines: PackedStringArray = [
		"# 經典紅獅 × 冥府領主｜編劇與剪輯分鏡腳本（100% 原生規則實測）",
		"",
		"- **種子 / 模式**: Seed `%d` · `經典紅獅 (lion)` vs `冥府領主 (underworld)`" % MATCH_SEED,
		"- **對戰結果**: %s · 總時長 `%s`（`%d` frames @60fps）" % [
			"紅獅王國勝利" if model.winner == 0 else ("冥府領主勝利" if model.winner == 1 else "未結束/平手"),
			Recorder.fmt_precise(float(tick) / 60.0),
			tick
		],
		"- **規則驗證**: 所有出牌與大招皆嚴格通過 `Battle.can_play` / `Battle.cast_skill`，無任何作弊加錢或無視冷卻。",
		"",
		"## 逐秒出牌與剪輯分鏡表",
	]
	for entry: Dictionary in executed_log:
		var c: Dictionary = entry.cue
		var tc := Recorder.fmt_precise(float(entry.t))
		var fr := int(entry.tick)
		var st := String(entry.status)
		if st == "timeout":
			failures += 1
			lines.append("- `[%s | f%05d]` ❌ **超時失敗** `%s`: %s" % [tc, fr, String(c.get("card", c.kind)), String(entry.get("reason", ""))])
			print("[FAIL] %s -> %s (%s)" % [tc, c.get("card", c.kind), entry.get("reason", "")])
		elif st == "chapter":
			lines.append("- `[%s | f%05d]` 🎬 **【章節轉場】** %s — *%s*" % [tc, fr, String(c.title), String(c.get("sub", ""))])
			print("[CHAPTER %s | f%05d] %s" % [tc, fr, c.title])
		elif st == "ult_cue":
			lines.append("- `[%s | f%05d]` 🎯 **【大招預告特寫】** `%s`" % [tc, fr, String(c.get("sub", ""))])
			print("[ULT_CUE %s | f%05d] %s" % [tc, fr, String(c.get("sub", ""))])
		elif st == "skill_ok":
			var sname := "獅王號令" if int(c.team) == 0 else "亡者大軍"
			var side := "紅方" if int(c.team) == 0 else "藍方"
			lines.append("- `[%s | f%05d]` ⚡ **【領主大招】** %s 發動「%s」 · 字幕：`%s`" % [tc, fr, side, sname, String(c.get("sub", ""))])
			print("[SKILL   %s | f%05d] %s: %s" % [tc, fr, side, sname])
		else:
			var card_name: String = String(B.CARDS[String(c.card)].name)
			var side := "紅方" if int(c.team) == 0 else "藍方"
			var spot: String = String(c.get("spot", ""))
			var fx := (" · 特寫介紹「%s」" % spot) if not spot.is_empty() and not bool(c.get("silent_card", false)) else ""
			lines.append("- `[%s | f%05d]` 🃏 **【%s出牌】** %s（slot `%s`，金幣 `%.1f→%.1f`）%s" % [
				tc, fr, side, card_name, str(entry.slot), float(entry.ink_before), float(entry.ink_after), fx
			])
			print("[PLAY    %s | f%05d] %s %-6s | gold %.1f->%.1f | slot=%s" % [
				tc, fr, side, card_name, float(entry.ink_before), float(entry.ink_after), str(entry.slot)
			])

	var out_dir := Recorder.output_dir()
	var script_path := out_dir.path_join("classic_lion_vs_underworld_剪輯劇本.md")
	var fa := FileAccess.open(script_path, FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(lines))
		fa.close()

	print("VERIFY_SUMMARY winner=%d ended=%s ticks=%d elapsed=%.2fs unplayed_cues=%d failures=%d" % [
		model.winner, str(model.ended), tick, model.elapsed, cues.size() - cue_idx, failures
	])
	print("SCRIPT_MD=" + script_path)
