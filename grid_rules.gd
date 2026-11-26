extends RefCounted
# Grid rules (producer 2026-11-18).
# 1. Building reach is a set of cells per building ("reach" in balance.gd, see below). Troops come first;
#    an enemy building in reach is shot only when no troop is (walls never).
# 2. Multi-lane troop footprints ("footprint":[cols, rows]): every covered cell must be on the field and
#    ours, otherwise the card cannot be played there (no shifting inward or back). Rows span lane..lane+rows-1,
#    centred when the row count is odd; extra columns lie behind the chosen cell.
# Hooks: battle (tower, play_check, deploy), arcane_mechanics, expansion_more, game.draw_preview / hover.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Giant = preload("res://giant_unit.gd")

# ---------------- building reach ----------------
# Each damage building lists its shape in balance.gd as "reach" (producer 2026-11-18), in cells, "ahead"
# meaning toward the enemy wall:
#   {"square":2,"cut_corners":true}  箭樓: 5x5 without its four corner cells (21)
#   {"square":1,"arms":2}            祕法塔: 3x3 plus one more cell up, down, left and right (13)
#   {"ahead":[1,2],"rows":1}         吸血蔓藤: the 2 columns in front, on its lane and the two beside it (6)
#   {"lane":6}                       重弩塔: its own lane, up to 6 cells ahead
# A 箭樓 watched by our 瞭望塔 reaches one cell further.
static func reach_cells(range_px: float) -> int:
	return maxi(0,int(floor(range_px/L.CELL_SIZE.x+0.0001)))

static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori((pos.x-L.GRID_ORIGIN.x)/L.CELL_SIZE.x),floori((pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y))

static func has_reach(kind: String) -> bool:
	return B.CARDS.get(kind,{}).has("reach")

static var _offsets_cache: Dictionary = {}
static var _offsets_set_cache: Dictionary = {}

# Offsets (dx ahead, dy down) a building of this kind covers; bonus widens it by that many cells.
static func offsets(kind: String, bonus: int = 0) -> Array:
	var key := "%s:%d" % [kind,bonus]
	if _offsets_cache.has(key): return _offsets_cache[key]
	var r: Dictionary = B.CARDS[kind].reach
	var out: Array = []
	if r.has("lane"):
		for dx: int in range(0,int(r.lane)+bonus+1): out.append(Vector2i(dx,0))
	elif r.has("ahead"):
		for dx: int in range(int(r.ahead[0]),int(r.ahead[1])+bonus+1):
			for dy: int in range(-int(r.rows),int(r.rows)+1): out.append(Vector2i(dx,dy))
	else:
		var n: int = int(r.square)+bonus
		for dx: int in range(-n,n+1):
			for dy: int in range(-n,n+1):
				if r.get("cut_corners",false) and absi(dx) == n and absi(dy) == n: continue
				out.append(Vector2i(dx,dy))
		var arm: int = int(r.get("arms",0))+(bonus if r.has("arms") else 0)
		for k: int in range(n+1,arm+1):
			for v: Vector2i in [Vector2i(k,0),Vector2i(-k,0),Vector2i(0,k),Vector2i(0,-k)]: out.append(v)
	_offsets_cache[key] = out
	return out

static func offsets_set(kind: String, bonus: int = 0) -> Dictionary:
	var key := "%s:%d" % [kind,bonus]
	if _offsets_set_cache.has(key): return _offsets_set_cache[key]
	var set := {}
	for v: Vector2i in offsets(kind,bonus):
		set[v] = true
	_offsets_set_cache[key] = set
	return set

# A reach shape given inline ({"square":n, "cut_corners":bool}) rather than by a building kind (攻城塔's archers).
static var _shape_cache: Dictionary = {}
static func shape_set(r: Dictionary, bonus: int = 0) -> Dictionary:
	var key := "%s:%d" % [str(r),bonus]
	if _shape_cache.has(key): return _shape_cache[key]
	var n: int = int(r.get("square",1))+bonus
	var set := {}
	for dx: int in range(-n,n+1):
		for dy: int in range(-n,n+1):
			if r.get("cut_corners",false) and absi(dx) == n and absi(dy) == n: continue
			set[Vector2i(dx,dy)] = true
	_shape_cache[key] = set
	return set

