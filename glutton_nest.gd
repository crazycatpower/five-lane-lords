extends RefCounted
const B = preload("res://balance.gd")

static func hidden(actor: Dictionary) -> bool:
	return actor.get("kind","") == "glutton_nest" and actor.get("digest_left",0.0) <= 0.0 and actor.get("nest_windup",0.0) <= 0.0

static func gold_for_health(health: float) -> int:
	var d: Dictionary = B.CARDS.glutton_nest
	# Arithmetic progression: 100, 220, 360, 520... cumulative HP.
	var half_step: float = d.gold_step / 2.0
	var linear: float = d.gold_first-half_step
	return maxi(0,int(floor((sqrt(linear*linear+4.0*half_step*maxf(0.0,health))-linear)/(2.0*half_step))))

static func digestion_time(gold: int) -> float:
	var d: Dictionary = B.CARDS.glutton_nest
	return d.digest_time + maxi(0,gold)*d.digest_per_gold

static func edible(u: Dictionary) -> bool:
	return u.get("kind","") != "lord" and not u.has("cell") and u.hp > 0 and u.get("spawn_delay",0.0) <= 0 and not u.get("phased",false) and not B.CARDS.get(u.kind,{}).get("flying",false)

static func update(m, b: Dictionary, dt: float) -> bool:
	if b.kind != "glutton_nest": return false
	if b.hp <= 0: return true
	var d: Dictionary = B.CARDS.glutton_nest
	if b.get("digest_left",0.0) > 0:
		var total: float = b.get("digest_total",digestion_time(int(b.get("last_gold",0))))
		var before: float = maxf(0.0,total-b.digest_left-d.bite_duration)
		b.digest_left = maxf(0.0,b.digest_left-dt)
		var after: float = maxf(0.0,total-b.digest_left-d.bite_duration)
		# Count completed chews, capped at the end of digestion even for large dt.
		var chews := int(floor((after+0.000001)/d.chew_period))-int(floor((before+0.000001)/d.chew_period))
		if b.get("meal_health",0.0) > 0 and chews > 0 and b.hp < b.max_hp:
			b.hp = minf(b.max_hp,b.hp+chews*d.chew_heal)
			if m.record_events: m.event("heal",b.pos,b.team,{"silent":true})
		if b.digest_left <= 0: m.build_lookups()
		return true
	if b.get("nest_windup",0.0) <= 0:
		for u: Dictionary in m.units:
			if edible(u) and u.pos.distance_to(b.pos) <= d.trigger_radius:
				b.nest_windup = d.windup
				m.event("nest_windup",b.pos,b.team)
				m.build_lookups()
				break
		return true
	b.nest_windup = maxf(0.0,b.nest_windup-dt)
	if b.nest_windup > 0: return true
	# Recheck at impact: units can flee or enter the mouth during the tell.
	var victims: Array[Dictionary] = []
	for u: Dictionary in m.units:
		if edible(u) and u.pos.distance_to(b.pos) <= d.radius: victims.append(u)
	var health := 0.0
	for u: Dictionary in victims:
		health += u.hp
		# Sacrifice bypasses armour, shields and lethal-hit rescue, but preserves death accounting.
		m.damage(u,u.hp,b.team,b.kind,{},true)
		m.link(u.pos,b.pos,b.team,"devour")
	b.meal_health = health
	b.last_gold = gold_for_health(health)
	b.digest_total = digestion_time(b.last_gold)
	b.digest_left = b.digest_total
	m.gain_ink(b.team,b.last_gold)
	m.event("nest_bite",b.pos,b.team)
	if b.last_gold > 0: m.event("ink",b.pos,b.team)
	m.build_lookups()
	return true

