extends RefCounted
# 戰鬥 HUD（2026-11-21 重做）：頂端兩面隊伍旗幟夾著中央日晷錶盤，底部胡桃木指揮台上是扇形手牌、
# 錢袋與領主肖像。全部只讀對局狀態、只畫圖；點擊範圍仍是 game.gd 的 card_rect／SKILL_RECT 等常數，
# 教學高亮（tutorial_coach.gd）也從這裡取位置。動態效果只看真實時間，不碰對局亂數。
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const ART = preload("res://manuscript_art.gd")
const DayCycle = preload("res://day_cycle.gd")
const Ceremony = preload("res://battle_ceremony.gd")
const Ornament = preload("res://interface_ornament.gd")
const Style = preload("res://command_style.gd")
const Keywords = preload("res://card_keywords.gd")
const Economy = preload("res://economy_hud.gd")
const Conveyor = preload("res://conveyor.gd")

const CREAM := Color("fff0ca")
const GOLD := Color("d2ad58")
const GOLD_LIT := Color("ffe39a")
const WALNUT := Color("3a2a1c")
const VELLUM := Color("ecdcb6")
# Top bar
const DIAL := Vector2(800,50)
const DIAL_R := 34.0
const RING_R := 41.0
const INFO_SEAL := Rect2(692,24,56,56)
const PAUSE_SEAL := Rect2(852,24,56,56)
const TOWER := Vector2(50,22)
const TOWER_STEP := 56.0
const TOWER_X := 100.0
const TOWER_Y := 54.0
const PILL_X := 504.0
const PILL_W := 150.0
# Bottom bar
const TRAY := Rect2(24,700,1552,188)
const PURSE_PLATE := Rect2(40,712,362,166)
const HAND_MAT := Rect2(410,712,794,170)
const LORD_PLATE := Rect2(1210,712,356,166)
const PORTRAIT := Vector2(1268,790)
const PORTRAIT_R := 46.0
const ROWS_X := 1334.0
const HAND_ANGLES := [-0.055,-0.018,0.018,0.055]
const HAND_DROP := [4.0,0.0,0.0,4.0]
const FARM_ANGLE := -0.03

static var trail := {} # smoothed hp shown behind the real bar: "lord:t" / "gate:t:l" -> value
static var gold_seen := {} # team -> last whole gold
static var gold_pop := {} # team -> seconds left of the number's pop
static var model_id := 0

static func animated(g) -> bool:
	return g.is_processing() and DisplayServer.get_name() != "headless"

static func lively(g) -> bool:
	return animated(g) and g.fx_enabled

static func dt(g) -> float:
	return float(g.polish.last_dt) if g.polish != null else 0.016

static func ease_back(t: float) -> float:
	var c := clampf(t,0.0,1.0)-1.0
	return 1.0+2.70158*c*c*c+1.70158*c*c

static func trailing(g, key: String, value: float) -> float:
	if not animated(g):
		trail[key] = value
		return value
	var shown: float = trail.get(key,value)
	if value >= shown: shown = value
	else: shown = move_toward(shown,value,maxf(1.0,(shown-value)*2.2)*dt(g))
	trail[key] = shown
	return shown

static func reset_if_new(g) -> void:
	var id: int = g.model.get_instance_id()
	if id == model_id: return
	model_id = id
	trail.clear()
	gold_seen.clear()
	gold_pop.clear()

# Positions other modules point at (tutorial rings, flying coins).
static func side_of(g, team: int) -> int:
	return 0 if team == g.me else 1

static func walls_rect(g, side: int) -> Rect2:
	var n: int = maxi(1,g.model.active_lanes.size())
	var w := n*TOWER_STEP-(TOWER_STEP-TOWER.x)
	var x := TOWER_X if side == 0 else L.VIEWPORT_SIZE.x-TOWER_X-w
	return Rect2(x,TOWER_Y,w,TOWER.y)

static func gold_anchor(side: int) -> Vector2:
	return Vector2(400,36) if side == 0 else Vector2(L.VIEWPORT_SIZE.x-400,36)

static func dial_rect() -> Rect2:
	return Rect2(DIAL-Vector2.ONE*(RING_R+6),Vector2.ONE*(RING_R+6)*2)

static func dial_point(g, t: float) -> Vector2:
	var end: float = DayCycle.day_end(g)
	return DIAL+Vector2.from_angle(-PI*0.5+TAU*clampf(t/maxf(1.0,end),0.0,1.0))*RING_R

# ---------------------------------------------------------------- entry
static func draw(g, single_lane: bool = false, hide_bottom: bool = false) -> void:
	reset_if_new(g)
	for team: int in range(2): step_gold(g,team)
	landscape(g)
	if not single_lane:
		for team: int in range(2): team_info(g,team)
		stage_pills(g)
	dial(g,single_lane)
	pause_seal(g)
	if hide_bottom: return
	tray(g)
	if g.model.is_conveyor(g.me):
		Conveyor.draw_hud(g)
	else:
		purse(g)
		hand(g,single_lane)
	keyword_strip(g,single_lane)
	if g.dragging and g.selected >= 0 and g.card_at(g.get_global_mouse_position()) < 0 and g.model.cell_at(g.get_global_mouse_position()).x < 0:
		var mouse: Vector2 = g.get_global_mouse_position()
		var drag_kind: String = g.model.kind_at(g.me,g.selected)
		if not drag_kind.is_empty(): g.draw_card_art(drag_kind,Rect2(mouse-Vector2(40,36),Vector2(80,72)),g.me,Color(1,1,1,0.7))
	lord_panel(g,single_lane)
	if not single_lane and not g.spectating: g.draw_cursor_hint(g.get_global_mouse_position())

# ---------------------------------------------------------------- top bar
static func mx(side: int, x: float) -> float:
	return x if side == 0 else L.VIEWPORT_SIZE.x-x

# The top bar is open sky that follows the hour of the battle's day (使用者 2026-11-21：太陽和天空
# 對應時間): pink dawn at 06:00, blue morning, bright midday, orange sunset, a starry night with the
# moon, and dawn again. The sun rises at the left, climbs, passes behind the dial at midday and sets
# at the right; the moon does the same at night. Birds fly by day. Drawing only.
const STRIP := Rect2(24,14,1552,78)
# The match clock as an hour of the day: 0:00 played is 06:00, 正午 starts at 11:00, 黃昏 at 16:00,
# night at 19:00 and dawn (the verdict) at 06:00 the next morning. Without a night the sun sets at
# the time limit.
const DAWN_H := 6.0
const NOON_H := 11.0
const DUSK_H := 16.0
const SET_H := 19.0
const NEXT_DAWN_H := 30.0
# hour, sky top, sky at the horizon
const SKY_KEYS := [
	[6.0,Color("7d8fb8"),Color("f2c6a8")],
	[7.5,Color("7fb0c8"),Color("cfe3ea")],
	[11.0,Color("6fa8cf"),Color("d8ecf0")],
	[15.0,Color("86aecb"),Color("ead9b4")],
	[17.6,Color("9c7b8e"),Color("f2a96c")],
	[19.0,Color("3a3f6e"),Color("8a6a86")],
	[20.5,Color("1c2448"),Color("343a66")],
	[28.5,Color("1c2448"),Color("343a66")],
	[30.0,Color("7d8fb8"),Color("f2c6a8")],
]
const ARC_LEFT := 64.0
const ARC_RIGHT := 1536.0
const ARC_GAP := Vector2(676,924) # the dial and its seals: the sun slips behind them quickly

