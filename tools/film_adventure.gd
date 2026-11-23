extends SceneTree
# 影片：從標題畫面進冒險模式，照教學指引打完 1-1～1-5 或 1-6～1-10（2026-11-22 / 2026-11-23）。
# 遊戲裝在 SubViewport 裡，滑鼠是畫出來的假游標、點擊用 push_input 送進去，所以錄影不會動到真正的滑鼠。
#   試跑（不出畫面）：godot_console --headless --path . --fixed-fps 30 -s tools/film_adventure.gd -- --verify --from=w1_6 --last=w1_10
#   錄影：在專案放 override.cfg（視窗 1920×1080）後
#         godot_console --path . --minimized --write-movie out.avi --fixed-fps 30 -s tools/film_adventure.gd -- --from=w1_6 --last=w1_10
# 參數：--from=w1_3 從某一課開始（之前的課直接記成已過關）、--last=w1_5 打到哪一課為止。
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Battle = preload("res://battle.gd")
const Coach = preload("res://tutorial_coach.gd")
const Hud = preload("res://battle_hud.gd")
const Conveyor = preload("res://conveyor.gd")
const SCALE := 1.2 # 1600×900 logical page -> 1920×1080 movie
const FPS := 30.0
const SAVE := "user://film_adventure.json"
const REST := Vector2(1180,640) # idle cursor spot above the hand

var game
var vp: SubViewport
var overlay: Node2D
var verify := false
var from_id := "w1_1"
var last_id := "w1_5"
var done := false
var frame := 0
var cursor := Vector2(1300,820)
var ripples: Array = [] # [pos, age]
var fade := 1.0 # black veil over the whole movie (fade in / out)
var ff := false
var ff_badge := 0.0
var rng := RandomNumberGenerator.new()
var log_lines: PackedStringArray = []
var ff_frames := 0
var lesson_start := 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--verify": verify = true
		elif arg.begins_with("--from="): from_id = arg.get_slice("=",1)
		elif arg.begins_with("--last="): last_id = arg.get_slice("=",1)
	rng.seed = 20261122
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	vp = SubViewport.new()
	vp.size = Vector2i(1920,1080)
	vp.size_2d_override = Vector2i(1600,900)
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.audio_listener_enable_2d = true
	root.add_child(vp)
	var shown := TextureRect.new()
	shown.texture = vp.get_texture()
	shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(shown)
	shown.position = Vector2.ZERO
	shown.size = L.VIEWPORT_SIZE
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	overlay = Node2D.new()
	overlay.draw.connect(paint_overlay)
	layer.add_child(overlay)
	game = load("res://main.tscn").instantiate()
	game.adventure.progress_path = SAVE
	seed_progress()
	vp.add_child(game) # _ready shows the title screen
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_size(Vector2i(1920,1080)) # fit_window may have shrunk it
	run()

# Lessons before --from count as already cleared, so a partial take starts on the map at that lesson.
func seed_progress() -> void:
	var ids: Array = []
	var star_map: Dictionary = {}
	for d: Dictionary in game.adventure.STAGES:
		if d.id == from_id: break
		ids.append(d.id)
		star_map[d.id] = 1
	if ids.is_empty(): return
	var f := FileAccess.open(SAVE,FileAccess.WRITE)
	f.store_string(JSON.stringify({"cleared":ids,"ever_cleared":ids,"stars":star_map,"difficulty":0}))
	f.close()

func _process(_delta: float) -> bool:
	frame += 1
	if ff: ff_frames += 1
	for r: Array in ripples: r[1] += 1.0/FPS
	ripples = ripples.filter(func(r: Array) -> bool: return r[1] < 0.6)
	ff_badge = move_toward(ff_badge,1.0 if ff else 0.0,1.0/(0.25*FPS))
	overlay.queue_redraw()
	if verify and frame > int(FPS*60*30): # safety: 30 minutes
		print("TIMEOUT")
		return true
	return done

# ---------------------------------------------------------------- overlay: cursor, clicks, fades
func paint_overlay() -> void:
	for r: Array in ripples:
		var k: float = r[1]/0.6
		overlay.draw_arc(r[0],10.0+k*26.0,0,TAU,40,Color(1,0.93,0.7,(1.0-k)*0.9),3.0,true)
	var p := cursor
	var pts := PackedVector2Array([p,p+Vector2(0,26),p+Vector2(7,20),p+Vector2(12,31),p+Vector2(17,29),p+Vector2(12,18),p+Vector2(20,18)])
	var shadow := PackedVector2Array()
	for q: Vector2 in pts: shadow.append(q+Vector2(2,3))
	overlay.draw_colored_polygon(shadow,Color(0,0,0,0.3))
	overlay.draw_colored_polygon(pts,Color("fffaf0"))
	var outline := pts.duplicate()
	outline.append(p)
	overlay.draw_polyline(outline,Color("2a1d12"),2.0,true)
	if ff_badge > 0.01:
		var r := Rect2(1466,640,108,36) # bottom-right corner of the field, clear of the HUD
		overlay.draw_rect(r,Color(0.16,0.11,0.07,0.72*ff_badge))
		var f: Font = game.font
		overlay.draw_string(f,r.position+Vector2(0,26),"▶▶ ×2",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,20,Color(1,0.94,0.78,ff_badge))
	if fade > 0.001: overlay.draw_rect(Rect2(Vector2.ZERO,L.VIEWPORT_SIZE),Color(0,0,0,fade))

# ---------------------------------------------------------------- time and input helpers
func wait(seconds: float) -> void:
	for i: int in range(maxi(1,int(round(seconds*FPS)))): await process_frame

func set_ff(on: bool) -> void:
	if on == ff: return
	ff = on
	Engine.time_scale = 2.0 if on else 1.0

