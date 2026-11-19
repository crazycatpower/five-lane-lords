extends RefCounted
## Presentation-only cinematic camera, atmosphere, battlefield decals, hit-stop, and Cut-In director.
## Keeps simulation (battle.gd) untouched while elevating battle footage for live play and YouTube.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const DayCycle = preload("res://day_cycle.gd")

const FIELD_CENTER := Vector2(800.0, 394.0)
const MAX_DECALS := 28
const MAX_SPARKS := 80
const FINISHER_SLOWMO_TIME := 0.85
const MAX_IMPULSE := 8.0
const MAX_IMPULSE_VEL := 120.0
const MAX_SHAKE_OFFSET := 10.0
const SPRING_MAX_STEP := 0.01

static var sun_beam_tex: GradientTexture2D
static var ember_glow_tex: GradientTexture2D

var enabled := true
var theater_mode := false
var theater_hint_left := 0.0

var field_active := false
var zoom := 1.0
var target_zoom := 1.0
var focus := FIELD_CENTER
var target_focus := FIELD_CENTER
var focus_hold := 0.0

var trauma := 0.0
var impulse := Vector2.ZERO
var impulse_vel := Vector2.ZERO

var hitstop_left := 0.0
var flash_alpha := 0.0
var flash_color := Color(1.0, 0.94, 0.78)

var finisher_active := false
var finisher_age := 0.0
var letterbox := 0.0

var cutin: Dictionary = {}
var decals: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var shockwaves: Array[Dictionary] = []
var showcase_chapter: Dictionary = {}
var showcase_card: Dictionary = {}
var showcase_cards: Array[Dictionary] = [{}, {}]
var showcase_queues: Array = [[], []]
var mini_hints: Array = [[], []]
var showcase_sub: Dictionary = {}

## Reset transient battle presentation state when entering or restarting a battle.
func reset() -> void:
	field_active = false
	zoom = 1.0
	target_zoom = 1.0
	focus = FIELD_CENTER
	target_focus = FIELD_CENTER
	focus_hold = 0.0
	trauma = 0.0
	impulse = Vector2.ZERO
	impulse_vel = Vector2.ZERO
	hitstop_left = 0.0
	flash_alpha = 0.0
	finisher_active = false
	finisher_age = 0.0
	letterbox = 1.0 if theater_mode else 0.0
	cutin = {}
	decals.clear()
	sparks.clear()
	shockwaves.clear()
	showcase_chapter = {}
	showcase_card = {}
	showcase_cards = [{}, {}]
	showcase_queues = [[], []]
	mini_hints = [[], []]
	showcase_sub = {}

static func clamp_focus(p: Vector2, z: float) -> Vector2:
	if z <= 1.001:
		return FIELD_CENTER
	var half := L.FIELD_FRAME.size * 0.5 / z
	var lo := L.FIELD_FRAME.position + half
	var hi := L.FIELD_FRAME.end - half
	return Vector2(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y))

static func screen_pos(g, model_pos: Vector2) -> Vector2:
	return Vector2(L.VIEWPORT_SIZE.x - model_pos.x, model_pos.y) if g.mirror_view else model_pos

## Map model/field local space into screen space inside FIELD_FRAME.
func field_transform(g) -> Transform2D:
	if not field_active:
		return g.view_mirror() if g.field_mirror else Transform2D.IDENTITY
	var shake_vec := Vector2.ZERO
	if g.shake_enabled:
		if trauma > 0.001:
			var t_clamped := minf(trauma, 1.0)
			var amp := t_clamped * t_clamped * 16.0
			shake_vec = Vector2(
				sin(g.clock * 117.0) + 0.5 * cos(g.clock * 193.0),
				cos(g.clock * 131.0) + 0.5 * sin(g.clock * 211.0)
			) * amp * 0.67
		shake_vec += impulse
		if not shake_vec.is_finite():
			shake_vec = Vector2.ZERO
		shake_vec = shake_vec.limit_length(MAX_SHAKE_OFFSET)
	var safe_zoom := clampf(zoom, 1.0, 1.35) if is_finite(zoom) else 1.0
	var active_focus := clamp_focus(focus if focus.is_finite() else FIELD_CENTER, safe_zoom)
	var cam := Transform2D(0.0, Vector2(safe_zoom, safe_zoom), 0.0, FIELD_CENTER + shake_vec - active_focus * safe_zoom)
	return cam * (g.view_mirror() if g.field_mirror else Transform2D.IDENTITY)

## Inverse transform so mouse clicks and cell previews remain accurate under any zoom or shake.
func screen_to_field(g, p: Vector2) -> Vector2:
	var prev_active := field_active
	var prev_mirror: bool = g.field_mirror
	field_active = true
	g.field_mirror = false
	var cam := field_transform(g)
	field_active = prev_active
	g.field_mirror = prev_mirror
	var unzoomed := cam.affine_inverse() * p
	return Vector2(L.VIEWPORT_SIZE.x - unzoomed.x, unzoomed.y) if g.mirror_view else unzoomed

func begin_field(g) -> void:
	field_active = true
	g.tf()

func end_field(g) -> void:
	field_active = false
	g.field_mirror = false
	g.tf()

## Effective simulation-presentation time scale (for bullet-time finisher & brief hit-stop).
func fx_dt(dt: float) -> float:
	if hitstop_left > 0.0:
		return dt * 0.05
	if finisher_active and finisher_age < FINISHER_SLOWMO_TIME:
		var k := finisher_age / FINISHER_SLOWMO_TIME
		return dt * lerpf(0.20, 1.0, k * k)
	return dt