static func bonus(m, b: Dictionary) -> int:
	return 1 if not b.is_empty() and String(b.get("kind","")) == "tower" and m != null and b.has("pos") and m.Faction.watched(m,b) else 0

static func covers(m, b: Dictionary, pos: Vector2) -> bool:
	var cell := cell_of(pos)
	var ahead: int = (cell.x-b.cell.x)*(1 if b.team == 0 else -1)
	return offsets_set(b.kind,bonus(m,b)).has(Vector2i(ahead,cell.y-b.cell.y))

# The target a damage building shoots: the nearest troop in reach, else the nearest enemy building in reach.
static func pick(m, b: Dictionary, troops: Array) -> Dictionary:
	var area_set := offsets_set(b.kind,bonus(m,b))
	var fwd := 1 if b.team == 0 else -1
	var b_cell: Vector2i = b.cell
	var b_pos: Vector2 = b.pos
	var found: Dictionary = {}
	var best := INF
	for o: Dictionary in troops:
		if o.hp <= 0 or o.get("stealthed",false) or o.get("phased",false) or o.get("spawn_delay",0.0) > 0: continue
		if not Giant.in_area_set(o,b_cell,fwd,area_set): continue
		var d: float = b_pos.distance_to(o.pos)
		if d < best-0.5 or (absf(d-best) <= 0.5 and int(o.get("serial",0)) > int(found.get("serial",0))):
			best = d
			found = o
	if not found.is_empty(): return found
	for o: Dictionary in m.buildings:
		if o.hp <= 0 or o.team == b.team or B.CARDS.get(o.kind,{}).has("trap"): continue
		if o.kind == "glutton_nest" and o.get("digest_left",0.0) <= 0.0 and o.get("nest_windup",0.0) <= 0.0: continue
		var c: Vector2i = o.cell if o.has("cell") else cell_of(o.pos)
		if not area_set.has(Vector2i((c.x-b_cell.x)*fwd,c.y-b_cell.y)): continue
		var d: float = b_pos.distance_to(o.pos)
		if d < best-0.5 or (absf(d-best) <= 0.5 and int(o.get("serial",0)) > int(found.get("serial",0))):
			best = d
			found = o
	return found

static func nearest_in(m, b: Dictionary, candidates: Array) -> Dictionary:
	var found: Dictionary = {}
	var best := INF
	var area_set := offsets_set(b.kind,bonus(m,b))
	var fwd := 1 if b.team == 0 else -1
	var b_cell: Vector2i = b.cell
	var b_pos: Vector2 = b.pos
	for o: Dictionary in candidates:
		if not Giant.in_area_set(o,b_cell,fwd,area_set): continue
		var d: float = b_pos.distance_to(o.pos)
		if d < best-0.5 or (absf(d-best) <= 0.5 and int(o.get("serial",0)) > int(found.get("serial",0))):
			best = d
			found = o
	return found

# Board cells a building of this kind covers from `cell` (preview and hover).
static func reach_area(m, kind: String, cell: Vector2i, team: int, b: Dictionary = {}) -> Array:
	var fwd := 1 if team == 0 else -1
	var out: Array = []
	for o: Vector2i in offsets(kind,bonus(m,b)):
		var c := Vector2i(cell.x+o.x*fwd,cell.y+o.y)
		if c.x >= 0 and c.x < L.GRID_COLUMNS and c.y >= 0 and c.y < L.GRID_ROWS and (m == null or c.y in m.active_lanes): out.append(c)
	return out

static func lane_length(kind: String) -> int:
	return int(B.CARDS[kind].reach.get("lane",0))

static func reach_text(kind: String) -> String:
	if not has_reach(kind): return ""
	var r: Dictionary = B.CARDS[kind].reach
	var shape := ""
	if r.has("lane"): shape = "本路前方 %d 格" % int(r.lane)
	elif r.has("ahead"): shape = "前方 %d 欄 × %d 路，共 %d 格" % [int(r.ahead[1])-int(r.ahead[0])+1,int(r.rows)*2+1,offsets(kind).size()]
	elif r.has("arms"): shape = "周圍 %d 格再加上下左右各 %d 格，共 %d 格" % [int(r.square),int(r.arms)-int(r.square),offsets(kind).size()]
	else: shape = "周圍 %d 格%s，共 %d 格" % [int(r.square),"（缺四角）" if r.get("cut_corners",false) else "",offsets(kind).size()]
	return "攻擊範圍：%s；沒有敵兵時改打敵方建築（不打城牆）。" % shape

