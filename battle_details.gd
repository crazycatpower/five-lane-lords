extends RefCounted
## Micro-details that turn board-game events into physical, cinematic battlefield motion:
## spells hurled by the Lord, feathered arrows, smoky siege shells, coin arcs, death knockback, and breach smoke.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

const SPELL_PALETTE := {
	"fire": Color("eb5d2a"),
	"flaming_pitch": Color("f06c24"),
	"rolling_boulder": Color("b88b4a"),
	"chain_lightning": Color("6cc8f5"),
	"mana_drain": Color("54a8e8"),
	"mana_spring": Color("47c7e8"),
	"arcane_shield": Color("7ac7e0"),
	"time_field": Color("7d8ce0"),
	"gravity_well": Color("6855b5"),
	"phase_shift": Color("9b8ce8"),
	"mirror_clone": Color("76b8d8"),
	"harvest": Color("ebc242"),
	"charge_horn": Color("e89e38"),
	"counter_charge": Color("e3872d"),
	"levy": Color("d8a74a"),
	"curse": Color("9b6ad6"),
	"plague": Color("2ca34b"),
	"corrosive_bile": Color("5ab83a"),
	"sacrifice": Color("bd2b38"),
	"berserk_blood": Color("c93838"),
	"devouring_maw": Color("9e343a"),
	"swarm_eruption": Color("72a832"),
	"wing_gust": Color("7db892"),
	"pack_ambush": Color("c96e32"),
	"feral_mutation": Color("68b54f"),
	"dread_howl": Color("7d4a9e"),
	"borrowed_bones": Color("8e6bb5"),
	"grave_exchange": Color("a67dc9"),
	"mourning_shroud": Color("8c72b5"),
	"sealed_coffin": Color("5f4875"),
}

static func spell_color(kind: String) -> Color:
	return SPELL_PALETTE.get(kind, Color("d8aa4c"))

## Where a spell physically originates: the Lord's outstretched hand/staff, or battlement if absent.
static func spell_origin(m, team: int, target_pos: Vector2) -> Vector2:
	var lord: Dictionary = m.lords[team]
	if m.lord_active[team] and float(lord.hp) > 0.0:
		var face := 1.0 if team == 0 else -1.0
		return lord.pos + Vector2(face * 20.0, -34.0)
	var gate_y: float = clampf(target_pos.y, L.GRID_ORIGIN.y + 36.0, L.GRID_ORIGIN.y + L.GRID_SIZE.y - 36.0)
	return Vector2(L.gate_icon_x(team), gate_y - 44.0)

static func arc_point(origin: Vector2, target: Vector2, t: float) -> Vector2:
	var dist := origin.distance_to(target)
	var peak := clampf(dist * 0.30, 100.0, 225.0)
	return origin.lerp(target, t) - Vector2(0.0, sin(t * PI) * peak)

## Aura & rune burst around the Lord while hurling a spell or casting a skill.
static func draw_lord_cast_aura(g, lord: Dictionary, left: float, spell_kind: String) -> void:
	if left <= 0.0 or not g.fx_enabled:
		return
	var is_ult := spell_kind.begins_with("skill:")
	var dur := 1.15 if is_ult else 0.42
	var p: float = clampf(1.0 - left / dur, 0.0, 1.0)
	var strength: float = sin(p * PI)
	var face := 1.0 if int(lord.team) == 0 else -1.0
	var hand: Vector2 = lord.pos + Vector2(face * 22.0, -36.0 - (14.0 if is_ult else 6.0) * strength)
	var col: Color = Color("f0c450") if is_ult else (spell_color(spell_kind) if not spell_kind.is_empty() else Color("f0c450"))
	if is_ult:
		var base_c: Vector2 = lord.pos + Vector2(0.0, -18.0)
		var ring_r: float = 34.0 + p * 78.0
		g.draw_circle(base_c, 42.0 * strength + 8.0, Color(col, 0.24 * strength))
		g.draw_arc(base_c, ring_r, 0.0, TAU, 36, Color(col, 0.92 * strength), 3.4, true)
		g.draw_arc(base_c, ring_r * 0.68, 0.0, TAU, 28, Color(1.0, 0.96, 0.82, 0.80 * strength), 2.0, true)
		for i: int in range(8):
			var a: float = float(i) * TAU / 8.0 + p * 1.2
			var inner: Vector2 = base_c + Vector2(cos(a), sin(a)) * 22.0
			var outer: Vector2 = base_c + Vector2(cos(a), sin(a)) * (36.0 + 36.0 * p)
			g.draw_line(inner, outer, Color(1.0, 0.94, 0.70, 0.82 * strength), 2.4, true)
	g.draw_circle(hand, (26.0 if is_ult else 20.0) * strength + 5.0, Color(col, 0.34 * strength))
	g.draw_circle(hand, (9.0 if is_ult else 7.0) * strength, Color(1.0, 0.96, 0.82, 0.90 * strength))
	g.draw_arc(hand, 12.0 + p * (32.0 if is_ult else 22.0), 0.0, TAU, 24, Color(col, 0.92 * strength), 2.6, true)
	for i: int in range(6):
		var a: float = float(i) * TAU / 6.0 + p * 2.4
		var spark: Vector2 = hand + Vector2(cos(a), sin(a)) * (11.0 + p * 18.0)
		g.draw_circle(spark, 2.5 * strength, Color(1.0, 0.96, 0.82, strength))

