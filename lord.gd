extends RefCounted
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const AI = preload("res://lord_ai.gd")
static func create(team: int, lord_kind: String = "lion") -> Dictionary:
	var data: Dictionary = B.lord_data(lord_kind)
	return {"kind":"lord","lord":lord_kind,"team":team,"max_hp":data.hp,"damage":data.damage,"speed":data.speed,"range":B.lord_attack_range(lord_kind),"ranged":B.lord_is_ranged(lord_kind),"body_radius":B.kind_radius(lord_kind),"pos":home(team),"hp":data.hp,"respawn":0.0,"cd":0.0,"last_hit":-10.0,"think":0.0,"target":L.spawn_position(team,2),"changed":-10.0,"retreating":false,"flash":0.0}
# Patrol on the castle side of the visible gate, mirrored for both teams.
static func zone(team: int) -> Vector2:
	var gate := L.gate_icon_x(team)
	if team == 0: return Vector2(gate-B.LORD_ZONE_DEPTH,gate-B.LORD_ZONE_DEPTH*0.5)
	return Vector2(gate+B.LORD_ZONE_DEPTH*0.5,gate+B.LORD_ZONE_DEPTH)

static func home(team: int) -> Vector2:
	return Vector2(zone(team).y if team == 0 else zone(team).x,L.cell_center(Vector2i(0,2)).y)

static func step(m: RefCounted, lord: Dictionary, dt: float) -> void:
	if lord.hp <= 0:
		lord.respawn -= dt
		if lord.respawn <= 0:
			lord.hp = lord.max_hp
			lord.pos = home(lord.team)
			lord.target = lord.pos
			lord.retreating = false
		return
	lord.flash = maxf(0,lord.flash-dt)
	if m.elapsed-lord.last_hit >= B.LORD_REGEN_DELAY: lord.hp = minf(lord.max_hp,lord.hp+B.LORD_REGEN*dt)
	# Respond immediately without lane scores, low-health retreat or switch delay.
	lord.retreating = false
	lord.target = AI.target_pos(lord,m.foe_units[lord.team] if not m.foe_units[lord.team].is_empty() else m.units)
	# Pursuit never crosses the gate, including after a breach.
	var z := zone(lord.team)
	var min_x: float = z.x
	var max_x: float = z.y
	lord.target.x = clampf(lord.target.x,min_x,max_x)
	lord.pos = lord.pos.move_toward(lord.target,lord.speed*dt)
	lord.pos.x = clampf(lord.pos.x,min_x,max_x)
	lord.cd -= dt
	if lord.cd <= 0:
		var foe: Dictionary = m.lord_target(lord)
		if not foe.is_empty():
			if lord.has("shot"): m.boss_shot(lord,foe) # 肉鴿魔王的招牌彈 (roguelike_catalog.BOSS_SHOTS)
			elif B.lord_is_ranged(lord.lord): m.shoot_lord(lord,foe,lord.damage)
			else: m.damage(foe,lord.damage,lord.team,"lord")
			lord.cd = float(lord.shot.interval) if lord.has("shot") else B.lord_attack_interval(lord.lord)
