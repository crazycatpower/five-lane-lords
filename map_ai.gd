extends RefCounted
# 敵方 AI 怎麼利用地圖機制（使用者 2026-11-22：讓 AI 會利用地圖機制）。enemy_ai.decide() 只呼叫兩處：
#   lane_bonus()  挑進攻路線：順風、乾路、傳送門通往弱牆、符文格加分；水路、快淹水的路、泥沼、熔岩扣分
#   cell_bonus()  挑出牌位置：不站在即將落石或熔岩的格子；遠程站符文格；守坡頂時多出遠程、在自己半場蓋防守建築
# 戰場沒有這些地形時兩者都回 0，原本的 AI 完全不變。
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

const WIND_WITH := 120.0
const WIND_AGAINST := 60.0
const FLOODED := 220.0
const FLOOD_SOON := 120.0
const MUD := 40.0
const LAVA := 90.0
const RUNE_LANE := 40.0
const PORTAL_GAIN := 220.0

static func marching_dir(team: int) -> int:
	return 1 if team == 0 else -1

# Is there any terrain worth thinking about in this snapshot?
static func any(s: Dictionary) -> bool:
	return not s.get("mech",{}).is_empty() or not s.get("water_lanes",[]).is_empty() or not s.get("wind_dir",{}).is_empty()

# Cells of this lane that lie ahead of our own half (where our troops will walk).
static func ahead(team: int, cell: Vector2i) -> bool:
	return cell.x >= 2 if team == 0 else cell.x <= L.GRID_COLUMNS-3

static func lane_bonus(s: Dictionary, team: int, lane: int) -> float:
	var bonus := 0.0
	var wind: Dictionary = s.get("wind_dir",{})
	if wind.has(lane): bonus += WIND_WITH if int(wind[lane]) == marching_dir(team) else -WIND_AGAINST
	if lane in s.get("water_lanes",[]): bonus -= FLOODED
	var mech: Dictionary = s.get("mech",{})
	if mech.is_empty(): return bonus
	if mech.has("sluice"):
		var sl: Dictionary = mech.sluice
		var next: int = int(sl.lanes[(int(sl.index)+1) % sl.lanes.size()])
		if lane == next and float(sl.timer) < 15.0: bonus -= FLOOD_SOON
	for c: Vector2i in mech.get("mud_cells",[]):
		if c.y == lane and ahead(team,c): bonus -= MUD
	for c: Vector2i in mech.get("lava_cells",[]):
		if c.y == lane and ahead(team,c): bonus -= LAVA
	for c: Vector2i in mech.get("rune_cells",[]):
		if c.y == lane: bonus += RUNE_LANE
	# A portal on our side of this lane that comes out in a lane whose wall is weaker.
	for pair: Array in mech.get("portals",[]):
		for end: int in range(2):
			var here: Vector2i = pair[end]
			var there: Vector2i = pair[1-end]
			if here.y != lane or there.y == lane or not there.y in s.get("active_lanes",[]): continue
			var gain: float = (s.gates[1-team][lane]-s.gates[1-team][there.y])/B.GATE_HP
			if gain > 0.0: bonus += gain*PORTAL_GAIN
	return bonus

static func cell_bonus(c: Dictionary, s: Dictionary, team: int, data: Dictionary) -> float:
	var mech: Dictionary = s.get("mech",{})
	if mech.is_empty(): return 0.0
	var cell: Vector2i = c.cell
	var bonus := 0.0
	if mech.has("eruption"):
		for f: Dictionary in mech.eruption.falling:
			if f.cell == cell: bonus -= 500.0 # a rock is about to land here
	if data.type == "unit" and not data.get("flying",false) and cell in mech.get("lava_cells",[]): bonus -= 200.0
	var shooter: bool = data.type == "unit" and data.get("projectile",false)
	if shooter:
		if cell in mech.get("rune_cells",[]): bonus += 60.0
		else:
			for r: Vector2i in mech.get("rune_cells",[]):
				if r.y == cell.y and (r.x-cell.x)*marching_dir(team) > 0:
					bonus += 25.0
					break
	if mech.has("slope_high") and int(mech.slope_high) == team:
		var own_half: bool = cell.x >= 5 if team == 1 else cell.x <= 3
		if shooter: bonus += 40.0 # high ground: shooters reach one tier further on our half
		elif data.type == "building" and own_half and (B.has_tag(c.kind,"guard") or B.has_tag(c.kind,"defend_building")): bonus += 40.0
	return bonus
