extends RefCounted
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

static func crystal_period(b: Dictionary) -> float:
	var d: Dictionary = B.CARDS.crystal
	var vitality := clampf((b.hp-1.0)/maxf(1.0,b.max_hp-1.0),0.0,1.0)
	return lerpf(d.max_period,d.period,vitality)

static func update_building(m, b: Dictionary, dt: float) -> bool:
	if b.kind == "crystal":
		var d: Dictionary = B.CARDS.crystal
		b.production += dt
		while b.production >= crystal_period(b):
			b.production -= crystal_period(b)
			m.gain_ink(b.team,d.income)
			b.hp = maxf(1.0,b.hp-b.max_hp*d.decay_fraction)
			m.event("ink",b.pos,b.team)
		return true
	if b.kind == "arcane_tower":
		var d: Dictionary = B.CARDS.arcane_tower
		b.cd -= dt
		if b.cd <= 0:
			var target: Dictionary = preload("res://grid_rules.gd").pick(m,b,m.foe_units[b.team]) # reach in cells; troops first
			if not target.is_empty():
				var impact: Vector2 = target.pos
				var dmg: float = float(b.get("area_damage",d.area_damage))
				for u: Dictionary in m.foe_units[b.team]:
					if u.hp > 0 and B.blast_hits(impact,String(d.get("blast","cross")),1 if b.team == 0 else -1,u): m.damage(u,dmg,b.team,b.kind)
				if target.has("cell"): m.damage(target,dmg,b.team,b.kind) # a building target takes the blast too
				b.cd = float(b.get("interval",d.interval))
				m.event("arcane_impact",impact,b.team,{"from":b.pos,"radius":d.radius})
		return true
	return false

static func repair(m, u: Dictionary, dt: float = 0.0) -> bool:
	if u.kind != "artificer": return false
	var d: Dictionary = B.CARDS.artificer
	var target: Dictionary = {}
	var distance: float = d.repair_range+1.0
	var missing := 0.0
	for ally: Dictionary in m.units:
		if ally.team == u.team and B.CARDS[ally.kind].get("construct",false) and ally.hp > 0 and ally.max_hp-ally.hp > missing and B.edge_distance(u,ally) <= d.repair_range:
			target = ally
			missing = ally.max_hp-ally.hp
	if not target.is_empty():
		u.pos.x = move_toward(u.pos.x,target.pos.x,minf(m.movement_speed(u),m.movement_speed(target))*dt)
	for b: Dictionary in m.buildings if target.is_empty() else []:
		if b.team != u.team or b.hp <= 0 or b.hp >= b.max_hp or B.CARDS[b.kind].has("trap"): continue
		var reach: float = B.edge_distance(u,b)
		if reach <= d.repair_range and reach < distance:
			target = b
			distance = reach
	if target.is_empty(): return false
	if u.cd <= 0:
		target.hp = minf(target.max_hp,target.hp+d.repair_amount)
		u.cd = d.repair_interval
		m.link(u.pos,target.pos,u.team,"repair")
		m.event("repair",target.pos,u.team)
	return true

