extends RefCounted
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

static func contains(origin: Vector2, target: Vector2, team: int) -> bool:
	var ahead := (target.x-origin.x)*(1.0 if team == 0 else -1.0)
	return ahead >= 0 and ahead <= B.LORDS.adventure.skill_cells*L.CELL_SIZE.x and absf(target.y-origin.y) <= L.CELL_SIZE.y*1.5

static func cast(m, team: int) -> void:
	var lord: Dictionary = m.lords[team]
	for actor: Dictionary in m.units+m.buildings+m.lords:
		if actor.team == team or actor.hp <= 0: continue
		if actor.get("spawn_delay",0.0) > 0: continue
		if contains(lord.pos,actor.pos,team): m.damage(actor,B.LORDS.adventure.skill_damage,team,"hero_slash")
	lord.cd = B.LORD_INTERVAL
	var dur: float = float(B.LORDS.adventure.get("spin_duration",0.6))
	var rad: float = float(B.LORDS.adventure.get("spin_radius",290.0))
	m.hero_spins.append({"team":team,"delay":0.18,"duration":dur,"elapsed":0.0,"radius":rad,"damage":float(B.LORDS.adventure.get("spin_damage",600.0)),"hit_ids":{},"started":false})
	m.event("hero_slash",lord.pos,team,{"length":B.LORDS.adventure.skill_cells*L.CELL_SIZE.x,"width":L.CELL_SIZE.y*3.0})

static func step_spins(m, dt: float) -> void:
	var i: int = m.hero_spins.size()-1
	while i >= 0:
		var s: Dictionary = m.hero_spins[i]
		var team: int = int(s.team)
		if m.frozen(team):
			i -= 1
			continue
		if float(s.delay) > 0.0:
			s.delay = float(s.delay)-dt
			i -= 1
			continue
		var lord: Dictionary = m.lords[team]
		if lord.hp <= 0:
			m.hero_spins.remove_at(i)
			i -= 1
			continue
		if not bool(s.started):
			s.started = true
			m.event("hero_spin",lord.pos,team,{"radius":float(s.radius),"duration":float(s.duration)})
		var dur: float = maxf(0.01,float(s.duration))
		var prev_p: float = clampf(float(s.elapsed)/dur,0.0,1.0)
		s.elapsed = float(s.elapsed)+dt
		var cur_p: float = clampf(float(s.elapsed)/dur,0.0,1.0)
		var base_ang: float = 0.0 if team == 0 else PI
		var dir: float = 1.0 if team == 0 else -1.0
		var hit_ids: Dictionary = s.hit_ids
		for actor: Dictionary in m.units+m.buildings+m.lords:
			if actor.team == team or actor.hp <= 0: continue
			if actor.get("spawn_delay",0.0) > 0: continue
			var key: int = int(actor.get("id",-10-int(actor.team)))
			if hit_ids.has(key): continue
			if B.point_edge_distance(lord.pos,actor) > float(s.radius): continue
			var rel: Vector2 = actor.pos-lord.pos
			var swept := cur_p >= 1.0 or rel.length_squared() < 16.0
			if not swept:
				var ang := fposmod((atan2(rel.y,rel.x)-base_ang)*dir,TAU)
				var frac := ang/TAU
				swept = frac >= prev_p and frac <= cur_p
			if swept:
				hit_ids[key] = true
				m.damage(actor,float(s.damage),team,"hero_slash")
		if float(s.elapsed) >= dur:
			m.hero_spins.remove_at(i)
		i -= 1
