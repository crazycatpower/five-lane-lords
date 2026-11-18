extends RefCounted
## Records deterministic 60Hz match inputs, generates YouTube editing cue sheets (剪輯筆記),
## and exports H.264 MP4 recordings via Godot Movie Maker + ffmpeg.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

const KILL_WINDOW_TICKS := 150 # 2.5 seconds at 60Hz
const PEAK_MIN_KILLS := 5

var active := false
var replaying := false
var tick := 0
var commands: Array = []
var replay_cursor := 0
var replay_total_ticks := 0
var setup_info: Dictionary = {}

var timeline: Array[Dictionary] = []
var highlights: Array[Dictionary] = []
var chapters: Array[Dictionary] = []
var recent_deaths: Array[Dictionary] = []
var active_peak: Dictionary = {}
var last_snapshot_tick := -1800

var saved := false
var last_base := ""
var replay_path := ""
var notes_path := ""
var mp4_path := ""
var export_state := "" # "", "rendering", "done", "error"
var export_pid := -1

static func output_dir() -> String:
	var res_abs: String = ProjectSettings.globalize_path("res://")
	if not res_abs.is_empty() and DirAccess.dir_exists_absolute(res_abs):
		var rec := res_abs.path_join("recordings")
		DirAccess.make_dir_recursive_absolute(rec)
		if DirAccess.dir_exists_absolute(rec):
			return rec
	var user_rec: String = OS.get_user_data_dir().path_join("recordings")
	DirAccess.make_dir_recursive_absolute(user_rec)
	return user_rec

static func fmt_time(t_sec: float) -> String:
	var total := maxf(0.0, t_sec)
	var mins := int(total) / 60
	var secs := int(total) % 60
	return "%02d:%02d" % [mins, secs]

static func fmt_precise(t_sec: float) -> String:
	var total := maxf(0.0, t_sec)
	var mins := int(total) / 60
	var secs := int(total) % 60
	var tenths := int(floorf(total * 10.0)) % 10
	return "%02d:%02d.%d" % [mins, secs, tenths]

static func lane_of(y: float) -> int:
	return clampi(int((y - L.GRID_ORIGIN.y) / L.CELL_SIZE.y) + 1, 1, 5)

func reset(enable_recording: bool) -> void:
	active = enable_recording
	replaying = false
	tick = 0
	commands.clear()
	replay_cursor = 0
	replay_total_ticks = 0
	setup_info = {}
	timeline.clear()
	highlights.clear()
	chapters = [{"tick": 0, "time": 0.0, "label": "開戰部署"}]
	recent_deaths.clear()
	active_peak = {}
	last_snapshot_tick = 0
	saved = false
	last_base = ""
	replay_path = ""
	notes_path = ""
	mp4_path = ""
	export_state = ""
	export_pid = -1