## Advance camera springs, slow-mo timer, particles, shockwaves, and decals.
func step(g, dt: float) -> void:
	theater_hint_left = maxf(0.0, theater_hint_left - dt)
	hitstop_left = maxf(0.0, hitstop_left - dt)
	flash_alpha = maxf(0.0, flash_alpha - dt * 2.2)
	trauma = maxf(0.0, trauma - dt * 1.45)

	# Spring-damper kick return: substep and clamp so frame spikes (e.g. 8x speed) never diverge.
	var k_spring := 160.0
	var damp := 18.0
	var rem := minf(maxf(dt, 0.0), 0.1)
	while rem > 0.00001:
		var sub := minf(rem, SPRING_MAX_STEP)
		impulse_vel += (-k_spring * impulse - damp * impulse_vel) * sub
		impulse += impulse_vel * sub
		rem -= sub
	impulse = impulse.limit_length(MAX_IMPULSE)
	impulse_vel = impulse_vel.limit_length(MAX_IMPULSE_VEL)
	if impulse.length() < 0.05 and impulse_vel.length() < 0.1:
		impulse = Vector2.ZERO
		impulse_vel = Vector2.ZERO

	if finisher_active:
		finisher_age += dt

	# Keep placement responsive: ease back toward 1x whenever player holds/drags a card.
	var aiming: bool = g.selected >= 0 or g.dragging
	if aiming and not finisher_active:
		focus_hold = minf(focus_hold, 0.12)
	if focus_hold > 0.0:
		focus_hold = maxf(0.0, focus_hold - dt)
	else:
		target_zoom = 1.0
		target_focus = FIELD_CENTER

	var active_enabled: bool = enabled and not (g.adventure != null and g.adventure.is_opening())
	var goal_zoom := clampf(target_zoom, 1.0, 1.35) if active_enabled else 1.0
	var goal_focus := target_focus if active_enabled else FIELD_CENTER
	var cam_rate := 1.0 - exp(-maxf(dt, 0.0) * (8.5 if focus_hold > 0.0 else 4.2))
	zoom = clampf(lerpf(zoom, goal_zoom, cam_rate), 1.0, 1.35)
	focus = focus.lerp(clamp_focus(goal_focus, zoom), cam_rate)

	if not cutin.is_empty():
		cutin.life -= dt
		if cutin.life <= 0.0:
			cutin = {}

	if not showcase_chapter.is_empty():
		showcase_chapter.life -= dt
		if showcase_chapter.life <= 0.0:
			showcase_chapter = {}
	if not showcase_card.is_empty():
		showcase_card.life -= dt
		if showcase_card.life <= 0.0:
			showcase_card = {}
	for side: int in range(2):
		if not showcase_cards[side].is_empty():
			showcase_cards[side].life -= dt
			if showcase_cards[side].life <= 0.0:
				showcase_cards[side] = {}
		if showcase_cards[side].is_empty() and not showcase_queues[side].is_empty():
			var next_entry: Dictionary = showcase_queues[side].pop_front()
			var dur := 3.8 if not showcase_queues[side].is_empty() else 5.4
			_activate_spotlight(next_entry, dur)
		var kept: Array = []
		for mh: Dictionary in mini_hints[side]:
			mh.life -= dt
			if mh.life > 0.0:
				kept.append(mh)
		mini_hints[side] = kept
	if not showcase_sub.is_empty():
		showcase_sub.life -= dt
		if showcase_sub.life <= 0.0:
			showcase_sub = {}

	var want_bars := 0.0
	if theater_mode:
		want_bars = 1.0
	elif active_enabled and finisher_active:
		want_bars = 1.0
	elif active_enabled and g.intro_left > 0.25:
		want_bars = 0.72
	elif active_enabled and not cutin.is_empty():
		want_bars = 0.45
	letterbox = move_toward(letterbox, want_bars, dt * 4.0)

	var eff_dt := fx_dt(dt)
	for s: Dictionary in sparks:
		s.life -= eff_dt
		s.pos += s.vel * eff_dt
		s.vel.y += s.gravity * eff_dt
		s.vel *= maxf(0.0, 1.0 - s.drag * eff_dt)
	sparks = sparks.filter(func(s: Dictionary) -> bool: return s.life > 0.0)

	for w: Dictionary in shockwaves:
		w.life -= eff_dt
	shockwaves = shockwaves.filter(func(w: Dictionary) -> bool: return w.life > 0.0)

	for d: Dictionary in decals:
		d.life -= eff_dt
	decals = decals.filter(func(d: Dictionary) -> bool: return d.life > 0.0)

func add_spark(pos: Vector2, vel: Vector2, color: Color, size: float, life: float, gravity: float = 160.0, drag: float = 2.0) -> void:
	if sparks.size() >= MAX_SPARKS:
		sparks.remove_at(0)
	sparks.append({"pos": pos, "vel": vel, "color": color, "size": size, "life": life, "duration": life, "gravity": gravity, "drag": drag})

func add_decal(kind: String, pos: Vector2, radius: float, life: float, angle: float = 0.0) -> void:
	if decals.size() >= MAX_DECALS:
		decals.remove_at(0)
	decals.append({"kind": kind, "pos": pos, "radius": radius, "life": life, "duration": life, "angle": angle})

func add_shockwave(pos: Vector2, radius: float, color: Color, life: float = 0.48, width: float = 4.0) -> void:
	shockwaves.append({"pos": pos, "radius": radius, "color": color, "life": life, "duration": life, "width": width})

## Add a bounded camera kick impulse velocity so stacked high-speed events cannot throw the camera off-screen.
func add_impulse(delta: Vector2) -> void:
	impulse_vel = (impulse_vel + delta).limit_length(MAX_IMPULSE_VEL)