func push_motion(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p*SCALE
	e.global_position = e.position
	vp.push_input(e)

func push_button(p: Vector2, pressed: bool, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.position = p*SCALE
	e.global_position = e.position
	e.button_index = index
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	vp.push_input(e)

# A hand moves fast at first and settles on the target, on a slight arc.
func move_to(target: Vector2, seconds: float = -1.0) -> void:
	var from := cursor
	var dist := from.distance_to(target)
	if dist < 1.0: return
	if seconds < 0.0: seconds = clampf(0.22+dist/1500.0,0.28,0.75)
	var n := maxi(2,int(round(seconds*FPS)))
	var side := (target-from).orthogonal().normalized()*dist*0.07*(1.0 if rng.randf() < 0.5 else -1.0)
	for i: int in range(1,n+1):
		var t := float(i)/n
		var e := 1.0-pow(1.0-t,3.0)
		cursor = from.lerp(target,e)+side*sin(PI*e)
		push_motion(cursor)
		await process_frame
	cursor = target
	push_motion(cursor)

func click(right: bool = false) -> void:
	var index := MOUSE_BUTTON_RIGHT if right else MOUSE_BUTTON_LEFT
	push_button(cursor,true,index)
	ripples.append([cursor,0.0])
	await wait(0.1)
	push_button(cursor,false,index)
	await process_frame

func click_at(p: Vector2, settle: float = 0.12) -> void:
	await move_to(p)
	await wait(settle)
	await click()

func find_button(caption: String) -> Button:
	for c in game.ui:
		if c is Button and is_instance_valid(c) and c.visible and caption in String(c.text): return c
	return null

func click_button(caption: String, hover: float = 0.35) -> bool:
	var b := find_button(caption)
	if b == null:
		note("button not found: "+caption)
		return false
	var spot := b.position+b.size*Vector2(0.5,0.55)
	if b.size.x > 300.0: spot.x = b.position.x+b.size.x*0.62 # big flags: aim at the caption
	await move_to(spot)
	await wait(hover)
	await click()
	return true

static func read_time(text: String) -> float:
	return clampf(1.0+text.length()*0.11,2.2,8.0)

func note(text: String) -> void:
	var line := "[%6.1fs] %s" % [frame/FPS,text]
	log_lines.append(line)
	print(line)

# ---------------------------------------------------------------- the film
func run() -> void:
	await wait(0.2)
	push_motion(cursor)
	# Title screen: fade in, let the flags unfurl, then pick 冒險模式.
	for i: int in range(int(FPS*1.2)):
		fade = 1.0-float(i+1)/(FPS*1.2)
		await process_frame
	fade = 0.0
	await wait(3.2)
	await move_to(Vector2(1180,560),0.9)
	await wait(0.6)
	await click_button("冒險模式",0.9)
	var started := false
	for d: Dictionary in game.adventure.STAGES:
		if d.id == from_id: started = true
		if not started: continue
		await lesson(d)
		if d.id == last_id: break
	# Back on the map with the next lesson unlocked: linger, then fade out.
	await move_to(Vector2(1000,600),1.2)
	await wait(3.5)
	for i: int in range(int(FPS*1.5)):
		fade = float(i+1)/(FPS*1.5)
		await process_frame
	await wait(0.3)
	note("FILM DONE · %.1f s of footage · %.1f s fast-forwarded" % [frame/FPS,ff_frames/FPS])
	done = true

func lesson(d: Dictionary) -> void:
	lesson_start = frame
	note("== %s %s" % [d.code,d.name])
	# The map: look over the briefing, then start the lesson.
	await wait_screen("adventure")
	await wait(1.0)
	var node: Vector2 = d.map
	var sel: int = game.adventure.selected
	if sel < 0 or sel >= game.adventure.STAGES.size() or String(game.adventure.STAGES[sel].id) != String(d.id):
		await click_at(node+Vector2(6,8),0.2)
		await wait(0.6)
	else:
		await move_to(node+Vector2(6,8),0.8)
		await wait(1.2)
	await move_to(Vector2(1300,330),0.7) # over the briefing text
	await wait(read_time(String(d.get("rule_desc","")))*0.8)
	if find_button("開始上課") != null: await click_button("開始上課",0.5)
	else: await click_button("出征",0.5)
	await story()
	await wait_screen("battle")
	await battle(d)
	set_ff(false)
	await wait(0.4)
	await story()

func wait_screen(name: String, limit: float = 20.0) -> void:
	var n := 0
	while game.screen != name and n < int(limit*FPS):
		n += 1
		await process_frame

# The story pages before and after a lesson: read each line, then turn the page.
func story() -> void:
	await wait(0.3)
	while game.screen == "road_toll_story":
		var s = game.adventure.road_story
		var line: Array = s.lines[s.step]
		var text := String(line[1])
		var before: int = s.step
		await move_to(Vector2(1320,760),0.6)
		await wait(read_time(text))
		var caption := "繼續"
		if before == s.lines.size()-1: caption = s.next_caption if s.victory else "開始戰鬥"
		await click_button(caption,0.3)
		await wait(0.5)

# ---------------------------------------------------------------- the battle
var acted_at := 0
var step_seen := -1
var step_at := 0

func min_gate_hp(m, team: int) -> float:
	var lo := INF
	for lane: int in m.active_lanes: lo = minf(lo,float(m.gates[team][lane]))
	return 0.0 if lo == INF else lo

func battle(d: Dictionary) -> void:
	var m = game.model
	var coach = game.adventure.coach
	step_seen = -1
	acted_at = frame
	await move_to(REST,0.6)
	var next_report := 15.0
	while game.screen == "battle" and not m.ended:
		if m.elapsed >= next_report:
			next_report += 15.0
			var lane: int = m.active_lanes[0]
			var eco := ("belt %d/8" % Conveyor.count(m)) if m.is_conveyor(0) else ("ink %.0f · farms %d vs %d" % [m.ink[0],m.count_buildings(0,"farm"),m.count_buildings(1,"farm")])
			note("  t=%.0f %s · units %d vs %d · min_wall %.0f vs %.0f" % [m.elapsed,eco,count_units(m,0),count_units(m,1),min_gate_hp(m,0),min_gate_hp(m,1)])
			if not m.is_conveyor(0) and m.ink[0] >= 40.0:
				var why: Array = []
				for k: int in [0,1,2,3,Battle.FARM_SLOT]: why.append("%s:%s cd%.1f" % [m.kind_at(0,k),m.play_error(0,k,cell_pos(Vector2i(0,lane))).left(12),m.slot_cd(0,k)])
				note("    stuck hand "+" | ".join(why)+" step %d" % coach.step)
		if coach.step != step_seen:
			step_seen = coach.step
			step_at = frame
			set_ff(false)
			if coach.step < coach.steps.size(): note("%s step %d: %s" % [d.code,coach.step,String(coach.steps[coach.step].text).left(24)])
		var reading := false
		if coach.started and coach.step < coach.steps.size():
			var sid := String(d.id)
			if m.is_conveyor(0):
				reading = coach.step == 0 and frame-step_at < int(2.5*FPS)
			elif sid in ["w1_6","w1_7","w1_8","w1_9"]:
				var max_r := minf(read_time(String(coach.steps[coach.step].text)), 2.8)
				reading = coach.step <= 2 and not enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*5.0) and frame-step_at < int(max_r*FPS)
			else:
				var danger: bool = not sid in ["w1_1","w1_2"] and enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*2.5)
				reading = not danger and frame-step_at < int(read_time(String(coach.steps[coach.step].text))*FPS)
		if not coach.started or reading:
			await idle_look(d,m,coach)
			continue
		var plan := decide(d,m,coach)
		if plan.is_empty():
			var quiet: bool = frame-acted_at > int(2.5*FPS) and m.elapsed > coach.callout_until and frame-step_at > int(4.0*FPS)
			set_ff(quiet)
			await idle_look(d,m,coach)
			continue
		set_ff(false)
		if plan.has("select"):
			var slot := -1
			for k: int in [0,1,2,3]:
				if m.kind_at(0,k) == "militia": slot = k
			if slot >= 0: await click_at(game.card_rect(slot).get_center()+Vector2(0,-10),0.25)
		elif plan.has("skill"):
			await click_at(game.SKILL_RECT.get_center(),0.15)
			note("  cast 破陣斬 (charge %.0f)" % m.skill_charge[0])
		else:
			await play(m,plan)
		acted_at = frame
		if m.is_conveyor(0):
			await wait(0.22+rng.randf()*0.22 if Conveyor.count(m) >= 5 else 0.38+rng.randf()*0.28)
		else:
			await wait(0.45+rng.randf()*0.35)
	note("%s %s in %.1f s battle time (%.1f s on film)" % [d.code,"WON" if m.winner == 0 else "LOST",m.elapsed,(frame-lesson_start)/FPS])

