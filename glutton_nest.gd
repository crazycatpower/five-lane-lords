extends RefCounted
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Giant = preload("res://giant_unit.gd")

static func hidden(actor: Dictionary) -> bool:
	return actor.get("kind","") == "glutton_nest" and actor.get("digest_left",0.0) <= 0.0 and actor.get("nest_windup",0.0) <= 0.0

static func gold_for_health(health: float, d: Dictionary = B.CARDS.glutton_nest) -> int:
	# Arithmetic progression: gold_first, gold_first + gold_step... cumulative HP.
	var half_step: float = float(d.gold_step) / 2.0
	var linear: float = float(d.gold_first)-half_step
	return maxi(0,int(floor((sqrt(linear*linear+4.0*half_step*maxf(0.0,health))-linear)/(2.0*half_step))))

static func meal_gold(health: float, d: Dictionary = B.CARDS.glutton_nest) -> int:
	if health <= 0.0: return 0
	return gold_for_health(health,d)+int(d.get("gold_bonus",0))

static func digestion_time(gold: int) -> float:
	var d: Dictionary = B.CARDS.glutton_nest
	return d.digest_time + maxi(0,gold)*d.digest_per_gold

static func edible_unit(u: Dictionary) -> bool:
	return u.hp > 0 and u.get("kind","") != "lord" and not u.has("cell") and not u.get("phased",false) and not B.CARDS.get(u.kind,{}).get("flying",false)

static func edible(u: Dictionary) -> bool:
	return edible_unit(u) and u.get("spawn_delay",0.0) <= 0

static func update(m, b: Dictionary, dt: float) -> bool:
	if b.kind != "glutton_nest": return false
	if b.hp <= 0: return true
	var d: Dictionary = B.CARDS.glutton_nest
	if b.get("digest_left",0.0) > 0:
		var total: float = float(b.get("digest_total",digestion_time(int(b.get("last_gold",0)))))
		var chew_span: float = maxf(0.01,total-float(d.bite_duration))
		var before: float = clampf(total-float(b.digest_left)-float(d.bite_duration),0.0,chew_span)
		b.digest_left = maxf(0.0,float(b.digest_left)-dt)
		var after: float = clampf(total-float(b.digest_left)-float(d.bite_duration),0.0,chew_span)
		# Count completed chews, capped at the end of digestion even for large dt.
		var chews := int(floor((after+0.000001)/d.chew_period))-int(floor((before+0.000001)/d.chew_period))
		if b.get("meal_health",0.0) > 0 and chews > 0 and b.hp < b.max_hp:
			b.hp = minf(b.max_hp,b.hp+chews*d.chew_heal)
			if m.record_events: m.event("heal",b.pos,b.team,{"silent":true})
		var goal_gold: int = int(b.get("last_gold",0))
		if goal_gold > 0:
			var total_chews: int = maxi(1,int(floor((chew_span+0.000001)/float(d.chew_period))))
			var done_chews: int = mini(total_chews,int(floor((after+0.000001)/float(d.chew_period))))
			var should_pay: int = goal_gold if b.digest_left <= 0.0 else int(floor(float(goal_gold)*float(done_chews)/float(total_chews)+0.000001))
			var paid: int = int(b.get("gold_paid",0))
			var due: int = should_pay-paid
			if due > 0:
				b.gold_paid = paid+due
				m.gain_ink(b.team,float(due))
				m.event("ink",b.pos,b.team)
		if b.digest_left <= 0: m.build_lookups()
		return true
	if b.get("nest_windup",0.0) <= 0:
		for u: Dictionary in m.units:
			if edible(u) and B.point_edge_distance(b.pos,u) <= d.trigger_radius: # allies and foes
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
		if edible(u) and B.point_edge_distance(b.pos,u) <= d.radius: victims.append(u)
	# One mouthful holds at most bite_max troops (enemies first, then nearest, ties by id).
	victims.sort_custom(func(a: Dictionary, c: Dictionary) -> bool:
		var ea: bool = a.team != b.team
		var ec: bool = c.team != b.team
		if ea != ec: return ea
		var da: float = B.point_edge_distance(b.pos,a)
		var dc: float = B.point_edge_distance(b.pos,c)
		return da < dc or (da == dc and a.id < c.id))
	victims = victims.slice(0,int(d.get("bite_max",victims.size())))
	var cap: float = d.get("bite_cap",500.0)
	var ally_mult: float = float(d.get("ally_feed_mult",2.0))
	var health := 0.0
	for u: Dictionary in victims:
		var dealt: float = cap if u.hp > cap else u.hp
		health += dealt*(ally_mult if u.team == b.team else 1.0)
		# Sacrifice bypasses armour, shields and lethal-hit rescue, but preserves death accounting.
		m.damage(u,dealt,b.team,b.kind,{},true)
		m.link(u.pos,b.pos,b.team,"devour")
	b.meal_health = health
	b.last_gold = meal_gold(health,d)
	b.gold_paid = 0
	b.digest_total = digestion_time(b.last_gold)
	b.digest_left = b.digest_total
	m.event("nest_bite",b.pos,b.team)
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

