extends RefCounted

# Small ornaments use existing ink and paper colours, without new texture loads.
static func rule(g, a: Vector2, b: Vector2, ink: Color) -> void:
	var center := (a+b)*0.5
	g.draw_line(a,center-Vector2(5,0),Color(ink,0.48),1,true)
	g.draw_line(center+Vector2(5,0),b,Color(ink,0.48),1,true)
	g.draw_colored_polygon(PackedVector2Array([center+Vector2(-3,0),center+Vector2(0,-2),center+Vector2(3,0),center+Vector2(0,2)]),ink)

static func vertical_rule(g, x: float, y0: float, y1: float, ink: Color) -> void:
	var mid := (y0+y1)*0.5
	g.draw_line(Vector2(x,y0),Vector2(x,mid-7),Color(ink,0.42),1.4,true)
	g.draw_line(Vector2(x,mid+7),Vector2(x,y1),Color(ink,0.42),1.4,true)
	g.draw_line(Vector2(x-3.5,y0),Vector2(x+3.5,y0),Color(ink,0.52),1.2,true)
	g.draw_line(Vector2(x-3.5,y1),Vector2(x+3.5,y1),Color(ink,0.52),1.2,true)
	g.draw_colored_polygon(PackedVector2Array([Vector2(x,mid-4.5),Vector2(x+3.2,mid),Vector2(x,mid+4.5),Vector2(x-3.2,mid)]),Color(ink,0.75))

static func card_caption(g, r: Rect2, tint: Color, blocked: bool = false) -> void:
	var paper := Color("b4b4b4") if blocked else Color("f2e4c2").lerp(tint,0.14)
	var p := r.position
	var s := r.size
	var c := clampf(s.x*0.032, 2.5, 4.0)
	var shadow := PackedVector2Array([
		p+Vector2(c+1,1.5), p+Vector2(s.x-c+1,1.5), p+Vector2(s.x+1,c+1.5), p+s+Vector2(1,-c+1.5),
		p+s+Vector2(-c+1,1.5), p+Vector2(c+1,s.y+1.5), p+Vector2(1,s.y-c+1.5), p+Vector2(1,c+1.5)
	])
	g.draw_colored_polygon(shadow,Color("261b11",0.20))
	var outline := PackedVector2Array([
		p+Vector2(c,0), p+Vector2(s.x-c,0), p+Vector2(s.x,c), p+s-Vector2(0,c),
		p+s-Vector2(c,0), p+Vector2(c,s.y), p+Vector2(0,s.y-c), p+Vector2(0,c)
	])
	g.draw_colored_polygon(outline,paper)
	g.draw_line(p+Vector2(c+1,1.5),p+Vector2(s.x-c-1,1.5),Color("d6d6d6",0.42) if blocked else Color("fff7de",0.72),1.2,true)
	g.draw_line(p+Vector2(c+1,s.y-1.5),p+Vector2(s.x-c-1,s.y-1.5),Color("5c5c5c",0.32) if blocked else Color("82663c",0.32),1.0,true)
	outline.append(outline[0])
	g.draw_polyline(outline,Color("646464",0.82) if blocked else Color("7a6038",0.82),1.1,true)
	# Subtle divider between card name and keyword cartouches
	var div_y := p.y + s.y * 0.54
	g.draw_line(Vector2(p.x+10,div_y),Vector2(p.x+s.x-10,div_y),Color("686868",0.28) if blocked else Color("8c6f42",0.28),1.0,true)
	for dx: float in [4.0, s.x-4.0]:
		g.draw_circle(Vector2(p.x+dx, div_y), 1.0, Color("666666",0.55) if blocked else Color("8a6d3f",0.55))

static func corner_seal(g, r: Rect2, text: String, fill: Color, fsize: int, is_special: bool = false) -> void:
	var p := r.position
	var s := r.size
	var cut := 2.8
	var sh := Vector2(1.2, 1.8)
	var shadow_pts := PackedVector2Array([
		p+sh+Vector2(cut,0), p+sh+Vector2(s.x-cut,0), p+sh+Vector2(s.x,cut), p+sh+Vector2(s.x,s.y-cut*1.3),
		p+sh+Vector2(s.x*0.5,s.y+1.2), p+sh+Vector2(0,s.y-cut*1.3), p+sh+Vector2(0,cut)
	])
	g.draw_colored_polygon(shadow_pts, Color("1a120b", 0.38))
	var pts := PackedVector2Array([
		p+Vector2(cut,0), p+Vector2(s.x-cut,0), p+Vector2(s.x,cut), p+Vector2(s.x,s.y-cut*1.3),
		p+Vector2(s.x*0.5,s.y+1.2), p+Vector2(0,s.y-cut*1.3), p+Vector2(0,cut)
	])
	g.draw_colored_polygon(pts, fill)
	g.draw_line(p+Vector2(cut+1,1.5), p+Vector2(s.x-cut-1,1.5), Color("fff3d1",0.30), 1.0, true)
	var rim := pts.duplicate()
	rim.append(rim[0])
	g.draw_polyline(rim, Color("d8b86e", 0.90 if is_special else 0.72), 1.2, true)
	g.draw_polyline(rim, Color("261b11", 0.85), 0.7, true)
	var by := p.y + s.y * 0.5 + float(fsize) * 0.36 - 0.5
	g.draw_string(g.font, Vector2(p.x, by), text, HORIZONTAL_ALIGNMENT_CENTER, s.x, fsize, Color("fbf0d5"))