# While reading or waiting, rest the cursor on whatever the step points at.
func idle_look(_d: Dictionary, m, coach) -> void:
	var target := REST
	if coach.started and coach.step < coach.steps.size():
		var hint := String(coach.steps[coach.step].get("hint",""))
		var head := hint.get_slice("+",0).get_slice(":",0)
		match head:
			"purse": target = Hud.PURSE_PLATE.get_center()+Vector2(40,10)
			"next": target = game.NEXT_RECT.get_center()+Vector2(10,20)
			"clock", "sundial": target = Hud.DIAL+Vector2(36,36)
			"walls": target = Vector2(210,86)
			"skill": target = game.SKILL_RECT.get_center()+Vector2(0,-10)
			"lord":
				if m.lords[0].hp > 0: target = screen(m.lords[0].pos)+Vector2(20,20)
			"card":
				var kind := hint.get_slice("+",0).get_slice(":",1)
				var slots: Array = range(Conveyor.count(m)) if m.is_conveyor(0) else [0,1,2,3,Battle.FARM_SLOT]
				for slot: int in slots:
					if m.kind_at(0,slot) == kind: target = game.card_rect(slot).get_center()+Vector2(8,-30)
			"home": target = game.card_rect(Battle.FARM_SLOT).get_center()+Vector2(8,-30)
			"our_farm":
				for b: Dictionary in m.buildings:
					if b.team == 0 and b.kind == "farm" and b.hp > 0: target = screen(b.pos)+Vector2(14,26)
			"enemy_wall", "enemy_units", "enemy_building", "front_cells", "own_cells":
				target = REST
	if cursor.distance_to(target) > 30.0: await move_to(target,0.7)
	else: await wait(0.25)

func screen(field_pos: Vector2) -> Vector2:
	return game.cinematic.field_transform(game)*field_pos

static func cell_pos(cell: Vector2i) -> Vector2:
	return L.GRID_ORIGIN+(Vector2(cell)+Vector2(0.5,0.55))*L.CELL_SIZE

func find_conveyor_slot(m, card_id: int) -> int:
	if not m.is_conveyor(0) or card_id < 0: return -1
	var cards: Array = m.conveyor.get("cards",[])
	for i: int in range(cards.size()):
		if int(cards[i].get("id",-1)) == card_id: return i
	return -1

# Select the card in the hand (tracking sliding conveyor cards), then click the spot on the field.
func play(m, plan: Dictionary) -> void:
	var slot: int = int(plan.slot)
	var cid: int = int(plan.get("card_id",-1))
	if m.is_conveyor(0) and cid >= 0:
		slot = find_conveyor_slot(m,cid)
		if slot < 0: return
	if game.selected != slot: # clicking an already selected card would put it back
		await move_to(game.card_rect(slot).get_center()+Vector2(0,-10))
		if m.is_conveyor(0) and cid >= 0:
			slot = find_conveyor_slot(m,cid)
			if slot < 0: return
			var live_pt: Vector2 = game.card_rect(slot).get_center()+Vector2(0,-10)
			if cursor.distance_to(live_pt) > 10.0: await move_to(live_pt,0.12)
		await wait(0.1)
		await click()
		if m.is_conveyor(0) and cid >= 0:
			slot = find_conveyor_slot(m,cid)
			if slot < 0: return
		if game.selected != slot:
			if game.selected >= 0: await click(true)
			return
		await wait(0.16)
	var pos: Vector2 = plan.pos
	await move_to(screen(pos),-1.0)
	await wait(0.1)
	if m.is_conveyor(0) and cid >= 0:
		var live_slot := find_conveyor_slot(m,cid)
		if live_slot >= 0: slot = live_slot
	if not m.play_error(0,slot,pos).is_empty():
		var again := decide_slot(m,slot,String(plan.why))
		if again.is_empty():
			await click(true) # changed our mind: put the card back
			return
		pos = again.pos
		await move_to(screen(pos),0.25)
	await click()
	note("  play %s %s (%s)" % [String(plan.kind),str(m.cell_at(pos)),String(plan.why)])