static func day_hour(g) -> float:
	var m = g.model
	var keys: Array = [[0.0,DAWN_H],[B.RAMP_1,NOON_H],[B.RAMP_2,DUSK_H]]
	if m.night_decay:
		keys.append([m.night_start_time(),SET_H])
		keys.append([m.dawn_time(),NEXT_DAWN_H])
	else:
		keys.append([DayCycle.day_end(g),SET_H])
	var t: float = m.day_clock() # stands still during 時空凝滯
	var last: Array = keys[0]
	for k: Array in keys.slice(1):
		if k[0] <= last[0]: continue
		if t <= k[0]: return lerpf(last[1],k[1],(t-last[0])/(k[0]-last[0]))
		last = k
	return last[1]

static func clock_text(hour: float) -> String:
	var minutes := int(floor(fposmod(hour,24.0)*60.0))
	return "%02d:%02d" % [minutes/60,minutes%60]

static func sky_at(hour: float) -> Array:
	for i: int in range(SKY_KEYS.size()-1):
		var a: Array = SKY_KEYS[i]
		var b: Array = SKY_KEYS[i+1]
		if hour <= b[0]:
			var k := smoothstep(0.0,1.0,clampf((hour-a[0])/(b[0]-a[0]),0.0,1.0))
			return [Color(a[1]).lerp(b[1],k),Color(a[2]).lerp(b[2],k)]
	var z: Array = SKY_KEYS[SKY_KEYS.size()-1]
	return [z[1],z[2]]

static func night_amount(hour: float) -> float:
	if hour < SET_H: return 0.0
	return smoothstep(SET_H,20.5,hour)*(1.0-smoothstep(28.5,NEXT_DAWN_H,hour))

# Where a body on its arc stands: share 0 at rising, 1 at setting.
static func arc_point(share: float) -> Vector2:
	var s := clampf(share,0.0,1.0)
	var x: float
	if s < 0.46: x = lerpf(ARC_LEFT,ARC_GAP.x,s/0.46)
	elif s < 0.54: x = lerpf(ARC_GAP.x,ARC_GAP.y,(s-0.46)/0.08)
	else: x = lerpf(ARC_GAP.y,ARC_RIGHT,(s-0.54)/0.46)
	return Vector2(x,STRIP.end.y-14.0-sin(s*PI)*42.0)

static func landscape(g) -> void:
	var r := STRIP
	var t: float = g.clock if lively(g) else 0.0
	var hour := day_hour(g)
	var sky := sky_at(hour)
	var night := night_amount(hour)
	var blood: float = preload("res://fx_polish.gd").blood_moon_k(g.model) # 血月蔽日 reddens the whole sky
	if blood > 0.0: sky = [Color(sky[0]).lerp(Color("2a0508"),blood),Color(sky[1]).lerp(Color("8a1a1c"),blood)]
	var bands := 14
	for i: int in range(bands):
		var y0 := lerpf(r.position.y,r.end.y,i/float(bands))
		var y1 := lerpf(r.position.y,r.end.y,(i+1)/float(bands))
		g.draw_rect(Rect2(r.position.x,y0,r.size.x,y1-y0+0.5),Color(sky[0]).lerp(sky[1],i/float(bands-1)))
	if night > 0.01:
		for i: int in range(46):
			var p := Vector2(r.position.x+g.scenery_noise(i,701)*r.size.x,r.position.y+4+g.scenery_noise(i,702)*(r.size.y-22))
			g.draw_circle(p,0.8+g.scenery_noise(i,703)*0.9,Color(1,0.97,0.85,night*(0.45+0.4*sin(t*2.0+i))))
	if hour < SET_H+0.3:
		sun(g,arc_point((hour-DAWN_H)/(SET_H-DAWN_H)),t)
	if hour > SET_H-0.3:
		var mp := arc_point((hour-SET_H)/(NEXT_DAWN_H-SET_H))
		moon(g,mp,t,night,Color(sky[0]).lerp(sky[1],(mp.y-r.position.y)/r.size.y))
	if blood > 0.0:
		# 蔽日: the sun (or night moon) goes dark under the red sky...
		var body := arc_point((hour-DAWN_H)/(SET_H-DAWN_H)) if hour < SET_H else arc_point((hour-SET_H)/(NEXT_DAWN_H-SET_H))
		g.draw_circle(body,19.0,Color(0.30,0.02,0.04,0.85*blood))
		# ...and the blood moon rises into the open sky between our purse and the 戰報 seal, always in view.
		preload("res://fx_polish.gd").eclipse(g,Vector2(1002.0 if has_stage_pills(g.model) else 592.0,STRIP.position.y+39.0+(1.0-blood)*14.0),blood,t)
	# Flocks cross by day only.
	var day := (1.0-night)*(1.0-blood)
	for f: int in range(3):
		var lap := 26.0+f*11.0
		var k := fposmod(t/lap+g.scenery_noise(f,741),1.0)
		var dir := 1.0 if f % 2 == 0 else -1.0
		var lead := Vector2(lerpf(r.position.x-40,r.end.x+40,k if dir > 0 else 1.0-k),r.position.y+18+g.scenery_noise(f,742)*30+sin(t*0.7+f)*5)
		var fade := clampf(minf(k,1.0-k)*14.0,0.0,1.0)*day
		if fade <= 0.01: continue
		var count := 3+f
		for b: int in range(count):
			var row := (b+1)/2
			var side := -1.0 if b % 2 == 1 else 1.0
			var at := lead+Vector2(-dir*row*14.0,side*row*7.0 if b > 0 else 0.0)
			if not r.grow(-4).has_point(at): continue
			var flap := sin(t*8.0+f*1.7+b*0.9)*3.5
			var span := 6.5-f*0.8
			g.draw_polyline(PackedVector2Array([at+Vector2(-span,-flap),at+Vector2(-span*0.4,-flap*0.3-1.0),at,at+Vector2(span*0.4,-flap*0.3-1.0),at+Vector2(span,-flap)]),Color(g.INK,0.6*fade),1.5,true)
	g.draw_texture_rect(g.PAPER,r,false,Color(1,1,1,0.12))
	g.ink_frame(r)