## Render all in-flight spells being hurled in a glowing parabola from the Lord to the target tile.
static func draw_spells(g) -> void:
	var m = g.model
	for spell: Dictionary in m.spells:
		var kind: String = spell.kind
		var delay: float = float(spell.delay)
		var t: float = clampf(1.0 - delay / B.SPELL_DELAY, 0.0, 1.0)
		var target: Vector2 = spell.pos
		var origin: Vector2 = spell.get("origin", spell_origin(m, int(spell.team), target))
		var col: Color = spell_color(kind)
		var sdata: Dictionary = B.CARDS.get(kind, {})
		var radius: float = float(sdata.get("radius", 56.0))

		# 1. Target reticle on turf: snapped grid footprint for grid spells, oval for rolling boulders.
		var pulse: float = 0.72 + 0.28 * sin(t * PI * 4.0)
		if sdata.get("rolling", false):
			g.tf(target, 0.0, Vector2(1.0, 0.46))
			g.draw_circle(Vector2.ZERO, radius, Color(col, 0.12 + 0.14 * t))
			g.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(g.INK, 0.34), 3.6, true)
			g.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(col, (0.55 + 0.35 * t) * pulse), 2.2, true)
			g.draw_arc(Vector2.ZERO, radius * maxf(0.12, 1.0 - t), 0.0, TAU, 28, Color(1.0, 0.95, 0.78, 0.82 * t), 2.2, true)
			for dir_v: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				g.draw_line(dir_v * (radius - 7.0), dir_v * (radius + 6.0), Color(col, 0.85), 2.2, true)
			g.tf()
		else:
			var srect: Rect2 = B.spell_rect(target, sdata)
			var sh: Vector2i = B.spell_shape(sdata)
			g.draw_rect(srect, Color(col, 0.14 + 0.14 * t))
			for gc: int in range(1, sh.x):
				var lx: float = srect.position.x + float(gc) * L.CELL_SIZE.x
				g.draw_line(Vector2(lx, srect.position.y), Vector2(lx, srect.end.y), Color(col, 0.42 * pulse), 1.4)
			for gr: int in range(1, sh.y):
				var ly: float = srect.position.y + float(gr) * L.CELL_SIZE.y
				g.draw_line(Vector2(srect.position.x, ly), Vector2(srect.end.x, ly), Color(col, 0.42 * pulse), 1.4)
			g.draw_rect(srect, Color(g.INK, 0.34), false, 3.8)
			g.draw_rect(srect, Color(col, (0.60 + 0.35 * t) * pulse), false, 2.4)
			var inner: Rect2 = Rect2(srect.get_center() - srect.size * 0.5 * maxf(0.12, 1.0 - t), srect.size * maxf(0.12, 1.0 - t))
			g.draw_rect(inner, Color(1.0, 0.95, 0.78, 0.80 * t), false, 2.0)
			target = srect.get_center()

		# 2. Ground shadow tracking under the flying arc.
		var ground: Vector2 = origin.lerp(target, t)
		var lift: float = sin(t * PI)
		g.tf(ground, 0.0, Vector2(1.0, 0.36))
		g.draw_circle(Vector2.ZERO, 17.0 - 5.0 * lift, Color(0.14, 0.10, 0.06, 0.30))
		g.tf()

		# 3. Full trajectory ribbon back to the Lord's hand + bright wake + drifting embers.
		var full_pts := PackedVector2Array()
		for j: int in range(11):
			full_pts.append(arc_point(origin, target, t * float(j) / 10.0))
		for j: int in range(full_pts.size() - 1):
			var ribbon_a: float = 0.10 + 0.24 * (float(j + 1) / 10.0)
			g.draw_line(full_pts[j], full_pts[j + 1], Color(col, ribbon_a), 2.2, true)
		var pts := PackedVector2Array()
		for i: int in range(10):
			var kt: float = maxf(0.0, t - float(9 - i) * 0.036)
			pts.append(arc_point(origin, target, kt))
		if pts.size() >= 2:
			for seg: int in range(pts.size() - 1):
				var frac: float = float(seg + 1) / float(pts.size())
				g.draw_line(pts[seg], pts[seg + 1], Color(col, 0.68 * frac), 1.8 + 5.6 * frac, true)
				g.draw_line(pts[seg], pts[seg + 1], Color(1.0, 0.95, 0.82, 0.58 * frac), 1.0 + 2.0 * frac, true)
		for s_idx: int in range(3):
			var st: float = maxf(0.0, t - 0.08 - float(s_idx) * 0.11)
			var sp: Vector2 = arc_point(origin, target, st) + Vector2(sin(st * 25.0 + float(s_idx)) * 5.0, cos(st * 19.0) * 4.0)
			g.draw_circle(sp, 3.0 - float(s_idx) * 0.6, Color(1.0, 0.92, 0.72, 0.78 - float(s_idx) * 0.20))

		# 4. Rotating spell relic / card crest at the tip of the arc.
		var cur: Vector2 = arc_point(origin, target, t)
		var nxt: Vector2 = arc_point(origin, target, minf(1.0, t + 0.04))
		var tilt: float = clampf((nxt - cur).angle() * 0.25, -0.35, 0.35)
		g.draw_circle(cur, 25.0, Color(col, 0.32))
		g.draw_arc(cur, 21.0 + 4.0 * sin(t * 14.0), 0.0, TAU, 20, Color(1.0, 0.92, 0.68, 0.78), 1.6, true)
		g.tf(cur, tilt)
		g.draw_texture_rect(g.art(kind), Rect2(-22.0, -28.0, 44.0, 56.0), false)
		g.tf()