static func original_decks(shuffled: Array, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array = []
	for source: Array in shuffled:
		var deck := source.duplicate()
		var swaps: Array = []
		for i: int in range(deck.size()-1, 0, -1):
			swaps.append([i, rng.randi_range(0, i)])
		swaps.reverse()
		for pair: Array in swaps:
			var old = deck[pair[0]]
			deck[pair[0]] = deck[pair[1]]
			deck[pair[1]] = old
		result.append(deck)
	return result

func start(g, m) -> void:
	var should_record: bool = bool(g.get("replay_enabled")) and (g.net == null) and (not g.adventure.is_opening()) and (DisplayServer.get_name() != "headless") and (not replaying)
	if replaying:
		return
	reset(should_record)
	if not active:
		return
	var originals := original_decks(m.decks, m.rng.seed)
	setup_info = {
		"balance_hash": FileAccess.get_sha256("res://balance.gd"),
		"seed": m.rng.seed,
		"red_lord": String(m.lords[0].lord),
		"blue_lord": String(m.lords[1].lord),
		"red_deck": originals[0],
		"blue_deck": originals[1],
		"difficulty": int(m.difficulty),
		"spectating": bool(g.spectating),
		"me": int(g.me),
		"mirror_view": bool(g.mirror_view),
	}

func load_replay(path: String) -> Dictionary:
	reset(false)
	var raw := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(raw)
	if not (data is Dictionary):
		return {}
	replaying = true
	setup_info = data.get("setup", {})
	commands = data.get("commands", [])
	replay_total_ticks = int(data.get("total_ticks", 0))
	return setup_info

func record_cmd(cmd: String, team: int, slot: int = -1, pos: Vector2 = Vector2.ZERO) -> void:
	if not active or replaying:
		return
	commands.append({
		"t": tick,
		"cmd": cmd,
		"team": team,
		"slot": slot,
		"x": float(pos.x),
		"y": float(pos.y),
	})

func dispatch_replay(m) -> void:
	if not replaying:
		return
	while replay_cursor < commands.size():
		var c: Dictionary = commands[replay_cursor]
		var ct: int = int(c.get("t", -1))
		if ct > tick:
			break
		replay_cursor += 1
		var team: int = int(c.get("team", 0))
		var cmd: String = String(c.get("cmd", ""))
		if cmd == "play":
			m.play(team, int(c.get("slot", 0)), Vector2(float(c.get("x", 0.0)), float(c.get("y", 0.0))))
		elif cmd == "skill":
			m.cast_skill(team)

func _flush_peak() -> void:
	if active_peak.is_empty():
		return
	var kills: int = int(active_peak.get("kills", 0))
	if kills >= PEAK_MIN_KILLS:
		var t0: float = float(active_peak.get("start_time", 0.0))
		var t1: float = float(active_peak.get("end_time", t0))
		var kinds: Dictionary = active_peak.get("kinds", {})
		var sorted_k := kinds.keys()
		sorted_k.sort_custom(func(a: String, b: String) -> bool: return int(kinds[a]) > int(kinds[b]))
		var names: Array[String] = []
		for k: String in sorted_k.slice(0, 3):
			var nm: String = B.CARDS.get(k, {}).get("name", k)
			names.append("%s×%d" % [nm, int(kinds[k])])
		highlights.append({
			"tag": "🔥 激戰高光",
			"start_tick": int(active_peak.get("start_tick", 0)),
			"end_tick": int(active_peak.get("end_tick", 0)),
			"start": t0,
			"end": t1,
			"summary": "2.5秒內擊殺 %d 名單位（%s）" % [kills, "、".join(names)],
			"tip": "建議保留原速或切特寫，團戰密度最高"
		})
	active_peak = {}

func observe_tick(m, _g) -> void:
	if not active:
		return
	var sec: float = float(tick) / 60.0
	var red_gates: int = 0
	var blue_gates: int = 0
	for l: int in m.active_lanes:
		if m.gates[0][l] > 0: red_gates += 1
		if m.gates[1][l] > 0: blue_gates += 1

	for e: Dictionary in m.events:
		var kind: String = String(e.get("kind", ""))
		var team: int = int(e.get("team", -1))
		var side: String = "紅方" if team == 0 else ("藍方" if team == 1 else "戰場")
		match kind:
			"play":
				var card: String = String(e.get("card", ""))
				var info: Dictionary = B.CARDS.get(card, {})
				var cname: String = String(info.get("name", card))
				var ccost: int = int(info.get("cost", 0))
				var pos: Vector2 = e.get("pos", Vector2.ZERO)
				var lane_txt := "第 %d 路" % lane_of(pos.y)
				timeline.append({
					"tick": tick, "t": sec, "type": "出牌",
					"text": "%s 部署【%s】（%d金）於%s" % [side, cname, ccost, lane_txt],
					"meta": "紅金:%d 藍金:%d | 城牆 %d:%d" % [int(m.ink[0]), int(m.ink[1]), red_gates, blue_gates]
				})
			"skill":
				var lkind: String = String(e.get("lord", ""))
				var ldata: Dictionary = B.lord_data(lkind)
				var sname: String = String(ldata.get("skill", "領主技能"))
				var lname: String = String(ldata.get("name", side))
				var msg := "%s（%s）發動領主大招【%s】" % [side, lname, sname]
				timeline.append({
					"tick": tick, "t": sec, "type": "大招",
					"text": msg,
					"meta": "紅金:%d 藍金:%d | 城牆 %d:%d" % [int(m.ink[0]), int(m.ink[1]), red_gates, blue_gates]
				})
				highlights.append({
					"tag": "⚡ 領主大招",
					"start_tick": maxi(0, tick - 30),
					"end_tick": tick + 240,
					"start": maxf(0.0, sec - 0.5),
					"end": sec + 4.0,
					"summary": msg,
					"tip": "會觸發全畫面 Cut-In 橫幅與鏡頭特寫，建議完整保留"
				})
			"spell":
				var scard: String = String(e.get("card", ""))
				var sinfo: Dictionary = B.CARDS.get(scard, {})
				var spos: Vector2 = e.get("pos", Vector2.ZERO)
				if scard in ["fire", "rain", "curse", "plague", "chain_lightning", "rolling_boulder"]:
					timeline.append({
						"tick": tick, "t": sec, "type": "法術命中",
						"text": "%s【%s】落地於第 %d 路" % [side, String(sinfo.get("name", scard)), lane_of(spos.y)],
						"meta": ""
					})
			"breach":
				var blane: int = int(e.get("lane", 0)) + 1
				var crumbled: bool = bool(e.get("crumbled", false))
				var defender := "紅方" if team == 1 else "藍方"
				var bmsg := ("%s第 %d 路城牆朽壞倒塌" % [defender, blane]) if crumbled else ("%s攻破%s第 %d 路城牆！" % [side, defender, blane])
				timeline.append({
					"tick": tick, "t": sec, "type": "破門",
					"text": bmsg,
					"meta": "剩餘城牆 紅 %d : 藍 %d" % [red_gates, blue_gates]
				})
				highlights.append({
					"tag": "🧱 破門轉折",
					"start_tick": maxi(0, tick - 90),
					"end_tick": tick + 180,
					"start": maxf(0.0, sec - 1.5),
					"end": sec + 3.0,
					"summary": bmsg,
					"tip": "城門倒塌有強震與木石碎裂音效，重要轉折點"
				})
			"ramp":
				var mult: float = float(e.get("multiplier", 2.0))
				var phase := "正午加速（×%.1f）" % mult if sec < B.RAMP_2 - 1.0 else "黃昏激戰（×%.1f）" % mult
				chapters.append({"tick": tick, "time": sec, "label": phase})
				timeline.append({"tick": tick, "t": sec, "type": "節奏切換", "text": "進入%s：產金與冷卻加快" % phase, "meta": ""})
			"nightfall":
				if bool(e.get("first", false)):
					chapters.append({"tick": tick, "time": sec, "label": "入夜決戰（×3.0 · 城牆開始朽壞）"})
					timeline.append({"tick": tick, "t": sec, "type": "節奏切換", "text": "入夜：產金×3、雙方城牆持續腐朽", "meta": ""})
			"dawn":
				chapters.append({"tick": tick, "time": sec, "label": "天亮結算"})
				timeline.append({"tick": tick, "t": sec, "type": "結算", "text": "天亮依領地結算勝負", "meta": ""})
			"invaded":
				var ilane: int = int(e.get("lane", 0)) + 1
				var uk: String = String(e.get("unit_kind", ""))
				var uname: String = String(B.CARDS.get(uk, {}).get("name", "部隊"))
				var imsg := "%s【%s】自第 %d 路突入城門鎖定勝局！" % [side, uname, ilane]
				timeline.append({"tick": tick, "t": sec, "type": "致勝", "text": imsg, "meta": "觸發子彈時間特寫"})
				highlights.append({
					"tag": "🏆 終局高潮",
					"start_tick": maxi(0, tick - 120),
					"end_tick": tick + 240,
					"start": maxf(0.0, sec - 2.0),
					"end": sec + 4.0,
					"summary": imsg,
					"tip": "內含 0.20x→1.0x 子彈時間定格與勝利結算畫面"
				})
			"death":
				var dk: String = String(e.get("card", ""))
				recent_deaths.append({"tick": tick, "t": sec, "card": dk})

	while not recent_deaths.is_empty() and tick - int(recent_deaths[0].tick) > KILL_WINDOW_TICKS:
		recent_deaths.pop_front()
	if recent_deaths.size() >= PEAK_MIN_KILLS:
		var kmap := {}
		for d: Dictionary in recent_deaths:
			var ck: String = String(d.card)
			if not ck.is_empty():
				kmap[ck] = int(kmap.get(ck, 0)) + 1
		if active_peak.is_empty():
			active_peak = {
				"start_tick": int(recent_deaths[0].tick),
				"end_tick": tick,
				"start_time": float(recent_deaths[0].t),
				"end_time": sec,
				"kills": recent_deaths.size(),
				"kinds": kmap,
			}
		else:
			active_peak["end_tick"] = tick
			active_peak["end_time"] = sec
			if recent_deaths.size() > int(active_peak.get("kills", 0)):
				active_peak["kills"] = recent_deaths.size()
			var prev_k: Dictionary = active_peak.get("kinds", {})
			for ck: String in kmap:
				prev_k[ck] = maxi(int(prev_k.get(ck, 0)), int(kmap[ck]))
			active_peak["kinds"] = prev_k
	elif not active_peak.is_empty() and tick - int(active_peak.get("end_tick", 0)) > KILL_WINDOW_TICKS:
		_flush_peak()

func finish(g, m) -> void:
	if not active or saved:
		return
	saved = true
	_flush_peak()
	var dt := Time.get_datetime_dict_from_system()
	last_base = "match_%04d%02d%02d_%02d%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	var dir := output_dir()
	replay_path = dir.path_join(last_base + ".json")
	notes_path = dir.path_join(last_base + "_剪輯筆記.md")
	mp4_path = dir.path_join(last_base + ".mp4")

	var payload := {
		"version": 1,
		"setup": setup_info,
		"total_ticks": tick,
		"duration": m.elapsed,
		"winner": m.winner,
		"commands": commands,
	}
	var rf := FileAccess.open(replay_path, FileAccess.WRITE)
	if rf != null:
		rf.store_string(JSON.stringify(payload, "\t"))
	var nf := FileAccess.open(notes_path, FileAccess.WRITE)
	if nf != null:
		nf.store_string(_build_markdown(g, m))

func _deck_lines(lord_kind: String, deck: Array) -> String:
	var ldata: Dictionary = B.lord_data(lord_kind)
	var home: String = B.home_card(lord_kind)
	var home_txt := String(B.CARDS[home].name) if B.CARDS.has(home) else "無"
	var card_names: Array[String] = []
	for k: String in deck:
		if B.CARDS.has(k):
			card_names.append("%s(%d金)" % [String(B.CARDS[k].name), int(B.CARDS[k].cost)])
	return "- **%s**（技能：%s / 常駐：%s）：%s" % [String(ldata.name), String(ldata.get("skill", "無")), home_txt, "、".join(card_names)]

func _build_markdown(_g, m) -> String:
	var lines: Array[String] = []
	var red_lord: String = String(setup_info.get("red_lord", m.lords[0].lord))
	var blue_lord: String = String(setup_info.get("blue_lord", m.lords[1].lord))
	var win_str := "紅方勝（%s）" % B.lord_name(red_lord) if m.winner == 0 else ("藍方勝（%s）" % B.lord_name(blue_lord) if m.winner == 1 else "平手")
	lines.append("# 《羊皮紙戰記》實戰錄影與剪輯筆記 — %s" % last_base)
	lines.append("")
	lines.append("## 1. 對戰總覽")
	lines.append("- **對陣**：%s vs %s（難度：%s）" % [B.lord_name(red_lord), B.lord_name(blue_lord), ["簡單", "普通", "困難"][clampi(int(m.difficulty), 0, 2)]])
	lines.append("- **戰果**：**%s**（總時長 `%s` · 模擬幀數 `%d` ticks @ 60fps）" % [win_str, fmt_time(m.elapsed), tick])
	lines.append("- **Seed**：`%d`" % int(setup_info.get("seed", 0)))
	lines.append(_deck_lines(red_lord, setup_info.get("red_deck", m.decks[0])))
	lines.append(_deck_lines(blue_lord, setup_info.get("blue_deck", m.decks[1])))
	lines.append("")
	lines.append("## 2. YouTube 影片章節（可直接複製貼到說明欄）")
	for c: Dictionary in chapters:
		lines.append("- `%s` %s" % [fmt_time(float(c.time)), String(c.label)])
	lines.append("")
	lines.append("## 3. 推薦高光剪輯片段（Highlights）")
	if highlights.is_empty():
		lines.append("- （本局無自動觸發之連續擊殺／破門高光，可參考下方時間軸剪輯大招與交戰。）")
	else:
		highlights.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.start_tick) < int(b.start_tick))
		for h: Dictionary in highlights:
			lines.append("- **%s** `%s ~ %s`（Frame `%d`–`%d`）：%s｜*%s*" % [
				String(h.tag), fmt_time(float(h.start)), fmt_time(float(h.end)),
				int(h.start_tick), int(h.end_tick), String(h.summary), String(h.tip)
			])
	lines.append("")
	lines.append("## 4. 全場數據與傷害排行")
	for team: int in range(2):
		var s: Dictionary = m.stats[team]
		var side := "紅方（%s）" % B.lord_name(red_lord if team == 0 else blue_lord)
		var ranked: Array = s.damage.keys().filter(func(k: String) -> bool: return B.CARDS.has(k))
		ranked.sort_custom(func(a: String, b: String) -> bool: return float(s.damage[a]) > float(s.damage[b]))
		var top3: Array[String] = []
		for k: String in ranked.slice(0, 3):
			top3.append("%s %d" % [String(B.CARDS[k].name), int(s.damage[k])])
		lines.append("- **%s**：產金 `%d`（溢出 `%d`）· 出牌 `%d` 次 · 技能 `%d` 次 · 傷害前三：%s" % [
			side, int(s.produced), int(s.wasted), int(s.plays), int(s.get("skills", 0)),
			"、".join(top3) if not top3.is_empty() else "無"
		])
	lines.append("")
	lines.append("## 5. 逐秒剪輯時間軸（Timecode + Frame @60fps）")
	for item: Dictionary in timeline:
		var meta_s: String = String(item.get("meta", ""))
		var tail := (" — `%s`" % meta_s) if not meta_s.is_empty() else ""
		lines.append("- `[%s | f%05d]` **【%s】** %s%s" % [
			fmt_precise(float(item.t)), int(item.tick), String(item.type), String(item.text), tail
		])
	lines.append("")
	return "\n".join(lines)

