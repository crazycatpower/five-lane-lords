extends RefCounted
# 標題畫面（2026-11-21 重做）：右側一根軍旗桿掛著四面隨風飄動的模式旗，進場時依序展開；
# 左側是會動的小戰場（民兵與食屍鬼來回交鋒、獵人放箭、兩面戰旗），下方是攤開的牌組扇與翻動的圖鑑。
# 所有按鈕仍是真正可聚焦的 Button（文字保留給測試與輔助工具，畫面上隱藏），外觀全部在 paint 裡畫。
const ART = preload("res://manuscript_art.gd")
const CREAM := Color("fff0ca")
const GOLD := Color("d2ad58")
const GOLD_LIT := Color("ffe39a")
const POLE_X := 1502.0
const FLAG_X := 924.0
const FLAG_W := 566.0
# id, hit rect, cloth colour, caption, icon
const FLAGS := [
	["net",Rect2(FLAG_X,180,FLAG_W,160),Color("963f30"),"對戰（尋找對手）","lord"],
	["adventure",Rect2(FLAG_X,358,FLAG_W,124),Color("3b5662"),"冒險模式","militia"],
	["rogue",Rect2(FLAG_X,500,FLAG_W,90),Color("8a5a2b"),"肉鴿模式","ghoul"],
	["watch",Rect2(FLAG_X,608,FLAG_W,90),Color("4c5032"),"觀戰模式","hunter"],
]
const FLAG_NOTES := {
	"rogue":"八場連戰、邊打邊換牌，輸一場就結束",
	"watch":"兩邊都交給 AI，看牌組怎麼打",
}
const DECK_HIT := Rect2(96,724,300,150)
const CODEX_HIT := Rect2(440,724,300,150)
const CODEX_CARDS := ["militia","hunter","farm","skeleton","ghoul","grave","reaper"]
static var opened_at := 0.0 # g.clock when the entrance started (-1 = not yet): game time, so recordings play it at true speed
static var buttons := {} # id -> Button

static func build(g) -> void:
	opened_at = -1.0 # the entrance starts on the first painted frame, after any loading
	buttons.clear()
	g.adventure.load_progress()
	var actions := {"net":g.show_net,"adventure":g.show_adventure,"rogue":g.show_rogue,"watch":g.show_watch}
	for f: Array in FLAGS: entry(g,f[0],f[1],f[3],actions[f[0]])
	entry(g,"deck",DECK_HIT,"牌組編成",g.show_deck)
	entry(g,"codex",CODEX_HIT,"卡牌圖鑑",func(): g.library.open())
	for tab: Array in tabs(): entry(g,tab[0],tab[1],tab[2],tab[3].call(g))

static func tabs() -> Array:
	var items: Array = []
	if not OS.has_feature("web"): items.append(["record","錄影模式",func(g): return func(): preload("res://recording_mode.gd").open(g)])
	items.append(["help","操作說明",func(g): return g.show_help])
	items.append(["settings","設定",func(g): return g.show_settings])
	if not OS.has_feature("web"): items.append(["quit","離開",func(g): return func(): g.get_tree().quit()])
	var gap := 14.0
	var w := (FLAG_W-gap*(items.size()-1))/items.size()
	var out: Array = []
	for i: int in range(items.size()):
		out.append([items[i][0],Rect2(FLAG_X+i*(w+gap),742,w,46),items[i][1],items[i][2]])
	return out

# An invisible, focusable button: the picture underneath is painted, the caption stays for tools.
static func entry(g, id: String, r: Rect2, caption: String, action: Callable) -> void:
	var b: Button = g.title_button(r,caption,action)
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		b.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	for state: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_disabled_color"]:
		b.add_theme_color_override(state,Color(0,0,0,0))
	buttons[id] = b

# ---------------------------------------------------------------- timing helpers
static func live(g) -> bool:
	return g.is_processing() and DisplayServer.get_name() != "headless"

