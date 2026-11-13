extends RefCounted
# 一日戰役 (2026-11-12): how the day shows on screen. The rules live in battle.gd (day_phase,
# night_rate, crumble_gates, dawn_verdict); nothing here changes a match.
# No words on the field (producer 2026-11-03): the sun on the day track, the light on the grass, the
# bell and the stones falling from the gates carry the message.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const RogueCatalog = preload("res://roguelike_catalog.gd")

const TRACK := Rect2(474,43,220,16)
const BANDS := [Color("b7d6e6"),Color("f4e2a2"),Color("e9a86d"),Color("3b4675")]
const BLEND := 10.0 # seconds the light takes to turn at each change of phase
const NOON := Color(1.0,0.93,0.62,0.07)
const DUSK := Color(0.93,0.50,0.22,0.17)
const NIGHT := Color(0.07,0.11,0.33,0.34)
static var glow_texture: GradientTexture2D

# Where the day track ends: dawn, the roguelike's time limit, or (the first lesson) nowhere near.
static func day_end(g) -> float:
	if g.model.night_decay: return B.DAWN
	return RogueCatalog.TIME_LIMIT if g.rogue.in_battle else B.RAMP_2+120.0

static func marks(g) -> Array:
	var result: Array = [0.0,B.RAMP_1,B.RAMP_2]
	if g.model.night_decay: result.append(B.NIGHT_START)
	result.append(day_end(g))
	return result

# The day track in the top bar: one inked band per phase; the sun rides along it and hands over to
# the moon at nightfall. Ticks mark where the gold speeds up.
static func track(g) -> void:
	var m = g.model
	var r := TRACK
	var points: Array = marks(g)
	var end: float = points[points.size()-1]
	g.draw_rect(r.grow(2),Color(g.INK,0.85))
	for i: int in range(points.size()-1):
		var x0: float = r.position.x+r.size.x*points[i]/end
		var x1: float = r.position.x+r.size.x*points[i+1]/end
		g.draw_rect(Rect2(x0,r.position.y,x1-x0,r.size.y),BANDS[i])
		if g.model.night_decay and i == points.size()-2: # a few stars in the night band
			for k: int in range(7):
				var star := Vector2(lerpf(x0+5,x1-5,g.scenery_noise(k,91)),r.position.y+3+g.scenery_noise(k,92)*(r.size.y-6))
				g.draw_circle(star,1.1,Color(1,0.97,0.82,0.55+0.4*sin(g.clock*2.0+k)))
	g.draw_texture_rect(g.PAPER,r,false,Color(1,1,1,0.10))
	for i: int in range(1,points.size()-1):
		var x: float = r.position.x+r.size.x*points[i]/end
		g.draw_line(Vector2(x,r.position.y-4),Vector2(x,r.end.y+4),Color(g.INK,0.85),2)
	var at := Vector2(r.position.x+r.size.x*clampf(m.elapsed/end,0,1),r.get_center().y)
	# The part of the day already spent is dimmed, so the sun's place reads at a glance.
	g.draw_rect(Rect2(r.position,Vector2(at.x-r.position.x,r.size.y)),Color(0.20,0.14,0.08,0.22))
	if m.day_phase() == 3:
		moon(g,at,11.0)
		balance(g)
	else: sun(g,at,9.0)

# At night the dawn verdict is in sight: who holds more land, as a tug-of-war bar under the track.
const BALANCE := Rect2(474,66,220,11)
static func balance(g) -> void:
	var m = g.model
	var mine: int = m.land(g.me)
	var theirs: int = m.land(1-g.me)
	var share: float = 0.5 if mine+theirs == 0 else float(mine)/(mine+theirs)
	var r := BALANCE
	var fade: float = darkness(m)
	var left: Color = g.RED if g.me == 0 else g.BLUE
	var right: Color = g.BLUE if g.me == 0 else g.RED
	g.draw_rect(r.grow(2),Color(g.INK,0.85*fade))
	g.draw_rect(Rect2(r.position,Vector2(r.size.x*share,r.size.y)),Color(left,fade))
	g.draw_rect(Rect2(r.position.x+r.size.x*share,r.position.y,r.size.x*(1-share),r.size.y),Color(right,fade))
	g.draw_line(Vector2(r.get_center().x,r.position.y-3),Vector2(r.get_center().x,r.end.y+3),Color(0.96,0.90,0.74,fade),2)
	g.draw_string(g.font,Vector2(r.position.x+4,r.end.y-1),str(mine),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(1,0.96,0.86,fade))
	g.draw_string(g.font,Vector2(r.end.x-44,r.end.y-1),str(theirs),HORIZONTAL_ALIGNMENT_RIGHT,40,12,Color(1,0.96,0.86,fade))