func has_saved_replay() -> bool:
	return saved and not replay_path.is_empty() and FileAccess.file_exists(replay_path)

func poll_export() -> void:
	if export_state != "rendering":
		return
	if FileAccess.file_exists(mp4_path):
		if export_pid <= 0 or not OS.is_process_running(export_pid):
			export_state = "done"
	elif export_pid > 0 and not OS.is_process_running(export_pid):
		export_state = "error"

func export_mp4() -> bool:
	if not has_saved_replay() or export_state == "rendering":
		return false
	var ps1 := ProjectSettings.globalize_path("res://tools/export_movie.ps1")
	var proj := ProjectSettings.globalize_path("res://")
	if not FileAccess.file_exists(ps1):
		export_state = "error"
		return false
	var godot_exe := OS.get_executable_path()
	var raw_avi := replay_path.get_basename() + "_raw.avi"
	var args := PackedStringArray([
		"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1,
		"-GodotExe", godot_exe,
		"-ProjectDir", proj,
		"-ReplayPath", replay_path,
		"-RawAvi", raw_avi,
		"-Mp4Path", mp4_path,
	])
	var pid := OS.create_process("powershell.exe", args, false)
	if pid <= 0:
		export_state = "error"
		return false
	export_pid = pid
	export_state = "rendering"
	return true

func open_recordings_folder() -> void:
	OS.shell_open(output_dir())