static func since(g) -> float:
	if not live(g): return 99.0
	if opened_at < 0.0: opened_at = g.clock
	return g.clock-opened_at

static func ease_out(t: float) -> float:
	var c := clampf(t,0.0,1.0)
	return 1.0-pow(1.0-c,3.0)

static func ease_back(t: float) -> float:
	var c := clampf(t,0.0,1.0)-1.0
	return 1.0+2.70158*c*c*c+1.70158*c*c

static func hover(g, id: String, r: Rect2) -> float:
	var b: Button = buttons.get(id)
	var on := r.has_point(g.get_global_mouse_position())
	var hv: float = g.polish.hover_val("title_"+id,on,live(g))
	if b != null and is_instance_valid(b):
		if b.has_focus(): hv = maxf(hv,0.6)
		if b.button_pressed or (on and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)): hv = maxf(hv,0.4)
	return hv

static func focused(id: String) -> bool:
	var b: Button = buttons.get(id)
	return b != null and is_instance_valid(b) and b.has_focus()

# ---------------------------------------------------------------- paint
static func paint(g) -> void:
	var t := since(g)
	var clock: float = g.clock if g.fx_enabled else 0.0
	heading(g,t)
	diorama(g,clock)
	deck_fan(g,t,clock)
	codex(g,t,clock)
	standard(g,t,clock)
	for i: int in range(FLAGS.size()): flag(g,i,t,clock)
	for i: int in range(tabs().size()): tab(g,i,t)
	g.draw_string(g.font,Vector2(1380,866),"v"+g.VERSION,HORIZONTAL_ALIGNMENT_RIGHT,180,15,Color(g.INK,0.5))

static func heading(g, t: float) -> void:
	var a := ease_out(t/0.55)
	# The vine ornament grows outward from the middle.
	var orn_w := 580.0*ease_out((t-0.1)/0.6)
	if orn_w > 4.0: g.draw_fitted(ART.ornament(4),Rect2(420-orn_w*0.5,50,orn_w,50),Color(1,1,1,a))
	# The title lands like a stamp: a little large at first, settling into place.
	var s := lerpf(1.28,1.0,ease_back(t/0.6))
	var c := Vector2(420,160)
	g.tf(c,0.0,Vector2(s,s))
	g.draw_string(g.font,Vector2(-360,26)+Vector2(3,4),"羊皮紙戰記",HORIZONTAL_ALIGNMENT_CENTER,720,84,Color(0.18,0.12,0.06,0.18*a))
	g.draw_string(g.font,Vector2(-360,26),"羊皮紙戰記",HORIZONTAL_ALIGNMENT_CENTER,720,84,Color(g.INK,a))
	g.tf()
	# Red wax seal stamped beside the title.
	var st := (t-0.5)/0.3
	if st > 0.0:
		var ss := lerpf(2.2,1.0,ease_out(st))
		var sa := clampf(st*2.0,0.0,1.0)
		var sc := Vector2(668,104)
		if st < 1.6: g.draw_arc(sc,30+st*40,0,TAU,40,Color(0.6,0.2,0.15,0.5*(1.0-st/1.6)),3.0,true)
		g.tf(sc,-0.22,Vector2(ss,ss))
		var rim := PackedVector2Array()
		for i: int in range(30):
			var ang := TAU*i/30.0
			rim.append(Vector2.from_angle(ang)*(30+2.0*sin(ang*6.0+0.7)))
		g.draw_colored_polygon(rim,Color(0.58,0.18,0.13,sa))
		g.draw_arc(Vector2.ZERO,23,0,TAU,32,Color(0.35,0.08,0.05,0.6*sa),2.0,true)
		g.draw_string(g.font,Vector2(-30,10),"戰",HORIZONTAL_ALIGNMENT_CENTER,60,28,Color(1,0.9,0.78,sa))
		g.tf()
	# The motto writes itself out.
	var motto := "種下村莊，寫下你的戰史。"
	var shown := clampi(int((t-0.35)/0.05),0,motto.length())
	if shown > 0:
		g.draw_string(g.font,Vector2(60,236),motto.left(shown),HORIZONTAL_ALIGNMENT_CENTER,720,24,g.INK)