# ---------------------------------------------------------------- what to play
func ready(m, slot: int) -> bool:
	var kind: String = m.kind_at(0,slot)
	if kind.is_empty() or not B.CARDS.has(kind): return false
	if m.is_conveyor(0): return true
	return m.slot_cd(0,slot) <= 0.0001 and m.ink[0] >= float(B.CARDS[kind].cost)

func hand_slots(m) -> Array:
	return range(Conveyor.count(m)) if m.is_conveyor(0) else [0,1,2,3,Battle.FARM_SLOT]

func slot_of(m, kind: String) -> int:
	for slot: int in hand_slots(m):
		if m.kind_at(0,slot) == kind and ready(m,slot): return slot
	return -1

func count_units(m, team: int, kind: String = "") -> int:
	var n := 0
	for u: Dictionary in m.units:
		if u.team == team and u.hp > 0 and (kind.is_empty() or u.kind == kind): n += 1
	return n

func enemy_near(m, max_x: float) -> bool:
	for u: Dictionary in m.units:
		if u.team == 1 and u.hp > 0 and u.pos.x < max_x: return true
	return false

func attach_meta(m, plan: Dictionary) -> Dictionary:
	if plan.is_empty(): return plan
	if m.is_conveyor(0):
		var cards: Array = m.conveyor.get("cards",[])
		var s: int = int(plan.slot)
		if s >= 0 and s < cards.size(): plan["card_id"] = int(cards[s].get("id",-1))
	return plan

func breached_lane(m) -> int:
	for lane: int in m.active_lanes:
		if float(m.gates[1][lane]) <= 0.0: return lane
	return -1

func best_rain_near(m) -> Dictionary:
	var close := best_rain_pos(m,2)
	if not close.is_empty() and float(close.pos.x) < L.GRID_ORIGIN.x+L.CELL_SIZE.x*5.2:
		return close
	return best_rain_pos(m,3)

func lane_threat(m, lane: int) -> float:
	var best := 0.0
	var close_foe := false
	for u: Dictionary in m.units:
		if u.team == 1 and u.hp > 0 and int(u.lane) == lane and u.get("spawn_delay",0.0) <= 0.0:
			var dist := clampf((L.GRID_ORIGIN.x+L.GRID_SIZE.x-float(u.pos.x))/L.GRID_SIZE.x,0.05,1.2)
			best += dist*dist*(3.0 if String(u.kind) == "ram" else 1.0)
			if float(u.pos.x) < L.GRID_ORIGIN.x+L.CELL_SIZE.x*5.5: close_foe = true
	var allies := 0
	for u: Dictionary in m.units:
		if u.team == 0 and u.hp > 0 and int(u.lane) == lane and u.get("spawn_delay",0.0) <= 0.0:
			allies += 1
	if close_foe and allies == 0: best += 0.8
	elif allies > 0: best = maxf(0.0, best - minf(0.4, float(allies)*0.08))
	if float(m.gates[0][lane]) < 900.0: best += 0.35
	return best

func threatened_lanes(m) -> Array:
	var lanes: Array = m.active_lanes.duplicate()
	lanes.sort_custom(func(a: int, b: int) -> bool:
		var ta := lane_threat(m,a)
		var tb := lane_threat(m,b)
		if absf(ta-tb) > 0.01: return ta > tb
		return a == 2
	)
	return lanes

func push_lanes(m) -> Array:
	var lanes: Array = m.active_lanes.duplicate()
	var wind_l: Array = []
	for wl: int in m.wind_lanes:
		if int(m.wind_dir.get(wl,1)) == 1: wind_l.append(wl)
	lanes.sort_custom(func(a: int, b: int) -> bool:
		var ga := float(m.gates[1][a])
		var gb := float(m.gates[1][b])
		var sa := ga-(300.0 if a in wind_l else 0.0)
		var sb := gb-(300.0 if b in wind_l else 0.0)
		if absf(sa-sb) > 1.0: return sa < sb
		return a == 2
	)
	return lanes

func best_rain_pos(m, min_hits: int = 2) -> Dictionary:
	var enemies: Array = []
	for u: Dictionary in m.units:
		if u.team == 1 and u.hp > 0 and u.get("spawn_delay",0.0) <= 0.0: enemies.append(u)
	if enemies.is_empty(): return {}
	var rx := L.CELL_SIZE.x*1.05
	var ry := L.CELL_SIZE.y*1.55
	var best_pos := Vector2.ZERO
	var best_score := 0.0
	var best_hits := 0
	for u: Dictionary in enemies:
		var p: Vector2 = u.pos+Vector2(-24.0,0.0)
		if not Rect2(L.GRID_ORIGIN,L.GRID_SIZE).has_point(p): p = u.pos
		var hits := 0
		var score := 0.0
		for v: Dictionary in enemies:
			if absf(float(v.pos.x)-p.x) <= rx and absf(float(v.pos.y)-p.y) <= ry:
				hits += 1
				score += 2.0 if float(v.pos.x) < L.GRID_ORIGIN.x+L.CELL_SIZE.x*4.5 else 1.0
		if m.lord_active[1] and float(m.lords[1].hp) > 0.0:
			var lp: Vector2 = m.lords[1].pos
			if absf(lp.x-p.x) <= rx and absf(lp.y-p.y) <= ry:
				hits += 1
				score += 1.5
		if hits >= min_hits and score > best_score:
			best_score = score
			best_hits = hits
			best_pos = p
	if best_hits >= min_hits: return {"pos":best_pos,"hits":best_hits}
	return {}

func best_fire_pos(m, prefer_kind: String = "", allow_farm: bool = false) -> Vector2:
	var targets: Array = m.buildings.filter(func(b: Dictionary) -> bool:
		if b.team != 1 or b.hp <= 0: return false
		if not prefer_kind.is_empty(): return String(b.kind) == prefer_kind
		return allow_farm or not B.is_economy_building(String(b.kind))
	)
	if targets.is_empty(): return Vector2.ZERO
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ea := 1 if B.is_economy_building(String(a.kind)) else 0
		var eb := 1 if B.is_economy_building(String(b.kind)) else 0
		if ea != eb: return ea < eb
		return float(a.pos.x) < float(b.pos.x)
	)
	return targets[0].pos

