extends RefCounted
# Visual-only effects that replaced the old placeholder rings and boxes (2026-11-17): spell landings,
# explosions, stone and shell impacts, summons, and the small economy/repair/heal cues.
# Every particle is placed by a hash of the event position, so an effect looks the same each frame
# and never touches the battle's random numbers.

const SPELL_STYLE := {
	"rain":"volley","fire":"fire","flaming_pitch":"fire","rolling_boulder":"boulder_launch",
	"chain_lightning":"storm","mana_drain":"drain","phase_shift":"rift","mirror_clone":"rift",
	"time_field":"clock","gravity_well":"vortex",
	"arcane_shield":"bless","mana_spring":"bless","charge_horn":"bless","harvest":"bless",
	"berserk_blood":"bless","feral_mutation":"bless","levy":"bless","counter_charge":"shock",
	"curse":"miasma","plague":"miasma","corrosive_bile":"miasma",
	"wing_gust":"gust","devouring_maw":"maw","swarm_eruption":"eruption","pack_ambush":"eruption",
}
const SPELL_COLOR := {
	"rain":"8a6a3c","fire":"f07a22","flaming_pitch":"e8571c","rolling_boulder":"b88b4a","chain_lightning":"9fd0ff",
	"mana_drain":"4fc3f7","phase_shift":"a497df","mirror_clone":"c6b8ff","time_field":"cbb0df",
	"gravity_well":"7a62d6","arcane_shield":"7ac7e0","mana_spring":"4fc3f7","charge_horn":"e2b23a",
	"harvest":"f2c230","berserk_blood":"c0392b","feral_mutation":"7fbf3f","levy":"e2b23a",
	"counter_charge":"e2b23a","curse":"926c9d","plague":"6f9a3a","corrosive_bile":"b5cc3a",
	"wing_gust":"d9e6ef","devouring_maw":"8b1e2a","swarm_eruption":"8a5a2b","pack_ambush":"8a5a2b",
}
const SMOKE := Color(0.32,0.28,0.24)
const DUST := Color(0.60,0.48,0.33)
const FLAME := Color("f07a22")
const FLAME_CORE := Color("ffd25a")

# Stable 0..1 noise for particle i of an effect at seed s.
static func h(s: float, i: int) -> float:
	return fposmod(sin(s*12.9898+i*78.233)*43758.5453,1.0)

static func seed_of(e: Dictionary) -> float:
	return e.pos.x*0.37+e.pos.y*1.13

# Point i spread over the spell's area (its grid rectangle, or a circle when it has none).
static func spot(e: Dictionary, s: float, i: int) -> Vector2:
	var r: Rect2 = e.get("rect",Rect2())
	if r.size != Vector2.ZERO: return r.position+Vector2((0.08+0.84*h(s,i))*r.size.x,(0.12+0.8*h(s,i+97))*r.size.y)
	var a := h(s,i)*TAU
	return e.pos+Vector2(cos(a),sin(a)*0.45)*e.get("radius",60.0)*sqrt(h(s,i+97))

static func area_center(e: Dictionary) -> Vector2:
	var r: Rect2 = e.get("rect",Rect2())
	return r.get_center() if r.size != Vector2.ZERO else e.pos

static func area_radius(e: Dictionary) -> float:
	var r: Rect2 = e.get("rect",Rect2())
	return minf(r.size.x,r.size.y)*0.5 if r.size != Vector2.ZERO else e.get("radius",60.0)

static func ease_out(t: float) -> float:
	return 1.0-pow(1.0-clampf(t,0,1),3)

# Flattened ring on the ground.
static func ground_ring(g, c: Vector2, r: float, col: Color, width: float) -> void:
	g.tf(c,0,Vector2(1,0.42))
	g.draw_arc(Vector2.ZERO,r,0,TAU,40,col,width,true)
	g.tf()

static func ground_disc(g, c: Vector2, r: float, col: Color) -> void:
	g.tf(c,0,Vector2(1,0.42))
	g.draw_circle(Vector2.ZERO,r,col)
	g.tf()

static func flame(g, base: Vector2, height: float, width: float, sway: float, alpha: float) -> void:
	if height <= 1: return
	var tip := base+Vector2(sway,-height)
	g.draw_colored_polygon(PackedVector2Array([base+Vector2(-width,0),base+Vector2(-width*0.55,-height*0.45),tip,base+Vector2(width*0.55,-height*0.45),base+Vector2(width,0)]),Color(FLAME,alpha))
	var inner := height*0.55
	g.draw_colored_polygon(PackedVector2Array([base+Vector2(-width*0.5,0),base+Vector2(sway*0.5,-inner),base+Vector2(width*0.5,0)]),Color(FLAME_CORE,alpha))

