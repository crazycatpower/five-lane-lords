extends SceneTree
## Picks (or uses specified) two Minion Lords, finds an exciting decisive AI-vs-AI seed
## at exact 60Hz deterministic step, and writes a render_replay.gd payload + YouTube metadata JSON.
const Battle = preload("res://battle.gd")
const B = preload("res://balance.gd")
const Catalog = preload("res://roguelike_catalog.gd")
const Recorder = preload("res://match_recorder.gd")

const STEP_DT := 1.0 / 60.0
const MAX_SIM_SECONDS := 545.0 # allow full day -> dusk -> night -> dawn battles
const MIN_IDEAL_SEC := 55.0
const MAX_IDEAL_SEC := 175.0

func _resolve_foe(query: String, keys: Array) -> String:
	if query.is_empty():
		return ""
	if B.LORDS.has(query) or Catalog.MINIONS.has(query):
		return query
	var all_keys: Array = []
	for lk: String in B.LORDS.keys():
		all_keys.append(lk)
	for mk: String in keys:
		if not mk in all_keys:
			all_keys.append(mk)
	for k: String in all_keys:
		if String(B.lord_name(k)) == query:
			return k
	var matches: Array[String] = []
	for k: String in all_keys:
		var nm := String(B.lord_name(k))
		var cname := String(B.CARDS.get(String(B.lord_data(k).get("card", "")), {}).get("name", ""))
		if query in nm or query in k or (not cname.is_empty() and query in cname):
			matches.append(k)
	if matches.is_empty():
		return ""
	matches.sort_custom(func(a: String, b: String) -> bool:
		var na := String(B.lord_name(a))
		var nb := String(B.lord_name(b))
		var pa := na.begins_with(query)
		var pb := nb.begins_with(query)
		if pa != pb:
			return pa
		if na.length() != nb.length():
			return na.length() < nb.length()
		return a < b)
	return matches[0]

func _default_deck_for(lord: String) -> Array:
	if Catalog.MINIONS.has(lord):
		return Catalog.MINIONS[lord].deck.duplicate()
	return Catalog.BOSSES.get(lord, B.DEFAULT_DECK).duplicate()

func _parse_deck_arg(csv: String) -> Array:
	var out: Array = []
	if csv.strip_edges().is_empty():
		return out
	for part: String in csv.split(",", false):
		var ck := part.strip_edges()
		if not ck.is_empty():
			out.append(ck)
	return out

func _load_history(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"pairs": [], "recent_lords": []}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {"pairs": [], "recent_lords": []}

func _pair_key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)

func _pick_pair(keys: Array, date_str: String, history: Dictionary) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("daily_minion_" + date_str)
	var seen_pairs := {}
	for p in history.get("pairs", []):
		seen_pairs[String(p)] = true
	var recent := []
	for l in history.get("recent_lords", []):
		recent.append(String(l))
	var recent_tail: Array = recent.slice(maxi(0, recent.size() - 12))

	var best_pair: Array[String] = []
	var best_score := -1e9
	for _attempt: int in range(250):
		var a: String = keys[rng.randi_range(0, keys.size() - 1)]
		var b: String = keys[rng.randi_range(0, keys.size() - 1)]
		if a == b:
			continue
		if seen_pairs.has(_pair_key(a, b)):
			continue
		var score := 0.0
		var ta: int = int(Catalog.MINIONS[a].get("tier", 1))
		var tb: int = int(Catalog.MINIONS[b].get("tier", 1))
		score -= absf(float(ta - tb)) * 3.0 # prefer close strength tiers
		if B.home_card(a) != B.home_card(b):
			score += 2.0 # cross-faction contrast is fun to watch
		if not (a in recent_tail):
			score += 3.0
		if not (b in recent_tail):
			score += 3.0
		score += rng.randf() * 0.5
		if score > best_score:
			best_score = score
			best_pair = [a, b]
	if best_pair.is_empty():
		var a: String = keys[rng.randi_range(0, keys.size() - 1)]
		var b: String = keys[(keys.find(a) + 1) % keys.size()]
		best_pair = [a, b]
	return best_pair

