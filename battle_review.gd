extends RefCounted
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
var log: Array[String] = []
var breakthrough := ""
var break_lane := -1
var economy_samples: Array[Dictionary] = []
var last_sample := 0.0
var last_produced := [0.0,0.0]
var previous_farms := [-1,-1]
var lost_farms := [0,0]
func clear() -> void:
	log.clear()
	economy_samples.clear()
	last_sample = 0.0
	last_produced = [0.0,0.0]
	previous_farms = [-1,-1]
	lost_farms = [0,0]
	breakthrough = ""
	break_lane = -1
func observe(model) -> void:
	# Record observed economy changes; disappearing farms may be destroyed or expire.
	var farms := [model.count_buildings(0,"farm"),model.count_buildings(1,"farm")]
	for team: int in range(2):
		if previous_farms[team] >= 0 and farms[team] < previous_farms[team]:
			var loss: int = previous_farms[team]-farms[team]
			lost_farms[team] += loss
			log.append("%02d:%02d　%s農田減少 %d 座，剩餘 %d 座（摧毀或到期）" % [int(model.elapsed)/60,int(model.elapsed)%60,["紅方","藍方"][team],loss,farms[team]])
			if log.size() > 200: log.pop_front()
		previous_farms[team] = farms[team]
	if economy_samples.is_empty() or model.elapsed-last_sample >= 30.0 or economy_samples[-1].farms != farms:
		economy_samples.append({"time":model.elapsed,"gold":[float(model.stats[0].produced),float(model.stats[1].produced)],"farms":farms.duplicate()})
		last_sample = model.elapsed
	for e: Dictionary in model.events:
		var message := ""
		var side: String = ["紅方","藍方"][e.team] if e.team in [0,1] else ""
		if e.kind == "breach": message = ("%s第 %d 路城牆朽壞倒塌" % [["紅方","藍方"][1-e.team],e.lane+1]) if e.get("crumbled",false) else ("%s打破第 %d 路城牆" % [side,e.lane+1])
		if e.kind == "nightfall" and e.get("first",false): message = "入夜：金幣 ×%s，雙方城牆開始朽壞" % B.number(B.NIGHT_GOLD)
		if e.kind == "dawn": message = "天亮：領地 紅 %d：藍 %d" % [e.land[0],e.land[1]]
		if e.kind == "skill": message = "%s施放%s" % [side,B.lord_data(e.lord).get("skill","技能")]
		if e.kind == "invaded":
			message = "%s的%s從第 %d 路突破" % [side,B.CARDS.get(e.get("unit_kind",""),{}).get("name","部隊"),e.lane+1]
			breakthrough = message
			break_lane = e.lane
		if not message.is_empty():
			log.append("%02d:%02d　%s" % [int(model.elapsed)/60,int(model.elapsed)%60,message])
			if log.size() > 200: log.pop_front()
static func pressure(model, team: int, lane: int) -> int:
	var nearby := false
	for u: Dictionary in model.units:
		if u.hp <= 0 or u.team == team or u.lane != lane or u.get("spawn_delay",0) > 0: continue
		if (u.pos.x < L.GRID_ORIGIN.x+L.CELL_SIZE.x*2 if team == 0 else u.pos.x > L.GRID_ORIGIN.x+L.GRID_SIZE.x-L.CELL_SIZE.x*2): nearby = true
	if nearby: return 2 if model.gates[team][lane] <= 0 else 1
	return 0
func draw_pressure(game) -> void:
	# Danger near our gates only (warnings about the enemy's gates are theirs, not ours): the whole
	# lane pulses red, harder and faster once that gate is already broken. No words.
	var t: float = Time.get_ticks_msec()/1000.0
	for lane: int in range(5):
		var level := pressure(game.model,game.me,lane)
		if level == 0: continue
		var beat := 0.5+0.5*sin(t*(9.0 if level == 2 else 5.0))
		var alpha := (0.16+0.16*beat) if level == 1 else (0.28+0.24*beat)
		var y: float = L.GRID_ORIGIN.y+lane*L.CELL_SIZE.y
		# Red from our gate fading toward the middle of the field: it points at where the danger is.
		var x0: float = L.GRID_ORIGIN.x-60 if game.me == 0 else L.GRID_ORIGIN.x+L.GRID_SIZE.x+60
		var x1: float = L.GRID_ORIGIN.x+L.GRID_SIZE.x*(0.55 if game.me == 0 else 0.45)
		var red := Color(0.82,0.12,0.08,alpha)
		var clear := Color(0.82,0.12,0.08,0.0)
		game.draw_polygon(PackedVector2Array([Vector2(x0,y),Vector2(x1,y),Vector2(x1,y+L.CELL_SIZE.y),Vector2(x0,y+L.CELL_SIZE.y)]),PackedColorArray([red,clear,clear,red]))