## Richer projectiles: feathered arrows, spinning axe trails, smoky mortar arcs, and wizard trails.
static func draw_projectile(g, arrow: Dictionary) -> void:
	var dir: float = float(arrow.get("direction", 1.0))
	if arrow.get("beam", false): # 水晶巨像: one thick flickering beam over both its lanes
		var lanes: Array = arrow.lanes
		var y0: float = L.cell_center(Vector2i(0, int(lanes[0]))).y - 34.0
		var y1: float = L.cell_center(Vector2i(0, int(lanes[lanes.size() - 1]))).y - 8.0
		var mid: float = (y0 + y1) * 0.5
		var half: float = maxf(26.0, (y1 - y0) * 0.5 + 18.0)
		var life: float = float(arrow.life)
		var age: float = life - float(arrow.remaining)
		var k: float = clampf(minf(age / 0.12, float(arrow.remaining) / 0.2), 0.0, 1.0)
		var flick: float = 0.85 + 0.15 * sin(float(g.clock) * 47.0)
		var x0: float = float(arrow.pos.x) + dir * 40.0
		var x1: float = float(arrow.pos.x) + dir * float(arrow.reach)
		var lo: float = minf(x0, x1)
		var w: float = absf(x1 - x0)
		g.draw_rect(Rect2(lo, mid - half, w, half * 2.0), Color(0.62, 0.45, 0.95, 0.16 * k))
		g.draw_rect(Rect2(lo, mid - half * 0.62, w, half * 1.24), Color(0.74, 0.60, 1.0, 0.28 * k * flick))
		g.draw_rect(Rect2(lo, mid - half * 0.28, w, half * 0.56), Color(0.93, 0.88, 1.0, 0.75 * k * flick))
		g.draw_circle(Vector2(x0, mid), half * 0.8, Color(0.85, 0.75, 1.0, 0.45 * k))
		if w > 8.0:
			for i: int in range(5):
				var sx: float = x0 + dir * fposmod(float(g.clock) * 900.0 + i * 97.0, w)
				var a1: float = clampf(sx, lo, lo + w)
				var b1: float = clampf(sx + dir * 30.0, lo, lo + w)
				if absf(b1 - a1) >= 2.0:
					g.draw_line(Vector2(a1, mid - half * 0.5), Vector2(b1, mid - half * 0.5), Color(1, 1, 1, 0.5 * k), 2.0, true)
				var a2: float = clampf(sx + dir * 45.0, lo, lo + w)
				var b2: float = clampf(sx + dir * 75.0, lo, lo + w)
				if absf(b2 - a2) >= 2.0:
					g.draw_line(Vector2(a2, mid + half * 0.45), Vector2(b2, mid + half * 0.45), Color(1, 1, 1, 0.4 * k), 2.0, true)
		return
	if arrow.get("rolling", false):
		var stone_pos: Vector2 = arrow.pos - Vector2(0.0, 32.0 + absf(sin(float(arrow.angle) * 2.0)) * 4.0)
		g.tf(arrow.pos + Vector2(0.0, 6.0), 0.0, Vector2(1.0, 0.25))
		g.draw_circle(Vector2.ZERO, 37.0, Color(0.2, 0.16, 0.10, 0.28))
		g.tf()
		for i: int in range(5):
			var puff: Vector2 = arrow.pos - Vector2(dir * (32.0 + float(i) * 12.0), -4.0 + sin(float(arrow.angle) + i) * 3.0)
			g.draw_circle(puff, 7.0 - float(i), Color(0.60, 0.50, 0.34, 0.36 - float(i) * 0.06))
		g.tf(stone_pos, float(arrow.angle))
		g.draw_texture_rect(g.art("rolling_boulder"), Rect2(-50.0, -50.0, 100.0, 100.0), false)
		g.tf()
		return

	if arrow.kind == "axe_thrower":
		var spin: float = (1.0 - float(arrow.remaining) / B.ARROW_TIME) * TAU * 2.2 * dir
		g.draw_arc(arrow.pos, 11.0, spin - 1.2 * dir, spin, 10, Color(0.85, 0.88, 0.92, 0.35), 2.5, true)
		g.tf(arrow.pos, spin)
		g.draw_line(Vector2(-9.0, 0.0), Vector2(9.0, 0.0), Color("78512d"), 3.0, true)
		g.draw_colored_polygon(PackedVector2Array([Vector2(3.0, -8.0), Vector2(12.0, -5.0), Vector2(12.0, 5.0), Vector2(3.0, 8.0)]), Color("a9a8a0"))
		g.draw_polyline(PackedVector2Array([Vector2(3.0, -8.0), Vector2(12.0, -5.0), Vector2(12.0, 5.0), Vector2(3.0, 8.0)]), g.INK, 1.5, true)
		g.tf()
		return

	if arrow.has("impact"):
		var flight: float = clampf(1.0 - float(arrow.remaining) / float(arrow.flight), 0.0, 1.0)
		var shadow_pos: Vector2 = arrow.start.lerp(arrow.impact, flight)
		g.tf(shadow_pos, 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, 9.0 * flight + 2.0, Color(0.16, 0.12, 0.08, 0.32))
		g.tf()
		var pulse: float = 0.35 + 0.2 * sin(float(g.model.elapsed) * 12.0)
		g.tf(arrow.impact, 0.0, Vector2(1.0, 0.48))
		g.draw_arc(Vector2.ZERO, float(arrow.radius), 0.0, TAU, 28, Color(0.84, 0.34, 0.14, pulse), 1.8, true)
		g.draw_arc(Vector2.ZERO, float(arrow.radius) * maxf(0.15, 1.0 - flight), 0.0, TAU, 20, Color(0.95, 0.56, 0.24, 0.45), 1.5, true)
		g.tf()
		if arrow.has("look"):
			draw_boss_bomb(g, arrow, flight)
			return
		var is_bomb: bool = arrow.kind in ["funeral_grenadier", "dog_cannon"]
		for i: int in range(1, 5):
			var bt: float = maxf(0.0, flight - float(i) * 0.045)
			var bp: Vector2 = arrow.start.lerp(arrow.impact, bt) - Vector2(0.0, sin(bt * PI) * 65.0)
			var sc: Color = Color(0.95, 0.52, 0.18, 0.45 - float(i) * 0.09) if is_bomb and i <= 2 else Color(0.55, 0.48, 0.38, 0.36 - float(i) * 0.07)
			g.draw_circle(bp, 4.5 - float(i) * 0.7, sc)
		var stone: Vector2 = arrow.pos - Vector2(0.0, sin(flight * PI) * 65.0)
		var shell_c := Color("3d3835") if is_bomb else Color("86745c")
		g.draw_circle(stone, 6.5, shell_c)
		g.draw_arc(stone, 6.5, 0.0, TAU, 12, g.INK, 1.5, true)
		if is_bomb:
			g.draw_circle(stone + Vector2(3.0, -5.0), 2.8, Color("f6a636"))
			g.draw_circle(stone + Vector2(3.0, -5.0), 1.3, Color("fff3c4"))
		return

	if arrow.get("piercing", false) and arrow.kind == "long_dragon":
		var mouth: Vector2 = arrow.start + Vector2(dir * 40.0, 8.0)
		var front: Vector2 = arrow.pos + Vector2(0.0, 8.0)
		var flicker: float = sin(float(g.model.elapsed) * 40.0) * 2.5
		g.draw_polygon(PackedVector2Array([mouth + Vector2(0, -3), front + Vector2(0, -11 - flicker), front + Vector2(dir * 9, 0), front + Vector2(0, 11 + flicker), mouth + Vector2(0, 3)]), PackedColorArray([Color(0.85, 0.30, 0.08, 0.78)]))
		g.draw_polygon(PackedVector2Array([mouth, front + Vector2(-dir * 6, -5), front, front + Vector2(-dir * 6, 5)]), PackedColorArray([Color(1.0, 0.82, 0.35, 0.88)]))
		return

	if arrow.get("piercing", false):
		var tip: Vector2 = arrow.pos
		var tail := Vector2(dir * 26.0, 0.0)
		var beam := [Color("c4a75f", 0.42), Color("e5c158"), Color("fff1b8")] if arrow.kind == "orrery_walker" else [Color("8966b8", 0.38), Color("c5a4eb"), Color("ead7ff")]
		if arrow.has("look"):
			beam = BOSS_BEAM.get(String(arrow.look), beam)
			tail *= 1.8
			g.draw_line(tip - tail * 1.4, tip, Color(beam[0], 0.25), 14.0, true)
		g.draw_line(tip - tail * 1.6, tip, beam[0], 5.5, true)
		g.draw_line(tip - tail, tip, beam[1], 2.2, true)
		g.draw_polyline(PackedVector2Array([tip - Vector2(dir * 6.0, 4.0), tip, tip - Vector2(dir * 6.0, -4.0)]), beam[2], 2.0, true)
		return

	if String(arrow.get("visual_kind", arrow.kind)) == "dark_wizard":
		var pos: Vector2 = arrow.pos
		g.draw_line(pos - Vector2(22.0 * dir, 0.0), pos, Color(0.48, 0.22, 0.65, 0.65), 5.0, true)
		g.draw_circle(pos - Vector2(10.0 * dir, sin(float(g.clock) * 18.0) * 2.5), 3.0, Color(0.75, 0.50, 0.92, 0.65))
		g.draw_circle(pos, 6.2, Color("aa6bce"))
		g.draw_circle(pos, 2.6, Color("f0deff"))
		return

	if arrow.get("curse_splash", false) and arrow.has("look"):
		var lk: Array = BOSS_CURSE.get(String(arrow.look), BOSS_CURSE.plague)
		var cp: Vector2 = arrow.pos
		for i: int in range(1, 6):
			g.draw_circle(cp - Vector2(dir * float(i) * 7.0, sin(float(g.clock) * 14.0 + float(i)) * 2.5), 7.0 - float(i), Color(lk[0], 0.5 - float(i) * 0.08))
		g.draw_circle(cp, 11.0, Color(lk[0], 0.3))
		g.draw_circle(cp, 7.5, lk[1])
		g.draw_arc(cp, 7.5, 0.0, TAU, 14, Color(lk[1].darkened(0.5)), 1.6, true)
		g.draw_circle(cp + Vector2(-2.0, -2.0), 2.6, lk[2])
		return

	if arrow.get("curse_splash", false):
		var pos: Vector2 = arrow.pos
		g.draw_line(pos - Vector2(20.0 * dir, 0.0), pos, Color("115224", 0.72), 4.5, true)
		g.draw_circle(pos - Vector2(9.0 * dir, cos(float(g.clock) * 16.0) * 2.0), 2.6, Color("48c96b", 0.65))
		g.draw_circle(pos, 6.0, Color("1b6e32"))
		g.draw_arc(pos, 6.0, 0.0, TAU, 12, Color("0b3617"), 1.5, true)
		g.draw_circle(pos, 2.2, Color("7be092"))
		return

	if arrow.get("lane_bolt", false):
		var bp: Vector2 = arrow.pos
		var b_back := Vector2(dir * 20.0, 0.0)
		g.draw_line(bp - b_back * 1.6, bp, Color(0.55, 0.78, 0.92, 0.35), 4.0, true)
		g.draw_line(bp - b_back, bp, Color("4a3b2c"), 3.0, true)
		g.draw_colored_polygon(PackedVector2Array([bp + Vector2(dir * 6.0, 0.0), bp - Vector2(dir * 4.0, 3.8), bp - Vector2(dir * 4.0, -3.8)]), Color("cfd8df"))
		return

	draw_shot(g, arrow, dir)

