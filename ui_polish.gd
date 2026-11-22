extends RefCounted
## Presentation-only UI transitions, card micro-animations, and battlefield actor motion cues.
## Never modifies battle rules, actor HP/positions, or simulation RNG.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

const VEIL_SCREEN_TIME := 0.32
const VEIL_SUB_TIME := 0.18
const ENTER_FADE_TIME := 0.22

var veil_left := 0.0
var veil_duration := VEIL_SCREEN_TIME
var veil_peak := 0.86
var last_screen := ""
var last_sub_key := ""
var screen_enter_t := 1.0
var pause_fade := 0.0
var last_dt := 0.016

var hovers := {}
var slot_lift := {}
var slot_last_kind := {}
var slot_entry := {}
var slot_was_blocked := {}
var slot_ready_flash := {}

var skill_was_ready := false
var skill_was_ready_init := false
var skill_ready_flash := 0.0
var purse_flash := 0.0

var hover_strip_alpha := 0.0
var hover_strip_kind := ""

var prev_model_id := 0
var unit_spawn_age := {}
var unit_last_x := {}
var unit_moving := {}
var bldg_spawn_age := {}
var bldg_last_hp := {}
var bldg_hit_flash := {}
var lord_last_hp := {}
var lord_hit_flash := {}
var lord_last_pos := {}
var lord_moving := {}
var gate_last_hp := {}
var gate_hit_flash := {}

static func ease_out(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - c, 3.0)

static func smooth01(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)

func reset_battle() -> void:
	slot_lift.clear()
	slot_last_kind.clear()
	slot_entry.clear()
	slot_was_blocked.clear()
	slot_ready_flash.clear()
	skill_was_ready = false
	skill_was_ready_init = false
	skill_ready_flash = 0.0
	purse_flash = 0.0
	hover_strip_alpha = 0.0
	hover_strip_kind = ""
	pause_fade = 0.0
	unit_spawn_age.clear()
	unit_last_x.clear()
	unit_moving.clear()
	bldg_spawn_age.clear()
	bldg_last_hp.clear()
	bldg_hit_flash.clear()
	lord_last_hp.clear()
	lord_hit_flash.clear()
	lord_last_pos.clear()
	lord_moving.clear()
	gate_last_hp.clear()
	gate_hit_flash.clear()

func current_sub_key(g) -> String:
	if g.screen == "rogue" and g.rogue != null:
		var ph: String = str(g.rogue.run.get("phase", g.rogue.phase) if not g.rogue.run.is_empty() else g.rogue.phase)
		return "rogue:" + ph
	return g.screen

func step_transitions(g, dt: float) -> void:
	last_dt = clampf(dt, 0.0, 0.1)
	var here: String = "battle" if g.in_battle() else g.screen
	var sub_key := current_sub_key(g)
	if here != last_screen:
		if not last_screen.is_empty():
			veil_duration = VEIL_SCREEN_TIME
			veil_left = VEIL_SCREEN_TIME
			veil_peak = 0.86
			screen_enter_t = 0.0
		last_screen = here
		last_sub_key = sub_key
	elif sub_key != last_sub_key:
		if not last_sub_key.is_empty():
			veil_duration = VEIL_SUB_TIME
			veil_left = VEIL_SUB_TIME
			veil_peak = 0.34
			screen_enter_t = 0.28
		last_sub_key = sub_key

	veil_left = maxf(0.0, veil_left - dt)
	screen_enter_t = move_toward(screen_enter_t, 1.0, dt / ENTER_FADE_TIME)
	if g.veil != null:
		var k := clampf(veil_left / maxf(0.01, veil_duration), 0.0, 1.0)
		g.veil.color.a = smooth01(k) * veil_peak

	apply_ui_fade(g)

func apply_ui_fade(g) -> void:
	var a := 1.0
	if g.is_processing() and DisplayServer.get_name() != "headless":
		a = ease_out(screen_enter_t)
	for c: Control in g.ui:
		if not is_instance_valid(c):
			continue
		if not c.has_meta("polish_base_a"):
			if c.modulate.a < 0.05:
				c.set_meta("polish_skip_fade", true)
				continue
			c.set_meta("polish_base_a", c.modulate.a)
		if c.get_meta("polish_skip_fade", false):
			continue
		c.modulate.a = float(c.get_meta("polish_base_a", 1.0)) * a
	for c: Control in g.ui:
		if is_instance_valid(c) and c is Button: restyle_button(c)

# Menu pages rise a little into place as they open (2026-11-21); controls are children of the game
# node, so they ride along with the drawing. Battle stays put.
func page_offset(g) -> float:
	if not g.is_processing() or DisplayServer.get_name() == "headless": return 0.0
	return (1.0 - ease_out(screen_enter_t)) * 18.0

