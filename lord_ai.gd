extends RefCounted
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const TIE := 0.5

# Signed depth prioritizes intruders beyond the gate, then the nearest equal-depth enemy.
static func select_target(lord: Dictionary, units: Array, radius: float = INF) -> Dictionary:
	var best: Dictionary = {}
	var best_depth := INF
	var best_distance := INF
	var forward := 1.0 if lord.team == 0 else -1.0
	var gate_x := L.gate_stop(lord.team)
	var lord_r := B.actor_radius(lord)
	var lord_pos: Vector2 = lord.pos
	for u: Dictionary in units:
		# Lords see through stealth (producer 2026-11-20): a hidden troop can still be hunted by a lord.
		if u.team == lord.team or u.hp <= 0 or u.get("spawn_delay",0.0) > 0: continue
		var depth: float = (u.pos.x-gate_x)*forward
		if not best.is_empty() and depth > best_depth+TIE: continue
		var ur: float = float(u.body_radius) if u.has("body_radius") else B.actor_radius(u)
		if radius < INF and absf(u.pos.x-lord_pos.x)-lord_r-ur > radius: continue
		var distance: float = maxf(0.0,lord_pos.distance_to(u.pos)-lord_r-ur)
		if distance > radius: continue
		if best.is_empty() or depth < best_depth-TIE or (absf(depth-best_depth) <= TIE and (distance < best_distance-TIE or (absf(distance-best_distance) <= TIE and u.get("serial",0) > best.get("serial",0)))):
			best = u
			best_depth = depth
			best_distance = distance
	return best

static func target_pos(lord: Dictionary, units: Array) -> Vector2:
	var enemy := select_target(lord,units)
	return lord.pos if enemy.is_empty() else enemy.pos

static func destination(lord: Dictionary, units: Array, _gates: Array) -> Dictionary:
	var enemy := select_target(lord,units)
	if enemy.is_empty(): return {"pos":lord.pos,"urgent":false}
	return {"pos":enemy.pos,"urgent":true}