func should_cast_skill(m) -> bool:
	if not m.skill_error(0).is_empty(): return false
	if not m.lord_active[0] or float(m.lords[0].hp) <= 0.0: return false
	var lp: Vector2 = m.lords[0].pos
	var max_dx := L.CELL_SIZE.x*4.8
	var max_dy := L.CELL_SIZE.y*1.6
	var hits := 0
	for u: Dictionary in m.units:
		if u.team != 1 or u.hp <= 0 or u.get("spawn_delay",0.0) > 0.0: continue
		var dx := float(u.pos.x)-lp.x
		var dy := absf(float(u.pos.y)-lp.y)
		if dx >= -24.0 and dx <= max_dx and dy <= max_dy:
			if String(u.kind) == "ram": return true
			hits += 1
	if m.lord_active[1] and float(m.lords[1].hp) > 0.0:
		var dx_l := float(m.lords[1].pos.x)-lp.x
		var dy_l := absf(float(m.lords[1].pos.y)-lp.y)
		if dx_l >= -24.0 and dx_l <= max_dx and dy_l <= max_dy: return true
	return hits >= 2

func place_in_lane(m, slot: int, lane: int, front: bool, why: String, allow_refresh: bool = false) -> Dictionary:
	var kind: String = m.kind_at(0,slot)
	if kind.is_empty() or not B.CARDS.has(kind): return {}
	var card: Dictionary = B.CARDS[kind]
	var cols: Array = range(L.GRID_COLUMNS-1,-1,-1) if front else range(L.GRID_COLUMNS)
	for col: int in cols:
		var cell := Vector2i(col,lane)
		if card.type == "building":
			var here: Dictionary = m.building_at(cell)
			if not here.is_empty():
				if not allow_refresh or int(here.team) != 0 or String(here.kind) != kind or float(here.hp) >= float(here.max_hp)*0.45:
					continue
		var pos := cell_pos(cell)
		if m.play_error(0,slot,pos).is_empty():
			return attach_meta(m,{"slot":slot,"pos":pos,"kind":kind,"why":why})
	return {}

func has_building(m, kind: String, lane: int = -1) -> bool:
	for b: Dictionary in m.buildings:
		if b.team == 0 and b.hp > 0 and String(b.kind) == kind and (lane < 0 or int(b.cell.y) == lane):
			return true
	return false

# Where this slot's card goes, by purpose. Returns {} if nowhere fits.
func decide_slot(m, slot: int, why: String) -> Dictionary:
	var kind: String = m.kind_at(0,slot)
	if kind.is_empty() or not B.CARDS.has(kind): return {}
	var card: Dictionary = B.CARDS[kind]
	var lanes: Array = threatened_lanes(m) if why in ["guard","defend"] else push_lanes(m)
	var cells: Array[Vector2i] = []
	match why:
		"farm":
			for col: int in range(L.GRID_COLUMNS):
				for lane: int in m.active_lanes: cells.append(Vector2i(col,lane))
		"farmer":
			var farms: Array = m.buildings.filter(func(b: Dictionary) -> bool: return b.team == 0 and b.kind == "farm" and b.hp > 0)
			farms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.cell.x > b.cell.x)
			for b: Dictionary in farms:
				for col: int in range(b.cell.x,-1,-1): cells.append(Vector2i(col,b.cell.y))
		"spell":
			if kind == "rain":
				var r_info := best_rain_pos(m,1)
				if not r_info.is_empty() and m.play_error(0,slot,r_info.pos).is_empty():
					return attach_meta(m,{"slot":slot,"pos":r_info.pos,"kind":kind,"why":why})
			var fpos := best_fire_pos(m,"",true)
			if fpos != Vector2.ZERO and m.play_error(0,slot,fpos).is_empty():
				return attach_meta(m,{"slot":slot,"pos":fpos,"kind":kind,"why":why})
			for lane: int in lanes:
				var gp := cell_pos(Vector2i(L.GRID_COLUMNS-1,lane))
				if m.play_error(0,slot,gp).is_empty(): return attach_meta(m,{"slot":slot,"pos":gp,"kind":kind,"why":why})
			return {}
		"guard", "defend": # troops that hold: form up behind threats on the threatened lane
			for lane: int in lanes:
				for col: int in range(L.GRID_COLUMNS): cells.append(Vector2i(col,lane))
		_: # troops and buildings: the front edge of our land
			for lane: int in lanes:
				for col: int in range(L.GRID_COLUMNS-1,-1,-1): cells.append(Vector2i(col,lane))
	for cell: Vector2i in cells:
		if card.type == "building" and why != "farm" and not m.building_at(cell).is_empty(): continue
		if why == "farm" and not m.building_at(cell).is_empty(): continue
		var pos := cell_pos(cell)
		if m.play_error(0,slot,pos).is_empty(): return attach_meta(m,{"slot":slot,"pos":pos,"kind":kind,"why":why})
	return {}

func want(m, kind: String, why: String) -> Dictionary:
	var slot := slot_of(m,kind)
	if slot < 0: return {}
	return decide_slot(m,slot,why)

func want_in_lane(m, kind: String, lane: int, front: bool, why: String, allow_refresh: bool = false) -> Dictionary:
	var slot := slot_of(m,kind)
	if slot < 0: return {}
	return place_in_lane(m,slot,lane,front,why,allow_refresh)

func want_troop(m, prefer: Array = ["militia","archer"], why: String = "troop") -> Dictionary:
	for kind: String in prefer:
		var p := want(m,kind,why)
		if not p.is_empty(): return p
	return {}

func farmers_needed(m) -> bool:
	return count_units(m,0,"farmer") < m.count_buildings(0,"farm")