func report(model, names: Array = []) -> String:
	var result := "突破紀錄："+(breakthrough if not breakthrough.is_empty() else "本局沒有部隊入城紀錄。")+"\n\n"
	for team: int in range(2):
		var s: Dictionary = model.stats[team]
		var side_label: String = "%s（%s）" % [["紅方","藍方"][team],names[team] if names.size() > team else B.lord_name(model.lords[team].lord)]
		result += "%s：產出 %d 金幣 · 滿額溢出 %d · 出牌 %d 次 · 技能 %d 次\n" % [side_label,s.produced,s.wasted,s.plays,s.get("skills",0)]
	for team: int in range(2):
		var ranked: Array = model.stats[team].damage.keys().filter(func(k: String) -> bool: return B.CARDS.has(k))
		ranked.sort_custom(func(a: String, b: String) -> bool: return model.stats[team].damage[a] > model.stats[team].damage[b])
		if ranked.is_empty(): continue
		var side_label: String = "%s（%s）" % [["紅方","藍方"][team],names[team] if names.size() > team else B.lord_name(model.lords[team].lord)]
		result += "%s傷害前三：%s\n" % [side_label,"、".join(ranked.slice(0,3).map(func(k: String) -> String: return "%s %d" % [B.CARDS[k].name,model.stats[team].damage[k]]))]
	result += "\n下局可嘗試："
	if model.winner < 0 or (model.night_decay and model.elapsed >= B.DAWN-0.001): result += "入夜後城牆會自己倒下：趁對方領主在別路時，從空門那一路送兵進去，別等到天亮比領地。"
	elif model.stats[0].wasted >= 10: result += "金幣接近上限時提早部署，減少產出溢出。"
	elif model.winner == 1 and model.stats[1].produced > model.stats[0].produced*1.25 and lost_farms[0] > 0: result += "本局產金落後，且農田曾減少。先保留安全的經濟後方，再擴張前線；補兵之外也要恢復產能。"
	elif model.winner == 1: result += "先查看突破路線，在敵兵抵達殘垣前補兵；破門後仍有回防機會。"
	else: result += "比較兩軍技能時機，看看能否在進攻前保留足夠金幣。"
	result += "\n\n關鍵事件（依時間，最多保留最近 200 筆）\n"
	return result+("\n".join(log) if not log.is_empty() else "沒有記錄到破門、技能或突破事件。")

func draw_charts(g) -> void:
	var points: Array = economy_samples.duplicate()
	points.append({"time":g.model.elapsed,"gold":[float(g.model.stats[0].produced),float(g.model.stats[1].produced)],"farms":[g.model.count_buildings(0,"farm"),g.model.count_buildings(1,"farm")]})
	g.label_at(Vector2(1080,125),"紅方 ━　藍方 ┄",20)
	for index: int in range(2):
		var key: String = "gold" if index == 0 else "farms"
		var r := Rect2(195+index*675,210,540,215)
		g.label_at(Vector2(r.position.x-45,183),"累計產金（所有來源）" if index == 0 else "農田數量（座）",24)
		var ceiling := 1.0
		for point: Dictionary in points:
			for value: float in point[key]: ceiling = maxf(ceiling,value)
		ceiling = ceilf(ceiling/4.0)*4.0
		for row: int in range(5):
			var y: float = r.end.y-r.size.y*row/4.0
			g.draw_line(Vector2(r.position.x,y),Vector2(r.end.x,y),Color(g.INK,0.14),1)
			g.draw_string(g.font,Vector2(r.position.x-50,y+6),str(int(ceiling*row/4)),HORIZONTAL_ALIGNMENT_RIGHT,40,16,g.INK)
		for tick: int in range(5):
			var t: float = g.model.elapsed*tick/4.0
			g.label_at(Vector2(r.position.x+r.size.x*tick/4.0-18,r.end.y+25),"%02d:%02d" % [int(t)/60,int(t)%60],16)
		for team: int in range(2):
			var path := PackedVector2Array()
			for point: Dictionary in points:
				var at := Vector2(r.position.x+r.size.x*point.time/maxf(1,g.model.elapsed),r.end.y-r.size.y*point[key][team]/ceiling)
				if key == "farms" and not path.is_empty(): path.append(Vector2(at.x,path[-1].y))
				path.append(at)
			var color: Color = g.RED if team == 0 else g.BLUE
			if path.size() > 1:
				if team == 0: g.draw_polyline(path,color,3,true)
				else:
					for i: int in range(1,path.size()): g.draw_dashed_line(path[i-1],path[i],color,3,7,true)
			if not path.is_empty(): g.draw_circle(path[-1],4,color)
