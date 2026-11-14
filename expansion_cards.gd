extends RefCounted
# Data-driven support and production for the November art expansion.
const B = preload("res://balance.gd")
const Arcane = preload("res://arcane_mechanics.gd")
const ExpansionMore = preload("res://expansion_more.gd")

static func update(m, dt: float) -> void:
	for actor: Dictionary in m.units+m.buildings:
		var d: Dictionary = B.CARDS.get(actor.kind,{})
		if not d.get("expansion",false) or actor.hp <= 0 or actor.get("spawn_delay",0.0) > 0: continue
		if d.has("reveal_radius"):
			for foe: Dictionary in m.units:
				if foe.hp > 0 and foe.team != actor.team and foe.get("stealthed",false) and foe.pos.distance_to(actor.pos) <= d.reveal_radius: Arcane.reveal(m,foe)
		if not d.has("period"): continue
		actor.expansion_clock = actor.get("expansion_clock",0.0)+dt
		if actor.expansion_clock < d.period: continue
		actor.expansion_clock -= d.period
		if d.has("regen_amount") and actor.hp < actor.max_hp:
			actor.hp = minf(actor.max_hp,actor.hp+d.regen_amount)
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

static func support(m, actor: Dictionary, d: Dictionary) -> void:
	if ExpansionMore.support(m,actor,d): return
	var allies: Array = m.buildings if d.support == "repair" else m.units
	var active := false
	for u: Dictionary in allies:
		if u.hp <= 0 or u.team != actor.team or u.get("spawn_delay",0.0) > 0 or u.pos.distance_to(actor.pos) > d.radius: continue
		match d.support:
			"heal", "repair":
				if u.hp < u.max_hp:
					if m.record_events: active = true
					u.hp = minf(u.max_hp,u.hp+d.support_amount)
					if m.record_events: m.link(actor.pos,u.pos,actor.team,d.support)
			"shield":
				if m.record_events: active = true
				# Refresh a bounded shield, rather than accumulating an unlimited passive shield.
				u.shield = maxf(u.get("shield",0.0) if u.get("shield_until",0.0) > m.elapsed else 0.0,d.support_amount)
				u.shield_until = m.elapsed+d.duration
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

static func absorb(m, target: Dictionary, amount: float, source: Dictionary) -> float:
	if target.get("armor_until",0.0) > m.elapsed and not B.CARDS.get(source.get("kind",""),{}).get("ignore_armor",false):
		return maxf(1.0,amount-target.get("expansion_armor",0.0))
	return amount

static func attack_damage(m, u: Dictionary, target: Dictionary, amount: float) -> float:
	var d: Dictionary = B.CARDS[u.kind]
	if d.has("charge_damage") and not u.get("expansion_charged",false):
		u.expansion_charged = true
		if target.has("spawn_delay"): target.stun_left = maxf(target.get("stun_left",0.0),d.charge_stun)
		if m.record_events: m.event("charge_impact",target.pos,u.team,{"radius":26.0,"face":1.0 if u.team == 0 else -1.0})
		return d.charge_damage
	return amount

static func on_death(m, dead: Dictionary) -> void:
	for b: Dictionary in m.buildings:
		var d: Dictionary = B.CARDS.get(b.kind,{})
		if not d.has("death_income") or b.hp <= 0 or b.pos.distance_to(dead.pos) > d.radius or b.get("soul_ready",0.0) > m.elapsed: continue
		if d.get("death_side","") == "ally" and dead.team != b.team: continue # 殯儀小屋: only our own dead
		b.soul_ready = m.elapsed+d.period
		m.gain_ink(b.team,d.death_income)
		m.link(dead.pos,b.pos,b.team,"soul")