static func sun(g, at: Vector2, t: float) -> void:
	# Low on the horizon it grows redder and its glow wider.
	var low := clampf((at.y-(STRIP.end.y-56.0))/42.0,0.0,1.0)
	var disc := Color("f2c230").lerp(Color("ea7a3a"),low)
	var breathe := 0.5+0.5*sin(t*1.3)
	for k: int in range(4):
		g.draw_circle(at,22.0+k*7.0+breathe*3.0+low*6.0,Color(Color(1.0,0.93,0.62).lerp(Color(1.0,0.62,0.35),low),0.10-k*0.02))
	for i: int in range(12):
		var d := Vector2.from_angle(t*0.25+i*TAU/12.0)
		var long := 8.0 if i % 2 == 0 else 5.0
		g.draw_line(at+d*20.0,at+d*(20.0+long+breathe*2.0),disc.darkened(0.2),2.2,true)
	g.draw_circle(at,16.0,disc)
	g.draw_circle(at+Vector2(-4,-4),7.0,Color(1,0.96,0.75,0.55))
	g.draw_arc(at,16.0,0,TAU,32,Color(g.INK,0.85),1.6,true)

static func moon(g, at: Vector2, t: float, night: float, behind: Color) -> void:
	var a := clampf(night*1.3,0.0,1.0)
	g.draw_circle(at,20.0+sin(t*1.5)*1.5,Color(0.95,0.93,0.75,0.16*a))
	g.draw_circle(at,13.0,Color(Color("f3ecc9"),a))
	g.draw_circle(at+Vector2(5.5,-2.5),11.0,Color(behind,a))
	g.draw_arc(at,13.0,0,TAU,28,Color(g.INK,0.7*a),1.4,true)

static func outlined(g, pos: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, color: Color) -> void:
	g.draw_string_outline(g.font,pos,text,align,width,size,5,Color("fbf3dc",0.9))
	g.draw_string(g.font,pos,text,align,width,size,color)

static func team_info(g, team: int) -> void:
	var m = g.model
	var side := side_of(g,team)
	var col: Color = g.RED if team == 0 else g.BLUE
	var t: float = g.clock if lively(g) else 0.0
	var hit := 0.0
	for lane: int in m.active_lanes: hit = maxf(hit,g.polish.gate_flash(team,lane))
	var shake := sin(t*70.0)*2.5*hit
	# Crest in a gilt roundel that bobs on its own beat.
	var bob := sin(t*1.8+side)*1.5
	var crest_c := Vector2(mx(side,62)+shake,52+bob)
	g.draw_circle(crest_c+Vector2(0,3),29,Color(0,0,0,0.22))
	g.draw_circle(crest_c,29,Color("f3e3bd"))
	g.draw_arc(crest_c,29,0,TAU,40,GOLD.darkened(0.15),3.0,true)
	g.draw_arc(crest_c,24,0,TAU,40,Color(col,0.5),1.2,true)
	g.draw_texture_rect(g.art("crest",team),Rect2(crest_c-Vector2(21,22),Vector2(42,44)),false)
	# Name and wall count, inked in the team colour with a paper halo so they read on any sky.
	var standing: int = m.active_lanes.filter(func(lane: int) -> bool: return m.gates[team][lane] > 0).size()
	var s_name: String = Ceremony.short_name(g,team)
	var name_sz := 17 if s_name.length() >= 5 else (20 if s_name.length() >= 3 else 23)
	var caption := "%s  城牆 %d / %d" % [s_name,standing,m.active_lanes.size()]
	var wr := walls_rect(g,side)
	var align := HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	outlined(g,Vector2((wr.position.x if side == 0 else wr.end.x-300)+shake,44),caption,align,300 if side == 1 else -1,name_sz,col.darkened(0.1))
	for i: int in range(m.active_lanes.size()):
		var lane: int = m.active_lanes[i]
		tower(g,Rect2(wr.position+Vector2(i*TOWER_STEP+shake,0),TOWER),team,lane,col)
	# Gold in the purse: a coin and the count, which pops when it rises.
	var ga := gold_anchor(side)+Vector2(shake,0)
	var pop: float = gold_pop.get(team,0.0)
	var coin_c := ga+Vector2(0,14)
	g.draw_texture_rect(Economy.coin_texture(),Rect2(coin_c-Vector2(13,13)-Vector2(0,pop*6),Vector2(26,26)),false)
	var gtxt := "%d / %d" % [int(m.ink[team]),B.MAX_INK]
	var gsz := 19+int(round(pop*5))
	var gx: float = ga.x+18 if side == 0 else ga.x-18-g.font.get_string_size(gtxt,HORIZONTAL_ALIGNMENT_LEFT,-1,gsz).x
	outlined(g,Vector2(gx,ga.y+21),gtxt,HORIZONTAL_ALIGNMENT_LEFT,-1,gsz,g.INK.lerp(Color("9a6a12"),pop))
	# At night the dawn verdict counts land: show it beside the purse, the leader glowing.
	if m.day_phase() == 3:
		var mine: int = m.land(team)
		var lead: bool = mine > m.land(1-team)
		var lx: float = ga.x+18 if side == 0 else ga.x-18-90
		var glow := 0.5+0.5*sin(t*4.0) if lead else 0.0
		outlined(g,Vector2(lx,ga.y+42),"領地 %d" % mine,HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT,90 if side == 1 else -1,15,g.INK.lerp(Color("b8862b"),glow))

