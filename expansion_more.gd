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

# Replaces the normal hit for lobbing, self-destructing and curse-splash troops. True = handled.
static func attack(m, u: Dictionary, target: Dictionary, data: Dictionary) -> bool:
	if data.get("suicide_blast",false):
		blast(m,u,target.pos,data)
		return true
	if data.get("lob",false):
		m.projectiles.append({"source":u,"pos":u.pos,"start":u.pos,"impact":target.pos,"flight":data.get("flight_time",0.8),"remaining":data.get("flight_time",0.8),"amount":data.area_damage,"radius":data.radius,"team":u.team,"kind":u.get("card",u.kind)})
		m.event("catapult_fire",u.pos,u.team,{"target":target.pos})
		return true
	if data.has("dot_damage"):
		var direction: float = 1.0 if target.pos.x >= u.pos.x else -1.0
		var origin: Vector2 = u.pos+Vector2(0,u.get("dy",0.0))+Vector2(direction*16,-30)
		m.projectiles.append({"source":u,"direction":direction,"pos":origin,"start":origin,"target":target,"remaining":B.ARROW_TIME,"amount":data.area_damage,"radius":data.radius,"dot_damage":data.dot_damage,"dot_interval":data.dot_interval,"dot_ticks":data.dot_ticks,"curse_splash":true,"team":u.team,"kind":u.get("card",u.kind)})
		m.event("arrow",u.pos,u.team)
		return true
	return false

# Splash impact for curse projectiles; returns true if handled.
static func hit_projectile(m, arrow: Dictionary) -> bool:
	if not arrow.get("curse_splash",false): return false
	var target: Dictionary = arrow.get("target",{})
	var point: Vector2 = target.get("pos",arrow.pos)
	var src: Dictionary = arrow.get("source",{})
	for u: Dictionary in m.units:
		if u.hp <= 0 or u.team == arrow.team or u.pos.distance_to(point) > arrow.radius: continue
		m.damage(u,arrow.amount,arrow.team,arrow.kind,src)
		if u.hp > 0:
			u.hex_ticks = int(arrow.dot_ticks)
			u.hex_interval = float(arrow.dot_interval)
			u.hex_timer = float(arrow.dot_interval)
			u.hex_damage = float(arrow.dot_damage)
			u.hex_team = arrow.team
			u.hex_kind = arrow.kind
	if not target.is_empty() and (target.has("cell") or target.get("kind","") == "lord") and target.hp > 0:
		m.damage(target,arrow.amount,arrow.team,arrow.kind,src)
	m.event("witch_curse",point,arrow.team,{"radius":arrow.radius,"from":arrow.start})
	return true

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
	if u.get("crit_mult",1.0) > 1.0:
		amount *= u.crit_mult
		u.erase("crit_mult")
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
		if sd.get("split_on_kill",false) and source.team != target.team and source.hp > 0:
			var child: Dictionary = m.spawn_unit(source.team,source.lane,source.kind,source.pos)
			child.card = source.kind
			m.event("summoned",child.pos,child.team)
	if target.has("spawn_delay") and target.hp > 0 and sd.get("root_on_hit",0.0) > 0 and not target.get("flying",false) and target.get("web_icd",0.0) <= m.elapsed:
		target.root_left = maxf(target.get("root_left",0.0),sd.root_on_hit)
		target.web_icd = m.elapsed+4.0
	if target.has("spawn_delay") and target.hp > 0:
		var td_hit: Dictionary = B.CARDS.get(target.kind,{})
		if td_hit.has("reflect_damage") and target.get("reflect_icd",0.0) <= m.elapsed and (source.is_empty() or B.CARDS.get(source.get("kind",""),{}).get("projectile",false) or B.CARDS.get(source.get("kind",""),{}).get("type","") == "spell"):
			var foe: Dictionary = m.nearest(target.pos,target.team,td_hit.range,m.foe_units[target.team])
			if not foe.is_empty():
				target.reflect_icd = m.elapsed+2.0
				m.damage(foe,td_hit.reflect_damage,target.team,target.kind)
				m.link(target.pos,foe.pos,target.team,"lightning")
	if target.has("cell") and target.kind == "mimic_egg": hatch_egg(m,target)
	if target.has("cell") and target.kind == "mana_battery" and target.hp <= 0: burst_battery(m,target)

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
	for u: Dictionary in m.units:
		var sd: Dictionary = B.CARDS.get(u.kind,{})
		if u.hp <= 0 or not sd.get("scavenger",false) or u.pos.distance_to(dead.pos) > sd.radius: continue
		u.hp = minf(u.max_hp,u.hp+sd.scavenger_heal)
		var ti: int = B.TIERS.damage.find(u.get("damage",sd.damage))
		if ti > 0: u.damage = B.TIERS.damage[maxi(B.tier_index("A"),ti-1)]
		m.link(dead.pos,u.pos,u.team,"devour")