# Every visible button becomes a slanted plate with a pressed lower edge and a drop shadow, pops a
# little under the mouse and dips when pressed. Invisible overlay buttons are left alone.
func restyle_button(b: Button) -> void:
	if b.has_meta("ui_styled"):
		return
	b.set_meta("ui_styled", true)
	# An invisible hit area (clear when idle, only a soft glow on hover) over a card or a banner stays square
	# and still: slanting its glow left crooked boxes over the cards (使用者 2026-11-22：好多虛框都是歪斜的).
	if b.has_theme_stylebox_override("normal"):
		var idle: StyleBox = b.get_theme_stylebox("normal")
		if not (idle is StyleBoxFlat) or (idle as StyleBoxFlat).bg_color.a < 0.05:
			return
	var visible_box := false
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		if not b.has_theme_stylebox_override(state):
			continue
		var sb: StyleBox = b.get_theme_stylebox(state)
		if not (sb is StyleBoxFlat) or (sb as StyleBoxFlat).bg_color.a < 0.05:
			continue
		var s: StyleBoxFlat = sb.duplicate()
		visible_box = true
		s.skew = Vector2(0.12, 0.0)
		s.anti_aliasing = true
		s.set_corner_radius_all(3)
		s.shadow_color = Color(0.12, 0.08, 0.04, 0.0 if state == "disabled" else 0.26)
		s.shadow_size = 1
		s.shadow_offset = Vector2(2, 2) if state == "pressed" else Vector2(3, 5)
		var edge: Color = s.border_color
		if state == "pressed":
			s.border_width_bottom = 2
			s.content_margin_top = 4
		elif state != "disabled":
			s.border_width_bottom = maxi(s.border_width_bottom, 4)
			s.border_color = edge
		b.add_theme_stylebox_override(state, s)
	if not visible_box or not b.is_inside_tree():
		return
	b.pivot_offset = b.size * 0.5
	b.mouse_entered.connect(func(): pop(b, 1.05))
	b.mouse_exited.connect(func(): pop(b, 1.0))
	b.button_down.connect(func(): pop(b, 0.95))
	b.button_up.connect(func(): pop(b, 1.05 if b.is_hovered() else 1.0))

static func pop(b: Button, to: float) -> void:
	if not is_instance_valid(b) or (b.disabled and to > 1.0):
		return
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(to, to), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func get_pause_fade(g) -> float:
	if g.model == null or g.model.ended:
		return 0.0
	if not g.is_processing() or DisplayServer.get_name() == "headless":
		return 1.0 if g.model.paused else 0.0
	return pause_fade

func hover_val(key: String, hovered: bool, processing: bool = true) -> float:
	if not processing or DisplayServer.get_name() == "headless":
		return 1.0 if hovered else 0.0
	var cur := float(hovers.get(key, 0.0))
	var target := 1.0 if hovered else 0.0
	cur = move_toward(cur, target, last_dt * (9.5 if hovered else 6.5))
	if cur <= 0.001 and not hovered:
		hovers.erase(key)
		return 0.0
	hovers[key] = cur
	return cur

func step_menu_hovers(dt: float) -> void:
	for k: String in hovers.keys():
		# Unused keys fade gently only when queried; prune stale zeroed keys
		if float(hovers[k]) <= 0.001:
			hovers.erase(k)
	var _unused := dt

