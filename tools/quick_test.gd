extends SceneTree

const Battle = preload("res://battle.gd")
const B = preload("res://balance.gd")
const DS = preload("res://deck_store.gd")

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

func run() -> void:
	var campaign_errors := preload("res://campaign_catalog.gd").validate()
	check(campaign_errors.is_empty(), "campaign data: " + str(campaign_errors))
	var rogue_errors := preload("res://roguelike_catalog.gd").validate()
	check(rogue_errors.is_empty(), "roguelike data: " + str(rogue_errors))
	var problems := B.validate()
	check(problems.is_empty(), "balance.gd validate: " + str(problems))
	check(DS.valid(B.DEFAULT_DECK, B.DEFAULT_LORD), "default deck valid")
	check(load("res://game.gd") != null, "game.gd loads")

	# Core battle determinism sanity check
	var a := Battle.new(7)
	var b := Battle.new(7)
	for i: int in range(360):
		a.step(1.0 / 60.0)
		b.step(1.0 / 60.0)
	check(a.winner == b.winner and is_equal_approx(a.elapsed, b.elapsed) and a.rng.state == b.rng.state, "deterministic simulation")

	# Old Witch neutral AoE + DoT check
	var wb := Battle.new(11)
	wb.ai_enabled = [false, false]
	wb.lords[0].hp = 0
	wb.lords[1].hp = 0
	wb.lord_active = [false, false]
	var witch := wb.spawn_unit(0, 2, "old_witch", Vector2(520, 420))
	witch.spawn_delay = 0.0
	var sk1 := wb.spawn_unit(1, 2, "skeleton", Vector2(610, 420))
	sk1.spawn_delay = 0.0
	var sk2 := wb.spawn_unit(1, 2, "skeleton", Vector2(635, 420))
	sk2.spawn_delay = 0.0
	for _s: int in range(180): # ~3.0s: cast AoE + 2 DoT ticks finish 50-HP skeletons without spreading plague zones
		wb.step(1.0 / 60.0)
	check(sk1.hp <= 0 and sk2.hp <= 0, "old_witch AoE + DoT kills clustered skeletons")
	check(wb.zones.is_empty(), "old_witch DoT does not spawn plague clouds")

	# Glutton Nest Beast home card check (F slot replaces farm, starting nests, devour HP->gold, AI avoids self-eat)
	check(B.home_card("beast") == "glutton_nest" and B.is_home_card("glutton_nest", "beast"), "glutton_nest is beast home card")
	check(not ("glutton_nest" in DS.pool("beast")) and not ("glutton_nest" in DS.pool("lion")), "home card glutton_nest stays out of 8-card pool")
	var gn_model := Battle.new(13, [], [], "beast", "lion")
	gn_model.ai_enabled = [false, false]
	gn_model.lords[0].hp = 0
	gn_model.lords[1].hp = 0
	gn_model.lord_active = [false, false]
	check(gn_model.kind_at(0, gn_model.FARM_SLOT) == "glutton_nest" and gn_model.count_buildings(0, "glutton_nest") == 2 and gn_model.count_buildings(0, "farm") == 0, "beast begins with two glutton_nests instead of farms")
	var nest := gn_model.add_building(0, Vector2i(2, 2), "glutton_nest")
	check(preload("res://glutton_nest.gd").hidden(nest), "glutton_nest starts hidden")
	gn_model.damage(nest, 100.0, 1, "fire")
	check(nest.hp == nest.max_hp, "hidden glutton_nest takes no damage")
	var prey := gn_model.spawn_unit(1, 2, "ox", nest.pos)
	prey.spawn_delay = 0.0
	var ink_before: float = gn_model.ink[0]
	gn_model.step(1.0 / 60.0)
	check(prey.hp > 0 and nest.get("nest_windup",0.0) > 0 and not preload("res://glutton_nest.gd").hidden(nest), "nest telegraphs before damage and becomes vulnerable")
	preload("res://glutton_nest.gd").update(gn_model,nest,B.CARDS.glutton_nest.windup)
	check(prey.hp <= 0 and gn_model.ink[0] > ink_before and not preload("res://glutton_nest.gd").hidden(nest), "glutton_nest devours ground foe for gold and exposes")
	gn_model.damage(nest, 100.0, 1, "fire")
	check(nest.hp < nest.max_hp, "digesting glutton_nest can take damage")

	# 金幣怪物: whole purse, bodies and tiers from B.GOLD_MONSTER_STAGES (closest value, never a lower stat for one more coin unless a body is added).
	var GM = preload("res://gold_monster.gd")
	var gm_rows: Array = B.GOLD_MONSTER_STAGES
	var gm_ok := int(gm_rows[0][0]) == 1 and int(gm_rows[-1][0]) <= int(B.MAX_INK)
	for i: int in range(gm_rows.size()):
		var r: Array = gm_rows[i]
		gm_ok = gm_ok and B.TIERS.hp.has(float(r[2])) and B.TIERS.damage.has(float(r[3])) and B.TIERS.interval.has(float(r[4])) and B.TIERS.speed.has(float(r[5])) and int(r[1]) >= 1 and int(r[1]) <= 5
		if i > 0:
			var p: Array = gm_rows[i-1]
			gm_ok = gm_ok and int(r[0]) > int(p[0]) and int(r[1]) >= int(p[1])
			if int(r[1]) == int(p[1]): gm_ok = gm_ok and r[2] >= p[2] and r[3] >= p[3] and r[4] <= p[4] and r[5] >= p[5]
	check(gm_ok, "gold_monster stages: tier values, 1..MAX_INK, bodies 1-5, no stat drops unless a body is added")
	var gm_bat := Battle.new(15, [], [], "lion", "lion")
	gm_bat.ai_enabled = [false, false]
	gm_bat.lord_active = [false, false]
	var gm_pos: Vector2 = preload("res://layout.gd").cell_center(Vector2i(1, 2))
	for gm_case: Array in [[37.6, 2, 900.0, 95.0, 0.65, 65.0], [50.0, 5, 900.0, 70.0, 1.9, 90.0], [1.2, 1, 130.0, 36.0, 1.9, 36.0]]:
		gm_bat.units.clear()
		gm_bat.decks[0][0] = "gold_monster"
		gm_bat.hand_cd[0][0] = 0.0
		gm_bat.ink[0] = gm_case[0]
		var spent_before: float = gm_bat.stats[0].spent.get("gold_monster", 0.0)
		var played: bool = gm_bat.play(0, 0, gm_pos)
		var bodies: Array = gm_bat.units.filter(func(u: Dictionary) -> bool: return u.kind == "gold_monster")
		var paid := floorf(gm_case[0])
		var shape_ok := bodies.size() == int(gm_case[1]) and bodies.all(func(u: Dictionary) -> bool: return u.max_hp == gm_case[2] and u.hp == gm_case[2] and u.damage == gm_case[3] and u.interval == gm_case[4] and u.speed == gm_case[5])
		check(played and is_equal_approx(gm_bat.ink[0], gm_case[0]-paid) and is_equal_approx(gm_bat.stats[0].spent.gold_monster-spent_before, paid) and shape_ok, "gold_monster with %s gold pays %d and fields %d x hp %s" % [str(gm_case[0]), int(paid), int(gm_case[1]), str(gm_case[2])])
	gm_bat.decks[0][0] = "gold_monster"
	gm_bat.hand_cd[0][0] = 0.0
	gm_bat.ink[0] = 0.5
	check(gm_bat.play_check(0, 0, gm_pos) == Battle.Refusal.GOLD, "gold_monster needs at least one whole coin")
	check(GM.cost_text("gold_monster", B.CARDS.gold_monster) == "全" and GM.cost_text("militia", B.CARDS.militia) == str(B.CARDS.militia.cost), "hand medallion reads 全 only for gold_monster")
	check(GM.ai_wait("gold_monster", 20.0, false) and not GM.ai_wait("gold_monster", 30.0, false) and not GM.ai_wait("gold_monster", 9.0, true) and not GM.ai_wait("militia", 0.0, false), "AI saves up for gold_monster, settles for less when defending")
	check(B.card_description("gold_monster").contains("花光全部金幣"), "gold_monster card text describes the whole-purse cost")

	# 封印祭壇: one per side, souls from deaths (own lane counts double), seals scare, last seal releases 瘟疫主教 + monks.
	var sa := Battle.new(16, [], [], "underworld", "lion")
	sa.ai_enabled = [false, false]
	sa.lord_active = [false, false]
	var SLayout = preload("res://layout.gd")
	sa.decks[0][0] = "seal_altar"
	sa.hand_cd[0][0] = 0.0
	sa.ink[0] = 50.0
	check(sa.play(0, 0, SLayout.cell_center(Vector2i(1, 2))), "seal_altar can be built")
	var sa_altar: Dictionary = sa.building_at(Vector2i(1, 2))
	sa.decks[0][0] = "seal_altar"
	sa.hand_cd[0][0] = 0.0
	check(sa.play_check(0, 0, SLayout.cell_center(Vector2i(1, 1))) == Battle.Refusal.UNIQUE and sa.play_check(0, 0, SLayout.cell_center(Vector2i(1, 2))) == Battle.Refusal.OK, "only one seal_altar per side; topping up the same one is allowed")
	var sa_kill := func(lane: int, x_col: int) -> void:
		var v: Dictionary = sa.spawn_unit(1, lane, "militia", SLayout.cell_center(Vector2i(x_col, lane)))
		v.spawn_delay = 0.0
		sa.damage(v, 9999.0, 0, "fire")
		sa.resolve_deaths()
	sa_kill.call(2, 6)
	sa_kill.call(0, 6)
	check(is_equal_approx(sa_altar.get("souls", 0.0), 2.0), "seal_altar: every death gives 1 soul, in its lane or elsewhere")
	var sa_scared: Dictionary = sa.spawn_unit(1, 2, "militia", sa_altar.pos + Vector2(60, 0))
	sa_scared.spawn_delay = 0.0
	sa_altar.souls = 19.0
	sa_kill.call(0, 6)
	check(sa_scared.get("fear_left", 0.0) > 0.0 and sa_altar.hp > 0, "breaking a seal makes nearby foes flee")
	sa_altar.souls = 59.0
	sa_kill.call(0, 6)
	var sa_proc: Array = sa.units.filter(func(u: Dictionary) -> bool: return u.team == 0 and u.hp > 0)
	check(sa_altar.hp <= 0 and sa_proc.filter(func(u: Dictionary) -> bool: return u.kind == "plague_bishop").size() == 1 and sa_proc.filter(func(u: Dictionary) -> bool: return u.kind == "funeral_monk").size() == 4, "the last seal shatters the sa_altar and releases the bishop with four monks")
	var sa_zones0: int = sa.zones.filter(func(z: Dictionary) -> bool: return z.team == 0).size()
	for i: int in range(150): sa.step(1.0 / 60.0)
	check(sa.zones.filter(func(z: Dictionary) -> bool: return z.team == 0).size() > sa_zones0, "the plague bishop leaves rotting ground behind him")
	var sa_open_ok := true
	for sa_seed: int in range(40):
		var sa_b := Battle.new(900+sa_seed, ["seal_altar","skeleton","ghoul","necromancer","plague","bellbearer","raven","reaper"], [], "underworld", "lion")
		sa_open_ok = sa_open_ok and not ("seal_altar" in sa_b.decks[0].slice(0,4)) and sa_b.decks[0].size() == 8 and "seal_altar" in sa_b.decks[0]
	check(sa_open_ok, "seal_altar never starts in the opening hand (40 shuffles)")
	check(B.card_description("seal_altar").contains("每方只能有一座") and B.card_description("plague_bishop").contains("土地腐敗"), "seal_altar and plague_bishop texts come from their data")

	var gn_ai := Battle.new(14, ["fishbeak", "bearded_imp", "belly_eye", "hooknose_flyer", "long_dragon", "thorn_dragon", "eyewing_dragon", "tusk_boar"], [], "beast", "lion")
	gn_ai.ai_enabled = [false, false]
	gn_ai.lords[0].hp = 0
	gn_ai.lords[1].hp = 0
	gn_ai.lord_active = [false, false]
	gn_ai.decks[0] = ["fishbeak", "bearded_imp", "belly_eye", "hooknose_flyer", "long_dragon", "thorn_dragon", "eyewing_dragon", "tusk_boar"]
	gn_ai.hand_cd[0] = [99.0, 99.0, 99.0, 99.0]
	gn_ai.farm_cd[0] = 0.0
	gn_ai.ink[0] = 20.0
	var p01 := Vector2.ZERO
	var p03 := Vector2.ZERO
	var p81 := Vector2.ZERO
	for gn_b: Dictionary in gn_ai.buildings:
		if gn_b.cell == Vector2i(0, 1): p01 = gn_b.pos
		elif gn_b.cell == Vector2i(0, 3): p03 = gn_b.pos
		elif gn_b.cell == Vector2i(8, 1): p81 = gn_b.pos
	var dx: float = (p81.x - p01.x) / 8.0
	var y2: float = (p01.y + p03.y) * 0.5
	var ally_u := gn_ai.spawn_unit(0, 2, "ox", Vector2(p01.x, y2))
	ally_u.spawn_delay = 0.0
	var foe1 := gn_ai.spawn_unit(1, 2, "ox", Vector2(p01.x + dx * 1.0, y2))
	foe1.spawn_delay = 0.0
	var foe2 := gn_ai.spawn_unit(1, 2, "ox", Vector2(p01.x + dx * 1.0, y2))
	foe2.spawn_delay = 0.0
	var unsafe_act: Dictionary = preload("res://enemy_ai.gd").decide(gn_ai.snapshot(0))
	check(unsafe_act.get("cell", Vector2i(-1, -1)) != Vector2i(1, 2), "AI rejects enlarged nest that would eat its own nearby ox")
	ally_u.pos.x -= dx
	var ai_act: Dictionary = preload("res://enemy_ai.gd").decide(gn_ai.snapshot(0))
	check(ai_act.get("slot", -1) == gn_ai.FARM_SLOT and ai_act.get("kind", "") == "glutton_nest" and ai_act.get("cell", Vector2i(-1, -1)) == Vector2i(1, 2), "AI places glutton_nest from F slot onto forward enemy cluster away from col 0")
	gn_ai.hand_cd[0] = [0.0, 99.0, 99.0, 99.0]
	gn_ai.farm_cd[0] = 99.0
	var lane1_foe := gn_ai.spawn_unit(1, 1, "ox", Vector2(p01.x + dx * 1.0, p01.y))
	lane1_foe.spawn_delay = 0.0
	var unit_act: Dictionary = preload("res://enemy_ai.gd").decide(gn_ai.snapshot(0))
	check(unit_act.get("cell", Vector2i(-1, -1)) != Vector2i(0, 1), "AI avoids spawning ground units behind its own armed glutton_nest")

	# One trigger consumes the whole enlarged area; cooldown follows the combined payout.
	var nest_rules = preload("res://glutton_nest.gd")
	var batch := Battle.new(19, [], [], "beast", "lion")
	batch.buildings.clear()
	batch.units.clear()
	batch.record_events = false
	batch.ink[0] = 0.0
	var mouth := batch.add_building(0, Vector2i(2, 2), "glutton_nest")
	nest_rules.update(batch, mouth, 40.0)
	check(batch.ink[0] == 0.0 and nest_rules.hidden(mouth), "idle nest never generates passive gold")
	var meal: Array[Dictionary] = []
	var health := 0.0
	for i: int in range(6):
		var unit := batch.spawn_unit(i % 2, 2, "militia", mouth.pos + Vector2(i * 24, 0))
		unit.spawn_delay = 0.0
		health += unit.hp
		meal.append(unit)
	var outside := batch.spawn_unit(1, 2, "militia", mouth.pos + Vector2(160, 0))
	outside.spawn_delay = 0.0
	nest_rules.update(batch, mouth, 0.01)
	check(meal.all(func(u: Dictionary) -> bool: return u.hp > 0), "windup cannot kill before impact")
	var rng_before: int = batch.rng.state
	nest_rules.update(batch, mouth, B.CARDS.glutton_nest.windup)
	check(batch.rng.state == rng_before and batch.events.is_empty(), "nest animation consumes no RNG or events when recording is disabled")
	check(meal.all(func(u: Dictionary) -> bool: return u.hp <= 0) and outside.hp > 0, "nest eats all six enemy and friendly units inside enlarged radius only")
	check(mouth.last_gold == nest_rules.gold_for_health(health) and mouth.digest_left == nest_rules.digestion_time(mouth.last_gold), "digestion uses total meal gold")
	check(nest_rules.digestion_time(5) == 20.0 and nest_rules.digestion_time(10) == 30.0, "larger payout takes longer to digest")
	mouth.hp = 100.0
	nest_rules.update(batch,mouth,B.CARDS.glutton_nest.bite_duration+B.CARDS.glutton_nest.chew_period)
	check(mouth.hp == 120.0, "one completed chew restores a small amount while events are disabled")
	mouth.hp = mouth.max_hp-1.0
	nest_rules.update(batch,mouth,B.CARDS.glutton_nest.chew_period)
	check(mouth.hp == mouth.max_hp, "chewing cannot exceed maximum health")
	var saved_gold: float = batch.ink[0]
	nest_rules.update(batch, mouth, mouth.digest_left)
	check(nest_rules.hidden(mouth) and batch.ink[0] == saved_gold, "digestion ends hidden without extra gold")

	batch.units.clear()
	var runner := batch.spawn_unit(1,2,"militia",mouth.pos)
	runner.spawn_delay = 0.0
	nest_rules.update(batch,mouth,0.01)
	runner.pos.x += B.CARDS.glutton_nest.radius+10.0
	nest_rules.update(batch,mouth,B.CARDS.glutton_nest.windup)
	check(runner.hp > 0 and mouth.last_gold == 0, "prey escaping during windup survives the bite")
	mouth.hp = 100.0
	nest_rules.update(batch,mouth,B.CARDS.glutton_nest.chew_period+B.CARDS.glutton_nest.bite_duration)
	check(mouth.hp == 100.0, "an empty bite gives no chewing recovery")
	mouth.digest_left = 0.0
	nest_rules.update(batch,mouth,5.0)
	check(mouth.hp == 100.0, "hidden nest does not regenerate after digestion")
	runner.pos = mouth.pos
	nest_rules.update(batch,mouth,0.01)
	batch.damage(mouth,mouth.hp,1,"fire",{},true)
	nest_rules.update(batch,mouth,B.CARDS.glutton_nest.windup)
	check(runner.hp > 0, "destroying the exposed nest cancels its pending bite")

	check("pouch_beast" in DS.pool("beast") and not ("pouch_beast" in DS.pool("lion")), "pouch beast belongs to monster card pool")
	for side: int in range(2):
		var pack := Battle.new(21, [], [], "beast", "beast")
		pack.record_events = false
		pack.ink[side] = B.MAX_INK
		pack.units.clear()
		pack.skill_cd[side] = 0.0
		pack.add_building(side,Vector2i(4,2),"farm")
		pack.cast_skill(side)
		var beasts: Array = pack.units.filter(func(u: Dictionary) -> bool: return u.team == side and u.kind == "pouch_beast")
		check(beasts.size() == pack.active_lanes.size() and pack.units.all(func(u: Dictionary) -> bool: return u.kind != "fishbeak"), "beast skill summons one pouch beast per lane, side %d" % side)
		check(beasts.all(func(u: Dictionary) -> bool: return u.pos == Battle.L.cell_center(Vector2i(pack.front_column(side,u.lane),u.lane))), "beast skill summons at each lane territory front, side %d" % side)
		check(beasts.all(func(u: Dictionary) -> bool: return u.hp == 560.0 and u.max_hp == 560.0), "summoned pouch beasts have full heavy infantry health")
		pack.units.clear()
		pack.buildings.clear()
		var hatch := pack.add_building(side,Vector2i(2 if side == 0 else 6,2),"monster_hatchery")
		preload("res://expansion_cards.gd").update(pack,B.CARDS.monster_hatchery.period)
		check(pack.units.size() == 1 and pack.units[0].kind == "pouch_beast" and pack.units[0].team == side, "hatchery produces a pouch beast for its owner")
	check(B.card_description("monster_hatchery").contains("囊腹獸") and B.skill_text("beast").contains("囊腹獸"), "summon descriptions name the actual summon")

	preload("res://tools/test_art_palette.gd").run(self)

	if failures > 0:
		printerr("FAIL: %d checks, %d failures" % [checks, failures])
		quit(1)
	else:
		print("QUICK PASS: %d checks, 0 failures" % checks)
		quit(0)
