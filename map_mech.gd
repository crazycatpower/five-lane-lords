extends RefCounted
# 地圖機制（使用者 2026-11-22：新機制，地形要搭配劇情，例如上坡、火山）。
# 關卡或肉鴿戰場的 field mutator 帶下列欄位就會啟用；狀態放在 battle.mech。純規則，畫法在 terrain_art.gd。
#   slope        {"high":1}       上坡：那一方守在坡頂。往坡頂走的部隊移速 ×0.8；坡頂一方站在自己半場的遠程射程升一檔
#   sluice       {"lanes":[…],"interval":秒}   水閘輪替：每隔幾秒換下一路淹水（水路規則：禁建、地面部隊 -60%）
#   rune_cells   [[欄,路],…]      符文格：站在上面的遠程部隊射程升一檔（雙方都可用）
#   portals      [[[欄,路],[欄,路]],…]   傳送門：地面部隊走進一端，從另一端出來（1.5 秒內不會再傳）
#   fog          欄               濃霧：這一欄之後的敵兵，我方部隊或建築沒靠近（2 格內）就看不到；只影響畫面
#   mud_cells    [[欄,路],…]      泥沼：地面部隊經過移速 ×0.7，可以蓋建築
#   lava_cells   [[欄,路],…]      熔岩：地面部隊每秒受 20 傷害，不能蓋建築
#   eruption     {"interval":秒}  火山噴石：預警 2 秒後砸中一格，對格內地面部隊與建築 230 傷害，該格 25 秒不能蓋建築
# 會變化的天候（使用者 2026-11-22：希望有更多動態或隨機性，比如風向轉變）。時間點都帶一點亂數，用 battle.rng，重播一致：
#   wind_shift   {"interval":秒}  風向轉變：所有順風道一起反向；轉向前 5 秒預告
#   gusts        {"interval":秒}  陣風：隨機一路吹起 12 秒的風，方向隨機
#   storm        {"interval":秒}  雷暴：隨機一格預警 1.5 秒後落雷，格內地面部隊與建築 140 傷害
#   blizzard     {"interval":秒}  暴風雪：一陣 8 秒，所有地面部隊移速 ×0.7
#   fog_drift    true             濃霧邊界在三格之間來回飄動
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Giant = preload("res://giant_unit.gd")

const SLOPE_SLOW := 0.8
const MUD_SLOW := 0.7
const LAVA_DPS := 20.0
const LAVA_TICK := 0.5
const PORTAL_RADIUS := 24.0
const PORTAL_COOLDOWN := 1.5
const ROCK_WARN := 2.0
const ROCK_DAMAGE := 230.0
const ROCK_BLOCK := 25.0
const FOG_SIGHT := 236.0 # two cells
const SHIFT_WARN := 5.0
const GUST_TIME := 12.0
const STORM_WARN := 1.5
const STORM_DAMAGE := 140.0
const BLIZZARD_TIME := 8.0
const BLIZZARD_SLOW := 0.7

# The next time something happens: the interval, give or take a quarter, from the battle's own rng.
static func next_in(m, interval: float) -> float:
	return maxf(6.0,interval*m.rng.randf_range(0.75,1.25))

static func cells(list: Array) -> Array:
	var out: Array = []
	for c in list: out.append(Vector2i(int(c[0]),int(c[1])))
	return out

static func setup(m, mut: Dictionary) -> void:
	var s: Dictionary = m.mech
	if mut.has("slope"): s.slope_high = int(mut.slope.get("high",1))
	if mut.has("sluice"):
		var lanes: Array = mut.sluice.get("lanes",[])
		if not lanes.is_empty():
			s.sluice = {"lanes":lanes.duplicate(),"interval":float(mut.sluice.get("interval",40.0)),"index":0,"timer":float(mut.sluice.get("interval",40.0))}
			flood(m,int(lanes[0]))
	if mut.has("rune_cells"): s.rune_cells = cells(mut.rune_cells)
	if mut.has("portals"):
		s.portals = []
		for p in mut.portals: s.portals.append([Vector2i(int(p[0][0]),int(p[0][1])),Vector2i(int(p[1][0]),int(p[1][1]))])
	if mut.has("fog"): s.fog_col = int(mut.fog)
	if mut.has("mud_cells"): s.mud_cells = cells(mut.mud_cells)
	if mut.has("lava_cells"):
		s.lava_cells = cells(mut.lava_cells)
		s.lava_timer = LAVA_TICK
	if mut.has("eruption"):
		s.eruption = {"interval":float(mut.eruption.get("interval",20.0)),"timer":float(mut.eruption.get("interval",20.0)),"falling":[],"blocked":[]}
	if mut.has("wind_shift"): s.wind_shift = {"interval":float(mut.wind_shift.get("interval",40.0)),"timer":float(mut.wind_shift.get("interval",40.0))}
	if mut.has("gusts"):
		s.gusts = {"interval":float(mut.gusts.get("interval",30.0)),"timer":float(mut.gusts.get("interval",30.0))*0.5,"live":[]}
	if mut.has("storm"): s.storm = {"interval":float(mut.storm.get("interval",18.0)),"timer":float(mut.storm.get("interval",18.0)),"falling":[],"flash":[]}
	if mut.has("blizzard"): s.blizzard = {"interval":float(mut.blizzard.get("interval",45.0)),"timer":float(mut.blizzard.get("interval",45.0)),"left":0.0}
	if mut.has("fog_drift") and s.has("fog_col"): s.fog_base = int(s.fog_col)

