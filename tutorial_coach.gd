extends RefCounted
# 冒險教學教練（2026-11-21）。冒險模式就是新手教學：
# - 第一章每關照 tutorial_lessons.gd 的腳本逐步指引（提示框、高亮、腳本敵軍、完成條件）；
# - 其餘關卡開戰時顯示「本關教學」，新敵人第一次出現時跳出說明，輸了在結算頁下方給一句提示。
# 完成條件只讀對局狀態（統計、建築、領地、城牆），不依賴繪圖事件；腳本敵軍用 deploy 依對局時間派出，
# 不花敵方金幣。畫面只用 game.gd 的繪圖工具，不改卡牌數值與對局規則。
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Lessons = preload("res://tutorial_lessons.gd")
const Keywords = preload("res://card_keywords.gd")

const PANEL := Rect2(330,108,940,104) # 一路／三路關卡：空著的第 I 路
const STRIP := Rect2(400,90,800,52) # 五路關卡：頂端精簡一列
const BANNER := Rect2(400,96,800,104)
const CALLOUT := Rect2(430,100,740,96)
const Hud = preload("res://battle_hud.gd")
const Ceremony = preload("res://battle_ceremony.gd")
const LORD_PLATE := Hud.LORD_PLATE
const PURSE := Hud.PURSE_PLATE
const CLOCK := Rect2(Hud.DIAL-Vector2(Hud.DIAL_R,Hud.DIAL_R),Vector2(Hud.DIAL_R,Hud.DIAL_R)*2)
const SUNDIAL := Rect2(Hud.DIAL-Vector2(Hud.RING_R+5,Hud.RING_R+5),Vector2(Hud.RING_R+5,Hud.RING_R+5)*2)
const LOSS_TIP := Rect2(310,626,980,54)
const GOLD := Color("d2ad58")
const BANNER_TIME := 8.0
const CALLOUT_TIME := 7.0
const PHASE_NOTES := ["","正午：金幣與冷卻 ×2","黃昏：金幣與冷卻 ×2.5","入夜：金幣與冷卻 ×3，雙方城牆開始自己崩塌"]

var on := false
var stage: Dictionary = {}
var lesson: Dictionary = {}
var steps: Array = []
var step := 0
var started := false
var start_time := 0.0
var step_start := 0.0
var flash_left := 0.0 # seconds of the ✓ after a finished step (model time)
var waves: Array = []
var wave_count := 0
var seen_foes: Dictionary = {}
var kills := 0
var banner_until := -1.0
var callouts: Array = []
var callout_until := -1.0
var called: Dictionary = {}
var phase := 0
var phase_until := -1.0
var ward_hp: Array = [] # enemy wall hp held while the lesson's ward stands, per lane

func begin(g, d: Dictionary) -> void:
	on = true
	stage = d
	lesson = Lessons.SCRIPTS.get(String(d.get("id","")),{})
	steps = lesson.get("steps",[])
	step = 0
	started = false
	start_time = 0.0
	step_start = 0.0
	flash_left = 0.0
	wave_count = 0
	seen_foes.clear()
	kills = 0
	banner_until = -1.0
	callouts.clear()
	callout_until = -1.0
	called.clear()
	phase = 0
	phase_until = -1.0
	waves.clear()
	for w: Dictionary in lesson.get("waves",[]):
		var copy := w.duplicate()
		copy.start = -1.0
		copy.next = INF
		copy.done = false
		waves.append(copy)
	setup(g.model,lesson.get("setup",{}))
	ward_hp = g.model.gates[1].duplicate()

func scripted() -> bool:
	return not steps.is_empty()