static func tower(g, r: Rect2, team: int, lane: int, col: Color) -> void:
	var m = g.model
	var hp: float = m.gates[team][lane]
	var shown := trailing(g,"gate:%d:%d" % [team,lane],hp)
	var flash: float = g.polish.gate_flash(team,lane)
	var jolt := Vector2(sin(g.clock*90.0)*2.0*flash,-flash*2.0)
	r.position += jolt
	var merlon := 6.0
	var body := Rect2(r.position+Vector2(0,merlon),r.size-Vector2(0,merlon))
	if hp <= 0:
		# Rubble: a dark stump with a crack.
		var stump := PackedVector2Array([body.position+Vector2(0,body.size.y),body.position+Vector2(0,body.size.y*0.45),body.position+Vector2(body.size.x*0.3,body.size.y*0.25),body.position+Vector2(body.size.x*0.55,body.size.y*0.55),body.position+Vector2(body.size.x*0.8,body.size.y*0.3),body.position+Vector2(body.size.x,body.size.y*0.5),body.end])
		g.draw_colored_polygon(stump,Color(0.12,0.08,0.05,0.55))
		g.draw_polyline(stump,Color("1e130b",0.8),1.2,true)
		return
	g.draw_rect(Rect2(body.position+Vector2(0,2),body.size),Color(0,0,0,0.25))
	g.draw_rect(body,Color(0.16,0.10,0.06,0.55))
	for k: int in range(3):
		var mr := Rect2(r.position+Vector2(k*(r.size.x-10)/2.0,0),Vector2(10,merlon+1))
		g.draw_rect(mr,Color("f3e3bd") if hp >= B.GATE_HP*0.999 else Color(0.16,0.10,0.06,0.55))
	var share := clampf(hp/B.GATE_HP,0.0,1.0)
	var trail_share := clampf(shown/B.GATE_HP,0.0,1.0)
	var inner := body.grow(-2)
	if trail_share > share: g.draw_rect(Rect2(inner.position+Vector2(0,inner.size.y*(1.0-trail_share)),Vector2(inner.size.x,inner.size.y*trail_share)),Color(1,0.93,0.72,0.75))
	g.draw_rect(Rect2(inner.position+Vector2(0,inner.size.y*(1.0-share)),Vector2(inner.size.x,inner.size.y*share)),Color("f3e3bd"))
	# Masonry lines and the gate arch keep it reading as a wall, not a bar.
	g.draw_line(inner.position+Vector2(0,inner.size.y*0.5),inner.position+Vector2(inner.size.x,inner.size.y*0.5),Color(col,0.35),1.0)
	var arch_c := Vector2(inner.get_center().x,inner.end.y)
	g.draw_arc(arch_c,5.0,PI,TAU,10,Color(col.darkened(0.3),0.8),2.0,true)
	g.draw_rect(body,Color("2a1b10",0.9),false,1.2)
	if flash > 0.0: g.draw_rect(body.grow(1),Color(1,1,1,0.75*flash))
	# A little pennant on a standing tower, flapping in the wind.
	var pole := Vector2(r.end.x-5,r.position.y)
	g.draw_line(pole,pole+Vector2(0,-11),Color("3a2a1c"),1.2,true)
	var tt: float = g.clock if lively(g) else 0.0
	var tip := pole+Vector2(9.0 if team == g.me else -9.0,-8.0+sin(tt*6.0+lane*1.7)*1.5)
	g.draw_colored_polygon(PackedVector2Array([pole+Vector2(0,-11),tip,pole+Vector2(0,-5)]),col)

static func has_stage_pills(m) -> bool:
	return m.day_phase() < 3 and (not m.field_mutators.is_empty() or not m.stage_rule_tag.is_empty() or not preload("res://season.gd").label(m.season,m.season_rule).is_empty())

static func stage_pills(g) -> void:
	var m = g.model
	if m.day_phase() >= 3: return
	var pills: Array = []
	if not m.field_mutators.is_empty():
		for mi: int in range(mini(2,m.field_mutators.size())):
			var fm: Dictionary = m.field_mutators[mi]
			var fk := String(fm.get("kind",""))
			var f_name := "法陣" if fm.has("kinds") and fk.is_empty() else String(B.CARDS.get(fk,{}).get("name",fk))
			pills.append(["%s %ds" % [f_name.left(4),ceili(maxf(0.0,float(fm.get("timer",0.0))))],g.RED if int(fm.get("team",1)) == 0 else g.BLUE])
	elif not m.stage_rule_tag.is_empty():
		pills.append(["本關：%s" % m.stage_rule_tag,Color("6e451d")])
	var season_tag: String = preload("res://season.gd").label(m.season,m.season_rule)
	if not season_tag.is_empty() and pills.size() < 2: pills.append([season_tag,Color("3c6e2e")])
	for i: int in range(pills.size()):
		var r := Rect2(PILL_X,24+i*28,PILL_W,22)
		var poly := PackedVector2Array([r.position+Vector2(8,0),Vector2(r.end.x,r.position.y),Vector2(r.end.x-8,r.end.y),Vector2(r.position.x,r.end.y)])
		g.draw_colored_polygon(poly,Color(0.98,0.93,0.80,0.92))
		var edge := poly.duplicate()
		edge.append(poly[0])
		g.draw_polyline(edge,Color(pills[i][1],0.9),1.4,true)
		g.draw_string(g.font,r.position+Vector2(4,16),pills[i][0],HORIZONTAL_ALIGNMENT_CENTER,r.size.x-8,13,pills[i][1])

static func dial(g, single_lane: bool) -> void:
	var m = g.model
	var t: float = g.clock if lively(g) else 0.0
	g.draw_circle(DIAL+Vector2(0,4),RING_R+7,Color(0,0,0,0.28))
	g.draw_circle(DIAL,RING_R+7,Color("2a1b10"))
	g.draw_arc(DIAL,RING_R+7,0,TAU,64,GOLD.darkened(0.2),2.0,true)
	if not single_lane:
		# The day as a ring: one band per phase, the spent part dimmed, the sun or moon riding on it.
		var marks: Array = DayCycle.marks(g)
		var end: float = marks[marks.size()-1]
		for i: int in range(marks.size()-1):
			var a0: float = -PI*0.5+TAU*marks[i]/end
			var a1: float = -PI*0.5+TAU*marks[i+1]/end
			var night: bool = m.night_decay and i == marks.size()-2
			var band: Color = DayCycle.BANDS[3] if night else DayCycle.BANDS[mini(i,DayCycle.BANDS.size()-2)]
			g.draw_arc(DIAL,RING_R,a0,a1,24,band,7.0,true)
			g.draw_line(DIAL+Vector2.from_angle(a0)*(RING_R-5),DIAL+Vector2.from_angle(a0)*(RING_R+5),Color("2a1b10"),2.0,true)
		var now_a := -PI*0.5+TAU*clampf(m.day_clock()/end,0.0,1.0)
		if now_a > -PI*0.5+0.01: g.draw_arc(DIAL,RING_R,-PI*0.5,now_a,48,Color(0.10,0.06,0.03,0.45),7.5,true)
		var at := DIAL+Vector2.from_angle(now_a)*RING_R
		if m.day_phase() == 3: DayCycle.moon(g,at,8.0)
		else: DayCycle.sun(g,at,7.0)
	# Face of the dial: the clock (or the survive countdown) and the phase underneath.
	var hot: bool = m.multiplier() > B.START_GOLD
	g.draw_circle(DIAL,DIAL_R,Color("f2e3c0"))
	g.draw_texture_rect(g.PAPER,Rect2(DIAL-Vector2.ONE*DIAL_R,Vector2.ONE*DIAL_R*2),false,Color(1,1,1,0.10))
	g.draw_arc(DIAL,DIAL_R,0,TAU,48,GOLD,2.5,true)
	g.draw_arc(DIAL,DIAL_R-4,0,TAU,48,Color(g.INK,0.35),1.0,true)
	var survive: bool = m.survive_time > 0.0
	if survive:
		var left_t := ceili(maxf(0.0,m.survive_time-m.day_clock()))
		g.draw_string(g.font,DIAL+Vector2(-DIAL_R,-6),"守",HORIZONTAL_ALIGNMENT_CENTER,DIAL_R*2,14,g.RED)
		g.draw_string(g.font,DIAL+Vector2(-DIAL_R,16),"%d:%02d" % [left_t/60,left_t%60],HORIZONTAL_ALIGNMENT_CENTER,DIAL_R*2,21,g.RED)
	else:
		# The hour of the battle's day, not minutes played: the sky above shows the same hour.
		g.draw_string(g.font,DIAL+Vector2(-DIAL_R,7),clock_text(day_hour(g)),HORIZONTAL_ALIGNMENT_CENTER,DIAL_R*2,21,g.RED if hot else g.INK)
		if not single_lane:
			var phase: int = m.day_phase()
			var label: String = ["早晨","正午","黃昏","入夜"][clampi(phase,0,3)]
			if phase == 3: # the night has its own hours: past midnight, then the last hour before dawn
				var h := day_hour(g)
				label = "天將亮" if h >= 28.5 else ("深夜" if h >= 24.0 else "入夜")
			g.draw_string(g.font,DIAL+Vector2(-DIAL_R,24),label,HORIZONTAL_ALIGNMENT_CENTER,DIAL_R*2,11,Color("6f5a3e"))
	# 戰局資料 seal on the left of the dial.
	info_seal(g,single_lane)