# ---------------------------------------------------------------- spells
static func spell(g, e: Dictionary, progress: float) -> bool:
	var kind: String = e.get("card","")
	if not SPELL_STYLE.has(kind): return false
	var col := Color(SPELL_COLOR.get(kind,"e2b23a"))
	area_tint(g,e,progress,col)
	match SPELL_STYLE[kind]:
		"volley": volley(g,e,progress)
		"fire": fire(g,e,progress)
		"storm": storm(g,e,progress,col)
		"drain": drain(g,e,progress,col)
		"rift": rift(g,e,progress,col)
		"clock": clock(g,e,progress,col)
		"vortex": vortex(g,e,progress,col)
		"bless": bless(g,e,progress,col)
		"shock": shock(g,e,progress,col)
		"miasma": miasma(g,e,progress,col,kind == "corrosive_bile")
		"gust": gust(g,e,progress,col)
		"maw": maw(g,e,progress,col)
		"eruption": eruption(g,e,progress,col)
		"boulder_launch": boulder_launch(g,e,progress,col)
	return true

# 巨石滾落 launch burst: dust plume, shock ring, and forward speed streaks.
static func boulder_launch(g, e: Dictionary, p: float, col: Color) -> void:
	var c := area_center(e)
	var dir := 1.0 if int(e.get("team", 0)) == 0 else -1.0
	var r := area_radius(e) * 0.85
	ground_disc(g, c, r * (0.45 + 0.55 * ease_out(p)), Color(col, (1.0 - p) * 0.25))
	ground_ring(g, c, r * ease_out(p * 1.4), Color(DUST, (1.0 - p) * 0.85), 3.5)
	for i: int in range(6):
		var a := -PI * 0.6 + float(i) * PI * 0.24
		var q := clampf(p * 1.4, 0.0, 1.0)
		var d := c + Vector2(-dir * 16.0 * q + cos(a) * r * 0.7 * q, -6.0 - sin(q * PI) * 26.0 + sin(a) * 10.0)
		g.draw_circle(d, 5.0 + 7.0 * q, Color(DUST, (1.0 - q) * 0.50))
	for i: int in range(3):
		var y_off := (i - 1) * 14.0
		var x0 := c.x + dir * (10.0 + p * 40.0)
		g.draw_line(Vector2(x0, c.y + y_off), Vector2(x0 + dir * 28.0, c.y + y_off), Color(col.lightened(0.3), (1.0 - p) * 0.75), 2.2, true)

# The spell's colour washes over its area and fades; a bright edge shrinks inward.
static func area_tint(g, e: Dictionary, p: float, col: Color) -> void:
	var r: Rect2 = e.get("rect",Rect2())
	if r.size == Vector2.ZERO: return
	var fade := pow(1.0-p,1.5)
	g.draw_rect(r,Color(col,0.22*fade))
	var inset := r.grow(-minf(r.size.x,r.size.y)*0.25*ease_out(p))
	g.draw_rect(inset,Color(col.lightened(0.4),0.5*fade),false,3.0)

# 箭雨: arrows drop from the caster's side, stick in the ground and kick up dust.
static func volley(g, e: Dictionary, p: float) -> void:
	var s := seed_of(e)
	var dir := 1.0 if e.get("team",0) == 0 else -1.0
	var fall := Vector2(dir*0.42,1).normalized()
	var side := fall.orthogonal()
	for i: int in range(24):
		var land := spot(e,s,i)
		var t0 := h(s,i+31)*0.35
		var t := clampf((p-t0)/0.2,0,1)
		if t < 1.0:
			if p < t0: continue
			var tip := land-fall*180*(1.0-t)
			g.draw_line(tip-fall*34,tip,Color("3d2b1c",0.95),3.0,true)
			g.draw_line(tip-fall*34,tip-fall*40+side*5,Color("efe4c8",0.95),2.5,true)
			g.draw_line(tip-fall*34,tip-fall*40-side*5,Color("efe4c8",0.95),2.5,true)
		else:
			var after := clampf((p-t0-0.2)/0.45,0,1)
			var alpha := 1.0-clampf((p-0.7)/0.3,0,1)
			g.draw_line(land-fall*20,land,Color("3d2b1c",alpha),3.0,true)
			g.draw_line(land-fall*20,land-fall*26+side*5,Color("efe4c8",alpha),2.5,true)
			g.draw_line(land-fall*20,land-fall*26-side*5,Color("efe4c8",alpha),2.5,true)
			if after < 1.0:
				ground_ring(g,land,6+after*20,Color(DUST,(1-after)*0.8),3.0)
				for k: int in range(3): g.draw_circle(land+Vector2((k-1)*8*after,-8*after-k*2),3+3*after,Color(DUST,(1-after)*0.55))

