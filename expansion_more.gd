extends RefCounted
# 2026-11-13 expansion, second half (docs/2026-11-13素材擴充設計.md): merchant mercenaries (neutral),
# blood thralls (dark) and faction gunpowder troops. Behaviour comes from card data fields so new
# cards need no code: shuttle, lob, suicide_blast, bonus_vs, structure_mult, damage_roll, kill_income,
# lifesteal, last_stand, spell_resist, ally_death_spawn, root / temporary summons from spells.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

const SPELLS := ["borrowed_bones","grave_exchange","mourning_shroud","sealed_coffin"]

# ---------------- troops ----------------

# Called from update_unit after stun / fear. True = this troop's step is handled here.
static func update_unit(m, u: Dictionary, data: Dictionary, dt: float) -> bool:
	if u.get("root_left",0.0) > 0: u.root_left = maxf(0.0,u.root_left-dt)
	if not data.get("shuttle",false): return false
	# 騾馬貨車: out to the middle of the field, back to our gate, paid on arrival, out again.
	var home: float = L.spawn_position(u.team,u.lane).x
	var mid: float = L.GRID_ORIGIN.x+L.GRID_SIZE.x*0.5
	var out := 1.0 if u.team == 0 else -1.0
	var going: bool = u.get("shuttle_out",true)
	var goal: float = mid if going else home
	u.face = out if going else -out
	u.pos.x = move_toward(u.pos.x,goal,m.movement_speed(u)*dt)
	if is_equal_approx(u.pos.x,goal):
		if not going:
			m.gain_ink(u.team,data.shuttle_income)
			m.event("ink",u.pos,u.team)
		u.shuttle_out = not going
	return true

# Rooted troops (封棺) cannot walk but still fight.
static func speed_factor(u: Dictionary) -> float:
	return 0.0 if u.get("root_left",0.0) > 0 else 1.0

# Replaces the normal hit for lobbing and self-destructing troops. True = handled.
static func attack(m, u: Dictionary, target: Dictionary, data: Dictionary) -> bool:
	if data.get("suicide_blast",false):
		blast(m,u,target.pos,data)
		return true
	if data.get("lob",false):
		m.projectiles.append({"source":u,"pos":u.pos,"start":u.pos,"impact":target.pos,"flight":data.get("flight_time",0.8),"remaining":data.get("flight_time",0.8),"amount":data.area_damage,"radius":data.radius,"team":u.team,"kind":u.get("card",u.kind)})
		m.event("catapult_fire",u.pos,u.team,{"target":target.pos})
		return true
	return false

# The same troops reaching a closed gate.
static func gate_attack(m, u: Dictionary, data: Dictionary, enemy: int) -> bool:
	if not data.get("suicide_blast",false): return false
	blast(m,u,Vector2(L.gate_stop(enemy),u.pos.y),data)
	return true

static func blast(m, u: Dictionary, point: Vector2, data: Dictionary) -> void:
	for t: Dictionary in m.units+m.buildings:
		if t.team != u.team and t.hp > 0 and t.pos.distance_to(point) <= data.radius: m.damage(t,data.area_damage,u.team,u.get("card",u.kind),u)
	for lane: int in m.active_lanes:
		if Vector2(L.gate_stop(1-u.team),L.cell_center(Vector2i(0,lane)).y).distance_to(point) <= data.radius: m.hit_gate(1-u.team,lane,data.area_damage,u.get("card",u.kind),u)
	m.event("stone_impact",point,u.team,{"radius":data.radius})
	m.damage(u,u.hp,u.team,"suicide_blast",{},true)

# ---------------- damage ----------------

static func faction_of(target: Dictionary) -> String:
	if target.get("kind","") == "lord": return "lord"
	return B.card_faction(target.kind) if B.CARDS.has(target.get("kind","")) else ""