# The little battlefield: two rows of a skirmish that never quite ends.
static func diorama(g, clock: float) -> void:
	g.draw_colored_polygon(PackedVector2Array([Vector2(465,410),Vector2(505,410),Vector2(541,452),Vector2(568,496),Vector2(618,549),Vector2(670,604),Vector2(751,681),Vector2(605,681),Vector2(577,613),Vector2(543,550),Vector2(517,501),Vector2(493,451)]),Color(0.76,0.68,0.46,0.16))
	g.ground_wash(Vector2(240,501),Vector2(200,150),Color("b5b66f"),72,0.06)
	g.ground_wash(Vector2(730,501),Vector2(150,150),Color("655a70"),81,0.06)
	war_flag(g,Vector2(312,336),Color("963f30"),clock,false)
	war_flag(g,Vector2(820,330),Color("4a4458"),clock,true)
	for row: int in range(2):
		var y := 398.0+row*119
		var phase := fposmod(clock/3.2+row*0.5,1.0)
		var lunge := pow(maxf(0.0,sin(phase*TAU)),3.0)
		g.draw_fitted(g.art("farm"),Rect2(72,y-32,146,103),Color.WHITE,true)
		g.draw_fitted(g.art("grave",1),Rect2(758,y-32,89,106),Color.WHITE,true)
		# Arrow volley: loosed every 2.4 s, lands on the skeleton, which flinches.
		var shot := fposmod(clock/2.4+row*0.37,1.0)
		var flight := shot/0.38
		var flinch := 0.0
		if flight > 1.0 and flight < 1.6: flinch = sin((flight-1.0)/0.6*PI)
		g.title_soldier("hunter",Vector2(262,y+38),0,1.12)
		g.title_soldier("militia",Vector2(366+lunge*26.0,y+56),0,1.32)
		g.title_soldier("skeleton",Vector2(690+flinch*8.0,y+38),1,1.22)
		g.title_soldier("ghoul",Vector2(579-lunge*22.0,y+56),1,1.38)
		if g.fx_enabled and flight <= 1.0:
			var from := Vector2(292,y+14)
			var to := Vector2(672,y+18)
			var p := from.lerp(to,flight)+Vector2(0,-70.0*sin(flight*PI))
			var ahead := from.lerp(to,minf(1.0,flight+0.04))+Vector2(0,-70.0*sin(minf(1.0,flight+0.04)*PI))
			var dir := (ahead-p).normalized()
			g.draw_line(p-dir*18,p,Color(g.INK,0.85),2.0,true)
			g.draw_colored_polygon(PackedVector2Array([p+dir*6,p+dir.orthogonal()*3,p-dir.orthogonal()*3]),g.INK)
		if g.fx_enabled and flinch > 0.0:
			for k: int in range(5):
				var d := Vector2.from_angle(k*1.3+row)*(8+flinch*14)
				g.draw_line(Vector2(676,y+16)+d*0.5,Vector2(676,y+16)+d,Color(0.95,0.9,0.75,flinch),1.5,true)
		# Where militia and ghoul meet: dust and a glint of steel.
		if g.fx_enabled and lunge > 0.55:
			var k2 := (lunge-0.55)/0.45
			var hit := Vector2(478,y+30)
			for j: int in range(6):
				var d := Vector2.from_angle(-PI*0.5+(j-2.5)*0.45)*(10+k2*20)
				g.draw_line(hit+d*0.4,hit+d,Color(1.0,0.92,0.6,k2*0.9),2.0,true)
			for j: int in range(4):
				g.draw_circle(hit+Vector2((j-1.5)*16,46),6+k2*8,Color(0.75,0.66,0.48,0.25*k2))
	var lord_step := sin(clock*1.1)*4.0
	g.title_soldier("lord_"+g.player_lord,Vector2(409+lord_step,649),0,1.55)
	g.title_soldier("reaper",Vector2(596-lord_step,649),1,1.55)