# 火罐 / 燃燒火油: a flash, licking flames over the area, embers and smoke.
static func fire(g, e: Dictionary, p: float) -> void:
	var s := seed_of(e)
	var c := area_center(e)
	var r := area_radius(e)
	ground_disc(g,c,r*1.1,Color(FLAME,0.22*(1-p)))
	if p < 0.2: ground_disc(g,c,r*(0.5+p*3.5),Color(1.0,0.9,0.6,(0.2-p)*3.5))
	for i: int in range(13):
		var b := spot(e,s,i)
		ground_disc(g,b,22,Color(0.12,0.07,0.03,(1-p)*0.35))
		var life := sin(clampf(p*1.2-h(s,i+5)*0.15+0.08,0,1)*PI)
		var flicker := 0.8+0.2*sin(p*40+i*1.7)
		flame(g,b,(40+24*h(s,i+11))*life*flicker,11+5*h(s,i+3),sin(p*14+i)*6,0.9*life)
	for i: int in range(22):
		var b := spot(e,s,i+40)
		var rise := fposmod(p*1.4+h(s,i+60),1.0)
		g.draw_circle(b+Vector2(sin(rise*6+i)*8,-rise*90),2.6,Color(FLAME_CORE,(1-rise)*(1-p)))
	for i: int in range(6):
		var b := spot(e,s,i+80)
		var q := clampf((p-0.25)/0.75,0,1)
		if q > 0: g.draw_circle(b+Vector2(0,-30-q*50),12+q*22,Color(SMOKE,(1-q)*0.4))

# 連鎖閃電: the bolts are drawn as links; the area crackles and flashes.
static func storm(g, e: Dictionary, p: float, col: Color) -> void:
	var s := seed_of(e)
	var r: Rect2 = e.get("rect",Rect2(e.pos-Vector2(60,60),Vector2(120,120)))
	g.draw_rect(r,Color(0.9,0.96,1.0,pow(1-p,2)*0.35))
	for i: int in range(9):
		var a := spot(e,s,i)
		var alive := 1.0-clampf(abs(p-h(s,i+9)*0.6)*5,0,1)
		if alive <= 0: continue
		var pts := PackedVector2Array([a])
		for k: int in range(1,6): pts.append(a+Vector2((h(s,i*7+k)-0.5)*34,-k*14))
		g.draw_polyline(pts,Color(col,alive*0.55),8,true)
		g.draw_polyline(pts,Color(1,1,1,alive),2.8,true)
		ground_ring(g,a,10+16*(1-alive),Color(col,alive*0.8),2.5)

# 魔力吸取: blue motes are pulled from the area to its centre and then fly up.
static func drain(g, e: Dictionary, p: float, col: Color) -> void:
	var s := seed_of(e)
	var c := area_center(e)
	ground_ring(g,c,area_radius(e)*(1.0-p*0.6),Color(col,(1-p)*0.8),3.5)
	ground_disc(g,c,22+18*p,Color(col,(1-p)*0.3))
	for i: int in range(24):
		var from := spot(e,s,i)
		var t := ease_out(clampf(p*1.6-h(s,i+3)*0.4,0,1))
		var tb := maxf(0.0,t-0.15)
		var pos := from.lerp(c,t)+Vector2(0,-t*t*50)
		var back := from.lerp(c,tb)+Vector2(0,-tb*tb*50)
		g.draw_line(back,pos,Color(col,(1-p)*0.45),3,true)
		g.draw_circle(pos,4.5,Color(col,(1-p)*0.95))
		g.draw_circle(pos,2,Color(1,1,1,1-p))

# 相位轉移 / 鏡像複製: counter-turning rune rings and drifting shards.
static func rift(g, e: Dictionary, p: float, col: Color) -> void:
	var s := seed_of(e)
	var c := area_center(e)
	var r := area_radius(e)*(0.55+0.45*ease_out(p*2))
	var a := (1-p)*0.85
	g.tf(c,0,Vector2(1,0.45))
	g.draw_circle(Vector2.ZERO,r,Color(col,a*0.18))
	for k: int in range(6):
		var start := k*TAU/6+p*2.2
		g.draw_arc(Vector2.ZERO,r,start,start+0.7,10,Color(col,a),5,true)
		var back := -k*TAU/6-p*2.2
		g.draw_arc(Vector2.ZERO,r*0.7,back,back+0.5,8,Color(1,1,1,a*0.8),3,true)
	g.tf()
	for i: int in range(14):
		var b := spot(e,s,i)
		var q := clampf(p*1.3-h(s,i+4)*0.3,0,1)
		var d := b+Vector2(0,-q*40)
		g.draw_colored_polygon(PackedVector2Array([d+Vector2(0,-9),d+Vector2(5,0),d+Vector2(0,9),d+Vector2(-5,0)]),Color(col.lightened(0.2),(1-q)*0.95))

