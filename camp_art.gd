extends RefCounted
# A bandit camp in place of a castle (使用者 2026-11-21：除了城堡還有營地素材). Drawing only.
# A stage marks the camp side with model meta "camp_team"; that side gets tents, a campfire and
# stores behind its walls, and each lane's wall is a log palisade instead of masonry. Rules are the
# castle's: a palisade section has the same hit points and falls the same way.
# Placeholder art until the requested pieces arrive (assets/manuscript-v1/tutorial-scenery-prompts.json):
# bandit-tent.png and the small-objects sheet; the palisade is drawn in ink. camp-backdrop.png, palisade.png and
# palisade-broken.png in that folder are used automatically once they exist.
const L = preload("res://layout.gd")
const ART = preload("res://manuscript_art.gd")
const TENT = preload("res://assets/manuscript-v1/bandit-tent.png")
const BACKDROP_PATH := "res://assets/manuscript-v1/camp-backdrop.png"
const BROKEN_PATH := "res://assets/manuscript-v1/palisade-broken.png"
const INTACT_PATH := "res://assets/manuscript-v1/palisade.png"
const EARTH := Color(0.62,0.52,0.34,0.55)
const WOOD := Color("8a6a3e")
const WOOD_DARK := Color("5b4326")
const STONE := Color("b9a882")

static func is_camp(g, team: int) -> bool:
	return g.model != null and g.model.has_meta("camp_team") and int(g.model.get_meta("camp_team")) == team

# The camp behind the walls; returns false (draw the castle as usual) when this side is not a camp.
static func backdrop(g, team: int) -> bool:
	if not is_camp(g, team): return false
	var area: Rect2 = L.CASTLE_RECTS[team]
	var dir := 1.0 if team == 0 else -1.0
	var ground := Rect2(area.position.x-30.0 if team == 1 else area.position.x,area.position.y,area.size.x+30.0,area.size.y)
	g.draw_rect(ground,EARTH)
	if ResourceLoader.exists(BACKDROP_PATH):
		var art: Texture2D = load(BACKDROP_PATH)
		if team == 1: g.draw_texture_rect(art,area,false)
		else: g.draw_mirrored(art,area,Color.WHITE)
		campfire(g,Vector2(area.position.x+area.size.x*0.5,area.position.y+area.size.y*0.72))
		return true
	# Three tents down the camp (kept inside the page: the castle picture runs past its edge, tents may not),
	# the middle one set back, a fire and the loot between them.
	var inner: float = L.gate_icon_x(team)-dir*60.0 # just behind the palisade
	var tx: float = inner if team == 1 else inner-150.0
	tent(g,Rect2(tx,area.position.y+12.0,150.0,137.0),dir)
	tent(g,Rect2(tx+(28.0 if team == 1 else -28.0),area.position.y+214.0,128.0,117.0),dir)
	tent(g,Rect2(tx,area.position.y+400.0,150.0,137.0),dir)
	campfire(g,Vector2(inner-dir*34.0,area.position.y+366.0))
	for spot: Array in [[4,Vector2(26,184),36.0],[3,Vector2(112,180),34.0],[4,Vector2(100,556),34.0],[3,Vector2(28,560),36.0]]:
		var p := Vector2(inner-dir*spot[1].x,area.position.y+spot[1].y)
		g.draw_circle(p+Vector2(4,spot[2]*0.42),spot[2]*0.42,Color(0.14,0.10,0.05,0.22))
		g.draw_texture_rect(ART.object_icon(spot[0]),Rect2(p-Vector2(spot[2],spot[2])*0.5,Vector2(spot[2],spot[2])),false)
	return true

static func tent(g, r: Rect2, dir: float) -> void:
	g.draw_circle(r.position+Vector2(r.size.x*0.5,r.size.y*0.92),r.size.x*0.36,Color(0.14,0.10,0.05,0.20))
	if dir < 0.0: g.draw_mirrored(TENT,r,Color.WHITE)
	else: g.draw_texture_rect(TENT,r,false)