func observe_battle(g, real_dt: float, sim_dt: float) -> void:
	if g.model == null:
		return
	var m = g.model
	var mid: int = m.get_instance_id()
	if mid != prev_model_id:
		reset_battle()
		prev_model_id = mid

	var target_pause := 1.0 if (m.paused and not m.ended) else 0.0
	pause_fade = move_toward(pause_fade, target_pause, real_dt / 0.16)
	purse_flash = maxf(0.0, purse_flash - real_dt)
	skill_ready_flash = maxf(0.0, skill_ready_flash - real_dt)

	var focus_slot: int = g.selected if g.selected >= 0 else g.hover_slot
	if focus_slot >= 0 and not g.spectating and not (g.adventure != null and g.adventure.is_opening()):
		var fk: String = m.kind_at(g.me, focus_slot)
		if B.CARDS.has(fk):
			hover_strip_kind = fk
			hover_strip_alpha = move_toward(hover_strip_alpha, 1.0, real_dt / 0.12)
		else:
			hover_strip_alpha = move_toward(hover_strip_alpha, 0.0, real_dt / 0.14)
	else:
		hover_strip_alpha = move_toward(hover_strip_alpha, 0.0, real_dt / 0.14)
		if hover_strip_alpha <= 0.001:
			hover_strip_kind = ""

	var hand_slots := [0, 1, 2, 3, g.Battle.FARM_SLOT]
	for slot: int in hand_slots:
		var target_lift := -16.0 if g.selected == slot else (-8.0 if g.hover_slot == slot else 0.0)
		var cur_lift := float(slot_lift.get(slot, 0.0))
		slot_lift[slot] = lerpf(cur_lift, target_lift, 1.0 - exp(-real_dt * 18.0))
		var kind: String = m.kind_at(g.me, slot)
		if slot != g.Battle.FARM_SLOT:
			if slot_last_kind.has(slot) and slot_last_kind[slot] != kind and not m.paused:
				slot_entry[slot] = 0.26
				slot_was_blocked.erase(slot)
			slot_last_kind[slot] = kind
		slot_entry[slot] = maxf(0.0, float(slot_entry.get(slot, 0.0)) - real_dt)
		slot_ready_flash[slot] = maxf(0.0, float(slot_ready_flash.get(slot, 0.0)) - real_dt)

		if not g.spectating and not m.paused and not m.ended and g.intro_left <= 0.0 and B.CARDS.has(kind):
			var cost_val := float(B.CARDS[kind].cost)
			var blocked: bool = m.ink[g.me] < cost_val or m.slot_cd(g.me, slot) > 0.0
			if slot_was_blocked.has(slot):
				if bool(slot_was_blocked[slot]) and not blocked:
					slot_ready_flash[slot] = 0.45
					if g.sound != null and m.elapsed > 0.3:
						g.sound.cue("card_ready")
			slot_was_blocked[slot] = blocked

	if not g.spectating and not m.paused and not m.ended and g.intro_left <= 0.0:
		var sk_ready: bool = m.skill_error(g.me).is_empty()
		if skill_was_ready_init and not skill_was_ready and sk_ready:
			skill_ready_flash = 0.75
			if g.sound != null and m.elapsed > 0.3:
				g.sound.cue("skill_ready")
		skill_was_ready = sk_ready
		skill_was_ready_init = true

	var eff_dt: float = g.cinematic.fx_dt(sim_dt)
	var alive_units := {}
	for u: Dictionary in m.units:
		if u.hp <= 0:
			continue
		var uid: int = int(u.id)
		alive_units[uid] = true
		if not unit_spawn_age.has(uid):
			unit_spawn_age[uid] = 1.0 if m.elapsed < 0.05 else 0.0
		elif eff_dt > 0.0:
			unit_spawn_age[uid] = minf(1.0, float(unit_spawn_age[uid]) + eff_dt / 0.22)
		var prev_x := float(unit_last_x.get(uid, float(u.pos.x)))
		if eff_dt > 0.0:
			unit_moving[uid] = absf(float(u.pos.x) - prev_x) > 0.05
			unit_last_x[uid] = float(u.pos.x)
	for uid in unit_spawn_age.keys():
		if not alive_units.has(uid):
			unit_spawn_age.erase(uid)
			unit_last_x.erase(uid)
			unit_moving.erase(uid)

	var alive_bldgs := {}
	for b: Dictionary in m.buildings:
		if b.hp <= 0:
			continue
		var bid: int = int(b.id)
		alive_bldgs[bid] = true
		if not bldg_spawn_age.has(bid):
			bldg_spawn_age[bid] = 1.0 if m.elapsed < 0.05 else 0.0
		elif eff_dt > 0.0:
			bldg_spawn_age[bid] = minf(1.0, float(bldg_spawn_age[bid]) + eff_dt / 0.26)
		var bhp := float(b.hp)
		if bldg_last_hp.has(bid) and bhp < float(bldg_last_hp[bid]) - 0.1:
			bldg_hit_flash[bid] = 0.16
		bldg_last_hp[bid] = bhp
		if bldg_hit_flash.has(bid) and eff_dt > 0.0:
			bldg_hit_flash[bid] = float(bldg_hit_flash[bid]) - eff_dt
			if bldg_hit_flash[bid] <= 0.0:
				bldg_hit_flash.erase(bid)
	for bid in bldg_spawn_age.keys():
		if not alive_bldgs.has(bid):
			bldg_spawn_age.erase(bid)
			bldg_last_hp.erase(bid)
			bldg_hit_flash.erase(bid)

	for lord: Dictionary in m.lords:
		var t: int = int(lord.team)
		var lhp := float(lord.hp)
		if lord_last_hp.has(t) and lhp > 0.0 and lhp < float(lord_last_hp[t]) - 0.1:
			lord_hit_flash[t] = 0.15
		lord_last_hp[t] = lhp
		if eff_dt > 0.0:
			lord_hit_flash[t] = maxf(0.0, float(lord_hit_flash.get(t, 0.0)) - eff_dt)
			var prev_lp: Vector2 = lord_last_pos.get(t, lord.pos)
			lord_moving[t] = prev_lp.distance_to(lord.pos) > 0.08
			lord_last_pos[t] = lord.pos

	for team: int in range(2):
		for lane: int in m.active_lanes:
			var gkey := "%d:%d" % [team, lane]
			var ghp := float(m.gates[team][lane])
			if gate_last_hp.has(gkey) and ghp > 0.0 and float(gate_last_hp[gkey]) - ghp > 2.0:
				gate_hit_flash[gkey] = 0.18
				if g.fx_enabled and g.effects.size() < 90:
					var has_chip: bool = g.effects.any(func(ef: Dictionary) -> bool: return ef.kind == "wall_chip" and ef.get("gkey", "") == gkey)
					if not has_chip:
						g.effects.append({
							"kind": "wall_chip",
							"gkey": gkey,
							"pos": Vector2(L.gate_icon_x(team), L.cell_center(Vector2i(0, lane)).y),
							"team": team,
							"life": 0.32,
							"duration": 0.32,
						})
			gate_last_hp[gkey] = ghp
			if gate_hit_flash.has(gkey) and eff_dt > 0.0:
				gate_hit_flash[gkey] = float(gate_hit_flash[gkey]) - eff_dt
				if gate_hit_flash[gkey] <= 0.0:
					gate_hit_flash.erase(gkey)