static func update_traps(m) -> void:
	if not m.has_trap: return
	var moved := false
	for trap: Dictionary in m.buildings:
		var d: Dictionary = B.CARDS[trap.kind]
		if trap.hp <= 0 or not d.has("trap"): continue
		var affected: Array[Dictionary] = []
		var triggered := false
		for u: Dictionary in m.units:
			if u.team == trap.team or u.hp <= 0 or u.spawn_delay > 0 or B.CARDS[u.kind].get("flying",false): continue
			var distance: float = B.point_edge_distance(trap.pos,u)
			if distance <= d.trigger_radius and not u.get("phased",false): triggered = true
			if (B.blast_hits(trap.pos,String(d.blast),1 if trap.team == 0 else -1,u) if d.has("blast") else distance <= d.radius): affected.append(u)
		if not triggered: continue
		if d.trap == "summon":
			var seen: Array = trap.get("summon_triggered",[])
			var fresh := false
			for u: Dictionary in affected:
				if u.get("phased",false) or B.point_edge_distance(trap.pos,u) > d.trigger_radius: continue
				if not u.id in seen:
					seen.append(u.id)
					fresh = true
			if not fresh: continue
			trap.summon_triggered = seen
			for i: int in range(d.summon_count):
				var child: Dictionary = m.spawn_unit(trap.team,trap.cell.y,d.summon_kind,trap.pos)
				child.card = trap.kind
				child.dy = (i-(d.summon_count-1)*0.5)*12.0
				child.spawn_delay = 0.12*i
				m.event("summoned",child.pos+Vector2(0,child.dy),child.team)
			if d.has("summon_blast"): # 召喚法陣 2026-11-19: the summoning circle bursts as it opens
				for foe: Dictionary in m.units:
					if foe.hp > 0 and foe.team != trap.team and B.blast_hits(trap.pos,String(d.blast),1 if trap.team == 0 else -1,foe): m.damage(foe,float(d.summon_blast),trap.team,trap.kind)
			m.event("rune_summon",trap.pos,trap.team)
			moved = true
		elif d.trap == "teleport":
			# Sends the group back to its own start of this same lane (producer 2026-11-03).
			for u: Dictionary in affected:
				if u.get("phased",false): continue
				var old: Vector2 = u.pos
				u.pos = L.cell_center(Vector2i(0 if u.team == 0 else L.GRID_COLUMNS-1,u.lane))
				u.work_id = -1
				u.work_left = 0.0
				u.stun_left = d.get("stun_duration",10.0)
				u.slow_left = d.get("slow_duration",10.0)
				m.event("teleport",old,trap.team,{"to":u.pos})
			moved = true
		else:
			# Each enemy sets off a given blast trap only once, so a crowd standing on it does not
			# spend all charges in one instant; the blast still hits everyone in range.
			var fresh := false
			for u: Dictionary in affected:
				if not u.get("phased",false) and B.point_edge_distance(trap.pos,u) <= d.trigger_radius and not u.id in trap.get("blasted",[]): fresh = true
			if not fresh: continue
			var blasted: Array = trap.get("blasted",[])
			var exp_dmg: float = float(trap.get("explosion_damage",d.explosion_damage))
			for u: Dictionary in affected:
				m.damage(u,exp_dmg,trap.team,trap.kind)
				if not u.id in blasted: blasted.append(u.id)
			trap.blasted = blasted
			m.event("trap_blast",trap.pos,trap.team,{"radius":d.radius})
		trap.charges = trap.get("charges",d.get("charges",3))-1
		if trap.charges <= 0:
			trap.hp = 0
			m.refresh_territory()
	if moved: m.build_lookups()

static func resonance(m, u: Dictionary) -> float:
	var d: Dictionary = B.CARDS.get(u.kind,{})
	return minf(d.get("resonance_max",0.0),m.count_buildings(u.team,"crystal")*d.get("resonance",0.0))

static func blink(m, u: Dictionary) -> void:
	var step: float = B.CARDS.get(u.kind,{}).get("blink_step",0.0)
	if step <= 0 or u.hp <= 0: return
	var old: Vector2 = u.pos
	var direction := 1.0 if u.team == 0 else -1.0
	u.pos.x += direction*L.CELL_SIZE.x*step
	u.pos.x = minf(u.pos.x,L.gate_stop(1)) if u.team == 0 else maxf(u.pos.x,L.gate_stop(0))
	m.event("teleport",old,u.team,{"to":u.pos,"afterimage":u.kind})

static func reveal(m, u: Dictionary, permanent: bool = true) -> void:
	if u.get("phased",false): m.event("teleport",u.pos,u.team,{"to":u.pos})
	u.phased = false
	u.stealthed = false
	if permanent:
		u.revealed = true
		u.march_time = 0.0

static func area_hit(m, u: Dictionary, point: Vector2) -> void:
	var d: Dictionary = B.CARDS[u.kind]
	for target: Dictionary in m.units+m.buildings+m.lords:
		if target.team == u.team or target.hp <= 0 or not B.blast_hits(point,String(d.get("blast","cell")),1 if u.team == 0 else -1,target): continue
		m.damage(target,d.area_damage,u.team,u.kind,u)
		if target.has("spawn_delay") and target.hp > 0: target.stun_left = maxf(target.get("stun_left",0.0),d.stun_on_hit)
	for lane: int in m.active_lanes:
		if B.blast_hits_gate(point,String(d.get("blast","cell")),1 if u.team == 0 else -1,1-u.team,lane):
			m.hit_gate(1-u.team,lane,d.area_damage,u.kind,u)
	m.event("arcane_impact",point,u.team,{"from":u.pos,"radius":d.radius,"clock":true})

