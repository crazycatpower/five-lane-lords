extends RefCounted
const Windup = preload("res://attack_windup.gd")
const WardRules = preload("res://ward_rules.gd")
const RelicTriggers = preload("res://relic_triggers.gd")
const Frontier = preload("res://frontier_cards.gd")
const Faction = preload("res://faction_cards.gd")
const GluttonNest = preload("res://glutton_nest.gd")
const Expansion = preload("res://expansion_cards.gd")
const ExpansionMore = preload("res://expansion_more.gd")
const Monster = preload("res://monster_cards.gd")
const GoldMonster = preload("res://gold_monster.gd")
const SealAltar = preload("res://seal_altar.gd")
const CoreCards = preload("res://core_cards.gd")
const GridRules = preload("res://grid_rules.gd")
const Upgrades = preload("res://card_upgrades.gd")
const DarkSorcery = preload("res://dark_sorcery.gd")
const LordExpansion = preload("res://lord_expansion.gd")
const Arcane = preload("res://arcane_mechanics.gd")
const AI = preload("res://enemy_ai.gd")
const Lord = preload("res://lord.gd")
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const COMBO_STRIKE_GAP := 0.14
var rng := RandomNumberGenerator.new()
var ink: Array = [B.START_INK,B.START_INK]
var base_clock: Array = [0.0,0.0]
var team_mods: Array = [{},{}] # roguelike 內政領主 passives (apply_domestic)
var card_upgrades: Array = [{},{}] # roguelike card upgrades per team: {card: {stat: steps}}
var hand_cd: Array = [[0.0,0.0,0.0,0.0],[0.0,0.0,0.0,0.0]] # seconds until each hand slot may be played
var decks: Array = []
var units: Array[Dictionary] = []
var buildings: Array[Dictionary] = []
var territory := PackedInt32Array() # -1 neutral; first owner keeps a tile while supported
var projectiles: Array[Dictionary] = []
var spells: Array[Dictionary] = []
var death_queue: Array[Dictionary] = [] # gameplay queue, independent of visual event recording
var zones: Array[Dictionary] = []
var fields: Array = [] # time fields (faction_cards.gd)
var horns: Array = [] # charge horns: {team, lane, until}
var lords: Array = []
var gates: Array = []
var alarm: Array = [0.0,0.0,0.0,0.0,0.0]
var building_alarm: Array = [0.0,0.0,0.0,0.0,0.0]
var stats: Array = []
var events: Array[Dictionary] = []
var elapsed := 0.0
var vampire_until: Array[float] = [0.0,0.0]
var time_stop_left := 0.0
var time_stop_team := -1
var time_stop_origin := Vector2.ZERO

func time_stopped() -> bool:
	return time_stop_left > 0.000001

func actor_time(actor: Dictionary) -> float:
	return elapsed+float(actor.get("extra_time",0.0))

# 時空凝滯 (producer 2026-11-19): the game keeps running; only the caster's enemies stop. Their
# troops and lord stand still (animations too), their buildings (towers and economy) and base income
# pause. Everything else, both sides' cards and cooldowns and the projectiles in flight, carries on.
func frozen(team: int) -> bool:
	return time_stop_left > 0.000001 and time_stop_team >= 0 and team != time_stop_team

func tick_time_stop(dt: float) -> void:
	if not time_stopped(): return
	for u: Dictionary in units:
		if frozen(u.team): u.extra_time = u.get("extra_time",0.0)-dt # hold the pose: actor_time stands still
	for lord: Dictionary in lords:
		if frozen(lord.team): lord.extra_time = lord.get("extra_time",0.0)-dt
	time_stop_left = maxf(0,time_stop_left-dt)
	if not time_stopped():
		time_stop_left = 0.0
		time_stop_team = -1
var last_dt := 0.0
var ended := false
# Challenge objectives can hold attackers at the far gate; normal matches keep both sides enabled.
var invasion_victory: Array[bool] = [true,true]
var active_lanes: Array[int] = [0,1,2,3,4]
var winner := -2
var paused := false
var next_id := 0
var ai_enabled: Array = [false,false]
var difficulty := 1
var ai_clock: Array = [0.0,0.0]
var ai_pending: Array = [{},{}]
var ai_delay: Array = [0.0,0.0]
var wave_until: Array = [0.0,0.0]
var memory: Array = [{},{}]
var recent_lanes: Array = [[],[]] # lanes of each side's last troop plays, for the AI to spread its attacks
var ai_start := 0.0
var lord_active: Array = [true,true] # the tutorial keeps the blue lord idle
var first_breach := -1.0 # seconds into the match when the first gate fell (-1 = never)
# Gates crumble after B.NIGHT_START. The roguelike turns this off: its gates carry their wounds into
# the next battle and it has its own time limit.
var night_decay := true
var serials_in_use: Dictionary = {} # 序號 currently held by a living unit or building
var record_events := true # batch simulators turn this off; no game logic reads events
# Per-step lookup lists, rebuilt after the AI plays (same order as units/buildings, so every
# "nearest" search sees the candidates in the same order as a scan of the full list would).
var foe_units: Array = [[],[]] # foe_units[team]: units of the other side
var lane_foes: Array = [] # lane_foes[team][lane]: enemy units in that lane
var lane_foe_buildings: Array = []
var lane_foe_taunts: Array = []
var lane_mill: Array = [] # lane_mill[team][lane]: number of living mills boosting that lane's farms
var has_watchtower: Array = [false,false]
var has_taunt: Array = [false,false]
var wards: Array = [[],[]] # living 結界護衛 per team (ward_rules.gd)
var has_trap := false
var has_poisoned_unit := false
var has_levy := false
var has_monster_tick := false
var has_plague_bishop := false
var has_thorns_aura: Array = [false,false]
var has_expansion_tick := false
var has_hex_unit := false
var has_borrowed_unit := false
var has_expansion_building := false
var water_lanes: Array[int] = []
var water_cols: Array[int] = []
var field_mutators: Array[Dictionary] = []

# Hand slots 0..3 rotate; FARM_SLOT is the permanent farmland slot (never rotates, own cooldown).
const FARM_SLOT := 4
var farm_cd: Array = [0.0,0.0]
var home_cards: Array = ["farm","farm"] # each side's F-slot card, fixed by its lord at the start
var skill_cd: Array = [0.0,0.0] # lord skill cooldown per side; starts ready (2026-11-19), the empty charge meter gates the first cast
var skill_charge: Array = [0.0,0.0] # lord skill charge: gold spent on cards and gold lost to a full purse
var ai_save: Array = [false,false] # the AI is holding gold for its lord's skill (unused since the charge meter)
var ai_params: Array = [{},{}] # per-side AI strategy weights (enemy_ai.gd; {} = the hand-written defaults)
var team_drum_until: Array = [0.0,0.0] # latest end of any drum on this team (kept for tools/tests)
var team_drums: Array = [[],[]] # end time of every drum beat still sounding; each one is a speed tier

func _init(seed_value: int = 1, deck_a: Array = [], deck_b: Array = [], lord_a: String = "", lord_b: String = "") -> void:
	territory.resize(L.GRID_COLUMNS*L.GRID_ROWS)
	territory.fill(-1)
	for team: int in range(2):
		for lane: int in range(L.GRID_ROWS):
			claim_around(team,Vector2i(-1 if team == 0 else L.GRID_COLUMNS,lane))
	rng.seed = seed_value
	for team: int in range(2):
		var deck: Array = (deck_a if team == 0 else deck_b).duplicate()
		if deck.is_empty(): deck = B.PRESETS[0].duplicate()
		for i: int in range(deck.size()-1,0,-1):
			var j := rng.randi_range(0,i)
			var swap = deck[i]
			deck[i] = deck[j]
			deck[j] = swap
		SealAltar.keep_out_of_opening(deck) # 封印祭壇 never starts in hand (no extra rng draw)
		var lord_kind: String = lord_a if team == 0 else lord_b
		if lord_kind.is_empty(): lord_kind = "lion" # neutral default when no lord is chosen
		lords.append(Lord.create(team,lord_kind))
		home_cards[team] = B.home_card(lord_kind)
		decks.append(deck)
		gates.append([B.GATE_HP,B.GATE_HP,B.GATE_HP,B.GATE_HP,B.GATE_HP])
		stats.append({"produced":0.0,"wasted":0.0,"planted":0,"burned":0,"plays":0,"used":{},"damage":{},"spent":{},"cultivated":0,"drops":0,"farms_lost_early":0,"gate_damage":{},"breach_card":"","invaded_card":""})
	# Both sides start with two of their home buildings (farms, or tombstones for the underworld lord);
	# they are not counted as planted.
	for team: int in range(2):
		if not home_cards[team].is_empty():
			for cell: Vector2i in B.START_FARMS:
				add_building(team,Vector2i(cell.x if team == 0 else 8-cell.x,cell.y),home_cards[team])
		# A 小怪領主 may start with its own buildings (columns counted from its back edge).
		for b: Array in lord_mod(team,"start_buildings",[]):
			add_building(team,Vector2i(b[0] if team == 0 else 8-b[0],b[1]),b[2])
		stats[team].planted = 0

# A visible tie between a cause and what it affects: a death feeding a tombstone or a ghoul, a
# necromancer raising a skeleton, a herbalist healing, 豐收 doubling a farm. Drawing only.
# A 小怪領主's passive rule (B.MINION_LORDS); normal lords have none, so the default comes back.
# A roguelike 內政領主 adds its own passive on top (team_mods, set by apply_domestic).
func lord_mod(team: int, key: String, default: Variant) -> Variant:
	if team_mods[team].has(key): return team_mods[team][key]
	if team >= lords.size(): return default # some tests clear the lords
	return B.lord_data(lords[team].lord).get(key,default)

# Roguelike: a second lord runs this side's economy. Its home card replaces the starting home
# buildings, and its passive rule applies to the whole side (same keys as B.MINION_LORDS).
func apply_domestic(team: int, home: String, mods: Dictionary) -> void:
	team_mods[team] = mods.duplicate(true)
	if home != home_cards[team]:
		buildings = buildings.filter(func(b: Dictionary) -> bool: return not (b.team == team and b.kind == home_cards[team]))
		home_cards[team] = home
		if not home.is_empty():
			for cell: Vector2i in B.START_FARMS: add_building(team,Vector2i(cell.x if team == 0 else 8-cell.x,cell.y),home)
	for b: Array in mods.get("start_buildings",[]):
		add_building(team,Vector2i(b[0] if team == 0 else 8-b[0],b[1]),b[2])
	var boost := int(mods.get("lord_boost",0))
	if boost > 0 and team < lords.size():
		lords[team].max_hp = Upgrades.shifted("hp",lords[team].max_hp,boost)
		lords[team].hp = lords[team].max_hp
		lords[team].damage = Upgrades.shifted("damage",lords[team].damage,boost)
	ink[team] = minf(B.MAX_INK,ink[team]+mods.get("start_ink",0.0))
	for fm: Dictionary in mods.get("field_mutators",[]):
		apply_field_mutator(fm,team)
	RelicTriggers.battle_start(self,team)
	refresh_territory()

func is_water_cell(cell: Vector2i) -> bool:
	return cell.y in water_lanes or cell.x in water_cols

func apply_field_mutator(mut: Dictionary, default_team: int = 1) -> void:
	if mut.is_empty(): return
	var target_team := int(mut.get("team",default_team))
	var water_added := false
	for wl in mut.get("water_lanes",[]):
		var l := clampi(int(wl),0,L.GRID_ROWS-1)
		if not l in water_lanes:
			water_lanes.append(l)
			water_added = true
	for wc in mut.get("water_cols",[]):
		var c := clampi(int(wc),0,L.GRID_COLUMNS-1)
		if not c in water_cols:
			water_cols.append(c)
			water_added = true
	if water_added:
		var removed := [0,0]
		var kept: Array[Dictionary] = []
		for b: Dictionary in buildings:
			if is_water_cell(b.cell):
				removed[b.team] += 1
			else:
				kept.append(b)
		buildings = kept
		for team: int in range(2):
			var hc: String = home_cards[team]
			if removed[team] <= 0 or hc.is_empty(): continue
			var cols: Array = [0,1,2,3,4,5,6,7,8] if team == 0 else [8,7,6,5,4,3,2,1,0]
			var placed := 0
			for col: int in cols:
				for dry_lane: int in [0,4,2,1,3]:
					var cell := Vector2i(col,dry_lane)
					if is_water_cell(cell) or not dry_lane in active_lanes: continue
					if not building_at(cell).is_empty(): continue
					add_building(team,cell,hc)
					placed += 1
					if placed >= removed[team]: break
				if placed >= removed[team]: break
		refresh_territory()
	if bool(mut.get("double_home_rows",false)):
		var hc: String = String(home_cards[target_team]) if not String(home_cards[target_team]).is_empty() else "barricade"
		for col_off: int in [0,1]:
			var col := col_off if target_team == 0 else L.GRID_COLUMNS-1-col_off
			for lane: int in active_lanes:
				var cell := Vector2i(col,lane)
				if is_water_cell(cell): continue
				if building_at(cell).is_empty():
					add_building(target_team,cell,hc)
	for b: Array in mut.get("enemy_buildings",[]):
		var col := int(b[0]) if target_team == 0 else L.GRID_COLUMNS-1-int(b[0])
		var cell := Vector2i(col,int(b[1]))
		if cell.x >= 0 and cell.x < L.GRID_COLUMNS and cell.y in active_lanes and not is_water_cell(cell):
			if building_at(cell).is_empty():
				add_building(target_team,cell,String(b[2]))
	for u_spec: Array in mut.get("enemy_units",[]):
		var lane := int(u_spec[1])
		if lane in active_lanes:
			var col := int(u_spec[0]) if target_team == 0 else L.GRID_COLUMNS-1-int(u_spec[0])
			var cell := Vector2i(col,lane)
			var u := spawn_unit(target_team,lane,String(u_spec[2]),L.cell_center(cell))
			u.spawn_delay = 0.0
	if mut.has("extra_ink"):
		ink[target_team] = minf(B.MAX_INK,ink[target_team]+float(mut.extra_ink))
	if mut.has("periodic"):
		var p: Dictionary = mut.periodic.duplicate(true)
		p["mode"] = "building"
		p["team"] = int(p.get("team",target_team))
		p["timer"] = float(p.get("interval",30.0))
		field_mutators.append(p)
	if mut.has("periodic_spell"):
		var ps: Dictionary = mut.periodic_spell.duplicate(true)
		ps["mode"] = "spell"
		ps["team"] = int(ps.get("team",target_team))
		ps["timer"] = float(ps.get("interval",25.0))
		field_mutators.append(ps)
	refresh_territory()

