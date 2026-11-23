extends RefCounted
# 傳送帶關卡機制（如 1-10）：玩家不採金幣與輪轉手牌，改由右側補給匣定期送出免費卡牌由右向左滑入，
# 上限 8 張、打出消耗，同時仍依卡牌原本費用替領主大招充能。
# Deliberately does NOT preload battle.gd or battle_hud.gd to avoid circular preload chains.
const B = preload("res://balance.gd")

const DEFAULT_CAPACITY := 8
const BELT_PLATE := Rect2(40.0, 712.0, 1158.0, 166.0)
const TRACK_RECT := Rect2(48.0, 720.0, 1028.0, 152.0)
const CHUTE_RECT := Rect2(1080.0, 718.0, 110.0, 154.0)
const CARD_Y := 728.0
const CARD_W := 118.0
const CARD_H := 150.0
const CARD_GAP := 8.0
const CARD_STEP := 126.0
const BELT_LEFT := 54.0
const SPAWN_X := 1020.0
const SLIDE_SPEED := 340.0

const CREAM := Color("f7ecd2")
const INK := Color("463529")
const GOLD := Color("c9a456")
const GOLD_LIT := Color("f0cf78")
const BELT_DARK := Color("24160d")
const BELT_WOOD := Color("4d311d")
const BELT_SLAT := Color("624129")
const BRASS := Color("b48b43")
const BRASS_DARK := Color("6f5020")

static func is_active(m, team: int = 0) -> bool:
	if m == null or not (m.conveyor is Dictionary):
		return false
	return bool(m.conveyor.get("active", false)) and int(m.conveyor.get("team", 0)) == team

static func count(m) -> int:
	if m == null or not (m.conveyor is Dictionary) or not bool(m.conveyor.get("active", false)):
		return 0
	return (m.conveyor.get("cards", []) as Array).size()

static func capacity(m) -> int:
	if m == null or not (m.conveyor is Dictionary):
		return DEFAULT_CAPACITY
	return int(m.conveyor.get("capacity", DEFAULT_CAPACITY))

static func kind_at(m, slot: int) -> String:
	if m == null or not (m.conveyor is Dictionary):
		return ""
	var cards: Array = m.conveyor.get("cards", [])
	if slot < 0 or slot >= cards.size():
		return ""
	return String(cards[slot].get("kind", ""))

static func setup(m, cfg: Dictionary) -> void:
	if m == null or cfg.is_empty():
		if m != null:
			m.conveyor = {}
		return
	var team := int(cfg.get("team", 0))
	var cap := mini(DEFAULT_CAPACITY, maxi(1, int(cfg.get("capacity", DEFAULT_CAPACITY))))
	var pool: Array = []
	for k in cfg.get("pool", []):
		if B.CARDS.has(String(k)):
			pool.append(String(k))
	var opening: Array = []
	for k in cfg.get("opening", []):
		if B.CARDS.has(String(k)):
			opening.append(String(k))
	var cv: Dictionary = {
		"active": true,
		"team": team,
		"capacity": cap,
		"interval": maxf(0.5, float(cfg.get("interval", 2.8))),
		"min_interval": maxf(0.45, float(cfg.get("min_interval", 1.7))),
		"pool": pool,
		"opening": opening,
		"cards": [],
		"next_kind": "",
		"timer": 0.0,
		"belt_dist": 0.0,
		"delivered": 0,
		"next_id": 1,
	}
	m.conveyor = cv
	m.ink[team] = 0.0
	if bool(cfg.get("clear_home", true)):
		m.home_cards[team] = ""
		m.buildings = m.buildings.filter(func(b: Dictionary) -> bool: return int(b.get("team", -1)) != team or String(b.get("kind", "")) != "farm")
		m.refresh_territory()

	var start_count := clampi(int(cfg.get("start_count", 3)), 0, cap)
	var open_src: Array = opening if not opening.is_empty() else pool
	var cards: Array = cv.cards
	for i: int in range(start_count):
		var chosen := _pick_opening_kind(m, open_src, cards, i == 0)
		if chosen.is_empty():
			break
		cards.append({
			"kind": chosen,
			"x": BELT_LEFT + float(i) * CARD_STEP,
			"id": int(cv.next_id),
		})
		cv["next_id"] = int(cv["next_id"]) + 1
		cv["delivered"] = int(cv["delivered"]) + 1
	cv["next_kind"] = next_card_kind(m)