func decide(d: Dictionary, m, coach) -> Dictionary:
	var plan := decide_lesson(d,m,coach)
	if m.is_conveyor(0): return plan
	var sid := String(d.id)
	if sid in ["w1_6","w1_7","w1_8"] and coach.step == 0: return {}
	if not plan.is_empty() or sid in ["w1_1","w1_2"]: return plan
	if sid == "w1_4" and coach.step == 0: return plan
	# No troop fits (no troop in hand, or archers with no room for their two cells): build the land out.
	if sid in ["w1_3","w1_4","w1_5"] and m.ink[0] >= 20.0 and want_troop(m).is_empty():
		var b := want(m,"barricade","front")
		if not b.is_empty(): return b
		return want(m,"farm","farm")
	return plan

func decide_lesson(d: Dictionary, m, coach) -> Dictionary:
	var s: int = coach.step
	var sid := String(d.id)
	# Any sensible player answers raiders at the gate in single-lane early lessons.
	if sid in ["w1_2","w1_3","w1_4","w1_5"] and enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*4.5) and count_units(m,1) >= count_units(m,0,"militia")+count_units(m,0,"archer"):
		var guard := want_troop(m,["archer","militia"] if count_units(m,0,"militia") > count_units(m,0,"archer") else ["militia","archer"],"guard")
		if not guard.is_empty(): return guard
	match sid:
		"w1_1":
			if s == 0:
				return {} if game.selected >= 0 else {"select":true}
			return want_troop(m,["militia"])
		"w1_2":
			if s in [0,2]: return {}
			if s == 1: return want(m,"archer","troop")
			if count_units(m,0,"militia") <= count_units(m,0,"archer")+1: return want_troop(m,["militia","archer"])
			return want_troop(m,["archer","militia"])
		"w1_3":
			if s == 0: return want(m,"farm","farm")
			if s == 1: return {}
			if s == 2: return want(m,"farmer","farmer")
			if s == 3: return want(m,"farm","farm")
			return grow_and_push(m)
		"w1_4":
			if s == 0: return {}
			if s <= 2 and Coach.front_col(m) < 4: return want(m,"barricade","front")
			return want_troop(m)
		"w1_5":
			return exam(m)
		"w1_6":
			return lesson_6(m,s)
		"w1_7":
			return lesson_7(m,s)
		"w1_8":
			return lesson_8(m,s)
		"w1_9":
			return lesson_9(m,s)
		"w1_10":
			return conveyor_decide(m)
	return want_troop(m)

# After the farm lesson: troops whenever the road needs them, two or three farms, one farmer at a time.
func grow_and_push(m) -> Dictionary:
	if enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*4.5) or count_units(m,1) > count_units(m,0):
		var t := want_troop(m,["militia","archer"],"guard")
		if not t.is_empty(): return t
	var farms: int = m.count_buildings(0,"farm")
	if farms < 2 or (farms < 3 and m.ink[0] >= 30.0):
		var f := want(m,"farm","farm")
		if not f.is_empty(): return f
	if count_units(m,0,"farmer") == 0 and farms > 0 and m.ink[0] >= 16.0:
		var fa := want(m,"farmer","farmer")
		if not fa.is_empty(): return fa
	if m.ink[0] >= 15.0:
		if count_units(m,0,"militia") <= count_units(m,0,"archer")+1: return want_troop(m,["militia","archer"])
		return want_troop(m,["archer","militia"])
	return {}

# 1-5: a real opponent. Farms and farmers first, fire on whatever building blocks the road, then troops.
func exam(m) -> Dictionary:
	var fire := want(m,"fire","spell")
	if not fire.is_empty(): return fire
	var threat := enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*3.5)
	if threat:
		var t := want_troop(m,["militia","archer"])
		if not t.is_empty(): return t
	if m.count_buildings(0,"farm") < 3 and (m.count_buildings(0,"farm") < 2 or m.ink[0] >= 26.0):
		var f := want(m,"farm","farm")
		if not f.is_empty(): return f
	if farmers_needed(m):
		var fa := want(m,"farmer","farmer")
		if not fa.is_empty(): return fa
	if Coach.front_col(m) < 3 and m.ink[0] >= 12.0:
		var b := want(m,"barricade","front")
		if not b.is_empty(): return b
	if m.ink[0] >= 24.0 or count_units(m,1) > count_units(m,0):
		if count_units(m,0,"militia") <= count_units(m,0,"archer")+1: return want_troop(m,["militia","archer"])
		return want_troop(m,["archer","militia"])
	return {}

# 1-6: tower behind + scarecrow in front in middle lane, then defend 3 lanes for 90s.
func lesson_6(m, step_idx: int) -> Dictionary:
	if step_idx == 0: return {}
	if step_idx == 1:
		var ts := slot_of(m,"tower")
		if ts >= 0:
			for col: int in [1,0]:
				var pos := cell_pos(Vector2i(col,2))
				if m.play_error(0,ts,pos).is_empty(): return {"slot":ts,"pos":pos,"kind":"tower","why":"tower"}
		return {}
	if step_idx == 2:
		return want_in_lane(m,"scarecrow",2,true,"scarecrow")
	# Step 3: maintain middle scarecrow, add a second tower on a flanking lane, answer close threats.
	if not has_building(m,"scarecrow",2):
		var sc := want_in_lane(m,"scarecrow",2,true,"scarecrow")
		if not sc.is_empty(): return sc
	else:
		var ref := want_in_lane(m,"scarecrow",2,true,"scarecrow",true)
		if not ref.is_empty(): return ref
	if m.count_buildings(0,"tower") < 2:
		for tlane: int in threatened_lanes(m):
			if not has_building(m,"tower",tlane):
				var tw := want_in_lane(m,"tower",tlane,false,"tower")
				if not tw.is_empty(): return tw
	var top_lane: int = threatened_lanes(m)[0]
	if lane_threat(m,top_lane) > 0.25:
		for k: String in ["militia","archer"]:
			var tr := want_in_lane(m,k,top_lane,false,"guard")
			if not tr.is_empty(): return tr
	if m.ink[0] >= 36.0:
		return want_troop(m,["archer","militia"],"guard")
	return {}

