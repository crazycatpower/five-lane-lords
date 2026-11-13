extends SceneTree
# 肉鴿模式: catalog rules, 小怪領主 passives, the run flow and its screens.
# Standalone: godot_console --headless --path . -s tools/test_roguelike.gd

const Battle = preload("res://battle.gd")
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const DS = preload("res://deck_store.gd")
const Catalog = preload("res://roguelike_catalog.gd")
const Rogue = preload("res://roguelike.gd")
const Upgrades = preload("res://card_upgrades.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run_standalone")

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + msg)

func run_standalone() -> void:
	run(self)
	if failures > 0:
		printerr("TEST FAIL: %d checks, %d failures" % [checks, failures])
		quit(1)
	else:
		print("ROGUELIKE PASS: %d checks, 0 failures" % checks)
		quit(0)

static func versus(foe: String, seed_value: int = 5) -> Battle:
	var m := Battle.new(seed_value,Catalog.starter_deck("harvest","lion"),Catalog.foe_deck(foe),"lion",foe)
	m.ai_enabled = [false,false]
	return m

static func run(t) -> void:
	var problems := Catalog.validate()
	t.check(problems.is_empty(),"roguelike catalog: "+str(problems))
	t.check(B.validate().is_empty(),"balance validate with minion lords: "+str(B.validate()))
	# Two lords: the 內政 lord brings ranged troops, the 戰鬥 lord melee troops; same faction, same troop.
	for domestic: String in B.LORDS:
		for combat: String in B.LORDS:
			if domestic == combat: continue
			var deck: Array = Catalog.starter_deck(domestic,combat)
			t.check(B.card_group(deck[0]) == 1 and B.card_faction(deck[0]) == B.lord_faction(domestic),"%s+%s: ranged troops from the 內政 lord" % [domestic,combat])
			t.check(B.card_group(deck[3]) == 0 and B.card_faction(deck[3]) == B.lord_faction(combat),"%s+%s: melee troops from the 戰鬥 lord" % [domestic,combat])
			for other: String in B.LORDS:
				if other != combat and other != domestic and B.lord_faction(other) == B.lord_faction(domestic):
					t.check(Catalog.starter_deck(other,combat)[0] == deck[0],"same-faction 內政 lords bring the same ranged troop: %s / %s" % [domestic,other])
	# 內政 passives reach the battle.
	var duo := Battle.new(3,Catalog.starter_deck("underworld","lion"),[],"lion","bandit_chief")
	duo.apply_domestic(0,B.home_card("lion"),Catalog.passive("underworld"))
	t.check(duo.home_cards[0] == "farm" and duo.count_buildings(0,"farm") == 2 and duo.count_buildings(0,"grave") == 0,"a 冥府 內政 lord does not change the 戰鬥 lord's farms")
	var home_run = Rogue.new()
	home_run.save_path = "user://rogue-home-test.json"
	home_run.begin("harvest","underworld",9)
	var home_battle: Battle = home_run.make_battle()
	t.check(home_battle.home_cards[0] == "grave" and home_battle.count_buildings(0,"grave") == 2 and home_battle.count_buildings(0,"farm") == 0,"the 戰鬥 lord decides the starting economy buildings")
	t.check(home_battle.skill_error(0) != "沒有墓碑","冥府 as 戰鬥 lord always has tombstones for its skill")
	t.check(duo.spawn_unit(0,2,"dark_wizard",L.cell_center(Vector2i(2,2))).max_hp == B.TIERS.hp[B.TIERS.hp.find(B.CARDS.dark_wizard.hp)-1],"冥府內政: dark wizards one hp tier tougher")
	t.check(duo.lords[0].lord == "lion" and duo.skill_error(0) != "這位領主沒有技能。","the 戰鬥 lord is on the field with its skill")
	duo = Battle.new(3,Catalog.starter_deck("adventure","mage"),[],"mage","bandit_chief")
	var gold: float = duo.ink[0]
	duo.apply_domestic(0,B.home_card("adventure"),Catalog.passive("adventure"))
	t.check(duo.ink[0] == gold+10.0,"邊境內政: +10 starting gold")
	duo = Battle.new(3,Catalog.starter_deck("harvest","lion"),[],"lion","bandit_chief")
	var plain: float = duo.production_rate(0)
	duo.apply_domestic(0,B.home_card("harvest"),Catalog.passive("harvest"))
	t.check(duo.production_rate(0) > plain,"豐收內政: farms produce more")
	duo = Battle.new(3,Catalog.starter_deck("iron","lion"),[],"lion","bandit_chief")
	duo.apply_domestic(0,B.home_card("iron"),Catalog.passive("iron"))
	t.check(duo.building_at(Vector2i(1,2)).get("kind","") == "barricade","鐵壁內政: barricades at the start")
	duo = Battle.new(3,Catalog.starter_deck("mage","lion"),[],"lion","bandit_chief")
	duo.apply_domestic(0,B.home_card("mage"),Catalog.passive("mage"))
	duo.hand_cd[0] = [10.0,10.0,10.0,10.0]
	duo.hand_cd[1] = [10.0,10.0,10.0,10.0]
	duo.tick_clocks(1.0)
	t.check(duo.hand_cd[0][0] < duo.hand_cd[1][0],"法師內政: every card cools down faster")

	# 小怪領主 stay out of normal mode.
	for foe: String in B.MINION_LORDS:
		t.check(not B.LORDS.has(foe) and not foe in B.lord_menu_order(),"minion lord not offered in normal mode: "+foe)
		t.check(not B.has_skill(foe) and not B.minion_text(foe).is_empty(),"minion lord has a passive instead of a skill: "+foe)
	t.check(not DS.save_deck(B.PRESETS[0],"user://rogue-deck-test.json","bandit_chief"),"a deck cannot be saved for a minion lord")

	# 強盜頭子: no farms, base gold doubled.
	var m := versus("bandit_chief")
	t.check(m.home_cards[1] == "" and m.count_buildings(1,"farm") == 0,"bandit chief starts without farms or a home card")
	t.check(is_equal_approx(m.production_rate(1),2.0/B.BASE_INTERVAL),"bandit chief's base income is doubled")
	m.ink = [0.0,0.0]
	for i: int in range(60*10): m.step(1.0/60.0)
	t.check(m.ink[1] >= 9.0 and m.ink[1] <= 11.0,"bandit chief gains about 10 gold in 10 s (got %s)" % str(m.ink[1]))
	t.check(not m.skill_error(1).is_empty() and not m.cast_skill(1),"a minion lord cannot cast a skill")

	# Home card swap, toughen, haste, swarm, start buildings.
	t.check(versus("skeleton_king").count_buildings(1,"grave") == 2,"skeleton king starts with tombstones")
	m = versus("knight_commander")
	var knight := m.spawn_unit(1,2,"knight",L.cell_center(Vector2i(6,2)))
	var red_knight := m.spawn_unit(0,2,"knight",L.cell_center(Vector2i(2,2)))
	t.check(knight.max_hp == 1500.0 and red_knight.max_hp == B.CARDS.knight.hp,"knight commander's knights are one hp tier tougher")
	m = versus("drummer_major")
	var fast := m.spawn_unit(1,2,"militia",L.cell_center(Vector2i(6,2)))
	var slow := m.spawn_unit(0,2,"militia",L.cell_center(Vector2i(2,2)))
	t.check(m.movement_speed(fast) > m.movement_speed(slow) and m.attack_interval(fast) < m.attack_interval(slow),"drummer major hastes every troop")
	m = versus("militia_captain")
	m.units.clear()
	m.deploy(1,"militia",Vector2i(6,2))
	t.check(m.units.size() == B.CARDS.militia.count+2,"militia captain deploys two extra militia")
	m = versus("tower_warden")
	t.check(m.building_at(Vector2i(7,1)).get("kind","") == "tower" and m.building_at(Vector2i(7,3)).get("kind","") == "tower","tower warden starts with towers on its side")

	# Every 小怪領主 and boss plays a short AI match without errors.
	var foes: Array = B.MINION_LORDS.keys()+Catalog.BOSSES.keys()
	for i: int in range(foes.size()):
		m = Battle.new(100+i,Catalog.starter_deck("harvest","iron"),Catalog.foe_deck(foes[i]),"iron",foes[i])
		m.difficulty = 2
		m.ai_enabled = [true,true]
		for s: int in range(60*30): m.step(1.0/60.0)
		t.check(m.stats[1].plays > 0,"%s's AI plays its deck" % foes[i])

	# Schedule: seven minions of the right tiers with no repeats, then a boss; same seed, same run.
	var plan: Array = Catalog.schedule(42)
	t.check(plan == Catalog.schedule(42) and plan.size() == Catalog.FLOORS,"schedule is fixed by the seed")
	for f: int in range(Catalog.FLOORS-1): t.check(Catalog.MINIONS[plan[f]].tier == Catalog.FLOOR_TIER[f],"floor %d gets a tier %d minion" % [f+1,Catalog.FLOOR_TIER[f]])
	t.check(plan.slice(0,7).duplicate().all(func(k: String) -> bool: return plan.count(k) == 1),"no minion twice in one run")
	t.check(B.LORDS.has(plan[7]),"floor 8 is a normal lord")

	# Run flow with a test save file.
	var r = Rogue.new()
	r.save_path = "user://rogue-test.json"
	r.begin("vampire","vampire",42)
	t.check(r.run.is_empty(),"the 內政 and 戰鬥 lords must differ")
	r.begin("underworld","vampire",42)
	t.check(r.run.phase == "map" and r.run.floor == 0 and r.run.deck == Catalog.starter_deck("underworld","vampire"),"a run starts on floor 1 with the two lords' deck")
	var battle: Battle = r.make_battle()
	t.check(battle.lords[1].lord == plan[0] and battle.decks[1].size() == 8,"floor battle uses the scheduled minion lord")
	t.check(battle.lords[0].lord == "vampire" and battle.home_cards[0] == "grave","the 戰鬥 lord fights with its own home card")
	t.check(battle.ink[1] == Catalog.ENEMY_START_INK and battle.ink[0] == B.START_INK,"the foe opens with 10 gold, the player with the normal purse")
	# Path choice: each floor 1-7 has an elite from the next tier, never a normal foe, never twice.
	t.check(r.run.elites.size() == 7,"seven elites, one per floor before the boss")
	for i: int in range(7):
		t.check(Catalog.MINIONS[r.run.elites[i]].tier == Catalog.elite_tier(i) and not r.run.elites[i] in r.run.foes and r.run.elites.count(r.run.elites[i]) == 1,"floor %d elite is a fresh next-tier 小怪" % (i+1))
	r.set_elite(true)
	t.check(r.foe() == r.run.elites[0],"choosing the elite changes the opponent")
	var elite_battle: Battle = r.make_battle()
	t.check(elite_battle.lords[1].lord == r.run.elites[0] and elite_battle.ink[1] == Catalog.ELITE_START_INK,"the elite fights with more starting gold")
	var reloaded = Rogue.new()
	reloaded.save_path = r.save_path
	reloaded.load_progress()
	t.check(reloaded.run.elite and reloaded.foe() == r.run.elites[0],"the path choice survives a reload")
	r.set_elite(false)
	t.check(r.foe() == plan[0],"back to the normal foe")
	r.settle(true)
	t.check(r.run.phase == "reward" and r.run.floor == 1 and r.run.offer.size() == Catalog.OFFER_SIZE,"a win offers three cards")
	t.check(r.run.gold == Catalog.GOLD_BY_TIER[Catalog.FLOOR_TIER[0]],"a floor-1 win pays %d gold" % Catalog.GOLD_BY_TIER[1])
	t.check(r.win_gold(0,true) == int(Catalog.GOLD_BY_TIER[1]*Catalog.ELITE_GOLD_MULT),"an elite win pays 1.5x")
	# Gates are SS in every mode; in a run our gates and lord keep their wounds until mended in the shop.
	t.check(B.GATE_HP == B.tier_value("hp","A") and Battle.new(1).gates[0][0] == B.GATE_HP,"gates have A health in every battle")
	var wound_run = Rogue.new()
	wound_run.save_path = "user://rogue-wound-test.json"
	wound_run.begin("harvest","lion",31)
	var hurt: Battle = wound_run.make_battle()
	hurt.gates[0] = [B.GATE_HP,0.0,600.0,B.GATE_HP,B.GATE_HP]
	hurt.lords[0].hp = 700.0
	wound_run.record_wounds(hurt)
	wound_run.settle(true)
	wound_run.skip_reward()
	wound_run.leave_shop()
	var next: Battle = wound_run.make_battle()
	t.check(next.gates[0] == [B.GATE_HP,0.0,600.0,B.GATE_HP,B.GATE_HP] and next.lords[0].hp == 700.0,"gate and lord damage carry into the next battle")
	t.check(next.gates[1][1] == B.GATE_HP,"the foe's gates start whole")
	var fallen: Battle = wound_run.make_battle()
	fallen.lords[0].hp = 0.0
	wound_run.record_wounds(fallen)
	t.check(wound_run.run.lord_hp == B.lord_data("lion").hp*Catalog.FALLEN_LORD_SHARE,"a lord down at victory comes back at 25%")
	wound_run.run.lord_hp = 700.0
	wound_run.open_shop()
	wound_run.run.gold = 10
	var missing: float = wound_run.gate_missing()
	wound_run.repair_gates()
	t.check(wound_run.run.gold == 0 and is_equal_approx(wound_run.gate_missing(),missing-10*Catalog.GATE_HP_PER_GOLD),"short of gold, repairs spend what there is")
	wound_run.run.gold = 1000
	var cost: int = wound_run.repair_cost()
	wound_run.repair_gates()
	t.check(wound_run.gate_missing() == 0.0 and wound_run.run.gold == 1000-cost,"a full repair costs 1 gold per %d health" % int(Catalog.GATE_HP_PER_GOLD))
	t.check(wound_run.repair_error() == "城門完好","nothing to repair when whole")
	var heal: int = wound_run.heal_cost()
	wound_run.heal_lord()
	t.check(wound_run.run.lord_hp == B.lord_data("lion").hp and wound_run.run.gold == 1000-cost-heal,"healing the lord")
	var wound_copy = Rogue.new()
	wound_copy.save_path = wound_run.save_path
	wound_copy.load_progress()
	t.check(wound_copy.run.gates == wound_run.run.gates and wound_copy.run.lord_hp == wound_run.run.lord_hp,"wounds survive saving and loading")
	var elite_run = Rogue.new()
	elite_run.save_path = "user://rogue-elite-test.json"
	elite_run.begin("harvest","lion",21)
	elite_run.set_elite(true)
	elite_run.settle(true)
	t.check(elite_run.run.gold == elite_run.win_gold(0,true) and not elite_run.run.elite,"winning the elite pays more, and the next floor starts on the normal path")
	elite_run.run.floor = Catalog.FLOORS-1
	elite_run.run.phase = "map"
	elite_run.set_elite(true)
	t.check(not elite_run.run.elite and B.LORDS.has(elite_run.foe()),"no elite on the boss floor")
	t.check(r.run.offer.all(func(k: String) -> bool: return (B.card_allowed(k,"vampire") or B.card_allowed(k,"underworld")) and r.run.offer.count(k) == 1),"offered cards suit the lords and differ")
	var new_card: String = r.run.offer[0]
	r.pick(new_card)
	r.replace(3)
	t.check(r.run.deck[3] == new_card and r.run.phase == "shop","the picked card replaces the chosen slot, then the shop opens")
	t.check(r.run.shop.size() == 3 and r.run.shop.map(func(k: String) -> int: return Catalog.RELICS[k].price) == Catalog.RELIC_PRICES,"the shop offers one relic at each price")
	# Card upgrades: 50 / 100 / 150 gold, one random stat one tier up, at most +3, never past SS.
	r.run.deck[0] = "bandit"
	var gold_before: int = r.run.gold
	r.upgrade("bandit")
	var ups: Dictionary = r.run.upgrades.bandit
	t.check(r.run.gold == gold_before-50 and Upgrades.level(ups) == 1,"+1 costs 50 gold and raises one stat")
	r.run.gold = 1000
	r.upgrade("bandit")
	r.upgrade("bandit")
	t.check(r.run.gold == 1000-100-150 and Upgrades.level(r.run.upgrades.bandit) == 3,"+2 costs 100, +3 costs 150")
	t.check(not r.upgrade_error("bandit").is_empty(),"no +4")
	r.run.deck[1] = "sacrifice"
	t.check(r.upgrade_error("sacrifice") == "沒有可強化的能力","a card with no upgradeable stat cannot be upgraded")
	t.check(Upgrades.options("knight",{"hp":20}).find("hp") < 0,"no stat goes past SS")
	t.check(Upgrades.shifted("hp",1500.0,5) == B.TIERS.hp[Upgrades.CAP],"shifting stops at SS")
	# Upgrades reach the battle: deployed bandit carry the raised stats.
	r.leave_shop()
	var upgraded: Battle = r.make_battle()
	upgraded.units.clear()
	upgraded.deploy(0,"bandit",Vector2i(2,2))
	var raised: Dictionary = upgraded.units[0]
	var shown := 0
	for key: String in r.run.upgrades.bandit:
		var want: float = Upgrades.shifted(key,B.CARDS.bandit[key],int(r.run.upgrades.bandit[key]))
		if key == "hp": shown += int(raised.max_hp == want)
		elif key == "speed": shown += int(upgraded.movement_speed(raised) == want)
		elif key == "interval": shown += int(upgraded.attack_interval(raised) == want)
		else: shown += int(raised.get(key,-1.0) == want)
	t.check(shown == r.run.upgrades.bandit.size(),"every upgraded stat shows up in battle: "+str(r.run.upgrades.bandit))
	var text: String = r.desc("bandit")
	t.check(text.contains("強化 +3") and text != B.card_description("bandit"),"card text shows the upgraded numbers")
	var shown_hp: bool = not r.run.upgrades.bandit.has("hp") or text.contains(B.number(Upgrades.shifted("hp",B.CARDS.bandit.hp,int(r.run.upgrades.bandit.hp))))
	t.check(shown_hp,"upgraded health appears in the card text")
	upgraded.units.clear()
	upgraded.deploy(1,"bandit",Vector2i(6,2))
	t.check(upgraded.units[0].max_hp == B.CARDS.bandit.hp or not r.run.upgrades.bandit.has("hp"),"the foe's bandit are not upgraded")
	var rain_battle := Battle.new(1,[],[],"lion","bandit_chief")
	rain_battle.card_upgrades[0] = {"rain":{"radius":1}}
	t.check(Upgrades.spell_data("rain",{"radius":1}).radius == B.TIERS.radius[B.TIERS.radius.find(B.CARDS.rain.radius)-1],"a spell's upgraded radius")
	# Relics: bought with gold, stack with the 內政 passive, used in battle.
	r.open_shop()
	r.run.gold = 1000
	var shelf_before: Array = r.run.shop.duplicate()
	r.reroll()
	t.check(r.run.gold == 1000-Catalog.REROLL_PRICE and r.run.rerolls == 1 and r.run.shop.size() == shelf_before.size(),"rerolling the relics costs %d gold" % Catalog.REROLL_PRICE)
	r.run.gold = 1000
	var relic: String = r.run.shop[0]
	r.buy_relic(relic)
	t.check(relic in r.run.relics and not relic in r.run.shop and r.run.gold == 1000-Catalog.RELICS[relic].price,"buying a relic")
	r.run.relics = ["coin_purse","gold_chest"]
	var with_relics: Battle = r.make_battle()
	t.check(with_relics.ink[0] == minf(B.MAX_INK,B.START_INK+10.0) and is_equal_approx(with_relics.lord_mod(0,"income_mult",1.0),1.25),"relic effects reach the battle")
	var stacked := Catalog.merge_mods({"income_mult":1.25,"start_ink":10.0,"haste":["dark_wizard"]},{"income_mult":1.25,"start_ink":5.0,"haste":["*"]})
	t.check(is_equal_approx(stacked.income_mult,1.5625) and stacked.start_ink == 15.0 and stacked.haste.size() == 2,"relics stack with passives")
	r.leave_shop()
	var copy = Rogue.new()
	copy.save_path = r.save_path
	copy.load_progress()
	t.check(copy.run.deck == r.run.deck and copy.run.floor == 1 and copy.best == 1 and copy.run.domestic == "underworld" and copy.run.relics == r.run.relics and copy.run.upgrades == r.run.upgrades and copy.run.gold == r.run.gold,"the run survives saving and loading")
	r.settle(true)
	r.skip_reward()
	t.check(r.run.phase == "shop" and r.run.floor == 2,"a reward can be skipped")
	r.leave_shop()
	r.settle(false)
	t.check(r.run.phase == "lost" and r.best == 2,"a loss ends the run and keeps the best record")
	r.abandon()
	t.check(r.run.is_empty(),"a new run can start after the end")
	r.begin("rune","mage",7)
	r.run.floor = Catalog.FLOORS-1
	t.check(r.is_boss() and B.LORDS.has(r.foe()),"the last floor is the boss")
	r.settle(true)
	t.check(r.run.phase == "won","beating the boss wins the run")
	# Stalemates end at the time limit: more gate health wins, a tie loses.
	var stall := Battle.new(1,Catalog.starter_deck("harvest","lion"),[],"lion","bandit_chief")
	stall.elapsed = Catalog.TIME_LIMIT-1.0
	Rogue.time_limit(stall)
	t.check(not stall.ended,"no verdict before the time limit")
	stall.elapsed = Catalog.TIME_LIMIT
	stall.gates[1][2] = 100.0
	Rogue.time_limit(stall)
	t.check(stall.ended and stall.winner == 0,"at the time limit the side with more gate health wins")
	var tie := Battle.new(1,Catalog.starter_deck("harvest","lion"),[],"lion","bandit_chief")
	tie.elapsed = Catalog.TIME_LIMIT
	Rogue.time_limit(tie)
	t.check(tie.ended and tie.winner == 1,"a tie at the time limit counts as a loss")

	# Screens open without errors and battles report back.
	var game = load("res://main.tscn").instantiate()
	t.root.add_child(game)
	game.set_physics_process(false)
	game.sound_enabled = false
	game.rogue.save_path = "user://rogue-screen-test.json"
	game.rogue.abandon()
	game.show_rogue()
	t.check(game.screen == "rogue" and game.rogue.phase == "lord","roguelike opens on the lord screen")
	game.rogue.pending_domestic = "harvest"
	game.rogue.phase = "combat"
	game.show_rogue()
	game.rogue.pending_combat = "lion"
	game.rogue.phase = "confirm"
	game.show_rogue()
	game.rogue.begin("harvest","lion",11)
	game.show_rogue()
	game.queue_redraw()
	game.rogue.start_battle(game)
	t.check(game.screen == "battle" and game.rogue.in_battle and B.is_minion(game.model.lords[1].lord),"出戰 starts a battle against a minion lord")
	t.check(game.overlay_buttons().any(func(b: Array) -> bool: return b[1] == "認輸離開") and not game.overlay_buttons().any(func(b: Array) -> bool: return b[1] == "重新開始"),"no restart in a roguelike battle, only forfeit")
	game.model.ended = true
	game.model.winner = 0
	game.rogue.update(game)
	t.check(game.rogue.run.phase == "reward" and game.rogue.outcome.contains("勝利"),"winning the battle leads to the reward")
	game.rogue.leave_battle(game)
	t.check(game.screen == "rogue" and not game.rogue.in_battle,"back on the roguelike screen")
	game.rogue.pick(game.rogue.run.offer[1])
	game.show_rogue()
	game.rogue.replace(0)
	game.show_rogue()
	t.check(game.rogue.run.phase == "shop","after the reward comes the shop")
	game.rogue.leave_shop()
	game.show_rogue()
	game.rogue.start_battle(game)
	game.rogue.leave_battle(game)
	t.check(game.rogue.run.phase == "lost","leaving a running battle counts as a loss")
	game.show_title()
	game.free()