static func _pick_opening_kind(m, src: Array, existing: Array, require_unit: bool) -> String:
	if src.is_empty():
		return ""
	var used := {}
	for c: Dictionary in existing:
		used[String(c.get("kind", ""))] = true
	var candidates: Array = []
	for k in src:
		var kind := String(k)
		if used.has(kind):
			continue
		if require_unit and B.CARDS.has(kind) and String(B.CARDS[kind].get("type", "")) != "unit":
			continue
		candidates.append(kind)
	if candidates.is_empty():
		for k in src:
			var kind := String(k)
			if require_unit and B.CARDS.has(kind) and String(B.CARDS[kind].get("type", "")) != "unit":
				continue
			if not kind in candidates:
				candidates.append(kind)
	if candidates.is_empty():
		candidates = src
	return String(candidates[m.rng.randi() % candidates.size()])

static func next_card_kind(m) -> String:
	if m == null or not (m.conveyor is Dictionary):
		return ""
	var cv: Dictionary = m.conveyor
	var pool: Array = cv.get("pool", [])
	if pool.is_empty():
		return ""
	var cards: Array = cv.get("cards", [])
	var counts := {}
	var spell_count := 0
	for c: Dictionary in cards:
		var ck := String(c.get("kind", ""))
		counts[ck] = int(counts.get(ck, 0)) + 1
		if B.CARDS.has(ck) and String(B.CARDS[ck].get("type", "")) == "spell":
			spell_count += 1
	var candidates: Array = []
	for k in pool:
		var kind := String(k)
		if int(counts.get(kind, 0)) >= 2:
			continue
		if spell_count >= 2 and B.CARDS.has(kind) and String(B.CARDS[kind].get("type", "")) == "spell":
			continue
		candidates.append(kind)
	if candidates.is_empty():
		for k in pool:
			var kind := String(k)
			if int(counts.get(kind, 0)) < 3:
				candidates.append(kind)
	if candidates.is_empty():
		candidates = pool
	return String(candidates[m.rng.randi() % candidates.size()])

static func current_interval(m) -> float:
	if m == null or not (m.conveyor is Dictionary):
		return 2.8
	var cv: Dictionary = m.conveyor
	var base_iv := float(cv.get("interval", 2.8))
	var min_iv := float(cv.get("min_interval", 1.7))
	var t_norm := clampf(float(m.elapsed) / 240.0, 0.0, 1.0)
	var iv := lerpf(base_iv, min_iv, t_norm)
	if int(m.difficulty) == 0:
		iv *= 0.90
	return maxf(0.45, iv)

static func update(m, dt: float) -> void:
	if not is_active(m, int(m.conveyor.get("team", 0))):
		return
	var cv: Dictionary = m.conveyor
	var cards: Array = cv.get("cards", [])
	var cap: int = int(cv.get("capacity", DEFAULT_CAPACITY))
	var moving := false
	for i: int in range(cards.size()):
		var c: Dictionary = cards[i]
		var target_x := BELT_LEFT + float(i) * CARD_STEP
		var cur_x := float(c.get("x", target_x))
		var nx := cur_x - SLIDE_SPEED * dt
		if i > 0:
			var prev_x := float(cards[i - 1].get("x", BELT_LEFT))
			nx = maxf(nx, prev_x + CARD_STEP)
		nx = maxf(target_x, nx)
		if absf(nx - cur_x) > 0.01:
			moving = true
		c["x"] = nx

	var belt_speed := 96.0 if moving else (22.0 if cards.size() < cap else 0.0)
	cv["belt_dist"] = float(cv.get("belt_dist", 0.0)) + belt_speed * dt

	var iv := current_interval(m)
	if cards.size() < cap:
		cv["timer"] = float(cv.get("timer", 0.0)) + dt
		if float(cv["timer"]) >= iv:
			cv["timer"] = float(cv["timer"]) - iv
			_spawn_next(m, cv)
	else:
		# Backed up at capacity: hold right before dispatch so a freed slot soon receives the next card.
		cv["timer"] = minf(float(cv.get("timer", 0.0)) + dt, iv * 0.85)

static func _spawn_next(m, cv: Dictionary) -> void:
	var cards: Array = cv.get("cards", [])
	var cap: int = int(cv.get("capacity", DEFAULT_CAPACITY))
	if cards.size() >= cap:
		return
	var kind := String(cv.get("next_kind", ""))
	if kind.is_empty() or not B.CARDS.has(kind):
		kind = next_card_kind(m)
	if kind.is_empty():
		return
	var spawn_x := SPAWN_X
	if not cards.is_empty():
		spawn_x = maxf(SPAWN_X, float(cards[cards.size() - 1].get("x", BELT_LEFT)) + CARD_STEP)
	cards.append({
		"kind": kind,
		"x": spawn_x,
		"id": int(cv.get("next_id", 1)),
	})
	cv["next_id"] = int(cv.get("next_id", 1)) + 1
	cv["delivered"] = int(cv.get("delivered", 0)) + 1
	cv["next_kind"] = next_card_kind(m)