static func seal(g, r: Rect2, fill: Color, key: String) -> float:
	var mouse: Vector2 = g.get_global_mouse_position()
	var hv: float = g.polish.hover_val(key,r.has_point(mouse),animated(g))
	var c := r.get_center()+Vector2(0,-2.0*hv)
	var rad := r.size.x*0.5*(1.0+0.06*hv)
	g.draw_circle(c+Vector2(0,3),rad,Color(0,0,0,0.30))
	# A wax seal: a lumpy rim around a pressed disc.
	var rim := PackedVector2Array()
	for i: int in range(28):
		var a := TAU*i/28.0
		rim.append(c+Vector2.from_angle(a)*(rad+1.5*sin(a*5.0+1.3)))
	g.draw_colored_polygon(rim,fill.lightened(0.12*hv))
	g.draw_arc(c,rad*0.74,0,TAU,32,Color(0,0,0,0.25),2.0,true)
	g.draw_arc(c,rad*0.74-1.5,-2.4,-0.6,12,Color(1,1,1,0.25),1.5,true)
	if hv > 0.01: g.draw_arc(c,rad+4,0,TAU,40,Color(GOLD_LIT,0.7*hv),2.0,true)
	return hv

static func info_seal(g, single_lane: bool) -> void:
	if single_lane: return
	var r: Rect2 = g.library.INFO_RECT
	var hv := seal(g,r,Color("2f5560"),"hud_info")
	var c := r.get_center()+Vector2(0,-2.0*hv)
	g.draw_string(g.font,c+Vector2(-r.size.x*0.5,1),"戰報",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,15,CREAM)
	g.draw_string(g.font,c+Vector2(-r.size.x*0.5,15),["簡單","普通","困難"][clampi(g.model.difficulty,0,2)],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,10,Color(CREAM,0.75))

static func pause_seal(g) -> void:
	var r := L.PAUSE_RECT
	var hv := seal(g,r,Color("8e3427"),"hud_pause")
	var c := r.get_center()+Vector2(0,-2.0*hv)
	if g.net != null:
		for dy: float in [-7.0, 0.0, 7.0]:
			g.draw_rect(Rect2(c+Vector2(-9.0, dy-1.5), Vector2(18.0, 3.0)), CREAM)
	elif g.model.paused:
		g.draw_colored_polygon(PackedVector2Array([c+Vector2(-6,-10),c+Vector2(10,0),c+Vector2(-6,10)]),CREAM)
	else:
		g.draw_rect(Rect2(c+Vector2(-8,-10),Vector2(5,20)),CREAM)
		g.draw_rect(Rect2(c+Vector2(3,-10),Vector2(5,20)),CREAM)

# ---------------------------------------------------------------- bottom bar
static func tray(g) -> void:
	var r := TRAY
	var pts := PackedVector2Array([r.position+Vector2(0,14),r.position+Vector2(14,0),Vector2(r.end.x-14,r.position.y),Vector2(r.end.x,r.position.y+14),r.end,Vector2(r.position.x,r.end.y)])
	g.draw_colored_polygon(pts,WALNUT)
	g.draw_rect(Rect2(r.position+Vector2(4,16),Vector2(r.size.x-8,40)),Color(1,0.85,0.6,0.05))
	# Wood grain.
	for i: int in range(9):
		var y := r.position.y+22+i*19.0
		var line := PackedVector2Array()
		for k: int in range(33):
			var x := r.position.x+8+k*(r.size.x-16)/32.0
			line.append(Vector2(x,y+sin(k*0.7+i*1.9)*2.0+sin(k*0.23+i)*3.0))
		g.draw_polyline(line,Color(0,0,0,0.13 if i%2 == 0 else 0.07),1.2,true)
	g.draw_texture_rect(g.PAPER,r,false,Color(1,0.9,0.75,0.05))
	# Gilt edge with a glint travelling along it.
	g.draw_line(pts[1],pts[2],GOLD,2.0,true)
	g.draw_line(pts[0],pts[1],GOLD,2.0,true)
	g.draw_line(pts[2],pts[3],GOLD,2.0,true)
	var outline := pts.duplicate()
	outline.append(pts[0])
	g.draw_polyline(outline,Color("1c120a"),2.0,true)

static func slanted(r: Rect2, lean_left: float, lean_right: float) -> PackedVector2Array:
	return PackedVector2Array([r.position+Vector2(lean_left,0),Vector2(r.end.x,r.position.y),Vector2(r.end.x-lean_right,r.end.y),Vector2(r.position.x,r.end.y)])

static func plate(g, pts: PackedVector2Array, fill: Color, edge: Color) -> void:
	var shadow := PackedVector2Array()
	for p: Vector2 in pts: shadow.append(p+Vector2(2,4))
	g.draw_colored_polygon(shadow,Color(0,0,0,0.35))
	g.draw_colored_polygon(pts,fill)
	var o := pts.duplicate()
	o.append(pts[0])
	g.draw_polyline(o,edge,1.6,true)

static func step_gold(g, team: int) -> void:
	var whole := int(g.model.ink[team])
	var last: int = gold_seen.get(team,whole)
	if whole > last and animated(g): gold_pop[team] = 1.0
	gold_seen[team] = whole
	gold_pop[team] = maxf(0.0,float(gold_pop.get(team,0.0))-dt(g)*4.0)

static func purse(g) -> void:
	var pts := slanted(PURSE_PLATE,0,12)
	plate(g,pts,VELLUM,Color("8a6f4a"))
	g.draw_texture_rect(g.PAPER,PURSE_PLATE,false,Color(1,1,1,0.10))
	Economy.draw(g,gold_pop.get(g.me,0.0))

static func card_xform(rect: Rect2, angle: float, scale: float) -> Transform2D:
	var c := rect.get_center()
	return Transform2D(angle,Vector2(scale,scale),0.0,c)*Transform2D(0.0,-c)