# ---------------- multi-lane footprints ----------------
static func _max_contiguous_lanes(lanes: Array) -> int:
	if lanes.is_empty(): return 0
	var sorted := lanes.duplicate()
	sorted.sort()
	var best := 1
	var cur := 1
	var prev := int(sorted[0])
	for i: int in range(1,sorted.size()):
		var v := int(sorted[i])
		if v == prev: continue
		if v == prev+1:
			cur += 1
			if cur > best: best = cur
		else: cur = 1
		prev = v
	return best

static func footprint(kind: String) -> Vector2i:
	var f: Array = B.CARDS.get(kind,{}).get("footprint",[1,1])
	return Vector2i(int(f[0]),int(f[1]))

static func footprint_cells(kind: String, cell: Vector2i, team: int, active_lanes: Array = []) -> Array:
	var d: Dictionary = B.CARDS.get(kind,{})
	var fm: String = d.get("formation","")
	var back := -1 if team == 0 else 1
	var raw: Array = []
	match fm:
		"t_front":
			raw = [Vector2i(cell.x,cell.y-1),Vector2i(cell.x,cell.y),Vector2i(cell.x,cell.y+1),Vector2i(cell.x+back,cell.y)]
		"t_back":
			raw = [Vector2i(cell.x,cell.y),Vector2i(cell.x+back,cell.y-1),Vector2i(cell.x+back,cell.y),Vector2i(cell.x+back,cell.y+1)]
		"v_wide":
			raw = [Vector2i(cell.x,cell.y),Vector2i(cell.x+back,cell.y-1),Vector2i(cell.x+back,cell.y+1)]
		"u_front":
			raw = [Vector2i(cell.x,cell.y-1),Vector2i(cell.x,cell.y+1),Vector2i(cell.x+back,cell.y)]
		"u_five":
			raw = [Vector2i(cell.x,cell.y-1),Vector2i(cell.x,cell.y),Vector2i(cell.x,cell.y+1),Vector2i(cell.x+back,cell.y-1),Vector2i(cell.x+back,cell.y+1)]
		"v_front":
			raw = [Vector2i(cell.x,cell.y),Vector2i(cell.x,cell.y+1),Vector2i(cell.x+back,cell.y)]
		"wedge":
			raw = [Vector2i(cell.x,cell.y),Vector2i(cell.x+back,cell.y),Vector2i(cell.x+back,cell.y+1)]
		_:
			var f := footprint(kind)
			var top: int = cell.y-(f.y/2 if f.y % 2 == 1 else 0)
			for row: int in range(top,top+f.y):
				for i: int in range(f.x): raw.append(Vector2i(cell.x+back*i,row))
	if not active_lanes.is_empty() and not raw.is_empty():
		var min_y := 999
		var max_y := -999
		for c: Vector2i in raw:
			if c.y < min_y: min_y = c.y
			if c.y > max_y: max_y = c.y
		var span_y := max_y-min_y+1
		if _max_contiguous_lanes(active_lanes) < span_y:
			if d.get("giant",false) or d.get("type","") == "building":
				var target_lane := cell.y if cell.y in active_lanes else int(active_lanes[0])
				if not cell.y in active_lanes and active_lanes.size() > 1:
					var best_dist := 999
					for al in active_lanes:
						var ly := int(al)
						var dist := absi(ly-cell.y)
						if dist < best_dist or (dist == best_dist and ly < target_lane):
							best_dist = dist
							target_lane = ly
				var single_lane: Array = []
				var seen := {}
				for c: Vector2i in raw:
					var mc := Vector2i(c.x,target_lane)
					if not seen.has(mc):
						seen[mc] = true
						single_lane.append(mc)
				return single_lane
			var collapsed: Array = []
			var seen := {}
			for c: Vector2i in raw:
				var best_lane := int(active_lanes[0])
				if active_lanes.size() > 1:
					var best_dist := 999
					for al in active_lanes:
						var ly := int(al)
						var dist := absi(ly-c.y)
						if dist < best_dist or (dist == best_dist and ((c.y > cell.y and ly > best_lane) or (c.y <= cell.y and ly < best_lane))):
							best_dist = dist
							best_lane = ly
				var mc := Vector2i(c.x,best_lane)
				if not seen.has(mc):
					seen[mc] = true
					collapsed.append(mc)
			return collapsed
	return raw

