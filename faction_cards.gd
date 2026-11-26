extends RefCounted
# Cards from the retired design note 三陣營各補四張 (2026-11-05; git history): four new cards for each faction.
# Battle hooks: spell casts (cast), extra play limits (play_error), damage (absorb),
# speed / interval multipliers, per-step update and deaths. Drawing lives in draw().
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Arcane = preload("res://arcane_mechanics.gd")
const GluttonNest = preload("res://glutton_nest.gd")
const Giant = preload("res://giant_unit.gd")

const SPELLS := ["mana_spring","chain_lightning","arcane_shield","time_field","charge_horn","levy","sacrifice","dread_howl"]
const DEFENSIVE := ["chain_lightning","time_field","levy","dread_howl"] # worth more in the lane the AI is defending

# ---------- casting ----------

# True when this module handled the spell.
static func cast(m, s: Dictionary) -> bool:
	if not s.kind in SPELLS: return false
	var data: Dictionary = m.spell_card_data(s.team,s.kind)
	var rect: Rect2 = B.spell_rect(s.pos,data)
	m.event("spell",s.pos,s.team,{"card":s.kind,"radius":data.get("radius",0.0),"rect":rect})
	match s.kind:
		"mana_spring":
			for b: Dictionary in crystals_in(m,s.team,s.pos,data):
				m.gain_ink(s.team,B.CARDS.crystal.income)
				b.hp = minf(b.max_hp,b.hp+b.max_hp*data.heal_fraction)
				m.event("ink",b.pos,s.team)
				m.link(s.pos,b.pos,s.team,"mana")
		"chain_lightning": chain(m,s,data,rect)
		"arcane_shield":
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team == s.team and B.rect_hits_actor(rect,u):
					# Stacks onto existing active shield; endless when duration is absent/<= 0.
					var left: float = u.get("shield",0.0) if shield_active(m,u) else 0.0
					var endless: bool = float(data.get("duration",-1.0)) <= 0.0
					u.shield = left+data.shield
					if endless or u.get("shield_until",0.0) < 0.0:
						u.shield_until = -1.0
					else:
						u.shield_until = m.elapsed+float(data.duration)
		"time_field":
			m.fields.append({"pos":rect.get_center(),"team":s.team,"radius":data.radius,"rect":rect,"left":data.duration,"duration":data.duration})
		"charge_horn":
			m.horns.append({"team":s.team,"lane":lane_of(s.pos),"until":m.elapsed+data.duration})
		"levy":
			var forward := 1.0 if s.team == 0 else -1.0
			for foe: Dictionary in intruders(m,s.team):
				# One militia per intruder, inside our territory on a lane the foe occupies.
				var spawn_lane: int = int(foe.lane)
				var fallback_x: float = foe.pos.x
				if Giant.is_giant(foe):
					for gc: Vector2i in Giant.cells(foe):
						if m.territory_owner(gc) == s.team:
							spawn_lane = gc.y
							fallback_x = L.cell_center(gc).x
							break
				var x := clampf(foe.pos.x-45.0*forward,L.GRID_ORIGIN.x+8.0,L.GRID_ORIGIN.x+L.GRID_SIZE.x-8.0)
				var y := L.cell_center(Vector2i(0,spawn_lane)).y
				if m.territory_owner(m.cell_at(Vector2(x,y))) != s.team:
					x = clampf(fallback_x,L.GRID_ORIGIN.x+8.0,L.GRID_ORIGIN.x+L.GRID_SIZE.x-8.0)
				var u: Dictionary = m.spawn_unit(s.team,spawn_lane,"militia",Vector2(x,y))
				u.card = "levy"
				u.levy = true
				m.has_levy = true
				m.event("summoned",u.pos,u.team)
		"sacrifice":
			var victims: Array = m.units.filter(func(u: Dictionary) -> bool: return u.hp > 0 and u.team == s.team and u.get("spawn_delay",0.0) <= 0 and B.rect_hits_actor(rect,u))
			var cap: float = float(data.get("bite_cap",500.0))
			var health := 0.0
			for u: Dictionary in victims:
				var dealt: float = cap if u.hp > cap else u.hp
				health += dealt
				m.link(u.pos,s.pos,s.team,"devour")
				m.damage(u,dealt,s.team,"sacrifice",{},true)
			var gold: int = GluttonNest.gold_for_health(health,data)
			if gold > 0:
				m.gain_ink(s.team,gold)
				m.event("ink",s.pos,s.team)
			m.add_skill_charge(s.team,health*float(data.get("charge_per_hp",0.0))) # 2026-11-19: blood feeds the lord's skill
			if health > 0.0 and data.has("blast_share"):
				var blast_dmg: float = clampf(health*float(data.blast_share),float(data.get("blast_min",90.0)),float(data.get("blast_max",600.0)))
				var slow_sec: float = float(data.get("slow_duration",2.0))
				for foe: Dictionary in m.units.duplicate():
					if foe.hp <= 0 or foe.team == s.team or not B.rect_hits_actor(rect,foe): continue
					m.damage(foe,blast_dmg,s.team,s.kind)
					if foe.hp > 0 and slow_sec > 0.0: foe.slow_left = maxf(foe.get("slow_left",0.0),slow_sec)
				m.event("boneburst",s.pos,s.team)
		"dread_howl":
			var enemy_dmg: float = float(data.get("enemy_damage",0.0))
			var dur: float = float(data.duration)
			var tmult: float = float(data.get("terror_mult",1.0))
			for u: Dictionary in m.units.duplicate():
				if u.hp <= 0 or not B.rect_hits_actor(rect,u): continue
				if u.team != s.team:
					if not u.get("cursed",false):
						u.cursed_until = maxf(u.get("cursed_until",0.0),m.elapsed+dur)
						u.curse_team = s.team
					if enemy_dmg > 0.0: m.damage(u,enemy_dmg,s.team,s.kind)
					if u.hp > 0:
						u.fear_left = maxf(u.get("fear_left",0.0),dur)
						u.slow_left = maxf(u.get("slow_left",0.0),dur)
						u.terror_until = maxf(u.get("terror_until",0.0),m.elapsed+dur) # 破膽: takes more damage while it flees
						u.terror_mult = maxf(float(u.get("terror_mult",1.0)),tmult)
				else: u.expansion_haste_until = maxf(u.get("expansion_haste_until",0.0),m.elapsed+4.0)
	return true

