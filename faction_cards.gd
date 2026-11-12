extends RefCounted
# Cards from docs/三陣營各補四張.md (2026-11-05): four new cards for each faction.
# Battle hooks: spell casts (cast), extra play limits (play_error), damage (absorb),
# speed / interval multipliers, per-step update and deaths. Drawing lives in draw().
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Arcane = preload("res://arcane_mechanics.gd")

const SPELLS := ["mana_spring","chain_lightning","arcane_shield","time_field","charge_horn","levy","sacrifice","dread_howl"]
const DEFENSIVE := ["chain_lightning","time_field","levy","dread_howl"] # worth more in the lane the AI is defending

# ---------- casting ----------

# True when this module handled the spell.
static func cast(m, s: Dictionary) -> bool:
	if not s.kind in SPELLS: return false
	var data: Dictionary = B.CARDS[s.kind]
	m.event("spell",s.pos,s.team,{"card":s.kind,"radius":data.get("radius",0.0)})
	match s.kind:
		"mana_spring":
			for b: Dictionary in crystals_in(m,s.team,s.pos,data.radius):
				m.gain_ink(s.team,B.CARDS.crystal.income)
				b.hp = minf(b.max_hp,b.hp+b.max_hp*data.heal_fraction)
				m.event("ink",b.pos,s.team)
				m.link(s.pos,b.pos,s.team,"mana")
		"chain_lightning": chain(m,s,data)
		"arcane_shield":
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team == s.team and u.pos.distance_to(s.pos) <= data.radius:
					# Stacks: a recast adds to what is left and restarts the clock.
					var left: float = u.get("shield",0.0) if u.get("shield_until",0.0) > m.elapsed else 0.0
					u.shield = left+data.shield
					u.shield_until = m.elapsed+data.duration
		"time_field":
			m.fields.append({"pos":s.pos,"team":s.team,"radius":data.radius,"left":data.duration,"duration":data.duration})
		"charge_horn":
			m.horns.append({"team":s.team,"lane":lane_of(s.pos),"until":m.elapsed+data.duration})
		"levy":
			var forward := 1.0 if s.team == 0 else -1.0
			for foe: Dictionary in intruders(m,s.team):
				# One militia per intruder, just on our side of it.
				var x := clampf(foe.pos.x-45*forward,L.GRID_ORIGIN.x+8,L.GRID_ORIGIN.x+L.GRID_SIZE.x-8)
				var u: Dictionary = m.spawn_unit(s.team,foe.lane,"militia",Vector2(x,L.cell_center(Vector2i(0,foe.lane)).y))
				u.card = "levy"
				u.levy = true
				m.event("summoned",u.pos,u.team)
		"sacrifice":
			var victims: Array = m.units.filter(func(u: Dictionary) -> bool: return u.hp > 0 and u.team == s.team and u.get("spawn_delay",0.0) <= 0 and u.pos.distance_to(s.pos) <= data.radius)
			for u: Dictionary in victims:
				m.link(u.pos,s.pos,s.team,"devour")
				m.damage(u,u.hp,s.team,"sacrifice",{},true)
			m.gain_ink(s.team,victims.size()*data.gold_per_unit)
		"dread_howl":
			for u: Dictionary in m.units:
				if u.hp > 0 and u.team != s.team and u.pos.distance_to(s.pos) <= data.radius: u.fear_left = data.duration
	return true

