extends RefCounted
# Two-lane buildings (使用者 2026-11-24：「木拒馬改 1*2」). A building card with "footprint":[1,2] stands on
# two cells of one column in neighbouring lanes. It is kept as two linked segments, one per lane, so lane
# targeting, blocking, reach and territory work unchanged; the segments share one health pool:
#  - a hit on one segment is mirrored on the other at once (deaths included), and the same blow landing on
#    both segments in the same instant (a spell, a blast) counts once;
#  - anything else that changes health (repairs, healers, re-placing the card) is merged once per step:
#    losses add up, gains take the larger one.
# Placement needs every covered cell on the field, ours, buildable and free (or the same card, to repair).
# Fields: twin_id (the other segment's id), twin_secondary (the lower-priority one), pair_hp.
# Hooks: battle (play_check, add_building, damage, step), game (draw_preview, building health bar).
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const GridRules = preload("res://grid_rules.gd")

static var _making_twin := false

static func is_tall(kind: String) -> bool:
	var d: Dictionary = B.CARDS.get(kind,{})
	return d.get("type","") == "building" and GridRules.footprint(kind).y >= 2

static func cells(m, team: int, kind: String, cell: Vector2i) -> Array:
	if m != null:
		var at: Dictionary = m.building_at(cell)
		if not at.is_empty() and at.team == team and at.kind == kind:
			var t := twin(m,at)
			if not t.is_empty(): return [at.cell,t.cell] if at.cell.y <= t.cell.y else [t.cell,at.cell]
			return [at.cell]
	var lanes: Array = m.active_lanes if m != null else Array(range(L.GRID_ROWS))
	return GridRules.footprint_cells(kind,cell,team,lanes)

# battle.play_check for a two-lane building (replaces the single-cell checks).
static func refusal(m, team: int, kind: String, cell: Vector2i) -> int:
	var covered := cells(m,team,kind,cell)
	var existing: Array = []
	for c: Vector2i in covered:
		if c.x < 0 or c.x >= L.GRID_COLUMNS or not c.y in m.active_lanes: return m.Refusal.FOOTPRINT
		if m.is_water_cell(c): return m.Refusal.WATER
		if m.is_blocked_cell(c): return m.Refusal.BLOCKED
		if m.territory_owner(c) != team: return m.Refusal.FOOTPRINT if c != cell else m.Refusal.NOT_OURS
		var here: Dictionary = m.building_at(c)
		if not here.is_empty():
			if here.team != team or here.kind != kind: return m.Refusal.OCCUPIED
			existing.append(here)
	if existing.size() > 0 and existing.size() < covered.size(): return m.Refusal.OCCUPIED
	if existing.size() == 2 and int(existing[0].get("twin_id",-1)) != int(existing[1].id): return m.Refusal.OCCUPIED
	return m.Refusal.OK

# battle.add_building: give a fresh two-lane building its second segment. The lane below first (as the
# placement preview shows), else the lane above; a building squeezed against the edge or other buildings
# (opening layouts, decrees) stays a single segment.
static func on_built(m, b: Dictionary) -> void:
	if _making_twin or not is_tall(String(b.kind)): return
	var spot := Vector2i(-1,-1)
	for c: Vector2i in GridRules.footprint_cells(String(b.kind),b.cell,int(b.team),m.active_lanes)+[b.cell+Vector2i(0,-1)]:
		if c == b.cell or not c.y in m.active_lanes or c.x < 0 or c.x >= L.GRID_COLUMNS: continue
		if m.is_no_build_cell(c) or not m.building_at(c).is_empty(): continue
		spot = c
		break
	if spot.y < 0: return
	_making_twin = true
	var t: Dictionary = m.add_building(int(b.team),spot,String(b.kind))
	_making_twin = false
	b.twin_id = int(t.id)
	t.twin_id = int(b.id)
	t.twin_secondary = true
	b.pair_hp = float(b.hp)
	t.pair_hp = float(t.hp)
	if b.has("fill_home"): t.fill_home = b.fill_home

static func twin(m, b: Dictionary) -> Dictionary:
	var id := int(b.get("twin_id",-1))
	if id < 0: return {}
	for other: Dictionary in m.buildings:
		if int(other.id) == id: return other
	return {}

# battle.damage, before the blow lands: true when the very same blow already hit the other segment.
static func repeat_hit(m, target: Dictionary, amount: float, kind: String, source: Dictionary) -> bool:
	var key := [snappedf(float(m.elapsed),0.0001),int(source.get("id",-1)),kind,snappedf(amount,0.01)]
	target.last_blow = key
	var t := twin(m,target)
	return not t.is_empty() and t.get("last_blow",[]) == key

# battle.damage, right after the blow: the other segment takes it too.
static func share_hit(m, target: Dictionary) -> void:
	var t := twin(m,target)
	if t.is_empty() or t.hp <= 0: return
	t.hp = target.hp
	t.pair_hp = target.hp
	target.pair_hp = target.hp
	var spawned := maxi(int(target.get("thresholds_spawned",0)),int(t.get("thresholds_spawned",0)))
	if spawned > 0:
		target.thresholds_spawned = spawned
		t.thresholds_spawned = spawned
	t.flash = 0.08

static func on_refresh(m, b: Dictionary) -> void:
	var t := twin(m,b)
	if t.is_empty(): return
	t.hp = b.hp
	t.pair_hp = float(b.hp)
	b.pair_hp = float(b.hp)
	t.expires = b.expires
	if b.has("charges"): t.charges = b.charges
	if b.kind == "bonewall": t.thresholds_spawned = 0

static func sync_thresholds(m, b: Dictionary) -> void:
	var t := twin(m,b)
	if not t.is_empty(): t.thresholds_spawned = int(b.get("thresholds_spawned",0))

# battle.step, once per step: merge any other health change and keep the pair alive or dead together.
static func sync(m) -> void:
	var lost_one := false
	for b: Dictionary in m.buildings:
		if not b.has("twin_id"): continue
		if b.get("twin_secondary",false):
			if twin(m,b).is_empty():
				b.erase("twin_id")
				b.erase("twin_secondary")
			continue
		var t := twin(m,b)
		if t.is_empty():
			b.erase("twin_id")
			continue
		var last: float = float(b.get("pair_hp",b.hp))
		var da: float = float(b.hp)-last
		var db: float = float(t.hp)-last
		var now: float = minf(last+minf(da,0.0)+minf(db,0.0)+maxf(maxf(da,0.0),maxf(db,0.0)),maxf(float(b.max_hp),float(t.max_hp)))
		if now <= 0.0 and (b.hp > 0 or t.hp > 0): lost_one = true
		b.hp = now
		t.hp = now
		b.pair_hp = now
		t.pair_hp = now
		if float(b.get("expires",-1.0)) > 0.0 or float(t.get("expires",-1.0)) > 0.0:
			var until := maxf(float(b.expires),float(t.expires))
			b.expires = until
			t.expires = until
	if lost_one: m.refresh_territory()

# game.draw_preview: the cells a two-lane building will stand on, with its ghost in each.
static func draw_preview(g, m, team: int, kind: String, cell: Vector2i, legal: bool) -> void:
	GridRules.draw_cells(g,cells(m,team,kind,cell),Color(0.2,0.7,0.3,0.22) if legal else Color(0.8,0.1,0.1,0.22),Color(0.28,0.85,0.42,0.9) if legal else Color(0.92,0.22,0.18,0.9))

# game: one health bar per building, so the lower segment of a pair shows none.
static func hide_bar(b: Dictionary) -> bool:
	return b.get("twin_secondary",false)