static func footprint_ok(m, team: int, kind: String, cell: Vector2i) -> bool:
	if footprint(kind) == Vector2i(1,1): return true
	for c: Vector2i in footprint_cells(kind,cell,team,m.active_lanes):
		if c.x < 0 or c.x >= L.GRID_COLUMNS or not c.y in m.active_lanes or m.territory_owner(c) != team: return false
	return true

# How deploy() fields a footprint card: [{lane, col, kind, count, offset}] with the totals unchanged.
# A single-kind card (or one whose members all stand together) is shared evenly over every covered cell.
# A mixed legion over two columns puts its front-most members in the chosen column and the rest behind.
static func plan(kind: String, cell: Vector2i, team: int, groups: Array, active_lanes: Array = []) -> Array:
	var d: Dictionary = B.CARDS[kind]
	var f := footprint(kind)
	var cells := footprint_cells(kind,cell,team,active_lanes)
	var front := INF
	var mixed := false
	for g: Array in groups: front = minf(front,float(g[2]))
	for g: Array in groups: mixed = mixed or not is_equal_approx(float(g[2]),front)
	var out: Array = []
	for g: Array in groups:
		var total: int = int(g[1])*(3 if d.get("spread",false) else 1)
		var spots: Array = cells
		if f.x > 1 and mixed:
			var want_front: bool = is_equal_approx(float(g[2]),front)
			spots = cells.filter(func(c: Vector2i) -> bool: return (c.x == cell.x) == want_front)
		for i: int in range(spots.size()):
			var n: int = total/spots.size()+(1 if i < total % spots.size() else 0)
			if n > 0: out.append({"lane":spots[i].y,"col":spots[i].x,"kind":g[0],"count":n,"offset":0.0})
	return out

# Where each squad of a unit card will stand if played on `cell`: [[kind, count, pos], ...]. Uses the same
# rules as battle.deploy(), so the placement preview matches what appears (spawn jitter aside).
static func spawn_preview(m, team: int, kind: String, cell: Vector2i) -> Array:
	var card: Dictionary = B.CARDS[kind]
	var groups: Array = card.get("members",[[kind,card.get("count",1),0.0]]).duplicate(true)
	var GoldMonster = preload("res://gold_monster.gd")
	if GoldMonster.pays_all(kind): GoldMonster.shape(groups,GoldMonster.price(m.ink[team]))
	var swarm: Dictionary = m.lord_mod(team,"swarm",{})
	for g: Array in groups: g[1] += int(swarm.get(g[0],swarm.get("*",0)))
	var forward := 1.0 if team == 0 else -1.0
	var out: Array = []
	var rear := func(col: int, lane: int) -> Vector2: return L.cell_center(Vector2i(col,lane))-Vector2(forward*(L.CELL_SIZE.x*0.5-12.0),0)
	if card.get("giant",false):
		var spec: Dictionary = Giant.deploy_spec(m,team,kind,cell)
		return [[kind,1,spec.pos]]
	if footprint(kind) != Vector2i(1,1):
		for p: Dictionary in plan(kind,cell,team,groups,m.active_lanes): out.append([p.kind,p.count,rear.call(p.col,p.lane)])
		return out
	var front_offset := 0.0
	for g: Array in groups: front_offset = minf(front_offset,float(g[2]))
	var col: int = m.deployment_column(team,cell.y,cell.x)
	if col < 0: return out
	for g: Array in groups: out.append([g[0],int(g[1]),rear.call(col,cell.y)-Vector2(forward*(float(g[2])-front_offset),0)])
	return out