static func shoot_piercing_arrow(m, u: Dictionary, target: Dictionary = {}) -> void:
	var d: Dictionary = B.CARDS[u.kind]
	var direction := 1.0 if u.team == 0 else -1.0
	if not target.is_empty() and not is_equal_approx(target.pos.x,u.pos.x): direction = signf(target.pos.x-u.pos.x)
	var reach: float = B.actor_radius(u)+u.get("range",d.range)*d.pierce_range_multiplier
	m.projectiles.append({"source":u,"piercing":true,"hit_ids":[],"travelled":0.0,"primary_hit":false,"pos":u.pos+Vector2(0,-30),"start":u.pos+Vector2(0,-30),"origin":u.pos,"end":u.pos+Vector2(direction*reach,-30),"direction":direction,"range":reach,"lane":u.lane,"target":target,"remaining":B.ARROW_TIME,"amount":u.get("damage",d.damage),"team":u.team,"kind":u.kind})

static func advance_piercing_arrow(m, a: Dictionary) -> void:
	var previous: float = a.travelled
	var reached: float = a.range*clampf(1-a.remaining/B.ARROW_TIME,0,1)
	a.pos = a.start.lerp(a.end,clampf(1-a.remaining/B.ARROW_TIME,0,1))
	for target: Dictionary in m.units:
		var r: float = B.actor_radius(target)
		var distance: float = (target.pos.x-a.origin.x)*a.direction
		if target.team != a.team and target.hp > 0 and target.lane == a.lane and distance+r >= previous and distance-r <= reached and not target.id in a.hit_ids:
			a.hit_ids.append(target.id)
			m.damage(target,a.amount,a.team,a.kind,a.get("source",{}))
			reveal(m, target)
	if a.kind != "long_dragon":
		for b: Dictionary in m.buildings:
			if b.team == a.team or b.hp <= 0 or b.cell.y != a.lane or B.CARDS[b.kind].has("trap") or b.id in a.hit_ids: continue
			var r_b: float = B.actor_radius(b)
			var distance: float = (b.pos.x-a.origin.x)*a.direction
			if distance+r_b >= previous and distance-r_b <= reached:
				a.hit_ids.append(b.id)
				m.damage(b,a.amount,a.team,a.kind,a.get("source",{}))
		var enemy: int = 1-a.team
		var forward := 1.0 if a.team == 0 else -1.0
		if not a.get("gate_hit",false) and is_equal_approx(a.direction,forward) and m.gates[enemy][a.lane] > 0:
			var gate_dist: float = (L.gate_stop(enemy)-a.origin.x)*a.direction
			if gate_dist >= previous and gate_dist <= reached:
				a.gate_hit = true
				m.hit_gate(enemy,a.lane,a.amount,a.kind,a.get("source",{}))
	if not a.primary_hit:
		var point: Vector2 = a.target.pos if not a.target.is_empty() else Vector2(L.gate_stop(1-a.team),a.origin.y)
		var r_t: float = B.actor_radius(a.target) if not a.target.is_empty() else 0.0
		var distance: float = (point.x-a.origin.x)*a.direction
		if distance+r_t >= previous and distance-r_t <= reached:
			a.primary_hit = true
			if a.target.is_empty() or a.target.get("kind","") == "gate":
				if not a.get("gate_hit",false):
					a.gate_hit = true
					var g_side: int = 1-a.team if a.target.is_empty() else a.target.team
					var g_lane: int = a.lane if a.target.is_empty() else a.target.lane
					m.hit_gate(g_side,g_lane,a.amount,a.kind,a.get("source",{}))
			elif a.target.kind == "lord" and a.target.hp > 0: m.damage(a.target,a.amount,a.team,a.kind,a.get("source",{}))
			elif a.target.has("cell") and a.target.hp > 0 and not a.target.id in a.hit_ids:
				a.hit_ids.append(a.target.id)
				m.damage(a.target,a.amount,a.team,a.kind,a.get("source",{}))
	a.travelled = reached