static func lane_of(pos: Vector2) -> int:
	return clampi(floori((pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,L.GRID_ROWS-1)

# Enemy ground troops standing on our territory.
static func intruders(m, team: int) -> Array:
	return m.units.filter(func(u: Dictionary) -> bool:
		if u.hp <= 0 or u.team == team or u.get("flying",false) or u.get("spawn_delay",0.0) > 0: return false
		if Giant.is_giant(u): return Giant.cells(u).any(func(c: Vector2i) -> bool: return m.territory_owner(c) == team)
		return m.territory_owner(m.cell_at(u.pos)) == team)

static func crystals_in(m, team: int, pos: Vector2, data: Dictionary) -> Array:
	var rect: Rect2 = B.spell_rect(pos,data)
	return m.buildings.filter(func(b: Dictionary) -> bool: return b.hp > 0 and b.team == team and b.kind == "crystal" and B.rect_hits_actor(rect,b))

# Hits the enemy in the cast grid box nearest its center, then hops to nearest enemies within hop_radius.
static func chain(m, s: Dictionary, data: Dictionary, rect: Rect2 = Rect2()) -> void:
	var pool: Array = []
	for u: Dictionary in m.units:
		if u.hp > 0 and u.team != s.team and u.get("spawn_delay",0.0) <= 0: pool.append(u)
	for b: Dictionary in m.buildings:
		if b.hp > 0 and b.team != s.team and not B.CARDS[b.kind].has("trap") and not GluttonNest.hidden(b): pool.append(b)
	var use_rect: Rect2 = rect if rect.size != Vector2.ZERO else B.spell_rect(s.pos,data)
	var at: Vector2 = s.pos
	var reach: float = data.radius
	var tier: int = B.TIERS.damage.find(data.bolt_damage)
	var base_tier: int = B.TIERS.damage.find(float(B.CARDS[s.kind].bolt_damage))
	var hop_mult: float = float(data.bolt_damage)/maxf(1.0,float(B.CARDS[s.kind].bolt_damage))
	var hit: Array = []
	for i: int in range(data.hops+1):
		var best: Dictionary = {}
		var best_d := INF
		for t: Dictionary in pool:
			if t in hit or t.hp <= 0: continue
			if i == 0 and not B.rect_hits_actor(use_rect,t): continue
			var d: float = B.point_edge_distance(at,t)
			if (i == 0 or d <= reach) and d < best_d:
				best = t
				best_d = d
		if best.is_empty(): break
		hit.append(best)
		if best.has("twin_id"):
			var twin_b: Dictionary = preload("res://large_body.gd").twin(m,best)
			if not twin_b.is_empty(): hit.append(twin_b)
		m.link(at,best.pos,s.team,"lightning")
		var dmg: float = float(B.TIERS.damage[mini(tier+i,B.TIERS.damage.size()-1)]) if tier >= 0 else (roundf(float(B.TIERS.damage[mini(base_tier+i,B.TIERS.damage.size()-1)])*hop_mult) if base_tier >= 0 else roundf(float(data.bolt_damage)*pow(0.65,i)))
		m.damage(best,dmg,s.team,s.kind)
		at = best.pos
		reach = data.hop_radius

# Extra placement limits ("" = fine). Called from play_check for these spells.
static func play_error(m, team: int, kind: String, pos: Vector2) -> String:
	if kind == "mana_spring" and crystals_in(m,team,pos,B.CARDS.mana_spring).is_empty(): return "no crystal"
	if kind == "levy" and (intruders(m,team).is_empty() or m.territory_owner(m.cell_at(pos)) != team): return "no intruders"
	if kind == "sacrifice" and not m.units.any(func(u: Dictionary) -> bool: return u.hp > 0 and u.team == team and B.spell_hits_actor(pos,B.CARDS.sacrifice,u)): return "no troops"
	return ""

# ---------- ongoing effects ----------

static func update(m, dt: float) -> void:
	if not m.fields.is_empty():
		var field_expired := false
		for f: Dictionary in m.fields:
			f.left -= dt
			if f.left <= 0.000001: field_expired = true
		if field_expired:
			m.fields = m.fields.filter(func(f: Dictionary) -> bool: return f.left > 0.000001)
	if not m.horns.is_empty():
		var horn_expired := false
		for h: Dictionary in m.horns:
			if h.until <= m.elapsed:
				horn_expired = true
				break
		if horn_expired:
			m.horns = m.horns.filter(func(h: Dictionary) -> bool: return h.until > m.elapsed)
	if m.has_levy:
		var levy_left := false
		for u: Dictionary in m.units:
			if u.get("levy",false) and u.hp > 0 and m.territory_owner(m.cell_at(u.pos)) != u.team:
				levy_left = true
				break
		if levy_left:
			m.units = m.units.filter(func(u: Dictionary) -> bool:
				if u.get("levy",false) and u.hp > 0 and m.territory_owner(m.cell_at(u.pos)) != u.team:
					u.hp = 0.0
					if u.has("serial"):
						m.serials_in_use.erase(u.serial)
						u.serial = 0
					return false
				return true)
			m.build_lookups()
	if m.has_watchtower[0] or m.has_watchtower[1]:
		for b: Dictionary in m.buildings:
			if b.hp <= 0 or b.kind != "watchtower": continue
			for u: Dictionary in m.units:
				if u.team != b.team and u.get("stealthed",false) and B.edge_distance(b,u) <= B.CARDS.watchtower.radius:
					Arcane.reveal(m, u)

static func horn_active(m, u: Dictionary) -> bool:
	return horn_count(m,u) > 0

static func horn_count(m, u: Dictionary) -> int:
	var n := 0
	for h: Dictionary in m.horns:
		if h.team == u.team and Giant.occupies_lane(u,h.lane): n += 1
	return n

# A troop that shoots, or a tower, inside our watchtower's reach: one range tier further.
static func watched(m, actor: Dictionary) -> bool:
	if not m.has_watchtower[actor.team]: return false
	for b: Dictionary in m.buildings:
		if b.hp > 0 and b.kind == "watchtower" and b.team == actor.team and B.edge_distance(b,actor) <= B.CARDS.watchtower.radius: return true
	return false

static func longer(r: float) -> float:
	var i: int = B.TIERS.range.find(r)
	if i > 0: return B.TIERS.range[i-1]
	if i == 0: return r
	return minf(B.TIERS.range[0],roundf(r*1.25))

static func unit_data(m, u: Dictionary, data: Dictionary) -> Dictionary:
	if not B.is_ranged_unit(data) or not watched(m,u): return data
	var d := data.duplicate()
	d.range = longer(data.range)
	return d

static func tower_range(m, b: Dictionary) -> float:
	return longer(B.CARDS.tower.range) if watched(m,b) else B.CARDS.tower.range

# Fear: the troop turns and walks home without attacking. True = it used its step.
static func flee(m, u: Dictionary, dt: float) -> bool:
	if u.get("fear_left",0.0) <= 0: return false
	u.fear_left = maxf(0.0,u.fear_left-dt)
	var home := L.gate_stop(u.team)
	var dir := signf(home-u.pos.x)
	u.face = dir if dir != 0.0 else (-1.0 if u.team == 0 else 1.0)
	u.pos.x = move_toward(u.pos.x,home,m.movement_speed(u)*0.85*dt)
	if u.fear_left <= 0: u.face = 1.0 if u.team == 0 else -1.0 # fear over: turn back toward the enemy
	return true

# A hit landed (after damage). Nets slow the target.
static func on_hit(m, target: Dictionary, source: Dictionary) -> void:
	var net_slow: float = B.CARDS.get(source.get("kind",""),{}).get("net_slow",0.0)
	if net_slow > 0 and target.has("lane") and not target.get("flying",false) and target.hp > 0:
		target.slow_left = maxf(target.get("slow_left",0.0),net_slow)

# Buildings with their own clock. True = handled.
static func update_building(m, b: Dictionary, dt: float) -> bool:
	if b.kind == "blood_tower":
		var d: Dictionary = B.CARDS.blood_tower
		b.blood_fx_cd = maxf(0.0,b.get("blood_fx_cd",0.0)-dt)
		b.blood_glow = maxf(0.0,b.get("blood_glow",0.0)-dt)
		b.blood = minf(d.blood_max,b.get("blood",0.0)+d.blood_rate*dt)
		if not b.get("bleeding",false) and b.blood > d.restart_at: b.bleeding = true
		if not b.get("bleeding",false): return true
		var hurt: Array = m.units.filter(func(u: Dictionary) -> bool: return u.hp > 0 and u.team == b.team and Giant.occupies_lane(u,b.cell.y) and u.get("spawn_delay",0.0) <= 0 and u.hp < u.max_hp)
		if hurt.is_empty(): return true
		var out := minf(b.blood,d.heal_rate*dt)
		b.blood -= out
		var each := out/hurt.size()
		for u: Dictionary in hurt: u.hp = minf(u.max_hp,u.hp+each)
		b.blood_glow = 0.45
		# At most four visual links every 0.35 s; no extra target search or RNG.
		if m.record_events and b.blood_fx_cd <= 0:
			for i: int in range(mini(4,hurt.size())):
				m.event("blood_transfer",b.pos+Vector2(0,-15),b.team,{"to":hurt[i].pos+Vector2(0,-12)})
			b.blood_fx_cd = 0.35
		if b.blood <= 0.000001:
			b.blood = 0.0
			b.bleeding = false
		return true
	return false

static func grave_spawn(m, b: Dictionary) -> void:
	for i: int in range(B.CARDS.mass_grave.spawn_count):
		var u: Dictionary = m.spawn_unit(b.team,b.cell.y,"skeleton",b.pos)
		u.card = "mass_grave"
		u.spawn_delay = i*0.12
	m.event("summoned",b.pos,b.team)

# Any non-skeleton troop dying feeds mass graves globally; blood towers devour in-lane deaths.
static func on_death(m, dead: Dictionary) -> void:
	for b: Dictionary in m.buildings:
		if b.hp <= 0: continue
		if b.kind == "mass_grave":
			if String(dead.get("kind","")) == "skeleton": continue
			m.link(dead.pos,b.pos,b.team,"soul")
			grave_spawn(m,b)
		elif b.kind == "blood_tower" and b.cell.y in dead.get("lanes",[dead.lane]):
			m.link(dead.pos,b.pos,b.team,"devour")
			b.blood = minf(B.CARDS.blood_tower.blood_max,b.get("blood",0.0)+B.CARDS.blood_tower.blood_per_death)

static func in_time_field(m, target: Dictionary) -> bool:
	if m.fields.is_empty(): return false
	for f: Dictionary in m.fields:
		if f.team != target.team:
			var hit: bool = B.rect_hits_actor(f.rect,target) if f.has("rect") else (B.point_edge_distance(f.pos,target) <= f.radius)
			if hit: return true
	return false

static func speed_factor(m, u: Dictionary) -> float:
	return 0.5 if in_time_field(m,u) else 1.0

static func interval_factor(m, u: Dictionary) -> float:
	return 2.0 if in_time_field(m,u) else 1.0

static func building_factor(m, b: Dictionary) -> float:
	return 0.5 if in_time_field(m,b) else 1.0

static func shield_active(m, target: Dictionary) -> bool:
	if target.get("shield",0.0) <= 0.0: return false
	var until: float = float(target.get("shield_until",0.0))
	return until < 0.0 or until > m.elapsed

# Shield soaks damage first (after armour). Returns what is left for hp.
static func absorb(m, target: Dictionary, amount: float) -> float:
	if not shield_active(m,target): return amount
	var soak := minf(amount,target.shield)
	target.shield -= soak
	if target.shield <= 0.0: target.shield_until = 0.0
	return amount-soak

# ---------- AI ----------

# Score for the new cards (-INF = no opinion). Plays >= 600 are deliberate (see enemy_ai.gd).
static func ai_score(c: Dictionary, s: Dictionary, covered: Dictionary = {}) -> float:
	var is_spell: bool = c.kind in SPELLS
	if not is_spell and not c.kind in ["watchtower","mass_grave","blood_tower"]: return -INF
	var team: int = s.team
	var data: Dictionary = B.CARDS[c.kind]
	var rect: Rect2 = B.spell_rect(c.pos,data) if is_spell else Rect2()
	match c.kind:
		"mana_spring":
			var n := 0
			var worn := false
			for b: Dictionary in s.buildings:
				if b.hp > 0 and b.team == team and b.kind == "crystal" and B.rect_hits_actor(rect,b):
					n += 1
					if b.hp < b.max_hp*0.5: worn = true
			if n >= 2 or worn: return 660.0+n*10
		"chain_lightning":
			var foes := 0
			var heavy := false
			for u: Dictionary in s.units:
				var in_box: bool = B.rect_hits_actor(rect,u)
				if u.hp > 0 and u.team != team and not covered.has(u.get("id",-1)) and (in_box or u.pos.distance_to(c.pos) <= data.radius+data.hop_radius):
					foes += 1
					if u.max_hp >= B.tier_value("hp","A") and in_box: heavy = true
			for b: Dictionary in s.buildings:
				if b.hp > 0 and b.team != team and not B.CARDS[b.kind].has("trap") and not GluttonNest.hidden(b) and not b.get("twin_secondary",false) and (B.rect_hits_actor(rect,b) or b.pos.distance_to(c.pos) <= data.radius+data.hop_radius):
					foes += 1
			if foes >= 3 or heavy: return 700.0+foes*15
		"arcane_shield":
			var allies := 0
			var engaged := false
			for u: Dictionary in s.units:
				if u.hp <= 0 or not B.rect_hits_actor(rect,u): continue
				if u.team == team: allies += 1
				else: engaged = true
			if allies >= 3 and engaged: return 690.0+allies*10
		"time_field":
			var near := 0
			var forward := 1.0 if team == 0 else -1.0
			for u: Dictionary in s.units:
				if u.hp > 0 and u.team != team and not covered.has(u.get("id",-1)) and B.rect_hits_actor(rect,u) and (u.pos.x-L.GRID_ORIGIN.x-L.GRID_SIZE.x*0.5)*forward < 0: near += 1
			for b: Dictionary in s.buildings:
				if b.hp > 0 and b.team != team and B.rect_hits_actor(rect,b): near += 1
			if near >= 4: return 710.0+near*10
		"charge_horn":
			var lane := lane_of(c.pos)
			var marching := 0
			for u: Dictionary in s.units:
				if u.hp > 0 and u.team == team and u.lane == lane: marching += 1
			if marching >= 3 and c.cell.x == (0 if team == 0 else 8): return 670.0+marching*8 # one candidate per lane
		"levy":
			var forward := 1.0 if team == 0 else -1.0
			var gate_x := L.gate_stop(team)
			var n := 0
			var first_c := Vector2i(999,999)
			for cand: Dictionary in s.get("candidates",[]):
				if cand.kind == "levy" and (cand.cell.x < first_c.x or (cand.cell.x == first_c.x and cand.cell.y < first_c.y)):
					first_c = cand.cell
			if c.cell == first_c:
				for u: Dictionary in s.units:
					if u.hp <= 0 or u.team == team or covered.has(u.get("id",-1)) or u.get("flying",false): continue
					if (u.pos.x-gate_x)*forward <= L.CELL_SIZE.x*4.5: n += 1
			if n >= 3: return 720.0+n*10
		"sacrifice":
			var cap: float = float(data.get("bite_cap",500.0))
			var sacrifice_hp := 0.0
			var mine := 0
			var cheap := 0
			var foes := 0
			for u: Dictionary in s.units:
				if u.hp <= 0 or not B.rect_hits_actor(rect,u): continue
				if u.team != team:
					if not covered.has(u.get("id",-1)): foes += 1
					continue
				mine += 1
				sacrifice_hp += minf(cap,u.hp)
				if u.kind == "skeleton" or u.get("borrowed_until",-1.0) > 0 or u.hp < u.max_hp*0.45: cheap += 1
			var gain: int = GluttonNest.gold_for_health(sacrifice_hp,data)
			if mine >= 1 and cheap == mine and foes >= 2:
				return 690.0+float(foes)*22.0+float(gain)*10.0
			if mine >= 2 and cheap == mine:
				if gain >= int(data.cost)+2: return 650.0+gain*10.0
		"dread_howl":
			var near := 0
			var foes := 0
			var allies := 0
			var gate_x := L.gate_stop(team)
			for u: Dictionary in s.units:
				if u.hp <= 0: continue
				if u.team == team:
					if B.rect_hits_actor(rect,u) or u.pos.distance_to(c.pos) <= 220.0: allies += 1
					continue
				if covered.has(u.get("id",-1)) or not B.rect_hits_actor(rect,u): continue
				foes += 1
				if absf(u.pos.x-gate_x) <= L.CELL_SIZE.x*2.5: near += 1
			if near >= 2: return 760.0+float(near)*14.0
			if foes >= 2 and allies >= 1: return 700.0+float(foes)*16.0+float(allies)*10.0
			if foes >= 3: return 690.0+float(foes)*14.0
		"watchtower", "mass_grave", "blood_tower":
			var col: int = c.cell.x if team == 0 else 8-c.cell.x
			if col > (4 if c.kind == "watchtower" else 2): return -INF
			var same := 0
			var total_same := 0
			var wt_count := 0
			var near_wt := false
			var fight := 0
			var non_skel := 0
			for b: Dictionary in s.buildings:
				if b.hp > 0 and b.team == team and b.kind == c.kind:
					total_same += 1
					if b.cell.y == c.cell.y: same += 1
					if c.kind == "watchtower":
						wt_count += 1
						if absi(b.cell.x-c.cell.x) <= 2 and absi(b.cell.y-c.cell.y) <= 2: near_wt = true
			for u: Dictionary in s.units:
				if u.hp <= 0 or (u.team != team and covered.has(u.get("id",-1))): continue
				if u.kind != "skeleton": non_skel += 1
				if u.lane == c.cell.y: fight += 1
			if c.kind == "watchtower":
				if wt_count >= 2 or near_wt: return -INF
				var shooters := 0
				var sneaky := false
				for u: Dictionary in s.units:
					if u.hp <= 0 or u.lane != c.cell.y: continue
					if u.team == team and B.is_ranged_unit(B.CARDS.get(u.kind,{})): shooters += 1
					if u.team != team and not covered.has(u.get("id",-1)) and B.CARDS[u.kind].get("stealth",false): sneaky = true
				if shooters >= 2 or sneaky: return 650.0+col*4
				if col >= 1 and int(s.get("owned_cells",0)) < 28: return 625.0+col*10
				return -INF
			if c.kind == "mass_grave":
				if same >= 2 or total_same >= 3: return -INF
				if non_skel >= 4: return 640.0+float(non_skel)*4.0+float(fight)*2.0-col*8.0
				return -INF
			if same >= 1: return -INF
			if fight >= 4: return 640.0+fight*4-col*8
	return -INF

# ---------- drawing (game.gd) ----------

static func draw_bar(g, b: Dictionary) -> void:
	if b.kind == "blood_tower": g.bar(Rect2(b.pos+Vector2(-30,36),Vector2(60,5)),b.get("blood",0.0),B.CARDS.blood_tower.blood_max,Color("b03a3a") if b.get("bleeding",false) else Color("6e3030"))

# Watchtower reach (producer 2026-11-05: the effect must match the real radius): a faint dashed ring
# at the true range and a beam that sweeps out to it, both read from the card data.
static func draw_watchtowers(g) -> void:
	var r: float = B.CARDS.watchtower.radius
	for b: Dictionary in g.model.buildings:
		if b.hp <= 0 or b.kind != "watchtower": continue
		var c: Vector2 = b.pos
		for i: int in range(48): # dashed ring
			if i % 2 == 0: g.draw_arc(c,r,i*TAU/48,(i+1)*TAU/48,4,Color(1.0,0.86,0.40,0.55),2.0,true)
		var angle: float = g.model.elapsed*0.6
		var fan := PackedVector2Array([c])
		for i: int in range(13): fan.append(c+Vector2.from_angle(angle-0.18+i*0.03)*r)
		g.draw_colored_polygon(fan,Color(1.0,0.89,0.47,0.10))
		g.draw_arc(c,r,angle-0.18,angle+0.18,12,Color(1.0,0.92,0.60,0.7),2.5,true)

static func draw_heal_auras(g) -> void:
	for b: Dictionary in g.model.buildings:
		if b.hp <= 0 or not b.kind in ["soul_well","sleepless_belfry"]: continue
		var r: float = float(B.CARDS[b.kind].radius)+B.actor_radius(b)
		var col := Color("dbd5ac",0.30) if b.kind == "sleepless_belfry" else Color("5ce675",0.30)
		var c: Vector2 = b.pos
		for i: int in range(48):
			if i % 2 == 0: g.draw_arc(c,r,i*TAU/48,(i+1)*TAU/48,4,col,1.8,true)

static func draw(g) -> void:
	if not g.fx_enabled: return
	draw_watchtowers(g)
	draw_heal_auras(g)
	for u: Dictionary in g.model.units:
		if u.hp <= 0 or u.get("spawn_delay",0.0) > 0 or u.get("flying",false): continue
		if horn_active(g.model,u):
			var foot: Vector2 = u.get("draw",u.pos)+Vector2(0,8)
			var forward := 1.0 if u.team == 0 else -1.0
			for i: int in range(4):
				var t: float = fposmod(g.model.elapsed*2.2+i*0.25+u.pos.x*0.01,1.0)
				g.draw_circle(foot+Vector2(-forward*(8+t*26),-t*10+sin(i*2.0)*3),2+t*4,Color(0.65,0.51,0.32,(1-t)*0.45))
	for f: Dictionary in g.model.fields:
		var fade := clampf(f.left/0.5,0,1)
		var spin: float = g.model.elapsed*0.6
		var frect: Rect2 = f.get("rect",Rect2())
		if frect.size != Vector2.ZERO:
			g.draw_rect(frect,Color(0.45,0.55,0.85,0.16*fade))
			g.draw_rect(frect,Color(0.35,0.45,0.80,0.72*fade),false,2.5)
			var fc: Vector2 = frect.get_center()
			for i: int in range(12):
				var a := spin+i*TAU/12
				g.draw_line(fc+Vector2.from_angle(a)*48.0,fc+Vector2.from_angle(a)*58.0,Color(0.30,0.40,0.75,0.7*fade),2)
		else:
			g.draw_circle(f.pos,f.radius,Color(0.45,0.55,0.85,0.16*fade))
			g.draw_arc(f.pos,f.radius,0,TAU,48,Color(0.35,0.45,0.80,0.65*fade),2,true)
			for i: int in range(12): # clock ticks turning slowly
				var a := spin+i*TAU/12
				g.draw_line(f.pos+Vector2.from_angle(a)*(f.radius-10),f.pos+Vector2.from_angle(a)*(f.radius-2),Color(0.30,0.40,0.75,0.7*fade),2)

# Drawn after the troops so the shield bubble sits on top of them.
static func draw_over(g) -> void:
	if not g.fx_enabled: return
	for b: Dictionary in g.model.buildings:
		if b.hp <= 0 or b.kind != "watchtower": continue
		var top: Vector2 = b.pos+Vector2(0,g.actor_rect("watchtower").position.y+10)
		g.draw_circle(top,4,Color(1.0,0.94,0.70,0.8)) # the lamp; its reach is drawn under the troops
	for u: Dictionary in g.model.units:
		if u.hp <= 0 or u.get("spawn_delay",0.0) > 0: continue
		if u.get("fear_left",0.0) > 0:
			var head: Vector2 = u.get("draw",u.pos)+Vector2(sin(g.model.elapsed*34+u.pos.x)*2.5,-60+sin(g.model.elapsed*19)*1.5)
			g.draw_circle(head,7,Color("352632"))
			g.draw_circle(head,5.5,Color("e8dcc0"))
			g.draw_rect(Rect2(head+Vector2(-3,3),Vector2(6,5)),Color("e8dcc0"))
			for x: float in [-2.2,2.2]: g.draw_circle(head+Vector2(x,-1),1.6,Color("352632"))
			g.draw_line(head+Vector2(0,5),head+Vector2(0,8),Color("352632"),1)
		if u.hp > 0 and shield_active(g.model,u):
			var k: float = clampf(u.shield/B.CARDS.arcane_shield.shield,0.25,1.0) # stacked shields stay at full glow
			var c: Vector2 = u.get("draw",u.pos)+Vector2(0,-22)
			g.draw_circle(c,30,Color(0.55,0.80,1.0,0.12*k))
			g.draw_arc(c,30,0,TAU,28,Color(0.45,0.75,1.0,0.85*k),2.5,true)
