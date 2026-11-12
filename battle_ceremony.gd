extends RefCounted
# The two ceremonies around a battle (2026-11-12): the banner that names both sides as it starts,
# and the page that closes it. Drawing only: the buttons and their actions stay in game.gd
# (overlay_buttons), and the figures come from the model's own statistics.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

const PANEL := Rect2(310,110,980,506) # game.gd RESULT_RECT is the same rectangle
const PANEL_DELAY := 0.9 # the field holds the last blow this long before the page comes down
const PANEL_IN := 0.45

# ---- the opening banner ------------------------------------------------------------------------

static func headline(g) -> String:
	if g.net != null: return "連線對戰"
	if g.rogue.in_battle: return "肉鴿 · 第 %d / %d 場" % [g.rogue.run.floor+1,g.rogue.Catalog.FLOORS]
	if g.adventure.index >= 0: return "征服 · %s" % g.adventure.STAGES[g.adventure.index].name
	if g.spectating: return "觀戰"
	return "自由對戰 · "+["簡單","普通","困難"][g.model.difficulty]

# The name under a side's portrait: its lord, or the rabble an adventure stage fields without one.
static func side_name(g, team: int) -> String:
	if team == 1 and g.adventure.index >= 0 and g.adventure.STAGES[g.adventure.index].enemy_camp: return "強盜"
	return B.lord_name(g.model.lords[team].lord)

static func intro(g) -> void:
	if g.intro_left <= 0.0 or g.model.ended: return
	var k: float = 1.0-g.intro_left/g.INTRO_TIME
	var enter: float = 1.0-pow(1.0-clampf(k/0.16,0,1),3)
	var alpha: float = 1.0-clampf((k-0.78)/0.22,0,1)
	var band := Rect2(L.FIELD_FRAME.position.x+4,322,L.FIELD_FRAME.size.x-8,150)
	g.draw_rect(band,Color(0.17,0.12,0.08,0.62*alpha))
	g.draw_line(band.position+Vector2(0,5),Vector2(band.end.x,band.position.y+5),Color(0.84,0.69,0.43,alpha),2)
	g.draw_line(Vector2(band.position.x,band.end.y-5),band.end-Vector2(0,5),Color(0.84,0.69,0.43,alpha),2)
	g.draw_string(g.font,Vector2(0,band.position.y+44),headline(g),HORIZONTAL_ALIGNMENT_CENTER,L.VIEWPORT_SIZE.x,24,Color(0.95,0.86,0.66,alpha))
	g.draw_string(g.font,Vector2(0,band.position.y+110),"VS",HORIZONTAL_ALIGNMENT_CENTER,L.VIEWPORT_SIZE.x,56,Color(0.98,0.90,0.70,alpha))
	for side: int in range(2):
		var team: int = g.me if side == 0 else 1-g.me
		var slide: float = (1.0-enter)*420.0*(-1.0 if side == 0 else 1.0)
		var x: float = (430.0 if side == 0 else 1170.0)+slide
		var color: Color = g.RED if team == 0 else g.BLUE
		var portrait := Rect2(x-70,band.position.y-18,140,176)
		var lord: String = g.model.lords[team].lord
		if g.model.lord_active[team] or team == g.me:
			g.draw_fitted_facing(g.lord_art(lord,team),portrait,1.0 if side == 0 else -1.0,Color(1,1,1,alpha))
		var name_x: float = x+90 if side == 0 else x-90-300
		g.draw_string(g.font,Vector2(name_x,band.position.y+92),side_name(g,team),HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT,300,34,Color(color.lightened(0.55),alpha))
		g.draw_string(g.font,Vector2(name_x,band.position.y+122),B.lord_data(lord).role,HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT,300,18,Color(0.92,0.84,0.66,alpha*0.9))

# ---- the closing page --------------------------------------------------------------------------

# 1 victory, -1 defeat, 0 draw - from the seat of whoever is watching.
static func mood(g) -> int:
	var w: int = g.model.winner
	if w < 0: return 0
	if g.spectating: return 1
	return 1 if w == g.me else -1

static func title(g) -> String:
	var w: int = g.model.winner
	if w < 0: return "平手"
	if g.spectating: return "紅獅勝利" if w == 0 else "藍旗勝利"
	return "勝利" if w == g.me else "敗北"

# One line on how it ended.
static func story(g) -> String:
	var m = g.model
	if g.adventure.index >= 0 and not g.adventure.outcome.is_empty(): return g.adventure.outcome
	if g.rogue.in_battle and not g.rogue.outcome.is_empty(): return g.rogue.outcome
	var names := ["紅獅","藍旗"]
	if dawn(m):
		if m.winner < 0: return "天亮了，雙方領地一樣大，這一頁沒有勝者。"
		return "天亮了，領地較大的%s獲勝。" % names[m.winner]
	if m.winner < 0: return "勝負未分。"
	var lane: int = g.review.break_lane
	var road: String = ("第 %s 路" % g.ROMAN[m.active_lanes.find(lane)]) if lane in m.active_lanes else ""
	if g.spectating: return "%s的士兵從%s攻進了%s主堡。" % [names[m.winner],road,names[1-m.winner]]
	return ("我軍從%s攻進了敵方主堡。" % road) if m.winner == g.me else ("敵軍從%s攻進了我方主堡。" % road)