func _simulate(red_lord: String, blue_lord: String, seed_val: int, record_notes: bool, custom_red_deck: Array = [], custom_blue_deck: Array = []) -> Dictionary:
	var red_deck: Array = custom_red_deck.duplicate() if not custom_red_deck.is_empty() else _default_deck_for(red_lord)
	var blue_deck: Array = custom_blue_deck.duplicate() if not custom_blue_deck.is_empty() else _default_deck_for(blue_lord)
	var m := Battle.new(seed_val, red_deck, blue_deck, red_lord, blue_lord)
	m.difficulty = 2
	m.ai_enabled = [true, true]
	m.record_events = record_notes

	var rec := Recorder.new()
	if record_notes:
		rec.reset(true)
		rec.setup_info = {
			"balance_hash": FileAccess.get_sha256("res://balance.gd"),
			"seed": seed_val,
			"red_lord": red_lord,
			"blue_lord": blue_lord,
			"red_deck": red_deck,
			"blue_deck": blue_deck,
			"difficulty": 2,
			"spectating": true,
			"me": 0,
			"mirror_view": false,
		}

	var max_ticks := int(MAX_SIM_SECONDS * 60.0)
	var tick := 0
	while not m.ended and tick < max_ticks:
		m.step(STEP_DT)
		if record_notes:
			if not m.paused and not m.ended:
				rec.observe_tick(m, null)
				rec.tick += 1
			m.events.clear()
		tick += 1

	return {
		"model": m,
		"tick": tick,
		"elapsed": m.elapsed,
		"winner": m.winner,
		"recorder": rec,
		"red_deck": red_deck,
		"blue_deck": blue_deck,
	}

func _score_match(sim: Dictionary, min_ideal: float = MIN_IDEAL_SEC, max_ideal: float = MAX_IDEAL_SEC) -> float:
	var m = sim.model
	if not m.ended or not (m.winner in [0, 1]):
		return -1000.0 + m.elapsed * 0.01
	var t: float = float(sim.elapsed)
	var s := 100.0
	if t < min_ideal:
		s -= (min_ideal - t) * 4.0
	elif t > max_ideal:
		s -= (t - max_ideal) * 0.8
	# Closer gate damage at the end means a more back-and-forth fight
	var red_rem := 0.0
	var blue_rem := 0.0
	for hp: float in m.gates[0]:
		red_rem += maxf(0.0, hp)
	for hp: float in m.gates[1]:
		blue_rem += maxf(0.0, hp)
	var loser_rem := blue_rem if m.winner == 0 else red_rem
	var winner_rem := red_rem if m.winner == 0 else blue_rem
	s += clampf(5.0 - winner_rem / 1500.0, 0.0, 5.0) * 4.0
	s -= loser_rem * 0.002
	s += float(m.stats[0].used.size() + m.stats[1].used.size()) * 3.5
	return s

func _card_names_text(deck: Array) -> String:
	var counts := {}
	var order: Array[String] = []
	for k: String in deck:
		if not counts.has(k):
			counts[k] = 0
			order.append(k)
		counts[k] += 1
	var parts: Array[String] = []
	for k: String in order:
		var nm := String(B.CARDS.get(k, {}).get("name", k))
		parts.append("%s ×%d" % [nm, int(counts[k])] if int(counts[k]) > 1 else nm)
	return "、".join(parts)