# 1-7: burn enemy granary with fire, rain down on approaching waves, hold 2-3 farms, then crush one lane.
func lesson_7(m, step_idx: int) -> Dictionary:
	if step_idx == 0: return {}
	if step_idx == 1:
		var fs := slot_of(m,"fire")
		var gp := best_fire_pos(m,"granary",false)
		if fs >= 0 and gp != Vector2.ZERO and m.play_error(0,fs,gp).is_empty():
			return {"slot":fs,"pos":gp,"kind":"fire","why":"spell"}
		return {}
	if step_idx == 2:
		var rs := slot_of(m,"rain")
		if rs >= 0:
			var best := best_rain_pos(m,3)
			if not best.is_empty() and float(best.pos.x) < L.GRID_ORIGIN.x+L.CELL_SIZE.x*7.5 and m.play_error(0,rs,best.pos).is_empty():
				return {"slot":rs,"pos":best.pos,"kind":"rain","why":"spell"}
		if enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*4.0):
			var dl: int = threatened_lanes(m)[0]
			for k: String in ["militia","archer"]:
				var tr := want_in_lane(m,k,dl,false,"guard")
				if not tr.is_empty(): return tr
		return {}
	# Step 3:
	var bl := breached_lane(m)
	if bl >= 0:
		for k: String in ["militia","archer"]:
			var fin := want_in_lane(m,k,bl,true,"troop")
			if not fin.is_empty(): return fin
	var r_slot := slot_of(m,"rain")
	if r_slot >= 0:
		var r_best := best_rain_near(m)
		if not r_best.is_empty() and m.play_error(0,r_slot,r_best.pos).is_empty():
			return {"slot":r_slot,"pos":r_best.pos,"kind":"rain","why":"spell"}
	var top_lane: int = threatened_lanes(m)[0]
	if lane_threat(m,top_lane) > 0.30:
		for k: String in ["militia","archer"]:
			var tr := want_in_lane(m,k,top_lane,false,"guard")
			if not tr.is_empty(): return tr
	if m.count_buildings(0,"farm") < 3 and m.ink[0] >= 12.0 and not enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*4.2):
		var fm := want(m,"farm","farm")
		if not fm.is_empty(): return fm
	if m.ink[0] >= 36.0 and not enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*4.5):
		var f_slot := slot_of(m,"fire")
		if f_slot >= 0:
			var fpos := best_fire_pos(m,"",false)
			if fpos != Vector2.ZERO and m.play_error(0,f_slot,fpos).is_empty():
				return {"slot":f_slot,"pos":fpos,"kind":"fire","why":"spell"}
	var push_l: int = push_lanes(m)[0]
	var order: Array = ["militia","archer"] if count_units(m,0,"militia") <= count_units(m,0,"archer")+1 else ["archer","militia"]
	for k: String in order:
		var tp := want_in_lane(m,k,push_l,true,"troop")
		if not tp.is_empty(): return tp
	return want_troop(m,order)

# 1-8: cycle until multi-lane hunter arrives, defend all 3 lanes with Lord & rain, exploit breach immediately.
func lesson_8(m, step_idx: int) -> Dictionary:
	if step_idx == 0: return {}
	if step_idx == 1:
		var h := want_in_lane(m,"hunter",2,false,"troop")
		if not h.is_empty(): return h
		var r1 := slot_of(m,"rain")
		if r1 >= 0:
			var rb1 := best_rain_pos(m,2)
			if not rb1.is_empty() and m.play_error(0,r1,rb1.pos).is_empty():
				return {"slot":r1,"pos":rb1.pos,"kind":"rain","why":"spell"}
		var tl1: int = threatened_lanes(m)[0]
		for k: String in ["militia","archer","farmer"]:
			var cyc := want_in_lane(m,k,tl1,false,"guard")
			if not cyc.is_empty(): return cyc
		return {}
	if step_idx == 2:
		if should_cast_skill(m): return {"skill":true}
		if enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*2.5):
			return want_troop(m,["militia","hunter","archer"],"guard")
		return {}
	if should_cast_skill(m): return {"skill":true}
	var bl := breached_lane(m)
	if bl >= 0:
		for k: String in ["militia","hunter","archer"]:
			var fin := want_in_lane(m,k,bl,true,"troop")
			if not fin.is_empty(): return fin
	var r_slot := slot_of(m,"rain")
	if r_slot >= 0:
		var r_best := best_rain_near(m)
		if not r_best.is_empty() and m.play_error(0,r_slot,r_best.pos).is_empty():
			return {"slot":r_slot,"pos":r_best.pos,"kind":"rain","why":"spell"}
	var top_lane: int = threatened_lanes(m)[0]
	if lane_threat(m,top_lane) > 0.30:
		for k: String in ["militia","hunter","archer"]:
			var tr := want_in_lane(m,k,top_lane,false,"guard")
			if not tr.is_empty(): return tr
	if m.count_buildings(0,"farm") < 3 and m.ink[0] >= 20.0 and not enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*4.2):
		var fm := want(m,"farm","farm")
		if not fm.is_empty(): return fm
	if farmers_needed(m) and m.ink[0] >= 20.0 and not enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*4.2):
		var fa := want(m,"farmer","farmer")
		if not fa.is_empty(): return fa
	var push_l: int = push_lanes(m)[0]
	for k: String in ["hunter","militia","archer"]:
		var tr := want_in_lane(m,k,push_l,true,"troop")
		if not tr.is_empty(): return tr
	return want_troop(m,["hunter","militia","archer"])