# The match ran out the day (battle.gd dawn_verdict) instead of ending at a gate.
static func dawn(m) -> bool:
	return m.ended and m.night_decay and m.elapsed >= B.DAWN-0.001 and m.winner != -2

# The card that did the most damage for a side ("" when it never hurt anything).
static func champion(m, team: int) -> String:
	var best := ""
	var most := 0.0
	for kind: String in m.stats[team].damage:
		if not B.CARDS.has(kind): continue # "lord", "skill" and the like are not cards
		if m.stats[team].damage[kind] > most:
			most = m.stats[team].damage[kind]
			best = kind
	return best

static func rows(g) -> Array:
	var m = g.model
	var result: Array = []
	result.append(["打破的城牆",g.result_value(0,"breaches"),g.result_value(1,"breaches")])
	result.append(["領地",m.land(0),m.land(1)])
	result.append(["產出金幣",int(m.stats[0].produced),int(m.stats[1].produced)])
	result.append(["出牌數",int(m.stats[0].plays),int(m.stats[1].plays)])
	result.append(["領主技能",int(m.stats[0].get("skills",0)),int(m.stats[1].get("skills",0))])
	return result

static func result(g) -> void:
	var m = g.model
	var age: float = g.result_age
	var feeling := mood(g)
	var accent: Color = Color("b8862b") if feeling > 0 else (Color("6b6257") if feeling < 0 else Color("7d6f52"))
	# The field dims behind the page; a lost battle goes greyer.
	g.draw_rect(L.FIELD_FRAME,Color(0.16,0.11,0.07,(0.34 if feeling >= 0 else 0.46)*clampf(age/0.7,0,1)))
	if age < PANEL_DELAY: return
	var k: float = clampf((age-PANEL_DELAY)/PANEL_IN,0,1)
	var drop: float = -70.0*pow(1.0-k,3)
	var alpha := k
	var r := Rect2(PANEL.position+Vector2(0,drop),PANEL.size)
	g.draw_rect(Rect2(r.position+Vector2(8,10),r.size),Color(0.12,0.08,0.04,0.30*alpha))
	g.panel(r,Color(0.94,0.88,0.74,alpha),g.INK)
	g.draw_texture_rect(g.PAPER,r.grow(-3),false,Color(1,1,1,0.18*alpha))
	g.draw_rect(r.grow(-8),Color(accent,0.9*alpha),false,3)
	g.draw_rect(r.grow(-14),Color(g.INK,0.35*alpha),false,1)
	g.draw_fitted(g.ART.ornament(4),Rect2(r.position.x+r.size.x*0.5-170,r.position.y+16,340,40),Color(1,1,1,alpha))
	var color: Color = (g.RED if m.winner == 0 else g.BLUE) if m.winner >= 0 else g.INK
	if not g.spectating and feeling < 0: color = Color("4c4338")
	g.draw_string(g.font,Vector2(r.position.x,r.position.y+122),title(g),HORIZONTAL_ALIGNMENT_CENTER,r.size.x,68,Color(color,alpha))
	g.draw_string(g.font,Vector2(r.position.x+40,r.position.y+162),story(g),HORIZONTAL_ALIGNMENT_CENTER,r.size.x-80,21,Color(g.INK,alpha))
	var t := int(m.elapsed)
	g.draw_string(g.font,Vector2(r.position.x,r.position.y+190),"戰鬥時間 %02d:%02d · %s" % [t/60,t%60,["上午","正午","黃昏","入夜"][m.day_phase()]],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,17,Color(0.44,0.36,0.25,alpha))
	# The winning lord stands at the left (ours in a draw), ringed with laurel after a win.
	var shown: int = m.winner if m.winner >= 0 else g.me
	var portrait := Rect2(r.position+Vector2(86,206),Vector2(180,172))
	if feeling > 0:
		rays(g,portrait.get_center(),alpha)
		laurel(g,portrait.get_center()+Vector2(0,6),alpha)
	g.draw_fitted(g.lord_art(m.lords[shown].lord,shown),portrait,Color(1,1,1,alpha),true)
	g.draw_string(g.font,Vector2(portrait.position.x-50,portrait.end.y+42),B.lord_name(m.lords[shown].lord),HORIZONTAL_ALIGNMENT_CENTER,portrait.size.x+100,22,Color(g.RED if shown == 0 else g.BLUE,alpha))
	# Figures, red and blue side by side.
	var left: float = r.position.x+360
	var top: float = r.position.y+230
	g.draw_string(g.font,Vector2(left+250,top),"紅獅",HORIZONTAL_ALIGNMENT_CENTER,110,20,Color(g.RED,alpha))
	g.draw_string(g.font,Vector2(left+380,top),"藍旗",HORIZONTAL_ALIGNMENT_CENTER,110,20,Color(g.BLUE,alpha))
	g.draw_line(Vector2(left,top+10),Vector2(left+500,top+10),Color(g.INK,0.35*alpha),1.5)
	var table: Array = rows(g)
	for i: int in range(table.size()):
		var y := top+36+i*26
		# Each row counts up from zero as the page settles.
		var grow: float = clampf((age-PANEL_DELAY-PANEL_IN-i*0.08)/0.5,0,1)
		g.draw_string(g.font,Vector2(left,y),table[i][0],HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color(g.INK,alpha))
		for team: int in range(2):
			var better: bool = table[i][1+team] > table[i][2-team]
			g.draw_string(g.font,Vector2(left+250+team*130,y),str(int(round(table[i][1+team]*grow))),HORIZONTAL_ALIGNMENT_CENTER,110,20 if better else 19,Color(g.INK if not better else (g.RED if team == 0 else g.BLUE),alpha))
	# 本局功臣: each side's hardest-hitting card.
	var y2 := top+36+table.size()*26+12
	g.draw_line(Vector2(left,y2-22),Vector2(left+500,y2-22),Color(g.INK,0.18*alpha),1)
	g.draw_string(g.font,Vector2(left,y2+6),"本局功臣",HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color(g.INK,alpha))
	for team: int in range(2):
		var kind := champion(m,team)
		if kind.is_empty(): continue
		var cell := Vector2(left+246+team*130,y2-22)
		g.draw_fitted(g.art(B.CARDS[kind].get("art",[kind])[0],team),Rect2(cell,Vector2(40,40)),Color(1,1,1,alpha),true)
		var name: String = B.CARDS[kind].name
		g.draw_string(g.font,cell+Vector2(42,27),name,HORIZONTAL_ALIGNMENT_LEFT,-1,13 if name.length() > 4 else 15,Color(g.INK,alpha))
	if age >= PANEL_DELAY+PANEL_IN:
		for item: Array in g.overlay_buttons():
			var hover: bool = item[0].has_point(g.get_global_mouse_position())
			g.panel(item[0],Color("fbf1d8") if hover else Color("f3e6c6"),accent if hover else g.INK)
			g.draw_string(g.font,item[0].position+Vector2(0,27),item[1],HORIZONTAL_ALIGNMENT_CENTER,item[0].size.x,20,g.INK)
	if feeling > 0: leaves(g,age-PANEL_DELAY)
	elif feeling < 0: ash(g,age)

