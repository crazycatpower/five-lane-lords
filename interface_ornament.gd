extends RefCounted

# Small ornaments use existing ink and paper colours, without new texture loads.
static func rule(g, a: Vector2, b: Vector2, ink: Color) -> void:
	var center := (a+b)*0.5
	g.draw_line(a,center-Vector2(5,0),Color(ink,0.48),1,true)
	g.draw_line(center+Vector2(5,0),b,Color(ink,0.48),1,true)
	g.draw_colored_polygon(PackedVector2Array([center+Vector2(-3,0),center+Vector2(0,-2),center+Vector2(3,0),center+Vector2(0,2)]),ink)

static func card_caption(g, r: Rect2, tint: Color) -> void:
	var paper := Color("f0e1bc").lerp(tint,0.12)
	var p := r.position
	var s := r.size
	var outline := PackedVector2Array([p+Vector2(3,0),p+Vector2(s.x-3,0),p+Vector2(s.x,3),p+s-Vector2(0,3),p+s-Vector2(3,0),p+Vector2(3,s.y),p+Vector2(0,s.y-3),p+Vector2(0,3)])
	g.draw_colored_polygon(outline,paper)
	outline.append(outline[0])
	g.draw_polyline(outline,Color("9b8054",0.65),0.8,true)
	g.draw_line(p+Vector2(4,2),p+Vector2(s.x-4,2),Color("fff4d5",0.65),1,true)

static func portrait(g, r: Rect2, tint: Color, selected: bool) -> void:
	g.draw_rect(Rect2(r.position+Vector2(2,3),r.size),Color("35291f",0.16))
	g.panel(r,Color("ecddb9"),Color("8c6e43"))
	var field := Rect2(r.position+Vector2(9,9),Vector2(r.size.x-18,r.size.y-75))
	g.draw_rect(field,Color("efe5cc").lerp(tint,0.23))
	g.draw_rect(field,Color("9b8054",0.4),false,1)
	for side: int in [0,1]:
		var x := field.position.x+5 if side == 0 else field.end.x-5
		g.draw_line(Vector2(x,field.position.y+5),Vector2(x,field.position.y+24),Color("a08147",0.65),1,true)
	rule(g,Vector2(r.position.x+24,r.end.y-60),Vector2(r.end.x-24,r.end.y-60),Color("92703c"))
	if selected: g.draw_rect(r.grow(-2),Color("a66b35"),false,2)