static func with_xform(g, xf: Transform2D) -> void:
	g.ui_xform = xf
	g.draw_set_transform_matrix(xf)

static func clear_xform(g) -> void:
	g.ui_xform = Transform2D.IDENTITY
	g.draw_set_transform_matrix(Transform2D.IDENTITY)

static func slot_blocked(g, slot: int) -> bool:
	var kind: String = g.model.kind_at(g.me,slot)
	if kind.is_empty() or not B.CARDS.has(kind): return true
	if g.model.is_conveyor(g.me): return false
	return g.model.ink[g.me] < B.CARDS[kind].cost or g.model.slot_cd(g.me,slot) > 0

static func hand(g, single_lane: bool) -> void:
	var m = g.model
	var t: float = g.clock if lively(g) else 0.0
	# Felt card mat.
	var mat := slanted(HAND_MAT,10,10)
	plate(g,mat,Color("4b2620"),Color("1c120a"))
	for i: int in range(26):
		var x := HAND_MAT.position.x+20+i*30.0
		g.draw_line(Vector2(x,HAND_MAT.position.y+4),Vector2(x-12,HAND_MAT.end.y-4),Color(1,0.8,0.6,0.035),1.0)
	var inner := slanted(HAND_MAT.grow(-6),8,8)
	inner.append(inner[0])
	g.draw_polyline(inner,Color(GOLD,0.45),1.2,true)
	# Permanent home slot sits in a gilt niche with its 常駐 ribbon.
	var farm_rect: Rect2 = g.card_rect(g.Battle.FARM_SLOT)
	var home_kind: String = m.kind_at(g.me,g.Battle.FARM_SLOT)
	var home_col: Color = Style.tag_color(home_kind)
	var home_blocked := slot_blocked(g,g.Battle.FARM_SLOT)
	var niche := farm_rect.grow(6)
	g.draw_rect(niche,Color(0,0,0,0.25))
	g.draw_rect(niche,Color(home_col,0.30) if not home_blocked else Color(0.4,0.4,0.4,0.25))
	g.draw_rect(niche,Color(GOLD,0.7),false,1.5)
	hand_card(g,g.Battle.FARM_SLOT,farm_rect,FARM_ANGLE,0.0,t)
	var fr: Rect2 = farm_rect
	var tag := Rect2(fr.position.x+fr.size.x*0.5-22,fr.end.y-10,44,16)
	Ornament.ribbon_tag(g,tag,"常駐",Color("5e5e5e") if home_blocked else home_col.darkened(0.10),12)
	# Divider between the home slot and the rotating hand.
	var dx := 551.0
	g.draw_line(Vector2(dx,724),Vector2(dx,876),Color(GOLD,0.45),1.2,true)
	g.draw_colored_polygon(PackedVector2Array([Vector2(dx,794),Vector2(dx+4,800),Vector2(dx,806),Vector2(dx-4,800)]),GOLD)
	# The four rotating cards, fanned like a held hand; the hovered one straightens and rises.
	var order := [0,3,1,2] # outer cards first so the inner ones overlap them
	var focus: int = g.selected if g.selected >= 0 else g.hover_slot
	if focus >= 0 and focus < 4:
		order.erase(focus)
		order.append(focus)
	for i: int in order:
		hand_card(g,i,g.card_rect(i),HAND_ANGLES[i],HAND_DROP[i],t)
	# Next card: smaller, swaying, waiting its turn.
	var nr: Rect2 = g.NEXT_RECT
	var ribbon := Rect2(nr.position.x+6,nr.position.y-22,nr.size.x-12,18)
	g.draw_colored_polygon(slanted(ribbon,5,5),Color("2a1b10",0.85))
	g.draw_string(g.font,ribbon.position+Vector2(0,14),"下一張",HORIZONTAL_ALIGNMENT_CENTER,ribbon.size.x,13,CREAM)
	var sway := sin(t*1.3)*0.03
	with_xform(g,card_xform(nr,sway,1.0))
	g.draw_card(m.decks[g.me][4],nr)
	g.draw_rect(nr.grow(2),Color(0.24,0.16,0.10,0.35))
	g.draw_rect(nr,Color(GOLD,0.5),false,1.2)
	clear_xform(g)
	if g.spectating: return

static func hand_card(g, slot: int, base: Rect2, angle: float, drop: float, t: float) -> void:
	var m = g.model
	var kind: String = m.kind_at(g.me,slot)
	var lift: float = g.polish.get_slot_lift(g,slot) # 0, -8 hover, -16 selected (smoothed)
	var rise := clampf(-lift/8.0,0.0,2.0)
	var r := base
	r.position.y += drop*(1.0-minf(1.0,rise))+lift*1.8
	if lively(g): r.position.y += sin(t*1.7+slot*1.3)*1.6
	var a := lerpf(angle,0.0,minf(1.0,rise))
	var s := 1.0+0.05*minf(1.0,rise)+0.03*maxf(0.0,rise-1.0)
	# A newly drawn card flies in from the next-card slot, spinning into place.
	var entry_left := float(g.polish.slot_entry.get(slot,0.0))
	if entry_left > 0.0 and animated(g) and slot < 4:
		var p := 1.0-clampf(entry_left/0.26,0.0,1.0)
		var e := ease_back(p)
		var from: Vector2 = g.NEXT_RECT.get_center()
		var to := r.get_center()
		var c := from.lerp(to,e)+Vector2(0,-40.0*sin(p*PI))
		r.position = c-r.size*0.5
		a = lerpf(0.5,a,e)
		s = lerpf(0.78,s,e)
	var blocked := slot_blocked(g,slot)
	var sel: bool = g.selected == slot
	var xf := card_xform(r,a,s)
	with_xform(g,xf)
	# Ready cards glow softly from underneath; the selected one burns brighter.
	if not blocked or sel:
		var pulse := 0.5+0.5*sin(t*3.2+slot)
		var glow_a := (0.30 if sel else 0.10+0.07*pulse)
		for k: int in range(5):
			g.draw_rect(r.grow(2.0+k*2.5),Color(1.0,0.80,0.32,glow_a*(1.0-k/5.0)))
	g.draw_rect(Rect2(r.position+Vector2(3,6),r.size),Color(0,0,0,0.35))
	g.draw_card(kind,r,slot)
	if g.fx_enabled and g.polish.slot_ready_flash.get(slot,0.0) > 0.0:
		g.polish.draw_ready_sheen(g,r,float(g.polish.slot_ready_flash[slot]))
	if sel:
		var k := fposmod(t*0.8,1.0)
		var perim := PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)])
		for j: int in range(4):
			var u := fposmod(k+j*0.25,1.0)*4.0
			var seg := int(u)
			var p0: Vector2 = perim[seg%4].lerp(perim[(seg+1)%4],u-seg)
			g.draw_circle(p0,3.0,GOLD_LIT)
			g.draw_circle(p0,6.0,Color(GOLD_LIT,0.3))
		g.draw_rect(r.grow(2),Color(GOLD_LIT,0.8),false,2.0)
	clear_xform(g)