# ---- 肉鴿魔王的招牌彈 (roguelike_catalog.BOSS_SHOTS, 2026-11-22) ----------------------------------
# Beams for the shots that run the whole lane, colours for the bursting curses, and the lobbed bombs.
const BOSS_BEAM := {
	"sword":[Color("9fc6e8", 0.45), Color("e4f2ff"), Color("ffffff")],
	"iron":[Color("6d6a64", 0.5), Color("b9b3a6"), Color("f2ede0")],
	"blood":[Color("7a1020", 0.5), Color("c8283c"), Color("ff9aa8")],
	"fire_beam":[Color("a8401a", 0.5), Color("f08a2c"), Color("ffe08a")],
}
const BOSS_CURSE := {
	"plague":[Color("5f8a3a"), Color("2f5a22"), Color("c9f08c")],
	"acid":[Color("a6c81e"), Color("6f8a14"), Color("f1ff9a")],
}
const BOSS_BOMB := { # shell, glow, fuse spark
	"fire":[Color("5a2a18"), Color("ff8a2a"), Color("fff0a0")],
	"harvest":[Color("b88a2e"), Color("f2c75a"), Color("fff6c8")],
	"time":[Color("2c4c7a"), Color("7fb8ff"), Color("e6f4ff")],
	"rune":[Color("4a2a6a"), Color("c58cff"), Color("f3e2ff")],
	"bone":[Color("3a3a2e"), Color("9fd08a"), Color("eef7d8")],
	"acid":[Color("4f5e12"), Color("b8d42a"), Color("f4ffb0")],
}