func setup(m, s: Dictionary) -> void:
	if s.has("enemy_gate"):
		for lane: int in m.active_lanes: m.gates[1][lane] = float(s.enemy_gate)
	if s.has("ink"): m.ink[0] = float(s.ink)
	for team: int in range(2):
		var key: String = ["our_farms","enemy_farms"][team]
		if not s.has(key): continue
		var keep := int(s[key])
		var kept: Array[Dictionary] = []
		for b: Dictionary in m.buildings:
			if b.team == team and b.kind == "farm":
				if keep <= 0: continue
				keep -= 1
			kept.append(b)
		m.buildings = kept
		m.refresh_territory()
	if not bool(s.get("lord",true)):
		m.lord_active[0] = false
		m.lords[0].hp = 0
	# The enemy always plays its own hand on top of the scripted waves, at the chosen difficulty
	# (使用者 2026-11-22：敵人要出牌、要用費用，不然難度沒用了). "enemy_ai" no longer switches it off.
	# Each lesson sets how much base gold the enemy earns (enemy_income, ×1.0 = normal; 使用者：基礎獲得金幣量可調低或調高).
	if s.has("enemy_income"): m.team_mods[1]["income_mult"] = float(m.lord_mod(1,"income_mult",1.0))*float(s.enemy_income)
	if s.has("enemy_ink"): m.ink[1] = float(s.enemy_ink)
	if s.has("skill_charge"): m.skill_charge[0] = m.skill_need(0)*clampf(float(s.skill_charge),0.0,1.0)
	m.farm_cd[0] = 0.0

# ---- 每個物理影格（adventure.update 呼叫） ----
func update(g) -> void:
	if not on: return
	var m = g.model
	if m.paused or m.ended: return
	if not started:
		if float(g.intro_left) > 0.0: return
		started = true
		start_time = m.elapsed
		step_start = m.elapsed
		if not scripted() and not String(stage.get("rule_desc","")).is_empty(): banner_until = m.elapsed+BANNER_TIME
	count_kills(m)
	run_waves(m)
	advance(g,m)
	hold_walls(m)
	watch_new_enemy(m)
	if bool(lesson.get("setup",{}).get("phase_notes",false)) and m.day_phase() > phase:
		phase = m.day_phase()
		phase_until = m.elapsed+6.0

# Lesson wards: the enemy wall cannot fall before the lesson reaches its "break the wall" step, and in
# the first lessons our own wall never drops below half. Restored after every step; one frame's damage
# is far below either floor, so a gate never actually reaches 0 while warded.
func warded() -> bool:
	var s: Dictionary = lesson.get("setup",{})
	return s.has("ward_until") and step < int(s.ward_until)

func hold_walls(m) -> void:
	if warded():
		for lane: int in m.active_lanes: m.gates[1][lane] = maxf(m.gates[1][lane],float(ward_hp[lane]))
	if bool(lesson.get("setup",{}).get("our_ward",false)):
		for lane: int in m.active_lanes: m.gates[0][lane] = maxf(m.gates[0][lane],B.GATE_HP*0.5)

func count_kills(m) -> void:
	var alive := 0
	for u: Dictionary in m.units:
		if u.team != 1 or u.hp <= 0: continue
		seen_foes[u.id] = true
		alive += 1
	kills = seen_foes.size()-alive

func run_waves(m) -> void:
	for w: Dictionary in waves:
		if w.done: continue
		if w.start < 0.0:
			if int(w.get("after",-1)) >= step: continue
			w.start = m.elapsed
			w.next = m.elapsed+float(w.get("delay",0.0))
		if int(w.get("until",-1)) >= 0 and step > int(w.until):
			w.done = true
			continue
		if m.elapsed < w.next: continue
		send(m,w)
		if float(w.get("every",0.0)) > 0.0: w.next += float(w.every)
		else: w.done = true

func send(m, w: Dictionary) -> void:
	if m.active_lanes.is_empty(): return
	var lane := int(w.get("lane",-1))
	if not lane in m.active_lanes:
		lane = m.active_lanes[wave_count % m.active_lanes.size()]
	wave_count += 1
	var before: int = m.units.size()
	m.deploy(1,String(w.kind),Vector2i(L.GRID_COLUMNS-1,lane))
	# Scripted raiders march in plain sight: stealth is its own lesson (2-9), not a first-day surprise.
	for k: int in range(before,m.units.size()):
		m.units[k].stealthed = false
		m.units[k].revealed = true