func trigger_focus(g, model_pos: Vector2, zoom_to: float, hold: float) -> void:
	if not enabled:
		return
	var sp := screen_pos(g, model_pos)
	target_zoom = maxf(target_zoom, zoom_to) if focus_hold > 0.0 else zoom_to
	target_focus = clamp_focus(sp, target_zoom)
	focus_hold = maxf(focus_hold, hold)

func trigger_cutin(lord: String, team: int) -> void:
	if not enabled or not B.LORDS.has(lord):
		return
	cutin = {"lord": lord, "team": team, "life": 1.55, "duration": 1.55}

## Director video-editing helpers: chapter slate, zoomed card spotlight badge, and YT subtitle bar.
func trigger_chapter(title: String, sub: String = "", duration: float = 2.8) -> void:
	if not enabled:
		return
	showcase_chapter = {"title": title, "sub": sub, "life": duration, "duration": duration}

func _make_spotlight(model_pos: Vector2, team: int, kind: String, desc: String, duration: float) -> Dictionary:
	var card: Dictionary = B.CARDS.get(kind, {})
	return {
		"team": team,
		"kind": kind,
		"name": String(card.get("name", kind)),
		"role": String(card.get("role", "")),
		"cost": int(card.get("cost", 0)),
		"desc": desc,
		"pos": model_pos,
		"life": duration,
		"duration": duration,
	}

func _activate_spotlight(entry: Dictionary, duration: float) -> void:
	entry["life"] = duration
	entry["duration"] = duration
	var side := clampi(int(entry.get("team", 0)), 0, 1)
	showcase_cards[side] = entry
	showcase_card = entry

func push_repeat_hint(team: int, kind: String, duration: float = 2.6) -> void:
	if not enabled or not B.CARDS.has(kind):
		return
	var side := clampi(team, 0, 1)
	var card: Dictionary = B.CARDS[kind]
	mini_hints[side].append({
		"team": side,
		"kind": kind,
		"name": String(card.get("name", kind)),
		"cost": int(card.get("cost", 0)),
		"life": duration,
		"duration": duration,
	})
	if mini_hints[side].size() > 3:
		mini_hints[side].pop_front()

func enqueue_spotlight(_g, model_pos: Vector2, team: int, kind: String, desc: String, duration: float = 5.4) -> void:
	if not enabled:
		return
	var side := clampi(team, 0, 1)
	var entry := _make_spotlight(model_pos, team, kind, desc, duration)
	if showcase_cards[side].is_empty():
		_activate_spotlight(entry, duration)
	else:
		showcase_queues[side].append(entry)

func trigger_spotlight(g, model_pos: Vector2, team: int, kind: String, desc: String, zoom_to: float = 1.0, hold: float = 0.0, duration: float = 4.8) -> void:
	if not enabled:
		return
	if zoom_to > 1.001 and hold > 0.0:
		trigger_focus(g, model_pos, zoom_to, hold)
	_activate_spotlight(_make_spotlight(model_pos, team, kind, desc, duration), duration)

func trigger_subtitle(text: String, team: int = -1, duration: float = 3.4) -> void:
	if not enabled or text.is_empty():
		return
	showcase_sub = {"text": text, "team": team, "life": duration, "duration": duration}

