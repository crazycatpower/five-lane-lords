extends RefCounted
# 2026-11-13 expansion, second half (design notes retired 2026-11-18; see the 企劃書 log / git history): merchant mercenaries (neutral),
# blood thralls (dark) and faction gunpowder troops. Behaviour comes from card data fields so new
# cards need no code: shuttle, lob, suicide_blast, bonus_vs, structure_mult, damage_roll, kill_income,
# lifesteal, last_stand, spell_resist, ally_death_spawn, root / temporary summons from spells.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

const SPELLS := ["borrowed_bones","grave_exchange","mourning_shroud","sealed_coffin"]

# ---------------- troops ----------------

static func shuttle_boundary_x(m, u: Dictionary) -> float:
	var home: float = L.spawn_position(u.team,u.lane).x
	var step_dir := 1 if u.team == 0 else -1
	var home_col := 0 if u.team == 0 else L.GRID_COLUMNS-1
	if m.territory_owner(Vector2i(home_col,u.lane)) != u.team:
		var front: int = m.front_column(u.team,u.lane)
		if front < 0: return home
		var edge_x: float = L.GRID_ORIGIN.x+(float(front+1) if u.team == 0 else float(front))*L.CELL_SIZE.x
		return clampf(edge_x,L.gate_stop(0),L.gate_stop(1))
	var edge_col := home_col
	while edge_col+step_dir >= 0 and edge_col+step_dir < L.GRID_COLUMNS and m.territory_owner(Vector2i(edge_col+step_dir,u.lane)) == u.team:
		edge_col += step_dir
	var bound_x: float = L.GRID_ORIGIN.x+(float(edge_col+1) if u.team == 0 else float(edge_col))*L.CELL_SIZE.x
	return clampf(bound_x,L.gate_stop(0),L.gate_stop(1))

# Called from update_unit after stun / fear. True = this troop's step is handled here.
static func update_unit(m, u: Dictionary, data: Dictionary, dt: float) -> bool:
	if u.get("root_left",0.0) > 0: u.root_left = maxf(0.0,u.root_left-dt)
	if not data.get("shuttle",false): return false
	# 騾馬貨車: out to our territory boundary, back to home gate, paid by distance (1, 3, 5, 7...), rest 3s.
	var rest_left: float = u.get("shuttle_rest",0.0)
	if rest_left > 0.0:
		u.shuttle_rest = maxf(0.0,rest_left-dt)
		u.face = 1.0 if u.team == 0 else -1.0
		return true
	var home: float = L.spawn_position(u.team,u.lane).x
	var out := 1.0 if u.team == 0 else -1.0
	var bound := shuttle_boundary_x(m,u)
	var going: bool = u.get("shuttle_out",true)
	var goal: float = bound if going else home
	u.face = out if going else -out
	if going and (u.pos.x-goal)*out >= -0.001:
		u.shuttle_turn_x = u.pos.x
		u.shuttle_out = false
		u.face = -out
		return true
	u.pos.x = move_toward(u.pos.x,goal,m.movement_speed(u)*dt)
	if going and (u.pos.x-goal)*out >= -0.001:
		u.shuttle_turn_x = u.pos.x
		u.shuttle_out = false
	elif not going and is_equal_approx(u.pos.x,home):
		var turn_x: float = u.get("shuttle_turn_x",home)
		var steps: int = int(floorf((absf(turn_x-home)+0.5)/L.CELL_SIZE.x))
		var payout: float = data.get("shuttle_base",1.0)+float(steps)*data.get("shuttle_step",2.0)
		m.gain_ink(u.team,payout)
		m.event("ink",u.pos,u.team)
		u.shuttle_turn_x = home
		u.shuttle_rest = data.get("shuttle_rest",3.0)
		u.shuttle_out = true
	return true

# Rooted troops cannot walk but still fight; sealed troops (封棺) also cannot attack.
static func speed_factor(u: Dictionary) -> float:
	return 0.0 if u.get("root_left",0.0) > 0 else 1.0

# Replaces the normal hit for lobbing, self-destructing and curse-splash troops. True = handled.
static func attack(m, u: Dictionary, target: Dictionary, data: Dictionary) -> bool:
	if data.get("suicide_blast",false):
		blast(m,u,target.pos,data)
		return true
	if data.get("lob",false):
		m.projectiles.append({"source":u,"pos":u.pos,"start":u.pos,"impact":target.pos,"flight":data.get("flight_time",0.8),"remaining":data.get("flight_time",0.8),"amount":data.area_damage,"radius":data.radius,"blast":data.get("blast",""),"team":u.team,"kind":u.get("card",u.kind)})
		m.event("catapult_fire",u.pos,u.team,{"target":target.pos})
		return true
	if data.has("dot_damage") and data.has("area_damage"):
		var direction: float = 1.0 if target.pos.x >= u.pos.x else -1.0
		var origin: Vector2 = u.pos+Vector2(0,u.get("dy",0.0))+Vector2(direction*16,-30)
		m.projectiles.append({"source":u,"direction":direction,"pos":origin,"start":origin,"target":target,"remaining":B.ARROW_TIME,"amount":data.area_damage,"radius":data.radius,"blast":data.get("blast",""),"dot_damage":data.dot_damage,"dot_interval":data.dot_interval,"dot_ticks":data.dot_ticks,"curse_splash":true,"team":u.team,"kind":u.get("card",u.kind)})
		m.event("arrow",u.pos,u.team)
		return true
	return false

static func add_hex(m, target: Dictionary, team: int, kind: String, dmg: float, interval: float, ticks: int) -> void:
	if target.hp <= 0 or not target.has("spawn_delay") or B.poison_immune(target): return
	var prev: int = int(target.get("hex_stacks",0))
	target.hex_stacks = prev+1
	target.hex_interval = interval
	target.hex_damage = maxf(float(target.get("hex_damage",0.0)),dmg) if prev > 0 else dmg
	target.hex_left = maxf(float(target.get("hex_left",0.0)),interval*float(ticks))
	if prev == 0: target.hex_timer = interval
	target.hex_team = team
	target.hex_kind = kind
	m.has_hex_unit = true