# 1-9: charge lord skill (from step 0!), cleave incoming rams with 破陣斬, push high-ground lane 1.
func lesson_9(m, step_idx: int) -> Dictionary:
	if step_idx == 0:
		var top0: int = threatened_lanes(m)[0]
		if lane_threat(m,top0) > 0.25:
			for k: String in ["militia","hunter","archer"]:
				var tr0 := want_in_lane(m,k,top0,false,"guard")
				if not tr0.is_empty(): return tr0
		for k: String in ["hunter","militia","archer","farm"]:
			var act := want(m,k,"farm" if k == "farm" else "troop")
			if not act.is_empty(): return act
		return {}
	if step_idx == 1:
		if should_cast_skill(m):
			var lp1: Vector2 = m.lords[0].pos
			for u: Dictionary in m.units:
				if u.team == 1 and u.hp > 0 and String(u.kind) == "ram" and float(u.pos.x) - lp1.x <= L.CELL_SIZE.x*4.8 and absf(float(u.pos.y) - lp1.y) <= L.CELL_SIZE.y*1.6:
					return {"skill":true}
			if enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*3.0):
				return {"skill":true}
		if lane_threat(m,threatened_lanes(m)[0]) > 0.45:
			for k: String in ["militia","hunter","archer"]:
				var tr1 := want_in_lane(m,k,threatened_lanes(m)[0],false,"guard")
				if not tr1.is_empty(): return tr1
		return {}
	if should_cast_skill(m):
		return {"skill":true}
	var bl := breached_lane(m)
	if bl >= 0:
		for k: String in ["militia","hunter","archer"]:
			var fin := want_in_lane(m,k,bl,true,"troop")
			if not fin.is_empty(): return fin
	var r_slot := slot_of(m,"rain")
	if r_slot >= 0:
		var r_best := best_rain_near(m)
		if not r_best.is_empty() and m.play_error(0,r_slot,r_best.pos).is_empty():
			return {"slot":r_slot,"pos":r_best.pos,"kind":"rain","why":"spell"}
	var top_lane: int = threatened_lanes(m)[0]
	if lane_threat(m,top_lane) > 0.30:
		for k: String in ["militia","hunter","archer"]:
			var tr := want_in_lane(m,k,top_lane,false,"guard")
			if not tr.is_empty(): return tr
	if m.count_buildings(0,"farm") < 2 and m.ink[0] >= 22.0 and not enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*4.2):
		var fm := want(m,"farm","farm")
		if not fm.is_empty(): return fm
	if farmers_needed(m) and m.ink[0] >= 22.0 and not enemy_near(m,L.GRID_ORIGIN.x+L.CELL_SIZE.x*4.2):
		var fa := want(m,"farmer","farmer")
		if not fa.is_empty(): return fa
	for k: String in ["hunter","militia","archer"]:
		var tr := want_in_lane(m,k,1,true,"troop")
		if not tr.is_empty(): return tr
	return want_troop(m,["hunter","militia","archer"])

# 1-10: free conveyor belt + Q skill against Harvest Lord across 5 lanes.
func conveyor_slot_of(m, kind: String) -> int:
	var cards: Array = m.conveyor.get("cards",[])
	var fallback := -1
	for i: int in range(cards.size()):
		if String(cards[i].get("kind","")) != kind: continue
		var target_x: float = Conveyor.BELT_LEFT + float(i) * Conveyor.CARD_STEP
		if absf(float(cards[i].get("x",target_x)) - target_x) <= 22.0: return i
		if fallback < 0: fallback = i
	if cards.size() >= 6: return fallback
	return -1

func conveyor_decide(m) -> Dictionary:
	if should_cast_skill(m):
		return {"skill":true}
	var cnt := Conveyor.count(m)
	if cnt <= 0: return {}

	# 1. High-value spells
	var fs := conveyor_slot_of(m,"fire")
	if fs >= 0:
		var fpos := best_fire_pos(m,"",cnt >= 5)
		if fpos != Vector2.ZERO and m.play_error(0,fs,fpos).is_empty():
			return attach_meta(m,{"slot":fs,"pos":fpos,"kind":"fire","why":"spell"})
	var rs := conveyor_slot_of(m,"rain")
	if rs >= 0:
		var min_hits := 1 if cnt >= 6 else 2
		var r_best := best_rain_pos(m,min_hits)
		if not r_best.is_empty() and m.play_error(0,rs,r_best.pos).is_empty():
			return attach_meta(m,{"slot":rs,"pos":r_best.pos,"kind":"rain","why":"spell"})

	# 2. Urgent lane defense when enemies cross midfield
	var t_lanes := threatened_lanes(m)
	var urgent: int = t_lanes[0]
	if lane_threat(m,urgent) > 0.35:
		for k: String in ["militia","mob","hunter","archer","scarecrow","tower","barricade"]:
			var cs := conveyor_slot_of(m,k)
			if cs < 0: continue
			var is_front := k in ["barricade","scarecrow"]
			var p := place_in_lane(m,cs,urgent,is_front,"defend",true)
			if not p.is_empty(): return p

	# 3. Forward expansion, production buildings, and pushing weak/wind lanes
	var p_lanes := push_lanes(m)
	var push_l: int = p_lanes[0]
	var rc := conveyor_slot_of(m,"recruit_camp")
	if rc >= 0:
		for lane: int in p_lanes:
			var p := place_in_lane(m,rc,lane,false,"building",true)
			if not p.is_empty(): return p
	var tw := conveyor_slot_of(m,"tower")
	if tw >= 0:
		for lane: int in t_lanes:
			if not has_building(m,"tower",lane):
				var p := place_in_lane(m,tw,lane,false,"building",true)
				if not p.is_empty(): return p
	var sc := conveyor_slot_of(m,"scarecrow")
	if sc >= 0:
		for lane: int in ([2,1,3] + p_lanes):
			if lane in m.active_lanes:
				var p := place_in_lane(m,sc,lane,true,"front",true)
				if not p.is_empty(): return p
	var br := conveyor_slot_of(m,"barricade")
	if br >= 0:
		for lane: int in p_lanes:
			var p := place_in_lane(m,br,lane,true,"front",true)
			if not p.is_empty(): return p
	var hu := conveyor_slot_of(m,"hunter")
	if hu >= 0:
		for lane: int in ([2,1,3] + p_lanes):
			if lane in m.active_lanes:
				var p := place_in_lane(m,hu,lane,false,"troop")
				if not p.is_empty(): return p
	for k: String in ["mob","militia","archer"]:
		var cs := conveyor_slot_of(m,k)
		if cs < 0: continue
		var p := place_in_lane(m,cs,push_l,true,"troop")
		if not p.is_empty(): return p

	# 4. Prevent belt from stalling when nearly full
	if cnt >= 6:
		for slot: int in range(cnt):
			var kind := Conveyor.kind_at(m,slot)
			if kind.is_empty(): continue
			var fallback_why := "spell" if B.CARDS[kind].type == "spell" else "front"
			var p := decide_slot(m,slot,fallback_why)
			if not p.is_empty(): return p
	return {}
