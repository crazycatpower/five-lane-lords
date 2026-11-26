extends RefCounted
# 2x2 single-body giant units (使用者 2026-11-23): straddles two adjacent lanes as one unit.
# Occupies u.lanes = [l0, l1], marches along their divider, can be hit from either lane (AoE once),
# sweeps both lanes in melee, and batters both gates simultaneously.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const GluttonNest = preload("res://glutton_nest.gd")
const SERIAL_TIE := 0.5

static func is_giant_kind(kind: String) -> bool:
	return B.CARDS.get(kind,{}).get("giant",false)

static func is_giant(actor: Dictionary) -> bool:
	return actor.get("giant",false)

static func lanes(actor: Dictionary) -> Array:
	if actor.has("lanes"): return actor.lanes
	return [int(actor.get("lane",actor.get("cell",Vector2i(-1,-1)).y))]

# Lanes a three-lane striker (三頭狂蜥) reaches: its own lane(s) plus one on each side. A 2×2 giant
# keeps its top lane in u.lane, so measuring from u.lane alone would reach up but never down.
static func reach_lanes(actor: Dictionary) -> Array[int]:
	var ls := lanes(actor)
	var lo := int(ls[0])
	var hi := int(ls[0])
	for l in ls:
		lo = mini(lo,int(l))
		hi = maxi(hi,int(l))
	var out: Array[int] = []
	for l: int in range(maxi(0,lo-1),mini(L.GRID_ROWS,hi+2)): out.append(l)
	return out

static func occupies_lane(actor: Dictionary, lane: int) -> bool:
	if actor.has("lanes"): return lane in actor.lanes
	return int(actor.get("lane",actor.get("cell",Vector2i(-1,-1)).y)) == lane

static func lanes_overlap(a: Dictionary, b: Dictionary) -> bool:
	var bl := lanes(b)
	for l in lanes(a):
		if l in bl: return true
	return false

static func pair_for_lane(active_lanes: Array, top_lane: int) -> Array:
	if top_lane in active_lanes and (top_lane+1) in active_lanes:
		return [top_lane,top_lane+1]
	if (top_lane-1) in active_lanes and top_lane in active_lanes:
		return [top_lane-1,top_lane]
	var best_pair: Array = []
	var best_dist := 999
	for al in active_lanes:
		var l := int(al)
		if (l+1) in active_lanes and absi(l-top_lane) < best_dist:
			best_dist = absi(l-top_lane)
			best_pair = [l,l+1]
	if not best_pair.is_empty(): return best_pair
	if top_lane in active_lanes: return [top_lane]
	if not active_lanes.is_empty(): return [int(active_lanes[0])]
	return [clampi(top_lane,0,L.GRID_ROWS-1)]

static func center_y(u: Dictionary) -> float:
	var ls := lanes(u)
	return (L.cell_center(Vector2i(0,int(ls[0]))).y+L.cell_center(Vector2i(0,int(ls[ls.size()-1]))).y)*0.5

static func deploy_spec(m, team: int, kind: String, cell: Vector2i) -> Dictionary:
	var GridRules = preload("res://grid_rules.gd")
	var covered: Array = GridRules.footprint_cells(kind,cell,team,m.active_lanes)
	var cols: Array[int] = []
	var ls: Array[int] = []
	for c: Vector2i in covered:
		var cx_i := clampi(c.x,0,L.GRID_COLUMNS-1)
		if not cx_i in cols: cols.append(cx_i)
		if c.y in m.active_lanes and not c.y in ls: ls.append(c.y)
	cols.sort()
	ls.sort()
	if ls.is_empty():
		for gl in pair_for_lane(m.active_lanes,cell.y): ls.append(int(gl))
	if cols.is_empty(): cols.append(clampi(cell.x,0,L.GRID_COLUMNS-1))
	var cx: float = (L.cell_center(Vector2i(cols[0],0)).x+L.cell_center(Vector2i(cols[cols.size()-1],0)).x)*0.5
	cx = clampf(cx,L.GRID_ORIGIN.x+12.0,L.GRID_ORIGIN.x+L.GRID_SIZE.x-12.0)
	var cy: float = (L.cell_center(Vector2i(0,ls[0])).y+L.cell_center(Vector2i(0,ls[ls.size()-1])).y)*0.5
	return {"pos":Vector2(cx,cy),"lanes":ls}