# Splash impact for curse projectiles; returns true if handled.
static func hit_projectile(m, arrow: Dictionary) -> bool:
	if not arrow.get("curse_splash",false): return false
	var target: Dictionary = arrow.get("target",{})
	var point: Vector2 = target.get("pos",arrow.pos)
	var src: Dictionary = arrow.get("source",{})
	for u: Dictionary in m.units:
		var curse_shape: String = String(arrow.get("blast",""))
		var in_curse: bool = B.blast_hits(point,curse_shape,1 if arrow.team == 0 else -1,u) if not curse_shape.is_empty() else B.point_edge_distance(point,u) <= arrow.radius
		if u.hp <= 0 or u.team == arrow.team or not in_curse: continue
		m.damage(u,arrow.amount,arrow.team,arrow.kind,src)
		if u.hp > 0: add_hex(m,u,arrow.team,arrow.kind,float(arrow.dot_damage),float(arrow.dot_interval),int(arrow.dot_ticks))
	if not target.is_empty():
		if target.get("kind","") == "gate": m.hit_gate(target.team,target.lane,arrow.amount,arrow.kind,src)
		elif (target.has("cell") or target.get("kind","") == "lord") and target.hp > 0: m.damage(target,arrow.amount,arrow.team,arrow.kind,src)
	m.event("witch_curse",point,arrow.team,{"radius":arrow.radius,"from":arrow.start})
	return true

# The same troops reaching a closed gate.
static func gate_attack(m, u: Dictionary, data: Dictionary, enemy: int) -> bool:
	if not data.get("suicide_blast",false): return false
	blast(m,u,Vector2(L.gate_stop(enemy),u.pos.y),data)
	return true

static func blast(m, u: Dictionary, point: Vector2, data: Dictionary) -> void:
	var dir := 1 if u.team == 0 else -1
	for t: Dictionary in m.units+m.buildings:
		if t.team != u.team and t.hp > 0 and B.blast_hits(point,String(data.get("blast","square")),dir,t): m.damage(t,data.area_damage,u.team,u.get("card",u.kind),u)
	for lane: int in m.active_lanes:
		if B.blast_hits_gate(point,String(data.get("blast","square")),dir,1-u.team,lane): m.hit_gate(1-u.team,lane,data.area_damage,u.get("card",u.kind),u)
	m.event("trap_blast",point,u.team,{"radius":data.radius})
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
	if d.has("structure_mult") and (target.has("cell") or target.get("kind","") == "gate"): amount *= d.structure_mult
	if u.get("crit_mult",1.0) > 1.0:
		amount *= u.crit_mult
		u.erase("crit_mult")
	return amount

static func gate_amount(m, u: Dictionary, amount: float) -> float:
	var d: Dictionary = B.CARDS[u.kind]
	if d.has("charge_damage") and not u.get("charged",false) and not u.get("expansion_charged",false):
		u.charged = true
		u.expansion_charged = true
		u.march_time = 0.0
		amount = d.charge_damage
		if m.record_events: m.event("charge_impact",Vector2(L.gate_stop(1-u.team),u.pos.y),u.team,{"radius":26.0,"face":u.face})
	elif u.get("granted_charge",false):
		u.granted_charge = false
		u.march_time = 0.0
		amount *= 2.0
		if m.record_events: m.event("charge_impact",Vector2(L.gate_stop(1-u.team),u.pos.y),u.team,{"radius":26.0,"face":u.face})
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
	if source.has("spawn_delay") and source.hp > 0:
		var ls: float = float(sd.get("lifesteal",0.0))+(0.25 if source.get("berserk_lifesteal_until",0.0) > m.elapsed else 0.0)
		if ls > 0.0: source.hp = minf(source.max_hp,source.hp+dealt*ls)
	if sd.has("dot_damage") and not sd.has("area_damage") and target.has("spawn_delay") and target.hp > 0:
		add_hex(m,target,source.team,source.kind,float(sd.dot_damage),float(sd.dot_interval),int(sd.dot_ticks))
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
			var foe: Dictionary = m.nearest(target.pos,target.team,td_hit.range,m.foe_units[target.team],-1,true,B.actor_radius(target))
			if not foe.is_empty():
				target.reflect_icd = m.elapsed+2.0
				m.damage(foe,td_hit.reflect_damage,target.team,target.kind)
				m.link(target.pos,foe.pos,target.team,"lightning")
	if target.has("cell") and target.kind == "mimic_egg": hatch_egg(m,target)
	if target.has("cell") and target.kind == "mana_battery" and target.hp <= 0: burst_battery(m,target)

static func _spawn_stitched(m, stitcher: Dictionary, center: Vector2, lane: int, d: Dictionary) -> void:
	var scount: int = maxi(1,int(d.get("stitch_count",1)))
	var forward := 1.0 if stitcher.team == 0 else -1.0
	for si: int in range(scount):
		var off := Vector2((si-0.5)*14.0*forward if scount > 1 else 0.0,(float(si % 2)-0.5)*10.0 if scount > 1 else 0.0)
		var pos := Vector2(clampf(center.x+off.x,L.gate_stop(0)+12.0,L.gate_stop(1)-12.0),center.y+off.y)
		var child: Dictionary = m.spawn_unit(stitcher.team,lane,d.ally_death_spawn,pos)
		child.card = stitcher.kind
		m.event("summoned",child.pos,child.team)
	m.link(stitcher.pos,center,stitcher.team,"summon")