static func keyword_strip(g, single_lane: bool) -> void:
	if g.spectating or single_lane: return
	var m = g.model
	var focus_slot: int = g.selected if g.selected >= 0 else g.hover_slot
	var strip_kind := ""
	var strip_alpha := 1.0
	if animated(g):
		strip_alpha = g.polish.hover_strip_alpha
		strip_kind = g.polish.hover_strip_kind
	elif focus_slot >= 0:
		strip_kind = m.kind_at(g.me,focus_slot)
	if strip_kind.is_empty() or strip_alpha <= 0.01 or not B.CARDS.has(strip_kind): return
	var fkws: Array[String] = Keywords.for_card(strip_kind)
	var strip := Rect2(414,664+(1.0-strip_alpha)*10.0,674,32)
	var poly := slanted(strip,10,10)
	var shadow := PackedVector2Array()
	for p: Vector2 in poly: shadow.append(p+Vector2(2,3))
	g.draw_colored_polygon(shadow,Color(0,0,0,0.3*strip_alpha))
	g.draw_colored_polygon(poly,Color(0.17,0.11,0.07,0.94*strip_alpha))
	var o := poly.duplicate()
	o.append(poly[0])
	g.draw_polyline(o,Color(GOLD,0.8*strip_alpha),1.4,true)
	var bw: float = Keywords.draw_badges(g,strip.position+Vector2(16,22.5),fkws,14,240.0,strip_alpha)
	var fdata: Dictionary = B.CARDS[strip_kind]
	var notes: Array[String] = []
	if fdata.type == "spell" and not fdata.get("rolling",false):
		var sh := B.spell_shape(fdata)
		notes.append("%d×%d %s" % [sh.x,sh.y,B.spell_shape_tag(sh)])
	var ups: Dictionary = m.card_upgrades[g.me].get(strip_kind,{}) if g.me < m.card_upgrades.size() else {}
	if not ups.is_empty():
		var Up = preload("res://card_upgrades.gd")
		notes.append("+%d（%s）" % [Up.level(ups),Up.text(ups)])
	notes.append(Keywords.desc_of(fkws[0]) if not fkws.is_empty() else fdata.role)
	g.draw_string(g.font,strip.position+Vector2(22+bw,22.0)," · ".join(notes),HORIZONTAL_ALIGNMENT_LEFT,strip.size.x-32.0-bw,15,Color(CREAM,strip_alpha))

# ---------------------------------------------------------------- lord panel
static func lord_panel(g, single_lane: bool) -> void:
	var pts := slanted(LORD_PLATE,12,0)
	plate(g,pts,VELLUM,Color("8a6f4a"))
	g.draw_texture_rect(g.PAPER,LORD_PLATE,false,Color(1,1,1,0.10))
	if single_lane: return
	var m = g.model
	var own: int = 0 if g.spectating else g.me
	portrait(g,own)
	if g.spectating: speed_row(g)
	else: skill_button(g)
	for team: int in range(2):
		var lord: Dictionary = m.lords[team]
		var y: float = 822.0+team*34.0
		var col: Color = g.RED if team == 0 else g.BLUE
		g.label_at(Vector2(ROWS_X,y),"%s · %s" % ["紅" if team == 0 else "藍",Ceremony.side_name(g,team)],15,col)
		var bar_r := Rect2(ROWS_X,y+6,176,6)
		var shown := trailing(g,"lord:%d" % team,float(lord.hp))
		g.draw_rect(bar_r.grow(1),Color(0.15,0.10,0.06,0.55))
		g.draw_rect(Rect2(bar_r.position,Vector2(bar_r.size.x*clampf(shown/maxf(1.0,lord.max_hp),0,1),bar_r.size.y)),Color(1,0.92,0.75,0.9))
		g.draw_rect(Rect2(bar_r.position,Vector2(bar_r.size.x*clampf(lord.hp/maxf(1.0,lord.max_hp),0,1),bar_r.size.y)),col)
		g.draw_string(g.font,Vector2(ROWS_X,y),"%d / %d" % [maxi(0,int(lord.hp)),int(lord.max_hp)],HORIZONTAL_ALIGNMENT_RIGHT,bar_r.size.x,12,Color("5a4630"))
		g.skill_mark(team,Vector2(1548,y+3))

static func portrait(g, team: int) -> void:
	var m = g.model
	var lord: Dictionary = m.lords[team]
	var col: Color = g.RED if team == 0 else g.BLUE
	var flash: float = g.polish.lord_flash(team)
	var t: float = g.clock if lively(g) else 0.0
	var c := PORTRAIT+Vector2(sin(t*80.0)*3.0*flash,0)
	var down: bool = lord.hp <= 0
	g.draw_circle(c+Vector2(0,4),PORTRAIT_R+9,Color(0,0,0,0.3))
	g.draw_circle(c,PORTRAIT_R+9,Color("2a1b10"))
	# HP ring with a pale trail where it was just hit.
	var share := clampf(lord.hp/maxf(1.0,lord.max_hp),0.0,1.0)
	var shown := clampf(trailing(g,"lord:%d" % team,float(lord.hp))/maxf(1.0,lord.max_hp),0.0,1.0)
	g.draw_arc(c,PORTRAIT_R+4,0,TAU,64,Color(0.2,0.14,0.09),6.0,true)
	if shown > share: g.draw_arc(c,PORTRAIT_R+4,-PI*0.5,-PI*0.5+TAU*shown,64,Color(1,0.92,0.75,0.85),6.0,true)
	if share > 0.0: g.draw_arc(c,PORTRAIT_R+4,-PI*0.5,-PI*0.5+TAU*share,64,col.lightened(0.15),6.0,true)
	g.draw_circle(c,PORTRAIT_R,Color("e9d8b0") if not down else Color("a8a29a"))
	g.draw_arc(c,PORTRAIT_R,0,TAU,48,GOLD,2.0,true)
	var bob := sin(t*1.5)*1.5
	var tex: Texture2D = Ceremony.side_portrait(g,team)
	if tex != null:
		var box := Rect2(c-Vector2(PORTRAIT_R*0.92,PORTRAIT_R*0.98)+Vector2(0,bob),Vector2(PORTRAIT_R*1.84,PORTRAIT_R*1.84))
		g.draw_fitted(tex,box,Color(0.55,0.55,0.55) if down else Color.WHITE,true)
	if flash > 0.0: g.draw_circle(c,PORTRAIT_R,Color(1,0.85,0.8,0.45*flash))