func advance(g, m) -> void:
	if flash_left > 0.0: flash_left = maxf(0.0,flash_left-m.last_dt)
	if step >= steps.size(): return
	var s: Dictionary = steps[step]
	var t: float = m.elapsed-step_start
	if t < float(s.get("min",1.0)): return
	var done := String(s.get("done",""))
	# Never stuck: an action step moves on by itself after STEP_MAX seconds.
	if not satisfied(g,m,done,t) and (done == "win" or t < Lessons.STEP_MAX): return
	step += 1
	step_start = m.elapsed
	flash_left = 0.9
	if g.get("sound") != null: g.sound.cue("card_ready")

func satisfied(g, m, cond: String, t: float) -> bool:
	var p := cond.split(":")
	var n := int(p[p.size()-1]) if p.size() > 1 else 1
	match p[0]:
		"selected": return int(g.selected) >= 0 or int(m.stats[0].plays) > 0
		"play": return int(m.stats[0].used.get(p[1],0)) >= (int(p[2]) if p.size() > 2 else 1)
		"plays": return int(m.stats[0].plays) >= n
		"farms": return m.count_buildings(0,"farm") >= n
		"drops": return int(m.stats[0].drops) >= n
		"cultivate": return int(m.stats[0].cultivated) >= n
		"build": return m.buildings.any(func(b: Dictionary) -> bool: return b.team == 0 and b.hp > 0 and b.kind == p[1] and b.cell.x >= int(p[2]))
		"front": return front_col(m) >= n
		"kills": return kills >= n
		"burn": return int(m.stats[1].burned) >= n or m.count_buildings(1,"farm") == 0 # troops may get there first
		"enemy_down": return not m.buildings.any(func(b: Dictionary) -> bool: return b.team == 1 and b.hp > 0 and b.kind == p[1])
		"skill_ready": return m.skill_error(0).is_empty()
		"skill": return int(m.stats[0].get("skills",0)) >= 1
		"gate_down": return m.active_lanes.any(func(lane: int) -> bool: return m.gates[1][lane] <= 0)
		"time": return t >= float(p[1])
	return false

static func front_col(m) -> int:
	var best := -1
	for lane: int in m.active_lanes:
		for col: int in range(L.GRID_COLUMNS):
			if m.territory_owner(Vector2i(col,lane)) == 0: best = maxi(best,col)
	return best

# The stage's featured enemy, called out once when it first shows up (a unit, a building, or a lord skill).
func watch_new_enemy(m) -> void:
	var kind := String(stage.get("new_enemy",""))
	if kind.is_empty() or called.has(kind): return
	if kind == "skill":
		if int(m.stats[1].get("skills",0)) < 1: return
		called[kind] = true
		var lord: String = m.lords[1].lord
		var info: Dictionary = B.lord_data(lord)
		callouts.append({"art":"lord:"+lord,"title":"敵方領主技能：%s" % info.get("skill",""),"body":B.skill_text(lord),"pos":m.lords[1].pos})
		return
	var found: Dictionary = {}
	for u: Dictionary in m.units:
		if u.team == 1 and u.hp > 0 and u.get("spawn_delay",0.0) <= 0.0 and (u.kind == kind or String(u.get("card","")) == kind):
			found = u
			break
	if found.is_empty():
		for b: Dictionary in m.buildings:
			if b.team == 1 and b.hp > 0 and b.kind == kind:
				found = b
				break
	if found.is_empty(): return
	called[kind] = true
	var card: Dictionary = B.CARDS.get(kind,{})
	var kws: Array[String] = Keywords.for_card(kind)
	var body: String = String(stage.get("enemy_note",""))
	if body.is_empty(): body = Keywords.desc_of(kws[0]) if not kws.is_empty() else String(card.get("role",""))
	callouts.append({"art":kind,"title":"新敵人：%s（%s）" % [card.get("name",kind),card.get("role","")],"body":body,"pos":found.pos})

func loss_tip() -> String:
	var tip := String(lesson.get("loss",""))
	return tip if not tip.is_empty() else String(stage.get("tip",""))