func update_field_mutators(dt: float) -> void:
	if field_mutators.is_empty(): return
	for fm: Dictionary in field_mutators:
		fm.timer = float(fm.timer) - dt
		if fm.timer > 0.0: continue
		fm.timer += maxf(5.0,float(fm.get("interval",30.0)))
		var team := int(fm.get("team",1))
		if String(fm.get("mode","building")) == "spell":
			var sp_kind := String(fm.get("kind","time_field"))
			if not B.CARDS.has(sp_kind): continue
			var pos := L.cell_center(Vector2i(3 if team == 1 else 5, active_lanes[rng.randi_range(0,active_lanes.size()-1)]))
			var friendly_spell := sp_kind in ["arcane_shield","harvest","mana_spring","charge_horn","feral_mutation","levy"]
			var cand_units: Array = units.filter(func(u: Dictionary) -> bool: return u.team == team and u.hp > 0) if friendly_spell else foe_units[team]
			if not cand_units.is_empty():
				var target_u: Dictionary = cand_units[rng.randi_range(0,cand_units.size()-1)]
				pos = target_u.pos
			spells.append({"team":team,"kind":sp_kind,"pos":pos,"delay":B.SPELL_DELAY})
			event("spell",pos,team,{"card":sp_kind})
			continue
		var kind := String(fm.get("kind","grave"))
		var c0 := clampi(int(fm.get("min_col",1)),0,L.GRID_COLUMNS-1)
		var c1 := clampi(int(fm.get("max_col",7)),c0,L.GRID_COLUMNS-1)
		var open_cells: Array[Vector2i] = []
		for row: int in active_lanes:
			for col: int in range(c0,c1+1):
				var cell := Vector2i(col,row)
				if is_water_cell(cell): continue
				if building_at(cell).is_empty(): open_cells.append(cell)
		if not open_cells.is_empty():
			var chosen: Vector2i = open_cells[rng.randi_range(0,open_cells.size()-1)]
			add_building(team,chosen,kind)
			refresh_territory()
			event("spell",L.cell_center(chosen),team,{"card":kind,"radius":48.0})
		elif fm.has("fallback_unit"):
			var f_lane := active_lanes[rng.randi_range(0,active_lanes.size()-1)]
			var f_col := (L.GRID_COLUMNS-2) if team == 1 else 1
			for _n: int in range(int(fm.get("fallback_count",3))):
				spawn_unit(team,f_lane,String(fm.fallback_unit),L.cell_center(Vector2i(f_col,f_lane)))

func link(from: Vector2, to: Vector2, team: int, style: String) -> void:
	event("link",from,team,{"to":to,"style":style})

func event(kind: String, pos: Vector2, team: int = 0, extra: Dictionary = {}) -> void:
	if not record_events: return
	var e := {"kind":kind,"pos":pos,"team":team,"time":elapsed}
	e.merge(extra)
	events.append(e)

func cell_at(pos: Vector2) -> Vector2i:
	if not Rect2(L.GRID_ORIGIN,L.GRID_SIZE).has_point(pos): return Vector2i(-1,-1)
	return Vector2i((pos-L.GRID_ORIGIN)/L.CELL_SIZE)

func territory_owner(cell: Vector2i) -> int:
	if not cell.y in active_lanes: return -1
	if cell.x < 0 or cell.x >= L.GRID_COLUMNS or cell.y < 0 or cell.y >= L.GRID_ROWS: return -1
	return territory[cell.y*L.GRID_COLUMNS+cell.x]

func claim_around(team: int, center: Vector2i) -> void:
	# Include the building's own tile, plus its eight neighbours; never overwrite ownership.
	for dy: int in range(-1,2):
		for dx: int in range(-1,2):
			var cell := center+Vector2i(dx,dy)
			if cell.x < 0 or cell.x >= L.GRID_COLUMNS or cell.y < 0 or cell.y >= L.GRID_ROWS: continue
			var index := cell.y*L.GRID_COLUMNS+cell.x
			if territory[index] == -1: territory[index] = team

func refresh_territory() -> void:
	# Keep the current owner while any living allied structure supports the tile.
	# Otherwise the oldest surviving claimant takes over, or the tile becomes neutral.
	for row: int in range(L.GRID_ROWS):
		for col: int in range(L.GRID_COLUMNS):
			var support := 0
			var first := -1
			for team: int in range(2):
				if col != (0 if team == 0 else L.GRID_COLUMNS-1): continue
				for lane: int in range(maxi(0,row-1),mini(L.GRID_ROWS,row+2)):
					if gates[team][lane] > 0:
						support |= 1 << team
						if first < 0: first = team
			for b: Dictionary in buildings:
				if b.hp <= 0 or absi(b.cell.x-col) > 1 or absi(b.cell.y-row) > 1: continue
				support |= 1 << int(b.team)
				if first < 0: first = b.team
			var index := row*L.GRID_COLUMNS+col
			var owner := territory[index]
			if owner < 0 or (support & (1 << owner)) == 0: territory[index] = first

func front_column(team: int, lane: int) -> int:
	for distance: int in range(L.GRID_COLUMNS-1,-1,-1):
		var col := distance if team == 0 else L.GRID_COLUMNS-1-distance
		if territory_owner(Vector2i(col,lane)) == team: return col
	return -1

func count_buildings(team: int, kind: String = "farm") -> int:
	var n := 0
	for b: Dictionary in buildings:
		if b.hp > 0 and b.team == team and b.kind == kind: n += 1
	return n

func building_at(cell: Vector2i) -> Dictionary:
	for b: Dictionary in buildings:
		if b.hp > 0 and b.cell == cell: return b
	return {}

func multiplier() -> float:
	if night_decay and elapsed >= B.NIGHT_START: return B.NIGHT_GOLD
	return B.DUSK_GOLD if elapsed >= B.RAMP_2 else (B.NOON_GOLD if elapsed >= B.RAMP_1 else B.START_GOLD)

func production_rate(team: int) -> float:
	var rate: float = lord_mod(team,"income_mult",1.0)/B.BASE_INTERVAL
	for b: Dictionary in buildings:
		if b.team == team and b.hp > 0 and b.kind == "farm": rate += B.FARM_DROP/B.FARM_INTERVAL*farm_speed(b)
	var crystal_rate := 0.0
	for b: Dictionary in buildings:
		if b.team == team and b.hp > 0 and b.kind == "crystal": crystal_rate += B.CARDS.crystal.income/Arcane.crystal_period(b)
		if b.team == team and b.hp > 0 and b.kind == "glutton_nest" and float(b.get("digest_left",0.0)) > 0.0 and int(b.get("last_gold",0)) > 0: crystal_rate += float(b.last_gold)/maxf(1.0,float(b.get("digest_total",10.0))-float(B.CARDS.glutton_nest.bite_duration))
	return (crystal_rate+rate*multiplier()+count_buildings(team,"grave")*B.CARDS.grave.income/B.CARDS.grave.period)*float(lord_mod(team,"gold_gain_mult",1.0))

func gain_ink(team: int, amount: float) -> void:
	amount *= float(lord_mod(team,"gold_gain_mult",1.0))
	stats[team].produced += amount
	var waste: float = maxf(0,ink[team]+amount-B.MAX_INK)
	stats[team].wasted += waste
	ink[team] = minf(B.MAX_INK,ink[team]+amount)
	if waste > 0:
		add_skill_charge(team,waste) # gold that does not fit the purse charges the lord's skill
		event("overflow",L.GOLD_TEXT,team)

# Every farm boost stacks (producer 2026-11-05): a cultivating farmer x2, 豐收 x2 and each mill in the
# lane x MILL_BONUS, all multiplied together.
func farm_speed(b: Dictionary) -> float:
	var mills := 0
	for other: Dictionary in buildings:
		if other.kind == "mill" and other.hp > 0 and other.team == b.team and other.cell.y == b.cell.y: mills += 1
	return farm_speed_with(b,mills)

func farm_speed_with(b: Dictionary, mills: int) -> float:
	var speed: float = lord_mod(b.team,"farm_mult",1.0)
	if b.boost_until > elapsed: speed *= 2.0
	if b.harvest_until > elapsed: speed *= 2.0
	return speed*pow(B.MILL_BONUS,mills)

func build_lookups() -> void:
	foe_units = [[],[]]
	lane_foes = [[[],[],[],[],[]],[[],[],[],[],[]]]
	lane_foe_buildings = [[[],[],[],[],[]],[[],[],[],[],[]]]
	lane_foe_taunts = [[[],[],[],[],[]],[[],[],[],[],[]]]
	lane_mill = [[0,0,0,0,0],[0,0,0,0,0]]
	has_watchtower = [false,false]
	has_taunt = [false,false]
	wards = [[],[]]
	has_trap = false
	has_poisoned_unit = false
	has_levy = false
	has_monster_tick = false
	has_plague_bishop = false
	has_thorns_aura = [false,false]
	has_expansion_tick = false
	has_hex_unit = false
	has_borrowed_unit = false
	has_expansion_building = false
	for u: Dictionary in units:
		var against: int = 1-u.team
		foe_units[against].append(u)
		lane_foes[against][u.lane].append(u)
		if u.hp > 0:
			if int(u.get("poison_stacks",0)) > 0 or float(u.get("poison_zone_seen",-1.0)) >= 0.0: has_poisoned_unit = true
			if u.get("levy",false): has_levy = true
			if u.get("has_monster_tick",false): has_monster_tick = true
			if u.kind == "plague_bishop": has_plague_bishop = true
			if u.get("has_thorns_aura",false): has_thorns_aura[u.team] = true
			WardRules.collect(u,wards)
			if u.get("has_expansion_tick",false): has_expansion_tick = true
			if int(u.get("hex_stacks",0)) > 0 and u.get("hex_team",-1) >= 0: has_hex_unit = true
			if u.get("borrowed_until",-1.0) >= 0: has_borrowed_unit = true
	for b: Dictionary in buildings:
		var against: int = 1-b.team
		var bd: Dictionary = B.CARDS[b.kind]
		if bd.has("trap"):
			if b.hp > 0: has_trap = true
		elif not GluttonNest.hidden(b):
			lane_foe_buildings[against][b.cell.y].append(b)
		if b.kind == "scarecrow":
			lane_foe_taunts[against][b.cell.y].append(b)
			if b.hp > 0: has_taunt[against] = true
		elif b.kind == "mill" and b.hp > 0: lane_mill[b.team][b.cell.y] += 1
		elif b.kind == "watchtower" and b.hp > 0: has_watchtower[b.team] = true
		if b.hp > 0:
			if b.get("is_expansion",false): has_expansion_building = true
			if b.get("has_expansion_tick",false): has_expansion_tick = true

func farm_drop(b: Dictionary) -> void:
	gain_ink(b.team,B.FARM_DROP)
	stats[b.team].drops += 1
	event("ink",b.pos,b.team)
	ExpansionMore.granary_store(self,b)

func kind_at(team: int, slot: int) -> String:
	return home_cards[team] if slot == FARM_SLOT else decks[team][slot]

func slot_cd(team: int, slot: int) -> float:
	return farm_cd[team] if slot == FARM_SLOT else hand_cd[team][slot]

# Placement rules live in one place: play_check() says why a card cannot go here (Refusal.OK = it
# can). can_play() is the cheap yes/no the AI asks hundreds of times per decision; play_error()
# turns the reason into the sentence the player sees.
enum Refusal {OK, ENDED, PAUSED, NO_CARD, COOLDOWN, GOLD, OFF_GRID, WATER, NOT_OURS, OCCUPIED, UNIQUE, FOOTPRINT}