static func cells(actor: Dictionary) -> Array[Vector2i]:
	if not is_giant(actor): return [B.actor_grid_cell(actor)]
	var r: float = B.actor_radius(actor)
	var c0 := clampi(floori((actor.pos.x-r-L.GRID_ORIGIN.x)/L.CELL_SIZE.x),0,L.GRID_COLUMNS-1)
	var c1 := clampi(floori((actor.pos.x+r-L.GRID_ORIGIN.x)/L.CELL_SIZE.x),0,L.GRID_COLUMNS-1)
	var out: Array[Vector2i] = []
	for l in lanes(actor):
		for col: int in range(c0,c1+1):
			out.append(Vector2i(col,int(l)))
	return out

static func in_area_set(actor: Dictionary, b_cell: Vector2i, fwd: int, area_set: Dictionary) -> bool:
	if not is_giant(actor):
		var c := Vector2i(floori((actor.pos.x-L.GRID_ORIGIN.x)/L.CELL_SIZE.x),floori((actor.pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y))
		return area_set.has(Vector2i((c.x-b_cell.x)*fwd,c.y-b_cell.y))
	for c: Vector2i in cells(actor):
		if area_set.has(Vector2i((c.x-b_cell.x)*fwd,c.y-b_cell.y)): return true
	return false

static func standing_gates(m, enemy: int, u: Dictionary) -> Array:
	var out: Array = []
	for l in lanes(u):
		var li := int(l)
		if li in m.active_lanes and m.gates[enemy][li] > 0: out.append(li)
	return out

static func at_gate(m, u: Dictionary, enemy: int) -> bool:
	var forward := 1.0 if u.team == 0 else -1.0
	return not standing_gates(m,enemy,u).is_empty() and absf(u.pos.x-(L.gate_stop(enemy)-forward*B.actor_radius(u))) <= 4.0

static func nearest_in_lanes(m, u: Dictionary, max_range: float, lane_lists: Array, can_hit_flying: bool, min_dx: float) -> Dictionary:
	var sr: float = float(u.body_radius) if u.has("body_radius") else B.actor_radius(u)
	var found: Dictionary = {}
	var best := INF
	var seen := {}
	for l in lanes(u):
		var li := int(l)
		if li < 0 or li >= lane_lists.size(): continue
		for other: Dictionary in lane_lists[li]:
			var oid := int(other.get("id",-1))
			if oid >= 0:
				if seen.has(oid): continue
				seen[oid] = true
			if other.team == u.team or other.hp <= 0 or other.get("stealthed",false) or GluttonNest.hidden(other): continue
			if not can_hit_flying and other.get("flying",false): continue
			if (other.pos.x-u.pos.x)*u.face < min_dx: continue
			var d: float = maxf(0.0,absf(other.pos.x-u.pos.x)-sr-B.actor_radius(other))
			if d > max_range: continue
			if found.is_empty() or d < best-SERIAL_TIE or (d <= best+SERIAL_TIE and other.get("serial",-1) > found.get("serial",-1)):
				found = other
				best = minf(best,d) if absf(d-best) <= SERIAL_TIE else d
	return found

static func nearest_lord_in_lanes(m, u: Dictionary, max_range: float) -> Dictionary:
	var sr: float = float(u.body_radius) if u.has("body_radius") else B.actor_radius(u)
	var u_lanes := lanes(u)
	var reach: float = maxf(54.0,max_range)
	for other: Dictionary in m.lords:
		if other.team == u.team or other.hp <= 0 or not m.lord_active[other.team]: continue
		if not m.lord_lane(other) in u_lanes: continue
		if (other.pos.x-u.pos.x)*u.face < -sr: continue
		var d: float = maxf(0.0,absf(other.pos.x-u.pos.x)-sr-B.actor_radius(other))
		if d <= reach: return other
	return {}

static func sweep_attack(m, u: Dictionary, target: Dictionary, amount: float) -> void:
	var x: float = target.pos.x
	var u_lanes := lanes(u)
	var half_x: float = L.CELL_SIZE.x*0.65
	var rams_only: bool = B.CARDS.get(u.kind,{}).get("hits","") == "buildings" # 攻城塔's ram never sweeps troops
	for other: Dictionary in ([] if rams_only else m.foe_units[u.team]):
		if other.hp <= 0 or is_same(other,target) or other.get("stealthed",false) or other.get("flying",false): continue
		if not lanes_overlap(u,other): continue
		if absf(other.pos.x-x) > half_x+B.actor_radius(other): continue
		m.damage(other,amount,u.team,u.get("card",u.kind),u)
	var hit_b := {}
	for l in u_lanes:
		for b: Dictionary in m.lane_foe_buildings[u.team][int(l)]:
			if b.hp <= 0 or is_same(b,target) or GluttonNest.hidden(b) or hit_b.has(b.id): continue
			if absf(b.pos.x-x) > half_x+B.actor_radius(b): continue
			hit_b[b.id] = true
			m.damage(b,amount,u.team,u.get("card",u.kind),u)
	if B.CARDS.get(u.kind,{}).get("breath",false): # 骸骨巨龍 (使用者 2026-11-24): a ranged fire breath across both its lanes
		var dir := 1.0 if u.team == 0 else -1.0
		m.event("dragon_breath",Vector2(x,u.pos.y),u.team,{"lane":u.lane,"from":u.pos+Vector2(dir*(B.actor_radius(u)+10.0),-46.0)})
	else: m.event("slash",Vector2(x,u.pos.y),u.team,{"lane":u.lane,"giant":true})

static func hit_gates(m, u: Dictionary, enemy: int, amount: float) -> void:
	var gs := standing_gates(m,enemy,u)
	for gl in gs:
		m.hit_gate(enemy,int(gl),amount,u.get("card",u.kind),u)
	sweep_attack(m,u,{"pos":Vector2(L.gate_stop(enemy),u.pos.y)},amount)

static func catapult_target(m, b: Dictionary, max_r: float, min_r: float) -> Dictionary:
	var found: Dictionary = {}
	var best := -1.0
	var seen := {}
	for l in lanes(b):
		for target: Dictionary in m.lane_foes[b.team][int(l)]+m.lane_foe_buildings[b.team][int(l)]:
			var tid := int(target.get("id",-1))
			if tid >= 0:
				if seen.has(tid): continue
				seen[tid] = true
			if target.hp <= 0 or target.get("stealthed",false): continue
			if (target.pos.x-b.pos.x)*b.face < 0: continue
			var dist: float = maxf(0.0,absf(target.pos.x-b.pos.x)-B.actor_radius(b)-B.actor_radius(target))
			if dist < min_r or dist > max_r: continue
			if dist > best or (is_equal_approx(dist,best) and target.serial > found.get("serial",0)):
				best = dist
				found = target
	if not found.is_empty(): return found
	var enemy: int = 1-b.team
	var gs := standing_gates(m,enemy,b)
	if gs.is_empty(): return {}
	var gx := L.gate_stop(enemy)
	if (gx-b.pos.x)*b.face < 0: return {}
	var gd: float = maxf(0.0,absf(gx-b.pos.x)-B.actor_radius(b))
	if gd < min_r or gd > max_r: return {}
	var gy: float = center_y(b) if gs.size() >= 2 else L.cell_center(Vector2i(0,int(gs[0]))).y
	return {"kind":"gate","team":enemy,"lane":int(gs[0]),"pos":Vector2(gx,gy),"hp":m.gates[enemy][int(gs[0])],"body_radius":0.0}