# A standard on a pole, its cloth blowing out to the right (same wind for both sides).
static func war_flag(g, base: Vector2, col: Color, clock: float, tattered: bool) -> void:
	var top := base
	var foot := base+Vector2(0,150)
	g.draw_line(top+Vector2(2,2),foot+Vector2(2,2),Color(0,0,0,0.2),5.0,true)
	g.draw_line(top,foot,Color("5b4330"),5.0,true)
	g.draw_circle(top+Vector2(0,-4),5,GOLD)
	var w := 92.0
	var h := 54.0
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for i: int in range(13):
		var u := i/12.0
		var wave := sin(u*5.0-clock*3.2+base.x)*7.0*u
		upper.append(top+Vector2(u*w,4+wave))
		var hang := h-u*6.0
		if tattered and i > 8: hang -= (i%2)*10.0
		lower.append(top+Vector2(u*w-u*4.0,4+hang+wave*1.1))
	for i: int in range(12):
		var shade := 0.10*cos(i/12.0*5.0-clock*3.2+base.x)
		g.draw_colored_polygon(PackedVector2Array([upper[i],upper[i+1],lower[i+1],lower[i]]),col.lightened(shade) if shade > 0 else col.darkened(-shade))
	var mid := upper[5].lerp(lower[5],0.5)
	g.draw_circle(mid,11,Color(GOLD,0.85) if not tattered else Color(0.85,0.82,0.72,0.7))
	g.draw_circle(mid,6,col.darkened(0.2))

static func card_back(g, r: Rect2) -> void:
	g.draw_rect(Rect2(r.position+Vector2(2,3),r.size),Color(0,0,0,0.25))
	g.draw_texture_rect(ART.card(false),r,false,Color(0.55,0.42,0.32))
	g.draw_rect(r.grow(-8),Color(0.30,0.18,0.12,0.55))
	g.draw_rect(r.grow(-8),Color(GOLD,0.8),false,1.5)
	var c := r.get_center()
	g.draw_colored_polygon(PackedVector2Array([c+Vector2(0,-18),c+Vector2(13,0),c+Vector2(0,18),c+Vector2(-13,0)]),Color(GOLD,0.85))
	g.draw_circle(c,5,Color(0.30,0.18,0.12))

# Rotate a card around a pivot below the fan, then draw it in that frame.
static func fan_card(g, pivot: Vector2, angle: float, reach: float, size: Vector2, kind: String, flip: float = 1.0) -> void:
	var xf := Transform2D(angle,Vector2(flip,1.0),0.0,pivot)*Transform2D(0.0,Vector2(0,-reach))
	g.ui_xform = xf
	g.draw_set_transform_matrix(xf)
	var r := Rect2(-size*0.5,size)
	if kind.is_empty(): card_back(g,r)
	else:
		g.draw_rect(Rect2(r.position+Vector2(3,5),r.size),Color(0,0,0,0.28))
		g.draw_card(kind,r)
	g.ui_xform = Transform2D.IDENTITY
	g.draw_set_transform_matrix(Transform2D.IDENTITY)

