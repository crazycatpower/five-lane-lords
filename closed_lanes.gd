extends RefCounted
# Lanes a stage leaves closed (使用者 2026-11-21：只有一路也要五段城牆，其他路要看得出不能走，而且要自然).
# Drawing only, in field space: game.gd calls draw() once after the ground. A closed lane is rough,
# stony waste — bare earth strewn with boulders and rubble (使用者 2026-11-21：收割過的農田改成亂石地) —
# with a line of big rocks along the edge of the open road beside it. Both walls still stand: five
# sections a side (a bandit camp's are palisades, see camp_art.gd). Nothing here touches the battle.
# A boulder sprite named field-boulder.png in assets/manuscript-v1/ replaces the drawn rocks once it exists.
const L = preload("res://layout.gd")
const WallArt = preload("res://wall_art.gd")
const BOULDER_PATH := "res://assets/manuscript-v1/field-boulder.png"

const EARTH := Color("a8946c")
const EARTH_LIGHT := Color("c2ae84")
const EARTH_DARK := Color("85704c")
const STONE := Color("a39c8e")
const STONE_LIGHT := Color("cfc8b8")
const STONE_DARK := Color("6f685c")
const SCRUB := Color("7d8a4a")

static func draw(g) -> void:
	var m = g.model
	if m.active_lanes.size() >= L.GRID_ROWS: return
	var sprite: Texture2D = load(BOULDER_PATH) if ResourceLoader.exists(BOULDER_PATH) else null
	for lane: int in range(L.GRID_ROWS):
		if lane in m.active_lanes: continue
		var top: float = L.GRID_ORIGIN.y+lane*L.CELL_SIZE.y
		var field := Rect2(L.GRID_ORIGIN.x,top,L.GRID_SIZE.x,L.CELL_SIZE.y)
		ground(g,field,lane)
		for team: int in range(2): WallArt.section(g,team,lane,false)
		# Scattered rubble, then the boulders, back to front so the lower ones overlap.
		var rocks: Array = []
		for i: int in range(16):
			var x: float = field.position.x+60.0+g.scenery_noise(i,lane*29+801)*(field.size.x-120.0)
			var y: float = field.position.y+24.0+g.scenery_noise(i,lane*29+802)*(field.size.y-40.0)
			rocks.append([Vector2(x,y),14.0+g.scenery_noise(i,lane*29+803)*26.0,lane*131+i])
		# Along an open road the edge is walled off by a row of big rocks.
		if lane > 0 and (lane-1) in m.active_lanes: rocks.append_array(edge_row(g,field,field.position.y+16.0,lane,811))
		if lane < L.GRID_ROWS-1 and (lane+1) in m.active_lanes: rocks.append_array(edge_row(g,field,field.end.y-10.0,lane,821))
		rocks.sort_custom(func(a: Array, b: Array) -> bool: return a[0].y < b[0].y)
		for i: int in range(60): pebble(g,field,lane,i)
		for rock: Array in rocks: boulder(g,rock[0],rock[1],rock[2],sprite)

static func edge_row(g, field: Rect2, y: float, lane: int, salt: int) -> Array:
	var out: Array = []
	var x: float = field.position.x+30.0+g.scenery_noise(lane,salt)*20.0
	var k := 0
	while x < field.end.x-30.0:
		var size: float = 15.0+g.scenery_noise(k,lane*17+salt+1)*13.0
		out.append([Vector2(x,y+(g.scenery_noise(k,lane*17+salt+2)-0.5)*8.0),size,lane*977+salt+k])
		x += size*1.5+g.scenery_noise(k,lane*17+salt+3)*10.0
		k += 1
	return out

# Bare stony earth: a dun wash with lighter and darker patches, a few cracks and tufts of scrub.
static func ground(g, field: Rect2, lane: int) -> void:
	g.draw_rect(field,EARTH)
	for i: int in range(14):
		var c := field.position+Vector2(40.0+g.scenery_noise(i,lane*23+831)*(field.size.x-80.0),20.0+g.scenery_noise(i,lane*23+832)*(field.size.y-40.0))
		g.ground_wash(c,Vector2(50.0+g.scenery_noise(i,lane*23+833)*90.0,10.0+g.scenery_noise(i,lane*23+834)*14.0),EARTH_LIGHT if i % 2 == 0 else EARTH_DARK,lane*41+i,0.45)
	for i: int in range(7):
		var p := field.position+Vector2(40.0+g.scenery_noise(i,lane*19+841)*(field.size.x-80.0),20.0+g.scenery_noise(i,lane*19+842)*(field.size.y-40.0))
		var crack := PackedVector2Array([p])
		for k: int in range(4):
			p += Vector2(10.0+g.scenery_noise(k,lane*19+i*5+843)*12.0,(g.scenery_noise(k,lane*19+i*5+844)-0.5)*10.0)
			crack.append(p)
		g.draw_polyline(crack,Color(0.30,0.22,0.12,0.35),1.2,true)
	for i: int in range(18):
		var b := field.position+Vector2(20.0+g.scenery_noise(i,lane*7+851)*(field.size.x-40.0),16.0+g.scenery_noise(i,lane*7+852)*(field.size.y-26.0))
		for k: int in range(3):
			var lean := (k-1)*3.0
			g.draw_line(b,b+Vector2(lean,-5.0-k%2*2.0),Color(SCRUB,0.75),1.3,true)

