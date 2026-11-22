extends RefCounted
# 冒險地形的畫法（2026-11-21）：單格池塘與巨石格。純畫面；規則在 battle.gd（水格禁建、緩速；巨石禁建）。
# 冬天池塘結冰（只是畫面，緩速照舊）。
const ClosedLanes = preload("res://closed_lanes.gd")

static func pond(g, r: Rect2) -> void:
	var winter: bool = g.model.season == "winter"
	var c := r.get_center()
	var w := r.size.x*0.46
	var h := r.size.y*0.40
	var pts := PackedVector2Array()
	for k: int in range(18):
		var a := TAU*k/18.0
		var wob: float = 0.86+0.14*g.scenery_noise(k,int(r.position.x+r.position.y*7))
		pts.append(c+Vector2(cos(a)*w*wob,sin(a)*h*wob))
	g.draw_colored_polygon(pts,Color("6f7c58",0.55)) # muddy bank
	var inner := PackedVector2Array()
	for p: Vector2 in pts: inner.append(c+(p-c)*0.82)
	g.draw_colored_polygon(inner,Color("d6e4ea") if winter else Color("3f7a9c"))
	var rim := inner.duplicate()
	rim.append(inner[0])
	g.draw_polyline(rim,Color(g.INK,0.7),1.6,true)
	var t: float = g.clock
	if winter:
		for k: int in range(3):
			var a0 := c+Vector2(-w*0.4+k*w*0.3,-h*0.2+k*4.0)
			g.draw_line(a0,a0+Vector2(w*0.25,h*0.18),Color("ffffff",0.8),1.4,true)
	else:
		for k: int in range(3):
			var ph := fposmod(t*0.5+k*0.33,1.0)
			g.draw_arc(c+Vector2((k-1)*w*0.35,(k%2)*4.0),4.0+ph*14.0,0,TAU,20,Color("c8ecff",0.6*(1.0-ph)),1.3,true)
		# Reeds on the bank.
		for k: int in range(5):
			var b := c+Vector2(-w*0.95+k*w*0.12,h*0.55-k*2.0)
			g.draw_line(b,b+Vector2(-2,-16-k%2*5),Color("5b6b2e",0.9),1.5,true)
			g.draw_line(b+Vector2(-2,-16-k%2*5),b+Vector2(-2,-21-k%2*5),Color("6b4a2a"),3.0,true)
	g.draw_string(g.font,Vector2(r.position.x,r.end.y-6),"水 · 禁建",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,11,Color(g.INK,0.75))

# A rocky outcrop: two or three boulders filling the cell. Nothing can be built here.
static func outcrop(g, r: Rect2) -> void:
	var c := r.get_center()
	var seed_i := int(r.position.x*3+r.position.y)
	var s := minf(r.size.x,r.size.y)
	ClosedLanes.boulder(g,c+Vector2(-s*0.18,-s*0.08),s*0.26,seed_i,null)
	ClosedLanes.boulder(g,c+Vector2(s*0.2,s*0.02),s*0.3,seed_i+7,null)
	ClosedLanes.boulder(g,c+Vector2(-s*0.02,s*0.2),s*0.18,seed_i+13,null)
	if g.model.season == "winter":
		for k: int in range(3):
			var p := c+Vector2((k-1)*s*0.2,-s*0.16+(k%2)*s*0.1)
			g.tf(p,0,Vector2(1.0,0.4))
			g.draw_circle(Vector2.ZERO,s*0.1,Color("f4f7fa",0.9))
			g.tf()
	g.draw_string(g.font,Vector2(r.position.x,r.end.y-6),"巨石 · 禁建",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,11,Color(g.INK,0.75))

# ---------------- map mechanics (map_mech.gd) ----------------
const MapMech = preload("res://map_mech.gd")
const L = preload("res://layout.gd")
const PORTAL_COLORS := [Color("8f5bd6"),Color("2f9c8f"),Color("d68a2f")]