static func footprint_text(kind: String) -> String:
	if B.CARDS.get(kind,{}).get("giant",false):
		return "佔 2×2 格單體巨獸（2 欄 × 2 路）；每一格都必須是我方領地才能放，並視為在所佔每一格打出。橫跨相鄰兩路行軍，兩路敵軍、防禦塔與法術皆可命中，近戰橫掃兩路敵軍與建築，攻城時同時攻擊兩扇城門。"
	var fm: String = B.CARDS.get(kind,{}).get("formation","")
	match fm:
		"t_front": return "佔 1+1×3 格（T字陣：後排中路 1 格＋前排三路 3 格，共 4 格）；每一格都必須是我方領地才能放，並視為在所佔每一格打出。"
		"t_back": return "佔 1×3+1 格（倒T陣：前排中路 1 格＋後排三路 3 格，共 4 格）；每一格都必須是我方領地才能放，並視為在所佔每一格打出。"
		"v_wide": return "佔 1+2 格（雁形陣：前排中路 1 格＋後排上下兩翼 2 格，共 3 格）；每一格都必須是我方領地才能放，並視為在所佔每一格打出。"
		"u_front": return "佔 1+2 格（鶴翼陣：後排中路 1 格＋前排上下兩翼 2 格，共 3 格）；每一格都必須是我方領地才能放，並視為在所佔每一格打出。"
		"u_five": return "佔 2+1×3 格（雁群陣：後排上下兩翼 2 格＋前排三路 3 格，共 5 格）；每一格都必須是我方領地才能放，並視為在所佔每一格打出。"
		"v_front": return "佔 1+1×2 格（三角前鋒陣：後排 1 格＋前排雙路 2 格，共 3 格）；每一格都必須是我方領地才能放，並視為在所佔每一格打出。"
		"wedge": return "佔 1+2 格（楔形陣：前排 1 格＋後排雙路 2 格，共 3 格）；每一格都必須是我方領地才能放，並視為在所佔每一格打出。"
	var f := footprint(kind)
	if f == Vector2i(1,1): return ""
	return "佔 %d×%d 格（%d 欄 × %d 路）；每一格都必須是我方領地才能放，並視為在所佔每一格打出。" % [f.x,f.y,f.x,f.y]

# Every board cell that playing `kind` at `cell`/`pos` occupies (for multi-cell formations, 1×2 walls, spread troops, and area spells).
static func played_cells(m, team: int, kind: String, cell: Vector2i, pos: Vector2 = Vector2.ZERO) -> Array[Vector2i]:
	var d: Dictionary = B.CARDS.get(kind,{})
	var out: Array[Vector2i] = []
	var seen := {}
	var add_cell := func(c: Vector2i) -> void:
		if not seen.has(c):
			seen[c] = true
			out.append(c)
	var ctype: String = String(d.get("type",""))
	if ctype == "building":
		var LB = preload("res://large_body.gd")
		if LB.is_tall(kind):
			for tc: Vector2i in LB.cells(m,team,kind,cell): add_cell.call(tc)
		else:
			add_cell.call(cell)
		return out
	if ctype == "unit":
		if footprint(kind) != Vector2i(1,1):
			for fc: Vector2i in footprint_cells(kind,cell,team,m.active_lanes): add_cell.call(fc)
		elif d.get("spread",false):
			var middle := clampi(cell.y,1,maxi(1,L.GRID_ROWS-2))
			for lane: int in [middle-1,middle,middle+1]:
				if not lane in m.active_lanes: continue
				var col: int = m.deployment_column(team,lane,cell.x)
				if col >= 0: add_cell.call(Vector2i(col,lane))
		if out.is_empty(): add_cell.call(cell)
		return out
	if d.get("rolling",false):
		for c_x: int in range(L.GRID_COLUMNS): add_cell.call(Vector2i(c_x,cell.y))
		return out
	var p: Vector2 = pos if pos != Vector2.ZERO else L.cell_center(cell)
	var rect: Rect2 = B.spell_rect(p,d)
	for cy: int in m.active_lanes:
		for cx: int in range(L.GRID_COLUMNS):
			var cr := Rect2(L.GRID_ORIGIN+Vector2(cx,cy)*L.CELL_SIZE,L.CELL_SIZE)
			if cr.intersects(rect): add_cell.call(Vector2i(cx,cy))
	if out.is_empty(): add_cell.call(cell)
	return out