static func campfire(g, at: Vector2) -> void:
	for i: int in range(7):
		var a := TAU*i/7.0
		g.draw_circle(at+Vector2(cos(a)*15.0,sin(a)*6.0+4.0),4.0,STONE)
		g.draw_arc(at+Vector2(cos(a)*15.0,sin(a)*6.0+4.0),4.0,0,TAU,8,Color(g.INK,0.7),1.0,true)
	var t: float = g.clock
	for k: int in range(3):
		var sway := sin(t*6.0+k*2.1)*3.0
		var h := 20.0+6.0*sin(t*9.0+k)
		var base_x := at.x+(k-1)*6.0
		g.draw_colored_polygon(PackedVector2Array([Vector2(base_x-6,at.y+2),Vector2(base_x+sway,at.y-h),Vector2(base_x+6,at.y+2)]),Color(0.95,0.55,0.15,0.85) if k != 1 else Color(1.0,0.82,0.30,0.9))
	for k: int in range(3): # smoke drifting up and away
		var life := fposmod(t*0.35+k/3.0,1.0)
		g.draw_circle(at+Vector2(sin(t+k)*6.0+life*10.0,-30.0-life*60.0),5.0+life*9.0,Color(0.45,0.42,0.38,0.30*(1.0-life)))

# One lane's palisade: sharpened logs lashed together, standing where the masonry would.
static func section(g, team: int, lane: int, broken: bool) -> void:
	var dir := 1.0 if team == 0 else -1.0
	var x: float = L.gate_icon_x(team)+dir
	var top: float = L.GRID_ORIGIN.y+lane*L.CELL_SIZE.y
	var h: float = L.CELL_SIZE.y
	g.draw_rect(Rect2(minf(x-dir*29.0,x-dir*91.0),top,62.0,h),EARTH) # trodden ground inside
	if broken:
		if ResourceLoader.exists(BROKEN_PATH):
			g.draw_texture_rect(load(BROKEN_PATH),Rect2(x-34.0,top-6.0,68.0,h+12.0),false)
			return
		for i: int in range(6): # stakes knocked flat across the gap
			var p := Vector2(x+(g.scenery_noise(i,lane*7+team*3+611)-0.5)*56.0,top+12.0+g.scenery_noise(i,lane*7+team*3+612)*(h-24.0))
			var ang: float = (g.scenery_noise(i,lane*7+team*3+613)-0.5)*2.4
			var v := Vector2(cos(ang),sin(ang))*22.0
			g.draw_line(p-v,p+v,g.INK,6.0,true)
			g.draw_line(p-v,p+v,WOOD,4.0,true)
		return
	g.draw_polygon(PackedVector2Array([Vector2(x+dir*20.0,top),Vector2(x+dir*44.0,top+10.0),Vector2(x+dir*44.0,top+h+10.0),Vector2(x+dir*20.0,top+h)]),PackedColorArray([Color(0.14,0.10,0.05,0.40),Color(0.14,0.10,0.05,0.0),Color(0.14,0.10,0.05,0.0),Color(0.14,0.10,0.05,0.40)]))
	if ResourceLoader.exists(INTACT_PATH): # painted section, once it exists
		g.draw_texture_rect(load(INTACT_PATH),Rect2(x-29.0,top,58.0,h),false)
		return
	# A run of sharpened logs seen from above and behind each other: every log's point peeks over the
	# one behind it, so the section reads as a timber wall standing across the lane's end.
	var count := 9
	for k: int in range(count):
		var cy: float = top-6.0+k*(h+4.0)/count
		var jitter: float = (g.scenery_noise(k,lane*11+team*5+621)-0.5)*6.0
		var w: float = 30.0
		var body := Rect2(x-w*0.5+jitter,cy,w,22.0)
		var shade: Color = WOOD.darkened(0.12*g.scenery_noise(k,lane*11+team*5+622))
		g.draw_colored_polygon(PackedVector2Array([body.position,Vector2(body.position.x+w*0.5,cy-12.0),Vector2(body.end.x,cy),body.end,Vector2(body.position.x,body.end.y)]),shade)
		g.draw_polyline(PackedVector2Array([Vector2(body.position.x,body.end.y),body.position,Vector2(body.position.x+w*0.5,cy-12.0),Vector2(body.end.x,cy),body.end]),g.INK,1.6,true)
		g.draw_line(Vector2(body.position.x+w*0.5,cy-12.0),Vector2(body.position.x+w*0.5,body.end.y),Color(WOOD_DARK,0.6),1.4,true)
	for band: float in [0.3,0.7]: # rope lashings across the logs
		var y: float = top+h*band
		g.draw_line(Vector2(x-17.0,y),Vector2(x+17.0,y+3.0),Color("c9b27a"),2.6,true)
		g.draw_line(Vector2(x-17.0,y),Vector2(x+17.0,y+3.0),Color(g.INK,0.5),0.8,true)
