extends RefCounted
# Presentation only: never consumes simulation RNG or mutates battle actors/events.

# Shared expansion feedback. Call before the legacy event switch; no actor state is changed.
static func event(g, e: Dictionary, progress: float) -> bool:
	if not g.fx_enabled: return false
	if e.kind == "charge_impact":
		var center: Vector2 = e.pos+Vector2(0,-18)
		var face: float = e.get("face",1.0)
		var alpha := 1.0-progress
		var radius: float = e.get("radius",26.0)*(0.3+progress)
		g.draw_arc(center,radius,-PI*0.55 if face > 0 else PI*0.45,PI*0.55 if face > 0 else PI*1.55,20,Color("e2b23a",alpha),4.0*alpha+1,true)
		for i: int in range(5):
			var angle: float = (i-2)*0.3+(0.0 if face > 0 else PI)
			var ray := Vector2.from_angle(angle)
			g.draw_line(center+ray*radius*0.6,center+ray*(radius+12),Color("fff0b2",alpha),2,true)
		return true
	if e.kind == "support_pulse":
		var style: String = e.get("style","")
		var color: Color = {"heal":Color("6eab69"),"repair":Color("c4a75f"),"shield":Color("7ac7e0"),"armor":Color("aaa7a0"),"haste":Color("e2b23a"),"range":Color("a497df"),"cleanse":Color("dbd5ac")}.get(style,Color("b9a3d6"))
		var radius: float = minf(e.get("radius",60.0),85.0)*(0.2+progress*0.8)
		var points := PackedVector2Array()
		for i: int in range(33):
			var angle := i*TAU/32
			points.append(e.pos+Vector2(cos(angle)*radius,sin(angle)*radius*0.38))
		g.draw_polyline(points,Color(color,(1.0-progress)*0.65),2,true)
		var top: Vector2 = e.pos+Vector2(0,-30-progress*16)
		if style in ["armor","shield"]:
			g.draw_polyline(PackedVector2Array([top+Vector2(-6,-5),top+Vector2(6,-5),top+Vector2(5,3),top+Vector2(0,8),top+Vector2(-5,3),top+Vector2(-6,-5)]),Color(color,1-progress),2,true)
		elif style in ["haste","range"]:
			var face := 1.0 if e.team == 0 else -1.0
			for i: int in range(2):
				var p := top+Vector2(i*8*face,0)
				g.draw_polyline(PackedVector2Array([p+Vector2(-4*face,-5),p+Vector2(3*face,0),p+Vector2(-4*face,5)]),Color(color,1-progress),2,true)
		else:
			g.draw_line(top+Vector2(-5,0),top+Vector2(5,0),Color(color,1-progress),2,true)
			g.draw_line(top+Vector2(0,-5),top+Vector2(0,5),Color(color,1-progress),2,true)
		return true
	return false

static func lightning(g, e: Dictionary, progress: float) -> void:
	var delta: Vector2 = e.to-e.pos
	var normal := delta.normalized().orthogonal()
	var points := PackedVector2Array([e.pos])
	for i: int in range(1,12):
		var offset := sin(i*17.3+floor(progress*8)*2.7)*minf(13,delta.length()*0.18)
		points.append(e.pos+delta*(i/12.0)+normal*offset)
	points.append(e.to)
	var width := maxf(1,4.5-e.get("hop",0)*0.8)
	g.draw_polyline(points,Color(0.35,0.65,1.0,(1-progress)*0.35),width+5,true)
	g.draw_polyline(points,Color(0.85,0.95,1.0,1-progress*0.8),width,true)

static func dust(g, pos: Vector2, progress: float) -> void:
	for i: int in range(8):
		var a := i*TAU/8
		g.draw_circle(pos+Vector2(cos(a)*30*progress,sin(a)*9*progress-12*progress),2+4*progress,Color(0.60,0.48,0.33,(1-progress)*0.6))