func get_slot_lift(g, slot: int) -> float:
	if not g.is_processing() or DisplayServer.get_name() == "headless":
		return -16.0 if g.selected == slot else (-8.0 if g.hover_slot == slot else 0.0)
	return float(slot_lift.get(slot, 0.0))

func unit_spawn_progress(uid: int) -> float:
	return clampf(float(unit_spawn_age.get(uid, 1.0)), 0.0, 1.0)

func bldg_spawn_progress(bid: int) -> float:
	return clampf(float(bldg_spawn_age.get(bid, 1.0)), 0.0, 1.0)

func bldg_flash(bid: int) -> float:
	return clampf(float(bldg_hit_flash.get(bid, 0.0)) / 0.16, 0.0, 1.0)

func lord_flash(team: int) -> float:
	return clampf(float(lord_hit_flash.get(team, 0.0)) / 0.15, 0.0, 1.0)

func gate_flash(team: int, lane: int) -> float:
	return clampf(float(gate_hit_flash.get("%d:%d" % [team, lane], 0.0)) / 0.18, 0.0, 1.0)

static func draw_card_hover_glow(g, rect: Rect2, strength: float, accent: Color = Color("d8b25c")) -> void:
	if strength <= 0.01:
		return
	for k: int in range(4): # a soft warm halo behind the lifted card
		g.draw_rect(rect.grow(3.0 + k * 3.0), Color(1.0, 0.86, 0.45, 0.12 * strength * (1.0 - k / 4.0)))
	g.draw_rect(Rect2(rect.position + Vector2(3, 8 + 4 * strength), rect.size), Color(0.12, 0.08, 0.04, 0.25 * strength))
	g.draw_rect(rect.grow(2.5), Color(accent, 0.72 * strength), false, 2.5)

static func draw_ready_sheen(g, rect: Rect2, left: float) -> void:
	if left <= 0.0:
		return
	var p := 1.0 - clampf(left / 0.45, 0.0, 1.0)
	var band_x := lerpf(rect.position.x - 24.0, rect.end.x + 24.0, p)
	var x0 := clampf(band_x - 10.0, rect.position.x + 3.0, rect.end.x - 3.0)
	var x1 := clampf(band_x + 12.0, rect.position.x + 3.0, rect.end.x - 3.0)
	var alpha := sin(p * PI) * 0.45
	if x1 > x0 + 1.0:
		g.draw_colored_polygon(PackedVector2Array([
			Vector2(x0, rect.position.y + 4.0),
			Vector2(x1, rect.position.y + 4.0),
			Vector2(clampf(x1 - 16.0, rect.position.x + 3.0, rect.end.x - 3.0), rect.end.y - 4.0),
			Vector2(clampf(x0 - 16.0, rect.position.x + 3.0, rect.end.x - 3.0), rect.end.y - 4.0),
		]), Color(1.0, 0.95, 0.72, alpha))
	g.draw_rect(rect.grow(2.0 + p * 4.0), Color(0.95, 0.78, 0.30, sin(p * PI) * 0.65), false, 2.5)