static func label_ribbon(g, center: Vector2, text: String, hv: float, col: Color, focus: bool) -> void:
	var r := Rect2(center-Vector2(110,17),Vector2(220,34))
	var pts := PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),Vector2(r.end.x-12,r.get_center().y),r.end,Vector2(r.position.x,r.end.y),Vector2(r.position.x+12,r.get_center().y)])
	var sh := PackedVector2Array()
	for p: Vector2 in pts: sh.append(p+Vector2(2,4))
	g.draw_colored_polygon(sh,Color(0,0,0,0.3))
	g.draw_colored_polygon(pts,col.lightened(0.12*hv))
	g.draw_line(r.position+Vector2(8,4),Vector2(r.end.x-8,r.position.y+4),Color(GOLD,0.8),1.2,true)
	g.draw_line(Vector2(r.position.x+8,r.end.y-4),r.end-Vector2(8,4),Color(GOLD,0.8),1.2,true)
	g.draw_string(g.font,r.position+Vector2(0,25),text,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,22,CREAM)
	if focus: g.draw_rect(r.grow(5),Color(GOLD_LIT,0.9),false,2.0)

static func deck_fan(g, t: float, clock: float) -> void:
	var hv := hover(g,"deck",DECK_HIT)
	var rise := (1.0-ease_out((t-0.25)/0.5))*160.0
	var pivot := Vector2(DECK_HIT.get_center().x,1010+rise-10.0*hv+sin(clock*1.4)*2.0)
	if hv > 0.01: g.draw_circle(pivot+Vector2(0,-215),100,Color(1,0.85,0.45,0.12*hv))
	var cards: Array = g.player_deck.filter(func(k: String) -> bool: return g.B.CARDS.has(k)).slice(0,3)
	while cards.size() < 3: cards.append("")
	var spread := 0.24+0.10*hv
	for i: int in [0,2,1]:
		var a := (i-1)*spread+sin(clock*1.2+i)*0.012
		fan_card(g,pivot,a,220.0+8.0*hv,Vector2(98,136),cards[i])
	label_ribbon(g,Vector2(DECK_HIT.get_center().x,858+rise),"牌組編成",hv,Color("714838"),focused("deck"))

static func codex(g, t: float, clock: float) -> void:
	var hv := hover(g,"codex",CODEX_HIT)
	var rise := (1.0-ease_out((t-0.35)/0.5))*160.0
	var pivot := Vector2(CODEX_HIT.get_center().x,1010+rise-10.0*hv+sin(clock*1.4+1.0)*2.0)
	if hv > 0.01: g.draw_circle(pivot+Vector2(0,-215),100,Color(0.6,0.85,1.0,0.12*hv))
	var spread := 0.20+0.10*hv
	fan_card(g,pivot,-spread,214.0,Vector2(92,128),"")
	fan_card(g,pivot,spread,214.0,Vector2(92,128),"")
	# The front card turns over every few seconds to show another entry.
	var period := 3.0
	var cycle := clock/period
	var idx := int(floor(cycle))%CODEX_CARDS.size()
	var k := fposmod(cycle,1.0)
	var flip := 1.0
	var kind: String = CODEX_CARDS[idx]
	if k > 0.86:
		var f := (k-0.86)/0.14
		flip = maxf(0.02,absf(cos(f*PI)))
		if f > 0.5: kind = CODEX_CARDS[(idx+1)%CODEX_CARDS.size()]
	fan_card(g,pivot,sin(clock*0.9)*0.02,222.0+10.0*hv,Vector2(100,138),kind,flip)
	label_ribbon(g,Vector2(CODEX_HIT.get_center().x,858+rise),"卡牌圖鑑",hv,Color("39565a"),focused("codex"))