# Slow rays turning behind the victor.
static func rays(g, at: Vector2, alpha: float) -> void:
	for i: int in range(12):
		var a: float = g.clock*0.25+i*TAU/12
		var points := PackedVector2Array([at,at+Vector2.from_angle(a-0.10)*150,at+Vector2.from_angle(a+0.10)*150])
		g.draw_colored_polygon(points,Color(1.0,0.80,0.30,0.16*alpha))

static func laurel(g, at: Vector2, alpha: float) -> void:
	g.draw_circle(at,98,Color(1.0,0.90,0.60,0.20*alpha))
	for side: float in [-1.0,1.0]:
		for i: int in range(9):
			var a: float = PI*0.5+side*(0.35+i*0.26)
			var p := at+Vector2(cos(a),sin(a))*98
			var leaf: float = a+side*1.1
			g.tf(p,leaf,Vector2(1,0.42))
			g.draw_circle(Vector2.ZERO,13,Color(0.46,0.56,0.24,alpha))
			g.draw_arc(Vector2.ZERO,13,0,TAU,14,Color(0.25,0.30,0.12,alpha),1.5,true)
			g.tf()

# Gold leaves drifting down the whole page for a win.
static func leaves(g, age: float) -> void:
	for i: int in range(46):
		var seed_x: float = g.scenery_noise(i,301)
		var fall: float = fposmod(age*(0.10+0.07*g.scenery_noise(i,302))+g.scenery_noise(i,303),1.0)
		if age < g.scenery_noise(i,303)*1.5: continue
		var p := Vector2(60+seed_x*1480+sin(age*1.3+i)*26,-20+fall*940)
		g.tf(p,age*(1.2+seed_x)+i,Vector2(1,0.55))
		g.draw_circle(Vector2.ZERO,5+3*g.scenery_noise(i,304),Color(0.93,0.74,0.26,0.85) if i%3 else Color(0.80,0.33,0.22,0.8))
		g.tf()

# Ash drifting across a lost field.
static func ash(g, age: float) -> void:
	for i: int in range(36):
		var fall: float = fposmod(age*(0.05+0.04*g.scenery_noise(i,311))+g.scenery_noise(i,312),1.0)
		var p := Vector2(40+g.scenery_noise(i,313)*1520+sin(age*0.6+i)*40,100+fall*600)
		g.draw_circle(p,1.5+2*g.scenery_noise(i,314),Color(0.25,0.22,0.20,0.5*(1-fall)))