static func cell_rect(c: Vector2i) -> Rect2:
	return Rect2(L.GRID_ORIGIN+Vector2(c)*L.CELL_SIZE,L.CELL_SIZE)

# Ground marks under the troops: slope shading, mud, lava, runes, portals, sluice gates, falling rocks.
static func mechanics(g) -> void:
	var m = g.model
	var s: Dictionary = m.mech
	if s.is_empty(): return
	var t: float = g.clock
	var grid := Rect2(L.GRID_ORIGIN,L.GRID_SIZE)
	if s.has("slope_high"):
		# Contour lines climbing toward the high side, darker at the foot of the hill.
		var high_right: bool = int(s.slope_high) == 1
		for k: int in range(8):
			var x: float = grid.position.x+grid.size.x*(k+0.5)/8.0
			var up: float = (k+0.5)/8.0 if high_right else 1.0-(k+0.5)/8.0
			g.draw_rect(Rect2(x-grid.size.x/16.0,grid.position.y,grid.size.x/8.0,grid.size.y),Color(0.35,0.25,0.12,0.10*(1.0-up)))
			var pts := PackedVector2Array()
			for i: int in range(13):
				var y: float = grid.position.y+grid.size.y*i/12.0
				pts.append(Vector2(x+sin(i*0.9+k)*6.0,y))
			g.draw_polyline(pts,Color(0.35,0.24,0.12,0.22),1.4,true)
		var arrow_x: float = grid.end.x-60.0 if high_right else grid.position.x+60.0
		g.draw_string(g.font,Vector2(arrow_x-50,grid.position.y+18),"坡頂 ▲" ,HORIZONTAL_ALIGNMENT_CENTER,100,13,Color(g.INK,0.7))
	for c: Vector2i in s.get("mud_cells",[]):
		if not c.y in m.active_lanes: continue
		var r := cell_rect(c).grow(-8)
		g.ground_wash(r.get_center(),r.size*0.5,Color("5d4a2e"),c.x*7+c.y,0.75)
		for k: int in range(4):
			var p: Vector2 = r.position+Vector2(14+k*24,r.size.y*0.5+sin(k*1.7)*12)
			g.draw_arc(p,5.0,PI,TAU,8,Color("3b2c18",0.6),1.4,true)
		g.draw_string(g.font,Vector2(r.position.x,r.end.y-2),"泥沼 ×0.7",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,11,Color(g.INK,0.75))
	for c: Vector2i in s.get("lava_cells",[]):
		if not c.y in m.active_lanes: continue
		var r := cell_rect(c).grow(-6)
		g.draw_rect(r,Color("3a1c12",0.85))
		var glow := 0.55+0.45*sin(t*3.0+c.x)
		for k: int in range(5):
			var a: Vector2 = r.position+Vector2(8+k*20,8+(k%2)*30)
			g.draw_polyline(PackedVector2Array([a,a+Vector2(10,18),a+Vector2(4,34),a+Vector2(14,r.size.y-24)]),Color(1.0,0.45+0.3*glow,0.1,0.9),3.0,true)
		g.draw_rect(r,Color(1.0,0.4,0.1,0.12*glow))
		g.draw_string(g.font,Vector2(r.position.x,r.end.y-4),"熔岩 · 禁建",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,11,Color("ffd9a0"))
	for c: Vector2i in s.get("rune_cells",[]):
		if not c.y in m.active_lanes: continue
		var ctr := cell_rect(c).get_center()
		var pulse := 0.5+0.5*sin(t*2.0+c.x+c.y)
		g.draw_arc(ctr,34.0,0,TAU,40,Color("5a6fd6",0.55+0.3*pulse),2.4,true)
		g.draw_arc(ctr,26.0,t*0.6,t*0.6+TAU*0.8,30,Color("9fb2ff",0.6),1.6,true)
		for k: int in range(6):
			var a := t*0.4+k*TAU/6.0
			g.draw_line(ctr+Vector2.from_angle(a)*20.0,ctr+Vector2.from_angle(a)*30.0,Color("c8d2ff",0.8),1.6,true)
		g.draw_string(g.font,ctr+Vector2(-40,48),"符文 射程+1",HORIZONTAL_ALIGNMENT_CENTER,80,11,Color("3f4f9e"))
	var pi := 0
	for pair: Array in s.get("portals",[]):
		var col: Color = PORTAL_COLORS[pi % PORTAL_COLORS.size()]
		pi += 1
		for c: Vector2i in pair:
			if not c.y in m.active_lanes: continue
			var ctr := cell_rect(c).get_center()
			g.tf(ctr,0,Vector2(0.7,1.0))
			for k: int in range(3):
				g.draw_arc(Vector2.ZERO,30.0-k*8.0,t*(2.0+k),t*(2.0+k)+TAU*0.7,24,Color(col,0.85-k*0.2),3.0,true)
			g.tf()
		if pair[0].y in m.active_lanes and pair[1].y in m.active_lanes:
			var a: Vector2 = cell_rect(pair[0]).get_center()
			var b: Vector2 = cell_rect(pair[1]).get_center()
			g.draw_dashed_line(a,b,Color(col,0.35),1.5,8.0)
	if s.has("sluice"):
		var sl: Dictionary = s.sluice
		var now: int = int(sl.lanes[sl.index])
		var next: int = int(sl.lanes[(int(sl.index)+1) % sl.lanes.size()])
		for lane in sl.lanes:
			if not int(lane) in m.active_lanes: continue
			var y: float = L.cell_center(Vector2i(0,int(lane))).y
			var gate := Rect2(grid.position.x+grid.size.x*0.5-14,y-L.CELL_SIZE.y*0.5+4,28,16)
			g.draw_rect(gate,Color("6b4a2a"))
			g.draw_rect(gate,Color(g.INK,0.8),false,1.2)
			var tag := "開閘" if int(lane) == now else ("%d 秒後淹水" % ceili(float(sl.timer)) if int(lane) == next else "")
			if not tag.is_empty(): g.draw_string(g.font,Vector2(gate.end.x+4,gate.end.y-2),tag,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("1f4663") if int(lane) == now else Color("9b2f2f"))
	if s.has("eruption"):
		var er: Dictionary = s.eruption
		for r: Dictionary in er.blocked:
			if not r.cell.y in m.active_lanes: continue
			var rr := cell_rect(r.cell)
			ClosedLanes.boulder(g,rr.get_center()+Vector2(0,6),24.0,r.cell.x*5+r.cell.y,null)
			g.draw_string(g.font,Vector2(rr.position.x,rr.end.y-6),"落石 %d" % ceili(float(r.left)),HORIZONTAL_ALIGNMENT_CENTER,rr.size.x,11,Color(g.INK,0.75))
		for f: Dictionary in er.falling:
			var ctr := cell_rect(f.cell).get_center()
			var k: float = 1.0-float(f.left)/MapMech.ROCK_WARN
			g.draw_circle(ctr,20.0+k*26.0,Color(0,0,0,0.18+0.25*k))
			g.draw_arc(ctr,46.0,0,TAU,32,Color(0.85,0.2,0.1,0.5+0.5*sin(t*14.0)),2.5,true)
			var rock := ctr+Vector2(0,-260.0*(1.0-k))
			ClosedLanes.boulder(g,rock,16.0,int(f.cell.x*3+f.cell.y),null)