# A troop's hit against a unit / building / lord, before defences.
static func modify_attack(m, u: Dictionary, target: Dictionary, amount: float) -> float:
	var d: Dictionary = B.CARDS[u.kind]
	if d.has("damage_roll"):
		amount = m.rng.randf_range(B.tier_value("damage",d.damage_roll[0]),B.tier_value("damage",d.damage_roll[1]))
	if d.has("bonus_vs"):
		var f := faction_of(target)
		if d.bonus_vs.has(f): amount *= d.bonus_vs[f]
	if d.has("structure_mult") and target.has("cell"): amount *= d.structure_mult
	return amount

static func gate_amount(m, u: Dictionary, amount: float) -> float:
	var d: Dictionary = B.CARDS[u.kind]
	if d.has("damage_roll"): amount = m.rng.randf_range(B.tier_value("damage",d.damage_roll[0]),B.tier_value("damage",d.damage_roll[1]))
	return amount*d.get("structure_mult",1.0)

# Defence against a hit (after armour): spell resistance.
static func absorb(target: Dictionary, amount: float, kind: String) -> float:
	var d: Dictionary = B.CARDS.get(target.get("kind",""),{})
	if d.has("spell_resist") and B.CARDS.get(kind,{}).get("type","") == "spell": return amount*d.spell_resist
	return amount

# Right after hp drops: lifesteal for the attacker, last stand for the target, bounty on a kill.
static func after_hit(m, target: Dictionary, dealt: float, source: Dictionary) -> void:
	var sd: Dictionary = B.CARDS.get(source.get("kind",""),{}) if source.has("spawn_delay") else {}
	if sd.has("lifesteal") and source.hp > 0: source.hp = minf(source.max_hp,source.hp+dealt*sd.lifesteal)
	if target.hp <= 0 and target.has("spawn_delay"):
		var td: Dictionary = B.CARDS.get(target.kind,{})
		var saved := false
		if td.get("last_stand",false) and not target.get("stood",false):
			target.stood = true
			saved = true
		elif target.get("shroud_until",0.0) > m.elapsed:
			target.shroud_until = 0.0
			saved = true
		if saved:
			target.hp = 1.0
			m.event("heal",target.pos,target.team)
			return
		if sd.has("kill_income") and source.team != target.team:
			m.gain_ink(source.team,sd.kill_income)
			m.event("ink",target.pos,source.team)

# A troop died (death queue): carts pay their loot, stitchers sew a skeleton, temporary bones vanish.
static func on_death(m, dead: Dictionary) -> void:
	var dd: Dictionary = B.CARDS.get(dead.kind,{})
	if dd.has("shuttle_loot"): m.gain_ink(1-dead.team,dd.shuttle_loot)
	for u: Dictionary in m.units:
		var d: Dictionary = B.CARDS.get(u.kind,{})
		if u.hp <= 0 or not d.has("ally_death_spawn") or u.team != dead.team or u.pos.distance_to(dead.pos) > d.radius: continue
		if u.get("stitch_ready",0.0) > m.elapsed or dead.kind == d.ally_death_spawn: continue
		u.stitch_ready = m.elapsed+d.stitch_cooldown
		var child: Dictionary = m.spawn_unit(u.team,dead.lane,d.ally_death_spawn,dead.pos)
		child.card = u.kind
		m.link(u.pos,dead.pos,u.team,"summon")
		m.event("summoned",child.pos,child.team)

# Per tick: borrowed bones go back to their coffins when time is up (no death effects).
static func update(m, _dt: float) -> void:
	m.units = m.units.filter(func(u: Dictionary) -> bool:
		if u.get("borrowed_until",-1.0) < 0 or u.borrowed_until > m.elapsed or u.hp <= 0: return true
		m.event("levy_dust",u.pos,u.team)
		return false)