# ---- 繪圖（game.gd draw_battle 最後一行呼叫） ----
func paint(g) -> void:
	if not on or g.adventure.index < 0 or g.screen != "battle": return
	var m = g.model
	if m.ended:
		paint_loss_tip(g,m)
		return
	if not started or m.paused: return
	if warded(): paint_ward(g,m)
	paint_hints(g,m)
	if not m.lord_active[0] and m.lords[0].hp <= 0: paint_lord_away(g)
	if scripted() and step < steps.size(): paint_step(g,m)
	elif m.elapsed < banner_until: paint_banner(g,m)
	elif not callouts.is_empty(): paint_callout(g,m)
	if m.elapsed < phase_until and phase > 0: paint_phase(g)

func paint_step(g, m) -> void:
	var s: Dictionary = steps[step]
	var compact := bool(lesson.get("setup",{}).get("compact",false))
	var r := STRIP if compact else PANEL
	g.panel(r,Color(0.96,0.91,0.78,0.95),GOLD.darkened(0.25))
	g.draw_rect(r.grow(-5),Color(g.INK,0.25),false,1.0)
	var tag := String(stage.get("rule_tag",""))
	var title := tag if tag.begins_with(lesson_name()) else "%s · %s" % [lesson_name(),tag]
	var count := "%d / %d" % [step+1,steps.size()]
	if compact:
		g.draw_string(g.font,r.position+Vector2(16,22),title,HORIZONTAL_ALIGNMENT_LEFT,-1,15,g.RED)
		g.draw_string(g.font,r.position+Vector2(r.size.x-80,22),count,HORIZONTAL_ALIGNMENT_RIGHT,64,14,Color("7a6446"))
		g.draw_multiline_string(g.font,r.position+Vector2(16,41),String(s.text),HORIZONTAL_ALIGNMENT_LEFT,r.size.x-32,15,1,g.INK)
	else:
		g.draw_fitted(g.art("militia"),Rect2(r.position+Vector2(12,8),Vector2(72,80)),Color.WHITE,true)
		g.draw_string(g.font,r.position+Vector2(96,26),title,HORIZONTAL_ALIGNMENT_LEFT,-1,17,g.RED)
		for i: int in range(steps.size()):
			var c := Vector2(r.end.x-24-(steps.size()-1-i)*18,r.position.y+21)
			g.draw_circle(c,5.5,GOLD if i < step else (Color(g.RED) if i == step else Color(g.INK,0.22)))
		g.draw_multiline_string(g.font,r.position+Vector2(96,52),String(s.text),HORIZONTAL_ALIGNMENT_LEFT,r.size.x-120,19,2,g.INK)
		g.draw_string(g.font,Vector2(r.end.x-200,r.end.y-6),"空白鍵暫停 · %s" % count,HORIZONTAL_ALIGNMENT_RIGHT,186,13,Color("7a6446"))
		if warded(): g.draw_string(g.font,Vector2(r.position.x+96,r.end.y-6),"藍方城牆有教學結界：照提示學完前幾步才打得破",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("7a6446"))
	if flash_left > 0.0:
		var a := clampf(flash_left/0.9,0.0,1.0)
		g.draw_string(g.font,Vector2(r.end.x-70,r.position.y+r.size.y*0.5+18),"✓",HORIZONTAL_ALIGNMENT_CENTER,48,44,Color(0.24,0.48,0.24,a))

func lesson_name() -> String:
	var code := String(stage.get("code",""))
	if bool(stage.get("boss",false)): return "畢業考"
	if bool(stage.get("special",false)): return "小考"
	return "第 %s 課" % code.get_slice("-",1)