# The campaign standard the mode flags hang from.
static func standard(g, t: float, clock: float) -> void:
	var a := ease_out(t/0.4)
	g.draw_string(g.font,Vector2(FLAG_X,150),"五路戰線 · 一卷戰史",HORIZONTAL_ALIGNMENT_CENTER,FLAG_W,27,Color(g.INK,a))
	var rule_w := 200.0*ease_out((t-0.15)/0.5)
	var mid := FLAG_X+FLAG_W*0.5
	g.draw_line(Vector2(mid-rule_w,160),Vector2(mid-150,160),Color(g.INK,0.4),1.2,true)
	g.draw_line(Vector2(mid+150,160),Vector2(mid+rule_w,160),Color(g.INK,0.4),1.2,true)
	var top := 168.0
	var foot := 712.0
	g.draw_line(Vector2(POLE_X+4,top+4),Vector2(POLE_X+4,foot+4),Color(0,0,0,0.22),9.0,true)
	g.draw_line(Vector2(POLE_X,top),Vector2(POLE_X,foot),Color("604831"),9.0,true)
	g.draw_line(Vector2(POLE_X-2,top),Vector2(POLE_X-2,foot),Color(1,0.9,0.7,0.18),2.0,true)
	# Gilt finial with a glint that comes and goes.
	g.draw_colored_polygon(PackedVector2Array([Vector2(POLE_X,top-34),Vector2(POLE_X+8,top-8),Vector2(POLE_X,top-2),Vector2(POLE_X-8,top-8)]),GOLD)
	g.draw_circle(Vector2(POLE_X,top),9,Color("b58a43"))

static func cloth_edges(r: Rect2, width: float, idx: int, clock: float, amp: float) -> Array:
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	var n := 24
	for i: int in range(n+1):
		var u := i/float(n) # 0 at the pole, 1 at the free end
		var wave := sin(u*4.6-clock*2.8+idx*1.3)*amp*u
		var x := r.end.x-u*width
		upper.append(Vector2(x,r.position.y+wave))
		lower.append(Vector2(x,r.end.y+wave*1.08))
	return [upper,lower]