# A troop died (death queue): carts pay their loot, stitchers sew skeletons, temporary bones vanish.
static func on_death(m, dead: Dictionary) -> void:
	var dd: Dictionary = B.CARDS.get(dead.kind,{})
	if dd.has("shuttle_loot"): m.gain_ink(1-dead.team,dd.shuttle_loot)
	for u: Dictionary in m.units:
		var d: Dictionary = B.CARDS.get(u.kind,{})
		if u.hp <= 0 or not d.has("ally_death_spawn") or B.edge_distance(u,dead) > d.radius: continue
		if not d.get("stitch_any_team",false) and u.team != dead.team: continue
		if u.get("stitch_ready",0.0) > m.elapsed or dead.kind == d.ally_death_spawn: continue
		u.stitch_ready = m.elapsed+d.stitch_cooldown
		if float(d.get("stitch_heal",0.0)) > 0.0:
			u.hp = minf(u.max_hp,u.hp+float(d.stitch_heal))
			m.event("heal",u.pos,u.team)
		_spawn_stitched(m,u,dead.pos,dead.lane,d)
	for u: Dictionary in m.units:
		var sd: Dictionary = B.CARDS.get(u.kind,{})
		if u.hp <= 0 or not sd.get("scavenger",false) or B.edge_distance(u,dead) > sd.radius: continue
		u.hp = minf(u.max_hp,u.hp+sd.scavenger_heal)
		var ti: int = B.TIERS.damage.find(u.get("damage",sd.damage))
		if ti > 0: u.damage = B.TIERS.damage[maxi(B.tier_index("A"),ti-1)]
		m.link(dead.pos,u.pos,u.team,"devour")

# Per tick: advance hex DoT ticks, then remove expired borrowed bones (no death effects).
static func update(m, dt: float) -> void:
	if m.has_hex_unit:
		for u: Dictionary in m.units:
			if u.hp <= 0 or int(u.get("hex_stacks",0)) <= 0 or u.get("hex_team",-1) < 0: continue
			var interval: float = u.get("hex_interval",1.0)
			u.hex_timer = u.get("hex_timer",interval)-dt
			while u.hex_timer <= 0.000001 and int(u.get("hex_stacks",0)) > 0:
				u.hex_timer += interval
				m.damage(u,u.get("hex_damage",20.0)*float(u.hex_stacks),u.hex_team,u.get("hex_kind","old_witch"))
				if u.hp <= 0: break
			if u.hp > 0:
				u.hex_left = float(u.get("hex_left",0.0))-dt
				if u.hex_left <= 0.000001:
					u.hex_stacks = 0
					u.hex_left = 0.0
					u.hex_team = -1
	if m.has_borrowed_unit:
		var borrowed_expired := false
		for u: Dictionary in m.units:
			if u.get("borrowed_until",-1.0) >= 0 and u.borrowed_until <= m.elapsed and u.hp > 0:
				borrowed_expired = true
				break
		if borrowed_expired:
			for u: Dictionary in m.units:
				if u.get("card","") != "borrowed_bones" or u.get("borrowed_until",-1.0) < 0 or u.borrowed_until > m.elapsed or u.hp <= 0: continue
				var bd: Dictionary = B.CARDS.borrowed_bones
				for foe: Dictionary in m.units+m.buildings:
					if foe.hp > 0 and foe.team != u.team and B.blast_hits(u.pos,String(bd.blast),1 if u.team == 0 else -1,foe): m.damage(foe,float(bd.return_blast),u.team,"borrowed_bones",u)
				m.event("boneburst",u.pos,u.team)
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
				if u.hp > 0 and u.team != actor.team and B.edge_distance(actor,u) <= d.radius and not u.get("flying",false):
					u.slow_left = maxf(u.get("slow_left",0.0),d.duration)
			m.event("drum",actor.pos,actor.team,{"duration":0.6})
			return true
		"cleanse":
			var pulsed := false
			var any_cleansed := false
			var haste_dur: float = float(d.get("duration",2.4))
			var heal_amt: float = float(d.get("support_amount",50.0))
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team == actor.team and u.get("spawn_delay",0.0) <= 0 and B.edge_distance(actor,u) <= d.radius:
					pulsed = true
					u.expansion_haste_until = maxf(u.get("expansion_haste_until",0.0),m.elapsed+haste_dur)
					var was_dirty: bool = u.get("stun_left",0.0) > 0 or u.get("slow_left",0.0) > 0 or u.get("fear_left",0.0) > 0 or u.get("root_left",0.0) > 0 or u.get("seal_left",0.0) > 0 or int(u.get("hex_stacks",0)) > 0 or int(u.get("poison_stacks",0)) > 0
					u.stun_left = 0.0
					u.slow_left = 0.0
					u.fear_left = 0.0
					u.root_left = 0.0
					u.seal_left = 0.0
					u.hex_stacks = 0
					u.hex_left = 0.0
					u.hex_team = -1
					u.poison_stacks = 0
					u.poison_left = 0.0
					u.poison_team = -1
					u.poison_zone_seen = -1.0
					if was_dirty:
						any_cleansed = true
						if heal_amt > 0.0 and u.hp < u.max_hp:
							u.hp = minf(u.max_hp,u.hp+heal_amt)
						if m.record_events: m.event("heal",u.pos,actor.team)
			if any_cleansed:
				for foe: Dictionary in m.units:
					if foe.hp > 0 and foe.team != actor.team and B.edge_distance(actor,foe) <= d.radius:
						foe.slow_left = maxf(foe.get("slow_left",0.0),1.5)
			if pulsed and m.record_events:
				m.event("support_pulse",actor.pos,actor.team,{"style":"cleanse","radius":d.radius})
			return true
	return false

# ---------------- spells ----------------