## Consume model visual events for camera, sparks, decals, hit-stop, and Cut-In choreography.
func on_event(g, e: Dictionary) -> void:
	if g.adventure != null and g.adventure.is_opening():
		return
	var kind: String = e.get("kind", "")
	var pos: Vector2 = e.get("pos", FIELD_CENTER)
	var sp := screen_pos(g, pos)
	var dir_x := -1.0 if sp.x < FIELD_CENTER.x else 1.0

	match kind:
		"breach":
			if g.shake_enabled:
				trauma = maxf(trauma, 0.24)
				add_impulse(Vector2(dir_x * 70.0, 24.0))
			if enabled:
				hitstop_left = maxf(hitstop_left, 0.04)
				flash_alpha = maxf(flash_alpha, 0.22)
				flash_color = Color(1.0, 0.86, 0.56)
				if g.music != null and g.music.has_method("duck_pulse"):
					g.music.duck_pulse(0.45, 0.65)
			if g.fx_enabled:
				add_shockwave(pos, 145.0, Color("e8b948"), 0.55, 5.0)
				add_decal("rubble", pos + Vector2(-dir_x * 16.0, 18.0), 34.0, 14.0)
				for i: int in range(14):
					var a := -PI * 0.85 + (float(i) / 13.0) * PI * 0.7
					var spd := 90.0 + fmod(i * 47.0, 130.0)
					add_spark(pos, Vector2(cos(a) * (-dir_x), sin(a)) * spd, Color("6e4a28") if i % 2 == 0 else Color("d8aa54"), 3.2, 0.55, 320.0, 1.8)
		"invaded":
			if g.shake_enabled:
				trauma = maxf(trauma, 0.34)
				add_impulse(Vector2(dir_x * 95.0, 32.0))
			if enabled:
				finisher_active = true
				finisher_age = 0.0
				trigger_focus(g, pos, 1.12, 1.25)
				hitstop_left = 0.065
				flash_alpha = 0.38
				flash_color = Color(1.0, 0.94, 0.76)
				if g.music != null and g.music.has_method("duck_pulse"):
					g.music.duck_pulse(0.32, 0.95)
			if g.fx_enabled:
				add_shockwave(pos, 185.0, Color("f6ce67"), 0.72, 6.0)
				add_shockwave(pos, 115.0, Color("ffffff"), 0.45, 3.0)
				for i: int in range(18):
					var a := float(i) * TAU / 18.0
					add_spark(pos, Vector2(cos(a), sin(a)) * (110.0 + float(i % 4) * 45.0), Color("f0c450") if i % 2 == 0 else Color("b03b2a"), 3.6, 0.75, 220.0, 1.6)
		"finish":
			if enabled and not finisher_active:
				finisher_active = true
				finisher_age = 0.0
				trigger_focus(g, pos, 1.08, 1.1)
				flash_alpha = maxf(flash_alpha, 0.22)
		"hero_slash":
			if g.shake_enabled:
				trauma = maxf(trauma, 0.18)
				var face := 1.0 if e.team == 0 else -1.0
				if g.mirror_view:
					face = -face
				add_impulse(Vector2(face * 65.0, -16.0))
			if enabled:
				hitstop_left = maxf(hitstop_left, 0.035)
				flash_alpha = maxf(flash_alpha, 0.18)
				flash_color = Color(1.0, 0.91, 0.62)
				trigger_cutin("adventure", e.team)
				if g.music != null and g.music.has_method("duck_pulse"):
					g.music.duck_pulse(0.55, 0.55)
			if g.fx_enabled:
				for i: int in range(12):
					var fwd := 1.0 if e.team == 0 else -1.0
					add_spark(pos + Vector2(fwd * float(i) * 28.0, -18.0 + (float(i % 3) - 1.0) * 14.0), Vector2(fwd * 140.0, -40.0 + float(i % 5) * 20.0), Color("ffe48f"), 2.8, 0.42, 120.0, 3.0)
		"skill":
			if g.shake_enabled:
				trauma = maxf(trauma, 0.20)
				add_impulse(Vector2(0.0, -40.0))
			if enabled:
				flash_alpha = maxf(flash_alpha, 0.22)
				flash_color = Color(1.0, 0.88, 0.55)
				trigger_cutin(e.get("lord", ""), e.team)
				if g.music != null and g.music.has_method("duck_pulse"):
					g.music.duck_pulse(0.45, 0.70)
			if g.fx_enabled:
				add_shockwave(pos + Vector2(0, -18), 160.0, Color("f6ce67"), 0.65, 5.0)
				add_shockwave(pos + Vector2(0, -18), 95.0, Color("ffffff"), 0.42, 3.0)
				for i: int in range(14):
					var a := float(i) * TAU / 14.0
					add_spark(pos + Vector2(0, -18), Vector2(cos(a), sin(a)) * 135.0, Color("ffe28a"), 2.8, 0.55, 160.0, 2.2)
		"stone_impact":
			if g.shake_enabled:
				trauma = maxf(trauma, 0.12)
				add_impulse(Vector2(0.0, 42.0))
			if g.fx_enabled:
				add_decal("crater", pos + Vector2(0, 14), e.get("radius", 60.0) * 0.52, 12.0)
				add_shockwave(pos, e.get("radius", 65.0) * 1.15, Color("c48d4e"), 0.42, 3.5)
				for i: int in range(10):
					var ang := -PI * 0.9 + (float(i) / 9.0) * PI * 0.8
					add_spark(pos, Vector2(cos(ang), sin(ang)) * (70.0 + float(i % 3) * 45.0), Color("5b4734") if i % 2 == 0 else Color("df9b3c"), 2.8, 0.48, 340.0, 1.8)
		"charge_impact":
			if g.shake_enabled:
				trauma = maxf(trauma, 0.08)
				var f: float = e.get("face", 1.0)
				if g.mirror_view:
					f = -f
				add_impulse(Vector2(f * 40.0, 0.0))
			if g.fx_enabled:
				add_shockwave(pos + Vector2(0, -8), 48.0, Color("ead296"), 0.32, 2.5)
				for i: int in range(6):
					add_spark(pos + Vector2(0, -6), Vector2((float(i % 2) - 0.5) * 90.0, -70.0 - float(i) * 12.0), Color("dfd0aa"), 2.4, 0.35, 220.0, 2.5)
		"spell":
			if g.shake_enabled:
				trauma = maxf(trauma, 0.06)
			if g.fx_enabled:
				add_decal("rune", pos + Vector2(0, 12), e.get("radius", 50.0) * 0.65, 9.0)
		"ramp":
			if enabled and g.music != null and g.music.has_method("duck_pulse"):
				g.music.duck_pulse(0.68, 0.55)
		"nightfall":
			if enabled and e.get("first", false) and g.music != null and g.music.has_method("duck_pulse"):
				g.music.duck_pulse(0.62, 0.65)
		"hit":
			if g.fx_enabled and sparks.size() < MAX_SPARKS - 4:
				var attacker: String = e.get("attacker", "")
				if attacker in ["knight", "corpse_giant", "ram", "catapult", "reaper"] or attacker.begins_with("lord_"):
					if g.shake_enabled:
						trauma = maxf(trauma, 0.09)
					for i: int in range(3):
						var a := -PI * 0.25 + float(i) * 0.8
						add_spark(pos + Vector2(0, -14), Vector2(cos(a), sin(a)) * 85.0, Color("ffe28a"), 2.0, 0.22, 180.0, 3.0)
		"death":
			if g.fx_enabled and sparks.size() < MAX_SPARKS - 6:
				add_decal("ash", pos + Vector2(0, 18), 18.0, 8.0)
				var col := Color("c94b3b") if e.team == 0 else Color("4d7ec9")
				for i: int in range(6):
					var ang := -PI + float(i) * PI / 5.0
					add_spark(pos + Vector2(0, -12), Vector2(cos(ang) * 55.0, sin(ang) * 70.0 - 20.0), col if i % 2 == 0 else Color("3b2c20"), 2.5, 0.42, 220.0, 2.2)

