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

# Just enough of game.gd for tutorial_coach.gd: the battle, the selected card and the intro banner.
class MockCoachHost extends RefCounted:
	var model = null
	var selected := -1
	var intro_left := 0.0
	var adventure = null

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

# Adventure as tutorial (2026-11-21): lesson 1-1 played by following its prompts must keep the enemy wall
# warded until the "break the wall" step, reach the last step and win; difficulties change the enemy
# (簡單 income x0.75, 困難 AI 2, 極難 passives); a stage's new card is put into the player's deck.
# Returns "" when all is well, otherwise what went wrong.
func tutorial_lesson_ok() -> String:
	var adv = preload("res://adventure.gd").new()
	adv.progress_path = "user://quick_test_adventure_unused.json"
	var host := MockCoachHost.new()
	host.adventure = adv
	adv.index = 0
	var d: Dictionary = adv.STAGES[0]
	host.model = adv.make_battle(0, d.deck.duplicate(), "adventure")
	adv.coach.begin(host, d)
	var m: Battle = host.model
	var full: float = m.gates[1][2]
	var ward_broke := false
	var t := 0
	while not m.ended and t < 60 * 90:
		m.step(1.0 / 60.0)
		m.events.clear()
		adv.coach.update(host)
		if adv.coach.warded() and m.gates[1][2] < full: ward_broke = true
		if t % 30 == 0:
			if adv.coach.step == 0: host.selected = 0
			else:
				host.selected = -1
				m.play(0, 0, L.cell_center(Vector2i(1, 2)))
		t += 1
	if ward_broke: return "ward let the wall take damage"
	if not (m.ended and m.winner == 0): return "lesson 1-1 not won (step %d)" % adv.coach.step
	if adv.coach.step != adv.coach.steps.size() - 1: return "lesson 1-1 ended on step %d" % adv.coach.step
	adv.difficulty = 0
	var easy: Battle = adv.make_battle(10, B.DEFAULT_DECK, "lion")
	if not is_equal_approx(float(easy.lord_mod(1, "gold_gain_mult", 1.0)), 0.75): return "簡單 does not cut enemy income"
	adv.difficulty = 2
	if adv.make_battle(10, B.DEFAULT_DECK, "lion").difficulty != 2: return "困難 does not force the hard AI"
	adv.difficulty = 3
	if adv.difficulty_passives(10).size() != 1 or adv.difficulty_passives(19).size() != 2: return "極難 passives: one per stage, two on exams"
	adv.difficulty = 1
	if not adv.difficulty_passives(10).is_empty(): return "普通 must add no passives"
	adv.lord = "adventure"
	var fed: Array = adv.with_featured(["militia","hunter","farmer","barricade","scarecrow","tower","rain","mob"], 10)
	if not "macebreaker" in fed or not DS.valid(fed, "adventure") or not "farmer" in fed: return "stage 2-1 did not put 釘錘破甲兵 into the deck: %s" % str(fed)
	var Conveyor = preload("res://conveyor.gd")
	if adv.STAGES[9].id != "w1_10" or adv.STAGES[10].id != "w2_1": return "stage indices shifted for 1-10 / 2-1"
	if bool(adv.STAGES[9].get("deck_lesson", false)) or not bool(adv.STAGES[10].get("deck_lesson", false)): return "deck_lesson must move from w1_10 to w2_1"
	var conv: Battle = adv.make_battle(9, adv.STAGES[9].deck.duplicate(), "adventure")
	if not conv.is_conveyor(0) or conv.is_conveyor(1): return "1-10 conveyor flag wrong"
	if not is_zero_approx(conv.production_rate(0)): return "1-10 conveyor should have 0 production_rate"
	if Conveyor.count(conv) != 3 or conv.ink[0] > 0.001: return "1-10 conveyor start state wrong"
	for _f: int in range(60 * 25):
		conv.step(1.0 / 60.0)
		conv.events.clear()
		if conv.ended: break
	if Conveyor.count(conv) != 8 or conv.ink[0] > 0.001: return "1-10 conveyor failed to cap at 8 or leaked gold"
	var play_slot := -1
	var play_pos := L.cell_center(Vector2i(0, 2))
	for s: int in range(Conveyor.count(conv)):
		if conv.can_play(0, s, play_pos):
			play_slot = s
			break
	if play_slot < 0: return "1-10 conveyor had no playable card on belt"
	var before_cnt := Conveyor.count(conv)
	var before_chg: float = conv.skill_charge[0]
	if not conv.play(0, play_slot, play_pos): return "1-10 conveyor free play failed"
	if Conveyor.count(conv) != before_cnt - 1: return "1-10 conveyor play did not consume card"
	if conv.skill_charge[0] <= before_chg: return "1-10 conveyor play did not charge lord skill"
	for _f2: int in range(20):
		conv.step(1.0 / 60.0)
		conv.events.clear()
	for si: int in range(1, Conveyor.count(conv)):
		if Conveyor.card_rect(conv, si).position.x < Conveyor.card_rect(conv, si - 1).position.x + Conveyor.CARD_STEP - 0.1:
			return "1-10 conveyor cards overlapped after slide"
	return ""

