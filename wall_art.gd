extends RefCounted
# How each lane's stretch of curtain wall is drawn (2026-11-12). The painted masonry stays
# (assets/manuscript-v1/lane-wall*.png); around it this adds what a flat strip lacked:
#   - its real proportions and the castle's muted tone, so wall and castle read as one fortress
#   - a shadow on the field side and a packed-earth courtyard behind: the wall has height and an inside
#   - a tower where two lanes meet, cut from the castle painting itself (same hand, same roofs, the
#     team's colour through the usual palette swap): the wall gains height and the side reads at a glance
#   - rubble spilling out of a breach
# Drawing only; game.gd draw_wall_section() calls section() for every lane and side.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

const WIDTH := 58.0
const SHADE := Color(0.86,0.83,0.77)
const STONE := Color("cdbb93")
const EARTH := Color(0.66,0.56,0.38,0.40)
# "flags": one painted pennant per standing stretch. "towers": a tower head on every joint.
static var style := "flags"

# +1 for the red wall (enemy to the right), -1 for blue. Positions are mirrored by hand rather than
# by a flipped transform, so flags and shadows still fall the same way on both sides.
static func facing(team: int) -> float:
	return 1.0 if team == 0 else -1.0

static func centre_x(team: int) -> float:
	return L.gate_icon_x(team)+facing(team)*1.0

static func section(g, team: int, lane: int, broken: bool) -> void:
	var m = g.model
	var dir := facing(team)
	var x := centre_x(team)
	var top: float = L.GRID_ORIGIN.y+lane*L.CELL_SIZE.y
	var height: float = L.CELL_SIZE.y
	# Courtyard: trodden earth between the castle and the wall.
	var inner: float = x-dir*WIDTH*0.5
	var yard := Rect2(minf(inner,inner-dir*62.0),top,62.0,height)
	var far: float = inner-dir*96.0
	g.draw_rect(yard,EARTH)
	g.draw_polygon(PackedVector2Array([Vector2(far,top),Vector2(inner-dir*62.0,top),Vector2(inner-dir*62.0,top+height),Vector2(far,top+height)]),PackedColorArray([Color(EARTH,0.0),EARTH,EARTH,Color(EARTH,0.0)]))
	for i: int in range(5):
		var p := yard.position+Vector2(g.scenery_noise(i,lane*13+team*7+401)*yard.size.x,g.scenery_noise(i,lane*17+team*5+402)*height)
		g.draw_arc(p,2.5+g.scenery_noise(i,403)*2.5,0.3,PI+0.6,8,Color(g.INK,0.22),1.2,true)
	# Shadow thrown onto the field: the wall stands taller than the soldiers.
	var outer: float = x+dir*WIDTH*0.5
	var dark := Color(0.14,0.10,0.05,0.44)
	var clear := Color(0.14,0.10,0.05,0.0)
	g.draw_polygon(PackedVector2Array([Vector2(outer,top),Vector2(outer+dir*26,top+10),Vector2(outer+dir*26,top+height+10),Vector2(outer,top+height)]),PackedColorArray([dark,clear,clear,dark]))
	# The painted masonry, mirrored for blue.
	g.tf(Vector2(x,top),0,Vector2(dir,1))
	g.draw_texture_rect(g.art("gate_broken" if broken else "gate",team),Rect2(-WIDTH*0.5,0,WIDTH,height),false,SHADE)
	if not broken:
		# Dark-ink cracks spread as the wall weakens, by day as well as by night.
		var ratio: float = clampf(m.gates[team][lane]/B.GATE_HP,0.0,1.0)
		if ratio < 0.75:
			var crack := Color(g.INK,lerpf(0.5,0.9,1.0-ratio))
			g.draw_polyline(PackedVector2Array([Vector2(-10,height*0.32),Vector2(3,height*0.42),Vector2(-4,height*0.54),Vector2(14,height*0.63)]),crack,1.8,true)
			if ratio < 0.45:
				g.draw_polyline(PackedVector2Array([Vector2(18,height*0.24),Vector2(5,height*0.36),Vector2(15,height*0.51)]),crack,1.6,true)
				g.draw_polyline(PackedVector2Array([Vector2(-19,height*0.66),Vector2(-5,height*0.74),Vector2(8,height*0.86)]),crack,1.6,true)
	g.tf()
	if broken: rubble(g,Vector2(x,top+height*0.5),dir,lane*31+team*17)
	# Turrets where this stretch meets the next one (and capping a wall that ends mid-field).
	if style == "towers":
		if lane > 0: turret(g,Vector2(x,top),team)
		if lane < L.GRID_ROWS-1 and not (lane+1) in m.active_lanes: turret(g,Vector2(x,top+height),team)
	elif not broken: pennant(g,Vector2(x-dir*9,top+height*0.5+16),team)

# The team's pennant flying over a standing stretch (cut from the castle painting; gone once the
# stretch is breached). It streams toward the enemy and stirs a little.
const FLAG_SOURCE := Rect2(572,262,126,86)
static func pennant(g, foot: Vector2, team: int) -> void:
	var dir := facing(team)
	var sway: float = sin(g.clock*2.6+foot.y*0.04)*0.07
	g.draw_line(foot,foot+Vector2(0,-30),g.INK,2.4,true)
	g.tf(foot+Vector2(0,-30),sway*dir,Vector2(dir,1))
	g.draw_texture_rect_region(g.art("castle_wall",team),Rect2(-7,-30,44,30),FLAG_SOURCE)
	g.tf()
	g.draw_circle(foot,2.6,g.INK)

# Fallen stones in the gap and spilling toward the field.
static func rubble(g, at: Vector2, dir: float, salt: int) -> void:
	for i: int in range(13):
		var spread: float = g.scenery_noise(i,salt+411)
		var p := at+Vector2(dir*(-20.0+spread*62.0),(g.scenery_noise(i,salt+412)-0.5)*44.0)
		var r: float = 3.0+g.scenery_noise(i,salt+413)*4.5
		g.draw_circle(p+Vector2(1.5,2),r,Color(0.14,0.10,0.05,0.25))
		g.draw_circle(p,r,STONE.darkened(0.08+0.22*g.scenery_noise(i,salt+414)))
		g.draw_arc(p,r,0,TAU,10,Color(g.INK,0.75),1.2,true)

# A tower standing on the joint between two stretches: the right-hand tower head of the castle
# painting (roof, pennant, crenellated drum), drawn small. Blue gets the recoloured, mirrored one.
const TOWER_SOURCE := Rect2(480,268,224,440)
const TOWER_SIZE := Vector2(42,82)
static func turret(g, at: Vector2, team: int) -> void:
	var dir := facing(team)
	g.tf(at+Vector2(5,20),0,Vector2(1,0.5))
	g.draw_circle(Vector2.ZERO,24,Color(0.14,0.10,0.05,0.32))
	g.tf()
	g.tf(at,0,Vector2(dir,1))
	g.draw_texture_rect_region(g.art("castle_wall",team),Rect2(Vector2(-TOWER_SIZE.x*0.5,-TOWER_SIZE.y+24),TOWER_SIZE),TOWER_SOURCE,SHADE.lightened(0.12))
	g.draw_line(Vector2(-TOWER_SIZE.x*0.5+2,24),Vector2(TOWER_SIZE.x*0.5-2,24),Color(g.INK,0.85),2.2,true)
	g.tf()
