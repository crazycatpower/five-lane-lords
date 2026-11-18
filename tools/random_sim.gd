extends SceneTree
# Worker for tools/autobalance.py and tools/evolve_ai.py: plays random-deck, random-lord AI matches
# and writes one JSON line per match. Same seed -> same decks, lords and match.
#   godot_console --headless --path . -s tools/random_sim.gd -- --start=1 --count=100 --out=PATH [--cap=900]
# AI strategy weights (enemy_ai.gd params; a JSON object, {} = the hand-written AI):
#   --params-red=FILE --params-blue=FILE   weights for each side
#   --mirror --cand=FILE [--base=FILE]     both sides get the same deck and lord; every seed is played
#                                          twice, the candidate once as red and once as blue
#   --difficulty=0|1|2                     AI difficulty (default 1; 2 = 困難, the evolved weights
#                                          when a side's params are empty)
const Battle = preload("res://battle.gd")
const B = preload("res://balance.gd")
const DeckStore = preload("res://deck_store.gd")
var difficulty := 1
var step_dt := 1.0 / 60.0

func read_params(path: String) -> Dictionary:
	if path.is_empty(): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func _initialize() -> void:
	var start := 1
	var count := 10
	var cap := 900.0
	var out := "user://random_sim.jsonl"
	var mirror := false
	var gauntlet := false
	var gauntlet_cards: Array = []
	var must_have_lords: Array = []
	var must_have_cards: Array = []
	var paths := {"red":"","blue":"","cand":"","base":""}
	for arg: String in OS.get_cmdline_user_args():
		var value := arg.get_slice("=",1)
		if arg.begins_with("--start="): start = int(value)
		elif arg.begins_with("--count="): count = int(value)
		elif arg.begins_with("--cap="): cap = float(value)
		elif arg.begins_with("--out="): out = value
		elif arg == "--mirror": mirror = true
		elif arg == "--gauntlet": gauntlet = true
		elif arg.begins_with("--cards="):
			for item: String in value.split(","):
				var ck := item.strip_edges()
				if B.CARDS.has(ck): gauntlet_cards.append(ck)
		elif arg.begins_with("--must-have-lords="):
			for item: String in value.split(","):
				var k := item.strip_edges()
				if B.LORDS.has(k): must_have_lords.append(k)
		elif arg.begins_with("--must-have-cards="):
			for item: String in value.split(","):
				var k := item.strip_edges()
				if B.CARDS.has(k): must_have_cards.append(k)
		elif arg.begins_with("--params-red="): paths.red = value
		elif arg.begins_with("--params-blue="): paths.blue = value
		elif arg.begins_with("--cand="): paths.cand = value
		elif arg.begins_with("--base="): paths.base = value
		elif arg.begins_with("--difficulty="): difficulty = clampi(int(value),0,2)
		elif arg.begins_with("--hz="): step_dt = 1.0 / maxf(1.0, float(value))
	var cand := read_params(paths.cand)
	var base := read_params(paths.base)
	var file := FileAccess.open(out,FileAccess.WRITE)
	if gauntlet:
		run_gauntlet(file, gauntlet_cards)
		file.close()
		quit()
		return
	var lords: Array = B.LORDS.keys()
	for seed_value: int in range(start,start+count):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var picks: Array = []
		if not must_have_lords.is_empty():
			var must_side := rng.randi_range(0,1)
			var must_pick: String = must_have_lords[rng.randi_range(0,must_have_lords.size()-1)]
			var other_pick: String = ""
			if not must_have_cards.is_empty():
				var can_must_take: bool = must_have_cards.all(func(c: String) -> bool: return B.card_allowed(c,must_pick))
				if can_must_take:
					other_pick = lords[rng.randi_range(0,lords.size()-1)]
				else:
					var eligible: Array = lords.filter(func(l: String) -> bool: return must_have_cards.all(func(c: String) -> bool: return B.card_allowed(c,l)))
					other_pick = eligible[rng.randi_range(0,eligible.size()-1)] if not eligible.is_empty() else lords[rng.randi_range(0,lords.size()-1)]
			else:
				other_pick = lords[rng.randi_range(0,lords.size()-1)]
			picks = [must_pick,other_pick] if must_side == 0 else [other_pick,must_pick]
		else:
			picks = [lords[rng.randi_range(0,lords.size()-1)],lords[rng.randi_range(0,lords.size()-1)]]
		var decks: Array = [DeckStore.random_deck(rng,picks[0]),DeckStore.random_deck(rng,picks[1])]
		if not must_have_cards.is_empty():
			for card: String in must_have_cards:
				var sides: Array = []
				for side: int in range(2):
					if B.card_allowed(card,picks[side]): sides.append(side)
				if not sides.is_empty():
					var has_card: bool = sides.any(func(s: int) -> bool: return card in decks[s])
					if not has_card:
						var target_side: int = sides[rng.randi_range(0,sides.size()-1)]
						var d: Array = decks[target_side]
						var replace_idx := -1
						for i: int in range(d.size()-1,-1,-1):
							if B.CARDS[d[i]].type != "unit":
								replace_idx = i
								break
						if replace_idx == -1: replace_idx = d.size()-1
						d[replace_idx] = card
		if mirror:
			decks[1] = decks[0].duplicate()
			picks[1] = picks[0]
			for cand_side: int in range(2):
				var params: Array = [cand,base] if cand_side == 0 else [base,cand]
				var r := play(seed_value,decks,picks,params,cap)
				r.cand_side = cand_side
				file.store_line(JSON.stringify(r))
		else:
			file.store_line(JSON.stringify(play(seed_value,decks,picks,[read_params(paths.red),read_params(paths.blue)],cap)))
		file.flush()
	file.close()
	quit()