static func played_lanes(cells: Array[Vector2i]) -> Array[int]:
	var out: Array[int] = []
	for c: Vector2i in cells:
		if not c.y in out: out.append(c.y)
	out.sort()
	return out

static func is_lane_play_building(kind: String) -> bool:
	var d: Dictionary = B.CARDS.get(kind,{})
	return d.has("play_buff") or d.has("depot_refund")

static func lane_play_color(kind: String) -> Color:
	match kind:
		"field_smithy": return Color("c4a75f")
		"war_lodge": return Color("f0ad32")
		"observatory": return Color("5d9cb8")
		"blood_cauldron": return Color("d93848")
		"supply_depot": return Color("e8af30")
	return Color("d2ad58")

static func card_has_ranged_member(kind: String) -> bool:
	var d: Dictionary = B.CARDS.get(kind,{})
	if d.get("projectile",false): return true
	for g: Array in d.get("members",[]):
		if B.CARDS.get(String(g[0]),{}).get("projectile",false): return true
	return false

static func draw_lane_play_reach(g, kind: String, cell: Vector2i, b: Dictionary = {}) -> void:
	var col := lane_play_color(kind)
	var lane_rect := Rect2(L.GRID_ORIGIN.x,L.GRID_ORIGIN.y+float(cell.y)*L.CELL_SIZE.y,L.GRID_SIZE.x,L.CELL_SIZE.y)
	g.draw_rect(lane_rect,Color(col,0.14))
	g.draw_rect(lane_rect.grow(-1.5),Color(col,0.78),false,2.2)
	var d: Dictionary = B.CARDS.get(kind,{})
	if d.has("reveal_radius"):
		var center: Vector2 = b.pos if b.has("pos") else L.cell_center(cell)
		var rr: float = float(d.reveal_radius)+(B.actor_radius(b) if not b.is_empty() else B.kind_radius(kind))
		draw_dashed_ring(g,center,rr,Color("38b89c"),0.06,1.8)

static func draw_play_triggers(g, kind: String, cell: Vector2i, team: int) -> void:
	if B.CARDS.get(kind,{}).get("type","") != "unit": return
	var cells := played_cells(g.model,team,kind,cell)
	var lanes := played_lanes(cells)
	var ranged := card_has_ranged_member(kind)
	for b: Dictionary in g.model.buildings:
		if b.hp <= 0 or b.team != team or not b.cell.y in lanes or not is_lane_play_building(b.kind): continue
		if String(B.CARDS.get(b.kind,{}).get("play_buff","")) == "range" and not ranged: continue
		var col := lane_play_color(b.kind)
		g.draw_circle(b.pos,34.0,Color(col,0.18))
		g.draw_arc(b.pos,34.0,0,TAU,32,Color(col,0.92),3.0,true)
		var best_c: Vector2i = cells[0]
		var best_d := INF
		for c: Vector2i in cells:
			if c.y != b.cell.y: continue
			var dist := absf(float(c.x-b.cell.x))
			if dist < best_d:
				best_d = dist
				best_c = c
		var dst: Vector2 = L.cell_center(best_c)
		if dst.distance_to(b.pos) > 8.0:
			g.draw_line(b.pos,dst,Color(col,0.55),2.2,true)

# ---------------- drawing ----------------
static func draw_cells(g, cells: Array, fill: Color, stroke: Color) -> void:
	for c: Vector2i in cells:
		if c.x < 0 or c.x >= L.GRID_COLUMNS or c.y < 0 or c.y >= L.GRID_ROWS: continue
		var r := Rect2(L.GRID_ORIGIN+Vector2(c)*L.CELL_SIZE,L.CELL_SIZE)
		g.draw_rect(r,fill)
		g.draw_rect(r.grow(-1.5),stroke,false,1.6)

static func is_heal_unit_kind(kind: String) -> bool:
	var d: Dictionary = B.CARDS.get(kind,{})
	return kind == "healer" or (d.get("type","") == "unit" and d.get("support","") == "heal")

static func is_heal_building_kind(kind: String) -> bool:
	return kind in ["soul_well","sleepless_belfry","blood_tower"]