# Lightning about to strike, the bolt itself, and the countdown before the wind turns.
static func storms(g) -> void:
	var m = g.model
	var s: Dictionary = m.mech
	var t: float = g.clock
	if s.has("storm"):
		for f: Dictionary in s.storm.falling:
			var r := cell_rect(f.cell)
			var blink := 0.5+0.5*sin(t*22.0)
			g.draw_rect(r.grow(-4),Color(1.0,0.95,0.5,0.12+0.25*blink))
			g.draw_rect(r.grow(-4),Color(0.95,0.8,0.2,0.8),false,2.0)
		for f: Dictionary in s.storm.flash:
			var c := cell_rect(f.cell).get_center()
			var top := Vector2(c.x+12.0,L.GRID_ORIGIN.y-10.0)
			var pts := PackedVector2Array([top])
			var k := 0
			while pts[pts.size()-1].y < c.y:
				k += 1
				pts.append(Vector2(c.x+(-10.0 if k % 2 == 0 else 10.0),minf(c.y,top.y+k*38.0)))
			g.draw_polyline(pts,Color(1.0,1.0,0.85,clampf(float(f.left)/0.4,0.0,1.0)),4.0,true)
			g.draw_circle(c,30.0,Color(1.0,1.0,0.8,0.5*clampf(float(f.left)/0.4,0.0,1.0)))
	if s.has("wind_shift") and float(s.wind_shift.timer) <= 5.0:
		for lane in m.wind_lanes:
			var y: float = L.cell_center(Vector2i(0,int(lane))).y
			g.draw_string(g.font,Vector2(L.GRID_ORIGIN.x+L.GRID_SIZE.x*0.5-90,y+6),"%d 秒後風向轉變" % ceili(float(s.wind_shift.timer)),HORIZONTAL_ALIGNMENT_CENTER,180,15,Color("9b2f2f"))