func paint_banner(g, m) -> void:
	var a := clampf((banner_until-m.elapsed)/0.6,0.0,1.0)
	var r := BANNER
	g.panel(r,Color(0.96,0.91,0.78,0.95*a),Color(GOLD.darkened(0.25),a))
	g.draw_string(g.font,r.position+Vector2(20,30),"本關教學 · %s" % stage.get("rule_tag",""),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color(g.RED,a))
	g.draw_multiline_string(g.font,r.position+Vector2(20,56),String(stage.get("rule_desc","")),HORIZONTAL_ALIGNMENT_LEFT,r.size.x-40,16,2,Color(g.INK,a))
	var fresh: Array = stage.get("rewards",[]).filter(func(k: String) -> bool: return B.CARDS.has(k))
	if not fresh.is_empty():
		var names: Array = fresh.map(func(k: String) -> String: return B.CARDS[k].name)
		g.draw_string(g.font,r.position+Vector2(20,r.size.y-10),"本關新卡：%s（已加入這一場的牌組）" % "、".join(names),HORIZONTAL_ALIGNMENT_LEFT,r.size.x-40,15,Color(Color("3c6e2e"),a))

func paint_callout(g, m) -> void:
	if callout_until < 0.0: callout_until = m.elapsed+CALLOUT_TIME
	if m.elapsed >= callout_until:
		callouts.pop_front()
		callout_until = -1.0
		return
	var c: Dictionary = callouts[0]
	var a := clampf((callout_until-m.elapsed)/0.6,0.0,1.0)
	var r := CALLOUT
	g.panel(r,Color(0.97,0.92,0.80,0.95*a),Color(g.BLUE,a))
	var tex: Texture2D = g.lord_art(String(c.art).trim_prefix("lord:"),1) if String(c.art).begins_with("lord:") else g.art(g.card_art_kinds(String(c.art))[0],1)
	g.draw_fitted(tex,Rect2(r.position+Vector2(10,8),Vector2(78,80)),Color(1,1,1,a),true)
	g.draw_string(g.font,r.position+Vector2(100,30),String(c.title),HORIZONTAL_ALIGNMENT_LEFT,r.size.x-114,19,Color(g.BLUE,a))
	g.draw_multiline_string(g.font,r.position+Vector2(100,54),String(c.body),HORIZONTAL_ALIGNMENT_LEFT,r.size.x-114,15,1,Color(g.INK,a))
	var tip := String(stage.get("tip",""))
	if not tip.is_empty():
		g.draw_multiline_string(g.font,r.position+Vector2(100,80),"對策：%s" % tip,HORIZONTAL_ALIGNMENT_LEFT,r.size.x-114,15,1,Color(Color("3c6e2e"),a))
	# A thin ink line from the note down to where the newcomer stands.
	var at: Vector2 = g.cinematic.field_transform(g)*Vector2(c.pos)
	g.draw_line(Vector2(clampf(at.x,r.position.x+20,r.end.x-20),r.end.y),at+Vector2(0,-30),Color(g.BLUE,0.55*a),2.0,true)
	g.draw_circle(at+Vector2(0,-30),4.0,Color(g.BLUE,0.75*a))

# A pale gold veil over each warded enemy wall section.
func paint_ward(g, m) -> void:
	g.draw_set_transform_matrix(g.cinematic.field_transform(g))
	var k := 0.5+0.5*sin(float(g.clock)*2.5)
	for lane: int in m.active_lanes:
		var y: float = L.cell_center(Vector2i(0,lane)).y
		var r := Rect2(L.gate_icon_x(1)-30,y-52,60,104)
		g.draw_rect(r,Color(1.0,0.92,0.55,0.12+0.08*k))
		g.draw_rect(r,Color(0.85,0.66,0.20,0.45+0.25*k),false,2.0)
		g.draw_string(g.font,Vector2(r.position.x-10,r.position.y-6),"教學結界",HORIZONTAL_ALIGNMENT_CENTER,r.size.x+20,12,Color(0.45,0.32,0.10,0.85))
	g.draw_set_transform_matrix(Transform2D.IDENTITY)

func paint_phase(g) -> void:
	var r := Rect2(560,146,480,34)
	g.panel(r,Color(0.20,0.16,0.10,0.82),GOLD)
	g.draw_string(g.font,r.position+Vector2(0,24),PHASE_NOTES[clampi(phase,0,3)],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,17,Color("fff0ca"))