static func beam_tex() -> GradientTexture2D:
	if sun_beam_tex == null:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.94, 0.72, 0.22))
		ramp.set_color(1, Color(1.0, 0.90, 0.65, 0.0))
		sun_beam_tex = GradientTexture2D.new()
		sun_beam_tex.gradient = ramp
		sun_beam_tex.fill = GradientTexture2D.FILL_LINEAR
		sun_beam_tex.fill_from = Vector2(0.0, 0.0)
		sun_beam_tex.fill_to = Vector2(0.0, 1.0)
		sun_beam_tex.width = 64
		sun_beam_tex.height = 128
	return sun_beam_tex

## Painted under actors and grid highlights: drifting cloud shadows and lingering battle scars.
func paint_ground(g, field: Rect2) -> void:
	if g.fx_enabled:
		# Drifting cloud shadows keep the parchment turf feeling alive even in quiet openings.
		var dark := DayCycle.darkness(g.model)
		var cloud_alpha := lerpf(0.065, 0.025, dark)
		for i: int in range(3):
			var span := field.size.x + 560.0
			var cx := field.position.x - 280.0 + fposmod(g.clock * (18.0 + i * 7.0) + i * 520.0, span)
			var cy := field.position.y + 115.0 + i * 175.0 + sin(g.clock * 0.25 + i) * 18.0
			g.tf(Vector2(cx, cy), -0.14, Vector2(2.6 + i * 0.35, 0.75))
			g.draw_circle(Vector2.ZERO, 105.0, Color(0.14, 0.12, 0.08, cloud_alpha))
			g.draw_circle(Vector2(65.0, 14.0), 75.0, Color(0.14, 0.12, 0.08, cloud_alpha * 0.8))
			g.tf()

	for d: Dictionary in decals:
		var fade := clampf(d.life / 3.0, 0.0, 1.0)
		match d.kind:
			"crater":
				g.tf(d.pos, 0.0, Vector2(1.0, 0.42))
				g.draw_circle(Vector2.ZERO, d.radius, Color(0.18, 0.13, 0.08, 0.34 * fade))
				g.draw_arc(Vector2.ZERO, d.radius * 0.85, 0.0, TAU, 18, Color(0.12, 0.08, 0.05, 0.42 * fade), 2.0, true)
				g.tf()
			"rubble":
				g.tf(d.pos, 0.0, Vector2(1.0, 0.48))
				g.draw_circle(Vector2.ZERO, d.radius, Color(0.24, 0.18, 0.12, 0.28 * fade))
				g.tf()
				for k: int in range(5):
					var offs := Vector2((k - 2) * 11.0, sin(k * 2.1) * 8.0)
					g.draw_circle(d.pos + offs, 3.2 - float(k % 2), Color(0.32, 0.25, 0.18, 0.65 * fade))
			"rune":
				g.tf(d.pos, 0.0, Vector2(1.0, 0.40))
				g.draw_arc(Vector2.ZERO, d.radius, 0.0, TAU, 24, Color(0.45, 0.32, 0.65, 0.28 * fade), 2.0, true)
				g.tf()
			"ash":
				g.tf(d.pos, 0.0, Vector2(1.0, 0.42))
				g.draw_circle(Vector2.ZERO, d.radius, Color(0.20, 0.16, 0.12, 0.24 * fade))
				g.tf()