# Per tick: advance hex DoT ticks, then remove expired borrowed bones (no death effects).
static func update(m, dt: float) -> void:
	for u: Dictionary in m.units:
		if u.hp <= 0 or u.get("hex_ticks",0) <= 0 or u.get("hex_team",-1) < 0: continue
		var interval: float = u.get("hex_interval",1.0)
		u.hex_timer = u.get("hex_timer",interval)-dt
		while u.hex_timer <= 0.000001 and u.hex_ticks > 0:
			u.hex_timer += interval
			u.hex_ticks -= 1
			m.damage(u,u.get("hex_damage",20.0),u.hex_team,u.get("hex_kind","old_witch"))
			if u.hp <= 0: break
		if u.hex_ticks <= 0:
			u.hex_ticks = 0
			u.hex_team = -1
	m.units = m.units.filter(func(u: Dictionary) -> bool:
		if u.get("borrowed_until",-1.0) < 0 or u.borrowed_until > m.elapsed or u.hp <= 0: return true
		m.event("levy_dust",u.pos,u.team)
		return false)
	tick_buildings_and_zones(m,dt)

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
					u.hex_ticks = 0
					u.hex_team = -1
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
	var d: Dictionary = B.CARDS[s.kind]
	var data_spell: bool = d.get("expansion_spell",false)
	if not s.kind in SPELLS and not data_spell: return false
	m.event("spell",s.pos,s.team,{"card":s.kind,"radius":d.radius})
	var lane: int = clampi(floori((s.pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,L.GRID_ROWS-1)
	if data_spell:
		cast_effects(m,s,d,lane)
		return true
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

static func cast_effects(m, s: Dictionary, d: Dictionary, lane: int) -> void:
	var dir := 1.0 if s.team == 0 else -1.0
	if s.kind == "flaming_pitch":
		var pools: Array = m.get_meta("pitch_pools",[])
		pools.append({"pos":s.pos,"team":s.team,"radius":d.radius,"left":d.duration,"tick":0.0,"damage":d.tick_damage})
		m.set_meta("pitch_pools",pools)
		return
	if s.kind == "mirror_clone":
		var best: Dictionary = {}
		for u: Dictionary in m.units:
			if u.hp > 0 and u.team == s.team and u.get("spawn_delay",0.0) <= 0 and u.pos.distance_to(s.pos) <= d.radius and (best.is_empty() or u.hp > best.hp):
				best = u
		if not best.is_empty():
			var clone: Dictionary = m.spawn_unit(s.team,best.lane,best.kind,best.pos+Vector2(-12*dir,10))
			clone.hp = best.hp
			clone.max_hp = best.max_hp
			clone.borrowed_until = m.elapsed+d.duration
			m.event("summoned",clone.pos,s.team)
		return
	var hits := 0
	var execs := 0
	var killed_foes: Array = []
	for u: Dictionary in m.units.duplicate():
		if u.hp <= 0 or u.pos.distance_to(s.pos) > d.radius: continue
		if u.team == s.team:
			if d.get("reset_attack",false): u.cd = 0.0
			if d.has("phase_shift"):
				u.phased = true
				u.stealthed = true
				u.pos.x = clampf(u.pos.x+dir*d.phase_shift,L.gate_stop(0)+10.0,L.gate_stop(1)-10.0)
			if d.has("hp_cost_share") and u.hp > 1.0:
				u.hp = maxf(1.0,u.hp*(1.0-d.hp_cost_share))
				var di: int = B.TIERS.damage.find(u.get("damage",B.CARDS[u.kind].damage))
				if di > 0: u.damage = B.TIERS.damage[maxi(B.tier_index("S"),di-1)]
			if d.get("beast_pounce",false) and B.card_faction(u.kind) == "beast":
				u.pos.x = clampf(u.pos.x+dir*60.0,L.gate_stop(0)+10.0,L.gate_stop(1)-10.0)
				var p_dmg: float = u.get("damage",B.CARDS[u.kind].damage)
				for f: Dictionary in m.units:
					if f.hp > 0 and f.team != s.team and f.pos.distance_to(u.pos) <= 52.0: m.damage(f,p_dmg,s.team,s.kind)
			if d.get("upgrade_hp",false):
				var hi: int = B.TIERS.hp.find(u.max_hp)
				if hi > 0:
					var nhp: float = B.TIERS.hp[maxi(B.tier_index("S"),hi-1)]
					u.hp += nhp-u.max_hp
					u.max_hp = nhp
		else:
			if d.has("knockback"):
				u.pos.x = clampf(u.pos.x+dir*d.knockback,L.gate_stop(0)+10.0,L.gate_stop(1)-10.0)
			if d.get("pull_center",false):
				u.pos = u.pos.lerp(s.pos,0.75)
				u.stun_left = maxf(u.get("stun_left",0.0),d.get("stun_on_hit",1.0))
			if d.get("strip_defences",false):
				u.shield = 0.0
				u.shield_until = 0.0
				u.armor = 0.0
				u.expansion_armor = 0.0
				u.armor_until = 0.0
			if d.has("execute_hp") and not u.get("flying",false) and u.hp <= d.execute_hp and execs < int(d.get("execute_max",3)):
				execs += 1
				m.damage(u,u.hp,s.team,s.kind,{},true)
				m.gain_ink(s.team,d.get("execute_gold",2.0))
				continue
			if d.has("enemy_damage"):
				var was_alive: bool = u.hp > 0
				m.damage(u,d.enemy_damage,s.team,s.kind)
				hits += 1
				if was_alive and u.hp <= 0: killed_foes.append({"lane":u.lane,"pos":u.pos})
	if d.get("strip_defences",false) and d.has("enemy_damage"):
		for b: Dictionary in m.buildings:
			if b.hp > 0 and b.team != s.team and b.pos.distance_to(s.pos) <= d.radius: m.damage(b,d.enemy_damage,s.team,s.kind)
	if d.has("drain_gold_per_hit") and hits > 0:
		m.gain_ink(s.team,minf(float(hits)*d.drain_gold_per_hit,d.get("drain_gold_max",5.0)))
	if d.has("spawn_on_kill"):
		for kf: Dictionary in killed_foes:
			var child: Dictionary = m.spawn_unit(s.team,kf.lane,d.spawn_on_kill,kf.pos)
			child.borrowed_until = m.elapsed+d.get("spawn_life",12.0)
			m.event("summoned",child.pos,s.team)

static func on_card_played(m, team: int, kind: String, lane: int) -> void:
	var card: Dictionary = B.CARDS[kind]
	if card.type == "unit":
		for b: Dictionary in m.buildings:
			if b.hp > 0 and b.team == team and b.kind == "supply_depot" and b.cell.y == lane and b.get("depot_icd",0.0) <= m.elapsed:
				b.depot_icd = m.elapsed+5.0
				m.gain_ink(team,1.0)
				m.event("ink",b.pos,team)
	elif card.type == "spell":
		for b: Dictionary in m.buildings:
			if b.hp <= 0 or b.kind != "mana_battery": continue
			b.battery = b.get("battery",0)+1
			m.link(b.pos,b.pos,b.team,"mana")
			if b.battery >= B.CARDS.mana_battery.max_charges: burst_battery(m,b)

static func burst_battery(m, b: Dictionary) -> void:
	var charges: int = b.get("battery",0)
	if charges <= 0: return
	b.battery = 0
	var d: Dictionary = B.CARDS.mana_battery
	m.gain_ink(b.team,float(charges)*d.gold_per_charge)
	m.event("ink",b.pos,b.team)
	for u: Dictionary in m.units:
		if u.hp > 0 and u.team != b.team and u.pos.distance_to(b.pos) <= d.radius:
			m.damage(u,d.area_damage,b.team,b.kind)

static func hatch_egg(m, b: Dictionary) -> void:
	if b.get("hatched",false): return
	b.hatched = true
	var d: Dictionary = B.CARDS.mimic_egg
	for i: int in range(d.spawn_count):
		var u: Dictionary = m.spawn_unit(b.team,b.cell.y,d.spawn_kind,b.pos+Vector2(0,(i-1)*10.0))
		u.card = b.kind
		m.event("summoned",u.pos,b.team)
	for foe: Dictionary in m.units:
		if foe.hp > 0 and foe.team != b.team and foe.pos.distance_to(b.pos) <= d.radius:
			m.damage(foe,d.area_damage,b.team,b.kind)
	b.hp = 0
	m.refresh_territory()

static func tick_buildings_and_zones(m, dt: float) -> void:
	var pools: Array = m.get_meta("pitch_pools",[])
	var next_pools: Array = []
	for p: Dictionary in pools:
		p.left -= dt
		if p.left <= 0: continue
		p.tick -= dt
		if p.tick <= 0:
			p.tick += 1.0
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team != p.team and not u.get("flying",false) and u.pos.distance_to(p.pos) <= p.radius:
					if u.get("stealthed",false): u.stealthed = false
					m.damage(u,p.damage,p.team,"flaming_pitch")
			for b: Dictionary in m.buildings:
				if b.hp > 0 and b.team != p.team and b.pos.distance_to(p.pos) <= p.radius:
					m.damage(b,p.damage,p.team,"flaming_pitch")
		next_pools.append(p)
	m.set_meta("pitch_pools",next_pools)
	for b: Dictionary in m.buildings.duplicate():
		if b.hp <= 0: continue
		var d: Dictionary = B.CARDS.get(b.kind,{})
		if not d.get("expansion",false): continue
		if b.kind == "mimic_egg":
			b.egg_clock = b.get("egg_clock",0.0)+dt
			if b.egg_clock >= d.hatch_time: hatch_egg(m,b)
		elif b.kind == "warp_beacon":
			b.warp_clock = b.get("warp_clock",0.0)+dt
			if b.warp_clock >= d.period:
				b.warp_clock -= d.period
				var best: Dictionary = {}
				var best_d := INF
				for u: Dictionary in m.units:
					if u.hp > 0 and u.team != b.team and not u.get("flying",false) and u.lane == b.cell.y:
						var dist: float = absf(u.pos.x-b.pos.x)
						if dist <= d.range and dist < best_d:
							best_d = dist
							best = u
				if not best.is_empty():
					var back := 1.0 if best.team == 0 else -1.0
					best.pos.x = clampf(best.pos.x-back*d.pushback,L.gate_stop(0)+10.0,L.gate_stop(1)-10.0)
					m.link(b.pos,best.pos,b.team,"mana")
		elif b.kind == "blood_cauldron":
			b.cauldron_clock = b.get("cauldron_clock",0.0)+dt
			if b.cauldron_clock >= d.period:
				b.cauldron_clock -= d.period
				for u: Dictionary in m.units:
					if u.hp > 0 and u.team == b.team and B.card_faction(u.kind) == "beast" and u.pos.distance_to(b.pos) <= d.radius:
						u.crit_mult = d.crit_mult
						m.link(b.pos,u.pos,b.team,"devour")
		elif d.has("damage") and d.has("range") and d.has("interval"):
			b.cd = b.get("cd",0.0)-dt
			if b.cd <= 0:
				var target: Dictionary = m.nearest(b.pos,b.team,d.range,m.foe_units[b.team])
				if not target.is_empty():
					b.cd = d.interval
					m.shoot(b,target,d.damage)
					if d.get("lifesteal",0.0) > 0: b.hp = minf(b.max_hp,b.hp+d.damage*d.lifesteal)

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
				if u.hp <= 0 or u.team == team or u.pos.distance_to(c.pos) > data.radius: continue
				if c.kind == "sealed_coffin" and (u.get("flying",false) or u.get("root_left",0.0) > 1.0): continue
				foes += 1
			if foes >= 2: return 700.0+foes*10
		"mourning_shroud":
			var allies := 0
			var fighting := false
			for u: Dictionary in s.units:
				if u.hp <= 0 or u.pos.distance_to(c.pos) > data.radius: continue
				if u.team == team:
					if u.get("shroud_until",0.0) <= s.elapsed and u.get("spawn_delay",0.0) <= 0: allies += 1
				else: fighting = true
			if allies >= 2 and fighting: return 680.0+allies*10
		"grave_exchange":
			var lord: String = "underworld"
			for l: Dictionary in s.get("lords",[]):
				if l.team == team: lord = l.lord
			var value := 0.0
			for b: Dictionary in s.buildings:
				if b.hp <= 0 or b.team != team or b.pos.distance_to(c.pos) > data.radius or B.is_home_card(b.kind,lord): continue
				# Do not destroy a healthy neighbour just to recycle one damaged building.
				if b.hp > b.max_hp*0.4: return -INF
				value += roundf(B.CARDS[b.kind].cost*data.refund)+data.skeletons*B.CARDS.skeleton.cost
			if value > data.cost and s.ink < B.MAX_INK-data.cost: return 650.0+value*4
	return -INF

# Support/economy cards must not fall through to the generic sacrificial building score.
static func conditional_building(data: Dictionary) -> bool:
	return data.type == "building" and data.get("expansion",false) and (data.has("support") or data.has("death_income") or data.has("income") or data.has("spawn_kind"))

static func placement_score(c: Dictionary, s: Dictionary, pr: Dictionary) -> float:
	var d: Dictionary = B.CARDS[c.kind]
	var forward := 1.0 if s.team == 0 else -1.0
	var radius: float = d.get("radius",d.get("reveal_radius",150.0))
	var allies := 0.0
	var foes := 0.0
	var danger := 0.0
	var duplicates := 0
	for u: Dictionary in s.units:
		if u.hp <= 0: continue
		var distance: float = u.pos.distance_to(c.pos)
		if u.team != s.team:
			if distance <= radius: foes += 1
			if distance < 100 and u.lane == c.cell.y: danger += u.hp
			continue
		if distance > radius: continue
		if d.get("support","") == "range" and not B.CARDS.get(u.kind,{}).get("projectile",false): continue
		if d.get("support","") == "tithe" and u.hp <= d.tithe_hp*2: continue
		if d.get("support","") == "heal" and u.hp >= u.max_hp: continue
		allies += 1
	for b: Dictionary in s.buildings:
		if b.hp <= 0 or b.team != s.team: continue
		if b.kind == c.kind and b.pos.distance_to(c.pos) < radius*1.5: duplicates += 1
		if d.get("support","") == "repair" and b.pos.distance_to(c.pos) <= radius and b.hp < b.max_hp: allies += 1
	if conditional_building(d):
		if duplicates >= int(pr.get("support_density",1.0)): return -INF
		if danger > 0: return -INF
		var value := allies
		if d.has("death_income"): value = minf(allies,foes)
		if d.get("support","") == "slow": value = foes
		if d.has("income") or d.has("spawn_kind"): value = 2.0
		if value <= 0: return -INF
		return pr.get("support_score",640.0)+minf(value,5)*15-duplicates*80
	if d.type == "unit" and (d.has("support") or d.has("reveal_radius") or d.has("dot_damage")):
		# Spawn behind the troops being supported, not in front of the enemy.
		var reach_escort: float = d.range if d.has("dot_damage") else radius
		var escort := 0
		for u: Dictionary in s.units:
			if u.hp > 0 and u.team == s.team and u.lane == c.cell.y and (u.pos.x-c.pos.x)*forward >= 0 and absf(u.pos.x-c.pos.x) <= reach_escort: escort += 1
		if escort > 0: return pr.get("support_score",640.0)+escort*15-danger*0.1
	if c.kind == "orrery_walker":
		var line := 0
		for u: Dictionary in s.units:
			if u.hp > 0 and u.team != s.team and u.lane == c.cell.y and (u.pos.x-c.pos.x)*forward >= 0 and absf(u.pos.x-c.pos.x) <= d.range*d.pierce_range_multiplier: line += 1
		if line >= 2: return 700.0+line*15-danger*0.1
	return -INF