static func consume(m, slot: int) -> void:
	if m == null or not (m.conveyor is Dictionary):
		return
	var cards: Array = m.conveyor.get("cards", [])
	if slot >= 0 and slot < cards.size():
		cards.remove_at(slot)

static func card_rect(m, slot: int) -> Rect2:
	if m == null or not (m.conveyor is Dictionary):
		return Rect2()
	var cards: Array = m.conveyor.get("cards", [])
	if slot < 0 or slot >= cards.size():
		return Rect2()
	var x := float(cards[slot].get("x", BELT_LEFT + float(slot) * CARD_STEP))
	return Rect2(x, CARD_Y, CARD_W, CARD_H)

static func card_at(m, pos: Vector2) -> int:
	if not is_active(m, 0):
		return -1
	if pos.x >= CHUTE_RECT.position.x + 8.0:
		return -1
	var cards: Array = m.conveyor.get("cards", [])
	for i: int in range(cards.size() - 1, -1, -1):
		if card_rect(m, i).has_point(pos):
			return i
	return -1

static func unique_pool(cfg: Dictionary) -> Array:
	var seen := {}
	var out: Array = []
	for src_key: String in ["opening", "pool"]:
		for k in cfg.get(src_key, []):
			var kind := String(k)
			if B.CARDS.has(kind) and not seen.has(kind):
				seen[kind] = true
				out.append(kind)
	return out

static func _bevel_poly(r: Rect2, cut: float = 8.0) -> PackedVector2Array:
	return PackedVector2Array([
		r.position + Vector2(cut, 0.0),
		Vector2(r.end.x - cut, r.position.y),
		Vector2(r.end.x, r.position.y + cut),
		r.end - Vector2(0.0, cut),
		r.end - Vector2(cut, 0.0),
		Vector2(r.position.x + cut, r.end.y),
		Vector2(r.position.x, r.end.y - cut),
		r.position + Vector2(0.0, cut),
	])

static func _draw_belt_bed(g, m) -> void:
	var cv: Dictionary = m.conveyor
	var outer := _bevel_poly(BELT_PLATE, 10.0)
	g.draw_colored_polygon(outer, BELT_DARK)
	var border := outer.duplicate()
	border.append(outer[0])
	g.draw_polyline(border, Color(BRASS, 0.72), 2.0, true)

	# Recessed conveyor track.
	g.draw_rect(TRACK_RECT, BELT_WOOD)
	g.draw_rect(Rect2(TRACK_RECT.position, Vector2(TRACK_RECT.size.x, 6.0)), Color(0, 0, 0, 0.32))
	g.draw_rect(Rect2(Vector2(TRACK_RECT.position.x, TRACK_RECT.end.y - 6.0), Vector2(TRACK_RECT.size.x, 6.0)), Color(0, 0, 0, 0.25))

	# Moving vertical rollers / wooden slats scrolling left (-x).
	var spacing := 36.0
	var phase := fposmod(-float(cv.get("belt_dist", 0.0)), spacing)
	var sx := TRACK_RECT.position.x + phase
	while sx < TRACK_RECT.end.x - 4.0:
		g.draw_line(Vector2(sx, TRACK_RECT.position.y + 8.0), Vector2(sx, TRACK_RECT.end.y - 8.0), BELT_SLAT, 3.0, true)
		g.draw_line(Vector2(sx + 2.5, TRACK_RECT.position.y + 8.0), Vector2(sx + 2.5, TRACK_RECT.end.y - 8.0), Color(0, 0, 0, 0.28), 1.5, true)
		sx += spacing

	# Top and bottom brass guide rails with rivets.
	for rail_y: float in [TRACK_RECT.position.y + 3.0, TRACK_RECT.end.y - 5.0]:
		g.draw_rect(Rect2(TRACK_RECT.position.x + 2.0, rail_y, TRACK_RECT.size.x - 4.0, 3.0), Color(BRASS_DARK, 0.85))
		var rx := TRACK_RECT.position.x + 18.0
		while rx < TRACK_RECT.end.x - 10.0:
			g.draw_circle(Vector2(rx, rail_y + 1.5), 1.8, GOLD)
			rx += 96.0

	# Directional stencil painted onto the open belt bed (under the cards).
	var cap: int = int(cv.get("capacity", DEFAULT_CAPACITY))
	var cards: Array = cv.get("cards", [])
	var stencil_alpha := 0.08 if cards.size() > 0 else 0.42
	var cy := TRACK_RECT.get_center().y
	for ax: float in [TRACK_RECT.position.x + 310.0, TRACK_RECT.position.x + 716.0]:
		g.draw_colored_polygon(PackedVector2Array([
			Vector2(ax - 9.0, cy),
			Vector2(ax + 5.0, cy - 7.0),
			Vector2(ax + 5.0, cy + 7.0),
		]), Color(CREAM, stencil_alpha))
	g.draw_string(
		g.font,
		Vector2(TRACK_RECT.position.x + 16.0, cy + 7.0),
		"補給傳送帶 · 免費出牌 · 1–8 選牌",
		HORIZONTAL_ALIGNMENT_CENTER,
		TRACK_RECT.size.x - 32.0,
		18,
		Color(CREAM, stencil_alpha)
	)
	g.draw_rect(Rect2(TRACK_RECT.position, TRACK_RECT.size), Color(BRASS_DARK, 0.6), false, 1.5)
	if cards.size() >= cap:
		g.draw_rect(TRACK_RECT, Color(0.55, 0.16, 0.10, 0.08))