static func draw_boss_bomb(g, arrow: Dictionary, flight: float) -> void:
	var c: Array = BOSS_BOMB.get(String(arrow.look), BOSS_BOMB.fire)
	var lift: float = 90.0
	var t: float = float(g.clock)
	# Where it will land: a pulsing warning ring that tightens as the shell comes down.
	g.tf(arrow.impact, 0.0, Vector2(1.0, 0.48))
	g.draw_circle(Vector2.ZERO, float(arrow.radius), Color(c[1], 0.10 + 0.12 * flight))
	g.draw_arc(Vector2.ZERO, float(arrow.radius), 0.0, TAU, 32, Color(c[1], 0.55 + 0.25 * sin(t * 14.0)), 2.4, true)
	g.draw_arc(Vector2.ZERO, float(arrow.radius) * maxf(0.12, 1.0 - flight), 0.0, TAU, 24, Color(c[2], 0.6), 1.8, true)
	g.tf()
	var shadow: Vector2 = (arrow.start as Vector2).lerp(arrow.impact, flight)
	g.tf(shadow, 0.0, Vector2(1.0, 0.45))
	g.draw_circle(Vector2.ZERO, 6.0 + 10.0 * flight, Color(0.12, 0.08, 0.05, 0.3))
	g.tf()
	for i: int in range(1, 7):
		var bt: float = maxf(0.0, flight - float(i) * 0.04)
		var bp: Vector2 = (arrow.start as Vector2).lerp(arrow.impact, bt) - Vector2(0.0, sin(bt * PI) * lift)
		g.draw_circle(bp, 6.5 - float(i) * 0.8, Color(c[1], 0.55 - float(i) * 0.08))
	var p: Vector2 = (arrow.pos as Vector2) - Vector2(0.0, sin(flight * PI) * lift)
	g.draw_circle(p, 15.0 + 2.0 * sin(t * 20.0), Color(c[1], 0.25))
	g.draw_circle(p, 10.0, c[0])
	g.draw_arc(p, 10.0, 0.0, TAU, 16, g.INK, 1.8, true)
	g.draw_circle(p + Vector2(-3.0, -3.0), 3.2, Color(c[1], 0.9))
	g.draw_circle(p + Vector2(4.0, -8.0), 3.0 + sin(t * 30.0), c[2])

# ---- shots (2026-11-22) ------------------------------------------------------------------------
# Everything that fires through Battle.shoot(): the model moves the shot in a straight line and lands it
# after B.ARROW_TIME; drawing only lifts it onto an arc and dresses it by shooter, so timing is untouched.
const SHOT_STYLE := {
	"tower":"bolt", "watchtower":"bolt", "ballista_tower":"bolt", "shroud_arbalist":"dark_bolt", "vampire_hunter":"silver_bolt",
	"arquebusier":"bullet", "spearbow":"javelin",
	"prism_mage":"orb", "sigil_weaver":"orb", "spell_mirror":"orb", "spell_tide_magus":"orb", "astrolabe_surveyor":"orb", "seal_bearer":"orb", "arcane_archer":"orb",
	"necromancer":"dark_orb", "funeral_monk":"dark_orb", "mourning_maid":"dark_orb",
	"bellbearer":"ring", "beekeeper":"bees", "net_hunter":"net", "web_spinner":"web",
}
const ORB_COLOR := {
	"prism_mage":Color("e6a1ff"), "sigil_weaver":Color("8fb8ff"), "spell_mirror":Color("b9e6ff"), "spell_tide_magus":Color("5fb4e8"),
	"astrolabe_surveyor":Color("f0c862"), "seal_bearer":Color("f2d27a"), "arcane_archer":Color("c5a4eb"),
	"necromancer":Color("7fd38f"), "funeral_monk":Color("a88fd0"), "mourning_maid":Color("9db0c8"),
}