# 時空力場: a clock face settles over the field and its hand sweeps once.
static func clock(g, e: Dictionary, p: float, col: Color) -> void:
	var c := area_center(e)
	var r := area_radius(e)*0.9
	var a := (1-p)*0.85
	g.tf(c,0,Vector2(1,0.45))
	g.draw_circle(Vector2.ZERO,r,Color(col,a*0.22))
	g.draw_arc(Vector2.ZERO,r,0,TAU,48,Color(col,a),5,true)
	g.draw_arc(Vector2.ZERO,r*0.92,0,TAU,48,Color(1,1,1,a*0.5),2,true)
	for k: int in range(12):
		var d := Vector2.from_angle(k*TAU/12)
		g.draw_line(d*r*0.8,d*r,Color(col.lightened(0.3),a),4.0 if k % 3 == 0 else 2.5,true)
	g.draw_line(Vector2.ZERO,Vector2.from_angle(-PI/2+p*TAU)*r*0.8,Color(1,1,1,a),4,true)
	g.draw_line(Vector2.ZERO,Vector2.from_angle(-PI/2+p*TAU/12)*r*0.5,Color(1,1,1,a),6,true)
	g.draw_circle(Vector2.ZERO,7,Color(1,1,1,a))
	g.tf()

# 重力井: spiral arms wind inward, dragging motes to the middle.
static func vortex(g, e: Dictionary, p: float, col: Color) -> void:
	var s := seed_of(e)
	var c := area_center(e)
	var r := area_radius(e)
	var a := (1-p)*0.8
	g.tf(c,0,Vector2(1,0.45))
	g.draw_circle(Vector2.ZERO,r*0.35,Color(0.15,0.10,0.25,a*0.45))
	for arm: int in range(4):
		var pts := PackedVector2Array()
		for k: int in range(16):
			var f := k/15.0
			pts.append(Vector2.from_angle(arm*TAU/4+f*2.6+p*5.0)*r*(1.0-f)*(1.0-p*0.3))
		g.draw_polyline(pts,Color(col,a*0.5),9,true)
		g.draw_polyline(pts,Color(col.lightened(0.4),a),3.5,true)
	g.tf()
	for i: int in range(18):
		var from := spot(e,s,i)
		var t := ease_out(clampf(p*1.5-h(s,i+2)*0.3,0,1))
		g.draw_circle(from.lerp(c,t),4,Color(col.lightened(0.4),a))

# Buffs and gifts: columns of light rise over the area and motes drift up.
static func bless(g, e: Dictionary, p: float, col: Color) -> void:
	var s := seed_of(e)
	var lift := sin(clampf(p,0,1)*PI)
	for i: int in range(10):
		var b := spot(e,s,i)
		var height := (80+40*h(s,i+7))*lift
		g.draw_line(b,b+Vector2(0,-height),Color(col,0.22*lift),20,true)
		g.draw_line(b,b+Vector2(0,-height),Color(col.lightened(0.5),0.75*lift),4,true)
		ground_disc(g,b,12+p*14,Color(col,(1-p)*0.35))
		ground_ring(g,b,12+p*14,Color(col.lightened(0.3),(1-p)*0.8),2.5)
	for i: int in range(24):
		var b := spot(e,s,i+50)
		var rise := clampf(p*1.3-h(s,i+70)*0.3,0,1)
		g.draw_circle(b+Vector2(sin(rise*5+i)*7,-rise*80),3.2,Color(col.lightened(0.35),(1-rise)*0.95))

# 反衝號令: shock rings and speed lines burst out from the middle.
static func shock(g, e: Dictionary, p: float, col: Color) -> void:
	var c := area_center(e)
	var r := area_radius(e)
	for k: int in range(3):
		var q := clampf(p*1.4-k*0.15,0,1)
		if q > 0: ground_ring(g,c,r*ease_out(q),Color(col,(1-q)*0.9),6.0-k*1.5)
	for i: int in range(12):
		var d := Vector2.from_angle(i*TAU/12)*Vector2(1,0.45)
		var q := ease_out(p*1.3)
		g.draw_line(c+d*r*q*0.55,c+d*r*q,Color(1,0.95,0.7,(1-p)*0.9),3.5,true)

# 詛咒 / 瘟疫 / 腐蝕酸雨: billowing clouds; the acid also bubbles.
static func miasma(g, e: Dictionary, p: float, col: Color, bubbles: bool) -> void:
	var s := seed_of(e)
	for i: int in range(16):
		var b := spot(e,s,i)
		var q := clampf(p*1.2-h(s,i+5)*0.2+0.1,0,1)
		var radius := 14+26*ease_out(q)
		var c := b+Vector2(sin(p*3+i)*8,-q*22)
		g.draw_circle(c,radius,Color(col.darkened(0.25),(1-q)*0.42))
		g.draw_circle(c+Vector2(-radius*0.3,-radius*0.3),radius*0.55,Color(col.lightened(0.25),(1-q)*0.38))
	if bubbles:
		for i: int in range(12):
			var b := spot(e,s,i+40)
			var q := fposmod(p*2+h(s,i+41),1.0)
			g.draw_arc(b,3+q*7,0,TAU,12,Color(col.lightened(0.35),(1-q)*(1-p)),2.5,true)