static func sun(g, at: Vector2, radius: float) -> void:
	var spin: float = g.clock*0.4
	for i: int in range(8):
		var d := Vector2.from_angle(spin+i*TAU/8)
		g.draw_line(at+d*(radius+2),at+d*(radius+6),Color("c98a1e"),2,true)
	g.draw_circle(at,radius,Color("f2c230"))
	g.draw_arc(at,radius,0,TAU,24,Color(g.INK,0.9),1.5,true)
	g.draw_circle(at+Vector2(-2,-2),radius*0.45,Color(1,0.95,0.7,0.6))

static func moon(g, at: Vector2, radius: float) -> void:
	g.draw_circle(at,radius+4+sin(g.clock*3.0),Color(0.95,0.93,0.75,0.25))
	g.draw_circle(at,radius,Color("f3ecc9"))
	g.draw_circle(at+Vector2(radius*0.42,-radius*0.18),radius*0.82,BANDS[BANDS.size()-1])
	g.draw_arc(at,radius,0,TAU,24,Color(g.INK,0.9),1.5,true)

# The light lying over the field right now (alpha 0 = plain daylight).
static func tint(m) -> Color:
	var t: float = m.elapsed
	var c := Color(NOON,0.0).lerp(NOON,smoothstep(B.RAMP_1,B.RAMP_1+BLEND,t))
	c = c.lerp(DUSK,smoothstep(B.RAMP_2,B.RAMP_2+BLEND,t))
	if m.night_decay: c = c.lerp(NIGHT,smoothstep(B.NIGHT_START,B.NIGHT_START+BLEND,t))
	return c

# How dark it is, 0..1 (lights come on with it).
static func darkness(m) -> float:
	return smoothstep(B.NIGHT_START,B.NIGHT_START+BLEND,m.elapsed) if m.night_decay else 0.0

static func glow() -> GradientTexture2D:
	if glow_texture == null:
		var ramp := Gradient.new()
		ramp.set_color(0,Color(1.0,0.80,0.42,0.55))
		ramp.set_color(1,Color(1.0,0.62,0.22,0.0))
		ramp.add_point(0.45,Color(1.0,0.72,0.32,0.26))
		glow_texture = GradientTexture2D.new()
		glow_texture.gradient = ramp
		glow_texture.fill = GradientTexture2D.FILL_RADIAL
		glow_texture.fill_from = Vector2(0.5,0.5)
		glow_texture.fill_to = Vector2(1.0,0.5)
		glow_texture.width = 128
		glow_texture.height = 128
	return glow_texture

static func pool(g, at: Vector2, radius: float, strength: float) -> void:
	var flicker: float = 1.0+0.06*sin(g.clock*11.0+at.y*0.05)+0.04*sin(g.clock*17.0+at.x*0.03)
	var size := Vector2(radius*2,radius*1.5)*flicker
	g.draw_texture_rect(glow(),Rect2(at-size*0.5,size),false,Color(1,1,1,strength))

# Drawn over the troops and effects, under the HUD: the wash of light, then at night the fires.
static func light(g, field: Rect2) -> void:
	var m = g.model
	var c := tint(m)
	if c.a > 0.003: g.draw_rect(field,c)
	var dark := darkness(m)
	if dark <= 0.0: return
	for team: int in range(2):
		for lane: int in m.active_lanes:
			var gate := Vector2(L.gate_icon_x(team),L.cell_center(Vector2i(0,lane)).y)
			pool(g,gate+Vector2(0,-6),78.0 if m.gates[team][lane] > 0 else 52.0,dark)
			if m.gates[team][lane] > 0: torch(g,gate+Vector2(-27 if team == 0 else 27,-38),dark)
	for lord: Dictionary in m.lords:
		if lord.hp > 0 and m.lord_active[lord.team]: pool(g,lord.pos+Vector2(0,-14),70.0,dark*0.8)
	for b: Dictionary in m.buildings:
		if b.hp > 0 and b.kind in ["tower","watchtower","arcane_tower","blood_tower"]: pool(g,b.pos+Vector2(0,-30),56.0,dark*0.7)