static func shot_style(arrow: Dictionary) -> String:
	var vk := String(arrow.get("visual_kind", ""))
	if vk == "lord": return "arrow"
	if SHOT_STYLE.has(vk): return SHOT_STYLE[vk] # shooter kind (e.g. ward_phalanx's prism_mage) or 小怪領主
	var sk := String(arrow.get("source", {}).get("kind", ""))
	if SHOT_STYLE.has(sk): return SHOT_STYLE[sk]
	return SHOT_STYLE.get(String(arrow.kind), "arrow")

# 0..1 along the flight, the straight-line end point, and the arc lift for this style.
static func shot_path(arrow: Dictionary, style: String) -> Array:
	var k: float = clampf(1.0 - float(arrow.remaining) / B.ARROW_TIME, 0.0, 1.0)
	var start: Vector2 = arrow.get("start", arrow.pos)
	var pos: Vector2 = arrow.pos
	var end: Vector2 = start + (pos - start) / maxf(k, 0.05) if k > 0.05 else pos
	var lift_share: float = {"arrow":0.16, "javelin":0.14, "net":0.2, "web":0.18, "bees":0.05, "bolt":0.06, "dark_bolt":0.06, "silver_bolt":0.06}.get(style, 0.0)
	var lift: float = clampf(start.distance_to(end) * lift_share, 0.0, 46.0)
	return [k, start, end, lift]

static func arc_at(path: Array, k: float) -> Vector2:
	return (path[1] as Vector2).lerp(path[2], k) - Vector2(0.0, sin(k * PI) * float(path[3]))

static func draw_shot(g, arrow: Dictionary, dir: float) -> void:
	var style := shot_style(arrow)
	var path := shot_path(arrow, style)
	var k: float = path[0]
	var p := arc_at(path, k)
	var ahead := arc_at(path, minf(1.0, k + 0.03)) - p
	var angle: float = ahead.angle() if ahead.length() > 0.01 else (0.0 if dir > 0.0 else PI)
	var t: float = float(g.clock)
	match style:
		"bolt", "dark_bolt", "silver_bolt":
			var shaft := Color("4a3626") if style == "bolt" else (Color("2b2133") if style == "dark_bolt" else Color("8b8f96"))
			var head := Color("9aa0a6") if style == "bolt" else (Color("7a4fa0") if style == "dark_bolt" else Color("eef3f7"))
			if style == "dark_bolt":
				for i: int in range(1, 4):
					g.draw_circle(arc_at(path, maxf(0.0, k - float(i) * 0.07)), 4.5 - float(i), Color(0.35, 0.2, 0.45, 0.32 - float(i) * 0.08))
			g.tf(p, angle)
			g.draw_line(Vector2(-34.0, 0.0), Vector2(-14.0, 0.0), Color(g.INK, 0.14), 2.0, true)
			g.draw_line(Vector2(-14.0, 0.0), Vector2(8.0, 0.0), shaft, 3.2, true)
			g.draw_colored_polygon(PackedVector2Array([Vector2(-14.0, 0.0), Vector2(-19.0, -4.0), Vector2(-11.0, 0.0), Vector2(-19.0, 4.0)]), Color("d7c9a6"))
			g.draw_colored_polygon(PackedVector2Array([Vector2(15.0, 0.0), Vector2(6.0, -4.2), Vector2(8.0, 0.0), Vector2(6.0, 4.2)]), head)
			if style == "silver_bolt": g.draw_circle(Vector2(10.0, -1.5), 1.6, Color(1, 1, 1, 0.5 + 0.5 * sin(t * 30.0)))
			g.tf()
		"bullet":
			var start: Vector2 = path[1]
			if k < 0.45: # muzzle smoke where the shot left
				var puff: float = k / 0.45
				for i: int in range(3):
					g.draw_circle(start + Vector2(dir * (6.0 + i * 7.0 * puff), -3.0 - i * 4.0 * puff), (5.0 + i * 3.0) * (0.6 + puff * 0.6), Color(0.86, 0.84, 0.8, 0.5 * (1.0 - puff)))
				g.draw_circle(start + Vector2(dir * 4.0, 0.0), 6.0 * (1.0 - puff), Color(1.0, 0.8, 0.35, 0.8 * (1.0 - puff)))
			g.draw_line(p - Vector2(dir * 30.0, 0.0), p, Color(1.0, 0.93, 0.7, 0.32), 2.0, true)
			g.draw_circle(p, 3.0, Color("3b3633"))
			g.draw_circle(p + Vector2(-0.8, -0.8), 1.1, Color(1, 1, 1, 0.5))
		"orb", "dark_orb":
			var ck := String(arrow.get("visual_kind", ""))
			if not ORB_COLOR.has(ck): ck = String(arrow.get("source", {}).get("kind", arrow.kind))
			var col: Color = ORB_COLOR.get(ck, ORB_COLOR.get(String(arrow.kind), Color("c5a4eb")))
			for i: int in range(1, 6):
				var trail := arc_at(path, maxf(0.0, k - float(i) * 0.035)) + Vector2(0.0, sin(t * 16.0 + float(i)) * 1.6)
				g.draw_circle(trail, 5.0 - float(i) * 0.75, Color(col, 0.42 - float(i) * 0.07))
			var wob := Vector2(0.0, sin(t * 11.0) * 1.5)
			g.draw_circle(p + wob, 9.0 + sin(t * 18.0), Color(col, 0.22))
			g.draw_circle(p + wob, 5.5, col.darkened(0.25) if style == "dark_orb" else col)
			g.draw_circle(p + wob + Vector2(-1.2, -1.2), 2.3, Color(1, 1, 1, 0.8) if style == "orb" else Color(col.lightened(0.6), 0.85))
		"ring":
			for i: int in range(3):
				var rk := fposmod(t * 3.0 + float(i) / 3.0, 1.0)
				g.draw_arc(p, 4.0 + rk * 12.0, angle - 0.9, angle + 0.9, 10, Color(0.95, 0.82, 0.45, 0.75 * (1.0 - rk)), 2.0, true)
			g.draw_circle(p, 3.2, Color("d9b45a"))
		"bees":
			for i: int in range(5):
				var off := Vector2(sin(t * 22.0 + float(i) * 1.7) * 7.0, cos(t * 19.0 + float(i) * 2.3) * 5.0) + Vector2(-dir * float(i) * 3.0, 0.0)
				g.draw_circle(p + off, 2.2, Color("e0a82e"))
				g.draw_line(p + off + Vector2(-1.5, 0), p + off + Vector2(1.5, 0), Color("2b2116"), 1.0)
				g.draw_circle(p + off + Vector2(0.0, -2.0), 1.4, Color(1, 1, 1, 0.55))
		"net", "web":
			var spin: float = k * TAU * 1.5 * dir
			var col := Color("8a6d45") if style == "net" else Color("f2efe6")
			var r: float = 7.0 + k * 5.0
			g.tf(p, spin)
			for i: int in range(6):
				var a0: float = float(i) * TAU / 6.0
				g.draw_line(Vector2.ZERO, Vector2(cos(a0), sin(a0)) * r, col, 1.2, true)
			g.draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 12, col, 1.0, true)
			g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 14, col, 1.2, true)
			if style == "net":
				for w: int in range(3): g.draw_circle(Vector2(cos(w * TAU / 3.0), sin(w * TAU / 3.0)) * r, 1.8, Color("5b5752"))
			g.tf()
		"javelin":
			g.tf(p, angle)
			g.draw_line(Vector2(-30.0, 0.0), Vector2(6.0, 0.0), Color("6b4a2b"), 2.6, true)
			g.draw_colored_polygon(PackedVector2Array([Vector2(14.0, 0.0), Vector2(5.0, -3.6), Vector2(5.0, 3.6)]), Color("b6b8bc"))
			g.tf()
		_:
			# A feathered arrow on its arc: wooden shaft, goose fletching, steel point and a faint streak.
			for i: int in range(1, 4):
				var a := arc_at(path, maxf(0.0, k - float(i) * 0.05))
				var b2 := arc_at(path, maxf(0.0, k - float(i - 1) * 0.05))
				g.draw_line(a, b2, Color(g.INK, 0.12 - float(i) * 0.03), 1.4, true)
			g.tf(p, angle)
			g.draw_line(Vector2(-18.0, 0.0), Vector2(4.0, 0.0), Color("6b4a2b"), 2.2, true)
			g.draw_colored_polygon(PackedVector2Array([Vector2(-18.0, 0.0), Vector2(-23.0, -3.6), Vector2(-15.0, 0.0), Vector2(-23.0, 3.6)]), Color("ece2c6"))
			g.draw_colored_polygon(PackedVector2Array([Vector2(9.0, 0.0), Vector2(2.0, -3.0), Vector2(2.0, 3.0)]), Color("b6b8bc"))
			g.draw_polyline(PackedVector2Array([Vector2(2.0, -3.0), Vector2(9.0, 0.0), Vector2(2.0, 3.0)]), Color(g.INK, 0.6), 1.0, true)
			g.tf()

