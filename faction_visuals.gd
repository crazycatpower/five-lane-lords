extends RefCounted
# Presentation only: never consumes simulation RNG or mutates battle actors/events.

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
	return false