# No lord on the field yet (使用者 2026-11-21：還沒來就先空著): the plate stays blank until lesson 8.
func paint_lord_away(g) -> void:
	var pts := Hud.slanted(LORD_PLATE,12,0)
	Hud.plate(g,pts,Hud.VELLUM,Color("8a6f4a"))
	g.draw_texture_rect(g.PAPER,LORD_PLATE,false,Color(1,1,1,0.10))

func paint_loss_tip(g, m) -> void:
	if m.winner == 0: return
	if float(g.get("result_age")) < Ceremony.PANEL_DELAY + Ceremony.PANEL_IN: return
	var tip := loss_tip()
	if tip.is_empty(): return
	var has_replay_line: bool = g.get("recorder") != null and g.recorder.has_saved_replay() and not OS.has_feature("web")
	var r := Rect2(310,654,980,54) if has_replay_line else LOSS_TIP
	g.panel(r,Color(0.97,0.92,0.80,0.97),GOLD.darkened(0.25))
	var para := TextParagraph.new()
	para.width = r.size.x-32.0
	para.alignment = HORIZONTAL_ALIGNMENT_CENTER
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	para.max_lines_visible = 2
	para.add_string("提示：%s" % tip,g.font,18)
	var py := r.position.y+maxf(4.0,(r.size.y-para.get_size().y)*0.5)
	para.draw(g.get_canvas_item(),Vector2(r.position.x+16.0,py),g.INK)

# ---- 高亮 ----
func paint_hints(g, m) -> void:
	if not scripted() or step >= steps.size(): return
	var hint := String(steps[step].get("hint",""))
	if hint.is_empty(): return
	var k := 0.5+0.5*sin(float(g.clock)*5.0)
	for h: String in hint.split("+",false):
		var head := h.get_slice(":",0)
		match head:
			"card":
				var kind := h.trim_prefix("card:")
				for slot: int in [0,1,2,3,4]:
					if m.kind_at(0,slot) == kind: ring(g,g.card_rect(slot),k,true)
			"home": ring(g,g.card_rect(4),k,true)
			"purse": ring(g,PURSE.grow(-6),k,true)
			"next": ring(g,g.NEXT_RECT,k,true)
			"skill": ring(g,g.SKILL_RECT,k,true)
			"sundial": ring(g,SUNDIAL.grow(5),k,false)
			"clock": ring(g,CLOCK,k,false)
			"walls":
				for side: int in range(2): ring(g,Hud.walls_rect(g,side).grow(3),k,false)
			_: paint_field_hint(g,m,head,k,h.get_slice(":",1))