## Card toss & summon ring, gold harvest coin parabola, and staggered death fade.
static func draw_play(g, e: Dictionary, progress: float) -> void:
	var card: String = e.card
	var is_spell: bool = B.CARDS.get(card, {}).get("type", "") == "spell"
	var hand_pos: Vector2 = g.to_model(g.card_rect(e.get("slot", 0)).get_center() if int(e.team) == g.me else preload("res://battle_hud.gd").gold_anchor(1))
	if is_spell:
		# For spells, fly a fast glowing sigil to the Lord's hand so the Lord hurls the spell.
		if progress < 0.45:
			var k: float = progress / 0.45
			var dest: Vector2 = spell_origin(g.model, int(e.team), e.pos)
			var at: Vector2 = hand_pos.lerp(dest, k) - Vector2(0.0, sin(k * PI) * 40.0)
			var col := spell_color(card)
			g.draw_circle(at, 8.0 * (1.0 - k * 0.3), Color(col, 0.55))
			g.draw_circle(at, 3.5, Color(1.0, 0.95, 0.78, 0.85))
		return
	if progress < 0.58:
		var k: float = progress / 0.58
		var arc: Vector2 = hand_pos.lerp(e.pos, k) - Vector2(0.0, sin(k * PI) * 65.0)
		var tilt: float = -0.22 * (1.0 - k) * (1.0 if int(e.team) == 0 else -1.0)
		g.tf(arc, tilt, Vector2(1.0 - 0.12 * k, 1.0 - 0.12 * k))
		g.draw_card_art(card, Rect2(-35.0, -30.0, 70.0, 60.0), int(e.team), Color(1, 1, 1, 0.85))
		g.tf()
	else:
		var k: float = (progress - 0.58) / 0.42
		g.tf(e.pos + Vector2(0.0, 12.0), 0.0, Vector2(1.0, 0.42))
		g.draw_arc(Vector2.ZERO, 18.0 + k * 34.0, 0.0, TAU, 24, Color(0.84, 0.68, 0.32, (1.0 - k) * 0.75), 2.4, true)
		g.draw_arc(Vector2.ZERO, 8.0 + k * 18.0, 0.0, TAU, 18, Color(1.0, 0.94, 0.72, (1.0 - k) * 0.55), 1.6, true)
		g.tf()
		for i: int in range(5):
			var a := float(i) * TAU / 5.0 + 0.4
			var dp: Vector2 = e.pos + Vector2(cos(a) * (10.0 + k * 24.0), 10.0 + sin(a) * (4.0 + k * 9.0) - k * 10.0)
			g.draw_circle(dp, 3.0 + k * 3.0, Color(0.60, 0.48, 0.33, (1.0 - k) * 0.45))