func _card_descriptions_lines(red_lord: String, blue_lord: String, red_deck: Array, blue_deck: Array) -> Array[String]:
	var ordered: Array[String] = []
	var seen := {}
	var append_card := func(ks: String) -> void:
		if ks.is_empty() or not B.CARDS.has(ks) or seen.has(ks):
			return
		seen[ks] = true
		ordered.append(ks)
	for k in [B.home_card(red_lord)] + red_deck + [B.home_card(blue_lord)] + blue_deck:
		append_card.call(String(k))
	if seen.has("seal_altar"):
		append_card.call("plague_bishop")
		append_card.call("funeral_monk")
	var skeleton_callers := ["necromancer", "corpse_stitcher", "pallbearer", "corpse_giant", "mass_grave", "ossuary", "borrowed_bones", "grave_exchange"]
	var needs_skeleton := red_lord == "underworld" or blue_lord == "underworld"
	if not needs_skeleton:
		for sk: String in skeleton_callers:
			if seen.has(sk):
				needs_skeleton = true
				break
	if needs_skeleton:
		append_card.call("skeleton")
	var out: Array[String] = ["🃏 本場登場卡牌完整說明："]
	for k: String in ordered:
		var c: Dictionary = B.CARDS[k]
		var fac_label := String(B.FACTIONS.get(B.card_faction(k), "中立"))
		var desc := B.card_description(k).strip_edges().replace("\n", "｜")
		out.append("• 【%s】（%s｜%s）：%s" % [String(c.name), fac_label, String(c.get("role", "")), desc])
	return out

func _build_meta(date_str: String, red_lord: String, blue_lord: String, sim: Dictionary, replay_path: String, mp4_path: String, notes_path: String, theme: String = "") -> Dictionary:
	var red_name := String(B.lord_name(red_lord))
	var blue_name := String(B.lord_name(blue_lord))
	var red_role := String(B.lord_data(red_lord).get("role", ""))
	var blue_role := String(B.lord_data(blue_lord).get("role", ""))
	var rec: Recorder = sim.recorder
	var m = sim.model
	var win_side := "紅方【%s】" % red_name if m.winner == 0 else ("藍方【%s】" % blue_name if m.winner == 1 else "雙方平手")

	var chap_lines: Array[String] = []
	for c: Dictionary in rec.chapters:
		chap_lines.append("%s %s" % [Recorder.fmt_time(float(c.time)), String(c.label)])

	var intro_line := ("《五路領主》主題流派 AI 對決 — %s（%s）！" % [theme, date_str]) if not theme.is_empty() else ("每日《五路領主》野怪領主 AI 全自動對決（%s）！" % date_str)
	var hashtags_line := "#五路領主 #主題對決 #策略遊戲 #AI對戰 #肉鴿" if not theme.is_empty() else "#五路領主 #野怪對決 #策略遊戲 #AI對戰 #肉鴿"
	var desc_lines := [
		intro_line,
		"",
		"🔴 紅方：%s（%s｜常駐：%s）" % [red_name, red_role, String(B.CARDS.get(B.home_card(red_lord), {}).get("name", "無"))],
		"套牌：%s" % _card_names_text(sim.red_deck),
		"",
		"🔵 藍方：%s（%s｜常駐：%s）" % [blue_name, blue_role, String(B.CARDS.get(B.home_card(blue_lord), {}).get("name", "無"))],
		"套牌：%s" % _card_names_text(sim.blue_deck),
		"",
		"⏱ 對戰時間軸：",
	]
	desc_lines.append_array(chap_lines)
	desc_lines.append("")
	desc_lines.append_array(_card_descriptions_lines(red_lord, blue_lord, sim.red_deck, sim.blue_deck))
	desc_lines.append("")
	desc_lines.append("🏆 本場勝者：%s（時長 %s）" % [win_side, Recorder.fmt_time(float(sim.elapsed))])
	desc_lines.append("")
	desc_lines.append(hashtags_line)

	var full_desc := "\n".join(desc_lines)
	if full_desc.length() > 4950:
		full_desc = full_desc.left(4947) + "..."

	var title := ("【五路領主】%s！%s VS %s｜誰能稱霸五路戰場？（%s）" % [theme, red_name, blue_name, date_str]) if not theme.is_empty() else ("【五路領主】野怪領主對決！%s VS %s｜誰能稱霸五路戰場？（%s）" % [red_name, blue_name, date_str])
	if title.length() > 98:
		title = ("【五路領主】%s｜%s VS %s (%s)" % [theme, red_name, blue_name, date_str]) if not theme.is_empty() else ("%s VS %s｜五路領主野怪對決 (%s)" % [red_name, blue_name, date_str])

	var tags := ["五路領主", theme if not theme.is_empty() else "野怪對決", red_name, blue_name, "AI對戰", "卡牌策略", "肉鴿"]
	return {
		"date": date_str,
		"theme": theme,
		"red_lord": red_lord,
		"blue_lord": blue_lord,
		"red_name": red_name,
		"blue_name": blue_name,
		"seed": int(m.rng.seed),
		"total_ticks": int(sim.tick),
		"duration_sec": float(sim.elapsed),
		"winner": int(m.winner),
		"replay_path": replay_path,
		"mp4_path": mp4_path,
		"notes_path": notes_path,
		"title": title,
		"description": full_desc,
		"tags": tags,
	}