static func lane_of(pos: Vector2) -> int:
	return clampi(floori((pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,L.GRID_ROWS-1)

# Enemy ground troops standing on our territory.
static func intruders(m, team: int) -> Array:
	return m.units.filter(func(u: Dictionary) -> bool: return u.hp > 0 and u.team != team and not u.get("flying",false) and u.get("spawn_delay",0.0) <= 0 and m.territory_owner(m.cell_at(u.pos)) == team)

static func crystals_in(m, team: int, pos: Vector2, radius: float) -> Array:
	return m.buildings.filter(func(b: Dictionary) -> bool: return b.hp > 0 and b.team == team and b.kind == "crystal" and b.pos.distance_to(pos) <= radius)

# Hits the enemy nearest the drop point, then hops to the nearest not-yet-hit enemy within
# hop_radius of the last one. Each hop is one damage tier lower (SS -> S -> A -> B -> C).
static func chain(m, s: Dictionary, data: Dictionary) -> void:
	var pool: Array = []
	for u: Dictionary in m.units:
		if u.hp > 0 and u.team != s.team and u.get("spawn_delay",0.0) <= 0: pool.append(u)
	for b: Dictionary in m.buildings:
		if b.hp > 0 and b.team != s.team: pool.append(b)
	var at: Vector2 = s.pos
	var reach: float = data.radius
	var tier: int = B.TIERS.damage.find(data.bolt_damage)
	var hit: Array = []
	for i: int in range(data.hops+1):
		var best: Dictionary = {}
		var best_d := INF
		for t: Dictionary in pool:
			if t in hit or t.hp <= 0: continue
			var d: float = t.pos.distance_to(at)
			if d <= reach and d < best_d:
				best = t
				best_d = d
		if best.is_empty(): break
		hit.append(best)
		m.link(at,best.pos,s.team,"lightning")
		m.damage(best,B.TIERS.damage[mini(tier+i,B.TIERS.damage.size()-1)],s.team,s.kind)
		at = best.pos
		reach = data.hop_radius

# Extra placement limits ("" = fine). Called from play_check for these spells.
static func play_error(m, team: int, kind: String, pos: Vector2) -> String:
	if kind == "mana_spring" and crystals_in(m,team,pos,B.CARDS.mana_spring.radius).is_empty(): return "no crystal"
	if kind == "levy" and (intruders(m,team).is_empty() or m.territory_owner(m.cell_at(pos)) != team): return "no intruders"
	if kind == "sacrifice" and not m.units.any(func(u: Dictionary) -> bool: return u.hp > 0 and u.team == team and u.pos.distance_to(pos) <= B.CARDS.sacrifice.radius): return "no troops"
	return ""

# ---------- ongoing effects ----------

static func update(m, dt: float) -> void:
	for f: Dictionary in m.fields: f.left -= dt
	m.fields = m.fields.filter(func(f: Dictionary) -> bool: return f.left > 0.000001)
	m.horns = m.horns.filter(func(h: Dictionary) -> bool: return h.until > m.elapsed)
	# Levy militia only exist inside our territory (they vanish, no death effects).
	m.units = m.units.filter(func(u: Dictionary) -> bool: return not (u.get("levy",false) and u.hp > 0 and m.territory_owner(m.cell_at(u.pos)) != u.team))
	# Watchtowers reveal stealthed enemies in reach.
	for b: Dictionary in m.buildings:
		if b.hp <= 0 or b.kind != "watchtower": continue
		for u: Dictionary in m.units:
			if u.team != b.team and u.get("stealthed",false) and u.pos.distance_to(b.pos) <= B.CARDS.watchtower.radius:
				Arcane.reveal(m, u)

static func horn_active(m, u: Dictionary) -> bool:
	return horn_count(m,u) > 0

static func horn_count(m, u: Dictionary) -> int:
	var n := 0
	for h: Dictionary in m.horns:
		if h.team == u.team and h.lane == u.lane: n += 1
	return n

# A troop that shoots, or a tower, inside our watchtower's reach: one range tier further.
static func watched(m, actor: Dictionary) -> bool:
	for b: Dictionary in m.buildings:
		if b.hp > 0 and b.kind == "watchtower" and b.team == actor.team and b.pos.distance_to(actor.pos) <= B.CARDS.watchtower.radius: return true
	return false

static func longer(r: float) -> float:
	var i: int = B.TIERS.range.find(r)
	return B.TIERS.range[i-1] if i > 0 else r

static func unit_data(m, u: Dictionary, data: Dictionary) -> Dictionary:
	if not data.get("projectile",false) or not watched(m,u): return data
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
	u.face = signf(home-u.pos.x)
	u.pos.x = move_toward(u.pos.x,home,m.movement_speed(u)*dt)
	if u.fear_left <= 0: u.face = 1.0 if u.team == 0 else -1.0 # fear over: turn back toward the enemy
	return true

# A hit landed (after damage). Nets slow the target.
static func on_hit(m, target: Dictionary, source: Dictionary) -> void:
	if source.get("kind","") == "net_hunter" and target.has("lane") and not target.get("flying",false) and target.hp > 0:
		target.slow_left = maxf(target.get("slow_left",0.0),B.CARDS.net_hunter.net_slow)

# Buildings with their own clock. True = handled.
static func update_building(m, b: Dictionary, dt: float) -> bool:
	if b.kind == "mass_grave":
		b.production += dt
		if b.production >= B.CARDS.mass_grave.period: grave_spawn(m,b)
		return true
	if b.kind == "blood_tower":
		var d: Dictionary = B.CARDS.blood_tower
		b.blood_fx_cd = maxf(0.0,b.get("blood_fx_cd",0.0)-dt)
		b.blood_glow = maxf(0.0,b.get("blood_glow",0.0)-dt)
		b.blood = minf(d.blood_max,b.get("blood",0.0)+d.blood_rate*dt)
		if not b.get("bleeding",false) and b.blood > d.restart_at: b.bleeding = true
		if not b.get("bleeding",false): return true
		var hurt: Array = m.units.filter(func(u: Dictionary) -> bool: return u.hp > 0 and u.team == b.team and u.lane == b.cell.y and u.get("spawn_delay",0.0) <= 0 and u.hp < u.max_hp)
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
	b.production = 0.0 # like the grave, extra time is not kept
	for i: int in range(B.CARDS.mass_grave.spawn_count):
		var u: Dictionary = m.spawn_unit(b.team,b.cell.y,"skeleton",b.pos)
		u.card = "mass_grave"
		u.spawn_delay = i*0.12
	m.event("summoned",b.pos,b.team)

# A troop died in a lane (either side): the grave-like buildings there advance.
static func on_death(m, dead: Dictionary) -> void:
	for b: Dictionary in m.buildings:
		if b.hp <= 0 or b.cell.y != dead.lane: continue
		if b.kind == "mass_grave":
			m.link(dead.pos,b.pos,b.team,"soul")
			b.production += B.CARDS.mass_grave.death_advance
			if b.production >= B.CARDS.mass_grave.period: grave_spawn(m,b)
		elif b.kind == "blood_tower":
			m.link(dead.pos,b.pos,b.team,"devour")
			b.blood = minf(B.CARDS.blood_tower.blood_max,b.get("blood",0.0)+B.CARDS.blood_tower.blood_per_death)

static func in_time_field(m, target: Dictionary) -> bool:
	for f: Dictionary in m.fields:
		if f.team != target.team and target.pos.distance_to(f.pos) <= f.radius: return true
	return false

static func speed_factor(m, u: Dictionary) -> float:
	return 0.5 if in_time_field(m,u) else 1.0

static func interval_factor(m, u: Dictionary) -> float:
	return 2.0 if in_time_field(m,u) else 1.0

static func building_factor(m, b: Dictionary) -> float:
	return 0.5 if in_time_field(m,b) else 1.0

# Shield soaks damage first (after armour). Returns what is left for hp.
static func absorb(m, target: Dictionary, amount: float) -> float:
	if target.get("shield",0.0) <= 0 or target.get("shield_until",0.0) <= m.elapsed: return amount
	var soak := minf(amount,target.shield)
	target.shield -= soak
	return amount-soak

# ---------- AI ----------

# Score for the new cards (-INF = no opinion). Plays >= 600 are deliberate (see enemy_ai.gd).
static func ai_score(c: Dictionary, s: Dictionary) -> float:
	var team: int = s.team
	var data: Dictionary = B.CARDS[c.kind]
	match c.kind:
		"mana_spring":
			var n := 0
			var worn := false
			for b: Dictionary in s.buildings:
				if b.hp > 0 and b.team == team and b.kind == "crystal" and b.pos.distance_to(c.pos) <= data.radius:
					n += 1
					if b.hp < b.max_hp*0.5: worn = true
			if n >= 2 or worn: return 660.0+n*10
		"chain_lightning":
			var foes := 0
			var heavy := false
			for u: Dictionary in s.units:
				if u.hp > 0 and u.team != team and u.pos.distance_to(c.pos) <= data.radius+data.hop_radius:
					foes += 1
					if u.max_hp >= B.tier_value("hp","A") and u.pos.distance_to(c.pos) <= data.radius: heavy = true
			for b: Dictionary in s.buildings:
				if b.hp > 0 and b.team != team and b.pos.distance_to(c.pos) <= data.radius+data.hop_radius:
					foes += 1
			if foes >= 3 or heavy: return 700.0+foes*15
		"arcane_shield":
			var allies := 0
			var engaged := false
			for u: Dictionary in s.units:
				if u.hp <= 0 or u.pos.distance_to(c.pos) > data.radius: continue
				if u.team == team: allies += 1
				else: engaged = true
			if allies >= 3 and engaged: return 690.0+allies*10
		"time_field":
			var near := 0
			var forward := 1.0 if team == 0 else -1.0
			for u: Dictionary in s.units:
				if u.hp > 0 and u.team != team and u.pos.distance_to(c.pos) <= data.radius and (u.pos.x-L.GRID_ORIGIN.x-L.GRID_SIZE.x*0.5)*forward < 0: near += 1
			for b: Dictionary in s.buildings:
				if b.hp > 0 and b.team != team and b.pos.distance_to(c.pos) <= data.radius: near += 1
			if near >= 4: return 710.0+near*10
		"charge_horn":
			var lane := lane_of(c.pos)
			var marching := 0
			for u: Dictionary in s.units:
				if u.hp > 0 and u.team == team and u.lane == lane: marching += 1
			if marching >= 3 and c.cell.x == (0 if team == 0 else 8): return 670.0+marching*8 # one candidate per lane
		"levy":
			var n := 0
			for u: Dictionary in s.units:
				if u.hp > 0 and u.team != team and not u.get("flying",false) and u.lane == c.cell.y and (u.pos.x-c.pos.x)*(1.0 if team == 0 else -1.0) >= 0: n += 1
			if n >= 3: return 720.0+n*10
		"sacrifice":
			var mine := 0
			var cheap := 0
			for u: Dictionary in s.units:
				if u.hp <= 0 or u.team != team or u.pos.distance_to(c.pos) > data.radius: continue
				mine += 1
				if u.kind == "skeleton" or u.hp < u.max_hp*0.3: cheap += 1
			if mine >= 3 and cheap == mine: return 650.0+mine*10
		"dread_howl":
			var near := 0
			var gate_x := L.gate_stop(team)
			for u: Dictionary in s.units:
				if u.hp > 0 and u.team != team and u.pos.distance_to(c.pos) <= data.radius and absf(u.pos.x-gate_x) <= L.CELL_SIZE.x*2: near += 1
			if near >= 3: return 760.0+near*10
		"watchtower", "mass_grave", "blood_tower":
			var col: int = c.cell.x if team == 0 else 8-c.cell.x
			if col > 2: return -INF
			var same := 0
			var fight := 0
			for b: Dictionary in s.buildings:
				if b.hp > 0 and b.team == team and b.kind == c.kind and b.cell.y == c.cell.y: same += 1
			for u: Dictionary in s.units:
				if u.hp > 0 and u.lane == c.cell.y: fight += 1
			if same >= (2 if c.kind == "mass_grave" else 1): return -INF
			if c.kind == "watchtower":
				var shooters := 0
				var sneaky := false
				for u: Dictionary in s.units:
					if u.hp <= 0 or u.lane != c.cell.y: continue
					if u.team == team and B.CARDS[u.kind].get("projectile",false): shooters += 1
					if u.team != team and B.CARDS[u.kind].get("stealth",false): sneaky = true
				return 650.0-col*8 if shooters >= 2 or sneaky else -INF
			if fight >= 4: return 640.0+fight*4-col*8
	return -INF

# ---------- drawing (game.gd) ----------

static func draw_bar(g, b: Dictionary) -> void:
	if b.kind == "mass_grave": g.bar(Rect2(b.pos+Vector2(-30,36),Vector2(60,5)),b.production,B.CARDS.mass_grave.period,Color("6f8f4e")) # rot green: bone white vanished on the bar background
	elif b.kind == "blood_tower": g.bar(Rect2(b.pos+Vector2(-30,36),Vector2(60,5)),b.get("blood",0.0),B.CARDS.blood_tower.blood_max,Color("b03a3a") if b.get("bleeding",false) else Color("6e3030"))

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

static func draw(g) -> void:
	if not g.fx_enabled: return
	draw_watchtowers(g)
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
		if u.hp > 0 and u.get("shield",0.0) > 0 and u.get("shield_until",0.0) > g.model.elapsed:
			var k: float = clampf(u.shield/B.CARDS.arcane_shield.shield,0.25,1.0) # stacked shields stay at full glow
			var c: Vector2 = u.get("draw",u.pos)+Vector2(0,-22)
			g.draw_circle(c,30,Color(0.55,0.80,1.0,0.12*k))
			g.draw_arc(c,30,0,TAU,28,Color(0.45,0.75,1.0,0.85*k),2.5,true)
