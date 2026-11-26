extends RefCounted
# 魔物 cards (2026-11-06). Only the four new rules live here; flying (鉤鼻飛魔), lane hunting (魚喙怪)
# and the piercing breath (長身龍) reuse the existing behaviour fields.
# Hooks called from battle.gd: on_spawn, update, on_hit, on_gate_hit.
const B = preload("res://balance.gd")
const Arcane = preload("res://arcane_mechanics.gd")

# 眼翼龍: triggers fear roar on arrival and periodically every roar_period (5.0s).
static func do_roar(m, u: Dictionary) -> void:
	var d: Dictionary = B.CARDS[u.kind]
	if not d.has("roar_fear"): return
	for foe: Dictionary in m.units:
		if foe.hp > 0 and foe.team != u.team and foe.get("spawn_delay",0.0) <= 0 and B.edge_distance(u,foe) <= d.radius:
			foe.fear_left = maxf(foe.get("fear_left",0.0),d.roar_fear)
	m.event("roar",u.pos,u.team,{"radius":d.radius})

static func on_spawn(m, u: Dictionary) -> void:
	var d: Dictionary = B.CARDS[u.kind]
	if d.has("roar_fear"):
		do_roar(m, u)
		u.roar_cd = d.get("roar_period", 5.0)

# 腹眼魔: stealthed enemies near it lose their stealth. Phased riders stay hidden.
static func update(m, dt: float) -> void:
	if not m.has_monster_tick: return
	for u: Dictionary in m.units:
		if u.hp <= 0 or m.frozen(u.team) or not u.get("has_monster_tick",false) or u.get("spawn_delay",0.0) > 0: continue
		var d: Dictionary = B.CARDS[u.kind]
		if d.has("roar_fear") and d.has("roar_period"):
			u.roar_cd = u.get("roar_cd", d.roar_period) - dt
			if u.roar_cd <= 0.0:
				u.roar_cd += d.roar_period
				do_roar(m, u)
		var reach: float = d.get("reveal_radius",0.0)
		if reach > 0:
			for foe: Dictionary in m.foe_units[u.team]:
				if (foe.get("stealthed",false) or (B.CARDS[foe.kind].get("stealth",false) and not foe.get("revealed",false))) and B.edge_distance(u,foe) <= reach:
					Arcane.reveal(m, foe)

# A hit landed. 鬍子魔 steals from buildings; 骨刺龍 pricks the melee troop that hit it.
static func on_hit(m, target: Dictionary, source: Dictionary) -> void:
	var source_data: Dictionary = B.CARDS.get(source.get("kind",""),{})
	if source_data.is_empty() or not source.has("lane"): return # spells, lords and buildings
	if source_data.has("steal_gold") and target.has("cell"): steal(m,source)
	var thorns: float = float(target.get("thorns",B.CARDS.get(target.get("kind",""),{}).get("thorns",0.0)))
	thorns = preload("res://core_cards.gd").thorns(m,target,thorns) # 荊棘母獸 aura
	if thorns > 0 and source.hp > 0 and not m.ranged_hit and not m.is_ranged_attacker(source_data) and not source_data.get("suicide_blast",false):
		m.damage(source,thorns,target.team,target.get("card",target.kind)) # no source: thorns never bounce back

static func on_gate_hit(m, source: Dictionary) -> void:
	if B.CARDS.get(source.get("kind",""),{}).has("steal_gold"): steal(m,source)

static func steal(m, thief: Dictionary) -> void:
	var foe: int = 1-thief.team
	var amount: float = minf(B.CARDS[thief.kind].steal_gold,m.ink[foe])
	if amount <= 0: return
	m.ink[foe] -= amount
	m.gain_ink(thief.team,amount)
	m.event("ink",thief.pos,thief.team)