func play(seed_value: int, decks: Array, picks: Array, params: Array, cap: float) -> Dictionary:
	var m := Battle.new(seed_value,decks[0].duplicate(),decks[1].duplicate(),picks[0],picks[1])
	m.difficulty = difficulty
	m.record_events = false
	m.ai_enabled = [true,true]
	var first_play: Array = [{},{}]
	var observed_plays: Array[int] = [0,0]
	m.ai_params = [params[0],params[1]]
	while not m.ended and m.elapsed < cap:
		m.step(step_dt)
		# Read counters only. Do not enable events or consume random values.
		for team: int in range(2):
			if m.stats[team].plays == observed_plays[team]: continue
			observed_plays[team] = m.stats[team].plays
			for kind: String in m.stats[team].used:
				if not first_play[team].has(kind): first_play[team][kind] = m.elapsed
		m.events.clear()
	return {"seed":seed_value,"decks":decks,"lords":picks,"factions":[B.lord_faction(picks[0]),B.lord_faction(picks[1])],"ended":m.ended,"rng_state":str(m.rng.state),"elapsed_exact":var_to_str(m.elapsed),"winner":m.winner if m.ended else -1,"t":snappedf(m.elapsed,0.1),"breach":snappedf(m.first_breach,0.1),"farms_lost_early":[m.stats[0].farms_lost_early,m.stats[1].farms_lost_early],"skills":[m.stats[0].get("skills",0),m.stats[1].get("skills",0)],"used":[m.stats[0].used,m.stats[1].used],"card_stats":[card_stats(m,0,decks[0],first_play[0]),card_stats(m,1,decks[1],first_play[1])],"damage_by_kind":[m.stats[0].damage,m.stats[1].damage]}

func card_stats(m: RefCounted, team: int, deck: Array, first: Dictionary) -> Dictionary:
	var result := {}
	for kind: String in [B.home_card(m.lords[team].lord)]+deck:
		result[kind] = {
			"plays":m.stats[team].used.get(kind,0),
			"first_play":first.get(kind,null),
			"spent":m.stats[team].spent.get(kind,0.0),
			# Combat buckets are unit kinds, not originating cards. Legion damage cannot be
			# recovered from them; null means unavailable, not zero damage.
			"damage":null if B.CARDS[kind].has("members") else m.stats[team].damage.get(kind,0.0)
		}
	return result