## Drawn over actors and DayCycle.light (still inside field camera transform): sparks, shockwaves, motes/embers/rays, impact flash.
func paint_atmosphere(g, field: Rect2) -> void:
	if g.fx_enabled:
		var phase: int = g.model.day_phase()
		var dark := DayCycle.darkness(g.model)
		# Daytime/noon sunlit god rays slanting softly from upper-left.
		if phase <= 1:
			var beam_alpha := 0.55 if phase == 0 else 0.72
			for i: int in range(4):
				var bx := field.position.x + 160.0 + i * 330.0 + sin(g.clock * 0.2 + i) * 28.0
				var top_w := 56.0 + (i % 2) * 22.0
				var bot_x := bx + 170.0
				var bot_w := 145.0 + (i % 2) * 35.0
				var poly := PackedVector2Array([
					Vector2(bx, field.position.y - 10.0),
					Vector2(bx + top_w, field.position.y - 10.0),
					Vector2(bot_x + bot_w, field.end.y + 10.0),
					Vector2(bot_x, field.end.y + 10.0),
				])
				g.draw_colored_polygon(poly, Color(1.0, 0.93, 0.70, 0.085 * beam_alpha))

		# Ambient drifting motes (day pollen / dusk embers / night mist fireflies).
		var mote_count := 26 if phase == 2 else 20
		for i: int in range(mote_count):
			var nx: float = g.scenery_noise(i, 401)
			var ny: float = g.scenery_noise(i, 402)
			var drift: float = fposmod(g.clock * (0.04 + 0.03 * nx) + ny, 1.0)
			var px: float = field.position.x + fposmod(nx * field.size.x + g.clock * (14.0 if phase == 2 else 9.0) + sin(g.clock * 0.9 + i) * 22.0, field.size.x)
			var py: float
			var col: Color
			var r: float = 1.6 + g.scenery_noise(i, 403) * 1.8
			if phase == 2: # Dusk embers rising
				py = field.end.y - drift * field.size.y
				var tw := 0.45 + 0.55 * sin(g.clock * 7.0 + i * 1.9)
				col = Color(1.0, 0.62, 0.22, 0.52 * tw * sin(drift * PI))
			elif phase == 3 and dark > 0.2: # Night mist & warm/blue sparks
				py = field.position.y + fposmod(ny * field.size.y + sin(g.clock * 0.6 + i) * 26.0, field.size.y)
				var tw := 0.4 + 0.6 * sin(g.clock * 4.5 + i * 2.3)
				col = Color(0.68, 0.82, 1.0, 0.36 * tw * dark) if i % 3 != 0 else Color(1.0, 0.74, 0.32, 0.42 * tw * dark)
			else: # Sunlit dust motes
				py = field.position.y + fposmod(ny * field.size.y + drift * 90.0, field.size.y)
				col = Color(1.0, 0.95, 0.76, 0.28 * sin(drift * PI))
			g.draw_circle(Vector2(px, py), r, col)

		for w: Dictionary in shockwaves:
			var prog: float = 1.0 - float(w.life) / float(w.duration)
			var rr: float = float(w.radius) * (0.2 + 0.8 * (1.0 - pow(1.0 - prog, 2.0)))
			var alpha: float = (1.0 - prog) * 0.85
			g.draw_arc(w.pos, rr, 0.0, TAU, 36, Color(w.color, alpha), float(w.width) * (1.0 - prog * 0.5), true)
			g.draw_arc(w.pos, rr * 0.82, 0.0, TAU, 32, Color(1.0, 0.96, 0.82, alpha * 0.5), 1.5, true)

		for s: Dictionary in sparks:
			var alpha: float = clampf(float(s.life) / float(s.duration), 0.0, 1.0)
			var tail: Vector2 = s.pos - s.vel * 0.032
			g.draw_line(tail, s.pos, Color(s.color, alpha * 0.85), float(s.size), true)
			g.draw_circle(s.pos, float(s.size) * 0.6, Color(1.0, 0.96, 0.84, alpha * 0.75))

	if flash_alpha > 0.005:
		g.draw_rect(field.grow(24.0), Color(flash_color, flash_alpha))

	for sc: Dictionary in showcase_cards:
		if sc.is_empty(): continue
		var life := float(sc.life)
		var dur := float(sc.duration)
		var prog := 1.0 - life / dur
		var alpha := clampf(prog / 0.14, 0.0, 1.0) * (1.0 - clampf((prog - 0.78) / 0.22, 0.0, 1.0))
		var p: Vector2 = sc.pos
		var pulse := 1.0 + 0.08 * sin(g.clock * 7.0)
		var r := 46.0 * pulse
		var col: Color = Color(0.95, 0.78, 0.34, alpha * 0.9) if int(sc.team) == 0 else Color(0.42, 0.72, 0.98, alpha * 0.9)
		g.tf(p, 0.0, Vector2(1.0, 0.48))
		g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, col, 3.0, true)
		g.draw_arc(Vector2.ZERO, r * 0.74, g.clock * 1.4, g.clock * 1.4 + PI * 1.35, 24, Color(1.0, 0.96, 0.80, alpha * 0.75), 2.0, true)
		g.tf()

## Drawn in clean screen space AFTER masking overflow outside FIELD_FRAME: vignette, letterbox, Cut-In banner.
func paint_screen_overlay(g, field: Rect2) -> void:
	if theater_mode:
		var matte := Color(0.08, 0.06, 0.04, 0.96)
		g.draw_rect(Rect2(0.0, 0.0, L.VIEWPORT_SIZE.x, field.position.y + 4.0), matte)
		g.draw_rect(Rect2(0.0, field.end.y - 4.0, L.VIEWPORT_SIZE.x, L.VIEWPORT_SIZE.y - field.end.y + 4.0), matte)
		g.draw_line(Vector2(field.position.x, field.position.y + 4.0), Vector2(field.end.x, field.position.y + 4.0), Color(0.84, 0.69, 0.42, 0.85), 1.8, true)
		g.draw_line(Vector2(field.position.x, field.end.y - 4.0), Vector2(field.end.x, field.end.y - 4.0), Color(0.84, 0.69, 0.42, 0.85), 1.8, true)
	var extra_v := maxf(letterbox * 0.45, DayCycle.darkness(g.model) * 0.35)
	if g.vignette != null and extra_v > 0.02:
		g.draw_texture_rect(g.vignette, field.grow(-4.0), false, Color(0.65, 0.55, 0.42, extra_v))
	if not theater_mode and letterbox > 0.005:
		var bar_h := 44.0 * letterbox
		var ink_bar := Color(0.08, 0.06, 0.04, 0.92 * minf(1.0, letterbox * 1.15))
		var gold_rim := Color(0.84, 0.69, 0.42, 0.75 * letterbox)
		g.draw_rect(Rect2(field.position.x + 2, field.position.y + 2, field.size.x - 4, bar_h), ink_bar)
		g.draw_rect(Rect2(field.position.x + 2, field.end.y - 2 - bar_h, field.size.x - 4, bar_h), ink_bar)
		g.draw_line(Vector2(field.position.x + 4, field.position.y + 2 + bar_h), Vector2(field.end.x - 4, field.position.y + 2 + bar_h), gold_rim, 1.5, true)
		g.draw_line(Vector2(field.position.x + 4, field.end.y - 2 - bar_h), Vector2(field.end.x - 4, field.end.y - 2 - bar_h), gold_rim, 1.5, true)

	if not cutin.is_empty():
		paint_cutin(g, field)

	paint_showcase_overlays(g, field)

	if theater_hint_left > 0.0:
		var ha := minf(1.0, theater_hint_left * 1.5)
		g.draw_string(g.font, Vector2(field.position.x, field.end.y + 38.0), "劇院無介面模式 · 再按 F9 恢復操作面板", HORIZONTAL_ALIGNMENT_CENTER, field.size.x, 16, Color(0.96, 0.89, 0.72, ha))