static func pebble(g, field: Rect2, lane: int, i: int) -> void:
	var p := field.position+Vector2(14.0+g.scenery_noise(i,lane*37+861)*(field.size.x-28.0),10.0+g.scenery_noise(i,lane*37+862)*(field.size.y-18.0))
	var r: float = 2.0+g.scenery_noise(i,lane*37+863)*3.5
	g.draw_circle(p+Vector2(1,1.5),r,Color(0.25,0.18,0.10,0.25))
	g.tf(p,0,Vector2(1.3,0.8))
	g.draw_circle(Vector2.ZERO,r,STONE.lerp(STONE_DARK,g.scenery_noise(i,lane*37+864)*0.6))
	g.tf()

# One boulder: a lumpy inked outline, a lit upper face, a shadow under it and a crack or two.
static func boulder(g, c: Vector2, size: float, seed_i: int, sprite: Texture2D) -> void:
	var w := size
	var h := size*0.72
	g.tf(c+Vector2(w*0.12,h*0.55),0,Vector2(1.0,0.32))
	g.draw_circle(Vector2.ZERO,w*1.05,Color(0.20,0.14,0.07,0.30))
	g.tf()
	if sprite != null:
		g.draw_texture_rect(sprite,Rect2(c-Vector2(w,h*1.25),Vector2(w*2.0,h*2.0)),false)
		return
	var pts := PackedVector2Array()
	var n := 11
	for k: int in range(n):
		var a := PI+TAU*k/n # start at the left, go over the top
		var wobble: float = 0.78+0.3*g.scenery_noise(k,seed_i)
		var flat := 0.55 if sin(a) > 0.0 else 1.0 # flattened underside where it sits on the ground
		pts.append(c+Vector2(cos(a)*w*wobble,sin(a)*h*wobble*flat))
	var tint: float = g.scenery_noise(seed_i,871)
	g.draw_colored_polygon(pts,STONE.lerp(STONE_DARK,tint*0.35))
	# The lit face: the upper-left part of the stone.
	var lit := PackedVector2Array()
	for k: int in range(n):
		var p: Vector2 = pts[k]
		if p.y <= c.y+h*0.05 and p.x <= c.x+w*0.35: lit.append(c.lerp(p,0.92))
	if lit.size() >= 3:
		lit.append(c+Vector2(-w*0.05,-h*0.05))
		lit = Geometry2D.convex_hull(lit)
		lit.remove_at(lit.size()-1) # the hull repeats its first point
		if area(lit) > 2.0: g.draw_colored_polygon(lit,Color(STONE_LIGHT,0.7))
	# Shaded underside.
	var shade := PackedVector2Array()
	for k: int in range(n):
		var p: Vector2 = pts[k]
		if p.y >= c.y-h*0.05: shade.append(p)
	shade = Geometry2D.convex_hull(shade)
	shade.remove_at(shade.size()-1)
	if area(shade) > 2.0: g.draw_colored_polygon(shade,Color(0.18,0.14,0.10,0.28))
	var rim := pts.duplicate()
	rim.append(pts[0])
	g.draw_polyline(rim,Color(g.INK,0.85),1.6,true)
	if size > 22.0:
		var a0 := c+Vector2(-w*0.1,-h*0.55)
		g.draw_polyline(PackedVector2Array([a0,a0+Vector2(w*0.12,h*0.3),a0+Vector2(w*0.05,h*0.55)]),Color(g.INK,0.55),1.1,true)

# Shoelace area: a hull squashed to a line cannot be filled.
static func area(pts: PackedVector2Array) -> float:
	if pts.size() < 3: return 0.0
	var sum := 0.0
	for i: int in range(pts.size()):
		sum += pts[i].cross(pts[(i+1)%pts.size()])
	return absf(sum)*0.5
