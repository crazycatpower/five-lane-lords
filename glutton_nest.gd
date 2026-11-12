extends RefCounted
const B = preload("res://balance.gd")

static func hidden(actor: Dictionary) -> bool:
	return actor.get("kind","") == "glutton_nest" and actor.get("digest_left",0.0) <= 0.0

static func gold_for_health(health: float) -> int:
	var d: Dictionary = B.CARDS.glutton_nest
	# Arithmetic progression: 100, 220, 360, 520... cumulative HP.
	var half_step: float = d.gold_step / 2.0
	var linear: float = d.gold_first-half_step
	return maxi(0,int(floor((sqrt(linear*linear+4.0*half_step*maxf(0.0,health))-linear)/(2.0*half_step))))

static func edible(u: Dictionary) -> bool:
	return u.get("kind","") != "lord" and not u.has("cell") and u.hp > 0 and u.get("spawn_delay",0.0) <= 0 and not u.get("phased",false) and not B.CARDS.get(u.kind,{}).get("flying",false)

static func update(m, b: Dictionary, dt: float) -> bool:
	if b.kind != "glutton_nest": return false
	if b.hp <= 0: return true
	var d: Dictionary = B.CARDS.glutton_nest
	if b.get("digest_left",0.0) > 0:
		b.digest_left = maxf(0.0,b.digest_left-dt)
		if b.digest_left <= 0: m.build_lookups()
		return true
	var victims: Array[Dictionary] = []
	var triggered := false
	for u: Dictionary in m.units:
		if not edible(u): continue
		var distance: float = u.pos.distance_to(b.pos)
		if distance <= d.trigger_radius: triggered = true
		if distance <= d.radius: victims.append(u)
	if not triggered: return true
	b.digest_left = d.digest_time
	var health := 0.0
	for u: Dictionary in victims:
		health += u.hp
		# Sacrifice bypasses armour, shields and lethal-hit rescue, but preserves death accounting.
		m.damage(u,u.hp,b.team,b.kind,{},true)
		m.link(u.pos,b.pos,b.team,"devour")
	b.last_gold = gold_for_health(health)
	m.gain_ink(b.team,b.last_gold)
	m.event("ink",b.pos,b.team)
	m.build_lookups()
	return true

static func draw(g, b: Dictionary, pos: Vector2) -> void:
	if hidden(b):
		# Owner/observer hint only. Opposing concealed nests are omitted by the scene loop.
		g.draw_arc(pos+Vector2(0,15),24,0,TAU,24,Color(g.RED if b.team == 0 else g.BLUE,0.35),1.0,true)
		return
	var age: float = B.CARDS.glutton_nest.digest_time-b.digest_left
	var rect: Rect2 = g.actor_rect("glutton_nest")
	var texture_kind := "glutton_nest" if age < 0.3 else "glutton_nest_closed"
	g.draw_texture_rect(g.art(texture_kind,b.team),Rect2(pos+rect.position,rect.size),false)
	g.bar(Rect2(pos+Vector2(-28,32),Vector2(56,4)),b.digest_left,B.CARDS.glutton_nest.digest_time,Color("c8962c"))