static func summon(g, pos: Vector2, progress: float) -> void:
	var gold := Color(0.98,0.79,0.32,1-progress)
	var points := PackedVector2Array()
	for i: int in range(33):
		var a := i*TAU/32
		points.append(pos+Vector2(cos(a)*(15+25*progress),sin(a)*(6+9*progress)))
	g.draw_polyline(points,gold,3,true)
	# Curving horn with a flared bell, entirely pictorial.
	var horn := pos+Vector2(-5,-10-progress*20)
	g.draw_arc(horn,10,0.1,PI*0.85,16,gold,3,true)
	g.draw_line(horn+Vector2(10,-4),horn+Vector2(13,6),gold,3,true)
	for i: int in range(3):
		g.draw_arc(horn+Vector2(13,0),7+i*6,-0.6,0.6,10,Color(gold, (1-progress)*0.6),1.5,true)

static func spell(g, e: Dictionary, progress: float) -> bool:
	var kind: String = e.get("card","")
	if kind == "sacrifice":
		var r: float = e.get("radius",70.0)*(0.85+progress*0.15)
		var red := Color(0.65,0.07,0.13,(1-progress)*0.8)
		g.draw_circle(e.pos,r,Color(red,red.a*0.14))
		g.draw_arc(e.pos,r,0,TAU,48,red,3,true)
		g.draw_arc(e.pos,r*0.78,0,TAU,48,red,1.5,true)
		for i: int in range(6):
			var a := i*TAU/6
			g.draw_line(e.pos+Vector2.from_angle(a)*r*0.65,e.pos+Vector2.from_angle(a+TAU/3)*r*0.65,red,2,true)
		return true
	if kind == "dread_howl":
		for i: int in range(3):
			var p := clampf(progress*1.4-i*0.15,0,1)
			g.draw_arc(e.pos,e.radius*p,0,TAU,48,Color(0.18,0.10,0.22,(1-p)*0.7),3,true)
		return true
	if kind == "borrowed_bones":
		var center: Vector2 = e.pos
		var r: float = e.get("radius",60.0)*(0.75+progress*0.25)
		var alpha := (1.0-progress)*0.85
		g.draw_arc(center,r,0,TAU,32,Color("7b4fa0",alpha*0.75),2.5,true)
		for i: int in range(6):
			var a := i*TAU/6+progress*0.8
			var p: Vector2 = center+Vector2(cos(a)*r*0.6,sin(a)*r*0.25-progress*28)
			g.draw_circle(p,3.0*(1.0-progress*0.5),Color("e4dbc8",alpha))
		return true
	if kind == "grave_exchange":
		var center: Vector2 = e.pos
		var r: float = e.get("radius",100.0)*clampf(1.15-progress*0.5,0.4,1.15)
		var alpha := (1.0-progress)*0.85
		g.draw_circle(center,r*0.65,Color("7b4fa0",alpha*0.16))
		g.draw_arc(center,r,0,TAU,36,Color("b9a3d6",alpha),2.5,true)
		for i: int in range(5):
			var a := i*TAU/5-progress*1.4
			g.draw_circle(center+Vector2.from_angle(a)*r*0.75,3.5,Color("e2b23a",alpha))
		return true
	if kind == "mourning_shroud":
		var center: Vector2 = e.pos
		var r: float = e.get("radius",100.0)*(0.85+progress*0.2)
		var alpha := (1.0-progress)*0.8
		g.draw_circle(center,r,Color("5e4b73",alpha*0.18))
		g.draw_arc(center,r,0,TAU,40,Color("b9a3d6",alpha),2.5,true)
		g.draw_arc(center,r*0.72,progress*1.5,progress*1.5+PI*1.3,28,Color("d8c8ee",alpha*0.85),2.0,true)
		return true
	if kind == "sealed_coffin":
		var center: Vector2 = e.pos
		var r: float = e.get("radius",100.0)*(1.05-progress*0.35)
		var alpha := (1.0-progress)*0.9
		g.draw_arc(center,r,0,TAU,36,Color("3d2c3e",alpha),3.5,true)
		g.draw_arc(center,r*0.82,0,TAU,36,Color("926c9d",alpha*0.75),1.5,true)
		for i: int in range(4):
			var p0: Vector2 = center+Vector2.from_angle(i*PI*0.5+PI*0.25)*r
			g.draw_line(p0,center.lerp(p0,0.4),Color("3d2c3e",alpha),2.5,true)
		return true
	return false