# 狂風振翼: sweeping gusts with a few feathers, blowing away from the caster.
static func gust(g, e: Dictionary, p: float, col: Color) -> void:
	var s := seed_of(e)
	var r: Rect2 = e.get("rect",Rect2(e.pos-Vector2(80,40),Vector2(160,80)))
	var dir := 1.0 if e.get("team",0) == 0 else -1.0
	for i: int in range(9):
		var y := r.position.y+r.size.y*(i+0.5)/9.0
		var t := clampf(p*1.3-h(s,i)*0.3,0,1)
		var x := r.position.x+r.size.x*(t if dir > 0 else 1.0-t)
		var pts := PackedVector2Array()
		for k: int in range(10): pts.append(Vector2(x-dir*k*12,y+sin(k*0.9+i)*6))
		g.draw_polyline(pts,Color(col,(1-t)*0.45),9,true)
		g.draw_polyline(pts,Color(1,1,1,(1-t)*0.9),3,true)
	for i: int in range(9):
		var b := spot(e,s,i+20)
		var q := clampf(p*1.2,0,1)
		var d := b+Vector2(dir*q*110,-sin(q*PI)*26)
		var f := Vector2.from_angle(q*8+i)*11
		g.draw_line(d-f,d+f,Color(0.95,0.93,0.86,1-q),3.5,true)

# 吞噬巨口: two toothed jaws open over the area and snap shut.
static func maw(g, e: Dictionary, p: float, col: Color) -> void:
	var c := area_center(e)
	var r := area_radius(e)*0.8
	var close := pow(clampf(p/0.45,0,1),2.5)
	var gap := r*0.8*(1.0-close)
	var a := 1.0-clampf((p-0.6)/0.4,0,1)
	# Dark gullet between the lips (a lens, not a box).
	if gap > 2:
		var mouth := PackedVector2Array()
		for k: int in range(17): mouth.append(Vector2(c.x-r+k*r/8.0,c.y-(gap+6)*sin(k/16.0*PI)))
		for k: int in range(17): mouth.append(Vector2(c.x+r-k*r/8.0,c.y+(gap+6)*sin(k/16.0*PI)))
		g.draw_colored_polygon(mouth,Color(0.18,0.04,0.06,0.6*a))
	for side: float in [-1.0,1.0]:
		var y := c.y+side*(gap+6)
		# Lip edge bulges toward the bite; the jaw's back edge is a wider, shallower curve.
		var lip := PackedVector2Array()
		for k: int in range(9): lip.append(Vector2(c.x-r+k*r/4.0,y-side*sin(k/8.0*PI)*gap*0.35))
		var jaw := lip.duplicate()
		for k: int in range(9): jaw.append(Vector2(c.x+r*1.1-k*r*2.2/8.0,y+side*(10+sin((8-k)/8.0*PI)*30)))
		g.draw_colored_polygon(jaw,Color(col,a*0.92))
		g.draw_polyline(lip,Color(col.darkened(0.45),a),4,true)
		for k: int in range(8):
			var x := c.x-r+(k+0.5)*r/4.0
			var base := y-side*sin((k+0.5)/8.0*PI)*gap*0.35
			g.draw_colored_polygon(PackedVector2Array([Vector2(x-8,base),Vector2(x,base-side*20),Vector2(x+8,base)]),Color(0.96,0.93,0.85,a))
	if close >= 1.0: ground_disc(g,c,r*0.7,Color(col,a*0.35))

# 蟲群爆發 / 獸群突襲: the ground cracks and clods fly out.
static func eruption(g, e: Dictionary, p: float, col: Color) -> void:
	var s := seed_of(e)
	for i: int in range(6):
		var b := spot(e,s,i)
		var crack := clampf(p*3,0,1)
		ground_disc(g,b,14,Color(0.2,0.13,0.06,(1-p)*0.45))
		for k: int in range(4):
			var d := Vector2.from_angle(h(s,i*5+k)*TAU)*Vector2(1,0.45)*32*crack
			g.draw_line(b,b+d,Color(0.22,0.14,0.06,(1-p)*0.95),3,true)
		for k: int in range(5):
			var q := clampf((p-h(s,i*3+k)*0.2)*1.5,0,1)
			var v := Vector2((h(s,i*11+k)-0.5)*80,-90-40*h(s,i*13+k))
			var clod := b+v*q+Vector2(0,170*q*q)
			if q > 0 and q < 1: g.draw_circle(clod,4.5,Color(col.darkened(0.1),1-q))
		ground_ring(g,b,10+p*26,Color(DUST,(1-p)*0.75),3)
		for k: int in range(3): g.draw_circle(b+Vector2((k-1)*12*p,-10-p*20),6+p*10,Color(DUST,(1-p)*0.4))