static func flag(g, i: int, t: float, clock: float) -> void:
	var f: Array = FLAGS[i]
	var id: String = f[0]
	var r: Rect2 = f[1]
	var col: Color = f[2]
	var hv := hover(g,id,r)
	var unfurl := ease_back((t-0.12-i*0.09)/0.5)
	if unfurl <= 0.01: return
	var attach := Rect2(r.position,Vector2(POLE_X-4.0-r.position.x,r.size.y)) # the cloth hangs from the pole
	var width := (attach.size.x-14.0)*unfurl+14.0*hv # hovering lets it blow out a little further
	var amp := 2.6+3.2*hv+(1.0-clampf(unfurl,0.0,1.0))*6.0
	var edges := cloth_edges(attach,width,i,clock,amp)
	var upper: PackedVector2Array = edges[0]
	var lower: PackedVector2Array = edges[1]
	var n := upper.size()-1
	var tail := minf(26.0,width*0.35) # a sliver of cloth while unfurling has a small notch
	var notch := upper[n].lerp(lower[n],0.5)+Vector2(tail,0)
	# Drop shadow, then the cloth in strips shaded by the ripple.
	var outline := PackedVector2Array()
	for p: Vector2 in upper: outline.append(p)
	outline.append(notch)
	for k: int in range(n,-1,-1): outline.append(lower[k])
	var shadow := PackedVector2Array()
	for p: Vector2 in outline: shadow.append(p+Vector2(6,8))
	g.draw_colored_polygon(shadow,Color(0.12,0.08,0.04,0.22))
	g.draw_colored_polygon(outline,col.lightened(0.10*hv))
	for k: int in range(n-2): # folds: light where the ripple faces up, shadow where it turns away
		var shade := 0.12*cos(k/float(n)*4.6-clock*2.8+i*1.3)
		g.draw_colored_polygon(PackedVector2Array([upper[k],upper[k+1],lower[k+1],lower[k]]),Color(1,1,1,shade) if shade > 0 else Color(0,0,0,-shade*0.9))
	g.draw_texture_rect(g.PAPER,Rect2(upper[n].x,r.position.y,width,r.size.y),false,Color(1,1,1,0.07))
	# Gilt trims follow the cloth.
	var trim_a := PackedVector2Array()
	var trim_b := PackedVector2Array()
	for k: int in range(n+1):
		trim_a.append(upper[k]+Vector2(0,7))
		trim_b.append(lower[k]-Vector2(0,7))
	var trim := Color("d5b16e").lerp(Color("fff2c4"),hv*0.6)
	g.draw_polyline(trim_a,trim,1.5+0.6*hv,true)
	g.draw_polyline(trim_b,trim,1.5+0.6*hv,true)
	var rim := outline.duplicate()
	rim.append(outline[0])
	g.draw_polyline(rim,Color("2a1b10",0.85),2.0,true)
	# Rings that hold the flag to the pole.
	for y: float in [r.position.y+10,r.end.y-10]:
		g.draw_arc(Vector2(POLE_X,y),7,0,TAU,16,Color("b58a43"),3.0,true)
	if unfurl < 0.6: return
	var ta := clampf((unfurl-0.6)/0.4,0.0,1.0)
	# Content rides the ripple at the flag's middle.
	var free_x := upper[n].x
	var mid_u := 0.5
	var dy := sin(mid_u*4.6-clock*2.8+i*1.3)*amp*mid_u
	var icon_r := clampf(r.size.y*0.30,24.0,42.0)
	var icon_c := Vector2(free_x+tail+icon_r+16,r.get_center().y+sin(0.85*4.6-clock*2.8+i*1.3)*amp*0.85)
	medallion(g,icon_c,icon_r*(1.0+0.10*hv),f[4],ta)
	var text_x := icon_c.x+icon_r+12
	var text_w := r.end.x-26-text_x
	var light := Color(CREAM,ta)
	var soft := Color(Color("e5cda1").lerp(Color("fff6df"),hv*0.5),ta)
	match id:
		"net":
			g.draw_string(g.font,Vector2(text_x,r.position.y+64+dy),f[3],HORIZONTAL_ALIGNMENT_CENTER,text_w,36,light)
			g.draw_string(g.font,Vector2(text_x,r.position.y+102+dy),"出征領主：%s · 牌組 %d 張" % [g.B.LORDS[g.player_lord].name,g.player_deck.size()],HORIZONTAL_ALIGNMENT_CENTER,text_w,18,light)
			g.draw_string(g.font,Vector2(text_x,r.position.y+130+dy),"搜尋線上對手 · 不足補 AI · 自由練習／好友房",HORIZONTAL_ALIGNMENT_CENTER,text_w,15,soft)
		"adventure":
			g.draw_string(g.font,Vector2(text_x,r.position.y+44+dy),f[3],HORIZONTAL_ALIGNMENT_CENTER,text_w,28,light)
			adventure_progress(g,text_x,text_w,r.position.y+dy,ta)
		_:
			g.draw_string(g.font,Vector2(text_x,r.position.y+42+dy),f[3],HORIZONTAL_ALIGNMENT_CENTER,text_w,26,light)
			g.draw_string(g.font,Vector2(text_x,r.position.y+70+dy),FLAG_NOTES[id],HORIZONTAL_ALIGNMENT_CENTER,text_w,15,soft)
	if focused(id): g.draw_polyline(rim,Color(GOLD_LIT,0.95),3.0,true)

static func medallion(g, c: Vector2, rad: float, icon: String, a: float) -> void:
	g.draw_circle(c+Vector2(2,3),rad+3,Color(0,0,0,0.25*a))
	g.draw_circle(c,rad+3,Color(GOLD.darkened(0.15),a))
	g.draw_circle(c,rad,Color(Color("f3e3bd"),a))
	var kind: String = "lord_"+g.player_lord if icon == "lord" else icon
	var tex: Texture2D = g.art(kind,0)
	if tex != null: g.draw_fitted(tex,Rect2(c-Vector2(rad,rad)*0.92,Vector2(rad,rad)*1.84),Color(1,1,1,a),true)
	g.draw_arc(c,rad,0,TAU,40,Color(0.35,0.24,0.14,0.6*a),1.5,true)