# ---------------- data and determinism (9) ----------------
func data_checks() -> void:
	var problems := B.validate()
	check(problems.is_empty(), "balance.gd validate: " + str(problems))
	var rogue_errors := preload("res://roguelike_catalog.gd").validate()
	rogue_errors.append_array(preload("res://rogue_terrain.gd").validate()) # every foe has a battlefield
	check(rogue_errors.is_empty(), "roguelike data: " + str(rogue_errors))
	var catalog = preload("res://campaign_catalog.gd")
	var campaign_errors: Array[String] = catalog.validate()
	var cb := Battle.new(91, ["barricade", "militia", "farmer", "hunter", "rain", "healer", "tower", "ox"], B.DEFAULT_DECK, "adventure", "card_enemy_barricade")
	cb.ai_enabled = [false, false]
	cb.apply_field_mutator({"wind_lanes": [1], "blocked_cells": [[0, 2]]}, 1)
	var u_wind := ready_unit(cb, 0, 1, "militia", L.cell_center(Vector2i(1, 1)))
	cb.decks[0][0] = "barricade"
	cb.ink[0] = 20.0
	var block_ok := cb.play_check(0, 0, L.cell_center(Vector2i(0, 2))) == Battle.Refusal.BLOCKED
	var u_against := ready_unit(cb, 1, 1, "militia", L.cell_center(Vector2i(7, 1)))
	var wind_ok := is_equal_approx(cb.movement_speed(u_wind), 65.0) and is_equal_approx(cb.movement_speed(u_against), 50.0) # wind blows one way only
	cb.apply_campaign_mods(0, {"start_ink": 5.0, "farm_mult": 1.25, "gate_armor": 0.2})
	cb.apply_campaign_mods(1, {"start_ink": 6.0})
	var mods_ok: bool = is_equal_approx(cb.ink[0], 25.0) and is_equal_approx(float(cb.lord_mod(0, "farm_mult", 1.0)), 1.25) and is_equal_approx(float(cb.lord_mod(0, "gate_armor", 0.0)), 0.2) and not (cb.lord_mod(1, "start_buildings", []) as Array).is_empty()
	cb.survive_time = 10.0
	cb.elapsed = 9.5
	cb.step(0.6)
	var survive_ok := cb.ended and cb.winner == 0
	var stage_list: Array = catalog.stages()
	var special_ok: bool = stage_list.size() == 50
	for si: int in range(stage_list.size()):
		var sd: Dictionary = stage_list[si]
		if bool(sd.get("special", false)) != (si % 10 == 4 or si % 10 == 9): special_ok = false
	var single := Battle.new(92, ["farmer", "hunter", "militia", "farmer", "hunter", "militia", "rain", "barricade"], B.DEFAULT_DECK, "adventure", "iron")
	single.ai_enabled = [false, false]
	single.lord_active = [false, false]
	single.buildings = single.buildings.filter(func(b: Dictionary) -> bool: return b.team == 0)
	single.set_active_lanes([2])
	single.decks[0][0] = "hunter"
	single.hand_cd[0][0] = 0.0
	single.ink[0] = 50.0
	var single_farms_ok: bool = single.count_buildings(0, "farm") == 2 and single.buildings.all(func(b: Dictionary) -> bool: return b.cell.y == 2)
	var hunter_ok: bool = single.play_check(0, 0, L.cell_center(Vector2i(1, 2))) == Battle.Refusal.OK and single.play(0, 0, L.cell_center(Vector2i(1, 2))) and single.units.filter(func(u: Dictionary) -> bool: return u.kind == "hunter" and u.lane == 2).size() == 3
	single.units.clear()
	single.decks[0][0] = "spearbow"
	single.hand_cd[0][0] = 0.0
	var spear_ok: bool = single.play_check(0, 0, L.cell_center(Vector2i(0, 2))) == Battle.Refusal.FOOTPRINT and single.play(0, 0, L.cell_center(Vector2i(1, 2))) and single.units.filter(func(u: Dictionary) -> bool: return u.kind == "militia" and u.lane == 2 and preload("res://grid_rules.gd").cell_of(u.pos).x == 1).size() == 4 and single.units.filter(func(u: Dictionary) -> bool: return u.kind == "archer" and u.lane == 2 and preload("res://grid_rules.gd").cell_of(u.pos).x == 0).size() == 2
	var lesson_ok := tutorial_lesson_ok()
	check(campaign_errors.is_empty() and special_ok and block_ok and wind_ok and mods_ok and survive_ok and single_farms_ok and hunter_ok and spear_ok and lesson_ok.is_empty(), "campaign data and mechanics: " + str(campaign_errors) + " spec=%s block=%s wind=%s mods=%s surv=%s 1lane=%s/%s/%s lesson=%s" % [special_ok, block_ok, wind_ok, mods_ok, survive_ok, single_farms_ok, hunter_ok, spear_ok, lesson_ok])
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
	var fresh: bool = not ox_u.charged and cb.movement_speed(ox_u) > float(B.CARDS.ox.speed) # charging runs one tier faster
	cb.attack(ox_u, dummy)
	var struck: bool = ox_u.charged and dummy.hp <= 0 and is_equal_approx(cb.movement_speed(ox_u), float(B.CARDS.ox.speed)) # x2 hit, back to normal pace
	cb.remove_dead()
	for i: int in range(120): cb.step(1.0 / 60.0)
	var held: bool = ox_u.charged
	for i: int in range(65): cb.step(1.0 / 60.0)
	check(fresh and struck and held and not ox_u.charged, "a charger (ox) runs faster, hits x2, and recharges only after 3 s of marching")

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
	# While hidden it takes no troop, building or lord damage; spells still hit (使用者 2026-11-22).
	var hp_before: float = bandit.hp
	sb.damage(bandit, 50.0, 1, "militia")
	sb.damage(bandit, 50.0, 1, "lord")
	var stealth_immune: bool = is_equal_approx(bandit.hp, hp_before)
	sb.damage(bandit, 10.0, 1, "rain")
	var spell_hits: bool = bandit.hp < hp_before
	bandit.hp = hp_before
	var tower := sb.add_building(1, Vector2i(3, 2), "watchtower")
	var wt_expand_ok: bool = sb.territory_owner(Vector2i(5, 0)) == 1 and sb.territory_owner(Vector2i(1, 2)) == 0 and sb.territory_owner(Vector2i(6, 2)) == -1
	bandit.pos = tower.pos - Vector2(40, 0)
	sb.step(1.0 / 60.0)
	sb.buildings.clear()
	sb.refresh_territory()
	wt_expand_ok = wt_expand_ok and sb.territory_owner(Vector2i(5, 0)) == -1
	for i: int in range(185): sb.step(1.0 / 60.0)
	check(hidden_at_start and broke and restealthed and stealth_immune and spell_hits and bandit.revealed and not bandit.stealthed and wt_expand_ok, "stealth breaks on attack, returns after marching, only spells hurt it while hidden, and a watchtower reveals it for good and expands 5x5 territory (immune=%s spell=%s expand=%s)" % [stealth_immune, spell_hits, wt_expand_ok])

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
	var ExpCards = preload("res://expansion_cards.gd")
	var hrb := quiet(34)
	hrb.record_events = true
	var h_u := hrb.spawn_unit(0, 2, "healer", Vector2(380, 420))
	var a_in := ready_unit(hrb, 0, 2, "shieldguard", Vector2(380.0 + 244.0, 420.0))
	var a_out := ready_unit(hrb, 0, 2, "shieldguard", Vector2(380.0 + 274.0, 420.0))
	a_in.hp = a_in.max_hp - 80.0
	a_out.hp = a_out.max_hp - 80.0
	hrb.heal(h_u, 0.1)
	var pulse_ok: bool = hrb.events.any(func(ev: Dictionary) -> bool: return ev.get("kind", "") == "support_pulse" and ev.get("style", "") == "heal" and is_equal_approx(float(ev.get("radius", 0.0)), 236.0) and is_equal_approx(float(ev.get("source_radius", 0.0)), 12.0))
	var heal_range_ok: bool = is_equal_approx(hrb.unit_heal_radius(h_u), 236.0) and a_in.hp > a_in.max_hp - 80.0 and is_equal_approx(a_out.hp, a_out.max_hp - 80.0) and pulse_ok
	h_u.range_pct = 0.30
	h_u.heal_cd = 0.0
	hrb.heal(h_u, 0.1)
	heal_range_ok = heal_range_ok and is_equal_approx(hrb.unit_heal_radius(h_u), 307.0) and a_out.hp > a_out.max_hp - 80.0
	for uk: String in ["bellbearer", "funeral_monk"]:
		var ub := quiet(37)
		ub.record_events = true
		var bu := ub.spawn_unit(0, 2, uk, Vector2(380, 420))
		var bi := ready_unit(ub, 0, 2, "shieldguard", Vector2(380.0 + 244.0, 420.0))
		var bo := ready_unit(ub, 0, 2, "shieldguard", Vector2(380.0 + 274.0, 420.0))
		bi.hp = bi.max_hp - 60.0
		bo.hp = bo.max_hp - 60.0
		ExpCards.support(ub, bu, B.CARDS[uk])
		var u_pulse: bool = ub.events.any(func(ev: Dictionary) -> bool: return ev.get("kind", "") == "support_pulse" and ev.get("style", "") == "heal" and is_equal_approx(float(ev.get("radius", 0.0)), 236.0))
		heal_range_ok = heal_range_ok and is_equal_approx(ub.unit_heal_radius(bu), 236.0) and bi.hp > bi.max_hp - 60.0 and is_equal_approx(bo.hp, bo.max_hp - 60.0) and u_pulse

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

	check(heal_ok and heal_range_ok and hex_4_ok and hex_dmg_ok and hex_exp_ok and imm_ok, "poison stacks infinitely, healer units heal within their attack range and emit true-radius pulse, and buildings/mechanical units are immune")
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
	var rear: Array = fp.units.filter(func(u: Dictionary) -> bool: return u.kind == "archer" and Grid.cell_of(u.pos).x == 0)
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
	for pc: Array in [["aether_hound", Vector2i(1, 1)], ["dog_cannon", Vector2i(1, 3)], ["ward_phalanx", Vector2i(1, 2)], ["orrery_walker", Vector2i(1, 1)], ["militia", Vector2i(1, 1)], ["shieldguard", Vector2i(1, 2)], ["skeleton", Vector2i(1, 3)], ["guard", Vector2i(1, 2)], ["ram", Vector2i(1, 1)], ["mob", Vector2i(1, 2)], ["gold_monster", Vector2i(1, 2)], ["necromancer", Vector2i(1, 2)], ["pallbearer", Vector2i(1, 2)], ["blink_blade", Vector2i(1, 2)], ["aether_hound", Vector2i(1, 2)], ["raven", Vector2i(1, 2)], ["dark_wizard", Vector2i(1, 2)], ["thorn_mother", Vector2i(1, 2)], ["giant_arcane_golem", Vector2i(1, 2)]]:
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
	var inside_top := g.spawn_unit(1, 1, "militia", L.cell_center(Vector2i(3, 1)))
	var inside_bot := g.spawn_unit(1, 3, "militia", L.cell_center(Vector2i(4, 3)))
	var far := g.spawn_unit(1, 0, "militia", L.cell_center(Vector2i(3, 0)))
	var far_east := g.spawn_unit(1, 2, "militia", L.cell_center(Vector2i(5, 2)))
	g.cast_spell({"kind": "rain", "team": 0, "pos": inside.pos})
	check(top.hp < top.max_hp and bottom.hp < bottom.max_hp and aside.hp == aside.max_hp and inside.hp < inside.max_hp and inside_top.hp < inside_top.max_hp and inside_bot.hp < inside_bot.max_hp and far.hp == far.max_hp and far_east.hp == far_east.max_hp, "1x5 and 2x3 spells hit exactly their tiles")

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
	var minion_meta_ok := B.lord_name("card_enemy_rolling_boulder") == "巨石"
	for mk: String in B.MINION_LORDS:
		var mname: String = B.MINION_LORDS[mk].name
		if B.passive_text(B.MINION_LORDS[mk]).is_empty() or "主人" in mname or "飼主" in mname or "首領" in mname or "領主" in mname:
			minion_meta_ok = false
	var gm := Battle.new(52, B.DEFAULT_DECK, B.DEFAULT_DECK, "lion", "card_enemy_gold_monster")
	gm.ai_enabled = [false, false]
	gm.skill_cd[1] = 0.0
	gm.skill_charge[1] = gm.skill_need(1)
	var gm_ok := gm.cast_skill(1) and gm.units.any(func(u: Dictionary) -> bool: return u.team == 1 and u.kind == "gold_monster" and int(u.get("gold_paid", 0)) == 16)
	var sa := Battle.new(53, B.DEFAULT_DECK, B.DEFAULT_DECK, "lion", "card_enemy_seal_altar")
	sa.ai_enabled = [false, false]
	var altars_before := sa.buildings.filter(func(b: Dictionary) -> bool: return b.hp > 0 and b.team == 1 and b.kind == "seal_altar")
	var souls_before: float = float(altars_before[0].get("souls", 0.0)) if altars_before.size() == 1 else -1.0
	sa.skill_cd[1] = 0.0
	sa.skill_charge[1] = sa.skill_need(1)
	var sa_cast := sa.cast_skill(1)
	var altars_after := sa.buildings.filter(func(b: Dictionary) -> bool: return b.hp > 0 and b.team == 1 and b.kind == "seal_altar")
	var sa_ok := altars_before.size() == 1 and sa_cast and altars_after.size() == 1 and is_equal_approx(float(altars_after[0].get("souls", 0.0)), souls_before + 4.0)
	check(planned and ms.cast_skill(1) and ms.units.size() > before and is_equal_approx(ms.skill_cd[1], B.MINION_SKILL_COOLDOWN) and minion_meta_ok and gm_ok and sa_ok, "AI plans a minion lord skill, minion lord names/passives/gold_monster/seal_altar skills behave properly (meta=%s gm=%s sa=%s)" % [minion_meta_ok, gm_ok, sa_ok])
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
	var season_cards: Array = rg.run.pile + rg.run.board.map(func(sl: Dictionary) -> String: return String(sl.kind))
	var support_ok: bool = season_cards.filter(func(k: String) -> bool: return k in RCatalog.SEASON_RANDOM_KINDS).size() == RCatalog.SEASON_RANDOM_COUNT
	var pile_ok: bool = season_cards.size() == RCatalog.SEASON_SIZE and season_cards.count("battle") == 4 and season_cards.count("elite") == 2 and support_ok and rg.run.pile.size() == 6 and String(rg.run.pile[-1]) == "sboss" and rg.run.season == 0 and int(rg.run.get("cards_cleared", -1)) == 0
	check(pile_ok and rg.run.board.size() == 4 and rg.run.deck.size() == 8 and DS.valid(rg.run.deck, "lion") and rg.run.deck.all(func(k: String) -> bool: return B.card_faction(k) == B.lord_faction("lion")), "a roguelike run starts in spring: a 4-flag board drawn from a 10-card season pile (4 battles, 2 elites, 3 random support, the boss last), and a legal 8-card faction deck")
	rg.run.board[3] = RCatalog.make_slot("camp", rg.run, 3)
	rg.select_node(3)
	rg.trigger_node()
	var at_camp: bool = rg.run.phase == "camp"
	rg.camp_card_index = 0
	rg.camp_action(1)
	check(at_camp and rg.run.phase == "map" and Upgrades.level(rg.run.upgrades.get(rg.run.deck[0], {})) == 1 and int(rg.run.get("cards_cleared", 0)) == 1 and is_equal_approx(Upgrades.stat_pct("hp", 2), 0.5), "the camp forge upgrades the chosen card additively by percentage and increments cards_cleared")
	rg.set_elite(true)
	rg.make_battle()
	rg.settle(true)
	var elite_ok: bool = rg.run.season_wins == 1 and rg.run.relics.size() >= 1 and rg.run.phase == "reward" and int(rg.run.get("cards_cleared", 0)) == 2
	# The season's boss card turns every flag into the boss; beating it opens the next season, and after winter the 魔王.
	rg.run.phase = "map"
	rg.run.pile = ["sboss"]
	rg.select_node(0)
	rg.consume_board_slot(true)
	var boss_board: bool = rg.run.board.all(func(sl: Dictionary) -> bool: return sl.kind == "sboss")
	var sb_battle := rg.make_battle()
	var sb_key: String = rg.run.sbosses[0]
	var sb_giant: String = String(RCatalog.SEASON_BOSSES[sb_key].giant)
	var summons: bool = sb_battle.field_mutators.all(func(fm: Dictionary) -> bool: return fm.get("mode", "") != "units") and sb_battle.lords[1].has("shot") and sb_giant in sb_battle.decks[1]
	rg.settle(true)
	var summer: bool = rg.run.season == 1 and rg.run.pile.size() == 6 and not rg.run.board.any(func(sl: Dictionary) -> bool: return sl.kind == "sboss") and int(rg.run.get("cards_cleared", 0)) == 4
	rg.run.phase = "map"
	rg.run.season = 3
	rg.run.pile = ["sboss"]
	rg.consume_board_slot(true)
	rg.settle(true)
	var throne: bool = rg.is_boss() and rg.run.board[0].kind == "boss" and rg.valid_run(rg.run) and int(rg.run.get("cards_cleared", 0)) == 6
	var gold_rg := Rogue.new()
	gold_rg.save_path = "user://quick_test_rogue_gold.json"
	gold_rg.begin("lion", 4242, 1)
	gold_rg.run.board[0] = RCatalog.make_slot("battle", gold_rg.run, 0)
	gold_rg.run.board[1] = RCatalog.make_slot("battle", gold_rg.run, 1)
	gold_rg.select_node(0)
	gold_rg.consume_board_slot(true)
	var aged_bounty_ok: bool = int(gold_rg.run.board[1].get("bounty", 0)) == 70
	gold_rg.run.gold = 200
	gold_rg.reroll_board()
	var reroll_bounty_ok: bool = true
	for sl: Dictionary in gold_rg.run.board:
		if sl.get("kind", "") in ["battle", "elite", "boss", "sboss"] and int(sl.get("bounty", 0)) != 50:
			reroll_bounty_ok = false
	var gold_double_ok: bool = RCatalog.GOLD_BY_FLOOR == [200, 280, 360, 460, 560, 660, 780] and RCatalog.SKIP_REWARD_GOLD == 130 and gold_rg.win_gold(0, false, false) == 192 and gold_rg.win_gold(0, true, false) == 288 and gold_rg.win_gold(0, false, true) == 576 and aged_bounty_ok and reroll_bounty_ok
	for fp: String in [gold_rg.save_path, gold_rg.save_path + ".bak"]:
		if FileAccess.file_exists(fp): DirAccess.remove_absolute(ProjectSettings.globalize_path(fp))
	check(elite_ok and gold_double_ok and boss_board and summons and summer and throne, "an elite win drops a relic; post-battle gold/bounty/skip rewards are doubled; the drawn season boss takes the whole board and opens the next 10-card season (elite %s gold2x %s board %s summons %s summer %s throne %s)" % [elite_ok, gold_double_ok, boss_board, summons, summer, throne])
	var rs := Rogue.new()
	rs.save_path = "user://quick_test_rogue_scale.json"
	rs.begin("adventure", 777, 3)
	rs.run.cards_cleared = 10
	rs.run.floor = RCatalog.FLOORS - 1
	var last := rs.make_battle()
	var boss_ld := B.lord_data(last.lords[1].lord)
	var boss_lord_ok: bool = is_equal_approx(last.lords[1].max_hp, roundf(float(boss_ld.hp) * (1.0 + RCatalog.BOSS_LORD_PCT + 0.50))) and is_equal_approx(last.lords[1].damage, roundf(float(boss_ld.damage) * (1.0 + RCatalog.BOSS_LORD_PCT + 0.50)))
	var rs2 := Rogue.new()
	rs2.save_path = rs.save_path
	rs2.begin("lion", 555, 0)
	rs2.run.cards_cleared = 10
	rs2.run.board[0] = RCatalog.make_slot("battle", rs2.run, 0)
	rs2.select_node(0)
	var b10 := rs2.make_battle()
	var foe_ld := B.lord_data(rs2.foe())
	var foe_lord_ok: bool = is_equal_approx(b10.lords[1].max_hp, roundf(float(foe_ld.hp) * 1.50)) and is_equal_approx(b10.lords[1].damage, roundf(float(foe_ld.damage) * 1.50))
	var m_add: Dictionary = RCatalog.merge_mods({"income_mult": 1.25, "cycle_speed": {"*": 1.15}, "skill_charge_mult": 1.2, "toughen": {"*": 0.35}, "haste": {"*": 0.25}, "lord_pct": 0.30}, {"income_mult": 1.35, "cycle_speed": {"*": 1.30}, "skill_charge_mult": 1.3, "toughen": {"*": 0.35}, "haste": {"*": 0.30}, "lord_pct": 0.35})
	var merge_add_ok: bool = is_equal_approx(float(m_add.income_mult), 1.60) and is_equal_approx(float(m_add.cycle_speed["*"]), 1.45) and is_equal_approx(float(m_add.skill_charge_mult), 1.50) and is_equal_approx(float(m_add.toughen["*"]), 0.70) and is_equal_approx(float(m_add.haste["*"]), 0.55) and is_equal_approx(float(m_add.lord_pct), 0.65)
	var ab := quiet(88)
	ab.apply_domestic(0, "farm", {"toughen": {"*": 0.35}, "haste": {"*": 0.25}})
	ab.card_upgrades[0]["militia"] = {"hp": 2, "speed": 2, "interval": 2}
	ab.decks[0][0] = "militia"
	ab.hand_cd[0][0] = 0.0
	ab.ink[0] = 50.0
	var played_mu := ab.play(0, 0, L.cell_center(Vector2i(0, 2)))
	var mu: Dictionary = ab.units[0] if not ab.units.is_empty() else {}
	var unit_add_ok: bool = played_mu and not mu.is_empty() and is_equal_approx(mu.max_hp, roundf(float(B.CARDS.militia.hp) * 1.85)) and is_equal_approx(ab.movement_speed(mu), float(B.CARDS.militia.speed) * 1.55) and is_equal_approx(ab.attack_interval(mu), float(B.CARDS.militia.interval) / 1.55)
	check(is_equal_approx(float(last.lord_mod(1, "gold_gain_mult", 1.0)), 2.0) and is_equal_approx(float(last.lord_mod(1, "cd_speed_mult", 1.0)), 2.0) and boss_lord_ok and foe_lord_ok and merge_add_ok and unit_add_ok, "final floor doubles enemy gold/cd; roguelike bonuses & upgrades stack additively by percentage; enemy lords scale +5%% per card cleared (boss %s foe %s merge %s unit %s)" % [boss_lord_ok, foe_lord_ok, merge_add_ok, unit_add_ok])
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

	var mg := quiet(71)
	mg.add_building(0, Vector2i(1, 2), "mass_grave")
	for i: int in range(1350): mg.step(1.0 / 30.0)
	var mg_no_timer := mg.units.is_empty()
	var mg_sk0 := ready_unit(mg, 0, 2, "skeleton", L.cell_center(Vector2i(3, 2)))
	var mg_sk1 := ready_unit(mg, 1, 0, "skeleton", L.cell_center(Vector2i(5, 0)))
	mg.damage(mg_sk0, 9999.0, 1, "fire")
	mg.damage(mg_sk1, 9999.0, 0, "fire")
	mg.resolve_deaths()
	var mg_skip_skel: bool = mg.units.filter(func(u: Dictionary) -> bool: return u.hp > 0 and u.get("card", "") == "mass_grave").is_empty()
	var mg_f0 := ready_unit(mg, 1, 0, "militia", L.cell_center(Vector2i(5, 0)))
	var mg_a4 := ready_unit(mg, 0, 4, "militia", L.cell_center(Vector2i(3, 4)))
	mg.damage(mg_f0, 9999.0, 0, "fire")
	mg.damage(mg_a4, 9999.0, 1, "fire")
	mg.resolve_deaths()
	var mg_spawned: Array = mg.units.filter(func(u: Dictionary) -> bool: return u.hp > 0 and u.team == 0 and u.lane == 2 and u.kind == "skeleton" and u.get("card", "") == "mass_grave")
	if not mg_no_timer or not mg_skip_skel or mg_spawned.size() != 2:
		rework_fails.append("mass_grave")

	var g_up = preload("res://card_upgrades.gd")
	var g_grid = preload("res://grid_rules.gd")
	var g_cat = preload("res://roguelike_catalog.gd")
	var sss_ok: bool = is_equal_approx(B.tier_value("hp", "SSS"), 6666.0) and is_equal_approx(g_up.shifted("hp", 6666.0, 1), 6666.0) and DS.pool().all(func(k: String) -> bool: return not B.CARDS[k].get("boss_only", false))
	for sbk: String in g_cat.SEASON_BOSSES:
		var gk := String(g_cat.SEASON_BOSSES[sbk].giant)
		sss_ok = sss_ok and is_equal_approx(B.CARDS[gk].hp, 6666.0) and gk in g_cat.season_boss_deck(sbk)
	var gb := quiet(72)
	gb.decks[0][0] = "giant_arcane_golem"
	gb.hand_cd[0][0] = 0.0
	gb.ink[0] = 50.0
	var fp_ok: bool = gb.play_check(0, 0, L.cell_center(Vector2i(0, 1))) == Battle.Refusal.FOOTPRINT and gb.play_check(0, 0, L.cell_center(Vector2i(1, 4))) == Battle.Refusal.FOOTPRINT and gb.play_check(0, 0, L.cell_center(Vector2i(1, 2))) == Battle.Refusal.OK and gb.play(0, 0, L.cell_center(Vector2i(1, 2)))
	var gunit: Dictionary = gb.units[0] if gb.units.size() == 1 else {}
	var spawn_ok: bool = not gunit.is_empty() and gunit.get("lanes", []) == [2, 3] and is_equal_approx(gunit.hp, 6666.0) and is_equal_approx(gunit.pos.y, (L.cell_center(Vector2i(0, 2)).y + L.cell_center(Vector2i(0, 3)).y) * 0.5)
	var g_twr := gb.add_building(1, Vector2i(3, 3), "tower")
	gb.build_lookups()
	var twr_pick_ok: bool = is_same(g_grid.pick(gb, g_twr, gb.foe_units[1]), gunit)
	var g_m2 := ready_unit(gb, 1, 2, "militia", Vector2(gunit.pos.x + 125.0, L.cell_center(Vector2i(0, 2)).y))
	var g_m3 := ready_unit(gb, 1, 3, "militia", Vector2(gunit.pos.x + 125.0, L.cell_center(Vector2i(0, 3)).y))
	var gfarm := gb.add_building(1, Vector2i(2, 3), "farm")
	gb.build_lookups()
	var both_hit_ok: bool = not gunit.is_empty() and is_same(gb.choose_target(g_m2, B.CARDS.militia), gunit) and is_same(gb.choose_target(g_m3, B.CARDS.militia), gunit)
	var g_hp0: float = gunit.hp if not gunit.is_empty() else 0.0
	if not gunit.is_empty(): gb.cast_spell({"kind": "rain", "team": 1, "pos": gunit.pos})
	var aoe_once_ok: bool = not gunit.is_empty() and is_equal_approx(g_hp0 - gunit.hp, B.CARDS.rain.damage)
	if not gunit.is_empty(): gb.attack(gunit, g_m2)
	var sweep_ok: bool = g_m2.hp < g_m2.max_hp and g_m3.hp < g_m3.max_hp and gfarm.hp < gfarm.max_hp
	var gg := quiet(73)
	ready_unit(gg, 0, 2, "giant_arcane_golem", Vector2(L.gate_stop(1) - B.kind_radius("giant_arcane_golem") - 2.0, L.cell_center(Vector2i(0, 2)).y))
	for _i: int in range(60): gg.step(1.0 / 30.0)
	var dual_gate_ok: bool = gg.gates[1][2] < B.GATE_HP and is_equal_approx(gg.gates[1][2], gg.gates[1][3])
	var g3_mid: float = gg.gates[1][3]
	gg.gates[1][2] = 0.0
	for _i: int in range(60): gg.step(1.0 / 30.0)
	dual_gate_ok = dual_gate_ok and not gg.ended and gg.gates[1][3] < g3_mid
	gg.gates[1][3] = 0.0
	for _i: int in range(90): gg.step(1.0 / 10.0)
	dual_gate_ok = dual_gate_ok and gg.ended and gg.winner == 0
	var gc := quiet(74)
	var gcat := ready_unit(gc, 0, 2, "giant_catapult", L.cell_center(Vector2i(3, 2)))
	var cat_foe3 := ready_unit(gc, 1, 3, "militia", L.cell_center(Vector2i(7, 3)))
	gc.build_lookups()
	var cat_ok: bool = is_same(gc.catapult_target(gcat), cat_foe3)
	gc.units.erase(cat_foe3)
	gcat.pos.x = L.cell_center(Vector2i(5, 2)).x
	gc.build_lookups()
	cat_ok = cat_ok and gc.catapult_target(gcat).get("kind", "") == "gate"
	for _i: int in range(90): gc.step(1.0 / 30.0)
	cat_ok = cat_ok and gc.gates[1][2] < B.GATE_HP and gc.gates[1][3] < B.GATE_HP
	if not sss_ok or not fp_ok or not spawn_ok or not twr_pick_ok or not both_hit_ok or not aoe_once_ok or not sweep_ok or not dual_gate_ok or not cat_ok:
		rework_fails.append("giant_2x2[sss=%s fp=%s sp=%s twr=%s hit=%s aoe=%s swp=%s gate=%s cat=%s]" % [sss_ok, fp_ok, spawn_ok, twr_pick_ok, both_hit_ok, aoe_once_ok, sweep_ok, dual_gate_ok, cat_ok])

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
	var MP = preload("res://music_player.gd")
	var MM = preload("res://music_mood.gd")
	var missing_music: Array = []
	for t_name: String in MP.THEMES:
		for l_name: String in MP.LAYERS:
			var mpath := "%sbattle_%s_%s.ogg" % [MP.DIR, t_name, l_name]
			if not ResourceLoader.exists(mpath): missing_music.append(mpath)
	var adv_m := preload("res://adventure.gd").new()
	adv_m.progress_path = "user://quick_test_music_unused.json"
	var m_conv: Battle = adv_m.make_battle(9, adv_m.STAGES[9].deck.duplicate(), "adventure")
	var mood_ok: bool = MM.theme(m_conv, 0) == "conveyor" and (MM.theme(champ, 0) in MP.THEMES)
	var polish = preload("res://ui_polish.gd").new()
	check(peak <= cd.MAX_IMPULSE + 0.01 and cd.impulse.length() < 0.5 and sort_ok and missing_sfx.is_empty() and missing_music.is_empty() and mood_ok and is_equal_approx(polish.screen_enter_t, 1.0), "camera shake stays bounded and settles under stacked events and frame spikes; CardSort, SoundBank (%s), Music (%s) and UiPolish are valid" % [str(missing_sfx), str(missing_music)])
	preload("res://tools/test_art_palette.gd").run(self)