# Presentation reads simulation clocks only; no Tween callback can change combat timing.
static func draw(g, b: Dictionary, pos: Vector2) -> void:
	var rect: Rect2 = g.actor_rect("glutton_nest")
	var d: Dictionary = B.CARDS.glutton_nest
	if hidden(b):
		g.draw_arc(pos+Vector2(0,22),34,0,PI,20,Color("a8b5c7"),2)
		g.draw_texture_rect(g.art("glutton_nest",b.team),Rect2(pos+rect.position,rect.size),false,Color(1,1,1,0.72))
		return
	if b.get("nest_windup",0.0) > 0:
		var progress: float = clampf(1.0-b.nest_windup/d.windup,0.0,1.0)
		var size := Vector2.ONE
		if g.fx_enabled:
			# Squat, then stretch the open jaw upwards; keep the roots on the ground.
			size = Vector2(1.0+0.13*sin(progress*PI),0.85+0.4*progress)
			g.draw_arc(pos,d.radius,-PI*0.5,-PI*0.5+TAU*maxf(0.02,progress),48,Color(0.8,0.45,0.16,0.25+progress*0.35),2,true)
		draw_body(g,b,pos,rect,"glutton_nest",size)
		return
	var total: float = b.get("digest_total",digestion_time(int(b.get("last_gold",0))))
	var age: float = total-b.digest_left
	var size := Vector2.ONE
	var texture_kind := "glutton_nest_closed"
	if g.fx_enabled and age < d.bite_duration:
		var bite: float = clampf(age/d.bite_duration,0,1)
		texture_kind = "glutton_nest" if bite < 0.35 else "glutton_nest_closed"
		size = Vector2(1.0+0.22*sin(bite*PI),1.25-0.45*sin(bite*PI))
		g.draw_arc(pos,d.radius*(1.0-bite),0,TAU,48,Color(0.76,0.56,0.27,(1.0-bite)*0.65),2,true)
	elif g.fx_enabled and age < 0.9:
		var settle: float = (age-d.bite_duration)/(0.9-d.bite_duration)
		size = Vector2(1.0+0.07*sin(settle*TAU)*(1-settle),1.0+0.12*sin(settle*PI)*(1-settle))
	elif g.fx_enabled and b.get("meal_health",0.0) > 0:
		var phase: float = fposmod(maxf(0.0,age-d.bite_duration),d.chew_period)/d.chew_period
		# Two short closed-jaw chews, then a pause; roots remain planted.
		var chew: float = maxf(0.0,sin(phase*TAU*2.0))
		size = Vector2(1.0+0.09*chew,1.0-0.12*chew)
		pos.x += sin(phase*TAU*2.0)*1.5
	draw_body(g,b,pos,rect,texture_kind,size)
	g.bar(Rect2(pos+Vector2(-28,32),Vector2(56,4)),b.digest_left,total,Color("c8962c"))

static func draw_body(g, b: Dictionary, pos: Vector2, rect: Rect2, texture: String, scale: Vector2) -> void:
	var size := rect.size*scale
	var bottom := pos+Vector2(rect.get_center().x,rect.end.y)
	g.draw_texture_rect(g.art(texture,b.team),Rect2(bottom-Vector2(size.x*0.5,size.y),size),false)

static func ai_score(c: Dictionary, s: Dictionary, _target_lane: int, defend: int) -> float:
	var d: Dictionary = B.CARDS.glutton_nest
	var team: int = s.team
	var forward := 1.0 if team == 0 else -1.0
	var lane: int = c.cell.y
	var col: int = c.cell.x if team == 0 else 8-c.cell.x
	var lane_nests := 0
	for b: Dictionary in s.buildings:
		if b.hp <= 0 or b.team != team or b.kind != "glutton_nest": continue
		if b.cell.y == lane: lane_nests += 1
	var foe_eat := 0.0
	var ally_eat := 0.0
	var foe_ahead := 0.0
	var ally_behind := 0.0
	var min_foe_dist := INF
	var min_ally_dist := INF
	for u: Dictionary in s.units:
		if u.hp <= 0 or u.get("kind","") == "lord" or u.has("cell") or u.get("phased",false) or B.CARDS.get(u.kind,{}).get("flying",false): continue
		var dist: float = u.pos.distance_to(c.pos)
		if u.team != team:
			if u.get("spawn_delay",0.0) <= 0 and dist <= d.radius: foe_eat += u.hp
			if u.lane == lane and u.get("fear_left",0.0) <= 0:
				var ahead: float = (u.pos.x-c.pos.x)*forward
				if ahead >= -d.trigger_radius and ahead <= 150.0:
					foe_ahead += u.hp
					min_foe_dist = minf(min_foe_dist,maxf(0.0,ahead-d.trigger_radius))
		else:
			if dist <= d.radius: ally_eat += u.hp
			if u.lane == lane:
				var behind: float = (c.pos.x-u.pos.x)*forward
				if behind > -d.trigger_radius and behind <= 200.0:
					ally_behind += u.hp
					min_ally_dist = minf(min_ally_dist,maxf(0.0,behind-d.trigger_radius))
	var net_eat: float = foe_eat-ally_eat*2.0
	if defend >= 0:
		if lane != defend: return -INF
		if foe_eat >= 150.0 and net_eat >= 100.0 and (min_foe_dist <= 35.0 or min_foe_dist <= min_ally_dist):
			return 940.0+minf(net_eat,1500.0)*0.06
		return -INF
	if foe_eat >= 180.0 and net_eat >= 130.0 and min_foe_dist <= 35.0:
		return 750.0+minf(net_eat,1200.0)*0.05
	if col >= 1 and lane_nests == 0 and ally_eat <= 0 and ally_behind <= 0 and foe_ahead >= 150.0:
		return 720.0+minf(foe_ahead,1000.0)*0.05+col*10.0
	# No passive income: never buy idle rear nests just to spend spare gold.
	return -INF