static func ribbon_tag(g, r: Rect2, text: String, fill: Color, fsize: int) -> void:
	var p := r.position
	var s := r.size
	var notch := minf(3.4, s.y * 0.22)
	var sh := Vector2(0.0, 1.8)
	var shadow_pts := PackedVector2Array([
		p+sh+Vector2(-notch,0), p+sh+Vector2(s.x+notch,0), p+sh+Vector2(s.x,s.y*0.5),
		p+sh+Vector2(s.x+notch,s.y), p+sh+Vector2(-notch,s.y), p+sh+Vector2(0,s.y*0.5)
	])
	g.draw_colored_polygon(shadow_pts, Color("1a120b", 0.34))
	var pts := PackedVector2Array([
		p+Vector2(-notch,0), p+Vector2(s.x+notch,0), p+Vector2(s.x,s.y*0.5),
		p+Vector2(s.x+notch,s.y), p+Vector2(-notch,s.y), p+Vector2(0,s.y*0.5)
	])
	g.draw_colored_polygon(pts, fill)
	g.draw_line(p+Vector2(-notch+2,1.5), p+Vector2(s.x+notch-2,1.5), Color("e2c47e",0.78), 1.0, true)
	g.draw_line(p+Vector2(-notch+2,s.y-1.5), p+Vector2(s.x+notch-2,s.y-1.5), Color("c4a058",0.65), 1.0, true)
	var rim := pts.duplicate()
	rim.append(rim[0])
	g.draw_polyline(rim, Color("281c11", 0.88), 1.0, true)
	var by := p.y + s.y * 0.5 + float(fsize) * 0.36 - 0.5
	g.draw_string(g.font, Vector2(p.x, by), text, HORIZONTAL_ALIGNMENT_CENTER, s.x, fsize, Color("fbf0d5"))

static func cost_medallion(g, center: Vector2, radius: float, text: String, blocked: bool = false) -> void:
	g.draw_circle(center + Vector2(1.4, 2.0), radius + 1.0, Color("1a120b", 0.38))
	g.draw_circle(center, radius + 1.0, Color("242424") if blocked else Color("261b11"))
	var enamel := Color("4a4a4a") if blocked else Color("283854")
	g.draw_circle(center, radius - 0.4, enamel)
	if not blocked:
		g.draw_arc(center + Vector2(-radius*0.12, -radius*0.12), radius*0.62, PI*0.95, PI*1.75, 12, Color("6888b8", 0.32), 2.0, true)
	var gold := Color("8c8c8c") if blocked else Color("d8b467")
	g.draw_arc(center, radius - 0.6, 0, TAU, 28, gold, 1.9, true)
	g.draw_arc(center, radius - 2.6, 0, TAU, 24, Color("dcdcdc", 0.25) if blocked else Color("fff3d1", 0.28), 0.9, true)
	for dir: Vector2 in [Vector2(0,-1), Vector2(1,0), Vector2(0,1), Vector2(-1,0)]:
		g.draw_circle(center + dir * (radius - 0.8), 1.3, Color("f5dfa8") if not blocked else gold)
	var scale_k := radius / 15.0
	var fsize := maxi(11, roundi((16.0 if text.length() >= 2 else 18.5) * scale_k))
	var by := center.y + float(fsize) * 0.36 - 0.5
	var w := radius * 2.0
	g.draw_string(g.font, Vector2(center.x - radius, by), text, HORIZONTAL_ALIGNMENT_CENTER, w, fsize, Color("d4d4d4") if blocked else Color("fff6df"))

static func wax_upgrade_seal(g, center: Vector2, radius: float, lv: int) -> void:
	g.draw_circle(center + Vector2(1.2, 1.8), radius + 0.8, Color("1a120b", 0.36))
	g.draw_circle(center, radius + 0.8, Color("381410"))
	g.draw_circle(center, radius - 0.5, Color("9c3226"))
	g.draw_arc(center, radius - 1.8, 0, TAU, 20, Color("e6be74", 0.82), 1.2, true)
	var scale := 11.5 if lv >= 10 else 14.0
	var fsize := maxi(10, roundi(scale * radius / 13.0))
	g.draw_string(g.font, Vector2(center.x - radius, center.y + float(fsize) * 0.36 - 0.5), "+%d" % lv, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fsize, Color("fff2d0"))

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