static func cast(m, s: Dictionary) -> bool:
	var d: Dictionary = m.spell_card_data(s.team,s.kind)
	var data_spell: bool = d.get("expansion_spell",false)
	if not s.kind in SPELLS and not data_spell: return false
	var rect: Rect2 = B.spell_rect(s.pos,d)
	m.event("spell",s.pos,s.team,{"card":s.kind,"radius":d.radius,"rect":rect})
	var lane: int = clampi(floori((s.pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,L.GRID_ROWS-1)
	if data_spell:
		cast_effects(m,s,d,lane,rect)
		return true
	match s.kind:
		"borrowed_bones":
			for i: int in range(d.summon_count):
				var u: Dictionary = m.spawn_unit(s.team,lane,"skeleton",Vector2(s.pos.x,L.cell_center(Vector2i(0,lane)).y))
				u.card = s.kind
				u.dy = (i-(d.summon_count-1)*0.5)*10.0
				u.spawn_delay = 0.08*i
				u.borrowed_until = m.elapsed+d.summon_life
				m.has_borrowed_unit = true
				m.event("summoned",u.pos,u.team)
		"grave_exchange":
			for b: Dictionary in m.buildings.duplicate():
				if b.hp <= 0 or b.team != s.team or not B.rect_hits_actor(rect,b) or B.is_home_card(b.kind,m.lords[s.team].lord): continue
				m.gain_ink(s.team,roundf(B.CARDS[b.kind].cost*d.refund))
				for i: int in range(d.skeletons):
					var u: Dictionary = m.spawn_unit(s.team,b.cell.y,"skeleton",b.pos)
					u.card = s.kind
					u.spawn_delay = 0.1*i
				m.damage(b,b.hp,s.team,s.kind,{},true)
		"mourning_shroud":
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team == s.team and B.rect_hits_actor(rect,u): u.shroud_until = m.elapsed+d.duration
		"sealed_coffin":
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team != s.team and B.rect_hits_actor(rect,u) and not u.get("flying",false):
					u.root_left = maxf(u.get("root_left",0.0),d.root)
					u.seal_left = maxf(u.get("seal_left",0.0),d.root)
	return true

static func shift_unit_lane(m, u: Dictionary, to_lane: int, team: int) -> void:
	var clamped: int = clampi(to_lane,0,L.GRID_ROWS-1)
	if clamped == u.lane: return
	var old_pos: Vector2 = u.pos
	u.lane = clamped
	u.pos.y = L.cell_center(Vector2i(0,clamped)).y
	m.knockback_unit(u,0.0)
	m.link(old_pos,u.pos,team,"harvest")

static func cast_effects(m, s: Dictionary, d: Dictionary, lane: int, rect: Rect2) -> void:
	var dir := 1.0 if s.team == 0 else -1.0
	if s.kind == "flaming_pitch":
		var pools: Array = m.get_meta("pitch_pools",[])
		pools.append({"pos":rect.get_center(),"team":s.team,"radius":d.radius,"rect":rect,"left":d.duration,"tick":0.0,"damage":d.tick_damage})
		m.set_meta("pitch_pools",pools)
		return
	if s.kind == "mirror_clone":
		var best: Dictionary = {}
		for u: Dictionary in m.units:
			if u.hp > 0 and u.team == s.team and u.get("spawn_delay",0.0) <= 0 and B.rect_hits_actor(rect,u) and (best.is_empty() or u.hp > best.hp):
				best = u
		if not best.is_empty():
			var clone: Dictionary = m.spawn_unit(s.team,best.lane,best.kind,best.pos+Vector2(-12*dir,10))
			clone.hp = best.hp
			clone.max_hp = best.max_hp
			clone.borrowed_until = m.elapsed+d.duration
			m.has_borrowed_unit = true
			m.event("summoned",clone.pos,s.team)
		return
	var hits := 0
	var execs := 0
	var killed_foes: Array = []
	var split_idx := 0
	# 吞噬巨口 (2026-11-19): only the maw_targets healthiest enemy ground troops in the area are bitten.
	var maw_ids := {}
	if d.has("maw_targets"):
		var prey: Array = m.units.filter(func(u: Dictionary) -> bool: return u.hp > 0 and u.team != s.team and not u.get("flying",false) and B.rect_hits_actor(rect,u))
		prey.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.hp > b.hp or (a.hp == b.hp and a.id < b.id))
		for u: Dictionary in prey.slice(0,int(d.maw_targets)): maw_ids[u.id] = true
	for u: Dictionary in m.units.duplicate():
		if u.hp <= 0 or not B.rect_hits_actor(rect,u): continue
		if u.team == s.team:
			if d.get("lane_split_gather",false) and abs(u.lane-lane) == 1:
				shift_unit_lane(m,u,lane,s.team)
			if d.has("phase_shift"):
				u.phased = true
				u.stealthed = true
				u.pos.x = clampf(u.pos.x+dir*d.phase_shift,L.gate_stop(0)+10.0,L.gate_stop(1)-10.0)
			if d.has("hp_cost_share") and u.hp > 1.0:
				u.hp = maxf(1.0,u.hp*(1.0-d.hp_cost_share))
				var di: int = B.TIERS.damage.find(u.get("damage",B.CARDS[u.kind].damage))
				if di > 0: u.damage = B.TIERS.damage[maxi(B.tier_index("S"),di-1)]
				u.expansion_haste_until = maxf(u.get("expansion_haste_until",0.0),m.elapsed+6.0)
				u.berserk_lifesteal_until = maxf(u.get("berserk_lifesteal_until",0.0),m.elapsed+6.0)
			if d.has("rally_haste_sec"):
				u.slow_left = 0.0
				u.root_left = 0.0
				u.expansion_haste_until = maxf(u.get("expansion_haste_until",0.0),m.elapsed+float(d.rally_haste_sec))
			if d.get("grant_charge",false):
				u.charged = false
				u.expansion_charged = false
				u.march_time = 0.0
				if u.kind != "ox" and not B.CARDS[u.kind].has("charge_damage"):
					u.granted_charge = true
					u.granted_charge_stun = float(d.get("charge_stun",0.5))
			if d.get("upgrade_hp",false):
				var hi: int = B.TIERS.hp.find(u.max_hp)
				if hi > 0:
					var nhp: float = B.TIERS.hp[maxi(B.tier_index("SS"),hi-1)]
					u.hp += nhp-u.max_hp
					u.max_hp = nhp
				else:
					u.hp = minf(u.max_hp,u.hp+350.0)
				var udi: int = B.TIERS.damage.find(u.get("damage",B.CARDS[u.kind].damage))
				if udi > 0: u.damage = B.TIERS.damage[maxi(B.tier_index("S"),udi-1)]
		else:
			if d.get("lane_split_gather",false) and u.lane == lane:
				var to_lane: int = lane+1 if lane == 0 else (lane-1 if lane == L.GRID_ROWS-1 else (lane-1 if u.pos.y < s.pos.y-1.0 else (lane+1 if u.pos.y > s.pos.y+1.0 else -1)))
				if to_lane < 0:
					to_lane = lane-1 if (split_idx % 2 == 0) else lane+1
					split_idx += 1
				shift_unit_lane(m,u,to_lane,s.team)
			if d.has("knockback"):
				m.knockback_unit(u,dir*d.knockback)
			if d.has("stun_on_hit") and not d.get("pull_center",false):
				var stun_dur: float = float(d.stun_on_hit)*(float(d.anti_air_mult) if (d.has("anti_air_mult") and u.get("flying",false)) else 1.0)
				u.stun_left = maxf(u.get("stun_left",0.0),stun_dur)
			if d.get("pull_center",false):
				u.pos = u.pos.lerp(s.pos,0.75)
				u.march_time = 0.0
				u.stun_left = maxf(u.get("stun_left",0.0),d.get("stun_on_hit",1.0))
			if d.get("strip_defences",false):
				u.shield = 0.0
				u.shield_until = 0.0
				u.armor = 0.0
				u.expansion_armor = 0.0
				u.armor_until = 0.0
				add_hex(m,u,s.team,s.kind,20.0,1.0,2)
			if d.has("maw_targets"):
				if maw_ids.has(u.id):
					m.damage(u,d.maw_damage,s.team,s.kind)
					hits += 1
				continue
			if d.has("execute_hp") and not u.get("flying",false) and u.hp <= d.execute_hp and execs < int(d.get("execute_max",3)):
				execs += 1
				m.damage(u,u.hp,s.team,s.kind,{},true)
				m.gain_ink(s.team,d.get("execute_gold",2.0))
				continue
			if d.has("enemy_damage"):
				var was_alive: bool = u.hp > 0
				var dmg: float = float(d.enemy_damage)*(float(d.anti_air_mult) if (d.has("anti_air_mult") and u.get("flying",false)) else 1.0)
				m.damage(u,dmg,s.team,s.kind)
				hits += 1
				if was_alive and u.hp <= 0: killed_foes.append({"lane":u.lane,"pos":u.pos})
	if d.get("strip_defences",false) and d.has("enemy_damage"):
		for b: Dictionary in m.buildings:
			if b.hp > 0 and b.team != s.team and B.rect_hits_actor(rect,b): m.damage(b,d.enemy_damage,s.team,s.kind)
	if d.has("drain_gold_per_hit") and hits > 0:
		m.gain_ink(s.team,minf(float(hits)*d.drain_gold_per_hit,d.get("drain_gold_max",5.0)))
	if d.has("spawn_on_kill"):
		for kf: Dictionary in killed_foes:
			var child: Dictionary = m.spawn_unit(s.team,kf.lane,d.spawn_on_kill,kf.pos)
			child.borrowed_until = m.elapsed+d.get("spawn_life",12.0)
			m.has_borrowed_unit = true
			m.event("summoned",child.pos,s.team)
	if d.has("ambush_spawn"): ambush(m,s.team,lane,String(d.ambush_spawn[0]),int(d.ambush_spawn[1]))

# 獸群突襲 (2026-11-19): beasts burst out at our front-most dry cell of the lane.
static func ambush(m, team: int, lane: int, kind: String, count: int) -> void:
	var cols: Array = range(L.GRID_COLUMNS-1,-1,-1) if team == 0 else range(L.GRID_COLUMNS)
	for col: int in cols:
		var cell := Vector2i(col,lane)
		if m.territory_owner(cell) != team or m.is_water_cell(cell): continue
		for i: int in range(count):
			var u: Dictionary = m.spawn_unit(team,lane,kind,L.cell_center(cell))
			u.card = "pack_ambush"
			u.dy = (i-(count-1)*0.5)*12.0
			m.event("summoned",u.pos,team)
		return

static func on_card_played(m, team: int, kind: String, lane: int) -> void:
	var card: Dictionary = B.CARDS[kind]
	if card.type == "unit":
		for b: Dictionary in m.buildings:
			if b.hp > 0 and b.team == team and b.kind == "supply_depot" and b.cell.y == lane:
				m.gain_ink(team,B.CARDS[b.kind].get("depot_refund",1.0))
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
	var dmg: float = float(b.get("area_damage",d.area_damage))
	m.gain_ink(b.team,float(charges)*d.gold_per_charge)
	m.event("ink",b.pos,b.team)
	for u: Dictionary in m.units:
		if u.hp > 0 and u.team != b.team and B.blast_hits(b.pos,String(d.get("blast","square")),1 if b.team == 0 else -1,u):
			m.damage(u,dmg,b.team,b.kind)

static func granary_store(m, farm_b: Dictionary) -> void:
	var d: Dictionary = B.CARDS.granary
	for b: Dictionary in m.buildings:
		if b.hp <= 0 or b.team != farm_b.team or b.kind != "granary": continue
		b.stored_gold = b.get("stored_gold",0.0)+d.store_per_farm
		if m.record_events: m.link(farm_b.pos,b.pos,farm_b.team,"harvest")
		if b.stored_gold >= d.store_max-0.000001:
			release_granary(m,b)

static func release_granary(m, b: Dictionary) -> void:
	var amount: float = b.get("stored_gold",0.0)
	if amount <= 0.0: return
	b.stored_gold = 0.0
	m.gain_ink(b.team,amount)
	m.event("ink",b.pos,b.team)

static func hatch_egg(m, b: Dictionary) -> void:
	if b.get("hatched",false): return
	b.hatched = true
	var d: Dictionary = B.CARDS.mimic_egg
	for i: int in range(d.spawn_count):
		var u: Dictionary = m.spawn_unit(b.team,b.cell.y,d.spawn_kind,b.pos+Vector2(0,(i-1)*10.0))
		u.card = b.kind
		m.event("summoned",u.pos,b.team)
	var dmg: float = float(b.get("area_damage",d.area_damage))
	for foe: Dictionary in m.units:
		if foe.hp > 0 and foe.team != b.team and B.blast_hits(b.pos,String(d.get("blast","square")),1 if b.team == 0 else -1,foe):
			m.damage(foe,dmg,b.team,b.kind)
	b.hp = 0
	m.refresh_territory()

static func tick_buildings_and_zones(m, dt: float) -> void:
	if m.has_meta("pitch_pools"):
		var pools: Array = m.get_meta("pitch_pools",[])
		if not pools.is_empty():
			var next_pools: Array = []
			for p: Dictionary in pools:
				p.left -= dt
				if p.left <= 0: continue
				p.tick -= dt
				if p.tick <= 0:
					p.tick += 1.0
					var prect: Rect2 = p.get("rect",Rect2())
					var use_rect := prect.size != Vector2.ZERO
					for u: Dictionary in m.units:
						if u.hp > 0 and u.team != p.team and not u.get("flying",false) and (B.rect_hits_actor(prect,u) if use_rect else B.point_edge_distance(p.pos,u) <= p.radius):
							if u.get("stealthed",false): u.stealthed = false
							m.damage(u,p.damage,p.team,"flaming_pitch")
					for b: Dictionary in m.buildings:
						if b.hp > 0 and b.team != p.team and (B.rect_hits_actor(prect,b) if use_rect else B.point_edge_distance(p.pos,b) <= p.radius):
							m.damage(b,p.damage,p.team,"flaming_pitch")
				next_pools.append(p)
			m.set_meta("pitch_pools",next_pools)
	if not m.has_expansion_building: return
	var Faction = preload("res://faction_cards.gd")
	var b_count: int = m.buildings.size()
	for idx: int in range(b_count):
		var b: Dictionary = m.buildings[idx]
		if b.hp <= 0 or not b.get("is_expansion",false): continue
		var d: Dictionary = B.CARDS.get(b.kind,{})
		var b_dt: float = dt * Faction.building_factor(m,b)
		if b.kind == "mimic_egg":
			b.egg_clock = b.get("egg_clock",0.0)+b_dt
			var sprung: bool = d.get("ambush_hatch",false) and m.units.any(func(u: Dictionary) -> bool: return u.hp > 0 and u.team != b.team and u.get("spawn_delay",0.0) <= 0 and not B.CARDS[u.kind].get("flying",false) and B.blast_hits(b.pos,String(d.blast),1 if b.team == 0 else -1,u))
			if sprung or b.egg_clock >= d.hatch_time: hatch_egg(m,b)
		elif b.kind == "warp_beacon":
			b.warp_clock = minf(float(d.period),float(b.get("warp_clock",d.period))+b_dt)
			if b.warp_clock >= float(d.period):
				var pdmg: float = float(b.get("area_damage",d.get("area_damage",0.0)))
				var pstun: float = float(d.get("pulse_stun",0.0))
				var targets: Array = []
				for u: Dictionary in m.units:
					if u.hp > 0 and u.team != b.team and u.get("spawn_delay",0.0) <= 0 and u.lane == b.cell.y:
						var dist: float = maxf(0.0,absf(u.pos.x-b.pos.x)-B.actor_radius(b)-B.actor_radius(u))
						if dist <= d.range: targets.append(u)
				if not targets.is_empty():
					b.warp_clock = 0.0
					for u: Dictionary in targets:
						var back: float = 1.0 if u.team == 0 else -1.0
						m.knockback_unit(u,-back*float(d.pushback))
						if pstun > 0.0: u.stun_left = maxf(u.get("stun_left",0.0),pstun)
						if pdmg > 0.0: m.damage(u,pdmg,b.team,b.kind)
						m.link(b.pos,u.pos,b.team,"mana")
					if m.record_events: m.event("support_pulse",b.pos,b.team,{"style":"range","radius":float(d.range)})
		elif b.kind == "blood_cauldron":
			b.cauldron_clock = b.get("cauldron_clock",0.0)+b_dt
			if b.cauldron_clock >= d.period:
				b.cauldron_clock -= d.period
				for u: Dictionary in m.units:
					if u.hp > 0 and u.team == b.team and B.edge_distance(b,u) <= d.radius:
						u.hp = minf(u.max_hp,u.hp+float(d.get("support_amount",36.0)))
						u.crit_mult = d.crit_mult
						m.link(b.pos,u.pos,b.team,"devour")
		elif d.get("support","") == "tithe":
			var drain: float = float(d.tithe_dps)*b_dt
			var drained := 0.0
			var fx_clock: float = b.get("tithe_fx_clock",0.55)+b_dt
			var pulse_fx := fx_clock >= 0.6
			if pulse_fx: fx_clock -= 0.6
			for u: Dictionary in m.units:
				if u.hp <= 1.0 or u.team != b.team or u.get("spawn_delay",0.0) > 0 or B.edge_distance(b,u) > d.radius: continue
				var prev_hp: float = u.hp
				u.hp = maxf(1.0,u.hp-drain)
				var took: float = prev_hp-u.hp
				if took > 0.0:
					drained += took
					if pulse_fx and m.record_events: m.link(u.pos,b.pos,b.team,"devour")
			b.tithe_fx_clock = fx_clock if drained > 0.0 else 0.55
			if drained > 0.0:
				var blood: float = b.get("tithe_blood",0.0)+drained
				var goal: float = float(d.tithe_goal)
				var paid := false
				while blood >= goal-0.000001:
					blood -= goal
					m.gain_ink(b.team,float(d.tithe_gold))
					m.event("ink",b.pos,b.team)
					paid = true
				if paid and float(d.get("tithe_buff_sec",0.0)) > 0.0:
					var buff_until: float = m.elapsed+float(d.tithe_buff_sec)
					for au: Dictionary in m.units:
						if au.hp > 0 and au.team == b.team and au.get("spawn_delay",0.0) <= 0 and B.edge_distance(b,au) <= d.radius:
							au.expansion_haste_until = maxf(au.get("expansion_haste_until",0.0),buff_until)
							au.berserk_lifesteal_until = maxf(au.get("berserk_lifesteal_until",0.0),buff_until)
							m.link(b.pos,au.pos,b.team,"heal")
					m.event("drum",b.pos,b.team,{"duration":0.6})
				b.tithe_blood = maxf(0.0,blood)
		elif d.get("well_heal_full",false):
			var served: Dictionary = b.get("well_served",{})
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team == b.team and u.get("spawn_delay",0.0) <= 0 and not served.has(u.id) and B.edge_distance(b,u) <= d.radius:
					served[u.id] = true
					u.hp = u.max_hp
					u.expansion_haste_until = maxf(u.get("expansion_haste_until",0.0),m.elapsed+d.duration)
					m.event("heal",u.pos,u.team)
					m.link(b.pos,u.pos,b.team,"heal")
			b.well_served = served
		elif d.has("damage") and d.has("range") and d.has("interval"):
			b.cd = b.get("cd",0.0)-b_dt
			if b.cd <= 0:
				if d.get("lane_shooter",false):
					fire_lane_shooter(m,b,d)
				else:
					var target: Dictionary = preload("res://grid_rules.gd").pick(m,b,m.foe_units[b.team]) # reach in cells; troops first
					if not target.is_empty():
						var dmg: float = float(b.get("damage",d.damage))
						b.cd = float(b.get("interval",d.interval))
						m.shoot(b,target,dmg)
						if d.get("lifesteal",0.0) > 0: b.hp = minf(b.max_hp,b.hp+dmg*d.lifesteal)

static func fire_lane_shooter(m, b: Dictionary, d: Dictionary) -> void:
	var forward := 1.0 if b.team == 0 else -1.0
	var b_rad := B.actor_radius(b)
	# Reach in cells (重弩塔: its lane, "reach" cells ahead): a troop there, or else an
	# enemy building there, makes it fire. The bolt still stops on whatever it meets first.
	var GridRules = preload("res://grid_rules.gd")
	if GridRules.pick(m,b,m.lane_foes[b.team][b.cell.y]).is_empty(): return
	b.cd = float(b.get("interval",d.interval))
	var origin: Vector2 = b.pos+Vector2(forward*(b_rad+4.0),-30.0)
	m.projectiles.append({
		"source":b,
		"lane_bolt":true,
		"lane":b.cell.y,
		"direction":forward,
		"pos":origin,
		"start":origin,
		"origin":b.pos,
		"speed":float(d.get("bolt_speed",540.0)),
		"max_dist":(GridRules.lane_length(b.kind)+0.5)*L.CELL_SIZE.x,
		"travelled":0.0,
		"remaining":1.0,
		"amount":float(b.get("damage",d.damage)),
		"team":b.team,
		"kind":b.kind
	})
	m.event("arrow",b.pos,b.team)

static func advance_lane_bolt(m, bolt: Dictionary, dt: float) -> void:
	var step: float = float(bolt.speed)*dt
	var prev_x: float = bolt.pos.x
	var dir: float = bolt.direction
	var next_x: float = prev_x+dir*step
	bolt.pos.x = next_x
	bolt.travelled = float(bolt.get("travelled",0.0))+step
	var best_d := INF
	var best_kind := ""
	var best_target: Dictionary = {}
	for u: Dictionary in m.lane_foes[bolt.team][bolt.lane]:
		if u.hp <= 0 or u.get("spawn_delay",0.0) > 0 or u.get("stealthed",false) or u.get("phased",false): continue
		var r := B.actor_radius(u)
		if (u.pos.x-prev_x)*dir+r >= -4.0 and (u.pos.x-next_x)*dir-r <= 0.0:
			var d: float = (u.pos.x-bolt.origin.x)*dir
			if d < best_d:
				best_d = d
				best_kind = "actor"
				best_target = u
	for fb: Dictionary in m.lane_foe_buildings[bolt.team][bolt.lane]:
		if fb.hp <= 0: continue
		var rb := B.actor_radius(fb)
		if (fb.pos.x-prev_x)*dir+rb >= 0.0 and (fb.pos.x-next_x)*dir-rb <= 0.0:
			var d: float = (fb.pos.x-bolt.origin.x)*dir
			if d < best_d:
				best_d = d
				best_kind = "actor"
				best_target = fb
	var enemy: int = 1-int(bolt.team)
	if m.gates[enemy][bolt.lane] > 0:
		var gx := L.gate_stop(enemy)
		if (gx-prev_x)*dir >= 0.0 and (gx-next_x)*dir <= 0.0:
			var d: float = (gx-bolt.origin.x)*dir
			if d < best_d:
				best_d = d
				best_kind = "gate"
	if best_kind == "gate":
		m.hit_gate(enemy,bolt.lane,bolt.amount,bolt.kind,bolt.get("source",{}))
		bolt.remaining = 0.0
	elif best_kind == "actor":
		m.damage(best_target,bolt.amount,bolt.team,bolt.kind,bolt.get("source",{}))
		bolt.remaining = 0.0
	elif bolt.travelled >= bolt.max_dist:
		bolt.remaining = 0.0

static func play_error(m, team: int, kind: String, pos: Vector2) -> String:
	if kind == "grave_exchange":
		var lord: String = m.lords[team].lord
		if not m.buildings.any(func(b: Dictionary) -> bool: return b.hp > 0 and b.team == team and B.spell_hits_actor(pos,B.CARDS.grave_exchange,b) and not B.is_home_card(b.kind,lord)): return "no building"
	return ""

# ---------------- AI ----------------

static func ai_score(c: Dictionary, s: Dictionary, covered: Dictionary = {}) -> float:
	var data: Dictionary = B.CARDS[c.kind]
	if not data.get("expansion_spell",false) and not c.kind in SPELLS: return -INF
	var team: int = s.team
	var rect: Rect2 = B.spell_rect(c.pos,data)
	match c.kind:
		"borrowed_bones", "sealed_coffin":
			var foes := 0
			for u: Dictionary in s.units:
				if u.hp <= 0 or u.team == team or covered.has(u.get("id",-1)) or not B.rect_hits_actor(rect,u): continue
				if c.kind == "sealed_coffin" and (u.get("flying",false) or u.get("seal_left",0.0) > 1.0 or u.get("root_left",0.0) > 1.0): continue
				foes += 1
			if foes >= 2: return 700.0+foes*10
		"mourning_shroud":
			var allies := 0
			var fighting := false
			for u: Dictionary in s.units:
				if u.hp <= 0 or not B.rect_hits_actor(rect,u): continue
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
				if b.hp <= 0 or b.team != team or not B.rect_hits_actor(rect,b) or B.is_home_card(b.kind,lord): continue
				# Do not destroy a healthy neighbour just to recycle one damaged building.
				if b.hp > b.max_hp*0.4: return -INF
				value += roundf(B.CARDS[b.kind].cost*data.refund)+data.skeletons*B.CARDS.skeleton.cost
			if value > data.cost and s.ink < B.MAX_INK-data.cost: return 650.0+value*4
	if data.get("expansion_spell",false):
		var allies := 0
		var foes := 0
		var exec_foes := 0
		var foe_hp: Array = []
		var best_ally_hp := 0.0
		for u: Dictionary in s.units:
			if u.hp <= 0 or u.get("spawn_delay",0.0) > 0 or not B.rect_hits_actor(rect,u): continue
			if u.team == team:
				allies += 1
				if u.hp > best_ally_hp: best_ally_hp = u.hp
			elif not covered.has(u.get("id",-1)):
				foes += 1
				if data.has("execute_hp") and not u.get("flying",false) and u.hp <= data.execute_hp: exec_foes += 1
				if data.has("maw_targets") and not u.get("flying",false): foe_hp.append(minf(u.hp,float(data.maw_damage)))
		if c.kind == "mirror_clone":
			if best_ally_hp >= 350.0: return 685.0+minf(best_ally_hp,1500.0)*0.04
			return -INF
		if c.kind == "counter_charge":
			if (foes >= 1 and allies >= 1) or foes >= 2: return 695.0+float(foes)*16.0+float(allies)*14.0
			return -INF
		if c.kind == "wing_gust":
			if foes >= 2 or (foes >= 1 and allies >= 2): return 695.0+float(foes)*18.0+float(allies)*10.0
			return -INF
		if c.kind in ["berserk_blood","phase_shift","pack_ambush","feral_mutation"]:
			if allies >= 2: return 680.0+allies*15.0
			return -INF
		if c.kind == "devouring_maw":
			# Worth it when the bites land on real bodies: the damage actually dealt by the top bites.
			foe_hp.sort()
			foe_hp.reverse()
			var bitten := 0.0
			for hp: float in foe_hp.slice(0,int(data.maw_targets)): bitten += hp
			if bitten >= 600.0: return 695.0+bitten*0.02
			return -INF
		if foes >= 2: return 685.0+foes*16.0
	return -INF

# Support/economy cards must not fall through to the generic sacrificial building score.
static func conditional_building(data: Dictionary) -> bool:
	return data.type == "building" and data.get("expansion",false) and (data.has("support") or data.has("death_income") or data.has("well_heal_full") or data.has("income") or data.has("store_per_farm") or data.has("spawn_kind") or data.has("gold_per_charge") or data.has("crit_mult") or data.has("pushback") or data.has("damage") or data.has("thorns") or data.has("reflect_damage"))

static func placement_score(c: Dictionary, s: Dictionary, pr: Dictionary, covered: Dictionary = {}) -> float:
	var d: Dictionary = B.CARDS[c.kind]
	var is_cond_b: bool = conditional_building(d)
	var is_supp_u: bool = d.type == "unit" and (d.has("support") or d.has("reveal_radius") or d.has("dot_damage"))
	if not is_cond_b and not is_supp_u and c.kind != "orrery_walker": return -INF
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
			if covered.has(u.get("id",-1)): continue
			if distance <= radius: foes += 1
			if distance < 100 and u.lane == c.cell.y: danger += u.hp
			continue
		if distance > radius: continue
		if d.get("support","") == "range" and not B.CARDS.get(u.kind,{}).get("projectile",false): continue
		if d.get("support","") == "tithe" and u.hp <= float(d.tithe_dps)*2.0: continue
		if d.get("support","") == "heal" and u.hp >= u.max_hp: continue
		allies += 1
	if is_cond_b:
		for b: Dictionary in s.buildings:
			if b.hp <= 0 or b.team != s.team: continue
			if b.kind == c.kind and ((b.cell.y == c.cell.y) if d.get("lane_shooter",false) else (b.pos.distance_to(c.pos) < radius*1.5)): duplicates += 1
			if d.get("support","") == "repair" and b.pos.distance_to(c.pos) <= radius and b.hp < b.max_hp: allies += 1
	if is_cond_b:
		if duplicates >= int(pr.get("support_density",1.0)): return -INF
		if d.get("lane_shooter",false):
			var lane_range: float = float(d.get("range",620.0))
			var lane_foes := 0
			for u: Dictionary in s.units:
				if u.hp <= 0 or u.team == s.team or covered.has(u.get("id",-1)) or u.lane != c.cell.y: continue
				if (u.pos.x-c.pos.x)*forward >= 0.0 and absf(u.pos.x-c.pos.x) <= lane_range: lane_foes += 1
			if lane_foes <= 0: return -INF
			return pr.get("support_score",660.0)+minf(float(lane_foes)+1.0,5.0)*18.0-duplicates*80.0
		if d.has("thorns") or d.has("damage") or d.has("pushback") or d.has("reflect_damage"):
			if foes <= 0 and danger <= 0: return -INF
			return pr.get("support_score",660.0)+minf(foes+1.0,5.0)*18.0-duplicates*80.0
		if danger > 0: return -INF
		var value := allies
		if d.has("death_income"): value = minf(allies,foes) if d.get("death_side","") == "ally" else (allies+foes)
		if d.get("support","") == "slow": value = foes
		if d.has("store_per_farm"):
			var farm_n := 0
			for b: Dictionary in s.buildings:
				if b.hp > 0 and b.team == s.team and b.kind == "farm": farm_n += 1
			value = float(farm_n)
		elif d.has("income") or d.has("spawn_kind") or d.has("gold_per_charge") or c.kind == "supply_depot": value = 2.0
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
			if u.hp > 0 and u.team != s.team and not covered.has(u.get("id",-1)) and u.lane == c.cell.y and (u.pos.x-c.pos.x)*forward >= 0 and absf(u.pos.x-c.pos.x) <= d.range*d.pierce_range_multiplier: line += 1
		if line >= 2: return 700.0+line*15-danger*0.1
	return -INF