static func unit_building_damage(u: Dictionary, ud: Dictionary, first_hit: bool = false) -> float:
	var dmg: float = u.get("damage",ud.get("damage",0.0))
	if ud.get("charge",false) and first_hit and not u.get("charged",false): dmg *= B.CHARGE_MULT
	if u.kind == "ox": dmg *= B.OX_BUILDING_BONUS
	return dmg*ud.get("structure_mult",1.0)

static func safe_coverage(s: Dictionary) -> Dictionary:
	var team: int = s.team
	var forward := 1.0 if team == 0 else -1.0
	var d: Dictionary = B.CARDS.glutton_nest
	var covered := {}
	var bait_lanes := L.per_lane(false)
	var bait_pos := L.per_lane(INF)
	var has_armed_nest := false
	for b: Dictionary in s.buildings:
		if b.hp > 0 and b.team == team and b.kind == "glutton_nest" and (hidden(b) or b.get("nest_windup",0.0) > 0.0):
			has_armed_nest = true
			break
	if not has_armed_nest:
		return {"covered":covered,"bait_lanes":bait_lanes,"bait_pos":bait_pos}
	var max_approach: float = 4.5*L.CELL_SIZE.x
	for lane: int in s.get("active_lanes",[0,1,2,3,4]):
		var nests: Array[Dictionary] = []
		for b: Dictionary in s.buildings:
			if b.hp > 0 and b.team == team and b.kind == "glutton_nest" and b.cell.y == lane and (hidden(b) or b.get("nest_windup",0.0) > 0.0):
				nests.append(b)
		if nests.is_empty(): continue
		nests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.pos.x-b.pos.x)*forward > 0)
		var claimed := {}
		for b: Dictionary in nests:
			var r_nest: float = B.actor_radius(b)
			var winding: bool = b.get("nest_windup",0.0) > 0.0
			var windup_dur: float = b.nest_windup if winding else d.windup
			var t_trigger := 0.0 if winding else INF
			var close_approach := winding
			if not winding:
				for u: Dictionary in s.units:
					if not edible_unit(u) or not Giant.occupies_lane(u,lane): continue
					var u_speed: float = maxf(1.0,u.get("speed",B.CARDS.get(u.kind,{}).get("speed",40.0)))
					var edge_now: float = B.point_edge_distance(b.pos,u)
					if u.team != team:
						if claimed.has(u.get("id",-1)): continue
						if (u.pos.x-b.pos.x)*forward < -d.trigger_radius or edge_now > max_approach: continue
						t_trigger = minf(t_trigger,maxf(0.0,edge_now-d.trigger_radius)/u_speed)
					else:
						# Friendly ground troops behind an armed nest trigger it early as they walk over it.
						if (b.pos.x-u.pos.x)*forward >= -d.trigger_radius and edge_now <= d.radius+u_speed*5.0:
							t_trigger = minf(t_trigger,maxf(0.0,edge_now-d.trigger_radius)/u_speed)
			if is_inf(t_trigger): continue
			var windup_damage := 0.0
			var will_eat: Array[Dictionary] = []
			for u: Dictionary in s.units:
				if u.hp <= 0 or u.team == team or not Giant.occupies_lane(u,lane) or claimed.has(u.get("id",-1)): continue
				var ud: Dictionary = B.CARDS.get(u.kind,{})
				var u_speed: float = maxf(1.0,u.get("speed",ud.get("speed",40.0)))
				var u_range: float = u.get("range",ud.get("range",0.0))
				var ahead: float = (u.pos.x-b.pos.x)*forward
				var edge_now: float = B.point_edge_distance(b.pos,u)
				if ahead < -(u_range+r_nest+B.actor_radius(u)): continue
				var dist_at_trig: float = edge_now+u_speed*t_trigger if ahead < 0.0 else maxf(0.0,edge_now-u_speed*t_trigger)
				var stop_edge: float = u_range+r_nest
				var min_range: float = ud.get("min_range",0.0)
				if dist_at_trig >= min_range:
					var walk_time: float = maxf(0.0,dist_at_trig-stop_edge)/u_speed
					if walk_time < windup_dur:
						var active: float = windup_dur-walk_time
						var first_delay: float = maxf(0.0,u.get("cd",0.0)-walk_time) if winding else 0.0
						if first_delay < active:
							var u_interval: float = maxf(0.1,u.get("interval",ud.get("interval",1.0)))
							var hits: int = 1+int(floor((active-first_delay)/u_interval))
							var base_dmg := unit_building_damage(u,ud,false)
							var first_dmg := unit_building_damage(u,ud,true)
							windup_damage += first_dmg+maxf(0,hits-1)*base_dmg
				if edible_unit(u) and ahead >= -d.trigger_radius and (winding or edge_now <= max_approach):
					var dist_at_bite: float = maxf(minf(dist_at_trig,stop_edge),dist_at_trig-u_speed*windup_dur)
					if dist_at_bite <= d.radius:
						will_eat.append(u)
						if winding or edge_now <= 2.5*L.CELL_SIZE.x or t_trigger <= 5.0: close_approach = true
			if windup_damage < b.hp and not will_eat.is_empty():
				var cap: float = d.get("bite_cap",500.0)
				var max_bites: int = int(d.get("bite_max",4))
				if will_eat.size() > max_bites:
					will_eat.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return B.point_edge_distance(b.pos,a) < B.point_edge_distance(b.pos,c))
					will_eat = will_eat.slice(0,max_bites)
				for u: Dictionary in will_eat:
					var uid: int = u.get("id",-1)
					if uid >= 0 and u.hp <= cap:
						covered[uid] = true
						claimed[uid] = true
				if close_approach:
					bait_lanes[lane] = true
					if is_inf(bait_pos[lane]) or (b.pos.x-bait_pos[lane])*forward > 0:
						bait_pos[lane] = b.pos.x
	return {"covered":covered,"bait_lanes":bait_lanes,"bait_pos":bait_pos}

