extends SceneTree
# Core checks only (producer 2026-11-18: at most 50). Each check guards something that would break the
# game or silently change match results; loops over every card / lord / sprite report as ONE check and
# list the offenders. Add a new check only by folding it into the closest existing one.
# The pre-trim suite (1493 checks) is kept in .runtime/quick-test-before/ for reference.

const Battle = preload("res://battle.gd")
const B = preload("res://balance.gd")
const DS = preload("res://deck_store.gd")
const EnemyAI = preload("res://enemy_ai.gd")
const ExpansionMore = preload("res://expansion_more.gd")
const L = preload("res://layout.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(15).timeout.connect(func(): quit(2))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

class MockCinematicHost extends RefCounted:
	var adventure = null
	var shake_enabled := true
	var fx_enabled := true
	var mirror_view := false
	var field_mirror := false
	var clock := 0.0
	var selected := -1
	var dragging := false
	var intro_left := 0.0
	var music = null
	func view_mirror() -> Transform2D:
		return Transform2D.IDENTITY

# A quiet battlefield: no AI, no lords, optionally no starting buildings.
func quiet(seed_value: int, lord_a := "lion", lord_b := "lion", clear_buildings := true) -> Battle:
	var m := Battle.new(seed_value, [], [], lord_a, lord_b)
	m.ai_enabled = [false, false]
	m.lords[0].hp = 0
	m.lords[1].hp = 0
	m.lord_active = [false, false]
	m.units.clear()
	if clear_buildings: m.buildings.clear()
	return m

func ready_unit(m: Battle, team: int, lane: int, kind: String, pos: Vector2) -> Dictionary:
	var u := m.spawn_unit(team, lane, kind, pos)
	u.spawn_delay = 0.0
	return u

func run() -> void:
	data_checks()
	combat_checks()
	lord_checks()
	economy_and_roguelike_checks()
	new_card_checks()
	presentation_checks()
	if failures > 0:
		printerr("FAIL: %d checks, %d failures" % [checks, failures])
		quit(1)
	else:
		print("QUICK PASS: %d checks, 0 failures" % checks)
		quit(0)

# ---------------- data and determinism (9) ----------------
func data_checks() -> void:
	var problems := B.validate()
	check(problems.is_empty(), "balance.gd validate: " + str(problems))
	var rogue_errors := preload("res://roguelike_catalog.gd").validate()
	check(rogue_errors.is_empty(), "roguelike data: " + str(rogue_errors))
	var catalog = preload("res://campaign_catalog.gd")
	var campaign_errors: Array[String] = catalog.validate()
	check(campaign_errors.is_empty(), "campaign data: " + str(campaign_errors))
	var obtainable := {}
	for k: String in catalog.STARTER_CARDS: obtainable[k] = true
	for stage: Dictionary in catalog.stages():
		for k: String in stage.get("rewards", []): obtainable[k] = true
	var missing_cards: Array = DS.pool("adventure").filter(func(k: String) -> bool: return not obtainable.has(k))
	var missing_lords: Array = B.LORDS.keys().filter(func(lk: String) -> bool: return lk != "adventure" and not lk in catalog.UNLOCK_LORDS.values())
	check(missing_cards.is_empty() and missing_lords.is_empty(), "campaign can obtain every adventure card and lord (missing %s / %s)" % [str(missing_cards), str(missing_lords)])
	var ratio_rng := RandomNumberGenerator.new()
	ratio_rng.seed = 20261119
	var ratios_ok := true
	for lk: String in B.LORDS:
		if not DS.LORD_BEST_RATIOS.has(lk):
			ratios_ok = false
			break
		var want: Dictionary = DS.lord_best_ratio(lk)
		var total_c := 0
		for gid: int in [0, 1, 2, 3]: total_c += int(want.get(gid, 0))
		var rd := DS.balanced_random_deck(ratio_rng, lk)
		if total_c != 8 or not DS.valid(rd, lk):
			ratios_ok = false
			break
		var got := {0: 0, 1: 0, 2: 0, 3: 0}
		for ck: String in rd: got[B.card_group(ck)] += 1
		if got != want:
			ratios_ok = false
			break
	for pe: Dictionary in DS.PRACTICE_RATIOS:
		var ptotal := 0
		for gid: int in [0, 1, 2, 3]: ptotal += int(pe.ratio.get(gid, 0))
		var pd := DS.balanced_random_deck(ratio_rng, "lion", pe.ratio)
		var pgot := {0: 0, 1: 0, 2: 0, 3: 0}
		for ck: String in pd: pgot[B.card_group(ck)] += 1
		if ptotal != 8 or not DS.valid(pd, "lion") or pgot != pe.ratio:
			ratios_ok = false
			break
	check(DS.valid(B.DEFAULT_DECK, B.DEFAULT_LORD) and load("res://game.gd") != null and ratios_ok, "default deck, game.gd, and lord/practice ratios are valid")
	var Upgrades = preload("res://card_upgrades.gd")
	var Keywords = preload("res://card_keywords.gd")
	var bad_cards: Array = B.CARDS.keys().filter(func(k: String) -> bool:
		var kws: Array = Keywords.for_card(k)
		return not Upgrades.can_upgrade(k, {}) or kws.is_empty() or not kws.all(func(kw: String) -> bool: return Keywords.KEYWORDS.has(kw)))
	check(bad_cards.is_empty(), "every card has an upgrade option and valid keywords (bad: %s)" % str(bad_cards))
	var bounds := Rect2(L.GRID_ORIGIN, L.GRID_SIZE).grow(0.01)
	var bad_spells: Array = []
	for ck: String in B.CARDS:
		var cdata: Dictionary = B.CARDS[ck]
		if cdata.type != "spell" or cdata.get("rolling", false): continue
		var sh: Vector2i = B.spell_shape(cdata)
		var ok := sh.x >= 1 and sh.x <= L.GRID_COLUMNS and sh.y >= 1 and sh.y <= L.GRID_ROWS
		for pt: Vector2 in [L.GRID_ORIGIN, L.GRID_ORIGIN + L.GRID_SIZE, L.GRID_ORIGIN - Vector2(50, 50), L.GRID_ORIGIN + L.GRID_SIZE + Vector2(50, 50)]:
			ok = ok and bounds.encloses(B.spell_rect(pt, cdata))
		if not ok: bad_spells.append(ck)
	check(bad_spells.is_empty(), "every spell area has a valid grid shape inside the battlefield (bad: %s)" % str(bad_spells))
	var a := Battle.new(7)
	var b := Battle.new(7)
	for i: int in range(360):
		a.step(1.0 / 60.0)
		b.step(1.0 / 60.0)
	check(a.winner == b.winner and is_equal_approx(a.elapsed, b.elapsed) and a.rng.state == b.rng.state, "deterministic simulation")
	var src = Battle.new(123, B.DEFAULT_DECK, B.CLASSIC_UNDERWORLD_DECK, "lion", "underworld")
	var recovered: Array = preload("res://match_recorder.gd").original_decks(src.decks, 123)
	var replay = Battle.new(123, recovered[0], recovered[1], "lion", "underworld")
	check(src.decks == replay.decks and src.rng.state == replay.rng.state, "recording restores original deck order and RNG")

# ---------------- combat rules (10) ----------------
func combat_checks() -> void:
	# Charge: first strike, then recharge only after 3 s of marching.
	var cb := quiet(31)
	var ox_u := cb.spawn_unit(0, 2, "ox", Vector2(300, 420))
	var dummy := cb.spawn_unit(1, 2, "militia", Vector2(330, 420))
	var fresh: bool = not ox_u.charged and is_equal_approx(cb.movement_speed(ox_u), 120.0)
	cb.attack(ox_u, dummy)
	var struck: bool = ox_u.charged and dummy.hp <= 0 and is_equal_approx(cb.movement_speed(ox_u), B.OX_SLOW_SPEED)
	cb.remove_dead()
	for i: int in range(120): cb.step(1.0 / 60.0)
	var held: bool = ox_u.charged
	for i: int in range(65): cb.step(1.0 / 60.0)
	check(fresh and struck and held and not ox_u.charged, "ox charges, strikes, and recharges only after 3 s of marching")

	# Stealth: attacking breaks it, marching restores it, a watchtower reveals for good.
	var sb := quiet(32)
	var bandit := sb.spawn_unit(0, 2, "bandit", Vector2(300, 420))
	var victim := sb.spawn_unit(1, 2, "skeleton", Vector2(330, 420))
	var hidden_at_start: bool = bandit.stealthed
	sb.attack(bandit, victim)
	sb.damage(victim, victim.hp, 0, "bandit")
	sb.remove_dead()
	var broke: bool = not bandit.stealthed
	for i: int in range(185): sb.step(1.0 / 60.0)
	var restealthed: bool = bandit.stealthed
	var tower := sb.add_building(1, Vector2i(3, 2), "watchtower")
	bandit.pos = tower.pos - Vector2(40, 0)
	sb.step(1.0 / 60.0)
	sb.buildings.clear()
	for i: int in range(185): sb.step(1.0 / 60.0)
	check(hidden_at_start and broke and restealthed and bandit.revealed and not bandit.stealthed, "stealth breaks on attack, returns after marching, and a watchtower reveals it for good")

	# Poison stacking, immunity for buildings and mechanical units, and healing; armor keeps a 1-damage floor.
	var pb := quiet(33)
	var sg := pb.spawn_unit(0, 2, "shieldguard", Vector2(400, 420))
	sg.poison_stacks = 3
	sg.poison_left = 2.0
	sg.poison_timer = 1.0
	sg.poison_team = 1
	sg.hex_stacks = 3
	sg.hex_left = 2.0
	sg.hex_timer = 1.0
	sg.hex_team = 1
	pb.heal(pb.spawn_unit(0, 2, "healer", Vector2(380, 420)), 0.1)
	var heal_ok: bool = int(sg.poison_stacks) == 2 and int(sg.hex_stacks) == 2

	# Hex stacks infinitely and expires cleanly after duration.
	var hex_pb := quiet(35)
	var hex_prey := ready_unit(hex_pb, 0, 2, "pouch_beast", Vector2(500, 420))
	for _hi: int in range(4):
		ExpansionMore.add_hex(hex_pb, hex_prey, 1, "old_witch", 20.0, 1.0, 2)
	var hex_4_ok: bool = int(hex_prey.get("hex_stacks", 0)) == 4
	for _hi: int in range(63): hex_pb.step(1.0 / 60.0)
	var hex_dmg_ok: bool = is_equal_approx(hex_prey.hp, hex_prey.max_hp - 80.0)
	for _hi: int in range(126): hex_pb.step(1.0 / 60.0)
	var hex_exp_ok: bool = int(hex_prey.get("hex_stacks", 0)) == 0 and is_equal_approx(hex_prey.hp, hex_prey.max_hp - 160.0)

	# Plague stacks infinitely on organic troops while buildings and mechanical/construct units are immune.
	var imm_pb := quiet(36)
	var org := ready_unit(imm_pb, 0, 2, "pouch_beast", L.cell_center(Vector2i(3, 2)))
	var imm_farm := imm_pb.add_building(0, Vector2i(3, 2), "farm")
	var imm_units: Array = [
		ready_unit(imm_pb, 0, 2, "catapult", L.cell_center(Vector2i(3, 2)) + Vector2(0, 10)),
		ready_unit(imm_pb, 0, 2, "ram", L.cell_center(Vector2i(3, 2)) + Vector2(0, 14)),
		ready_unit(imm_pb, 0, 2, "orrery_walker", L.cell_center(Vector2i(3, 2)) + Vector2(0, -10)),
		ready_unit(imm_pb, 0, 2, "arcane_golem", L.cell_center(Vector2i(3, 2)) + Vector2(0, -14)),
		ready_unit(imm_pb, 0, 0, "ward_guard", L.cell_center(Vector2i(3, 0))),
	]
	var esc_mil := ready_unit(imm_pb, 0, 4, "militia", L.cell_center(Vector2i(3, 4)))
	imm_pb.add_zone(org.pos, 1, 290.0, 10.0)
	imm_pb.add_zone(imm_units[4].pos, 1, 150.0, 10.0)
	ExpansionMore.add_hex(imm_pb, imm_farm, 1, "old_witch", 20.0, 1.0, 2)
	for iu: Dictionary in imm_units:
		ExpansionMore.add_hex(imm_pb, iu, 1, "old_witch", 20.0, 1.0, 2)
	for _pi: int in range(186): imm_pb.step(1.0 / 60.0)
	var imm_ok: bool = int(org.get("poison_stacks", 0)) == 3 and is_equal_approx(org.hp, org.max_hp - 210.0)
	imm_ok = imm_ok and is_equal_approx(imm_farm.hp, imm_farm.max_hp) and int(imm_farm.get("hex_stacks", 0)) == 0
	for iu: Dictionary in imm_units:
		imm_ok = imm_ok and is_equal_approx(iu.hp, iu.max_hp) and int(iu.get("poison_stacks", 0)) == 0 and int(iu.get("hex_stacks", 0)) == 0
	imm_ok = imm_ok and B.poison_immune(imm_units[1]) and not B.poison_immune(esc_mil)

	check(heal_ok and hex_4_ok and hex_dmg_ok and hex_exp_ok and imm_ok, "poison stacks infinitely, healer removes 1 stack of each, and buildings/mechanical units are immune")
	var armor: float = float(B.CARDS.shieldguard.armor)
	var hp0: float = sg.hp
	pb.damage(sg, armor, 1, "knight")
	var floor_ok := is_equal_approx(sg.hp, hp0 - 1.0)
	pb.damage(sg, armor + 16.0, 1, "knight")
	check(floor_ok and is_equal_approx(sg.hp, hp0 - 17.0), "armor subtracts from each hit but always lets 1 damage through")

	# Old witch: area curse plus damage over time, without leaving plague clouds.
	var wb := quiet(11, "lion", "lion", false)
	ready_unit(wb, 0, 2, "old_witch", Vector2(520, 420))
	var sk1 := ready_unit(wb, 1, 2, "skeleton", Vector2(610, 420))
	var sk2 := ready_unit(wb, 1, 2, "skeleton", Vector2(635, 420))
	for i: int in range(180): wb.step(1.0 / 60.0)
	check(sk1.hp <= 0 and sk2.hp <= 0 and wb.zones.is_empty(), "old_witch area curse and damage over time kill a cluster without plague clouds")

	# Melee reach is measured edge to edge.
	var eb := quiet(34)
	var mil := eb.spawn_unit(0, 2, "militia", Vector2(400, 420))
	var dragon := eb.spawn_unit(1, 2, "thorn_dragon", Vector2(490, 420))
	eb.step(0.001)
	var big_ok: bool = is_same(eb.choose_target(mil, B.CARDS.militia), dragon)
	dragon.hp = 0
	eb.spawn_unit(1, 2, "militia", Vector2(490, 420))
	eb.remove_dead()
	eb.step(0.001)
	var edge_ok: bool = big_ok and eb.choose_target(mil, B.CARDS.militia).is_empty()
	var rp := eb.spawn_unit(0, 2, "reaper", L.cell_center(Vector2i(3, 2)))
	var rp_foe := eb.spawn_unit(1, 2, "knight", L.cell_center(Vector2i(4, 2)))
	var adj_farm := eb.add_building(1, Vector2i(4, 1), "farm")
	eb.build_lookups()
	eb.attack(rp, rp_foe)
	check(edge_ok and adj_farm.hp < adj_farm.max_hp, "melee reach is edge to edge, and 3-lane melee cleave hits enemy buildings in adjacent lanes")

	# Gates: melee and spells hit in full, ranged hits are halved; ranged troops shoot gates from range.
	var rgt := Battle.new(42, B.DEFAULT_DECK, B.DEFAULT_DECK, "iron", "lion")
	rgt.ai_enabled = [false, false]
	rgt.lord_active = [false, true]
	var gate_y: float = L.cell_center(Vector2i(0, 2)).y
	rgt.lords[1].lane = 2
	rgt.lords[1].pos = Vector2(rgt.lords[1].pos.x, gate_y)
	var lord_hp0: float = rgt.lords[1].hp
	var hunter := ready_unit(rgt, 0, 2, "hunter", Vector2(L.gate_stop(1) - 250.0, gate_y))
	rgt.build_lookups()
	var aim: Dictionary = rgt.choose_target(hunter, B.CARDS.hunter)
	var x0: float = hunter.pos.x
	for i: int in range(30): rgt.step(0.05)
	check(aim.get("kind", "") == "gate" and is_equal_approx(hunter.pos.x, x0) and rgt.gates[1][2] < B.GATE_HP and is_equal_approx(rgt.lords[1].hp, lord_hp0), "ranged troops shoot the gate from range without walking up or hitting the lord")
	var gate_ok := true
	for hit: Array in [[40.0, "knight", 40.0], [36.0, "hunter", 18.0], [130.0, "fire", 130.0]]:
		rgt.gates[1][1] = B.GATE_HP
		rgt.hit_gate(1, 1, hit[0], hit[1])
		gate_ok = gate_ok and is_equal_approx(rgt.gates[1][1], B.GATE_HP - hit[2])
	check(gate_ok, "gate damage: melee and spells in full, ranged halved")

	# Glutton nest: hidden and immune until it bites; devours up to bite_max allies (2x feed) or foes, paying gold gradually while chewing.
	var gn := Battle.new(13, [], [], "beast", "lion")
	gn.ai_enabled = [false, false]
	gn.lords[0].hp = 0
	gn.lords[1].hp = 0
	gn.lord_active = [false, false]
	var Nest = preload("res://glutton_nest.gd")
	var nest := gn.add_building(0, Vector2i(2, 2), "glutton_nest")
	gn.damage(nest, 100.0, 1, "fire")
	var immune: bool = Nest.hidden(nest) and nest.hp == nest.max_hp
	var prey := ready_unit(gn, 1, 2, "ox", nest.pos)
	var prey_hp: float = minf(prey.max_hp, float(B.CARDS.glutton_nest.bite_cap))
	gn.step(1.0 / 60.0)
	var gold0: float = gn.ink[0]
	Nest.update(gn, nest, B.CARDS.glutton_nest.windup)
	var bite_now_ok: bool = prey.hp <= 0 and not Nest.hidden(nest) and is_equal_approx(gn.ink[0], gold0) and int(nest.get("last_gold", 0)) == Nest.meal_gold(prey_hp)
	Nest.update(gn, nest, float(nest.digest_total) * 0.5)
	var mid_gold_ok: bool = gn.ink[0] > gold0 and gn.ink[0] < gold0 + float(nest.last_gold)
	Nest.update(gn, nest, float(nest.digest_total))
	check(immune and bite_now_ok and mid_gold_ok and is_equal_approx(gn.ink[0], gold0 + float(nest.last_gold)) and Nest.hidden(nest), "glutton_nest hides immune, pays gold+2 gradually during chewing, then hides again")
	gn.units.clear()
	gn.buildings.clear()
	var mouth := gn.add_building(0, Vector2i(2, 2), "glutton_nest")
	var tank := ready_unit(gn, 1, 2, "arcane_golem", mouth.pos)
	var own := ready_unit(gn, 0, 2, "militia", mouth.pos + Vector2(10.0, 0.0)) # closer ally spared when 4 foes exist
	var swarm: Array = []
	for i: int in range(4): swarm.append(ready_unit(gn, 1, 2, "militia", mouth.pos + Vector2(30.0 + i * 20.0, 0.0)))
	var gn_ink0: float = gn.ink[0]
	Nest.update(gn, mouth, 0.01)
	Nest.update(gn, mouth, B.CARDS.glutton_nest.windup)
	var eaten_foes: int = ([tank] + swarm).filter(func(u: Dictionary) -> bool: return u.hp < u.max_hp).size()
	var feed_check: int = Nest.meal_gold(900.0 + swarm[0].max_hp + swarm[1].max_hp + swarm[2].max_hp)
	Nest.update(gn, mouth, 10.0)
	var earned_partial: float = gn.ink[0] - gn_ink0
	mouth.hp = 0.0
	Nest.update(gn, mouth, 100.0)
	gn.units.clear()
	gn.buildings.clear()
	var mouth2 := gn.add_building(0, Vector2i(2, 2), "glutton_nest")
	var foe2 := ready_unit(gn, 1, 2, "militia", mouth2.pos + Vector2(20.0, 0.0))
	var ally2 := ready_unit(gn, 0, 2, "militia", mouth2.pos + Vector2(5.0, 0.0))
	Nest.update(gn, mouth2, 0.01)
	Nest.update(gn, mouth2, B.CARDS.glutton_nest.windup)
	var fallback_ok: bool = foe2.hp <= 0 and ally2.hp <= 0 and int(mouth2.last_gold) == Nest.meal_gold(foe2.max_hp + ally2.max_hp * 2.0)
	check(int(B.CARDS.glutton_nest.bite_max) == 4 and is_equal_approx(tank.hp, tank.max_hp - B.CARDS.glutton_nest.bite_cap) and is_equal_approx(own.hp, own.max_hp) and eaten_foes == 4 and is_equal_approx(swarm[3].hp, swarm[3].max_hp) and int(mouth.last_gold) == feed_check and earned_partial > 0.0 and is_equal_approx(gn.ink[0] - gn_ink0, earned_partial) and earned_partial < float(mouth.last_gold) and fallback_ok, "glutton_nest prioritizes 4 nearest foes before allies(2x), caps at bite_cap, and stops unpaid gold if destroyed")

	# Damage buildings hit enemy buildings only when no enemy troop is in range.
	var tw := quiet(35)
	tw.add_building(0, Vector2i(3, 2), "tower")
	var foe_farm := tw.add_building(1, Vector2i(5, 2), "farm")
	for i: int in range(120): tw.step(1.0 / 60.0)
	var farm_hit: bool = foe_farm.hp < foe_farm.max_hp
	var farm_hp: float = foe_farm.hp
	var intruder := ready_unit(tw, 1, 2, "knight", L.cell_center(Vector2i(4, 2)))
	intruder.speed = 0.0
	tw.projectiles.clear() # an arrow already flying at the farm still lands
	for i: int in range(120): tw.step(1.0 / 60.0)
	check(farm_hit and is_equal_approx(foe_farm.hp, farm_hp) and intruder.hp < intruder.max_hp, "towers shoot enemy buildings only while no enemy troop is in range")

	# Building reach is counted in cells (floor(range / cell width)); a lane shooter fires at a building ahead.
	var Grid = preload("res://grid_rules.gd")
	var rc := quiet(37)
	var arcane := rc.add_building(0, Vector2i(3, 2), "arcane_tower")
	var diagonal := ready_unit(rc, 1, 3, "knight", L.cell_center(Vector2i(4, 3)))
	var two_away := ready_unit(rc, 1, 3, "knight", L.cell_center(Vector2i(5, 3)))
	var near_pick: Dictionary = Grid.pick(rc, arcane, [diagonal, two_away])
	var far_pick: Dictionary = Grid.pick(rc, arcane, [two_away])
	var ballista := rc.add_building(0, Vector2i(1, 1), "ballista_tower")
	rc.add_building(1, Vector2i(5, 1), "farm")
	rc.build_lookups()
	preload("res://expansion_more.gd").fire_lane_shooter(rc, ballista, B.CARDS.ballista_tower)
	check(is_same(near_pick, diagonal) and far_pick.is_empty() and rc.projectiles.any(func(p: Dictionary) -> bool: return p.get("lane_bolt", false)), "building reach follows its cell shape (祕法塔: diagonal yes, 2 ahead + 1 down no), and 重弩塔 fires at an enemy building ahead")

	# Multi-lane cards (佔位): every covered cell must be ours; no shifting inward or back.
	var fp := Battle.new(36, [], [], "lion", "lion")
	fp.ai_enabled = [false, false]
	fp.lord_active = [false, false]
	fp.decks[0][0] = "mob"
	fp.hand_cd[0][0] = 0.0
	fp.ink[0] = 50.0
	var top_refused: bool = fp.play_check(0, 0, L.cell_center(Vector2i(1, 0))) == Battle.Refusal.FOOTPRINT
	fp.units.clear()
	var mob_played: bool = fp.play(0, 0, L.cell_center(Vector2i(1, 2)))
	var mob_lanes: Array = [1, 2, 3].map(func(l: int) -> int: return fp.units.filter(func(u: Dictionary) -> bool: return u.kind == "mob" and u.lane == l).size())
	fp.units.clear()
	fp.decks[0][0] = "spearbow"
	fp.hand_cd[0][0] = 0.0
	fp.ink[0] = 50.0
	var back_refused: bool = fp.play_check(0, 0, L.cell_center(Vector2i(0, 2))) == Battle.Refusal.FOOTPRINT
	fp.play(0, 0, L.cell_center(Vector2i(1, 2)))
	var front: Array = fp.units.filter(func(u: Dictionary) -> bool: return u.kind == "militia" and Grid.cell_of(u.pos).x == 1)
	var rear: Array = fp.units.filter(func(u: Dictionary) -> bool: return u.kind == "hunter" and Grid.cell_of(u.pos).x == 0)
	fp.units.clear()
	fp.decks[0][0] = "necromancer"
	fp.hand_cd[0][0] = 0.0
	fp.ink[0] = 50.0
	var necro_refused: bool = fp.play_check(0, 0, L.cell_center(Vector2i(0, 2))) == Battle.Refusal.FOOTPRINT and fp.play_check(0, 0, L.cell_center(Vector2i(1, 0))) == Battle.Refusal.FOOTPRINT
	var necro_played: bool = fp.play(0, 0, L.cell_center(Vector2i(1, 2)))
	var necro_ok: bool = fp.units.filter(func(u: Dictionary) -> bool: return u.kind == "necromancer" and Grid.cell_of(u.pos) == Vector2i(0, 2)).size() == 1 and fp.units.filter(func(u: Dictionary) -> bool: return u.kind == "skeleton" and Grid.cell_of(u.pos).x == 1).size() == 3
	for i: int in range(10): fp.step(0.05)
	var no_entry_summon: bool = fp.units.size() == 4
	for i: int in range(200): fp.step(0.05)
	var necro_lanes: Array = [1, 2, 3].map(func(l: int) -> int: return fp.units.filter(func(u: Dictionary) -> bool: return u.kind == "skeleton" and u.lane == l).size())
	check(top_refused and mob_played and mob_lanes == [4, 4, 4] and back_refused and front.size() == 4 and rear.size() == 2 and front.filter(func(u: Dictionary) -> bool: return u.lane == 2).size() == 2 and necro_refused and necro_played and necro_ok and no_entry_summon and necro_lanes == [2, 2, 2], "暴民 takes 1x3, 槍弓混編 2x2, 死靈法師 1+1x3 (no entry summon, 3-lane periodic); refused unless every cell is ours (mob %s, necro %s)" % [str(mob_lanes), str(necro_lanes)])

	# The placement preview shows exactly where each squad will stand (same rules as deploy).
	var pv := Battle.new(38, [], [], "lion", "lion")
	pv.ai_enabled = [false, false]
	pv.lord_active = [false, false]
	var mismatched: Array = []
	for pc: Array in [["aether_hound", Vector2i(1, 1)], ["dog_cannon", Vector2i(1, 3)], ["ward_phalanx", Vector2i(1, 2)], ["orrery_walker", Vector2i(1, 1)], ["militia", Vector2i(1, 1)], ["shieldguard", Vector2i(1, 2)], ["skeleton", Vector2i(1, 3)], ["guard", Vector2i(1, 2)], ["ram", Vector2i(1, 1)], ["mob", Vector2i(1, 2)], ["gold_monster", Vector2i(1, 2)], ["necromancer", Vector2i(1, 2)], ["pallbearer", Vector2i(1, 2)], ["blink_blade", Vector2i(1, 2)], ["aether_hound", Vector2i(1, 2)], ["raven", Vector2i(1, 2)], ["dark_wizard", Vector2i(1, 2)], ["thorn_mother", Vector2i(1, 2)]]:
		pv.units.clear()
		pv.decks[0][0] = pc[0]
		pv.hand_cd[0][0] = 0.0
		pv.ink[0] = 50.0
		var expect: Dictionary = {}
		for sq: Array in Grid.spawn_preview(pv, 0, pc[0], pc[1]): expect[[sq[0], sq[2]]] = int(expect.get([sq[0], sq[2]], 0)) + int(sq[1])
		if not pv.play(0, 0, L.cell_center(pc[1])):
			mismatched.append(pc[0] + " (refused)")
			continue
		var got: Dictionary = {}
		for u: Dictionary in pv.units: got[[u.kind, u.pos]] = int(got.get([u.kind, u.pos], 0)) + 1
		if got != expect: mismatched.append(pc[0])
	# 結界護衛 takes half of what a nearby ally suffers, and an artificer repairs it (construct).
	var wd := Battle.new(39, [], [], "mage", "lion")
	wd.ai_enabled = [false, false]
	wd.lord_active = [false, false]
	wd.units.clear()
	var ward: Dictionary = wd.spawn_unit(0, 2, "ward_guard", L.cell_center(Vector2i(2, 2)))
	var warded: Dictionary = wd.spawn_unit(0, 2, "prism_mage", ward.pos - Vector2(40, 0))
	var smith: Dictionary = wd.spawn_unit(0, 2, "artificer", ward.pos - Vector2(60, 0))
	for x: Dictionary in [ward, warded, smith]: x.spawn_delay = 0.0
	wd.build_lookups()
	wd.damage(warded, 100.0, 1, "militia")
	var ward_ok: bool = is_equal_approx(warded.hp, warded.max_hp - 50.0) and is_equal_approx(ward.hp, ward.max_hp - 50.0)
	for i: int in range(90): wd.step(1.0 / 30.0)
	ward_ok = ward_ok and is_equal_approx(ward.hp, ward.max_hp)
	# Grid blasts: a cross misses the diagonal a nine-square hits; a row runs away from the attacker.
	var bc: Vector2 = L.cell_center(Vector2i(5, 2))
	var east := {"pos": L.cell_center(Vector2i(6, 2)), "lane": 2}
	var corner := {"pos": L.cell_center(Vector2i(6, 3)), "lane": 3}
	ward_ok = ward_ok and B.blast_hits(bc, "cross", 1, east) and not B.blast_hits(bc, "cross", 1, corner) and B.blast_hits(bc, "square", 1, corner) and B.blast_hits(bc, "row2", 1, east) and not B.blast_hits(bc, "row2", -1, east)
	check(mismatched.is_empty() and ward_ok, "placement preview matches where every squad really stands, and 結界護衛 shares damage and is repaired by an artificer, and grid blasts cover their cells (mismatch: %s, ward/blast %s)" % [str(mismatched), ward_ok])

	# Grid spells hit exactly their tiles.
	var g := quiet(63, "mage", "lion")
	var top := g.spawn_unit(1, 0, "knight", L.cell_center(Vector2i(4, 0)))
	var bottom := g.spawn_unit(1, 4, "knight", L.cell_center(Vector2i(4, 4)))
	var aside := g.spawn_unit(1, 2, "knight", L.cell_center(Vector2i(6, 2)))
	preload("res://expansion_more.gd").cast(g, {"kind": "mana_drain", "team": 0, "pos": L.cell_center(Vector2i(4, 2))})
	var inside := g.spawn_unit(1, 2, "militia", L.cell_center(Vector2i(3, 2)))
	var far := g.spawn_unit(1, 0, "militia", L.cell_center(Vector2i(3, 0)))
	g.cast_spell({"kind": "rain", "team": 0, "pos": inside.pos})
	check(top.hp < top.max_hp and bottom.hp < bottom.max_hp and aside.hp == aside.max_hp and inside.hp < inside.max_hp and far.hp == far.max_hp, "1x5 and 2x2 spells hit exactly their tiles")

# ---------------- lords (6) ----------------
func lord_checks() -> void:
	check(B.lord_is_ranged("mage") and B.lord_is_ranged("rune") and B.lord_is_ranged("underworld") and not B.lord_is_ranged("lion") and not B.lord_is_ranged("iron") and not B.lord_is_ranged("beast") and not B.lord_is_ranged("vampire"), "casters are ranged lords, frontline lords are melee")
	var pl := Battle.new(51, B.DEFAULT_DECK, B.DEFAULT_DECK, "mage", "lion")
	pl.ai_enabled = [false, false]
	pl.lord_active = [true, false]
	var mage: Dictionary = pl.lords[0]
	mage.cd = 0.0
	ready_unit(pl, 1, 2, "knight", mage.pos + Vector2(240.0, 0.0))
	pl.build_lookups()
	var aimed: bool = not pl.lord_target(mage).is_empty()
	var shots: int = pl.projectiles.size()
	preload("res://lord.gd").step(pl, mage, 0.05)
	check(aimed and pl.projectiles.size() == shots + 1 and is_equal_approx(mage.cd, B.LORD_RANGED_INTERVAL), "a ranged lord targets a foe at range and fires a projectile")
	var ml := Battle.new(50, B.DEFAULT_DECK, B.DEFAULT_DECK, "lion", "shield_sergeant")
	ml.ai_enabled = [false, false]
	ml.lord_active = [false, true]
	ready_unit(ml, 0, 2, "knight", ml.lords[1].pos - Vector2(B.LORD_RANGE + 80.0, 0.0))
	var side_lane: int = (ml.lord_lane(ml.lords[1]) + 1) % L.GRID_ROWS
	ready_unit(ml, 0, side_lane, "knight", Vector2(ml.lords[1].pos.x - 40.0, L.cell_center(Vector2i(0, side_lane)).y))
	ml.build_lookups()
	check(ml.lord_target(ml.lords[1]).is_empty(), "a melee lord does not reach beyond B.LORD_RANGE nor into another lane")
	var ms := Battle.new(51, B.DEFAULT_DECK, B.DEFAULT_DECK, "lion", "shield_sergeant")
	ms.ai_enabled = [false, false]
	ms.skill_cd[1] = 0.0
	ms.skill_charge[1] = ms.skill_need(1)
	ready_unit(ms, 0, 1, "militia", L.cell_center(Vector2i(6, 1)))
	var planned: bool = EnemyAI.skill_plan(ms.skill_state(1)).cast
	var before: int = ms.units.size()
	check(planned and ms.cast_skill(1) and ms.units.size() > before and is_equal_approx(ms.skill_cd[1], B.MINION_SKILL_COOLDOWN), "AI plans a minion lord skill, which summons troops and starts its cooldown")
	var pack := Battle.new(21, [], [], "beast", "beast")
	pack.record_events = false
	pack.ink[0] = B.MAX_INK
	pack.units.clear()
	pack.skill_cd[0] = 0.0
	pack.gain_ink(0, 7.0) # a full purse: the overflow charges the skill instead
	var overflow_charged: bool = is_equal_approx(pack.skill_charge[0], 7.0) and not pack.cast_skill(0)
	pack.skill_charge[0] = pack.skill_need(0) - 0.5
	pack.ink[0] = 0.0
	pack.add_skill_charge(0, 3.0) # stands in for gold spent on a card; capped at the need
	var cast_free: bool = pack.cast_skill(0) and pack.ink[0] == 0.0 and pack.skill_charge[0] == 0.0
	pack.ink[0] = B.MAX_INK
	pack.gain_ink(0, 5.0)
	cast_free = cast_free and pack.skill_charge[0] == 0.0 # cooling down: overflow does not charge
	var beasts: Array = pack.units.filter(func(u: Dictionary) -> bool: return u.team == 0 and u.kind == "pouch_beast")
	var iron := Battle.new(8, [], [], "iron", "lion")
	iron.record_events = false
	iron.skill_charge[0] = iron.skill_need(0)
	iron.skill_cd[0] = 0.0
	var towers_up: bool = iron.cast_skill(0) and iron.buildings.filter(func(b: Dictionary) -> bool: return b.team == 0 and b.kind == "tower" and iron.territory_owner(b.cell) == 0).size() == int(B.LORDS.iron.tower_count)
	check(towers_up and overflow_charged and cast_free and is_equal_approx(B.skill_charge_need("beast"), B.skill_cost("beast") * 2.0 + 10.0) and beasts.size() == pack.active_lanes.size() * int(B.LORDS.beast.pack_count), "overflow and spent gold charge the lord skill (not while it cools down), which casts free; 獸群號角 summons pouch beasts in every lane and 箭樓築城 builds two towers on our land")
	var freeze := Battle.new(17, [], [], "mage", "lion")
	freeze.time_stop_team = 0
	freeze.time_stop_left = 3.5
	freeze.finish(0)
	check(freeze.ended and not freeze.time_stopped() and freeze.time_stop_team == -1, "winning during 時空凝滯 lifts the freeze so the result screen can open")

# ---------------- economy, day cycle, roguelike (8) ----------------
func economy_and_roguelike_checks() -> void:
	var dc := Battle.new(63, [], [], "lion", "beast")
	dc.ai_enabled = [false, false]
	dc.decks[0] = ["mill", "granary", "tower", "militia", "ox", "rain", "fire", "hunter"]
	var clock_ok := is_equal_approx(dc.multiplier(), 1.5)
	for phase_t: float in [0.0, B.RAMP_1, B.RAMP_2, B.NIGHT_START]:
		dc.elapsed = phase_t
		var mult := dc.multiplier()
		dc.hand_cd[0] = [10.0, 10.0, 10.0, 10.0]
		dc.farm_cd[0] = 10.0
		dc.tick_clocks(1.0)
		clock_ok = clock_ok and is_equal_approx(dc.hand_cd[0][0], 9.0) and is_equal_approx(dc.hand_cd[0][2], 10.0 - mult) and is_equal_approx(dc.farm_cd[0], 9.0)
	check(clock_ok, "day cycle speeds up card cooldowns (x1.5 -> x3) but not economy buildings")
	var gr := Battle.new(54, B.DEFAULT_DECK, B.DEFAULT_DECK, "lion", "iron")
	gr.ai_enabled = [false, false]
	gr.buildings.clear()
	var farm := gr.add_building(0, Vector2i(0, 1), "farm")
	var granary := gr.add_building(0, Vector2i(1, 2), "granary")
	gr.ink[0] = 0.0
	for i: int in range(9): gr.farm_drop(farm)
	var stored := is_equal_approx(granary.get("stored_gold", 0.0), 9.0)
	gr.farm_drop(farm)
	check(stored and is_equal_approx(granary.get("stored_gold", 0.0), 0.0) and is_equal_approx(gr.ink[0], B.FARM_DROP * 10.0 + 10.0), "granary stores 1 gold per farm drop and pays out 10 at a time")

	var Upgrades = preload("res://card_upgrades.gd")
	var Rogue = preload("res://roguelike.gd")
	var RCatalog = preload("res://roguelike_catalog.gd")
	var rg := Rogue.new()
	rg.save_path = "user://quick_test_rogue.json"
	rg.begin("lion", 4242, 1)
	check(rg.run.board.size() == 4 and rg.run.deck.size() == 8 and DS.valid(rg.run.deck, "lion") and rg.run.deck.all(func(k: String) -> bool: return B.card_faction(k) == B.lord_faction("lion")), "a roguelike run starts with a 4-slot board and a legal 8-card faction deck")
	rg.select_node(3)
	rg.trigger_node()
	var at_camp: bool = rg.run.phase == "camp"
	rg.camp_card_index = 0
	rg.camp_action(1)
	check(at_camp and rg.run.phase == "map" and Upgrades.level(rg.run.upgrades.get(rg.run.deck[0], {})) == 1, "the camp forge upgrades the chosen card by one level")
	rg.set_elite(true)
	rg.make_battle()
	rg.settle(true)
	check(rg.run.floor == 1 and rg.run.relics.size() >= 1 and rg.run.phase == "reward", "winning an elite battle drops a relic and advances the floor")
	var rs := Rogue.new()
	rs.save_path = "user://quick_test_rogue_scale.json"
	rs.begin("adventure", 777, 3)
	rs.run.floor = RCatalog.FLOORS - 1
	var last := rs.make_battle()
	check(is_equal_approx(float(last.lord_mod(1, "gold_gain_mult", 1.0)), 2.0) and is_equal_approx(float(last.lord_mod(1, "cd_speed_mult", 1.0)), 2.0), "the final floor doubles enemy gold and cooldown speed")
	var broken: Array = []
	for boss_k: String in B.LORDS:
		var sim := Battle.new(900 + hash(boss_k) % 100, B.DEFAULT_DECK, RCatalog.BOSSES[boss_k], "mage", boss_k)
		sim.apply_domestic(0, B.home_card("mage"), RCatalog.side_mods("mage", ["river_sluice", "trench_engineer", "spirit_graveyard", "sky_volley_seal", "aegis_obelisk", "fertile_floodplain", "warlord_seal", "echo_bell", "soul_lantern", "last_ward", "phoenix_ash"]))
		sim.apply_field_mutator(RCatalog.BOSS_MUTATORS[boss_k])
		sim.apply_field_mutator(RCatalog.BOSS_VARIANTS.get(boss_k + "_ii", {})) # both faces of the boss at once
		sim.ai_enabled = [true, true]
		sim.difficulty = 2
		for f: int in range(960):
			sim.step(1.0 / 30.0)
			if sim.ended: break
		if not (is_finite(sim.ink[0]) and is_finite(sim.ink[1])) or sim.buildings.any(func(b: Dictionary) -> bool: return b.hp > 0 and sim.is_water_cell(b.cell)):
			broken.append(boss_k)
	check(broken.is_empty(), "every boss with all field relics runs 32 s of AI play cleanly (broken: %s)" % str(broken))
	for fp: String in [rg.save_path, rg.save_path + ".bak", rs.save_path, rs.save_path + ".bak"]:
		if FileAccess.file_exists(fp): DirAccess.remove_absolute(ProjectSettings.globalize_path(fp))

# ---------------- new cards: 金幣怪物 and 封印祭壇 (9) ----------------
func new_card_checks() -> void:
	var GM = preload("res://gold_monster.gd")
	var rows: Array = B.GOLD_MONSTER_STAGES
	var table_ok := int(rows[0][0]) == 1 and int(rows[-1][0]) <= int(B.MAX_INK)
	for i: int in range(rows.size()):
		var r: Array = rows[i]
		table_ok = table_ok and B.TIERS.hp.has(float(r[2])) and B.TIERS.damage.has(float(r[3])) and B.TIERS.interval.has(float(r[4])) and B.TIERS.speed.has(float(r[5])) and int(r[1]) >= 1 and int(r[1]) <= 5
		if i > 0:
			var p: Array = rows[i - 1]
			table_ok = table_ok and int(r[0]) > int(p[0]) and int(r[1]) >= int(p[1])
			if int(r[1]) == int(p[1]): table_ok = table_ok and r[2] >= p[2] and r[3] >= p[3] and r[4] <= p[4] and r[5] >= p[5]
	check(table_ok, "gold_monster stages: tier values, 1..MAX_INK, 1-5 bodies, no stat drops unless a body is added")
	var gm := quiet(15)
	var spot := L.cell_center(Vector2i(1, 2))
	var plays_ok := true
	for c: Array in [[37.6, 3, 900.0, 130.0, 1.4, 65.0], [50.0, 5, 900.0, 95.0, 1.4, 90.0], [1.2, 1, 130.0, 36.0, 1.9, 36.0]]:
		gm.units.clear()
		gm.decks[0][0] = "gold_monster"
		gm.hand_cd[0][0] = 0.0
		gm.ink[0] = c[0]
		var played: bool = gm.play(0, 0, spot)
		var bodies: Array = gm.units.filter(func(u: Dictionary) -> bool: return u.kind == "gold_monster")
		plays_ok = plays_ok and played and is_equal_approx(gm.ink[0], c[0] - floorf(c[0])) and bodies.size() == int(c[1]) and bodies.all(func(u: Dictionary) -> bool: return u.max_hp == c[2] and u.damage == c[3] and u.interval == c[4] and u.speed == c[5])
	gm.decks[0][0] = "gold_monster"
	gm.hand_cd[0][0] = 0.0
	gm.ink[0] = 0.5
	var gm2 := quiet(20, "lion", "lion")
	gm2.decks[0][0] = "gold_monster"
	gm2.hand_cd[0][0] = 0.0
	gm2.ink[0] = 24.0
	gm2.play(0, 0, L.cell_center(Vector2i(1, 2)))
	var gmb: Array = gm2.units.filter(func(u: Dictionary) -> bool: return u.kind == "gold_monster")
	var gm_no_shield_ok: bool = gmb.size() == 2 and is_equal_approx(float(gmb[0].get("shield", 0.0)), 0.0)
	var before_refund: float = gm2.ink[0]
	for gb: Dictionary in gmb: gm2.damage(gb, 99999.0, 1, "fire")
	gm2.resolve_deaths()
	var gm_refund_ok: bool = is_equal_approx(gm2.ink[0] - before_refund, 9.0)
	gm2.decks[0][0] = "gold_monster"
	gm2.hand_cd[0][0] = 0.0
	gm2.ink[0] = 24.0
	gm2.play(0, 0, L.cell_center(Vector2i(1, 2)))
	var gmb2: Array = gm2.units.filter(func(u: Dictionary) -> bool: return u.kind == "gold_monster" and u.hp > 0)
	var before_sac: float = gm2.ink[0]
	gm2.damage(gmb2[0], 99999.0, 0, "sacrifice", {}, true)
	gm2.damage(gmb2[1], 99999.0, 1, "fire")
	gm2.resolve_deaths()
	var gm_sac_ok: bool = is_equal_approx(gm2.ink[0] - before_sac, 4.0)
	gm2.decks[0][0] = "gold_monster"
	gm2.hand_cd[0][0] = 0.0
	gm2.ink[0] = 1.0
	gm2.play(0, 0, L.cell_center(Vector2i(1, 2)))
	var gmb1: Array = gm2.units.filter(func(u: Dictionary) -> bool: return u.kind == "gold_monster" and u.hp > 0)
	var before_one: float = gm2.ink[0]
	for gb1: Dictionary in gmb1: gm2.damage(gb1, 9999.0, 1, "fire")
	gm2.resolve_deaths()
	check(plays_ok and gm.play_check(0, 0, spot) == Battle.Refusal.GOLD and gm_no_shield_ok and gm_refund_ok and gm_sac_ok and is_equal_approx(gm2.ink[0] - before_one, 0.0) and GM.ai_wait("gold_monster", 20.0, false) and not GM.ai_wait("gold_monster", 30.0, false) and not GM.ai_wait("gold_monster", 9.0, true) and GM.cost_text("gold_monster", B.CARDS.gold_monster) == "全", "gold_monster spends purse at 100% stages (no shield), refunds 40% non-sacrificed deaths (>=3g), AI waits and shows 全")

	var sa := quiet(16, "underworld", "lion", false)
	sa.decks[0][0] = "seal_altar"
	sa.hand_cd[0][0] = 0.0
	sa.ink[0] = 50.0
	var built: bool = sa.play(0, 0, L.cell_center(Vector2i(1, 2)))
	var altar: Dictionary = sa.building_at(Vector2i(1, 2))
	sa.decks[0][0] = "seal_altar"
	sa.hand_cd[0][0] = 0.0
	check(built and sa.play_check(0, 0, L.cell_center(Vector2i(1, 1))) == Battle.Refusal.UNIQUE and sa.play_check(0, 0, L.cell_center(Vector2i(1, 2))) == Battle.Refusal.OK, "one seal_altar per side; topping up the same one is allowed")
	sa.hand_cd[0][0] = 10.0
	for i: int in range(60): sa.step(1.0 / 60.0)
	var held := is_equal_approx(sa.hand_cd[0][0], 10.0)
	var kill := func(lane: int) -> void:
		var v: Dictionary = ready_unit(sa, 1, lane, "militia", L.cell_center(Vector2i(6, lane)))
		sa.damage(v, 9999.0, 0, "fire")
		sa.resolve_deaths()
	kill.call(2)
	kill.call(0)
	var souls_ok := is_equal_approx(altar.get("souls", 0.0), 2.0)
	var scared := ready_unit(sa, 1, 2, "militia", altar.pos + Vector2(60, 0))
	altar.souls = 19.0
	kill.call(0)
	check(souls_ok and scared.get("fear_left", 0.0) > 0.0 and altar.hp > 0, "every death gives the altar 1 soul and a breaking seal scares nearby foes")
	altar.souls = 59.0
	kill.call(0)
	var ours: Array = sa.units.filter(func(u: Dictionary) -> bool: return u.team == 0 and u.hp > 0)
	var zones0: int = sa.zones.filter(func(z: Dictionary) -> bool: return z.team == 0).size()
	var released: bool = altar.hp <= 0 and ours.filter(func(u: Dictionary) -> bool: return u.kind == "plague_bishop").size() == 1 and ours.filter(func(u: Dictionary) -> bool: return u.kind == "funeral_monk").size() == 4
	for i: int in range(150): sa.step(1.0 / 60.0)
	check(released and sa.zones.filter(func(z: Dictionary) -> bool: return z.team == 0).size() > zones0, "the last seal releases the plague bishop and four monks, and he leaves rotting ground")
	check(held and sa.hand_cd[0][0] < 10.0, "the altar card holds its cooldown while our altar stands and resumes once it shatters")
	var opening_ok := true
	for s: int in range(40):
		var deck_test := Battle.new(900 + s, ["seal_altar", "skeleton", "ghoul", "necromancer", "plague", "bellbearer", "raven", "reaper"], [], "underworld", "lion")
		opening_ok = opening_ok and not ("seal_altar" in deck_test.decks[0].slice(0, 4)) and deck_test.decks[0].size() == 8
	check(opening_ok, "seal_altar never starts in the opening hand (40 shuffles)")

	# 咒潮法師: our spells (played from hand) stack the tide; 3 stacks reach S damage, 5 cap attack speed.
	var CoreCards = preload("res://core_cards.gd")
	var tide := quiet(18, "mage", "lion")
	var magus := ready_unit(tide, 0, 2, "spell_tide_magus", L.cell_center(Vector2i(1, 2)))
	tide.decks[0][0] = "rain"
	tide.hand_cd[0][0] = 0.0
	tide.ink[0] = 50.0
	tide.play(0, 0, L.cell_center(Vector2i(5, 2)))
	var first_stack: bool = int(magus.get("tide", 0)) == 1 and magus.damage == 95.0
	CoreCards.on_card_played(tide, 1, "rain")
	for i: int in range(6): CoreCards.on_card_played(tide, 0, "rain")
	CoreCards.on_card_played(tide, 0, "militia")
	check(first_stack and int(magus.tide) == 5 and magus.damage == 180.0 and magus.interval == 0.85, "咒潮法師 grows with our spells only: S damage after 3, faster attacks at 4-5, capped at 5")

	# 荊棘母獸: allies near her prick melee attackers (existing thorns two tiers up, others get the aura value).
	var Monster = preload("res://monster_cards.gd")
	var den := quiet(19, "beast", "lion")
	var mother := ready_unit(den, 0, 2, "thorn_mother", L.cell_center(Vector2i(3, 2)))
	var hound := ready_unit(den, 0, 2, "thorn_hound", mother.pos + Vector2(40, 0))
	var plain := ready_unit(den, 0, 2, "militia", mother.pos + Vector2(-40, 0))
	var alone := ready_unit(den, 0, 4, "militia", L.cell_center(Vector2i(3, 4)))
	var pricks: Array = []
	for t: Dictionary in [hound, plain, alone]:
		var attacker := ready_unit(den, 1, t.lane, "knight", t.pos + Vector2(30, 0))
		Monster.on_hit(den, t, attacker)
		pricks.append(attacker.max_hp - attacker.hp)
	check(pricks == [70.0, 36.0, 0.0], "荊棘母獸 aura: thorns two tiers up (36 -> 70), 36 for allies without, none outside (got %s)" % str(pricks))

	var rework_fails: Array = []
	var Exp := preload("res://expansion_cards.gd")
	var ExpMore := preload("res://expansion_more.gd")
	var Faction := preload("res://faction_cards.gd")

	var wb := quiet(21, "rune", "beast")
	wb.decks[0][0] = "warp_beacon"
	wb.hand_cd[0][0] = 0.0
	wb.ink[0] = 50.0
	var wb_spot := L.cell_center(Vector2i(1, 2))
	var wb_placed: bool = wb.play(0, 0, wb_spot)
	var wb_flyer := ready_unit(wb, 1, 2, "hooknose_flyer", wb_spot + Vector2(100.0, 0.0))
	var wb_x0: float = wb_flyer.pos.x
	wb.step(1.0 / 60.0)
	if not wb_placed or wb_flyer.pos.x <= wb_x0 + 100.0 or float(wb_flyer.get("stun_left", 0.0)) <= 0.5 or not is_equal_approx(wb_flyer.max_hp - wb_flyer.hp, 55.0):
		rework_fails.append("warp_beacon")

	var sb := quiet(22, "vampire", "lion")
	sb.decks[0][0] = "sleepless_belfry"
	sb.hand_cd[0][0] = 0.0
	sb.ink[0] = 50.0
	var sb_spot := L.cell_center(Vector2i(1, 2))
	var sb_placed: bool = sb.play(0, 0, sb_spot)
	var belfry := sb.building_at(Vector2i(1, 2))
	var sb_healthy := ready_unit(sb, 0, 2, "militia", sb_spot + Vector2(40.0, 0.0))
	var sb_dirty := ready_unit(sb, 0, 2, "militia", sb_spot + Vector2(20.0, 0.0))
	sb_dirty.hp = 50.0
	sb_dirty.slow_left = 4.0
	sb_dirty.poison_stacks = 5
	sb_dirty.poison_left = 2.0
	sb_dirty.poison_team = 1
	sb_dirty.hex_stacks = 4
	sb_dirty.hex_left = 2.0
	sb_dirty.hex_team = 1
	var sb_foe := ready_unit(sb, 1, 2, "militia", sb_spot + Vector2(120.0, 0.0))
	Exp.support(sb, belfry, B.CARDS.sleepless_belfry)
	var belfry_pulse_ok: bool = sb_placed and float(sb_healthy.get("expansion_haste_until", 0.0)) > sb.elapsed and is_equal_approx(sb_dirty.slow_left, 0.0) and is_equal_approx(sb_dirty.hp, 100.0) and int(sb_dirty.get("poison_stacks", 0)) == 0 and int(sb_dirty.get("hex_stacks", 0)) == 0 and float(sb_foe.get("slow_left", 0.0)) >= 1.5
	sb.damage(belfry, 9999.0, 1, "fire")
	var belfry_skels: int = sb.units.filter(func(u: Dictionary) -> bool: return u.team == 0 and u.kind == "skeleton" and u.hp > 0 and u.get("card", "") == "sleepless_belfry").size()
	if not belfry_pulse_ok or belfry_skels != 3:
		rework_fails.append("sleepless_belfry")

	var dh := quiet(23, "vampire", "lion")
	var dh_ally := ready_unit(dh, 0, 2, "militia", L.cell_center(Vector2i(2, 2)))
	var dh_foe := ready_unit(dh, 1, 2, "militia", L.cell_center(Vector2i(3, 2)) + Vector2(40.0, 0.0))
	Faction.cast(dh, {"kind": "dread_howl", "team": 0, "pos": L.cell_center(Vector2i(3, 2))})
	var dh_hit_ok: bool = is_equal_approx(dh_foe.max_hp - dh_foe.hp, 55.0) and float(dh_foe.get("fear_left", 0.0)) >= 5.0 and float(dh_foe.get("slow_left", 0.0)) >= 5.0 and float(dh_foe.get("terror_until", 0.0)) > dh.elapsed and float(dh_foe.get("cursed_until", 0.0)) > dh.elapsed and float(dh_ally.get("expansion_haste_until", 0.0)) >= 4.0
	dh.damage(dh_foe, 9999.0, 0, "fire")
	dh.resolve_deaths()
	var dh_curse_ok: bool = dh.units.any(func(u: Dictionary) -> bool: return u.team == 0 and u.kind == "skeleton" and u.hp > 0)
	if not (dh_hit_ok and dh_curse_ok):
		rework_fails.append("dread_howl")

	var os_m := quiet(24, "underworld", "lion")
	os_m.decks[0][0] = "ossuary"
	os_m.hand_cd[0][0] = 0.0
	os_m.ink[0] = 50.0
	os_m.play(0, 0, L.cell_center(Vector2i(1, 2)))
	var os_build_cnt: int = os_m.units.filter(func(u: Dictionary) -> bool: return u.team == 0 and u.kind == "skeleton" and u.hp > 0).size()
	var os_b := os_m.building_at(Vector2i(1, 2))
	os_m.damage(os_b, 9999.0, 1, "fire")
	var os_total_cnt: int = os_m.units.filter(func(u: Dictionary) -> bool: return u.team == 0 and u.kind == "skeleton" and u.hp > 0).size()
	if os_build_cnt != 2 or os_total_cnt != 6:
		rework_fails.append("ossuary")

	var sa2 := quiet(25, "vampire", "lion")
	var sa_ally := ready_unit(sa2, 0, 2, "knight", L.cell_center(Vector2i(3, 2)))
	var sa_foe := ready_unit(sa2, 1, 2, "knight", L.cell_center(Vector2i(3, 2)) + Vector2(30.0, 0.0))
	sa2.ink[0] = 0.0
	sa2.skill_charge[0] = 0.0
	Faction.cast(sa2, {"kind": "sacrifice", "team": 0, "pos": L.cell_center(Vector2i(3, 2))})
	if not is_equal_approx(sa_ally.max_hp - sa_ally.hp, 500.0) or not is_equal_approx(sa_foe.max_hp - sa_foe.hp, 250.0) or float(sa_foe.get("slow_left", 0.0)) < 2.0 or sa2.ink[0] <= 0.0 or sa2.skill_charge[0] <= 0.0:
		rework_fails.append("sacrifice")

	var fc := quiet(26, "vampire", "lion")
	fc.decks[0][0] = "funeral_cottage"
	fc.hand_cd[0][0] = 0.0
	fc.ink[0] = 50.0
	fc.play(0, 0, L.cell_center(Vector2i(1, 2)))
	fc.ink[0] = 10.0
	fc.skill_charge[0] = 0.0
	var fc_foe1 := ready_unit(fc, 1, 2, "militia", L.cell_center(Vector2i(3, 2)))
	fc.damage(fc_foe1, 9999.0, 0, "fire")
	fc.resolve_deaths()
	var fc_first_ok: bool = is_equal_approx(fc.ink[0], 11.0) and is_equal_approx(fc.skill_charge[0], 2.0)
	var fc_foe2 := ready_unit(fc, 1, 2, "militia", L.cell_center(Vector2i(3, 2)))
	fc.damage(fc_foe2, 9999.0, 0, "fire")
	fc.resolve_deaths()
	if not fc_first_ok or not is_equal_approx(fc.ink[0], 11.0):
		rework_fails.append("funeral_cottage")

	var wg := quiet(27, "beast", "lion")
	var wg_ally := ready_unit(wg, 0, 2, "militia", L.cell_center(Vector2i(3, 2)) - Vector2(20.0, 0.0))
	wg_ally.slow_left = 3.0
	var wg_ground := ready_unit(wg, 1, 2, "pouch_beast", L.cell_center(Vector2i(3, 2)) + Vector2(20.0, 0.0))
	var wg_fly := ready_unit(wg, 1, 2, "hooknose_flyer", L.cell_center(Vector2i(3, 2)) + Vector2(20.0, 0.0))
	var wg_gx0: float = wg_ground.pos.x
	var wg_fx0: float = wg_fly.pos.x
	ExpMore.cast(wg, {"kind": "wing_gust", "team": 0, "pos": L.cell_center(Vector2i(3, 2))})
	if not is_equal_approx(wg_ally.slow_left, 0.0) or float(wg_ally.get("expansion_haste_until", 0.0)) <= wg.elapsed or not is_equal_approx(wg_ground.pos.x - wg_gx0, 236.0) or not is_equal_approx(float(wg_ground.get("stun_left", 0.0)), 1.0) or not is_equal_approx(wg_ground.max_hp - wg_ground.hp, 55.0) or not is_equal_approx(wg_fly.pos.x - wg_fx0, 236.0) or not is_equal_approx(float(wg_fly.get("stun_left", 0.0)), 2.0) or not is_equal_approx(wg_fly.max_hp - wg_fly.hp, 110.0):
		rework_fails.append("wing_gust")

	check(rework_fails.is_empty(), "low-cost card mechanic reworks: " + str(rework_fails))

# ---------------- presentation (3) ----------------
func presentation_checks() -> void:
	var champ := Battle.new(7, ["hunter", "ram", "militia", "ox", "farmer", "guard", "fire", "axe_thrower"], ["long_dragon", "fishbeak", "bearded_imp", "ox", "farmer", "guard", "fire", "militia"], "lion", "beast")
	champ.lords[0].hp = 0.0
	champ.lords[0].respawn = 99.0
	champ.lords[1].hp = 0.0
	champ.lords[1].respawn = 99.0
	var Ceremony = preload("res://battle_ceremony.gd")
	var ram := champ.spawn_unit(0, 2, "ram", Vector2(L.gate_stop(1) - 30.0, L.cell_center(Vector2i(0, 2)).y))
	champ.hit_gate(1, 2, 5000.0, "ram", ram)
	var invader := champ.spawn_unit(0, 2, "militia", Vector2(L.gate_icon_x(1), L.cell_center(Vector2i(0, 2)).y))
	champ.build_lookups()
	champ.march(invader, B.CARDS.militia, 0.05)
	check(champ.ended and champ.winner == 0 and Ceremony.champion(champ, 0) == "militia", "walking through a broken wall wins, and the invader is the match champion")
	var cd = preload("res://cinematic_director.gd").new()
	var host := MockCinematicHost.new()
	cd.field_active = true
	for burst: int in range(4):
		cd.on_event(host, {"kind": "hero_slash", "pos": L.cell_center(Vector2i(0, 3)), "team": 0})
		cd.on_event(host, {"kind": "breach", "pos": L.cell_center(Vector2i(8, 2)), "team": 1})
	var peak := 0.0
	for f: int in range(25):
		host.clock += 0.15
		cd.step(host, 0.15)
		peak = maxf(peak, cd.impulse.length())
	var CardSort = preload("res://card_sort.gd")
	var all_cards: Array = B.CARDS.keys()
	var before_cards := all_cards.duplicate()
	var sort_ok: bool = CardSort.sort_lords(B.LORDS.keys()) == B.lord_menu_order() and CardSort.sort_cards(["gold_monster", "militia", "fire", "farm"], "cost_asc")[-1] == "gold_monster"
	for mode: Array in CardSort.MODES:
		var sorted: Array = CardSort.sort_cards(all_cards, mode[0], "magic")
		sort_ok = sort_ok and sorted.size() == all_cards.size() and all_cards == before_cards
	var SB = preload("res://sound_bank.gd")
	var missing_sfx: Array = []
	for sfx_name: String in SB.CUES.values():
		if not ResourceLoader.exists("res://assets/audio/" + sfx_name + ".ogg") and not sfx_name in missing_sfx:
			missing_sfx.append(sfx_name)
	var polish = preload("res://ui_polish.gd").new()
	check(peak <= cd.MAX_IMPULSE + 0.01 and cd.impulse.length() < 0.5 and sort_ok and missing_sfx.is_empty() and is_equal_approx(polish.screen_enter_t, 1.0), "camera shake stays bounded and settles under stacked events and frame spikes; CardSort, SoundBank (%s) and UiPolish are valid" % str(missing_sfx))
	preload("res://tools/test_art_palette.gd").run(self)