const ROLE_ANCHORS := {
	"frontline": {"manor_retainer": 5, "shieldguard": 6, "knight": 21},
	"ranged": {"axe_thrower": 7, "hunter": 9, "arcane_archer": 9},
	"swarm_raid": {"bandit": 3, "raven": 7, "ox": 8, "militia": 11, "ram": 15},
	"support_unit": {"drummer": 4, "healer": 5, "necromancer": 18},
	"defense_building": {"barricade": 1, "scarecrow": 2, "blast_trap": 6, "arcane_tower": 11, "tower": 23},
	"economy": {"sacrifice": 1, "mule_cart": 6, "harvest": 8, "farmer": 12, "mill": 29},
	"spell": {"time_field": 2, "dread_howl": 2, "arcane_shield": 4, "plague": 6, "rain": 8, "chain_lightning": 11, "fire": 20}
}

const ROLE_EXAMINERS := {
	"frontline": ["militia", "axe_thrower", "knight", "hunter"],
	"ranged": ["knight", "militia", "hooknose_flyer", "shieldguard"],
	"swarm_raid": ["axe_thrower", "hunter", "tower", "manor_retainer"],
	"support_unit": ["manor_retainer", "militia", "axe_thrower"],
	"defense_building": ["militia", "ox", "knight", "raven"],
	"economy": ["bearded_imp", "bandit"],
	"spell": ["militia", "hunter", "shieldguard", "knight"]
}

const ECONOMY_CARDS := ["farmer","mule_cart","mill","granary","funeral_cottage","soul_well","blood_altar","mana_battery","supply_depot","harvest","mana_spring","sacrifice","grave_exchange","ossuary"]
const SUPPORT_UNITS := ["healer","drummer","artificer","bellbearer","mourning_maid","sigil_weaver","astrolabe_surveyor","corpse_stitcher","necromancer","pallbearer"]
const SWARM_RAID_UNITS := ["militia","skeleton","mob","bandit","assassin","ox","ram","gatebreaker","raven","hooknose_flyer","fishbeak","bearded_imp","parasite_mite","imp_bomb_runner","phase_rider","blink_blade","aether_hound","runaway_thrall","sky_scavenger"]

func classify_role(kind: String, d: Dictionary) -> String:
	if kind in ECONOMY_CARDS: return "economy"
	var t: String = d.get("type", "unit")
	if t == "spell": return "spell"
	if t == "building": return "defense_building"
	if kind in SUPPORT_UNITS: return "support_unit"
	if kind in SWARM_RAID_UNITS: return "swarm_raid"
	if d.get("projectile", false) or d.get("lob", false) or float(d.get("range", 47.0)) >= 100.0: return "ranged"
	return "frontline"

func lord_for_card(kind: String) -> String:
	match B.card_faction(kind):
		"dark": return "vampire"
		"magic": return "mage"
		"beast": return "beast"
		_: return "lion"

func run_gauntlet(file: FileAccess, target_cards: Array) -> void:
	var baselines := {}
	for role: String in ROLE_EXAMINERS:
		baselines[role] = {}
		for ex: String in ROLE_EXAMINERS[role]:
			baselines[role][ex] = role_trial("", role, ex, true)
	var cards_to_run: Array = target_cards if not target_cards.is_empty() else B.CARDS.keys()
	for kind: String in cards_to_run:
		var d: Dictionary = B.CARDS.get(kind, {})
		if d.is_empty() or d.get("summon_only", false) or kind in ["farm","grave","glutton_nest","crystal"]: continue
		var role := classify_role(kind, d)
		var ex_list: Array = ROLE_EXAMINERS[role]
		var scores := {}
		var total := 0.0
		for ex: String in ex_list:
			var raw := role_trial(kind, role, ex, false)
			var base_val: float = baselines[role][ex]
			var net: float = raw - base_val
			scores[ex] = snappedf(net, 0.1)
			total += net
		var avg_net := total / float(ex_list.size())
		var row := {
			"kind": kind,
			"name": d.name,
			"cost": d.cost,
			"type": d.get("type", "unit"),
			"role_track": role,
			"faction": B.card_faction(kind),
			"examiner_avg": snappedf(avg_net, 0.1),
			"examiner_scores": scores
		}
		file.store_line(JSON.stringify(row))
		file.flush()