static func ai_score(c: Dictionary, s: Dictionary, _target_lane: int, defend: int, covered: Dictionary = {}) -> float:
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
	var ally_cost := 0.0
	var foe_ahead := 0.0
	var ally_behind := 0.0
	var min_foe_dist := INF
	var min_ally_dist := INF
	var cap: float = float(d.get("bite_cap",500.0))
	for u: Dictionary in s.units:
		if u.hp <= 0 or u.get("kind","") == "lord" or u.has("cell") or u.get("phased",false) or B.CARDS.get(u.kind,{}).get("flying",false): continue
		var dist: float = B.point_edge_distance(c.pos,u)
		var bite_hp: float = minf(u.hp,cap)
		if u.team != team:
			if covered.has(u.get("id",-1)): continue
			if u.get("spawn_delay",0.0) <= 0 and dist <= d.radius: foe_eat += bite_hp
			if Giant.occupies_lane(u,lane) and u.get("fear_left",0.0) <= 0:
				var ahead: float = (u.pos.x-c.pos.x)*forward
				if ahead >= -d.trigger_radius and ahead <= 150.0:
					foe_ahead += bite_hp
					min_foe_dist = minf(min_foe_dist,maxf(0.0,ahead-d.trigger_radius))
		else:
			if u.get("spawn_delay",0.0) <= 0 and dist <= d.radius:
				ally_eat += bite_hp
				var ud: Dictionary = B.CARDS.get(u.kind,{})
				ally_cost += float(ud.get("cost",0))/maxf(1.0,float(ud.get("count",1)))*(bite_hp/maxf(1.0,float(u.max_hp)))
			if Giant.occupies_lane(u,lane):
				var behind: float = (c.pos.x-u.pos.x)*forward
				if behind > -d.trigger_radius and behind <= 200.0:
					ally_behind += bite_hp
					min_ally_dist = minf(min_ally_dist,maxf(0.0,behind-d.trigger_radius))
	if defend >= 0:
		if lane != defend: return -INF
		if foe_eat >= 150.0 and foe_eat >= ally_eat and (min_foe_dist <= 35.0 or min_foe_dist <= min_ally_dist):
			return 940.0+minf(foe_eat,1500.0)*0.06
		return -INF
	if foe_eat >= 180.0 and foe_eat >= ally_eat and min_foe_dist <= 35.0:
		return 750.0+minf(foe_eat,1200.0)*0.05
	if col >= 1 and lane_nests == 0 and ally_eat <= 0 and ally_behind <= 0 and foe_ahead >= 150.0:
		return 720.0+minf(foe_ahead,1000.0)*0.05+col*10.0
	if foe_eat <= 0.0 and foe_ahead <= 0.0 and ally_eat >= 350.0 and lane_nests == 0:
		var feed_g: int = meal_gold(ally_eat*float(d.get("ally_feed_mult",2.0)),d)
		var net_g: float = float(feed_g)-ally_cost
		if net_g >= float(d.cost)+4.0:
			return 710.0+minf(net_g,16.0)*6.0
	# No passive income: never buy idle rear nests just to spend spare gold.
	return -INF

static func feed_score(c: Dictionary, s: Dictionary, data: Dictionary, lane_foe_hp: float) -> float:
	if lane_foe_hp > 0.0 or float(s.ink) >= B.MAX_INK-10.0: return -INF
	if data.type != "unit" or data.get("flying",false) or data.get("phase",false) or data.has("members") or data.get("spread",false) or data.get("pay_all",false) or data.get("shuttle",false): return -INF
	var col: int = int(c.cell.x) if int(s.team) == 0 else 8-int(c.cell.x)
	if col > 1: return -INF
	var d: Dictionary = B.CARDS.glutton_nest
	var cnt: int = mini(int(data.get("count",1)),int(d.get("bite_max",4)))
	var feed_hp: float = minf(float(data.hp),float(d.bite_cap))*float(cnt)*float(d.get("ally_feed_mult",2.0))
	var profit: float = float(meal_gold(feed_hp,d))-float(data.cost)
	if profit >= 6.0: return 770.0+minf(profit,15.0)*8.0
	return -INF