func _initialize() -> void:
	var dt := Time.get_datetime_dict_from_system()
	var date_str := "%04d%02d%02d" % [dt.year, dt.month, dt.day]
	var red_arg := ""
	var blue_arg := ""
	var red_deck_arg := ""
	var blue_deck_arg := ""
	var theme := ""
	var custom_slug := ""
	var out_dir := ProjectSettings.globalize_path("res://recordings/daily_yt")
	var history_path := out_dir.path_join("history.json")
	var fixed_seed := -1
	var min_dur := MIN_IDEAL_SEC
	var max_dur := MAX_IDEAL_SEC
	var night_mode := false

	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--red="): red_arg = arg.get_slice("=", 1)
		elif arg.begins_with("--blue="): blue_arg = arg.get_slice("=", 1)
		elif arg.begins_with("--red-deck="): red_deck_arg = arg.get_slice("=", 1)
		elif arg.begins_with("--blue-deck="): blue_deck_arg = arg.get_slice("=", 1)
		elif arg.begins_with("--theme="): theme = arg.get_slice("=", 1)
		elif arg.begins_with("--slug="): custom_slug = arg.get_slice("=", 1)
		elif arg.begins_with("--date="): date_str = arg.get_slice("=", 1)
		elif arg.begins_with("--out-dir="): out_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--history="): history_path = arg.get_slice("=", 1)
		elif arg.begins_with("--seed="): fixed_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--min-dur="): min_dur = float(arg.get_slice("=", 1))
		elif arg.begins_with("--max-dur="): max_dur = float(arg.get_slice("=", 1))
		elif arg == "--night":
			night_mode = true
			min_dur = maxf(min_dur, B.NIGHT_START + 50.0) # 6:50+ deep night clash
			max_dur = maxf(max_dur, B.DAWN - 15.0)

	var custom_red_deck := _parse_deck_arg(red_deck_arg)
	var custom_blue_deck := _parse_deck_arg(blue_deck_arg)
	for ck: String in custom_red_deck + custom_blue_deck:
		if not B.CARDS.has(ck):
			push_error("Unknown card id in deck arg: " + ck)
			quit(1)
			return
	var has_custom_decks := not custom_red_deck.is_empty() or not custom_blue_deck.is_empty()

	var keys: Array = Catalog.MINIONS.keys()
	keys.sort()
	var history := _load_history(history_path)
	var fixed_red := _resolve_foe(red_arg, keys)
	var fixed_blue := _resolve_foe(blue_arg, keys)
	var red_lord := fixed_red
	var blue_lord := fixed_blue

	var best_seed := fixed_seed if fixed_seed > 0 else 100
	var chosen_sim: Dictionary = {}
	if fixed_seed > 0 and not red_lord.is_empty() and not blue_lord.is_empty():
		chosen_sim = _simulate(red_lord, blue_lord, best_seed, false, custom_red_deck, custom_blue_deck)
	elif night_mode and (fixed_red.is_empty() or fixed_blue.is_empty()):
		# Search across stalwart Tier 2-3 (then all) pairs to find a genuine decisive late-night war.
		var search_rng := RandomNumberGenerator.new()
		search_rng.seed = hash("night_" + date_str + "_" + fixed_red + "_" + fixed_blue)
		var sturdy: Array[String] = []
		for k: String in keys:
			if int(Catalog.MINIONS[k].get("tier", 1)) >= 2:
				sturdy.append(k)
		if sturdy.size() < 4:
			sturdy.assign(keys)
		var best_score := -1e9
		for attempt: int in range(120):
			var pool: Array = sturdy if attempt < 72 else keys
			var r_cand := fixed_red if not fixed_red.is_empty() else String(pool[search_rng.randi_range(0, pool.size() - 1)])
			var b_cand := fixed_blue if not fixed_blue.is_empty() else String(pool[search_rng.randi_range(0, pool.size() - 1)])
			if r_cand == b_cand:
				continue
			var s_cand := search_rng.randi_range(1000, 999999)
			var sim := _simulate(r_cand, b_cand, s_cand, false, custom_red_deck, custom_blue_deck)
			var sc := _score_match(sim, min_dur, max_dur)
			if sc > best_score:
				best_score = sc
				red_lord = r_cand
				blue_lord = b_cand
				best_seed = s_cand
				chosen_sim = sim
			if sim.model.ended and sim.model.winner in [0, 1] and sim.elapsed >= min_dur and sim.elapsed <= max_dur:
				break
	else:
		if red_lord.is_empty() or blue_lord.is_empty():
			var auto_pair := _pick_pair(keys, date_str, history)
			if red_lord.is_empty():
				red_lord = auto_pair[0] if auto_pair[0] != blue_lord else auto_pair[1]
			if blue_lord.is_empty():
				blue_lord = auto_pair[1] if auto_pair[1] != red_lord else auto_pair[0]
		if fixed_seed <= 0:
			best_seed = int(absi(hash(date_str + "_" + red_lord + "_vs_" + blue_lord)) % 900000) + 100
		var best_score := -1e9
		var max_tries := 40
		for off: int in range(max_tries):
			var cand_seed := best_seed + off * 7
			var sim := _simulate(red_lord, blue_lord, cand_seed, false, custom_red_deck, custom_blue_deck)
			var sc := _score_match(sim, min_dur, max_dur)
			if sc > best_score:
				best_score = sc
				best_seed = cand_seed
				chosen_sim = sim
			if not has_custom_decks and sim.model.ended and sim.model.winner in [0, 1] and sim.elapsed >= min_dur and sim.elapsed <= max_dur:
				break

	# Final deterministic pass with full chapter/highlight note capture
	var final_sim := _simulate(red_lord, blue_lord, best_seed, true, custom_red_deck, custom_blue_deck)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var slug := custom_slug if not custom_slug.is_empty() else ("duel_%s_%s_vs_%s" % [date_str, red_lord, blue_lord])
	var replay_path := out_dir.path_join(slug + ".json")
	var mp4_path := out_dir.path_join(slug + ".mp4")
	var notes_path := out_dir.path_join(slug + "_notes.md")
	var meta_path := out_dir.path_join(slug + "_meta.json")

	var payload := {
		"version": 1,
		"setup": final_sim.recorder.setup_info,
		"total_ticks": int(final_sim.tick),
		"duration": float(final_sim.elapsed),
		"winner": int(final_sim.winner),
		"commands": [],
	}
	var rf := FileAccess.open(replay_path, FileAccess.WRITE)
	if rf == null:
		push_error("Failed to write replay JSON: " + replay_path)
		quit(1)
		return
	rf.store_string(JSON.stringify(payload, "\t"))

	final_sim.recorder.last_base = slug
	var nf := FileAccess.open(notes_path, FileAccess.WRITE)
	if nf != null:
		nf.store_string(final_sim.recorder._build_markdown(null, final_sim.model))

	var meta := _build_meta(date_str, red_lord, blue_lord, final_sim, replay_path, mp4_path, notes_path, theme)
	var mf := FileAccess.open(meta_path, FileAccess.WRITE)
	if mf != null:
		mf.store_string(JSON.stringify(meta, "\t"))

	print("RED_USED: %s" % JSON.stringify(final_sim.model.stats[0].used))
	print("BLUE_USED: %s" % JSON.stringify(final_sim.model.stats[1].used))
	print("DUEL READY: %s VS %s (seed=%d, ticks=%d, dur=%.1fs, winner=%d)" % [
		meta.red_name, meta.blue_name, best_seed, int(final_sim.tick), float(final_sim.elapsed), int(final_sim.winner)
	])
	print("META_JSON: " + meta_path)
	quit(0)