static func speed_row(g) -> void:
	var mouse: Vector2 = g.get_global_mouse_position()
	g.draw_string(g.font,Vector2(ROWS_X,756),"速度",HORIZONTAL_ALIGNMENT_LEFT,-1,15,g.INK)
	for i: int in range(g.SPEEDS.size()):
		var r: Rect2 = g.SPEED_RECTS[i]
		var on: bool = g.speed == g.SPEEDS[i]
		var hv: float = g.polish.hover_val("hud_speed_%d" % i,r.has_point(mouse),animated(g))
		var rr := Rect2(r.position+Vector2(0,-2.0*hv),r.size)
		plate(g,slanted(rr,5,5),Color("8e3427") if on else Color("f3e6c6").lerp(Color("fff7e0"),hv),Color("2a1b10"))
		g.draw_string(g.font,rr.position+Vector2(0,22),"×%d" % g.SPEEDS[i],HORIZONTAL_ALIGNMENT_CENTER,rr.size.x,17,CREAM if on else g.INK)

# Our lord's skill: Q or click. The plate fills with molten gold as it charges, a grey wash drains
# away while it cools, and once ready it glows with sparks running round its edge.
static func skill_button(g) -> void:
	var m = g.model
	var lord_kind: String = m.lords[g.me].lord
	var info: Dictionary = B.lord_data(lord_kind)
	var has_sk: bool = B.has_skill(lord_kind)
	var ready: bool = m.skill_error(g.me).is_empty()
	var t: float = g.clock if lively(g) else 0.0
	var r: Rect2 = g.SKILL_RECT
	if g.skill_shake > 0.0: r.position.x += sin(g.skill_shake*55.0)*5.0*clampf(g.skill_shake/0.45,0.0,1.0)
	var hv: float = g.polish.hover_val("hud_skill",r.has_point(g.get_global_mouse_position()),animated(g))
	r.position.y -= 2.0*hv
	var dead: bool = not has_sk or m.lords[g.me].hp <= 0
	if ready:
		var pulse := 0.5+0.5*sin(t*4.0)
		for k: int in range(4):
			g.draw_colored_polygon(slanted(r.grow(4.0+k*3.0+pulse*2.0),10,10),Color(1.0,0.75,0.25,(0.16-k*0.035)*(0.6+0.4*pulse)))
	var pts := slanted(r,10,10)
	var base := Color("8e3427") if ready else (Color("5c5650") if dead else Color("4b3a2c"))
	plate(g,pts,base.lightened(0.10*hv),Color("1c120a"))
	var inner := r.grow(-4)
	if has_sk and not ready and not dead:
		if m.skill_cd[g.me] > 0.0:
			var cool := clampf(m.skill_cd[g.me]/maxf(0.01,B.skill_cooldown(lord_kind)),0.0,1.0)
			g.draw_rect(Rect2(inner.position,Vector2(inner.size.x*cool,inner.size.y)),Color(0.10,0.10,0.11,0.40))
		else:
			var charge := clampf(m.skill_charge[g.me]/maxf(1.0,m.skill_need(g.me)),0.0,1.0)
			if charge > 0.0:
				# Molten gold rising, its surface rippling.
				var top := inner.end.y-inner.size.y*charge
				var liquid := PackedVector2Array()
				for k: int in range(21):
					var x := lerpf(inner.position.x,inner.end.x,k/20.0)
					var wave := sin(x*0.08+t*4.0)*2.0+sin(x*0.13-t*2.6)*1.2 if charge < 0.999 else 0.0
					liquid.append(Vector2(x,clampf(top+wave,inner.position.y,inner.end.y)))
				liquid.append(inner.end)
				liquid.append(Vector2(inner.position.x,inner.end.y))
				var clipped := Geometry2D.intersect_polygons(liquid,slanted(inner,8,8))
				for poly: PackedVector2Array in clipped: g.draw_colored_polygon(poly,Color(0.93,0.68,0.20,0.55))
	g.draw_line(pts[0]+Vector2(2,3),pts[1]+Vector2(-2,3),Color(GOLD,0.7),1.2,true)
	# Q seal, the skill name and its state.
	var q := Vector2(r.position.x+30,r.get_center().y)
	g.draw_circle(q,16,Color("f3e3bd") if ready else Color("b9ab92"))
	g.draw_arc(q,16,0,TAU,32,GOLD if ready else Color("6b6b6b"),2.0,true)
	g.draw_string(g.font,q+Vector2(-16,6),"Q",HORIZONTAL_ALIGNMENT_CENTER,32,17,g.RED if ready else Color("4f4f4f"))
	var text_col := CREAM if not dead else Color("d0cbc3")
	g.draw_string(g.font,Vector2(r.position.x+54,r.position.y+30),String(info.skill),HORIZONTAL_ALIGNMENT_LEFT,r.size.x-100,19,text_col)
	var state := "可發動！" if ready else ("沒有技能" if not has_sk else ("領主倒下中" if m.lords[g.me].hp <= 0 else ("冷卻 %ds" % ceili(m.skill_cd[g.me]) if m.skill_cd[g.me] > 0.0 else "充能 %d ／ %d" % [int(m.skill_charge[g.me]),roundi(m.skill_need(g.me))])))
	g.draw_string(g.font,Vector2(r.position.x+54,r.position.y+52),state,HORIZONTAL_ALIGNMENT_LEFT,r.size.x-100,13,GOLD_LIT if ready else Color(text_col,0.8))
	if has_sk: Ornament.cost_medallion(g,Vector2(r.end.x-28,r.get_center().y),15.0,str(roundi(m.skill_need(g.me))),not ready)
	if ready and lively(g):
		var perim := PackedVector2Array(pts)
		for j: int in range(5):
			var u := fposmod(t*0.35+j/5.0,1.0)*4.0
			var seg := int(u)
			var p0: Vector2 = perim[seg%4].lerp(perim[(seg+1)%4],u-seg)
			g.draw_circle(p0,2.5,GOLD_LIT)
			g.draw_circle(p0,5.5,Color(GOLD_LIT,0.25))
	if g.polish.skill_ready_flash > 0.0:
		var rp: float = 1.0-clampf(float(g.polish.skill_ready_flash)/0.75,0.0,1.0)
		g.draw_polyline(closed(slanted(r.grow(3.0+rp*14.0),10,10)),Color(0.98,0.80,0.25,sin(rp*PI)*0.8),3.0,true)
	if g.skill_flash_left > 0.0:
		var fp: float = 1.0-clampf(g.skill_flash_left/1.15,0.0,1.0)
		var fa := sin(fp*PI)
		g.draw_polyline(closed(slanted(r.grow(2.0+fp*18.0),10,10)),Color(1.0,0.85,0.30,fa*0.8),3.5,true)
		g.draw_colored_polygon(pts,Color(1.0,0.90,0.45,fa*0.3))
		g.draw_string(g.font,Vector2(r.position.x,r.position.y-8.0-fp*12.0),"★ 領主大招發動！",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,16,Color(0.95,0.72,0.12,fa))

static func closed(pts: PackedVector2Array) -> PackedVector2Array:
	var o := pts.duplicate()
	o.append(pts[0])
	return o