static func _draw_chute(g, m) -> void:
	var cv: Dictionary = m.conveyor
	var cards: Array = cv.get("cards", [])
	var cap: int = int(cv.get("capacity", DEFAULT_CAPACITY))
	var full := cards.size() >= cap
	var r := CHUTE_RECT
	var pts := _bevel_poly(r, 8.0)
	g.draw_colored_polygon(pts, Color("312014"))
	var rim := pts.duplicate()
	rim.append(pts[0])
	g.draw_polyline(rim, GOLD if full else BRASS, 2.0, true)

	# Slotted brass curtain mouth covering the right seam where new cards enter.
	g.draw_rect(Rect2(r.position.x - 4.0, r.position.y + 6.0, 8.0, r.size.y - 12.0), BELT_DARK)
	g.draw_rect(Rect2(r.position.x - 2.0, r.position.y + 10.0, 4.0, r.size.y - 20.0), BRASS)

	g.draw_string(g.font, Vector2(r.position.x, r.position.y + 20.0), "補給匣", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, GOLD_LIT)

	# Mini preview of the next incoming card.
	var next_box := Rect2(r.position.x + 18.0, r.position.y + 27.0, 74.0, 62.0)
	g.draw_rect(next_box, Color("e9d7b1"))
	g.draw_rect(next_box, BRASS_DARK, false, 1.5)
	var nk := String(cv.get("next_kind", ""))
	if not nk.is_empty() and B.CARDS.has(nk):
		g.draw_card_art(nk, next_box.grow(-4.0), g.me, Color(0.95, 0.95, 0.95) if full else Color.WHITE)
		g.draw_rect(Rect2(next_box.position.x, next_box.end.y - 18.0, next_box.size.x, 18.0), Color(0.18, 0.12, 0.07, 0.78))
		g.draw_string(g.font, Vector2(next_box.position.x, next_box.end.y - 4.0), String(B.CARDS[nk].name), HORIZONTAL_ALIGNMENT_CENTER, next_box.size.x, 11, CREAM)

	# Countdown bar toward next card delivery.
	var iv := maxf(0.01, current_interval(m))
	var frac := clampf(float(cv.get("timer", 0.0)) / iv, 0.0, 1.0)
	var bar := Rect2(r.position.x + 12.0, r.position.y + 98.0, r.size.x - 24.0, 10.0)
	g.draw_rect(bar, BELT_DARK)
	g.draw_rect(Rect2(bar.position + Vector2(1.0, 1.0), Vector2((bar.size.x - 2.0) * frac, bar.size.y - 2.0)), Color("b8442a") if full else GOLD_LIT)
	g.draw_rect(bar, BRASS_DARK, false, 1.0)

	var status_txt := "已滿 %d/%d" % [cards.size(), cap] if full else "送牌 %d/%d" % [cards.size(), cap]
	g.draw_string(g.font, Vector2(r.position.x, r.position.y + 127.0), status_txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, Color("ffcf9b") if full else CREAM)
	g.draw_string(g.font, Vector2(r.position.x, r.position.y + 144.0), "%.1f 秒/張" % iv, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, Color(CREAM, 0.7))

static func draw_hud(g) -> void:
	var m = g.model
	if not is_active(m, g.me):
		return
	_draw_belt_bed(g, m)

	var cards: Array = m.conveyor.get("cards", [])
	for slot: int in range(cards.size()):
		var r := card_rect(m, slot)
		var lift := float(g.polish.get_slot_lift(g, slot)) if g.polish != null else 0.0
		var draw_r := Rect2(r.position + Vector2(0.0, lift), r.size)
		# Soft tray shadow beneath sliding card.
		g.draw_rect(Rect2(draw_r.position + Vector2(3.0, 5.0), draw_r.size), Color(0, 0, 0, 0.28))
		var kind := String(cards[slot].get("kind", ""))
		if not kind.is_empty():
			g.draw_card(kind, draw_r, slot)
		if g.selected == slot:
			g.draw_rect(draw_r.grow(2.5), GOLD_LIT, false, 2.5)

	_draw_chute(g, m)
