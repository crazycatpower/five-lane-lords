extends RefCounted
# Data-driven support and production for the November art expansion.
const B = preload("res://balance.gd")
const Arcane = preload("res://arcane_mechanics.gd")
const ExpansionMore = preload("res://expansion_more.gd")

static func _update_actor(m, actor: Dictionary, dt: float) -> void:
	var d: Dictionary = B.CARDS.get(actor.kind,{})
	if not d.get("expansion",false) or actor.hp <= 0 or actor.get("spawn_delay",0.0) > 0: return
	if d.has("reveal_radius"):
		for foe: Dictionary in m.units:
			if foe.hp > 0 and foe.team != actor.team and (foe.get("stealthed",false) or (B.CARDS[foe.kind].get("stealth",false) and not foe.get("revealed",false))) and B.edge_distance(actor,foe) <= d.reveal_radius: Arcane.reveal(m,foe)
	if not d.has("period"): return
	actor.expansion_clock = actor.get("expansion_clock",0.0)+dt
	if actor.expansion_clock < d.period: return
	actor.expansion_clock -= d.period
	if d.has("regen_amount") and actor.hp < actor.max_hp:
		var regen: float = d.regen_amount*(1.5 if actor.get("march_time",0.0) >= B.CHARGE_RESET_TIME else 1.0)
		actor.hp = minf(actor.max_hp,actor.hp+regen)
		if m.record_events: m.event("heal",actor.pos,actor.team)
	if d.has("income"):
		m.gain_ink(actor.team,d.income)
		m.event("ink",actor.pos,actor.team)
	if d.has("spawn_kind"):
		for i: int in range(d.spawn_count):
			var u: Dictionary = m.spawn_unit(actor.team,actor.cell.y,d.spawn_kind,actor.pos+Vector2(-24 if actor.team == 0 else 24,(i-(d.spawn_count-1)*0.5)*12))
			u.card = actor.kind
			m.event("summoned",u.pos,u.team)
	if d.has("support"): support(m,actor,d)

static func update(m, dt: float) -> void:
	if not m.has_expansion_tick: return
	var Faction = preload("res://faction_cards.gd")
	var u_count: int = m.units.size()
	for i: int in range(u_count):
		var u: Dictionary = m.units[i]
		if u.get("has_expansion_tick",false): _update_actor(m,u,dt)
	var b_count: int = m.buildings.size()
	for i: int in range(b_count):
		var b: Dictionary = m.buildings[i]
		if b.get("has_expansion_tick",false): _update_actor(m,b,dt*Faction.building_factor(m,b))

static func support(m, actor: Dictionary, d: Dictionary) -> void:
	if ExpansionMore.support(m,actor,d): return
	var allies: Array = m.buildings if d.support == "repair" else m.units
	var active := false
	for u: Dictionary in allies:
		if u.hp <= 0 or u.team != actor.team or u.get("spawn_delay",0.0) > 0 or B.edge_distance(actor,u) > d.radius: continue
		match d.support:
			"heal":
				var poisoned: bool = int(u.get("hex_stacks",0)) > 0 or int(u.get("poison_stacks",0)) > 0
				if u.hp < u.max_hp or poisoned:
					if m.record_events: active = true
					u.hp = minf(u.max_hp,u.hp+d.support_amount)
					if int(u.get("hex_stacks",0)) > 0:
						u.hex_stacks = maxi(0,int(u.hex_stacks)-1)
						if u.hex_stacks == 0:
							u.hex_left = 0.0
							u.hex_team = -1
					if int(u.get("poison_stacks",0)) > 0:
						u.poison_stacks = maxi(0,int(u.poison_stacks)-1)
						if u.poison_stacks == 0:
							u.poison_left = 0.0
							u.poison_team = -1
					if m.record_events:
						m.event("heal",u.pos,actor.team)
						m.link(actor.pos,u.pos,actor.team,d.support)
			"repair":
				if u.hp < u.max_hp:
					if m.record_events: active = true
					u.hp = minf(u.max_hp,u.hp+d.support_amount)
					if m.record_events: m.link(actor.pos,u.pos,actor.team,d.support)
			"shield":
				if m.record_events: active = true
				# Refresh a bounded shield, preserving endless shields if already applied.
				var s_until: float = float(u.get("shield_until",0.0))
				var s_active: bool = s_until < 0.0 or s_until > m.elapsed
				u.shield = maxf(u.get("shield",0.0) if s_active else 0.0,d.support_amount)
				if s_until >= 0.0: u.shield_until = m.elapsed+d.duration
			"armor":
				if m.record_events: active = true
				u.expansion_armor = maxf(u.get("expansion_armor",0.0) if u.get("armor_until",0.0) > m.elapsed else 0.0,d.support_amount)
				u.armor_until = m.elapsed+d.duration
			"haste":
				if m.record_events: active = true
				u.expansion_haste_until = m.elapsed+d.duration
			"range":
				if m.record_events: active = active or B.CARDS.get(u.kind,{}).get("projectile",false)
				u.expansion_range_until = m.elapsed+d.duration
	if m.record_events and active:
		m.event("support_pulse",actor.pos,actor.team,{"style":d.support,"radius":d.radius})

static func absorb(_m, _target: Dictionary, amount: float, _source: Dictionary) -> float:
	return amount

static func attack_damage(m, u: Dictionary, target: Dictionary, amount: float) -> float:
	var d: Dictionary = B.CARDS[u.kind]
	if d.has("charge_damage") and not u.get("charged",false) and not u.get("expansion_charged",false):
		u.charged = true
		u.expansion_charged = true
		u.march_time = 0.0
		if target.has("spawn_delay"):
			target.stun_left = maxf(target.get("stun_left",0.0),d.charge_stun)
			m.knockback_unit(target,u.face*15.0)
		if m.record_events: m.event("charge_impact",target.pos,u.team,{"radius":26.0,"face":1.0 if u.team == 0 else -1.0})
		return d.charge_damage
	if u.get("granted_charge",false):
		u.granted_charge = false
		u.march_time = 0.0
		if target.has("spawn_delay"):
			target.stun_left = maxf(target.get("stun_left",0.0),float(u.get("granted_charge_stun",0.5)))
			m.knockback_unit(target,u.face*15.0)
		if m.record_events: m.event("charge_impact",target.pos,u.team,{"radius":26.0,"face":1.0 if u.team == 0 else -1.0})
		return amount*2.0
	return amount

static func on_death(m, dead: Dictionary) -> void:
	for b: Dictionary in m.buildings:
		var d: Dictionary = B.CARDS.get(b.kind,{})
		if not d.has("death_income") or b.hp <= 0 or B.point_edge_distance(b.pos,dead) > d.radius: continue
		var period: float = d.get("period",0.0)
		if period > 0.0 and b.get("soul_ready",0.0) > m.elapsed: continue
		if d.get("death_side","") == "ally" and dead.team != b.team: continue # 殯儀小屋: only our own dead
		if period > 0.0: b.soul_ready = m.elapsed+period
		m.gain_ink(b.team,d.death_income)
		var charge: float = float(d.get("death_charge",0.0))
		if charge > 0.0: m.add_skill_charge(b.team,charge)
		m.link(dead.pos,b.pos,b.team,"soul")