# Chapter progress on the adventure flag; the first chapter names the next lesson.
static func adventure_progress(g, x: float, w: float, y: float, a: float) -> void:
	var adv = g.adventure
	var count: int = adv.STAGES.size()
	var next: int = adv.frontier()
	var done: int = adv.cleared_count()
	var line := "五域已一統！★ %d · 可開新周目" % adv.total_stars() if done == count else "遠征 %d / %d · ★ %d · 下一關：「%s」" % [done,count,adv.total_stars(),adv.STAGES[next].name]
	if not adv.tutorial_done():
		var nd: Dictionary = adv.STAGES[next]
		var label: String = "畢業考" if nd.boss else ("小考" if nd.special else "第 %s 課" % String(nd.code).get_slice("-",1))
		line = "新手從這裡開始 · %s「%s」" % [label,nd.rule_tag]
	g.draw_string(g.font,Vector2(x,y+70),line,HORIZONTAL_ALIGNMENT_CENTER,w,16,Color(Color("fff5df"),a))
	var per: int = adv.Catalog.STAGES_PER_WORLD
	var frontier_w: int = int(adv.STAGES[next].world) if done < count else -1
	var n: int = adv.WORLDS.size()
	var pw := minf(84.0,(w-8.0*(n-1))/n)
	var x0 := x+(w-(pw*n+8.0*(n-1)))*0.5
	for wi: int in range(n):
		var r := Rect2(x0+wi*(pw+8.0),y+82,pw,18)
		var w_done: int = adv.world_cleared_count(wi)
		g.draw_rect(r,Color(0.15,0.10,0.06,0.42*a))
		if w_done > 0:
			var c: Color = adv.WORLDS[wi].color if w_done < per else Color("963f30")
			g.draw_rect(Rect2(r.position,Vector2(r.size.x*float(w_done)/per,r.size.y)),Color(c,0.88*a))
		var lit: bool = wi == frontier_w
		var pulse := 0.5+0.5*sin(float(g.clock)*3.0) if lit and g.fx_enabled else 0.0
		g.draw_rect(r.grow(pulse*1.5),Color(Color("f4d78c"),a) if lit else Color(Color("e5cda1"),0.65*a),false,2.0 if lit else 1.2)
		g.draw_string(g.font,r.position+Vector2(0,13),"✓" if w_done == per else "%d/%d" % [w_done,per],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,12,Color(Color("fff5df"),a))

static func tab(g, i: int, t: float) -> void:
	var item: Array = tabs()[i]
	var id: String = item[0]
	var r: Rect2 = item[1]
	var hv := hover(g,id,r)
	var k := ease_out((t-0.55-i*0.06)/0.35)
	if k <= 0.01: return
	var rr := Rect2(r.position+Vector2(0,(1.0-k)*24.0-3.0*hv),r.size)
	var pts := PackedVector2Array([rr.position+Vector2(10,0),Vector2(rr.end.x,rr.position.y),Vector2(rr.end.x-10,rr.end.y),Vector2(rr.position.x,rr.end.y)])
	var sh := PackedVector2Array()
	for p: Vector2 in pts: sh.append(p+Vector2(2,4))
	g.draw_colored_polygon(sh,Color(0,0,0,0.22*k))
	g.draw_colored_polygon(pts,Color(Color("e8d6af").lerp(Color("fbf0d6"),hv),k))
	var o := pts.duplicate()
	o.append(pts[0])
	g.draw_polyline(o,Color(Color("92734b"),k),1.6,true)
	if hv > 0.01:
		var uw := (rr.size.x-40)*hv
		g.draw_line(Vector2(rr.get_center().x-uw*0.5,rr.end.y-8),Vector2(rr.get_center().x+uw*0.5,rr.end.y-8),Color(g.RED,0.8),2.0,true)
	g.draw_string(g.font,rr.position+Vector2(0,31),item[2],HORIZONTAL_ALIGNMENT_CENTER,rr.size.x,20,Color(g.INK,k))
	if focused(id): g.draw_polyline(o,Color(GOLD_LIT,0.95),3.0,true)