static func torch(g, at: Vector2, strength: float) -> void:
	var lick: float = sin(g.clock*13.0+at.y)*2.0
	g.draw_line(at+Vector2(0,10),at+Vector2(0,24),Color("5b3d22",strength),3,true)
	g.draw_colored_polygon(PackedVector2Array([at+Vector2(-5,10),at+Vector2(lick,-8-absf(lick)),at+Vector2(5,10)]),Color(0.95,0.48,0.12,0.9*strength))
	g.draw_colored_polygon(PackedVector2Array([at+Vector2(-2.5,10),at+Vector2(lick*0.5,0),at+Vector2(2.5,10)]),Color(1.0,0.86,0.42,0.95*strength))

# A standing gate at night: it shudders, cracks run up it as it weakens and stones keep falling.
static func crumble(g, team: int, lane: int, gate_rect: Rect2) -> void:
	var m = g.model
	var rate: float = m.night_rate()
	if rate <= 0.0 or m.gates[team][lane] <= 0: return
	var worn: float = 1.0-m.gates[team][lane]/B.GATE_HP
	var x := gate_rect.get_center().x
	var crack := Color(0.16,0.11,0.07,0.55+0.4*worn)
	for i: int in range(1+int(worn*4.0)):
		var from := Vector2(x-20+g.scenery_noise(i,lane*7+team*3+40)*40,gate_rect.end.y-10)
		var points := PackedVector2Array([from])
		for k: int in range(4):
			from += Vector2((g.scenery_noise(i*5+k,lane+60)-0.5)*14,-(7+worn*6))
			points.append(from)
		g.draw_polyline(points,crack,1.6,true)
	# More stones the faster the night wears the gates down.
	var stones: int = clampi(3+int(rate/B.NIGHT_DECAY),3,9)
	for i: int in range(stones):
		var cycle: float = fposmod(g.clock*(0.9+0.35*g.scenery_noise(i,lane*5+team))+g.scenery_noise(i,lane+team*9+70),1.0)
		var px: float = x-26+g.scenery_noise(i,lane*11+team+80)*52
		var p := Vector2(px,gate_rect.position.y+18+cycle*cycle*(gate_rect.size.y-10))
		g.draw_circle(p,1.6+g.scenery_noise(i,90)*1.8,Color(0.38,0.32,0.25,0.9*(1.0-cycle*0.5)))
	var dust: float = 0.5+0.5*sin(g.clock*4.0+lane)
	g.tf(Vector2(x,gate_rect.end.y-2),0,Vector2(1,0.35))
	g.draw_circle(Vector2.ZERO,30+dust*5,Color(0.62,0.55,0.42,0.16+0.10*dust))
	g.tf()

# The moment night falls (and each later toll): the moon's rings on the track, a hush over the field.
static func toll(g, e: Dictionary, progress: float) -> void:
	var at := Vector2(TRACK.position.x+TRACK.size.x*clampf(e.time/day_end(g),0,1),TRACK.get_center().y)
	g.draw_set_transform_matrix(Transform2D.IDENTITY) # the top bar is never mirrored (online guest)
	for k: int in range(3):
		var ring: float = fmod(progress*1.6+k/3.0,1.0)
		g.draw_arc(at,14+ring*46,0,TAU,32,Color(0.86,0.84,0.98,(1-progress)*(1-ring)*0.9),3,true)
	g.tf()
	if e.get("first",false):
		var veil := sin(clampf(progress*1.4,0,1)*PI)
		g.draw_rect(L.FIELD_FRAME.grow(-6),Color(0.05,0.07,0.22,0.22*veil))