# Periodic supports that touch enemies or cost hp (called from Expansion.support).
static func support(m, actor: Dictionary, d: Dictionary) -> bool:
	match d.support:
		"slow":
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team != actor.team and u.pos.distance_to(actor.pos) <= d.radius and not u.get("flying",false):
					u.slow_left = maxf(u.get("slow_left",0.0),d.duration)
			m.event("drum",actor.pos,actor.team,{"duration":0.6})
			return true
		"cleanse":
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team == actor.team and u.pos.distance_to(actor.pos) <= d.radius:
					u.stun_left = 0.0
					u.slow_left = 0.0
					u.fear_left = 0.0
					u.root_left = 0.0
			return true
		"tithe":
			var paid := 0
			for u: Dictionary in m.units:
				if paid >= d.tithe_max: break
				if u.hp <= 1 or u.team != actor.team or u.get("spawn_delay",0.0) > 0 or u.pos.distance_to(actor.pos) > d.radius: continue
				u.hp = maxf(1.0,u.hp-d.tithe_hp)
				paid += 1
				m.link(u.pos,actor.pos,actor.team,"devour")
			if paid > 0:
				m.gain_ink(actor.team,paid)
				m.event("ink",actor.pos,actor.team)
			return true
	return false

# ---------------- spells ----------------

static func cast(m, s: Dictionary) -> bool:
	if not s.kind in SPELLS: return false
	var d: Dictionary = B.CARDS[s.kind]
	m.event("spell",s.pos,s.team,{"card":s.kind,"radius":d.radius})
	var lane: int = clampi(floori((s.pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,L.GRID_ROWS-1)
	match s.kind:
		"borrowed_bones":
			for i: int in range(d.summon_count):
				var u: Dictionary = m.spawn_unit(s.team,lane,"skeleton",Vector2(s.pos.x,L.cell_center(Vector2i(0,lane)).y))
				u.card = s.kind
				u.dy = (i-(d.summon_count-1)*0.5)*10.0
				u.spawn_delay = 0.08*i
				u.borrowed_until = m.elapsed+d.summon_life
				m.event("summoned",u.pos,u.team)
		"grave_exchange":
			for b: Dictionary in m.buildings.duplicate():
				if b.hp <= 0 or b.team != s.team or b.pos.distance_to(s.pos) > d.radius or B.is_home_card(b.kind,m.lords[s.team].lord): continue
				m.gain_ink(s.team,roundf(B.CARDS[b.kind].cost*d.refund))
				for i: int in range(d.skeletons):
					var u: Dictionary = m.spawn_unit(s.team,b.cell.y,"skeleton",b.pos)
					u.card = s.kind
					u.spawn_delay = 0.1*i
				m.damage(b,b.hp,s.team,s.kind,{},true)
		"mourning_shroud":
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team == s.team and u.pos.distance_to(s.pos) <= d.radius: u.shroud_until = m.elapsed+d.duration
		"sealed_coffin":
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team != s.team and u.pos.distance_to(s.pos) <= d.radius and not u.get("flying",false): u.root_left = d.root
	return true

static func play_error(m, team: int, kind: String, pos: Vector2) -> String:
	if kind == "grave_exchange":
		var lord: String = m.lords[team].lord
		if not m.buildings.any(func(b: Dictionary) -> bool: return b.hp > 0 and b.team == team and b.pos.distance_to(pos) <= B.CARDS.grave_exchange.radius and not B.is_home_card(b.kind,lord)): return "no building"
	return ""

# ---------------- AI ----------------

static func ai_score(c: Dictionary, s: Dictionary) -> float:
	var team: int = s.team
	var data: Dictionary = B.CARDS[c.kind]
	match c.kind:
		"borrowed_bones", "sealed_coffin":
			var foes := 0
			for u: Dictionary in s.units:
				if u.hp > 0 and u.team != team and u.pos.distance_to(c.pos) <= data.radius: foes += 1
			if foes >= 3: return 700.0+foes*10
		"mourning_shroud":
			var allies := 0
			var fighting := false
			for u: Dictionary in s.units:
				if u.hp <= 0 or u.pos.distance_to(c.pos) > data.radius: continue
				if u.team == team: allies += 1
				else: fighting = true
			if allies >= 3 and fighting: return 680.0+allies*10
		"grave_exchange":
			if s.ink < 5:
				var n := 0
				for b: Dictionary in s.buildings:
					if b.hp > 0 and b.team == team and b.pos.distance_to(c.pos) <= data.radius and b.hp < b.max_hp*0.4: n += 1
				if n >= 1: return 650.0+n*20
	return -INF