func role_trial(kind: String, role: String, ex: String, is_baseline: bool) -> float:
	var m := Battle.new(777, [], [], lord_for_card(kind) if not is_baseline else "lion", "lion")
	m.record_events = false
	m.ai_enabled = [false, false]
	m.night_decay = false
	m.active_lanes = [1, 2, 3]
	m.buildings.clear()
	m.units.clear()
	m.lords[0].hp = 0.0
	m.lords[1].hp = 0.0
	m.lord_active = [false, false]
	m.refresh_territory()
	# Backline setup per role track (keep (1,2) and (2,2) free for candidate buildings!)
	var use_crystal := kind in ["mana_spring","artificer","arcane_golem","rune_workshop"]
	var f0a := m.add_building(0, Vector2i(0, 2), "crystal" if use_crystal else "farm")
	var f0b := m.add_building(0, Vector2i(0, 1), "crystal" if use_crystal else "farm")
	if kind in ["mana_spring","artificer","rune_workshop"]:
		f0a.hp = f0a.max_hp * 0.45
		f0b.hp = f0b.max_hp * 0.45
	if kind == "grave_exchange":
		var bw := m.add_building(0, Vector2i(1, 2), "barricade")
		bw.hp = bw.max_hp * 0.3
	m.add_building(1, Vector2i(8, 2), "farm")
	m.add_building(1, Vector2i(8, 1), "farm")
	m.refresh_territory()
	for lane_y: int in [1, 2, 3]:
		for cx: int in [0, 1, 2]:
			m.territory[lane_y * 9 + cx] = 0
		for cx: int in [6, 7, 8]:
			m.territory[lane_y * 9 + cx] = 1

	# Role-specific Examiner deployment on Side 1 (Blue)
	if ex == "tower":
		m.add_building(1, Vector2i(6, 2), "tower")
	else:
		m.decks[1][0] = ex
		m.hand_cd[1][0] = 0.0
		m.ink[1] = 50.0
		m.play(1, 0, Battle.L.cell_center(Vector2i(6, 2)))
	if role == "frontline" and ex == "axe_thrower":
		m.decks[1][1] = "shieldguard"
		m.hand_cd[1][1] = 0.0
		m.ink[1] = 50.0
		m.play(1, 1, Battle.L.cell_center(Vector2i(5, 2)))
	elif role == "ranged" and ex == "shieldguard":
		m.decks[1][1] = "hunter"
		m.hand_cd[1][1] = 0.0
		m.ink[1] = 50.0
		m.play(1, 1, Battle.L.cell_center(Vector2i(7, 2)))
	elif role == "defense_building":
		m.decks[1][1] = "manor_retainer"
		m.hand_cd[1][1] = 0.0
		m.ink[1] = 50.0
		m.play(1, 1, Battle.L.cell_center(Vector2i(5, 2)))
	elif role == "spell" and ex in ["hunter", "knight"]:
		m.decks[1][1] = "militia"
		m.hand_cd[1][1] = 0.0
		m.ink[1] = 50.0
		m.play(1, 1, Battle.L.cell_center(Vector2i(5, 2)))

	var ex_hp := 0.0
	for u: Dictionary in m.units:
		if u.team == 1: ex_hp += u.max_hp
	for b: Dictionary in m.buildings:
		if b.team == 1: ex_hp += b.max_hp

	# Role-specific Escort deployment on Side 0 (Red)
	if role == "ranged":
		m.decks[0][1] = "shieldguard"
		m.hand_cd[0][1] = 0.0
		m.ink[0] = 50.0
		m.play(0, 1, Battle.L.cell_center(Vector2i(2, 2)))
	elif role in ["support_unit", "spell", "economy", "defense_building"]:
		m.decks[0][1] = "manor_retainer"
		m.hand_cd[0][1] = 0.0
		m.ink[0] = 50.0
		var esc_x := 1 if role == "defense_building" else 2
		m.play(0, 1, Battle.L.cell_center(Vector2i(esc_x, 2)))
		if role in ["support_unit", "defense_building"]:
			for u: Dictionary in m.units:
				if u.team == 0: u.hp = u.max_hp * 0.65

	var cast_later := false
	if not is_baseline:
		var d: Dictionary = B.CARDS[kind]
		if d.type == "spell":
			cast_later = true
		else:
			m.decks[0][0] = kind
			m.hand_cd[0][0] = 0.0
			m.ink[0] = 50.0
			var cell_x := 2
			if role in ["ranged", "support_unit", "economy"]: cell_x = 1
			m.play(0, 0, Battle.L.cell_center(Vector2i(cell_x, 2)))

	# Reset both purses to 10.0 after deployment so economy income never hits the 50-ink cap
	m.ink[0] = 10.0
	m.ink[1] = 10.0
	var ink0_after: float = 10.0
	var ink1_after: float = 10.0
	var spell_done := false
	var sim_time := 32.0 if role in ["economy", "defense_building"] else 18.0
	var dt := 1.0 / 30.0
	for step_i: int in range(int(sim_time / dt)):
		if cast_later and not spell_done:
			var t := step_i * dt
			var ready_now := t >= 2.2
			if kind == "levy":
				ready_now = m.units.any(func(u: Dictionary) -> bool: return u.hp > 0 and u.team == 1 and not u.get("flying",false) and m.territory_owner(m.cell_at(u.pos)) == 0)
			if ready_now or t >= 6.5:
				spell_done = true
				var ink_before_cast: float = float(m.ink[0])
				m.decks[0][0] = kind
				m.hand_cd[0][0] = 0.0
				m.ink[0] = 50.0
				var target_pos := Battle.L.cell_center(Vector2i(4, 2))
				if kind == "rolling_boulder":
					target_pos = Battle.L.cell_center(Vector2i(0, 2))
				elif kind in ["mana_spring","harvest"]:
					target_pos = Battle.L.cell_center(Vector2i(0, 2))
				elif kind == "grave_exchange":
					target_pos = Battle.L.cell_center(Vector2i(1, 2))
				elif kind in ["arcane_shield","charge_horn","mourning_shroud","berserk_blood","phase_shift","mirror_clone","pack_ambush","feral_mutation","sacrifice"]:
					for u: Dictionary in m.units:
						if u.hp > 0 and u.team == 0:
							target_pos = u.pos
							break
				else:
					for u: Dictionary in m.units:
						if u.hp > 0 and u.team == 1:
							target_pos = u.pos
							break
				m.play(0, 0, target_pos)
				var cast_gain: float = (float(m.ink[0]) - (50.0 - float(B.CARDS[kind].cost)))
				m.ink[0] = clampf(ink_before_cast + cast_gain, 0.0, B.MAX_INK)
		if role == "economy" and kind == "supply_depot" and step_i % 160 == 80:
			m.spawn_unit(0, 2, "militia", Battle.L.cell_center(Vector2i(2, 2)))
			m.ink[0] = float(m.ink[0]) + 1.0
		elif role == "economy" and kind == "mana_battery" and step_i % 90 == 45:
			for b: Dictionary in m.buildings:
				if b.team == 0 and b.kind == "mana_battery":
					b.battery = int(b.get("battery", 0)) + 1
					if b.battery >= B.CARDS.mana_battery.max_charges:
						preload("res://expansion_more.gd").burst_battery(m, b)
		m.step(dt)
		m.events.clear()

	var red_hp := 0.0
	var blue_hp := 0.0
	for u: Dictionary in m.units:
		if u.hp <= 0: continue
		if u.team == 0: red_hp += minf(u.hp, u.max_hp)
		else: blue_hp += minf(u.hp, u.max_hp)
	for b: Dictionary in m.buildings:
		if b.hp <= 0: continue
		if b.team == 1: blue_hp += minf(b.hp, b.max_hp)
		elif b.cell.x >= 2: red_hp += minf(b.hp, b.max_hp) * 0.45
	var gate_diff: float = float(B.GATE_HP - (m.gates[1][1] + m.gates[1][2] + m.gates[1][3]) / 3.0) - float(B.GATE_HP - (m.gates[0][1] + m.gates[0][2] + m.gates[0][3]) / 3.0)
	var net_ink: float = (float(m.ink[0]) - ink0_after) - (float(m.ink[1]) - ink1_after)
	if role == "economy":
		return net_ink * 65.0 + (red_hp - blue_hp) * 0.15
	return (ex_hp - blue_hp) * 1.15 + red_hp * 0.70 + gate_diff * 1.25 + net_ink * 30.0