# ---------------------------------------------------------------- impacts and summons
# Blast trap, powder barrel, imp bomb: flash, fireball, debris, smoke and a scorch mark.
static func explosion(g, e: Dictionary, p: float) -> void:
	var s := seed_of(e)
	var r: float = e.get("radius",60.0)
	var c: Vector2 = e.pos
	ground_disc(g,c,r*0.75,Color(0.10,0.06,0.03,0.35*(1-p)))
	if p < 0.12: g.draw_circle(c+Vector2(0,-10),r*(0.3+p*4),Color(1,0.97,0.82,(0.12-p)*7))
	var ball := ease_out(p*3)
	var fade := 1.0-clampf((p-0.15)/0.5,0,1)
	if fade > 0:
		g.draw_circle(c+Vector2(0,-14),r*0.55*ball,Color(FLAME,0.75*fade))
		g.draw_circle(c+Vector2(0,-16),r*0.36*ball,Color(FLAME_CORE,0.85*fade))
	ground_ring(g,c,r*ease_out(p*1.6),Color(1,0.8,0.5,(1-p)*0.8),4)
	for i: int in range(14):
		var a := h(s,i)*TAU
		var q := clampf(p*1.6,0,1)
		var v := Vector2(cos(a),sin(a)*0.5)*r*(0.7+0.5*h(s,i+3))
		var d := c+v*q+Vector2(0,-60*sin(q*PI)*h(s,i+8))
		if q < 1: g.draw_rect(Rect2(d-Vector2(3,3),Vector2(6,6)),Color(0.22,0.16,0.10,1-q))
	for i: int in range(8):
		var q := clampf((p-0.15)/0.85,0,1)
		if q <= 0: continue
		var a := i*TAU/8+h(s,i+20)
		var d := c+Vector2(cos(a)*r*0.5*q,-20-q*45+sin(a)*r*0.2)
		g.draw_circle(d,10+q*18,Color(SMOKE,(1-q)*0.4))

# Catapult stones and lobbed shells: crater, dust ring, flying chips.
static func stone_impact(g, e: Dictionary, p: float) -> void:
	var s := seed_of(e)
	var r: float = e.get("radius",60.0)
	var c: Vector2 = e.pos
	ground_disc(g,c,r*0.5,Color(0.18,0.12,0.06,0.45*(1-p)))
	for k: int in range(2):
		var q := clampf(p*1.5-k*0.2,0,1)
		if q > 0: ground_ring(g,c,r*ease_out(q),Color(DUST,(1-q)*0.85),4.0-k)
	for i: int in range(12):
		var a := h(s,i)*TAU
		var q := clampf(p*1.4,0,1)
		var d := c+Vector2(cos(a),sin(a)*0.5)*r*0.9*q+Vector2(0,-50*sin(q*PI)*h(s,i+4))
		if q < 1: g.draw_circle(d,3.5+2*h(s,i+9),Color(0.40,0.31,0.20,1-q))
	for i: int in range(6):
		var a := i*TAU/6
		var q := clampf(p*1.1,0,1)
		g.draw_circle(c+Vector2(cos(a)*r*0.6*q,-10-q*24+sin(a)*r*0.2*q),9+q*14,Color(DUST,(1-q)*0.45))

# A troop called up: the ground glows, cracks and throws up dust; a beam marks the spot.
static func summon(g, e: Dictionary, p: float, col: Color) -> void:
	var s := seed_of(e)
	var c: Vector2 = e.pos+Vector2(0,14)
	var a := 1.0-p
	ground_disc(g,c,22+14*ease_out(p*2),Color(col,0.35*a))
	ground_ring(g,c,16+34*ease_out(p*1.5),Color(col,0.95*a),4)
	ground_ring(g,c,10+20*ease_out(p*1.5),Color(col.lightened(0.4),0.7*a),2)
	for k: int in range(6):
		var d := Vector2.from_angle(h(s,k)*TAU)*Vector2(1,0.42)*(12+26*ease_out(p*2.5))
		g.draw_line(c,c+d,Color(0.20,0.12,0.06,0.85*a),2.5,true)
	if p < 0.55:
		var beam := (0.55-p)/0.55
		g.draw_line(c,c+Vector2(0,-90*beam),Color(col,0.35*beam),18,true)
		g.draw_line(c,c+Vector2(0,-90*beam),Color(col.lightened(0.6),0.9*beam),5,true)
	for i: int in range(10):
		var q := clampf(p*1.3-h(s,i+7)*0.25,0,1)
		g.draw_circle(c+Vector2((h(s,i+3)-0.5)*46,-q*56),3.4,Color(col.lightened(0.4),(1-q)*a))
	for k: int in range(3):
		var q := clampf(p*1.2,0,1)
		g.draw_circle(c+Vector2((k-1)*22*q,-4-q*10),6+q*9,Color(DUST,(1-q)*0.4))