func paint_cutin(g, field: Rect2) -> void:
	var t: float = 1.0 - float(cutin.life) / float(cutin.duration)
	var enter := clampf(t / 0.16, 0.0, 1.0)
	var exit_fade := 1.0 - clampf((t - 0.74) / 0.26, 0.0, 1.0)
	var alpha := exit_fade
	var ease_x := 1.0 - pow(1.0 - enter, 3.0)
	var left_side: bool = (cutin.team == 0) != g.mirror_view
	var team_col: Color = g.RED if cutin.team == 0 else g.BLUE
	var lord: String = cutin.lord
	var lord_data: Dictionary = B.LORDS.get(lord, {})
	var band_h := 72.0
	var band_w := 430.0
	var base_y := field.position.y + 62.0
	var slide := (1.0 - ease_x) * (band_w + 40.0)
	var x := (field.position.x + 10.0 - slide) if left_side else (field.end.x - 10.0 - band_w + slide)
	var r := Rect2(x, base_y, band_w, band_h)

	var slant := 24.0 if left_side else -24.0
	var poly := PackedVector2Array([
		Vector2(r.position.x, r.position.y),
		Vector2(r.end.x, r.position.y),
		Vector2(r.end.x - slant, r.end.y),
		Vector2(r.position.x - slant, r.end.y),
	])
	g.draw_colored_polygon(poly, Color(0.14, 0.10, 0.07, 0.86 * alpha))
	var rim := poly.duplicate()
	rim.append(poly[0])
	g.draw_polyline(rim, Color(0.86, 0.71, 0.42, 0.92 * alpha), 2.0, true)

	var portrait_rect := Rect2(r.position.x + (14.0 if left_side else band_w - 94.0), r.position.y - 16.0, 76.0, 92.0)
	g.draw_fitted_facing(g.lord_art(lord, cutin.team), portrait_rect, 1.0 if left_side else -1.0, Color(1, 1, 1, alpha))

	var tx := r.position.x + (104.0 if left_side else 22.0)
	var tw := band_w - 126.0
	var align := HORIZONTAL_ALIGNMENT_LEFT if left_side else HORIZONTAL_ALIGNMENT_RIGHT
	g.draw_string(g.font, Vector2(tx, r.position.y + 27.0), "%s發動領主大招 · %s" % ["★ 玩家（紅方）" if cutin.team == 0 else "◆ 敵軍（藍方）", B.lord_name(lord)], align, tw, 16, Color(team_col.lightened(0.45), alpha))
	g.draw_string(g.font, Vector2(tx, r.position.y + 57.0), "「%s」" % lord_data.get("skill", "領主技"), align, tw, 26, Color(0.99, 0.91, 0.70, alpha))