# Mist over the far side of the field, and blizzard whiteout; drawn above the troops.
static func fog(g) -> void:
	var m = g.model
	if m.mech.has("blizzard") and float(m.mech.blizzard.left) > 0.0:
		var grid := Rect2(L.GRID_ORIGIN,L.GRID_SIZE)
		var left: float = float(m.mech.blizzard.left)
		var a: float = clampf(minf(left,MapMech.BLIZZARD_TIME-left),0.0,1.0)
		g.draw_rect(grid,Color(0.92,0.95,1.0,0.32*a))
		var t: float = g.clock
		for i: int in range(90):
			var p := Vector2(grid.position.x+fposmod(g.scenery_noise(i,981)*grid.size.x-t*160.0,grid.size.x),grid.position.y+fposmod(g.scenery_noise(i,982)*grid.size.y+t*60.0,grid.size.y))
			g.draw_line(p,p+Vector2(-12,4),Color(1,1,1,0.8*a),1.6,true)
		g.draw_string(g.font,Vector2(grid.position.x,grid.position.y+40),"暴風雪 · 地面部隊減速",HORIZONTAL_ALIGNMENT_CENTER,grid.size.x,20,Color(0.25,0.32,0.45,0.9*a))
	if not m.mech.has("fog_col"): return
	var col := int(m.mech.fog_col)
	var x0: float = L.GRID_ORIGIN.x+col*L.CELL_SIZE.x
	var grid := Rect2(L.GRID_ORIGIN,L.GRID_SIZE)
	var r := Rect2(x0,grid.position.y,grid.end.x-x0,grid.size.y)
	var t: float = g.clock
	for k: int in range(10):
		var a := float(k)/10.0
		g.draw_rect(Rect2(r.position.x+r.size.x*a,r.position.y,r.size.x/10.0+1.0,r.size.y),Color(0.78,0.80,0.82,0.10+0.30*a))
	for i: int in range(14):
		var p := Vector2(r.position.x+fposmod(g.scenery_noise(i,971)*r.size.x+t*8.0,r.size.x),r.position.y+g.scenery_noise(i,972)*r.size.y)
		g.tf(p,0,Vector2(1.8,0.6))
		g.draw_circle(Vector2.ZERO,40.0+g.scenery_noise(i,973)*30.0,Color(0.86,0.88,0.9,0.22))
		g.tf()
	g.draw_string(g.font,Vector2(x0+8,grid.position.y+18),"濃霧",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(g.INK,0.6))