# The corpse giant bursting: bone shards fly out spinning.
static func boneburst(g, e: Dictionary, p: float) -> void:
	var s := seed_of(e)
	var c: Vector2 = e.pos
	summon(g,e,p,Color(0.55,0.38,0.60))
	for i: int in range(12):
		var a := h(s,i)*TAU
		var q := clampf(p*1.4,0,1)
		var d := c+Vector2(cos(a),sin(a)*0.5)*80*q+Vector2(0,-60*sin(q*PI))
		var spin := Vector2.from_angle(q*9+i)*10
		if q < 1:
			g.draw_line(d-spin,d+spin,Color(0.92,0.88,0.78,1-q),4,true)
			g.draw_circle(d+spin,3,Color(0.92,0.88,0.78,1-q))

# ---------------------------------------------------------------- small cues
static func repair(g, e: Dictionary, p: float) -> void:
	var c: Vector2 = e.pos+Vector2(0,-26-p*22)
	var col := Color(0.92,0.78,0.34,1-p)
	g.draw_line(c+Vector2(-9,0),c+Vector2(9,0),Color(0.3,0.2,0.1,(1-p)*0.6),7,true)
	g.draw_line(c+Vector2(0,-9),c+Vector2(0,9),Color(0.3,0.2,0.1,(1-p)*0.6),7,true)
	g.draw_line(c+Vector2(-9,0),c+Vector2(9,0),col,4,true)
	g.draw_line(c+Vector2(0,-9),c+Vector2(0,9),col,4,true)
	if p < 0.45:
		for i: int in range(7):
			var d := Vector2.from_angle(-PI*0.05-i*PI*0.15)
			var o: Vector2 = e.pos+Vector2(0,-10)
			g.draw_line(o+d*(6+p*44),o+d*(12+p*50),Color(1,0.9,0.5,(0.45-p)*2.2),2.5,true)

static func blood_gain(g, e: Dictionary, p: float) -> void:
	var c: Vector2 = e.pos+Vector2(0,-24-p*36)
	var red := Color(0.72,0.06,0.15,1-p)
	g.draw_line(c+Vector2(0,6),c+Vector2(0,6+p*18),Color(red,(1-p)*0.45),3,true)
	g.draw_circle(c,6,red)
	g.draw_colored_polygon(PackedVector2Array([c+Vector2(-5.4,-2),c+Vector2(0,-14),c+Vector2(5.4,-2)]),red)
	g.draw_circle(c+Vector2(-2,-1),1.8,Color(1,0.7,0.7,(1-p)*0.8))

static func heal(g, e: Dictionary, p: float) -> void:
	var green := Color("5ce675")
	ground_disc(g,e.pos+Vector2(0,12),20+p*14,Color(green,(1-p)*0.25))
	ground_ring(g,e.pos+Vector2(0,12),20+p*14,Color(green,(1-p)*0.85),2.5)
	for i: int in range(3):
		var q := clampf(p*1.3-i*0.15,0,1)
		var c: Vector2 = e.pos+Vector2((i-1)*14,-22-q*34)
		var col := Color(green.lightened(0.25),1-q)
		g.draw_line(c+Vector2(-6,0),c+Vector2(6,0),Color(0.1,0.35,0.15,(1-q)*0.5),6,true)
		g.draw_line(c+Vector2(0,-6),c+Vector2(0,6),Color(0.1,0.35,0.15,(1-q)*0.5),6,true)
		g.draw_line(c+Vector2(-6,0),c+Vector2(6,0),col,3.5,true)
		g.draw_line(c+Vector2(0,-6),c+Vector2(0,6),col,3.5,true)

static func curse_rise(g, e: Dictionary, p: float) -> void:
	var col := Color("926c9d")
	ground_disc(g,e.pos+Vector2(0,10),14+p*30,Color(col,(1-p)*0.3))
	ground_ring(g,e.pos+Vector2(0,10),14+p*30,Color(col,1-p),3)
	for i: int in range(4):
		var a := i*TAU/4+p*5
		var c: Vector2 = e.pos+Vector2(cos(a)*18*(1-p),-p*48+sin(a)*6)
		g.draw_circle(c,6*(1-p)+2,Color("c89fe0",1-p))

static func cultivate(g, e: Dictionary, p: float) -> void:
	var s := seed_of(e)
	ground_ring(g,e.pos+Vector2(0,8),8+p*22,Color(DUST,(1-p)*0.75),2.5)
	for i: int in range(8):
		var v := Vector2((h(s,i)-0.5)*60,-44-18*h(s,i+3))
		g.draw_circle(e.pos+v*p+Vector2(0,90*p*p),3.6,Color(0.48,0.34,0.14,1-p*0.6))

static func catapult_fire(g, e: Dictionary, p: float) -> void:
	var s := seed_of(e)
	ground_ring(g,e.pos+Vector2(0,10),16+p*36,Color(DUST,(1-p)*0.8),3)
	for i: int in range(7):
		var a := h(s,i)*TAU
		var drift := Vector2(cos(a)*(8+18*p),-6-p*(22+20*h(s,i+3))+sin(a)*5)
		g.draw_circle(e.pos+drift,6+p*12*(0.6+0.4*h(s,i+6)),Color(SMOKE.lightened(0.15*h(s,i+9)),(1-p)*0.42))

