extends RefCounted
const B = preload("res://balance.gd")

static func tower(g, b: Dictionary) -> void:
	var fill: float = clampf(b.get("blood",0.0)/B.CARDS.blood_tower.blood_max,0,1)
	var active: bool = b.get("blood_glow",0.0) > 0
	var pulse: float = (sin(g.model.elapsed*(8.0 if active else 2.0))+1.0)*0.5
	var center: Vector2 = b.pos+Vector2(0,25)
	g.tf(center,0,Vector2(1,0.34))
	g.draw_circle(Vector2.ZERO,29+4*pulse,Color(0.55,0.08,0.12,0.10+fill*0.16))
	g.draw_arc(Vector2.ZERO,32+3*pulse,0,TAU,24,Color(0.8,0.25,0.25,0.65 if active else 0.2),2,true)
	g.tf()
	if active:
		for i: int in range(3):
			var t: float = fposmod(g.model.elapsed*0.7+i/3.0,1.0)
			g.draw_circle(b.pos+Vector2((i-1)*13,-8-t*32),2.5,Color(0.85,0.28,0.25,1-t))

static func transfer(g, e: Dictionary, progress: float) -> void:
	var alpha: float = 1-progress
	g.draw_line(e.pos,e.to,Color(0.65,0.12,0.16,alpha*0.4),2,true)
	for i: int in range(3):
		var t: float = clampf(progress*1.6-i*0.16,0,1)
		var p: Vector2 = e.pos.lerp(e.to,t)+Vector2(0,-sin(t*PI)*18)
		g.draw_circle(p,4,Color(0.65,0.12,0.16,alpha))
		g.draw_circle(p,1.5,Color(1.0,0.72,0.56,alpha))
	g.draw_arc(e.to,7+progress*15,0,TAU,16,Color(0.85,0.30,0.30,alpha),2,true)