static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((pos.x-L.GRID_ORIGIN.x)/L.CELL_SIZE.x),0,L.GRID_COLUMNS-1),clampi(floori((pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,L.GRID_ROWS-1))

static func ground(u: Dictionary) -> bool:
	return u.hp > 0 and not u.get("flying",false)

static func unit_cells(u: Dictionary) -> Array[Vector2i]:
	if Giant.is_giant(u): return Giant.cells(u)
	var out: Array[Vector2i] = [cell_of(u.pos)]
	return out

# Lava cells and freshly struck rock cannot be built on.
static func no_build(m, cell: Vector2i) -> bool:
	var s: Dictionary = m.mech
	if s.is_empty(): return false
	if cell in s.get("lava_cells",[]): return true
	if s.has("eruption"):
		for r: Dictionary in s.eruption.blocked:
			if r.cell == cell: return true
	return false

# Marching speed: uphill, mud.
static func speed_mult(m, u: Dictionary) -> float:
	var s: Dictionary = m.mech
	if s.is_empty() or u.get("flying",false): return 1.0
	var mult := 1.0
	if s.has("slope_high") and int(u.team) != int(s.slope_high): mult *= SLOPE_SLOW
	if s.has("mud_cells") and unit_cells(u).any(func(c: Vector2i) -> bool: return c in s.mud_cells): mult *= MUD_SLOW
	if s.has("blizzard") and float(s.blizzard.left) > 0.0: mult *= BLIZZARD_SLOW
	return mult

# One range tier further: standing on a rune cell, or a shooter of the high side on its own half.
static func range_steps(m, u: Dictionary) -> int:
	var s: Dictionary = m.mech
	if s.is_empty(): return 0
	var steps := 0
	var uc := unit_cells(u)
	if uc.any(func(c: Vector2i) -> bool: return c in s.get("rune_cells",[])): steps += 1
	if s.has("slope_high") and int(u.team) == int(s.slope_high):
		var c := cell_of(u.pos)
		var own_half: bool = c.x >= 5 if int(u.team) == 1 else c.x <= 3
		if own_half: steps += 1
	return mini(steps,1)

static func update(m, dt: float) -> void:
	var s: Dictionary = m.mech
	if s.is_empty(): return
	weather(m,s,dt)
	if s.has("sluice"):
		var sl: Dictionary = s.sluice
		sl.timer -= dt
		if sl.timer <= 0.0:
			sl.timer += maxf(10.0,float(sl.interval))
			sl.index = (int(sl.index)+1) % sl.lanes.size()
			flood(m,int(sl.lanes[sl.index]))
	if s.has("portals"):
		for u: Dictionary in m.units:
			if not ground(u) or Giant.is_giant(u): continue
			if float(u.get("portal_cd",0.0)) > 0.0:
				u.portal_cd = float(u.portal_cd)-dt
				continue
			for pair: Array in s.portals:
				for end: int in range(2):
					var here: Vector2 = L.cell_center(pair[end])
					if u.pos.distance_to(here) > PORTAL_RADIUS: continue
					var there: Vector2i = pair[1-end]
					if not there.y in m.active_lanes: continue
					u.pos = L.cell_center(there)+Vector2(float(u.face)*(PORTAL_RADIUS+6.0),0.0)
					u.lane = there.y
					u.portal_cd = PORTAL_COOLDOWN
					m.event("spell",u.pos,u.team,{"card":"teleport_trap","radius":40.0})
					break
				if float(u.get("portal_cd",0.0)) > 0.0: break
	if s.has("lava_cells"):
		s.lava_timer = float(s.lava_timer)-dt
		if s.lava_timer <= 0.0:
			s.lava_timer += LAVA_TICK
			for u: Dictionary in m.units.duplicate():
				if ground(u) and unit_cells(u).any(func(c: Vector2i) -> bool: return c in s.lava_cells): m.damage(u,LAVA_DPS*LAVA_TICK,1-int(u.team),"lava")
	if s.has("eruption"):
		var er: Dictionary = s.eruption
		er.timer -= dt
		if er.timer <= 0.0:
			er.timer += maxf(6.0,float(er.interval))
			var lane: int = m.active_lanes[m.rng.randi_range(0,m.active_lanes.size()-1)]
			er.falling.append({"cell":Vector2i(m.rng.randi_range(2,6),lane),"left":ROCK_WARN})
		var still: Array = []
		for f: Dictionary in er.falling:
			f.left = float(f.left)-dt
			if f.left > 0.0:
				still.append(f)
				continue
			strike(m,f.cell)
		er.falling = still
		var kept: Array = []
		for r: Dictionary in er.blocked:
			r.left = float(r.left)-dt
			if r.left > 0.0: kept.append(r)
		er.blocked = kept

# The changing weather: wind shifts, gusts, lightning, blizzards and drifting fog.
static func weather(m, s: Dictionary, dt: float) -> void:
	if s.has("wind_shift"):
		var ws: Dictionary = s.wind_shift
		ws.timer = float(ws.timer)-dt
		if ws.timer <= 0.0:
			ws.timer = next_in(m,float(ws.interval))
			var gust_lanes: Array = s.gusts.live.map(func(g: Dictionary) -> int: return int(g.lane)) if s.has("gusts") else []
			for lane in m.wind_dir.keys():
				if not int(lane) in gust_lanes: m.wind_dir[lane] = -int(m.wind_dir[lane])
			m.event("spell",L.cell_center(Vector2i(4,m.active_lanes[0])),1,{"card":"wing_gust","radius":60.0})
	if s.has("gusts"):
		var gs: Dictionary = s.gusts
		var live: Array = []
		for g: Dictionary in gs.live:
			g.left = float(g.left)-dt
			if g.left > 0.0: live.append(g)
			else:
				m.wind_lanes.erase(int(g.lane))
				m.wind_dir.erase(int(g.lane))
		gs.live = live
		gs.timer = float(gs.timer)-dt
		if gs.timer <= 0.0:
			gs.timer = next_in(m,float(gs.interval))
			var calm: Array = m.active_lanes.filter(func(l: int) -> bool: return not l in m.wind_lanes)
			if not calm.is_empty():
				var lane: int = calm[m.rng.randi_range(0,calm.size()-1)]
				var dir: int = 1 if m.rng.randf() < 0.5 else -1
				m.wind_lanes.append(lane)
				m.wind_dir[lane] = dir
				gs.live.append({"lane":lane,"left":GUST_TIME})
	if s.has("storm"):
		var st: Dictionary = s.storm
		st.timer = float(st.timer)-dt
		if st.timer <= 0.0:
			st.timer = next_in(m,float(st.interval))
			var lane: int = m.active_lanes[m.rng.randi_range(0,m.active_lanes.size()-1)]
			st.falling.append({"cell":Vector2i(m.rng.randi_range(1,7),lane),"left":STORM_WARN})
		var still: Array = []
		for f: Dictionary in st.falling:
			f.left = float(f.left)-dt
			if f.left > 0.0:
				still.append(f)
				continue
			var rect := Rect2(L.GRID_ORIGIN+Vector2(f.cell)*L.CELL_SIZE,L.CELL_SIZE)
			for u: Dictionary in m.units.duplicate():
				if ground(u) and (rect.has_point(u.pos) or f.cell in unit_cells(u)): m.damage(u,STORM_DAMAGE,1-int(u.team),"storm")
			for b: Dictionary in m.buildings:
				if b.hp > 0 and b.cell == f.cell: m.damage(b,STORM_DAMAGE,1-int(b.team),"storm")
			st.flash.append({"cell":f.cell,"left":0.4})
			m.event("spell",rect.get_center(),1,{"card":"chain_lightning","radius":50.0})
		st.falling = still
		st.flash = st.flash.filter(func(f: Dictionary) -> bool:
			f.left = float(f.left)-dt
			return float(f.left) > 0.0)
	if s.has("blizzard"):
		var bz: Dictionary = s.blizzard
		if float(bz.left) > 0.0: bz.left = float(bz.left)-dt
		else:
			bz.timer = float(bz.timer)-dt
			if bz.timer <= 0.0:
				bz.timer = next_in(m,float(bz.interval))
				bz.left = BLIZZARD_TIME
	if s.has("fog_base"):
		s.fog_col = clampi(int(s.fog_base)+roundi(sin(m.elapsed/18.0)*1.4),2,L.GRID_COLUMNS-2)

# The sluice opens on this lane: it becomes the only flooded lane of the rotation.
static func flood(m, lane: int) -> void:
	var s: Dictionary = m.mech
	var rot: Array = s.sluice.lanes if s.has("sluice") else []
	var kept: Array[int] = []
	for l: int in m.water_lanes:
		if not l in rot: kept.append(l)
	if lane in m.active_lanes: kept.append(lane)
	m.water_lanes = kept
	m.event("spell",L.cell_center(Vector2i(4,lane)),1,{"card":"time_field","radius":60.0})

static func strike(m, cell: Vector2i) -> void:
	var rect := Rect2(L.GRID_ORIGIN+Vector2(cell)*L.CELL_SIZE,L.CELL_SIZE)
	for u: Dictionary in m.units.duplicate():
		if ground(u) and (rect.has_point(u.pos) or cell in unit_cells(u)): m.damage(u,ROCK_DAMAGE,1-int(u.team),"eruption")
	for b: Dictionary in m.buildings:
		if b.hp > 0 and b.cell == cell: m.damage(b,ROCK_DAMAGE,1-int(b.team),"eruption")
	m.mech.eruption.blocked.append({"cell":cell,"left":ROCK_BLOCK})
	m.event("spell",rect.get_center(),1,{"card":"rolling_boulder","radius":58.0})

# Fog: an enemy troop deep in the mist that none of our troops or buildings is near is not drawn.
static func hidden(m, u: Dictionary, viewer: int) -> bool:
	var s: Dictionary = m.mech
	if s.is_empty() or not s.has("fog_col") or int(u.team) == viewer: return false
	var col := cell_of(u.pos).x
	if (col < int(s.fog_col)) if viewer == 0 else (col > L.GRID_COLUMNS-1-int(s.fog_col)): return false
	for o: Dictionary in m.units:
		if o.team == viewer and o.hp > 0 and o.pos.distance_to(u.pos) <= FOG_SIGHT: return false
	for b: Dictionary in m.buildings:
		if b.team == viewer and b.hp > 0 and b.pos.distance_to(u.pos) <= FOG_SIGHT: return false
	return true

# The panel line for a mutator's mechanics, e.g. 「上坡（敵方守坡頂）· 濃霧」.
static func labels(mut: Dictionary) -> Array:
	var out: Array = []
	if mut.has("slope"): out.append("上坡")
	if mut.has("sluice"): out.append("水閘輪替")
	if mut.has("rune_cells"): out.append("符文格")
	if mut.has("portals"): out.append("傳送門")
	if mut.has("fog"): out.append("濃霧")
	if mut.has("mud_cells"): out.append("泥沼")
	if mut.has("lava_cells"): out.append("熔岩")
	if mut.has("eruption"): out.append("火山噴石")
	if mut.has("wind_shift"): out.append("風向轉變")
	if mut.has("gusts"): out.append("陣風")
	if mut.has("storm"): out.append("雷暴")
	if mut.has("blizzard"): out.append("暴風雪")
	if mut.has("fog_drift"): out.append("飄霧")
	return out

static func explain(mut: Dictionary) -> Array:
	var out: Array = []
	if mut.has("slope"): out.append("上坡：敵方守在坡頂。我方部隊往上攻移速 ×0.8；敵方遠程站在自己半場射程升一檔。")
	if mut.has("sluice"): out.append("水閘輪替：每 %d 秒換一路淹水（禁建、地面部隊 -60%%）。" % int(mut.sluice.get("interval",40.0)))
	if mut.has("rune_cells"): out.append("符文格：站在上面的遠程部隊射程升一檔，雙方都能用。")
	if mut.has("portals"): out.append("傳送門：地面部隊走進一端，會從同色的另一端出來。")
	if mut.has("fog"): out.append("濃霧：霧裡的敵兵要等我方部隊或建築靠近 2 格內才看得到。")
	if mut.has("mud_cells"): out.append("泥沼：地面部隊經過移速 ×0.7，可以蓋建築。")
	if mut.has("lava_cells"): out.append("熔岩：地面部隊站上去每秒受 20 傷害，不能蓋建築。")
	if mut.has("eruption"): out.append("火山噴石：每 %d 秒預警 2 秒後砸中一格，230 傷害，之後 25 秒不能蓋建築。" % int(mut.eruption.get("interval",20.0)))
	if mut.has("wind_shift"): out.append("風向轉變：大約每 %d 秒所有順風道一起反向，轉向前 5 秒會預告。" % int(mut.wind_shift.get("interval",40.0)))
	if mut.has("gusts"): out.append("陣風：大約每 %d 秒隨機一路吹起 12 秒的風，方向也隨機。" % int(mut.gusts.get("interval",30.0)))
	if mut.has("storm"): out.append("雷暴：大約每 %d 秒隨機一格閃光預警，1.5 秒後落雷，140 傷害。" % int(mut.storm.get("interval",18.0)))
	if mut.has("blizzard"): out.append("暴風雪：大約每 %d 秒來一陣，8 秒內所有地面部隊移速 ×0.7。" % int(mut.blizzard.get("interval",45.0)))
	if mut.has("fog_drift"): out.append("飄霧：濃霧的邊界會前後飄動。")
	return out

# ---------------- how many rules one battle carries (使用者 2026-11-22：同一關不要疊加太多機制) ----------------
# A field's features grouped into rules; a battle keeps only the first few (in this order of importance).
# Boulders are plain scenery and never count.
const GROUPS := [
	["sluice",["sluice"]],["slope",["slope"]],["portals",["portals"]],["rune",["rune_cells"]],
	["fog",["fog","fog_drift"]],["volcano",["lava_cells","eruption"]],["mud",["mud_cells"]],["storm",["storm"]],
	["water",["water_lanes","water_cols","water_cells"]],["wind",["wind_lanes","wind_left_lanes","wind_shift"]],
	["blizzard",["blizzard"]],["gusts",["gusts"]],
]
const GROUP_NAMES := {"sluice":"水閘輪替","slope":"上坡","portals":"傳送門","rune":"符文格","fog":"濃霧","volcano":"火山",
	"mud":"泥沼","storm":"雷暴","water":"水路","wind":"順風道","blizzard":"暴風雪","gusts":"陣風"}

static func groups_in(mut: Dictionary) -> Array:
	var out: Array = []
	for g: Array in GROUPS:
		for key: String in g[1]:
			if mut.has(key) and not (mut[key] is Array and mut[key].is_empty()):
				out.append(g[0])
				break
	return out

# Keep only the first `keep` rule groups of a field mutator; boulders, enemy buildings and units stay.
static func trim(mut: Dictionary, keep: int) -> Dictionary:
	var kept: Array = groups_in(mut).slice(0,maxi(0,keep))
	var out := mut.duplicate(true)
	for g: Array in GROUPS:
		if g[0] in kept: continue
		for key: String in g[1]: out.erase(key)
	return out

# One rule group as a line for the briefing: 「名稱：說明」.
static func group_line(mut: Dictionary, group: String) -> Array:
	var sub := {}
	for g: Array in GROUPS:
		if g[0] != group: continue
		for key: String in g[1]:
			if mut.has(key): sub[key] = mut[key]
	var text := ""
	match group:
		"water": text = "不能蓋建築，地面部隊經過移速 -60%（飛行不受影響）。"
		"wind":
			text = "→ 往右走的部隊移速升一檔" if not mut.get("wind_lanes",[]).is_empty() else ""
			if not mut.get("wind_left_lanes",[]).is_empty(): text += ("；" if not text.is_empty() else "")+"← 往左走的部隊移速升一檔"
			text += "。" + ("約每 %d 秒風向一起反轉，轉向前 5 秒預告。" % int(mut.wind_shift.get("interval",40.0)) if mut.has("wind_shift") else "")
		_:
			var lines: Array = explain(sub)
			text = " ".join(lines.map(func(l: String) -> String: return l.substr(l.find("：")+1) if l.find("：") >= 0 else l))
	return [GROUP_NAMES.get(group,group),text]