# Lingering fire (5 s): flames that die down over a scorch mark.
static func burn(g, e: Dictionary, p: float) -> void:
	ground_disc(g,e.pos,38,Color(0.15,0.07,0.02,0.4*(1-p)))
	var s := seed_of(e)
	var strength := 1.0-p
	for i: int in range(6):
		var b: Vector2 = e.pos+Vector2((h(s,i)-0.5)*56,(h(s,i+5)-0.5)*18)
		var flicker := 0.75+0.25*sin(p*70+i*2.1)
		flame(g,b,(18+14*h(s,i+2))*strength*flicker,7,sin(p*30+i)*4,0.85*strength)

static func hit_spark(g, e: Dictionary, p: float) -> void:
	var s := seed_of(e)
	var at: Vector2 = e.pos + Vector2(0.0, -18.0)
	var a := 1.0 - p
	var attacker: String = String(e.get("attacker", ""))
	var target: String = String(e.get("target", ""))
	var is_shield := target in ["shieldguard", "barricade", "bonewall"]
	var is_magic := attacker in ["dark_wizard", "prism_mage", "spell_tide_magus", "arcane_archer", "arcane_tower", "chronomancer", "orrery_walker", "old_witch", "seal_bearer", "plague_bishop", "lord_mage", "lord_rune", "lord_underworld"]
	var is_heavy := attacker.begins_with("giant_") or attacker in ["corpse_giant", "arcane_golem", "bog_troll", "thorn_dragon", "dire_hydra", "tusk_boar", "gold_monster", "thorn_mother", "knight", "reaper", "ram", "lord_iron", "lord_beast", "lord_lion", "lord_vampire", "lord_adventure"]
	if is_shield:
		var r := 10.0 + p * 14.0
		g.draw_arc(at, r, -PI * 0.55, PI * 0.55, 14, Color("e8d294", a * 0.9), 2.6, true)
		g.draw_line(at + Vector2(-7, 0), at + Vector2(7, 0), Color(1.0, 0.96, 0.80, a * 0.85), 2.0, true)
		g.draw_line(at + Vector2(0, -7), at + Vector2(0, 7), Color(1.0, 0.96, 0.80, a * 0.85), 2.0, true)
		return
	if is_magic:
		var mcol := Color("a88ce8")
		var r := 7.0 + p * 16.0
		g.draw_circle(at, 6.0 * a + 2.0, Color(mcol, a * 0.45))
		for k: int in range(4):
			var ang := k * PI * 0.5 + h(s, 3) * 0.6
			var d := Vector2.from_angle(ang)
			g.draw_line(at + d * 3.0, at + d * r, Color(0.92, 0.90, 1.0, a * 0.9), 1.8, true)
		return
	if is_heavy:
		var r := 12.0 + ease_out(p) * 20.0
		g.draw_arc(at, r, 0.0, TAU, 18, Color("f0c458", a * 0.75), 2.4, true)
		for k: int in range(3):
			var ang := (h(s, k) - 0.5) * 2.4 + (0.0 if int(e.get("team", 0)) == 1 else PI)
			var d := Vector2.from_angle(ang)
			g.draw_line(at + d * (4.0 + p * 6.0), at + d * (14.0 + p * 18.0), Color("fff0c0", a * 0.9), 2.2, true)
		return
	for k: int in range(3):
		var ang := h(s, k + 11) * TAU
		var d := Vector2.from_angle(ang)
		g.draw_line(at + d * (3.0 + p * 5.0), at + d * (10.0 + p * 12.0), Color(0.28, 0.20, 0.14, a * 0.72), 2.0, true)
		g.draw_line(at + d * (3.0 + p * 5.0), at + d * (9.0 + p * 10.0), Color(1.0, 0.93, 0.75, a * 0.85), 1.2, true)

static func wall_chip(g, e: Dictionary, p: float) -> void:
	var s := seed_of(e)
	var a := 1.0 - p
	var dir := 1.0 if int(e.get("team", 0)) == 0 else -1.0
	for i: int in range(5):
		var vy := -24.0 - h(s, i + 1) * 26.0
		var vx := dir * (14.0 + h(s, i + 7) * 24.0)
		var pt: Vector2 = e.pos + Vector2(vx * p, vy * p + 65.0 * p * p - 12.0 + (h(s, i + 13) - 0.5) * 32.0)
		g.draw_circle(pt, 2.2 + h(s, i + 19) * 1.8, Color(0.55, 0.48, 0.36, a * 0.85))
	ground_ring(g, e.pos + Vector2(dir * 10.0, 12.0), 10.0 + p * 18.0, Color(DUST, a * 0.55), 2.0)