func paint_field_hint(g, m, head: String, k: float, kind_of_hint: String = "") -> void:
	g.draw_set_transform_matrix(g.cinematic.field_transform(g))
	match head:
		"own_cells":
			for cell: Vector2i in own_cells(m): glow_cell(g,cell,k)
		"front_cells":
			for cell: Vector2i in front_cells(m): glow_cell(g,cell,k,true)
		"behind_farm":
			for b: Dictionary in m.buildings:
				if b.team != 0 or b.kind != "farm" or b.hp <= 0: continue
				for col: int in range(int(b.cell.x)+1):
					var cell := Vector2i(col,int(b.cell.y))
					if m.territory_owner(cell) == 0: glow_cell(g,cell,k,col == int(b.cell.x))
		"our_farm":
			for b: Dictionary in m.buildings:
				if b.team == 0 and b.kind == "farm" and b.hp > 0: circle(g,b.pos,52.0,k)
		"enemy_farm":
			for b: Dictionary in m.buildings:
				if b.team == 1 and b.kind == "farm" and b.hp > 0: circle(g,b.pos,52.0,k)
		"building":
			for b: Dictionary in m.buildings:
				if b.team == 1 and b.kind == kind_of_hint and b.hp > 0:
					circle(g,b.pos,56.0,k)
					arrow(g,b.pos+Vector2(0,-62),k,true)
		"enemy_building":
			for b: Dictionary in m.buildings:
				if b.team == 1 and b.hp > 0 and not B.is_economy_building(b.kind): circle(g,b.pos,56.0,k)
		"enemy_wall":
			for lane: int in m.active_lanes:
				var y: float = L.cell_center(Vector2i(0,lane)).y
				var r := Rect2(L.gate_icon_x(1)-34,y-54,68,108)
				g.draw_rect(r.grow(2.0+3.0*k),Color(1.0,0.86,0.35,0.55+0.4*k),false,3.0)
				arrow(g,Vector2(r.position.x+r.size.x*0.5,r.position.y-6),k,true)
		"enemy_units":
			var box := Rect2()
			var any := false
			for u: Dictionary in m.units:
				if u.team != 1 or u.hp <= 0 or u.get("spawn_delay",0.0) > 0.0: continue
				var ur := Rect2(u.pos-Vector2(26,48),Vector2(52,70))
				box = ur if not any else box.merge(ur)
				any = true
			if any:
				g.draw_rect(box.grow(6.0+3.0*k),Color(0.30,0.45,0.75,0.55+0.4*k),false,3.0)
				arrow(g,Vector2(box.position.x+box.size.x*0.5,box.position.y-10),k,true)
		"lord":
			if m.lords[0].hp > 0:
				circle(g,m.lords[0].pos,44.0,k)
				arrow(g,m.lords[0].pos+Vector2(0,-74),k,true)
	g.draw_set_transform_matrix(Transform2D.IDENTITY)

static func own_cells(m) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for lane: int in m.active_lanes:
		for col: int in range(L.GRID_COLUMNS):
			var cell := Vector2i(col,lane)
			if m.territory_owner(cell) == 0 and m.building_at(cell).is_empty(): out.append(cell)
	return out

static func front_cells(m) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for lane: int in m.active_lanes:
		var best := -1
		for col: int in range(L.GRID_COLUMNS):
			if m.territory_owner(Vector2i(col,lane)) == 0: best = col
		if best >= 0: out.append(Vector2i(best,lane))
	return out

func glow_cell(g, cell: Vector2i, k: float, strong: bool = false) -> void:
	var r := Rect2(L.GRID_ORIGIN+Vector2(cell)*L.CELL_SIZE,L.CELL_SIZE).grow(-6)
	g.draw_rect(r,Color(1.0,0.90,0.45,(0.16 if not strong else 0.24)+0.18*k))
	g.draw_rect(r,Color(0.86,0.64,0.16,0.55+0.4*k),false,2.0+(2.0 if strong else 1.0)*k)

func circle(g, pos: Vector2, radius: float, k: float) -> void:
	g.draw_arc(pos,radius+4.0*k,0,TAU,40,Color(1.0,0.86,0.35,0.6+0.35*k),3.0,true)

func ring(g, r: Rect2, k: float, from_above: bool) -> void:
	g.draw_rect(r.grow(3.0+3.0*k),Color(1.0,0.86,0.35,0.55+0.4*k),false,3.5)
	if from_above: arrow(g,Vector2(r.position.x+r.size.x*0.5,r.position.y-8),k,true)
	else: arrow(g,Vector2(r.position.x+r.size.x*0.5,r.end.y+8),k,false)

# A bobbing gold arrow: pointing down onto the target from above, or up at it from below.
func arrow(g, tip: Vector2, k: float, down: bool) -> void:
	var d := 1.0 if down else -1.0
	var p := tip+Vector2(0,-d*(4.0+5.0*k))
	var pts := PackedVector2Array([p,p+Vector2(-11,-d*16),p+Vector2(-4,-d*16),p+Vector2(-4,-d*28),p+Vector2(4,-d*28),p+Vector2(4,-d*16),p+Vector2(11,-d*16)])
	g.draw_colored_polygon(pts,Color(0.95,0.75,0.25,0.95))
	var edge := pts.duplicate()
	edge.append(pts[0])
	g.draw_polyline(edge,Color(0.36,0.25,0.10,0.9),1.6,true)