func play_check(team: int, slot: int, pos: Vector2) -> Refusal:
	if ended: return Refusal.ENDED
	if paused: return Refusal.PAUSED
	if (slot < 0 or slot >= 4) and slot != FARM_SLOT: return Refusal.NO_CARD
	var kind: String = kind_at(team,slot)
	if kind.is_empty() or not B.CARDS.has(kind): return Refusal.NO_CARD
	var card: Dictionary = B.CARDS[kind]
	if card.get("summon_only",false): return Refusal.NO_CARD
	if slot_cd(team,slot) > 0.00001: return Refusal.COOLDOWN
	if ink[team] < card.cost: return Refusal.GOLD
	if card.get("rolling",false):
		# Rolled from the start of a lane (the cell in front of our own gate) all the way to the enemy gate.
		var start_cell := cell_at(pos)
		if start_cell.x != (0 if team == 0 else L.GRID_COLUMNS-1) or not start_cell.y in active_lanes: return Refusal.OFF_GRID
		return Refusal.OK
	if card.type == "spell":
		var lane := int((pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y)
		if not lane in active_lanes or pos.x < L.FIELD_FRAME.position.x or pos.x > L.FIELD_FRAME.end.x:
			return Refusal.OFF_GRID
		if not Faction.play_error(self,team,kind,pos).is_empty(): return Refusal.OFF_GRID
		if not ExpansionMore.play_error(self,team,kind,pos).is_empty(): return Refusal.OFF_GRID
		return Refusal.OK
	var cell := cell_at(pos)
	if cell.x < 0 or not cell.y in active_lanes: return Refusal.OFF_GRID
	if card.type == "building" and is_water_cell(cell): return Refusal.WATER
	if territory_owner(cell) != team: return Refusal.NOT_OURS
	if card.type == "unit" and not GridRules.footprint_ok(self,team,kind,cell): return Refusal.FOOTPRINT # 佔位 cards need every cell
	if card.type == "building":
		var here := building_at(cell)
		if not here.is_empty() and (here.team != team or here.kind != kind): return Refusal.OCCUPIED
		if SealAltar.is_duplicate(self,team,kind,cell): return Refusal.UNIQUE # one 封印祭壇 per side
	return Refusal.OK

func can_play(team: int, slot: int, pos: Vector2) -> bool:
	return play_check(team,slot,pos) == Refusal.OK

# Why a card cannot go here ("" = it can). The player sees this text when a placement is refused.
func play_error(team: int, slot: int, pos: Vector2) -> String:
	var why := play_check(team,slot,pos)
	match why:
		Refusal.OK: return ""
		Refusal.ENDED: return "戰局已經結束。"
		Refusal.PAUSED: return "暫停中。"
		Refusal.NO_CARD: return "先選一張手牌。"
		Refusal.OFF_GRID: return "要放在戰場的格子上。"
		Refusal.WATER: return "水域路線無法建造建築。"
		Refusal.NOT_OURS: return "只能部署在我方領地；建築與城牆周圍八格可擴張，先佔先得。"
		Refusal.OCCUPIED: return "這格已經有別的建築；只有同一種建築可以覆蓋回血。"
		Refusal.FOOTPRINT: return "%s要佔的每一格都必須是我方領地，這裡放不下。" % B.CARDS[kind_at(team,slot)].name
		Refusal.UNIQUE: return "%s每方只能有一座；疊在原本那座上可以補滿生命。" % B.CARDS[kind_at(team,slot)].name
	var card: Dictionary = B.CARDS[kind_at(team,slot)]
	if why == Refusal.COOLDOWN: return "%s 還要冷卻 %.1f 秒。%s" % [card.name,slot_cd(team,slot),SealAltar.cooldown_note(self,team,kind_at(team,slot))]
	return "金幣不足：%s 要 %d，還差 %d。" % [card.name,card.cost,ceili(card.cost-ink[team])]

func play(team: int, slot: int, pos: Vector2) -> bool:
	if not can_play(team,slot,pos): return false
	var kind: String = kind_at(team,slot)
	var card: Dictionary = B.CARDS[kind]
	var paid: float = GoldMonster.cost(self,team,kind) # card.cost, or the whole purse for 金幣怪物
	ink[team] -= paid
	add_skill_charge(team,paid) # every gold spent also charges the lord's skill
	add_skill_charge(team,paid) # every gold spent also charges the lord's skill
	if slot == FARM_SLOT: farm_cd[team] = card.cooldown # the farmland slot never rotates
	else:
		# Replace only the played slot; the other three cards and cooldowns stay put.
		decks[team][slot] = decks[team][4]
		decks[team].remove_at(4)
		decks[team].append(kind)
		hand_cd[team][slot] = B.CARDS[decks[team][slot]].cooldown
	stats[team].plays += 1
	stats[team].used[kind] = stats[team].used.get(kind,0)+1
	stats[team].spent[kind] = stats[team].spent.get(kind,0.0)+paid
	var cell := cell_at(pos)
	if card.type == "building":
		var here := building_at(cell)
		if here.is_empty():
			var built := add_building(team,cell,kind)
			if card.get("spawn_on_build",false) and card.has("spawn_kind"):
				var cnt: int = int(card.get("spawn_count",1))
				for i: int in range(cnt):
					var u: Dictionary = spawn_unit(team,cell.y,String(card.spawn_kind),built.pos+Vector2(-24.0 if team == 0 else 24.0,(i-(cnt-1)*0.5)*12.0))
					u.card = kind
					event("summoned",u.pos,team)
		else: refresh_building(here)
	elif card.type == "unit": deploy(team,kind,cell,int(paid) if GoldMonster.pays_all(kind) else 0)
	else:
		var spell_origin: Vector2 = lords[team].pos+Vector2((1.0 if team == 0 else -1.0)*20.0,-34.0) if (lord_active[team] and float(lords[team].hp) > 0.0) else Vector2(L.gate_icon_x(team),clampf(pos.y,L.GRID_ORIGIN.y+36.0,L.GRID_ORIGIN.y+L.GRID_SIZE.y-36.0)-44.0)
		spells.append({"kind":kind,"team":team,"pos":pos,"origin":spell_origin,"delay":B.SPELL_DELAY})
	memory[1-team] = {"card":kind,"lane":cell.y if cell.y in active_lanes else clampi(int((pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,4)}
	if card.type == "unit":
		recent_lanes[team].append(cell.y)
		if recent_lanes[team].size() > 3: recent_lanes[team].pop_front()
	event("play",pos,team,{"card":kind,"slot":slot})
	ExpansionMore.on_card_played(self,team,kind,cell.y)
	CoreCards.on_card_played(self,team,kind) # 咒潮法師 tide stacks
	return true

func add_building(team: int, cell: Vector2i, kind: String) -> Dictionary:
	claim_around(team,cell)
	next_id += 1
	var data: Dictionary = B.CARDS[kind]
	var is_exp: bool = data.get("expansion",false)
	var has_exp_tick: bool = is_exp and (data.has("reveal_radius") or data.has("period"))
	var b := {"id":next_id,"serial":take_serial(),"kind":kind,"team":team,"cell":cell,"pos":L.cell_center(cell),"hp":data.hp,"max_hp":data.hp,"body_radius":B.kind_radius(kind),"expires":elapsed+data.expires if data.expires > 0 else -1.0,"boost_until":0.0,"harvest_until":0.0,"ready_at":elapsed+B.FARM_START,"production":0.0,"cd":0.0,"flash":0.0,"is_expansion":is_exp,"has_expansion_tick":has_exp_tick}
	if is_exp: has_expansion_building = true
	if has_exp_tick: has_expansion_tick = true
	buildings.append(b)
	if data.has("charges"): b.charges = data.charges
	var ups: Dictionary = card_upgrades[team].get(kind,{})
	if ups.has("hp"):
		b.max_hp = Upgrades.shifted("hp",b.max_hp,int(ups.hp))
		b.hp = b.max_hp
	for key: String in ["damage","area_damage","explosion_damage","thorns","interval"]:
		if ups.has(key) and data.has(key):
			b[key] = Upgrades.shifted(Upgrades.table_name_for(kind,key),float(data[key]),int(ups[key]))
	if kind == "farm": stats[team].planted += 1
	return b

func spell_card_data(team: int, kind: String) -> Dictionary:
	var ups: Dictionary = card_upgrades[team].get(kind,{})
	return Upgrades.spell_data(kind,ups) if not ups.is_empty() else B.CARDS[kind]

# Placing the same building on our own one restores it: full health and a fresh lifetime.
# A farm keeps its production timer and any cultivation boost.
func refresh_building(b: Dictionary) -> void:
	var data: Dictionary = B.CARDS[b.kind]
	b.hp = b.max_hp
	if data.has("charges"): b.charges = data.charges
	if data.expires > 0: b.expires = elapsed+data.expires
	if b.kind == "bonewall": b.thresholds_spawned = 0
	stats[b.team].repairs = stats[b.team].get("repairs",0)+1
	event("heal",b.pos,b.team)

# Fields a unit card: one troop type, a mixed legion ("members"), or the same squad in three
# adjacent lanes ("spread"; shifted inward at the edge lanes). Troops behind the front stand back.
func deployment_column(team: int, lane: int, requested: int) -> int:
	var direction := -1 if team == 0 else 1
	var col := requested
	while col >= 0 and col < L.GRID_COLUMNS:
		if territory_owner(Vector2i(col,lane)) == team: return col
		col += direction
	return front_column(team,lane)

func deploy(team: int, kind: String, cell: Vector2i, gold: int = 0) -> void:
	var card: Dictionary = B.CARDS[kind]
	var groups: Array = card.get("members",[[kind,card.get("count",1),0.0]]).duplicate(true)
	if gold > 0: GoldMonster.shape(groups,gold) # 金幣怪物: bodies depend on the gold paid
	var swarm: Dictionary = lord_mod(team,"swarm",{})
	for group: Array in groups: group[1] += int(swarm.get(group[0],swarm.get("*",0)))
	var front_offset := 0.0
	for group: Array in groups: front_offset = minf(front_offset,group[2])
	var lanes: Array = [cell.y]
	if card.get("spread",false):
		var middle := clampi(cell.y,1,3)
		lanes = [middle-1,middle,middle+1]
	# Legion members march at their own speeds (producer 2026-11-19: no forced common pace).
	if GridRules.footprint(kind) != Vector2i(1,1) and GridRules.footprint_ok(self,team,kind,cell):
		# Multi-cell cards (佔位): play_check already required every covered cell to be ours, so each
		# share lands exactly on its cell; nothing is shifted inward or back. (A lord skill summoning the
		# card where the formation does not fit falls back to the single-cell squad below.)
		var cells: Dictionary = {}
		for p: Dictionary in GridRules.plan(kind,cell,team,groups):
			var at := Vector2i(p.col,p.lane)
			if not cells.has(at): cells[at] = []
			cells[at].append([p.kind,p.count,p.offset])
		var order: Dictionary = {}
		for at: Vector2i in cells:
			order[at.y] = spawn_groups(team,kind,at.y,at.x,cells[at],0.0,gold,int(order.get(at.y,0)))
		return
	for lane: int in lanes:
		if not lane in active_lanes: continue
		var col := deployment_column(team,lane,cell.x)
		if col < 0: continue
		spawn_groups(team,kind,lane,col,groups,front_offset,gold,0)

# One squad in one cell: placed at the rear of the cell (mirrored for blue) so enemies inside it stay in
# front of the freshly deployed interceptors. Each lane counts its own spawn order, so a multi-lane squad
# steps out in all lanes at once. Returns the next spawn index for that lane.
func spawn_groups(team: int, kind: String, lane: int, col: int, groups: Array, front_offset: float, gold: int, n: int) -> int:
	var card: Dictionary = B.CARDS[kind]
	var forward := 1.0 if team == 0 else -1.0
	var spot := L.cell_center(Vector2i(col,lane))-Vector2(forward*(L.CELL_SIZE.x*0.5-12.0),0)
	for group: Array in groups:
		for i: int in range(group[1]):
			var spawn_pos := spot-Vector2(forward*(group[2]-front_offset),0)
			spawn_pos.x = clampf(spawn_pos.x,L.GRID_ORIGIN.x+12.0,L.GRID_ORIGIN.x+L.GRID_SIZE.x-12.0)
			var u := spawn_unit(team,lane,group[0],spawn_pos)
			u.spawn_delay = n*0.12
			u.card = kind
			if gold > 0: GoldMonster.apply(u,gold,card_upgrades[team].get(kind,{}),i,int(group[1]))
			elif card_upgrades[team].has(kind): Upgrades.apply_unit(u,kind,card_upgrades[team][kind])
			n += 1
	return n

func spawn_unit(team: int, lane: int, kind: String, pos: Vector2) -> Dictionary:
	if not lane in active_lanes:
		lane = active_lanes[0]
		pos.y = L.cell_center(Vector2i(0,lane)).y
	next_id += 1
	var data: Dictionary = B.CARDS[kind]
	var hp: float = data.hp
	var toughen: Array = lord_mod(team,"toughen",[])
	if kind in toughen or "*" in toughen:
		var at: int = B.TIERS.hp.find(hp)
		if at > 0: hp = B.TIERS.hp[maxi(B.tier_index("SS"),at-1)]
	var mt: bool = data.has("roar_fear") or data.has("reveal_radius")
	var ta: bool = data.has("thorns_aura")
	var et: bool = data.get("expansion",false) and (data.has("reveal_radius") or data.has("period"))
	var u := {"id":next_id,"serial":take_serial(),"kind":kind,"team":team,"lane":lane,"pos":pos,"hp":hp,"max_hp":hp,"body_radius":B.kind_radius(kind),"cd":0.0,"phase":rng.randf()*TAU,"face":1.0 if team == 0 else -1.0,"worked":[],"work_id":-1,"work_left":0.0,"spawn_delay":0.0,"charged":false,"expansion_charged":false,"march_time":0.0,"revealed":false,"flash":0.0,"heal_cd":0.0,"dy":rng.randf_range(-B.PLACE_JITTER,B.PLACE_JITTER),"has_monster_tick":mt,"has_thorns_aura":ta,"has_expansion_tick":et}
	if mt: has_monster_tick = true
	if kind == "plague_bishop": has_plague_bishop = true
	if ta: has_thorns_aura[team] = true
	if et: has_expansion_tick = true
	units.append(u)
	u.phased = data.get("phase",false)
	u.stealthed = data.get("stealth",false) or u.phased
	u.flying = data.get("flying",false)
	u.armor = data.get("armor",0.0)
	u.summon_left = float(data.get("summon_interval",0.0)) # deploys with its escort formation; periodic summons start after summon_interval
	if kind == "drummer":
		u.drum_cd = data.get("inspire_period",10.0)
		trigger_drum(u)
	Monster.on_spawn(self,u)
	return u

func trigger_drum(u: Dictionary) -> void:
	var dur: float = B.CARDS.drummer.get("inspire_duration",3.0)
	team_drum_until[u.team] = maxf(team_drum_until[u.team],elapsed+dur)
	team_drums[u.team] = team_drums[u.team].filter(func(t: float) -> bool: return t > elapsed)
	team_drums[u.team].append(elapsed+dur)
	event("drum",u.pos,u.team,{"duration":dur})

func knockback_unit(u: Dictionary, delta_x: float) -> void:
	if u.hp <= 0 or u.has("cell") or u.get("kind","") == "lord": return
	u.pos.x = clampf(u.pos.x+delta_x,L.gate_stop(0)+10.0,L.gate_stop(1)-10.0)
	Windup.cancel(u)
	u.march_time = 0.0

func effective_armor(target: Dictionary) -> float:
	var base_armor: float = target.get("armor",0.0)
	var buff_armor: float = target.get("expansion_armor",0.0) if target.get("armor_until",0.0) > elapsed else 0.0
	return base_armor+buff_armor

func damage(target: Dictionary, amount: float, team: int, kind: String, source: Dictionary = {}, sacrifice: bool = false) -> void:
	if target.hp <= 0 or GluttonNest.hidden(target): return
	if amount <= 0: return
	if not sacrifice:
		amount *= 1.0-Arcane.resonance(self,target)
		var total_armor := effective_armor(target)
		var ignore_armor: bool = B.CARDS.get(source.get("kind",""),{}).get("ignore_armor",false) or B.CARDS.get(kind,{}).get("ignore_armor",false)
		if total_armor > 0 and not ignore_armor: amount = maxf(1.0,amount-total_armor)
		amount = Expansion.absorb(self,target,amount,source)
		amount = ExpansionMore.absorb(target,amount,kind)
		amount = Faction.absorb(self,target,amount)
		if target.get("terror_until",-1.0) > elapsed: amount *= float(target.get("terror_mult",1.0)) # 恐懼嚎叫 破膽
		amount = WardRules.share(self,target,amount,team,kind,source) # 結界護衛 takes a share
		if amount <= 0: return
	var dealt := minf(amount,target.hp)
	target.hp -= amount
	if not sacrifice: ExpansionMore.after_hit(self,target,dealt,source)
	if not sacrifice:
		LordExpansion.drain(self,source,dealt,target.pos)
		Arcane.blink(self,target)
		Faction.on_hit(self,target,source)
		Monster.on_hit(self,target,source)
	if target.kind == "lord":
		target.last_hit = elapsed
		if target.hp <= 0: target.respawn = B.LORD_RESPAWN
	target.flash = 0.08
	if B.CARDS.get(target.kind,{}).has("burst_step"): giant_burst(target)
	if target.kind == "bonewall":
		var hp_lost: float = target.max_hp - maxf(0.0, target.hp)
		var threshold_reached: int = clampi(int(hp_lost / (target.max_hp * 0.2)), 0, 5)
		var spawned: int = target.get("thresholds_spawned", 0)
		while spawned < threshold_reached:
			spawned += 1
			var forward := 1.0 if target.team == 0 else -1.0
			var spawn_pos: Vector2 = target.pos - Vector2(forward * 45.0, 0.0)
			spawn_pos.x = clampf(spawn_pos.x, L.GRID_ORIGIN.x, L.GRID_ORIGIN.x + L.GRID_SIZE.x)
			for k: int in range(2): # producer 2026-11-05: two per step
				var skel := spawn_unit(target.team, target.cell.y, "skeleton", spawn_pos+Vector2(0,(k-0.5)*14))
				skel.card = "bonewall"
				event("summoned", skel.pos, skel.team)
				link(target.pos, skel.pos, target.team, "summon")
		target.thresholds_spawned = spawned
	if not sacrifice: stats[team].damage[kind] = stats[team].damage.get(kind,0.0)+dealt
	event("hit",target.pos,target.team,{"attacker":kind,"target":target.kind})
	if target.hp <= 0 and not sacrifice: DarkSorcery.rescue(self,target)
	if target.has("cell") and target.team == 0: building_alarm[target.cell.y] = 1.5
	if target.hp <= 0:
		if target.has("serial"):
			serials_in_use.erase(target.serial)
			# Clear the released number: later cleanup must not free a number reused by a summon.
			var old_serial: int = target.serial
			target.serial = 0
			if not target.has("cell"):
				if B.CARDS[target.kind].has("resonance"):
					death_queue.append({"explosion":true,"pos":target.pos,"team":target.team,"kind":target.kind})
				death_queue.append({"lane":target.lane,"pos":target.pos,"team":target.team,"kind":target.kind,"serial":old_serial,"poison_team":team if kind == "plague" and not B.poison_immune(target) else -1,"curse_team":target.get("curse_team",-1) if (target.get("cursed",false) or target.get("cursed_until",0.0) > elapsed) else -1,"spawn":B.CARDS[target.kind].get("on_death_spawn",[]),"card":target.get("card",target.kind),"death_refund":0.0 if sacrifice else float(target.get("death_refund",0.0))})
		if target.has("cell"):
			refresh_territory()
			if target.kind == "granary": ExpansionMore.release_granary(self,target)
			var b_spawn: Array = B.CARDS.get(target.kind,{}).get("on_death_spawn",[])
			if not b_spawn.is_empty():
				var b_cnt: int = int(b_spawn[1])
				for k: int in range(b_cnt):
					var child: Dictionary = spawn_unit(target.team,target.cell.y,String(b_spawn[0]),target.pos+Vector2(0.0,(k-(b_cnt-1)*0.5)*12.0))
					child.card = target.kind
					event("summoned",child.pos,child.team)
					link(target.pos,child.pos,target.team,"summon")
			if target.kind == "sleepless_belfry":
				ExpansionMore.support(self,target,B.CARDS.sleepless_belfry)
		if target.kind == "farm" and elapsed < 180.0: stats[target.team].farms_lost_early += 1
		var art_kind: String = "lord_"+target.lord if target.kind == "lord" else target.kind
		var face: float = target.get("face",1.0 if target.team == 0 else -1.0)
		if target.has("cell"): face = 1.0
		var visual_pos: Vector2 = target.pos+Vector2(0,target.get("dy",0.0))
		event("death",visual_pos,target.team,{"card":target.kind,"art_kind":art_kind,"face":face})
		if target.kind == "farm" and kind == "fire":
			stats[target.team].burned += 1
			event("burn",target.pos,target.team)
		if not target.has("cell") and target.kind != "lord" and not target.get("summoned",false):
			var bounty := float(lord_mod(1-target.team,"kill_bounty",0.0))
			if bounty > 0: gain_ink(1-target.team,bounty)
			RelicTriggers.on_kill(self,1-target.team)

func gate_credit_card(kind: String, source: Dictionary) -> String:
	if not source.is_empty():
		var sk: String = source.get("kind","")
		if B.CARDS.has(sk): return sk
	return kind if B.CARDS.has(kind) else ""

func hit_gate(side: int, lane: int, amount: float, kind: String = "militia", source: Dictionary = {}) -> void:
	if gates[side][lane] <= 0: return # already open; the attackers just walk in
	amount *= maxf(0.1,1.0-float(lord_mod(side,"gate_armor",0.0)))
	var src_key: String = source.get("kind","")
	var atk_data: Dictionary = B.CARDS.get(src_key if not src_key.is_empty() else kind,{})
	var ignore_armor: bool = atk_data.get("ignore_armor",false) or B.CARDS.get(kind,{}).get("ignore_armor",false)
	if B.GATE_ARMOR > 0.0 and not ignore_armor: amount = maxf(1.0,amount-B.GATE_ARMOR)
	if atk_data.get("type","") != "spell" and is_ranged_attacker(atk_data): amount *= 0.5
	var dealt: float = minf(gates[side][lane],amount)
	gates[side][lane] = maxf(0,gates[side][lane]-amount)
	var thorns := float(lord_mod(side,"thorns_gate",0.0))
	var src_data: Dictionary = B.CARDS.get(source.get("kind",""),{})
	if thorns > 0 and not source.is_empty() and source.get("hp",0.0) > 0 and not source.has("cell") and not src_data.get("projectile",false) and not src_data.get("lob",false):
		damage(source,thorns,side,"barricade")
	LordExpansion.drain(self,source,dealt,Vector2(L.gate_stop(side),L.cell_center(Vector2i(0,lane)).y))
	Monster.on_gate_hit(self,source)
	var credit := gate_credit_card(kind,source)
	if dealt > 0.0 and not credit.is_empty():
		stats[1-side].gate_damage[credit] = stats[1-side].gate_damage.get(credit,0.0)+dealt
	if gates[side][lane] == 0: refresh_territory()
	if gates[side][lane] == 0 and first_breach < 0: first_breach = elapsed
	if gates[side][lane] == 0:
		if not credit.is_empty(): stats[1-side].breach_card = credit
		RelicTriggers.on_gate_fall(self,side,lane)
		event("breach",Vector2(L.gate_icon_x(side),L.cell_center(Vector2i(0,lane)).y),1-side,{"lane":lane})
	stats[1-side].damage[kind] = stats[1-side].damage.get(kind,0.0)+dealt
	if side == 0: alarm[lane] = 1.5

func grave_drop(b: Dictionary) -> void:
	b.production = 0.0 # death acceleration never carries over into the next cycle
	gain_ink(b.team,B.CARDS.grave.income)
	event("ink",b.pos,b.team)

func add_zone(pos: Vector2, team: int, radius: float, duration: float, rect: Rect2 = Rect2(), dmg: float = -1.0) -> void:
	var tick_dmg: float = dmg if dmg >= 0.0 else float(B.CARDS.plague.tick_damage)
	zones.append({"pos":pos,"team":team,"radius":radius,"rect":rect,"damage":tick_dmg,"left":duration,"tick":B.CARDS.plague.tick_interval})

func add_plague_stack(u: Dictionary, team: int, dmg: float, dt: float) -> void:
	if u.hp <= 0 or B.poison_immune(u): return
	var interval: float = B.CARDS.plague.tick_interval
	var prev: int = int(u.get("poison_stacks",0))
	u.poison_stacks = prev+1
	u.poison_team = team
	u.poison_damage = maxf(float(u.get("poison_damage",0.0)),dmg) if prev > 0 else dmg
	u.poison_left = interval*2.0+dt
	if prev == 0: u.poison_timer = dt
	has_poisoned_unit = true

func update_zones(dt: float) -> void:
	if zones.is_empty() and not has_poisoned_unit: return
	if not zones.is_empty():
		var z_count := zones.size()
		var z_expired := false
		for zi: int in range(z_count):
			var zone: Dictionary = zones[zi]
			var active := minf(dt,zone.left)
			zone.left -= dt
			if zone.left <= 0.000001: z_expired = true
			zone.tick -= active
			var zrect: Rect2 = zone.get("rect",Rect2())
			var use_rect := zrect.size != Vector2.ZERO
			var zdmg: float = float(zone.get("damage",B.CARDS.plague.tick_damage))
			while zone.tick <= 0.000001:
				zone.tick += B.CARDS.plague.tick_interval
				for u: Dictionary in units:
					if u.hp > 0 and u.team != zone.team and not B.poison_immune(u) and (B.rect_hits_actor(zrect,u) if use_rect else B.point_edge_distance(zone.pos,u) <= zone.radius):
						add_plague_stack(u,zone.team,zdmg,dt)
			for u: Dictionary in units:
				if u.hp > 0 and u.team != zone.team and not B.poison_immune(u) and (B.rect_hits_actor(zrect,u) if use_rect else B.point_edge_distance(zone.pos,u) <= zone.radius):
					has_poisoned_unit = true
					u.poison_zone_seen = elapsed
					u.poison_zone_team = zone.team
					u.poison_zone_damage = zdmg
		if z_expired:
			zones = zones.filter(func(z: Dictionary) -> bool: return z.left > 0.000001)

	if not has_poisoned_unit: return
	var interval: float = B.CARDS.plague.tick_interval
	for u: Dictionary in units:
		if u.hp <= 0: continue
		if float(u.get("poison_zone_seen",-1.0)) >= 0.0 and u.poison_zone_seen < elapsed:
			u.poison_zone_seen = -1.0
			if int(u.get("poison_stacks",0)) == 0:
				u.poison_stacks = 1
				u.poison_team = u.get("poison_zone_team",-1)
				u.poison_damage = float(u.get("poison_zone_damage",B.CARDS.plague.tick_damage))
				u.poison_timer = interval+dt
				u.poison_left = interval*2.0+dt
		if int(u.get("poison_stacks",0)) > 0:
			u.poison_timer = u.get("poison_timer",interval)-dt
			while u.poison_timer <= 0.000001 and int(u.get("poison_stacks",0)) > 0:
				u.poison_timer += interval
				damage(u,float(u.get("poison_damage",B.CARDS.plague.tick_damage))*float(u.poison_stacks),u.poison_team,"plague")
				if u.hp <= 0: break
			if u.hp > 0:
				u.poison_left = float(u.get("poison_left",0.0))-dt
				if u.poison_left <= 0.000001:
					u.poison_stacks = 0
					u.poison_left = 0.0
					u.poison_team = -1

func resolve_deaths() -> void:
	# Append-only during processing: explosions may add more deaths, in deterministic order.
	var index := 0
	while index < death_queue.size():
		var dead: Dictionary = death_queue[index]
		index += 1
		if dead.get("explosion",false):
			var explosion_kind: String = dead.get("kind","bonewall")
			var explosion: Dictionary = B.CARDS[explosion_kind]
			for u: Dictionary in units:
				if u.hp > 0 and u.team != dead.team and B.blast_hits(dead.pos,String(explosion.get("blast","square")),1 if dead.team == 0 else -1,u):
					damage(u,explosion.explosion_damage,dead.team,explosion_kind)
			event("boneburst",dead.pos,dead.team)
			continue
		Faction.on_death(self,dead)
		Expansion.on_death(self,dead)
		ExpansionMore.on_death(self,dead)
		SealAltar.on_death(self,dead)
		var refund: float = float(dead.get("death_refund",0.0))
		if refund > 0.0:
			gain_ink(dead.team,refund)
			event("ink",dead.pos,dead.team)
		for b: Dictionary in buildings:
			if b.hp > 0 and b.kind == "grave" and b.cell.y == dead.lane:
				link(dead.pos,b.pos,b.team,"soul")
				b.production += B.CARDS.grave.death_advance
				if b.production >= B.CARDS.grave.period: grave_drop(b)
		for u: Dictionary in units:
			if u.hp <= 0 or u.kind != "ghoul" or B.edge_distance(u,dead) > B.CARDS.ghoul.radius: continue
			link(dead.pos,u.pos,u.team,"devour")
			u.hp = minf(u.max_hp,u.hp+B.CARDS.ghoul.devour_heal)
			var tier_index: int = B.TIERS.damage.find(u.get("damage",B.CARDS.ghoul.damage))
			u.damage = B.TIERS.damage[maxi(B.tier_index(B.CARDS.ghoul.max_damage_tier),tier_index-1)]
			event("heal",u.pos,u.team)
		if dead.poison_team >= 0:
			add_zone(dead.pos,dead.poison_team,B.CARDS.plague.spread_radius,B.CARDS.plague.spread_duration)
		# Resolve after the original death fed the economy; the new troops are independent.
		if not dead.spawn.is_empty():
			for i: int in range(dead.spawn[1]):
				var child := spawn_unit(dead.team,dead.lane,dead.spawn[0],dead.pos)
				child.card = dead.card
				event("summoned",child.pos,child.team)
		if dead.curse_team >= 0:
			var child := spawn_unit(dead.curse_team,dead.lane,"skeleton",dead.pos)
			child.card = "curse"
			event("summoned",child.pos,child.team)
			event("curse_rise",child.pos,child.team)
			link(dead.pos,child.pos,dead.curse_team,"curse")
	death_queue.clear()

func reaper_target(u: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	for other: Dictionary in lane_foes[u.team][u.lane]+lane_foe_buildings[u.team][u.lane]:
		if other.hp <= 0 or other.get("stealthed",false) or B.edge_distance(u,other) > B.CARDS.reaper.range: continue
		if (other.pos.x-u.pos.x)*u.face < 0: continue
		if found.is_empty() or other.serial < found.serial: found = other
	if found.is_empty():
		var forward_lords: Array = lords.filter(func(l: Dictionary) -> bool: return (l.pos.x-u.pos.x)*u.face >= 0)
		return nearest(u.pos,u.team,54.0,forward_lords,-1,true,B.actor_radius(u))
	return found

# Lord skills cost no gold (2026-11-19): they cast free once the charge meter is full. Spending gold
# and gold lost to a full purse both fill it.
func skill_need(team: int) -> float:
	return B.skill_charge_need(lords[team].lord,float(lord_mod(team,"skill_discount",0.0)))

func add_skill_charge(team: int, amount: float) -> void:
	if skill_cd[team] > 0.0: return # no charging while the skill cools down (producer 2026-11-19)
	amount = RelicTriggers.charge_gain(self,team,amount)
	if amount > 0.0: skill_charge[team] = minf(skill_need(team),skill_charge[team]+amount)

func skill_charged(team: int) -> bool:
	return skill_charge[team] >= skill_need(team)-0.00001

# Why the lord's skill cannot be cast now ("" = it can).
func skill_error(team: int) -> String:
	if ended: return "戰局已經結束。"
	if paused: return "暫停中。"
	if not B.has_skill(lords[team].lord): return "這位領主沒有技能。"
	var info: Dictionary = B.lord_data(lords[team].lord)
	if lords[team].hp <= 0: return "領主倒下了，復活後才能發動%s。" % info.skill
	if skill_cd[team] > 0.00001: return "%s還要冷卻 %d 秒。" % [info.skill,ceili(skill_cd[team])]
	if lords[team].lord == "underworld" and count_buildings(team,"grave") == 0: return "沒有墓碑"
	if lords[team].lord == "iron" and iron_tower_cells(team).is_empty(): return "領地內沒有空格可建箭樓。"
	if lords[team].lord == "rune" and LordExpansion.rune_cells(self,team).is_empty(): return "領地內沒有可召喚法陣的空格。"
	if B.is_minion(lords[team].lord) and info.get("skill_card","") == "levy" and Faction.intruders(self,team).is_empty(): return "領地內沒有敵軍。"
	if not skill_charged(team): return "充能不足：%s還差 %d（花費金幣或金幣溢出時充能）。" % [info.skill,ceili(skill_need(team)-skill_charge[team])]
	return ""

func _minion_lane_priority(team: int) -> Array[int]:
	var dir := 1.0 if team == 0 else -1.0
	var home_x := L.gate_stop(team)
	var scored: Array = []
	for lane: int in active_lanes:
		var best_threat := -INF
		for u: Dictionary in units:
			if u.hp > 0 and u.team != team and u.lane == lane and u.get("spawn_delay",0.0) <= 0:
				best_threat = maxf(best_threat,-(u.pos.x-home_x)*dir)
		scored.append({"lane":lane,"score":best_threat})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a.score,b.score): return a.score > b.score
		return absi(a.lane-2) < absi(b.lane-2))
	var out: Array[int] = []
	for entry: Dictionary in scored: out.append(int(entry.lane))
	return out

func _minion_open_cell(team: int) -> Vector2i:
	for lane: int in _minion_lane_priority(team):
		var col := front_column(team,lane)
		if col < 0: continue
		var step_back := -1 if team == 0 else 1
		var c := col
		while c >= 0 and c < L.GRID_COLUMNS:
			var cell := Vector2i(c,lane)
			if territory_owner(cell) == team and building_at(cell).is_empty(): return cell
			c += step_back
	return Vector2i(-1,-1)

func _minion_spell_target(team: int, card_kind: String) -> Vector2:
	var cdata: Dictionary = B.CARDS[card_kind]
	var radius: float = float(cdata.get("radius",100.0))
	if card_kind == "levy":
		var foes := Faction.intruders(self,team)
		if not foes.is_empty(): return foes[0].pos
	if card_kind in B.FRIENDLY_SPELLS:
		var pref_kind := "farm" if card_kind == "harvest" else ("crystal" if card_kind == "mana_spring" else "")
		if not pref_kind.is_empty():
			for b: Dictionary in buildings:
				if b.hp > 0 and b.team == team and b.kind == pref_kind: return b.pos
		var best_pos: Vector2 = lords[team].pos
		var best_score := -1.0
		for a: Dictionary in units:
			if a.hp <= 0 or a.team != team: continue
			var s := 0.0
			for o: Dictionary in units:
				if o.hp > 0 and o.team == team and B.spell_hits_actor(a.pos,cdata,o): s += 1.0
			if s > best_score:
				best_score = s
				best_pos = a.pos
		return best_pos
	var rolling: bool = cdata.get("rolling",false)
	var best_foe_pos := Vector2.ZERO
	var best_foe_score := -1.0
	for t: Dictionary in units:
		if t.hp <= 0 or t.team == team or t.get("spawn_delay",0.0) > 0: continue
		var s := 0.0
		for o: Dictionary in units+buildings:
			if o.hp <= 0 or o.team == team: continue
			if rolling:
				if o.get("lane",o.get("cell",Vector2i(-1,-1)).y) == t.lane: s += 1.0
			elif B.spell_hits_actor(t.pos,cdata,o): s += 1.0
		if s > best_foe_score:
			best_foe_score = s
			best_foe_pos = t.pos
	if best_foe_score > 0.0: return best_foe_pos
	for b: Dictionary in buildings:
		if b.hp > 0 and b.team != team: return b.pos
	return L.cell_center(Vector2i(L.GRID_COLUMNS/2,active_lanes[0]))

func _cast_minion_skill(team: int, kind: String, visual_targets: Array[Vector2]) -> void:
	var info: Dictionary = B.lord_data(kind)
	var card_kind: String = info.skill_card
	match info.skill_kind:
		"unit":
			var order := _minion_lane_priority(team)
			var count := int(info.get("summon_count",1))
			for i: int in range(count):
				var lane: int = order[i % order.size()]
				var col: int = front_column(team,lane)
				if col < 0: col = 0 if team == 0 else L.GRID_COLUMNS-1
				var cell := Vector2i(col,lane)
				deploy(team,card_kind,cell)
				visual_targets.append(L.cell_center(cell))
		"spell":
			var target_pos := _minion_spell_target(team,card_kind)
			var spell_origin: Vector2 = lords[team].pos+Vector2((1.0 if team == 0 else -1.0)*20.0,-34.0)
			spells.append({"kind":card_kind,"team":team,"pos":target_pos,"origin":spell_origin,"delay":B.SPELL_DELAY})
			visual_targets.append(target_pos)
		"building":
			var cell := _minion_open_cell(team)
			if cell.x >= 0:
				add_building(team,cell,card_kind)
				visual_targets.append(L.cell_center(cell))
			for b: Dictionary in buildings:
				if b.hp <= 0 or b.team != team: continue
				var heal_amt: float = b.max_hp*0.25
				if b.hp < b.max_hp:
					b.hp = minf(b.max_hp,b.hp+heal_amt)
					event("repair",b.pos,team)
				if visual_targets.size() < 3 and b.cell != cell: visual_targets.append(b.pos)

func cast_skill(team: int) -> bool:
	if not skill_error(team).is_empty(): return false
	skill_charge[team] = 0.0
	skill_cd[team] = B.skill_cooldown(lords[team].lord)
	RelicTriggers.on_cast(self,team)
	var kind: String = lords[team].lord
	stats[team].skills = stats[team].get("skills",0)+1
	var visual_targets: Array[Vector2] = []
	if B.is_minion(kind):
		_cast_minion_skill(team,kind,visual_targets)
		event("skill",lords[team].pos,team,{"lord":kind,"targets":visual_targets})
		return true
	match kind:
		"rune": visual_targets = LordExpansion.cast_runes(self,team)
		"vampire":
			vampire_until[team] = elapsed+B.LORDS.vampire.blood_duration
			for u: Dictionary in units:
				if u.team == team and u.hp > 0: visual_targets.append(u.pos)
		"mage":
			time_stop_team = team
			time_stop_left = B.LORDS.mage.freeze_duration
			time_stop_origin = lords[team].pos
		"underworld":
			for b: Dictionary in buildings:
				if b.hp <= 0 or b.team != team or b.kind != "grave": continue
				for i: int in range(B.LORDS.underworld.summon_count):
					var u := spawn_unit(team,b.cell.y,"skeleton",b.pos)
					u.card = "skill"
					u.spawn_delay = i*0.12
				if record_events: visual_targets.append(b.pos)
		"adventure":
			preload("res://hero_slash.gd").cast(self,team)
		"lion":
			# One knight per lane spawned from home gate, marching slowly.
			for lane: int in active_lanes:
				var gate_cell := Vector2i(0 if team == 0 else L.GRID_COLUMNS - 1, lane)
				if territory_owner(gate_cell) != team: continue
				var u := spawn_unit(team,lane,"knight",L.spawn_position(team,lane))
				u.card = "skill"
				u.march = B.LION_KNIGHT_SPEED
				if record_events: visual_targets.append(u.pos)
		"beast":
			# Summon at the foremost owned cell on each active lane, for either side.
			for lane: int in active_lanes:
				var col := front_column(team,lane)
				if col < 0: continue
				var origin := L.cell_center(Vector2i(col,lane))
				for i: int in range(B.LORDS.beast.pack_count):
					var u := spawn_unit(team,lane,B.LORDS.beast.pack_kind,origin)
					u.card = "skill"
					u.spawn_delay = i*0.12
				if record_events: visual_targets.append(origin)
		"harvest":
			# A farm in each lane (front-most free home cell), then every farm healed (no extra yield).
			for lane: int in active_lanes:
				for col: int in range(L.GRID_COLUMNS):
					var cell := Vector2i(col if team == 0 else 8-col,lane)
					if territory_owner(cell) == team and building_at(cell).is_empty():
						add_building(team,cell,"farm")
						break
			for b: Dictionary in buildings:
				if b.team == team and b.kind == "farm" and b.hp > 0:
					b.hp = b.max_hp
					if record_events: visual_targets.append(b.pos)
		"iron":
			# 箭樓築城 (producer 2026-11-19): two 箭樓 on random empty cells of our territory.
			var free: Array[Vector2i] = iron_tower_cells(team)
			for i: int in range(mini(int(B.LORDS.iron.tower_count),free.size())):
				var cell: Vector2i = free[rng.randi_range(0,free.size()-1)]
				free.erase(cell)
				var tower: Dictionary = add_building(team,cell,"tower")
				if record_events: visual_targets.append(tower.pos)
	event("skill",lords[team].pos,team,{"lord":kind,"targets":visual_targets})
	return true

# Empty land cells we own, in a fixed order (the skill draws from them with the battle rng).
func iron_tower_cells(team: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for lane: int in active_lanes:
		for col: int in range(L.GRID_COLUMNS):
			var cell := Vector2i(col,lane)
			if territory_owner(cell) == team and building_at(cell).is_empty() and not is_water_cell(cell): cells.append(cell)
	return cells

func finish(side: int) -> void:
	ended = true
	winner = side
	# A win during 時空凝滯 lifts the freeze at once: net play stops stepping an ended match, so the freeze
	# never ran out and the locked result screen hung (2026-11-18). Both peers run this, so they stay in sync.
	time_stop_left = 0.0
	time_stop_team = -1
	event("finish",Vector2(800,450),side)

# Serial numbers (序號, producer 2026-10-30), like Plants vs. Zombies: every unit and building gets
# the lowest serial no living thing holds (one pool for both sides); when it dies its serial is free
# again for the next one. "id" stays unique for the whole match and is only for bookkeeping.
# At the same distance (within SERIAL_TIE px) the higher serial is attacked first.
const SERIAL_TIE := 0.5

func take_serial() -> int:
	var n := 1
	while serials_in_use.has(n): n += 1
	serials_in_use[n] = true
	return n

func _nearest_dir(pos: Vector2, team: int, radius: float, candidates: Array, can_hit_flying: bool, source_radius: float, dir: float, min_dx: float, prefer_kind: String = "") -> Dictionary:
	if candidates.is_empty(): return {}
	var found: Dictionary = {}
	var best := radius
	for other: Dictionary in candidates:
		if other.team == team or other.hp <= 0 or other.get("stealthed",false) or (other.kind == "glutton_nest" and GluttonNest.hidden(other)): continue
		if not can_hit_flying and other.get("flying",false): continue
		if not prefer_kind.is_empty() and other.kind != prefer_kind: continue
		var dx: float = (other.pos.x-pos.x)*dir
		if dx < min_dx: continue
		var orad: float = float(other.body_radius) if other.has("body_radius") else B.actor_radius(other)
		if dx - source_radius - orad > radius: continue
		var d := maxf(0.0,pos.distance_to(other.pos)-source_radius-orad)
		if d > radius: continue
		if found.is_empty() or d < best-SERIAL_TIE or (d <= best+SERIAL_TIE and other.get("serial",-1) > found.get("serial",-1)):
			found = other
			best = minf(best,d) if absf(d-best) <= SERIAL_TIE else d
	return found

func nearest(pos: Vector2, team: int, radius: float, candidates: Array, lane: int = -1, can_hit_flying: bool = true, source_radius: float = 0.0) -> Dictionary:
	var found: Dictionary = {}
	var best := radius
	for other: Dictionary in candidates:
		if other.team == team or other.hp <= 0 or other.get("stealthed",false) or GluttonNest.hidden(other): continue
		if not can_hit_flying and other.get("flying",false): continue
		if lane >= 0 and other.get("lane",other.get("cell",Vector2i(-1,-1)).y) != lane: continue
		var d := maxf(0.0,pos.distance_to(other.pos)-source_radius-B.actor_radius(other))
		if d > radius: continue
		if found.is_empty() or d < best-SERIAL_TIE or (d <= best+SERIAL_TIE and other.get("serial",-1) > found.get("serial",-1)):
			found = other
			best = minf(best,d) if absf(d-best) <= SERIAL_TIE else d
	return found

# Movement and attacks share frontmost-then-nearest priority.
# Lords only strike foes in the lane they stand in (producer 2026-11-19).
func lord_lane(lord: Dictionary) -> int:
	return clampi(floori((lord.pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,L.GRID_ROWS-1)

func lord_target(lord: Dictionary) -> Dictionary:
	return Lord.AI.select_target(lord,lane_foes[lord.team][lord_lane(lord)],B.lord_attack_range(lord.lord))

func shoot_lord(lord: Dictionary, target: Dictionary, amount: float) -> void:
	shoot(lord,target,amount)
	if not projectiles.is_empty():
		projectiles[projectiles.size()-1].visual_kind = B.lord_projectile_kind(lord.lord)

func _execute_unit_strike(u: Dictionary, target: Dictionary, data: Dictionary) -> void:
	Arcane.reveal(self,u,false)
	u.march_time = 0.0
	u.strike_seq = u.get("strike_seq",0)+1
	var amount: float = ExpansionMore.modify_attack(self,u,target,Expansion.attack_damage(self,u,target,u.get("damage",data.damage)))
	if u.kind == "ox" and target.has("cell"): amount *= B.OX_BUILDING_BONUS # 耕牛 tears down buildings; its charge is the common one
	if ExpansionMore.attack(self,u,target,data): return
	if data.has("stun_on_hit"): Arcane.area_hit(self,u,target.pos)
	elif data.get("pierce",false): Arcane.shoot_piercing_arrow(self,u,target)
	elif data.get("projectile",false): shoot(u,target,amount)
	elif target.get("kind","") == "gate": hit_gate(target.team,target.lane,amount,u.get("card",u.kind),u)
	else: damage(target,amount,u.team,u.get("card",u.kind),u)
	if data.get("splash","") == "column": column_slash(u,target,amount)

func attack(u: Dictionary, target: Dictionary) -> void:
	var data: Dictionary = B.CARDS[u.kind]
	_execute_unit_strike(u,target,data)
	u.cd = attack_interval(u)
	var total_strikes := int(data.get("strikes",1))
	if total_strikes > 1:
		u.combo_left = total_strikes-1
		u.combo_cd = COMBO_STRIKE_GAP
	else:
		u.erase("combo_left")
		u.erase("combo_cd")

# A vertical slash: every other enemy troop in the target's column, in this lane and the two lanes
# next to it, takes the same hit.
func column_slash(u: Dictionary, target: Dictionary, amount: float) -> void:
	var x: float = target.pos.x
	for other: Dictionary in foe_units[u.team]:
		if other.hp <= 0 or is_same(other,target) or absi(other.lane-u.lane) > 1 or absf(other.pos.x-x) > L.CELL_SIZE.x*0.5: continue
		damage(other,amount,u.team,u.get("card",u.kind),u)
	if not B.CARDS[u.kind].get("projectile",false):
		for lane: int in range(maxi(0,u.lane-1),mini(5,u.lane+2)):
			for b: Dictionary in lane_foe_buildings[u.team][lane]:
				if b.hp <= 0 or is_same(b,target) or GluttonNest.hidden(b) or absf(b.pos.x-x) > L.CELL_SIZE.x*0.5: continue
				damage(b,amount,u.team,u.get("card",u.kind),u)
	event("slash",Vector2(x,L.cell_center(Vector2i(0,u.lane)).y),u.team,{"lane":u.lane})

func shoot(source: Dictionary, target: Dictionary, amount: float) -> void:
	var direction: float = signf(target.pos.x-source.pos.x)
	var origin: Vector2 = source.pos+Vector2(0,source.get("dy",0.0))+Vector2(direction*(B.actor_radius(source)+4.0),-30 if not source.has("cell") else -42) # model position only: drawing state must never steer the simulation (network lockstep)
	projectiles.append({"source":source,"direction":direction,"pos":origin,"start":origin,"target":target,"remaining":B.ARROW_TIME,"amount":amount,"team":source.team,"kind":source.get("card",source.kind)})
	event("arrow",source.pos,source.team)

func update_projectiles(dt: float) -> void:
	if projectiles.is_empty(): return
	var expired := false
	for arrow: Dictionary in projectiles:
		if arrow.get("rolling",false):
			Frontier.roll(self,arrow,dt)
			if arrow.remaining <= 0: expired = true
			continue
		arrow.remaining -= dt
		if arrow.get("piercing",false):
			Arcane.advance_piercing_arrow(self,arrow)
			if arrow.remaining <= 0: expired = true
			continue
		if arrow.get("lane_bolt",false):
			ExpansionMore.advance_lane_bolt(self,arrow,dt)
			if arrow.remaining <= 0: expired = true
			continue
		if arrow.remaining <= 0: expired = true
		if arrow.has("impact"):
			arrow.pos = arrow.start.lerp(arrow.impact,clampf(1-arrow.remaining/arrow.flight,0,1))
			if arrow.remaining <= 0:
				var shell_shape: String = String(arrow.get("blast",""))
				var shell_dir := 1 if arrow.team == 0 else -1
				for u: Dictionary in units:
					if u.hp > 0 and u.team != arrow.team and (B.blast_hits(arrow.impact,shell_shape,shell_dir,u) if not shell_shape.is_empty() else B.point_edge_distance(arrow.impact,u) <= arrow.radius): damage(u,arrow.amount,arrow.team,arrow.kind,arrow.get("source",{}))
				for b: Dictionary in buildings:
					if b.hp > 0 and b.team != arrow.team and (B.blast_hits(arrow.impact,shell_shape,shell_dir,b) if not shell_shape.is_empty() else B.point_edge_distance(arrow.impact,b) <= arrow.radius): damage(b,arrow.amount,arrow.team,arrow.kind,arrow.get("source",{}))
				for lane: int in active_lanes:
					var gate_hit: bool = B.blast_hits_gate(arrow.impact,shell_shape,shell_dir,1-arrow.team,lane) if not shell_shape.is_empty() else Vector2(L.gate_stop(1-arrow.team),L.cell_center(Vector2i(0,lane)).y).distance_to(arrow.impact) <= arrow.radius
					if gates[1-arrow.team][lane] > 0 and gate_hit:
						hit_gate(1-arrow.team,lane,arrow.amount,arrow.kind,arrow.get("source",{}))
				event("stone_impact",arrow.impact,arrow.team,{"radius":arrow.radius})
			continue
		arrow.pos = arrow.start.lerp(arrow.target.get("draw",arrow.target.pos)+Vector2(0,-30),clampf(1-arrow.remaining/B.ARROW_TIME,0,1))
		if arrow.remaining <= 0:
			if ExpansionMore.hit_projectile(self,arrow): continue
			if arrow.target.get("kind","") == "gate":
				if gates[arrow.target.team][arrow.target.lane] > 0:
					hit_gate(arrow.target.team,arrow.target.lane,arrow.amount,arrow.kind,arrow.get("source",{}))
			elif arrow.target.hp > 0: damage(arrow.target,arrow.amount,arrow.team,arrow.kind,arrow.get("source",{}))
			projectile_blast(arrow)
	if expired:
		projectiles = projectiles.filter(func(a: Dictionary) -> bool: return a.remaining > 0)

# Grid splash around a shot's target for troops with "blast" and "area_damage" (2026-11-19).
func projectile_blast(arrow: Dictionary) -> void:
	var src: Dictionary = arrow.get("source",{})
	var sd: Dictionary = B.CARDS.get(String(src.get("kind","")),{})
	if not sd.has("blast") or not sd.has("area_damage") or sd.get("lob",false): return
	var center: Vector2 = arrow.target.get("pos",arrow.pos) if arrow.target.get("kind","") != "gate" else Vector2(L.gate_stop(arrow.target.team),L.cell_center(Vector2i(0,arrow.target.lane)).y)
	var dir := 1 if arrow.team == 0 else -1
	var amount: float = float(src.get("area_damage",sd.area_damage))
	for t: Dictionary in units+buildings:
		if t.hp > 0 and t.team != arrow.team and not is_same(t,arrow.target) and B.blast_hits(center,String(sd.blast),dir,t): damage(t,amount,arrow.team,arrow.kind,src)
	event("arcane_impact",center,arrow.team,{"from":arrow.start,"radius":float(sd.get("radius",75.0))})

func heal(u: Dictionary, dt: float) -> void:
	if u.kind != "healer": return
	u.heal_cd = maxf(0.0,u.heal_cd-dt)
	if u.heal_cd > 0: return
	var healed := false
	for ally: Dictionary in units:
		var poisoned: bool = int(ally.get("hex_stacks",0)) > 0 or int(ally.get("poison_stacks",0)) > 0
		if ally.team == u.team and ally.hp > 0 and (ally.hp < ally.max_hp or poisoned) and B.edge_distance(u,ally) <= B.HEAL_RADIUS:
			ally.hp = minf(ally.max_hp,ally.hp+B.HEAL_AMOUNT)
			if int(ally.get("hex_stacks",0)) > 0:
				ally.hex_stacks = maxi(0,int(ally.hex_stacks)-1)
				if ally.hex_stacks == 0:
					ally.hex_left = 0.0
					ally.hex_team = -1
			if int(ally.get("poison_stacks",0)) > 0:
				ally.poison_stacks = maxi(0,int(ally.poison_stacks)-1)
				if ally.poison_stacks == 0:
					ally.poison_left = 0.0
					ally.poison_team = -1
			event("heal",ally.pos,u.team)
			if not is_same(ally,u): link(u.pos,ally.pos,u.team,"heal")
			healed = true
	if healed: u.heal_cd = B.HEAL_INTERVAL

func cultivate(u: Dictionary, dt: float) -> bool:
	if u.kind != "farmer": return false
	if u.work_left > 0:
		u.work_left -= dt
		if u.work_left <= 0:
			for b: Dictionary in buildings:
				if b.id == u.work_id and b.hp > 0:
					b.boost_until = elapsed+B.BOOST_TIME
					b.hp = minf(b.max_hp,b.hp+B.FARMER_HEAL)
					stats[u.team].cultivated += 1
					event("cultivate",b.pos,u.team)
		return true
	for b: Dictionary in buildings:
		if b.hp <= 0 or b.team != u.team or b.kind != "farm" or b.cell.y != u.lane or b.id in u.worked: continue
		var distance: float = (b.pos.x-u.pos.x)*u.face
		if distance >= -0.01 and distance <= B.CARDS[u.kind].speed*dt+0.01:
			u.pos.x = b.pos.x
			u.worked.append(b.id)
			u.work_id = b.id
			u.work_left = B.CULTIVATE_TIME
			event("hoe",b.pos,u.team)
			return true
	return false

# One fixed simulation step. The phase order is part of the rules (fixed-seed results and online
# lockstep depend on it): deaths, AI plays, clocks and income, buildings, spells and
# clouds, arrows, lords, troops, then deaths again and cleanup.
func step(dt: float) -> void:
	if paused or ended: return
	elapsed += dt
	last_dt = dt
	resolve_deaths()
	update_ai(dt)
	tick_clocks(dt)
	build_lookups()
	Arcane.update_traps(self)
	update_buildings(dt)
	update_field_mutators(dt)
	update_spells(dt)
	update_zones(dt)
	Faction.update(self,dt)
	Monster.update(self,dt)
	SealAltar.update(self,dt)
	Expansion.update(self,dt)
	ExpansionMore.update(self,dt)
	update_projectiles(dt)
	for lord: Dictionary in lords:
		if lord_active[lord.team] and not frozen(lord.team):
			Lord.step(self,lord,dt)
			if active_lanes.size() == 1:
				lord.pos.y = L.cell_center(Vector2i(0,active_lanes[0])).y
				lord.target.y = lord.pos.y
	update_units(dt)
	tick_time_stop(dt)
	resolve_deaths()
	remove_dead()
	update_clock()

# Card and skill cooldowns, base income, lane alarms.
func tick_clocks(dt: float) -> void:
	var mult := multiplier()
	for team: int in range(2):
		# Card cooldowns speed up together with ink (x1.5 after 3:00, x2 after 5:00), except economy buildings.
		var cycle: Dictionary = lord_mod(team,"cycle_speed",{})
		var cd_mult: float = float(lord_mod(team,"cd_speed_mult",1.0))
		var global_cycle: float = float(cycle.get("*",1.0))*cd_mult
		for slot: int in range(4):
			if hand_cd[team][slot] <= 0.0: continue
			var card_kind: String = kind_at(team,slot)
			var card_cycle: float = float(cycle.get(card_kind,1.0)) if card_kind != "*" else 1.0
			var rate: float = global_cycle*card_cycle*(1.0+0.2*int(card_upgrades[team].get(card_kind,{}).get("cycle",0)))
			var day_speed: float = 1.0 if B.is_economy_building(card_kind) else mult
			if SealAltar.holds_cooldown(self,team,card_kind): continue # 封印祭壇: no countdown while ours stands
			hand_cd[team][slot] = maxf(0,hand_cd[team][slot]-dt*day_speed*rate)
		if farm_cd[team] > 0.0:
			var home_speed: float = 1.0 if B.is_economy_building(home_cards[team]) else mult
			farm_cd[team] = maxf(0,farm_cd[team]-dt*home_speed*cd_mult)
		if skill_cd[team] > 0.0:
			skill_cd[team] = maxf(0,skill_cd[team]-dt*float(lord_mod(team,"skill_haste",1.0))*cd_mult)
		if not frozen(team): base_clock[team] += dt*mult # 時空凝滯 pauses the enemy's base income
		while base_clock[team] >= B.BASE_INTERVAL-0.000001:
			base_clock[team] -= B.BASE_INTERVAL
			gain_ink(team,lord_mod(team,"income_mult",1.0))
	for lane: int in active_lanes:
		alarm[lane] = maxf(0,alarm[lane]-dt)
		building_alarm[lane] = maxf(0,building_alarm[lane]-dt)
	crumble_gates(dt)

# Phase of the day: 0 morning (x1.5), 1 noon (gold x2.0), 2 dusk (gold x2.5), 3 night (gates crumble, x3.0).
func day_phase() -> int:
	if night_decay and elapsed >= B.NIGHT_START: return 3
	return 2 if elapsed >= B.RAMP_2 else (1 if elapsed >= B.RAMP_1 else 0)

# Gate hp every standing gate loses per second right now (0 before nightfall).
func night_rate() -> float:
	if not night_decay or elapsed < B.NIGHT_START: return 0.0
	return B.NIGHT_DECAY*pow(2.0,floorf((elapsed-B.NIGHT_START)/B.NIGHT_STEP))

# Night: both sides' gates wear down on their own; one that reaches 0 falls like any breached gate.
func crumble_gates(dt: float) -> void:
	var rate := night_rate()
	if rate <= 0.0: return
	var fell := false
	for side: int in range(2):
		for lane: int in active_lanes:
			if gates[side][lane] <= 0: continue
			gates[side][lane] = maxf(0.0,gates[side][lane]-rate*dt)
			if gates[side][lane] > 0: continue
			fell = true
			if first_breach < 0: first_breach = elapsed
			event("breach",Vector2(L.gate_icon_x(side),L.cell_center(Vector2i(0,lane)).y),1-side,{"lane":lane,"crumbled":true})
	if fell: refresh_territory()

# Expiry, farm and grave income, tower shots.
func update_buildings(dt: float) -> void:
	for b: Dictionary in buildings:
		b.flash = maxf(0,b.flash-dt)
		if b.hp <= 0: continue
		if b.expires > 0 and elapsed >= b.expires:
			b.hp = 0
			refresh_territory()
			event("death",b.pos,b.team,{"card":b.kind,"art_kind":b.kind,"face":1.0})
			continue
		if frozen(b.team): continue # 時空凝滯 pauses every enemy building: towers and economy alike
		var b_factor: float = 1.0 if fields.is_empty() else Faction.building_factor(self,b)
		var b_dt: float = dt * b_factor
		if GluttonNest.update(self,b,b_dt): continue
		if Arcane.update_building(self,b,b_dt): continue
		if Faction.update_building(self,b,b_dt): continue
		if b.kind == "grave":
			b.production += b_dt
			if b.production >= B.CARDS.grave.period: grave_drop(b)
		elif b.kind == "farm":
			var active_dt: float = clampf(elapsed-b.ready_at,0,b_dt)
			b.production += active_dt*farm_speed_with(b,lane_mill[b.team][b.cell.y])*multiplier()
			while b.production >= B.FARM_INTERVAL-0.000001:
				b.production -= B.FARM_INTERVAL
				farm_drop(b)
		elif b.kind == "tower":
			b.cd -= b_dt
			if b.cd <= 0:
				var target := GridRules.pick(self,b,foe_units[b.team]) # reach in cells; troops first, then buildings
				if not target.is_empty():
					shoot(b,target,b.get("damage",B.CARDS.tower.damage))
					b.cd = b.get("interval",B.CARDS.tower.interval)

func is_ranged_attacker(data: Dictionary) -> bool:
	return data.get("projectile",false) or data.get("lob",false) or float(data.get("min_range",0.0)) > 0.0 or (data.has("area_damage") and float(data.get("range",B.MELEE_RANGE)) > B.MELEE_RANGE)

func gate_target_dict(side: int, lane: int) -> Dictionary:
	return {"kind":"gate","team":side,"lane":lane,"pos":Vector2(L.gate_stop(side),L.cell_center(Vector2i(0,lane)).y),"hp":gates[side][lane],"body_radius":0.0}

func enemy_gate_target(u: Dictionary, max_range: float, min_range: float = 0.0) -> Dictionary:
	var enemy: int = 1-u.team
	if not u.lane in active_lanes or gates[enemy][u.lane] <= 0: return {}
	var gate := gate_target_dict(enemy,u.lane)
	if (gate.pos.x-u.pos.x)*u.face < 0: return {}
	var dist := B.edge_distance(u,gate)
	if dist < min_range or dist > max_range: return {}
	return gate

func catapult_target(b: Dictionary) -> Dictionary:
	var data: Dictionary = B.CARDS[b.kind]
	var max_r: float = float(b.get("range",data.range))
	var taunt := taunting_scarecrow(b)
	if is_switching_to_taunt(b,taunt): return {}
	if not taunt.is_empty():
		var d: float = B.edge_distance(b,taunt)
		if d >= data.min_range and d <= max_r: return taunt
	var found: Dictionary = {}
	var best := -1.0
	for target: Dictionary in lane_foes[b.team][b.lane] + lane_foe_buildings[b.team][b.lane]:
		if target.hp <= 0 or target.get("stealthed",false): continue
		if (target.pos.x-b.pos.x)*b.face < 0: continue
		var distance: float = B.edge_distance(b,target)
		if distance < data.min_range or distance > max_r: continue
		if distance > best or (is_equal_approx(distance,best) and target.serial > found.get("serial",0)):
			best = distance
			found = target
	if found.is_empty(): return enemy_gate_target(b,max_r,data.min_range)
	return found

# Buff the actual marching speed (including a legion's formation or a slowed ox), once only.
func movement_speed(u: Dictionary) -> float:
	var data: Dictionary = B.CARDS[u.kind]
	var base: float = u.get("march",u.get("speed",data.speed))
	var steps := buff_steps(u)
	u.inspired = steps > 0
	var charge_step := 1 if ((data.get("charge",false) and not u.get("charged",false) and not u.get("expansion_charged",false)) or u.get("granted_charge",false)) else 0
	var total_steps := steps+charge_step
	if total_steps > 0:
		var index: int = B.TIERS.speed.find(base)
		if index >= 0: base = B.TIERS.speed[maxi(B.tier_index("S"),index-total_steps)] # one tier per buff, never past S
	if u.get("slow_left",0.0) > 0:
		base *= 0.5
	if (not water_lanes.is_empty() or not water_cols.is_empty()) and not u.get("flying",false):
		var ulane := clampi(floori((u.pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y),0,L.GRID_ROWS-1)
		var ucol := clampi(floori((u.pos.x-L.GRID_ORIGIN.x)/L.CELL_SIZE.x),0,L.GRID_COLUMNS-1)
		if ulane in water_lanes or ucol in water_cols:
			base *= 0.4 # water zones slow non-flying troops by 60%
	if u.get("root_left",0.0) > 0.0: return 0.0
	if not fields.is_empty() and Faction.in_time_field(self,u): base *= 0.5
	return base

func attack_interval(u: Dictionary) -> float:
	var data: Dictionary = B.CARDS[u.kind]
	var base: float = u.get("interval",data.interval)
	var steps := buff_steps(u)
	if steps > 0:
		var index: int = B.TIERS.interval.find(base)
		if index >= 0: base = B.TIERS.interval[maxi(B.tier_index("S"),index-steps)] # one tier per buff, never past S
	if u.get("slow_left",0.0) > 0:
		base *= 2.0
	if not fields.is_empty() and Faction.in_time_field(self,u): base *= 2.0
	return base

# Speed / attack-speed buffs on this troop; each one is a tier (producer 2026-11-05: all buffs stack).
func buff_steps(u: Dictionary) -> int:
	var steps := 1 if u.get("expansion_haste_until",0.0) > elapsed else 0
	if u.kind != "drummer":
		var beats := 0
		for t: float in team_drums[u.team]:
			if t > elapsed: beats += 1
		steps += maxi(beats,1 if team_drum_until[u.team] > elapsed else 0) # tests may set team_drum_until directly
	if vampire_until[u.team] > elapsed and LordExpansion.active(self,u): steps += 1
	if not horns.is_empty(): steps += Faction.horn_count(self,u)
	if u.get("levy",false): steps += 1 # 緊急徵召 militia fight in a hurry
	var haste: Array = lord_mod(u.team,"haste",[])
	if not haste.is_empty() and ("*" in haste or u.kind in haste): steps += 1
	return steps

func update_spells(dt: float) -> void:
	if spells.is_empty(): return
	var expired := false
	for spell: Dictionary in spells:
		spell.delay -= dt
		if spell.delay <= 0:
			cast_spell(spell)
			expired = true
	if expired:
		spells = spells.filter(func(s: Dictionary) -> bool: return s.delay > 0)

func update_units(dt: float) -> void:
	# Summons append to units; count snapshot prevents them acting in their birth step.
	var count := units.size()
	for idx: int in range(count):
		if frozen(units[idx].team): continue # 時空凝滯
		if update_unit(units[idx],dt): return # an invader just ended the match

# One troop's turn: summon, heal, then fight, cultivate or march. True when it ends the match.
func update_unit(u: Dictionary, dt: float) -> bool:
	u.flash = maxf(0,u.flash-dt)
	if u.hp <= 0: return false
	if u.spawn_delay > 0:
		u.spawn_delay -= dt
		return false
	u.cd = maxf(0,u.cd-dt)
	if u.get("slow_left",0.0) > 0:
		u.slow_left = maxf(0.0,u.slow_left-dt)
	if u.get("stun_left",0.0) > 0:
		Windup.cancel(u)
		_cancel_combo(u)
		u.march_time = 0.0
		u.stun_left = maxf(0.0,u.stun_left-dt)
		return false
	if u.get("seal_left",0.0) > 0:
		Windup.cancel(u)
		_cancel_combo(u)
		u.march_time = 0.0
		u.seal_left = maxf(0.0,u.seal_left-dt)
		u.root_left = maxf(0.0,u.root_left-dt)
		return false
	if Faction.flee(self,u,dt):
		Windup.cancel(u)
		_cancel_combo(u)
		u.march_time = 0.0
		return false
	var data: Dictionary = B.CARDS[u.kind]
	if ExpansionMore.update_unit(self,u,data,dt): return false
	if u.kind == "necromancer": summon_skeletons(u,data,dt)
	if u.kind == "drummer":
		u.drum_cd = u.get("drum_cd",10.0)-dt
		if u.drum_cd <= 0:
			u.drum_cd += B.CARDS.drummer.get("inspire_period",10.0)
			trigger_drum(u)
	heal(u,dt)
	if data.get("patrol",false):
		var foes: Array = lane_foes[u.team][u.lane]+lane_foe_buildings[u.team][u.lane]
		var patrol_target := nearest(u.pos,u.team,data.range,foes,-1,false,B.actor_radius(u))
		if not patrol_target.is_empty():
			u.march_time = 0.0
			u.face = 1.0 if patrol_target.pos.x >= u.pos.x else -1.0
			if Windup.ready(self,u,Windup.target_key(patrol_target),dt): attack(u,patrol_target)
		else:
			Windup.cancel(u)
			Frontier.patrol(self,u,dt)
		return false
	if u.kind == "catapult":
		var target := catapult_target(u)
		if not target.is_empty():
			u.march_time = 0.0
			if Windup.ready(self,u,Windup.target_key(target),dt):
				projectiles.append({"source":u,"pos":u.pos,"start":u.pos,"impact":target.pos,"flight":data.flight_time,"remaining":data.flight_time,"amount":data.area_damage,"radius":data.radius,"blast":data.get("blast",""),"team":u.team,"kind":u.kind})
				u.cd = attack_interval(u)
				event("catapult_fire",u.pos,u.team,{"target":target.pos})
			return false
		return march(u,data,dt)
	var reach: Dictionary = _unit_reach_data(u,data)
	var combat_data := Faction.unit_data(self,u,reach)
	if _advance_combo(u,combat_data,dt): return false
	var taunt := taunting_scarecrow(u)
	var switching_to_taunt := is_switching_to_taunt(u,taunt)
	if not switching_to_taunt:
		var target := _choose_target_with_taunt(u,combat_data,taunt,false)
		if not target.is_empty():
			u.march_time = 0.0
			if Windup.ready(self,u,Windup.target_key(target),dt): attack(u,target)
			return false
		if u.kind == "artificer" and Arcane.repair(self,u,dt):
			Windup.cancel(u)
			u.march_time = 0.0
			return false
		if u.kind == "farmer" and cultivate(u,dt):
			Windup.cancel(u)
			u.march_time = 0.0
			return false
	return _march_with_taunt(u,data,dt,taunt)

# 腐屍巨人: each burst_step of max hp lost (the last one is its death) bursts burst_count skeletons.
func giant_burst(target: Dictionary) -> void:
	var d: Dictionary = B.CARDS[target.kind]
	var steps: int = roundi(1.0/d.burst_step)
	var reached: int = clampi(int((target.max_hp-maxf(0.0,target.hp))/(target.max_hp*d.burst_step)+0.000001),0,steps)
	while target.get("bursts",0) < reached:
		target.bursts = target.get("bursts",0)+1
		for i: int in range(d.burst_count):
			var child := spawn_unit(target.team,target.lane,"skeleton",target.pos)
			child.card = target.get("card",target.kind)
			child.spawn_delay = i*0.08
			event("summoned",child.pos,child.team)
		link(target.pos,target.pos+Vector2(0,-30),target.team,"summon")

func summon_skeletons(u: Dictionary, data: Dictionary, dt: float) -> void:
	u.summon_left -= dt
	if u.summon_left > 0: return
	u.summon_left += data.summon_interval
	var col := clampi(floori((u.pos.x-L.GRID_ORIGIN.x)/L.CELL_SIZE.x),0,L.GRID_COLUMNS-1)
	var span: int = int(data.get("summon_lanes",3))
	var lanes: Array = [u.lane-1,u.lane,u.lane+1] if span >= 3 else [u.lane]
	for lane: int in lanes:
		if not lane in active_lanes: continue
		for i: int in range(data.get("summon_per_lane",1)):
			var child := spawn_unit(u.team,lane,"skeleton",L.cell_center(Vector2i(col,lane)))
			child.card = u.get("card",u.kind)
			event("summoned",child.pos,u.team)
			link(u.pos,child.pos,u.team,"summon")

# 稻草人: an enemy scarecrow whose 3 x 3 block (its lane and the two next to it, its column and the
# two next to it) holds this troop draws all of its attacks, from wherever it stands - ravens and
# rams included. The nearest such scarecrow wins; level ones go by the higher serial.
func taunting_scarecrow(u: Dictionary) -> Dictionary:
	if not has_taunt[u.team]: return {}
	var col := clampi(floori((u.pos.x-L.GRID_ORIGIN.x)/L.CELL_SIZE.x),0,L.GRID_COLUMNS-1)
	var found: Dictionary = {}
	for lane: int in range(maxi(0,u.lane-1),mini(5,u.lane+2)):
		for b: Dictionary in lane_foe_taunts[u.team][lane]:
			if b.hp <= 0 or absi(b.cell.x-col) > 1: continue
			if found.is_empty():
				found = b
				continue
			var d: float = u.pos.distance_to(b.pos)
			var best: float = u.pos.distance_to(found.pos)
			if d < best-SERIAL_TIE or (d <= best+SERIAL_TIE and b.serial > found.serial): found = b
	return found

# Taunted units finish moving into the scarecrow's lane before attacking (never diagonally).
func is_switching_to_taunt(u: Dictionary, taunt: Dictionary) -> bool:
	return not taunt.is_empty() and absf(u.pos.y-L.cell_center(Vector2i(0,taunt.cell.y)).y) > 0.01

func _cancel_combo(u: Dictionary) -> void:
	u.erase("combo_left")
	u.erase("combo_cd")

func _unit_reach_data(u: Dictionary, data: Dictionary) -> Dictionary:
	var reach: Dictionary = data
	if u.has("range"): # an upgraded card reaches one tier further
		reach = data.duplicate()
		reach.range = u.range
	if u.get("expansion_range_until",0.0) > elapsed and B.CARDS[u.kind].get("projectile",false):
		var tier: int = B.TIERS.range.find(reach.range)
		if tier > B.tier_index("S"):
			if not u.has("range"): reach = data.duplicate()
			reach.range = B.TIERS.range[tier-1]
	return reach

func _advance_combo(u: Dictionary, combat_data: Dictionary, dt: float) -> bool:
	if u.get("combo_left",0) <= 0: return false
	u.combo_cd = u.get("combo_cd",0.0)-dt
	var enemy: int = 1-int(u.team)
	var forward := 1.0 if u.team == 0 else -1.0
	var at_gate: bool = gates[enemy][u.lane] > 0 and absf(u.pos.x-(L.gate_stop(enemy)-forward*B.actor_radius(u))) <= 4.0
	while u.get("combo_left",0) > 0 and u.combo_cd <= 0.000001:
		var next_target := choose_target(u,combat_data)
		if not next_target.is_empty():
			_execute_unit_strike(u,next_target,combat_data)
		elif at_gate and gates[enemy][u.lane] > 0:
			_execute_gate_strike(u,combat_data,enemy)
		else:
			_cancel_combo(u)
			return false
		u.combo_left -= 1
		if u.combo_left <= 0:
			_cancel_combo(u)
			return true
		u.combo_cd += COMBO_STRIKE_GAP
	if not choose_target(u,combat_data).is_empty() or (at_gate and gates[enemy][u.lane] > 0):
		u.march_time = 0.0
		return true
	_cancel_combo(u)
	return false

func _horizontal_reach(u: Dictionary, other: Dictionary) -> float:
	return maxf(0.0,absf(other.pos.x-u.pos.x)-B.actor_radius(u)-B.actor_radius(other))

func _nearest_three_lane(u: Dictionary, max_range: float, candidates: Array, can_hit_flying: bool) -> Dictionary:
	var sr := B.actor_radius(u)
	var found: Dictionary = {}
	var best := INF
	for other: Dictionary in candidates:
		if other.team == u.team or other.hp <= 0 or other.get("stealthed",false) or GluttonNest.hidden(other): continue
		if not can_hit_flying and other.get("flying",false): continue
		var other_lane: int = clampi(roundi((other.pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y-0.5),0,4) if other.get("kind","") == "lord" else int(other.get("lane",other.get("cell",Vector2i(-1,-1)).y))
		if absi(other_lane-u.lane) > 1: continue
		if (other.pos.x-u.pos.x)*u.face < -sr: continue
		var d := maxf(0.0,absf(other.pos.x-u.pos.x)-sr-B.actor_radius(other))
		if d > max_range: continue
		var score := d+(0.01 if other_lane != u.lane else 0.0)
		if found.is_empty() or score < best-SERIAL_TIE or (score <= best+SERIAL_TIE and other.get("serial",-1) > found.get("serial",-1)):
			found = other
			best = minf(best,score) if absf(score-best) <= SERIAL_TIE else score
	return found

func _nearest_three_lane_lanes(u: Dictionary, max_range: float, lane_lists: Array, can_hit_flying: bool, min_dx: float) -> Dictionary:
	var sr := B.actor_radius(u)
	var found: Dictionary = {}
	var best := INF
	for l: int in range(maxi(0,u.lane-1),mini(5,u.lane+2)):
		for other: Dictionary in lane_lists[l]:
			if other.team == u.team or other.hp <= 0 or other.get("stealthed",false) or GluttonNest.hidden(other): continue
			if not can_hit_flying and other.get("flying",false): continue
			var other_lane: int = int(other.get("lane",other.get("cell",Vector2i(-1,-1)).y))
			if absi(other_lane-u.lane) > 1: continue
			if (other.pos.x-u.pos.x)*u.face < min_dx: continue
			var d := maxf(0.0,absf(other.pos.x-u.pos.x)-sr-B.actor_radius(other))
			if d > max_range: continue
			var score := d+(0.01 if other_lane != u.lane else 0.0)
			if found.is_empty() or score < best-SERIAL_TIE or (score <= best+SERIAL_TIE and other.get("serial",-1) > found.get("serial",-1)):
				found = other
				best = minf(best,score) if absf(score-best) <= SERIAL_TIE else score
	return found

# Whom this troop attacks right now ({} = nobody in reach).
func choose_target(u: Dictionary, data: Dictionary) -> Dictionary:
	var taunt := taunting_scarecrow(u)
	return _choose_target_with_taunt(u,data,taunt,is_switching_to_taunt(u,taunt))

func _choose_target_with_taunt(u: Dictionary, data: Dictionary, taunt: Dictionary, switching_to_taunt: bool) -> Dictionary:
	if switching_to_taunt: return {}
	var sr: float = float(u.body_radius) if u.has("body_radius") else B.actor_radius(u)
	var three_lane: bool = data.get("three_lane_target",false)
	var bld_lanes: Array = lane_foe_buildings[u.team]
	var foe_lanes: Array = lane_foes[u.team]
	if u.get("phased",false):
		return _nearest_three_lane_lanes(u,data.range,bld_lanes,true,-sr) if three_lane else _nearest_dir(u.pos,u.team,data.range,bld_lanes[u.lane],true,sr,u.face,0.0)
	if data.has("blink_step"):
		var front_u := _nearest_dir(u.pos,u.team,data.range,foe_lanes[u.lane],false,sr,u.face,0.0)
		var front_b := _nearest_dir(u.pos,u.team,data.range,bld_lanes[u.lane],false,sr,u.face,0.0)
		var front: Dictionary = front_u
		if not front_b.is_empty():
			if front.is_empty(): front = front_b
			else:
				var du := B.edge_distance(u,front)
				var db := B.edge_distance(u,front_b)
				if db < du-SERIAL_TIE or (db <= du+SERIAL_TIE and front_b.get("serial",-1) > front.get("serial",-1)):
					front = front_b
		if not front.is_empty(): return front
	if not taunt.is_empty() and B.edge_distance(u,taunt) <= data.range: return taunt
	var can_fly: bool = data.range > B.MELEE_RANGE
	var target: Dictionary = {} if data.get("hits","") == "buildings" else (_nearest_three_lane_lanes(u,data.range,foe_lanes,can_fly,-sr) if three_lane else _nearest_dir(u.pos,u.team,data.range,foe_lanes[u.lane],can_fly,sr,u.face,0.0))
	var building := _nearest_three_lane_lanes(u,data.range,bld_lanes,true,-sr) if three_lane else _nearest_dir(u.pos,u.team,data.range,bld_lanes[u.lane],true,sr,u.face,0.0)
	if data.get("hits","") == "units": building = {} # 刺客: walks past buildings, still strikes troops, lords and the gate
	if data.get("prefers","") == "farm":
		var farm := _nearest_dir(u.pos,u.team,INF,bld_lanes[u.lane],true,sr,u.face,-data.range,"farm")
		if not farm.is_empty():
			building = farm if B.edge_distance(u,farm) <= data.range else {}
	if not building.is_empty():
		var b_dist := _horizontal_reach(u,building) if three_lane else B.edge_distance(u,building)
		var t_dist := (_horizontal_reach(u,target) if three_lane else B.edge_distance(u,target)) if not target.is_empty() else INF
		if target.is_empty() or b_dist < t_dist: target = building
	if data.get("target_rule","") == "lowest_serial": target = reaper_target(u)
	elif target.is_empty():
		if is_ranged_attacker(data): target = enemy_gate_target(u,data.range)
		if target.is_empty():
			if three_lane:
				target = _nearest_three_lane(u,data.range,lords,true)
			else:
				target = _nearest_dir(u.pos,u.team,54.0,lords,true,sr,u.face,0.0)
	return target

# Nothing to hit: walk to the enemy gate, batter it, clear its rubble, walk in. True = match won.
# For units with "hunt_nearest": finds the lane of the nearest enemy ahead.
func nearest_enemy_lane(u: Dictionary, _data: Dictionary) -> int:
	var forward: float = 1.0 if u.team == 0 else -1.0
	var best_d: float = INF
	var best_lane: int = u.lane
	# 1. Search enemy units ahead
	for foe: Dictionary in units:
		if foe.team == u.team or foe.hp <= 0 or foe.get("spawn_delay",0.0) > 0: continue
		if foe.get("stealthed",false) or foe.get("phased",false): continue
		if (foe.pos.x-u.pos.x)*forward < -30.0: continue
		var d: float = u.pos.distance_to(foe.pos)
		if foe.lane == u.lane: d -= 20.0 # slight hysteresis to prevent flickering on ties
		if d < best_d:
			best_d = d
			best_lane = foe.lane
	# 2. If no enemy units ahead, search enemy buildings ahead
	if best_d == INF:
		for b: Dictionary in buildings:
			if b.team == u.team or b.hp <= 0: continue
			if (b.pos.x-u.pos.x)*forward < -30.0: continue
			var d: float = u.pos.distance_to(b.pos)
			if b.cell.y == u.lane: d -= 20.0
			if d < best_d:
				best_d = d
				best_lane = b.cell.y
	# 3. If no buildings, search active enemy lords ahead
	if best_d == INF:
		for l: Dictionary in lords:
			if l.team == u.team or l.hp <= 0 or not lord_active[l.team]: continue
			if (l.pos.x-u.pos.x)*forward < -30.0: continue
			var d: float = u.pos.distance_to(l.pos)
			if d < best_d:
				best_d = d
				best_lane = clampi(roundi((l.pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y-0.5),0,4)
	return best_lane

func advance_march_timers(u: Dictionary, data: Dictionary, spd: float, dt: float) -> void:
	if spd > 0.0:
		u.march_time = u.get("march_time",0.0)+dt
		if u.march_time >= B.CHARGE_RESET_TIME:
			if data.get("charge",false) and (u.get("charged",false) or u.get("expansion_charged",false)):
				u.charged = false
				u.expansion_charged = false
				event("charge_ready",u.pos,u.team,{"face":u.face})
			if data.get("stealth",false) and not u.get("stealthed",false) and not u.get("revealed",false):
				u.stealthed = true
				event("stealth_ready",u.pos,u.team)
	else:
		u.march_time = 0.0

func _execute_gate_strike(u: Dictionary, data: Dictionary, enemy: int) -> void:
	Arcane.reveal(self,u,false)
	u.strike_seq = u.get("strike_seq",0)+1
	if data.get("pierce",false):
		Arcane.shoot_piercing_arrow(self,u)
		return
	if data.has("stun_on_hit"):
		Arcane.area_hit(self,u,Vector2(L.gate_stop(enemy),u.pos.y))
		return
	if ExpansionMore.gate_attack(self,u,data,enemy): return
	var amount: float = ExpansionMore.gate_amount(self,u,u.get("damage",data.damage))
	if u.kind == "ox": amount *= B.OX_BUILDING_BONUS
	hit_gate(enemy,u.lane,amount,u.get("card",u.kind),u)
	if data.get("splash","") == "column": column_slash(u,{"pos":Vector2(L.gate_stop(enemy),u.pos.y)},amount)

func march(u: Dictionary, data: Dictionary, dt: float) -> bool:
	return _march_with_taunt(u,data,dt,taunting_scarecrow(u))

func _march_with_taunt(u: Dictionary, data: Dictionary, dt: float, taunt: Dictionary) -> bool:
	var enemy: int = 1-u.team
	var target_lane: int = taunt.cell.y if not taunt.is_empty() else u.lane
	if taunt.is_empty() and data.get("hunt_nearest",false):
		target_lane = nearest_enemy_lane(u,data)
	var target_y: float = L.cell_center(Vector2i(0,target_lane)).y
	if not is_equal_approx(u.pos.y,target_y):
		var spd_y := movement_speed(u)
		u.pos.y = move_toward(u.pos.y,target_y,spd_y*dt)
		if absf(u.pos.y-target_y) <= 0.01:
			u.pos.y = target_y
			u.lane = target_lane
		else:
			var new_lane: int = clampi(roundi((u.pos.y-L.GRID_ORIGIN.y)/L.CELL_SIZE.y-0.5),0,4)
			if new_lane != u.lane: u.lane = new_lane
		if not taunt.is_empty():
			Windup.cancel(u)
			_cancel_combo(u)
			advance_march_timers(u,data,spd_y,dt)
			return false
	var open: bool = gates[enemy][u.lane] <= 0
	var forward := 1.0 if u.team == 0 else -1.0
	var stop: float = L.gate_icon_x(enemy) if open else L.gate_stop(enemy)-forward*B.actor_radius(u)
	if (stop-u.pos.x)*forward > 0.001:
		Windup.cancel(u)
		_cancel_combo(u)
		var spd := movement_speed(u)
		u.pos.x = move_toward(u.pos.x,stop,spd*dt)
		advance_march_timers(u,data,spd,dt)
	elif open:
		Windup.cancel(u)
		_cancel_combo(u)
		u.march_time = 0.0
		if not invasion_victory[u.team]: return false
		if B.CARDS.has(u.kind): stats[u.team].invaded_card = u.kind
		event("invaded",u.pos,u.team,{"lane":u.lane,"unit_kind":u.kind})
		finish(u.team)
		return true
	elif u.cd <= 0:
		u.march_time = 0.0
		if not Windup.ready(self,u,"gate:%d:%d" % [enemy,u.lane],dt): return false
		_execute_gate_strike(u,data,enemy)
		u.cd = attack_interval(u)
		var total_strikes := int(data.get("strikes",1))
		if total_strikes > 1:
			u.combo_left = total_strikes-1
			u.combo_cd = COMBO_STRIKE_GAP
		else:
			_cancel_combo(u)
	else:
		u.march_time = 0.0
	return false

# Free the serials of the dead and drop them.
func remove_dead() -> void:
	var dead_u := false
	for u: Dictionary in units:
		if u.hp <= 0:
			dead_u = true
			if u.serial > 0:
				serials_in_use.erase(u.serial)
				u.serial = 0
	var dead_b := false
	for b: Dictionary in buildings:
		if b.hp <= 0:
			dead_b = true
			if b.serial > 0:
				serials_in_use.erase(b.serial)
				b.serial = 0
	if dead_u:
		units = units.filter(func(u: Dictionary) -> bool: return u.hp > 0)
	if dead_b:
		buildings = buildings.filter(func(b: Dictionary) -> bool: return b.hp > 0)

func cast_spell(s: Dictionary) -> void:
	var data: Dictionary = spell_card_data(s.team,s.kind)
	if data.get("rolling",false):
		Frontier.launch(self,s)
		return
	if Faction.cast(self,s): return
	if ExpansionMore.cast(self,s): return
	var rect: Rect2 = B.spell_rect(s.pos,data)
	event("spell",s.pos,s.team,{"card":s.kind,"radius":data.radius,"rect":rect})
	if s.kind == "curse":
		for u: Dictionary in units: # friend or foe: whoever dies cursed rises as the caster's skeleton
			if u.hp > 0 and B.rect_hits_actor(rect,u):
				u.cursed = true
				u.cursed_until = INF
				u.curse_team = s.team
				link(s.pos,u.pos,s.team,"curse")
		return
	if s.kind == "plague":
		add_zone(s.pos,s.team,data.radius,data.duration,rect,float(data.tick_damage))
		return
	if s.kind == "harvest":
		for b: Dictionary in buildings:
			if b.team == s.team and b.hp > 0 and b.kind == "farm" and B.rect_hits_actor(rect,b):
				b.harvest_until = elapsed+B.HARVEST_TIME
				link(s.pos,b.pos,s.team,"harvest")
		return
	for u: Dictionary in units:
		if u.team != s.team and B.rect_hits_actor(rect,u):
			if s.kind == "fire": knockback_unit(u,B.FIRE_KNOCKBACK*(1.0 if s.team == 0 else -1.0))
			damage(u,data.damage,s.team,s.kind)
	for b: Dictionary in buildings:
		if b.team != s.team and B.rect_hits_actor(rect,b): damage(b,data.building_damage,s.team,s.kind)
	for lane: int in active_lanes:
		var gate_pos := Vector2(L.gate_stop(1-s.team),L.cell_center(Vector2i(0,lane)).y)
		if B.rect_hits_point(rect,gate_pos,10.0): hit_gate(1-s.team,lane,data.gate_damage,s.kind)

func update_clock() -> void:
	if ended: return
	for ramp: float in [B.RAMP_1,B.RAMP_2]:
		if elapsed >= ramp and elapsed-last_dt < ramp: event("ramp",Vector2(800,50),0,{"multiplier":multiplier()})
	if night_decay and elapsed >= B.NIGHT_START:
		# Nightfall, then one toll each time the crumbling doubles.
		var before: float = elapsed-last_dt-B.NIGHT_START
		if before < 0 or floorf(before/B.NIGHT_STEP) != floorf((elapsed-B.NIGHT_START)/B.NIGHT_STEP): event("nightfall",Vector2(800,50),0,{"rate":night_rate(),"first":before < 0})
		if elapsed >= B.DAWN: dawn_verdict()

# Land each side holds: territory cells in the lanes being played.
func land(team: int) -> int:
	var cells := 0
	for lane: int in active_lanes:
		for col: int in range(L.GRID_COLUMNS):
			if territory_owner(Vector2i(col,lane)) == team: cells += 1
	return cells

# Dawn with nobody inside either home: more land wins, level is a draw (winner -1).
func dawn_verdict() -> void:
	var mine := land(0)
	var theirs := land(1)
	event("dawn",Vector2(800,450),0,{"land":[mine,theirs]})
	finish(0 if mine > theirs else (1 if theirs > mine else -1))

# What the AI needs to decide on its lord's skill.
func skill_state(team: int) -> Dictionary:
	var farms := 0
	var graves := 0
	var damaged_blds := 0
	for b: Dictionary in buildings:
		if b.hp <= 0 or b.team != team: continue
		if b.kind == "farm": farms += 1
		elif b.kind == "grave": graves += 1
		if b.hp < b.max_hp: damaged_blds += 1
	var gate_total := 0.0
	var broken := 0
	for hp: float in gates[team]:
		gate_total += hp
		if hp <= 0: broken += 1
	var my_army_count := 0
	var my_army_hp := 0.0
	var enemy_troops := 0
	var slash_targets := 0
	var lord_kind: String = lords[team].lord
	var is_adv := lord_kind == "adventure"
	var lpos: Vector2 = lords[team].pos
	var Slash = preload("res://hero_slash.gd") if is_adv else null
	for u: Dictionary in units:
		if u.hp <= 0: continue
		if u.team == team:
			if not u.kind in ["farmer","artificer"]:
				my_army_count += 1
				my_army_hp += u.hp
		elif u.spawn_delay <= 0:
			enemy_troops += 1
			if is_adv and Slash.contains(lpos,u.pos,team): slash_targets += 1
	var has_open := _minion_open_cell(team).x >= 0 if B.is_minion(lord_kind) else false
	return {"rune_lanes":LordExpansion.rune_cells(self,team).size() if lord_kind == "rune" else 0,"slash_targets":slash_targets,"troops":my_army_count,"troop_hp":my_army_hp,"enemy_troops":enemy_troops,"minion_open_cell":has_open,"minion_damaged_buildings":damaged_blds,"lord":lord_kind,"ready":lords[team].hp > 0 and skill_cd[team] <= 0,"ink":ink[team],"charge":skill_charge[team],"need":skill_need(team),"elapsed":elapsed,"farms":farms,"graves":graves,"gate_share":gate_total/(5*B.GATE_HP),"broken":broken,"difficulty":difficulty,"params":ai_params[team]}

func snapshot(team: int) -> Dictionary:
	var candidates: Array = []
	var can_act := not ended and not paused
	var has_intruders := false
	var checked_intruders := false
	var has_ally_unit := false
	var checked_ally_unit := false
	var crystal_count := -1
	for slot: int in [0,1,2,3,FARM_SLOT]:
		if not can_act: break
		var kind: String = kind_at(team,slot)
		if kind.is_empty() or not B.CARDS.has(kind): continue
		var data: Dictionary = B.CARDS[kind]
		if data.get("summon_only",false) or slot_cd(team,slot) > 0.00001 or ink[team] < data.cost: continue
		if data.get("rolling",false):
			var rcol := 0 if team == 0 else L.GRID_COLUMNS-1
			for row: int in range(5):
				if not row in active_lanes: continue
				var cell := Vector2i(rcol,row)
				var pos := L.cell_center(cell)
				if can_play(team,slot,pos): candidates.append({"slot":slot,"kind":kind,"pos":pos,"cell":cell})
			continue
		if kind == "levy":
			if not checked_intruders:
				checked_intruders = true
				has_intruders = not Faction.intruders(self,team).is_empty()
			if not has_intruders: continue
		elif kind == "mana_spring":
			if crystal_count < 0: crystal_count = count_buildings(team,"crystal")
			if crystal_count == 0: continue
		elif kind == "sacrifice":
			if not checked_ally_unit:
				checked_ally_unit = true
				for u: Dictionary in units:
					if u.hp > 0 and u.team == team:
						has_ally_unit = true
						break
			if not has_ally_unit: continue
		var is_spell: bool = data.type == "spell"
		for row: int in range(5):
			if not row in active_lanes: continue
			var row_off := row*L.GRID_COLUMNS
			for col: int in range(9):
				if not is_spell and territory[row_off+col] != team: continue
				var cell := Vector2i(col,row)
				var pos := L.cell_center(cell)
				if can_play(team,slot,pos): candidates.append({"slot":slot,"kind":kind,"pos":pos,"cell":cell})
	var active_lords: Array = []
	for l: Dictionary in lords:
		if lord_active[l.team]: active_lords.append(l)
	return {"team":team,"lord":lords[team].lord,"night_decay":night_decay,"ink":ink[team],"enemy_ink":ink[1-team],"difficulty":difficulty,"elapsed":elapsed,"wave_until":wave_until[team],"memory":memory[team].duplicate(),"recent":recent_lanes[team].duplicate(),"saving":ai_save[team],"params":ai_params[team],"units":units,"buildings":buildings,"lords":active_lords,"gates":gates,"candidates":candidates,"owned_cells":territory.count(team),"active_lanes":active_lanes.duplicate()}

func update_ai(dt: float) -> void:
	if elapsed < ai_start: return
	for team: int in range(2):
		if not ai_enabled[team]: continue
		if not ai_pending[team].is_empty():
			ai_delay[team] -= dt
			if ai_delay[team] <= 0:
				var c: Dictionary = ai_pending[team]
				if c.kind == kind_at(team,c.slot) and play(team,c.slot,c.pos):
					if c.get("wave",false) and elapsed >= wave_until[team]: wave_until[team] = elapsed+ai_params[team].get("wave_time",6.0)
				ai_pending[team] = {}
			continue
		ai_clock[team] -= dt
		if ai_clock[team] <= 0:
			ai_clock[team] = B.AI_TICK
			var plan: Dictionary = AI.skill_plan(skill_state(team))
			ai_save[team] = plan.save
			if plan.cast and cast_skill(team): continue
			ai_pending[team] = AI.decide(snapshot(team))
			ai_delay[team] = [1.2,0.6,0.2][difficulty]