static func draw_dashed_ring(g, center: Vector2, r: float, color: Color, fill_alpha: float = 0.08, width: float = 2.0) -> void:
	g.draw_circle(center,r,Color(color,fill_alpha))
	for ai: int in range(48):
		if ai % 2 == 0: g.draw_arc(center,r,ai*TAU/48,(ai+1)*TAU/48,4,Color(color,0.78),width,true)

static func draw_heal_building_reach(g, kind: String, cell: Vector2i, b: Dictionary = {}) -> void:
	if kind == "blood_tower":
		var lane_rect := Rect2(L.GRID_ORIGIN.x,L.GRID_ORIGIN.y+float(cell.y)*L.CELL_SIZE.y,L.GRID_SIZE.x,L.CELL_SIZE.y)
		g.draw_rect(lane_rect,Color("5ce675",0.14))
		g.draw_rect(lane_rect.grow(-1.5),Color("5ce675",0.75),false,2.2)
	elif kind in ["soul_well","sleepless_belfry"]:
		var center: Vector2 = b.pos if b.has("pos") else L.cell_center(cell)
		var r: float = float(B.CARDS[kind].radius)+(B.actor_radius(b) if not b.is_empty() else B.kind_radius(kind))
		var col := Color("dbd5ac") if kind == "sleepless_belfry" else Color("5ce675")
		draw_dashed_ring(g,center,r,col,0.09,2.2)

# Ghosts of the squads where they will actually stand, with their head count.
static func draw_spawn_preview(g, kind: String, cell: Vector2i, team: int) -> void:
	var Up = preload("res://card_upgrades.gd")
	var r_pct: float = Up.stat_pct("range",int(g.model.card_upgrades[team].get(kind,{}).get("range",0)))
	for s: Array in spawn_preview(g.model,team,kind,cell):
		var sk := String(s[0])
		if is_heal_unit_kind(sk):
			var srad := B.kind_radius(sk)
			var hrad: float = g.model.unit_heal_radius({"kind":sk,"team":team,"pos":s[2],"body_radius":srad,"range_pct":r_pct})+srad
			draw_dashed_ring(g,s[2],hrad,Color("5ce675"),0.07,2.0)
		g.draw_actor(sk,team,s[2],1.0 if team == 0 else -1.0,Color(1,1,1,0.55))
		if int(s[1]) > 1: g.field_text(s[2]+Vector2(-14,24),"×%d" % int(s[1]),HORIZONTAL_ALIGNMENT_LEFT,40.0,15,Color(1,0.97,0.86,0.95))

static func draw_reach(g, kind: String, cell: Vector2i, team: int, b: Dictionary = {}) -> void:
	if not has_reach(kind): return
	draw_cells(g,reach_area(g.model,kind,cell,team,b),Color(0.85,0.30,0.08,0.22),Color(0.80,0.25,0.05,0.90))

# Hovering one of our or the enemy's damage/healing buildings or healing troops shows its reach.
static func draw_hover(g, mouse: Vector2) -> void:
	for b: Dictionary in g.model.buildings:
		if b.hp > 0 and b.pos.distance_to(mouse) <= 40.0 and has_reach(b.kind):
			draw_reach(g,b.kind,b.cell,b.team,b)
			return
	for b: Dictionary in g.model.buildings:
		if b.hp > 0 and b.pos.distance_to(mouse) <= 44.0 and is_heal_building_kind(b.kind):
			draw_heal_building_reach(g,b.kind,b.cell,b)
			return
	for b: Dictionary in g.model.buildings:
		if b.hp > 0 and b.pos.distance_to(mouse) <= 44.0 and is_lane_play_building(b.kind):
			draw_lane_play_reach(g,b.kind,b.cell,b)
			return
	for u: Dictionary in g.model.units:
		if u.hp > 0 and u.get("spawn_delay",0.0) <= 0 and is_heal_unit_kind(u.kind):
			var upos: Vector2 = u.get("draw",u.pos)
			if upos.distance_to(mouse) <= 36.0:
				var r: float = g.model.unit_heal_radius(u)+B.actor_radius(u)
				draw_dashed_ring(g,u.pos,r,Color("5ce675"),0.09,2.2)
				return