func paint_showcase_overlays(g, field: Rect2) -> void:
	for sc: Dictionary in showcase_cards:
		if sc.is_empty(): continue
		var t := 1.0 - float(sc.life) / float(sc.duration)
		var enter := clampf(t / 0.14, 0.0, 1.0)
		var fade := 1.0 - clampf((t - 0.84) / 0.16, 0.0, 1.0)
		var alpha := enter * fade
		var slide := (1.0 - pow(1.0 - enter, 3.0))
		var left_side := int(sc.team) == 0
		var box_w := 560.0
		var paragraph := TextParagraph.new()
		paragraph.width = box_w - 106.0
		paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND
		var desc_size := 17
		paragraph.add_string(String(sc.desc), g.font, desc_size)
		while paragraph.get_size().y > 215.0 and desc_size > 11:
			desc_size -= 1
			paragraph.clear()
			paragraph.add_string(String(sc.desc), g.font, desc_size)
		var box_h := clampf(68.0 + paragraph.get_size().y + 14.0, 165.0, 305.0)
		var y := field.position.y + 16.0
		var hidden_x := field.position.x - box_w - 20.0 if left_side else field.end.x + 20.0
		var shown_x := field.position.x + 16.0 if left_side else field.end.x - box_w - 16.0
		var x := lerpf(hidden_x, shown_x, slide)
		var rect := Rect2(x, y, box_w, box_h)
		var accent: Color = Color("c94b3b") if left_side else Color("4a7cc4")
		g.draw_rect(rect, Color(0.11, 0.08, 0.05, 0.90 * alpha))
		g.draw_rect(rect, Color(0.86, 0.71, 0.42, 0.90 * alpha), false, 2.0)
		g.draw_rect(Rect2(rect.position, Vector2(6.0, rect.size.y)), Color(accent, alpha))
		var icon_rect := Rect2(rect.position + Vector2(14.0, 10.0), Vector2(66.0, 68.0))
		g.draw_rect(icon_rect.grow(2.0), Color(0.92, 0.85, 0.70, 0.16 * alpha))
		var art_id: String = g.card_art_kinds(sc.kind)[0]
		g.draw_fitted(g.art(art_id, int(sc.team)), icon_rect, Color(1, 1, 1, alpha), true)
		var side_txt := B.lord_name(String(g.model.lords[int(sc.team)].lord))
		g.draw_string(g.font, rect.position + Vector2(92.0, 25.0), "%s｜%s" % [side_txt, String(sc.name)], HORIZONTAL_ALIGNMENT_LEFT, box_w - 140.0, 20, Color(0.99, 0.91, 0.70, alpha))
		var coin_pos := rect.position + Vector2(rect.size.x - 30.0, 22.0)
		g.draw_circle(coin_pos, 13.0, Color(0.82, 0.62, 0.20, 0.95 * alpha))
		g.draw_arc(coin_pos, 13.0, 0.0, TAU, 20, Color(1.0, 0.93, 0.68, alpha), 1.5, true)
		g.draw_string(g.font, coin_pos + Vector2(-14.0, 6.0), str(int(sc.cost)), HORIZONTAL_ALIGNMENT_CENTER, 28.0, 16, Color(0.14, 0.09, 0.04, alpha))
		g.draw_string(g.font, rect.position + Vector2(92.0, 47.0), "[%s]" % String(sc.role), HORIZONTAL_ALIGNMENT_LEFT, box_w - 106.0, 14, Color(accent.lightened(0.45), alpha))
		paragraph.draw(g.get_canvas_item(), rect.position + Vector2(92, 60), Color(0.95, 0.91, 0.82, alpha))

	for side: int in range(2):
		var list: Array = mini_hints[side]
		var count: int = list.size()
		for i: int in range(count):
			var mh: Dictionary = list[i]
			var t := 1.0 - float(mh.life) / float(mh.duration)
			var alpha := clampf(t / 0.14, 0.0, 1.0) * (1.0 - clampf((t - 0.78) / 0.22, 0.0, 1.0))
			var left_side := side == 0
			var pw := 230.0
			var ph := 28.0
			var slide := 1.0 - pow(1.0 - clampf(t / 0.16, 0.0, 1.0), 3.0)
			var shown_x := field.position.x + 14.0 if left_side else field.end.x - pw - 14.0
			var hidden_x := field.position.x - pw - 10.0 if left_side else field.end.x + 10.0
			var x := lerpf(hidden_x, shown_x, slide)
			var y := field.end.y - 38.0 - float(count - 1 - i) * 32.0
			var rect := Rect2(x, y, pw, ph)
			var accent: Color = Color("c94b3b") if left_side else Color("4a7cc4")
			g.draw_rect(rect, Color(0.11, 0.08, 0.05, 0.84 * alpha))
			g.draw_rect(rect, Color(0.84, 0.69, 0.42, 0.78 * alpha), false, 1.4)
			g.draw_rect(Rect2(rect.position, Vector2(4.0, ph)), Color(accent, alpha))
			var icon_rect := Rect2(rect.position + Vector2(8.0, 3.0), Vector2(22.0, 22.0))
			var art_id: String = g.card_art_kinds(mh.kind)[0]
			g.draw_fitted(g.art(art_id, side), icon_rect, Color(1, 1, 1, alpha), true)
			g.draw_string(g.font, rect.position + Vector2(36.0, 19.0), "登場：%s" % String(mh.name), HORIZONTAL_ALIGNMENT_LEFT, pw - 70.0, 15, Color(0.98, 0.92, 0.78, alpha))
			var cpos := rect.position + Vector2(pw - 17.0, ph * 0.5)
			g.draw_circle(cpos, 9.5, Color(0.82, 0.62, 0.20, 0.92 * alpha))
			g.draw_string(g.font, cpos + Vector2(-10.0, 5.0), str(int(mh.cost)), HORIZONTAL_ALIGNMENT_CENTER, 20.0, 12, Color(0.14, 0.09, 0.04, alpha))

	if not showcase_chapter.is_empty():
		var t := 1.0 - float(showcase_chapter.life) / float(showcase_chapter.duration)
		var alpha := clampf(t / 0.18, 0.0, 1.0) * (1.0 - clampf((t - 0.76) / 0.24, 0.0, 1.0))
		var cw := 680.0
		var ch := 84.0
		var cx := field.get_center().x - cw * 0.5
		var cy := field.position.y + 114.0
		var rect := Rect2(cx, cy, cw, ch)
		g.draw_rect(rect, Color(0.09, 0.07, 0.05, 0.86 * alpha))
		g.draw_rect(rect.grow(-4.0), Color(0.86, 0.70, 0.40, 0.85 * alpha), false, 1.8)
		g.draw_string(g.font, rect.position + Vector2(0.0, 40.0), String(showcase_chapter.title), HORIZONTAL_ALIGNMENT_CENTER, cw, 28, Color(0.99, 0.92, 0.72, alpha))
		if not String(showcase_chapter.sub).is_empty():
			g.draw_string(g.font, rect.position + Vector2(0.0, 66.0), String(showcase_chapter.sub), HORIZONTAL_ALIGNMENT_CENTER, cw, 16, Color(0.88, 0.81, 0.68, alpha))

	if not showcase_sub.is_empty():
		var t := 1.0 - float(showcase_sub.life) / float(showcase_sub.duration)
		var alpha := clampf(t / 0.12, 0.0, 1.0) * (1.0 - clampf((t - 0.84) / 0.16, 0.0, 1.0))
		var sw := 880.0
		var sh := 36.0
		var rect := Rect2(field.get_center().x - sw * 0.5, field.end.y - sh - 12.0, sw, sh)
		g.draw_rect(rect, Color(0.08, 0.06, 0.04, 0.84 * alpha))
		var rim := Color(0.84, 0.69, 0.42, 0.75 * alpha)
		g.draw_rect(rect, rim, false, 1.4)
		var s_team := int(showcase_sub.team)
		if s_team >= 0:
			var dot_col: Color = g.RED if s_team == 0 else g.BLUE
			g.draw_circle(rect.position + Vector2(22.0, sh * 0.5), 5.5, Color(dot_col.lightened(0.2), alpha))
		g.draw_string(g.font, rect.position + Vector2(0.0, 24.0), String(showcase_sub.text), HORIZONTAL_ALIGNMENT_CENTER, sw, 18, Color(0.98, 0.93, 0.82, alpha))