static func model_to_screen(g, model_pos: Vector2) -> Vector2:
	var prev_active: bool = g.cinematic.field_active
	var prev_mirror: bool = g.field_mirror
	g.cinematic.field_active = true
	g.field_mirror = g.mirror_view
	var cam: Transform2D = g.cinematic.field_transform(g)
	g.cinematic.field_active = prev_active
	g.field_mirror = prev_mirror
	return cam * model_pos

static func draw_ink_hud(g, e: Dictionary, progress: float) -> void:
	var start: Vector2 = model_to_screen(g, e.pos)
	var target: Vector2 = preload("res://economy_hud.gd").PURSE.get_center() if int(e.team) == g.me else preload("res://battle_hud.gd").gold_anchor(1)+Vector2(0,14)
	var ease_t: float = 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 2.0)
	var pos: Vector2 = start.lerp(target, ease_t) - Vector2(0.0, sin(ease_t * PI) * 62.0)
	var fade: float = 1.0 - clampf((progress - 0.85) / 0.15, 0.0, 1.0)
	for i: int in range(1, 3):
		var bt: float = maxf(0.0, ease_t - float(i) * 0.05)
		var bp: Vector2 = start.lerp(target, bt) - Vector2(0.0, sin(bt * PI) * 62.0)
		g.draw_circle(bp, 3.2 - float(i) * 0.8, Color(1.0, 0.86, 0.35, (0.55 - float(i) * 0.18) * fade))
	g.draw_circle(pos, 7.6, Color("d9a62e", fade))
	g.draw_arc(pos, 7.6, 0.0, TAU, 12, Color("6c4b14", fade), 1.4, true)
	g.draw_circle(pos + Vector2(-2.0, -2.0), 2.3, Color("fff0a6", fade))
	if progress > 0.84:
		var rp := (progress - 0.84) / 0.16
		g.draw_arc(target, 10.0 + rp * 20.0, 0.0, TAU, 18, Color(1.0, 0.88, 0.42, (1.0 - rp) * 0.85), 2.2, true)

static func draw_ink(g, e: Dictionary, progress: float) -> void:
	draw_ink_hud(g, e, progress)

static func draw_death(g, e: Dictionary, progress: float) -> void:
	var kind: String = e.get("art_kind", e.card)
	var face: float = float(e.get("face", 1.0 if int(e.team) == 0 else -1.0))
	var is_bldg: bool = B.CARDS.has(kind) and B.CARDS[kind].type == "building"
	if is_bldg:
		face = 1.0 if int(e.team) == 0 else -1.0
	var death_pos: Vector2 = e.pos
	if not is_bldg:
		death_pos.x -= face * 16.0 * progress
	var fade := 1.0 - progress
	if g.adventure.is_opening() and int(e.team) == 1 and kind == "bandit":
		g.draw_fitted_facing(g.adventure.opening.BANDIT, Rect2(death_pos - Vector2(43.0, 73.0), Vector2(86.0, 104.0)), -1.0, Color(1, 1, 1, fade))
	elif not is_bldg:
		var tilt: float = -face * 0.28 * progress
		var rect: Rect2 = g.actor_rect(kind)
		g.tf(death_pos + Vector2(0.0, 10.0 * progress), tilt, Vector2(face, 1.0 - 0.14 * progress))
		g.draw_texture_rect(g.art(kind, int(e.team)), rect, false, Color(1.0, 0.96, 0.90, fade))
		g.tf()
	else:
		g.draw_actor(kind, int(e.team), death_pos, face, Color(1, 1, 1, fade))
	for i: int in range(6):
		var a := float(i) * TAU / 6.0 + progress * 1.4
		var p: Vector2 = e.pos + Vector2(cos(a) * progress * 26.0, sin(a) * progress * 16.0 - progress * 18.0)
		g.draw_circle(p, 3.0 * fade, Color(g.INK, fade * 0.85))

## Rising smoke wisps from breached castle gates.
static func draw_breach_smoke(g) -> void:
	if not g.fx_enabled:
		return
	var m = g.model
	for team: int in range(2):
		for lane: int in m.active_lanes:
			if m.gates[team][lane] > 0:
				continue
			var gate := Vector2(L.gate_icon_x(team), L.cell_center(Vector2i(0, lane)).y)
			for i: int in range(3):
				var cyc: float = fposmod(float(g.clock) * (0.35 + float(i) * 0.08) + float(lane) * 0.31 + float(team) * 0.17, 1.0)
				var sx: float = gate.x + sin(float(g.clock) * 1.6 + float(i) * 2.1 + float(lane)) * 10.0 + (float(i) - 1.0) * 9.0
				var sy: float = gate.y + 8.0 - cyc * 46.0
				var sa: float = sin(cyc * PI) * 0.22
				g.draw_circle(Vector2(sx, sy), 6.0 + cyc * 11.0, Color(0.24, 0.20, 0.16, sa))
