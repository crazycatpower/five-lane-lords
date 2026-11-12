extends "res://tools/quick_test.gd"
# docs/三陣營各補四張.md — mechanics of the new faction cards, both teams.
const F = preload("res://faction_cards.gd")

func fresh():
	var m = bare(77)
	m.ai_enabled = [false,false]
	m.lord_active = [false,false]
	m.record_events = false
	return m

func run() -> void:
	check(B.validate().is_empty(),"card validation: "+str(B.validate()))
	for side: int in [0,1]:
		var forward := 1.0 if side == 0 else -1.0
		var p := L.cell_center(Vector2i(4,2))
		var tag := " (team %d)" % side
		# --- 法力湧泉 ---
		var m = fresh()
		m.decks[side][0] = "mana_spring"
		m.hand_cd[side][0] = 0
		m.ink[side] = 20
		check(not m.can_play(side,0,p),"mana spring needs a crystal in range"+tag)
		var crystal: Dictionary = m.add_building(side,Vector2i(4,2),"crystal")
		crystal.hp = crystal.max_hp*0.5
		var far: Dictionary = m.add_building(side,Vector2i(4,0),"crystal")
		far.hp = far.max_hp*0.5
		check(m.can_play(side,0,p),"mana spring with a crystal in range"+tag)
		m.ink[side] = 10
		m.cast_spell({"kind":"mana_spring","pos":p,"team":side})
		check(is_equal_approx(m.ink[side],10+B.CARDS.crystal.income),"one crystal payout"+tag)
		check(crystal.hp == crystal.max_hp and is_equal_approx(far.hp,far.max_hp*0.5),"refills crystals in range only"+tag)
		# --- 連鎖閃電 ---
		m = fresh()
		var a: Dictionary = m.spawn_unit(1-side,2,"knight",p)
		var b: Dictionary = m.spawn_unit(1-side,2,"knight",p+Vector2(60*forward,0))
		var c: Dictionary = m.spawn_unit(1-side,2,"knight",p+Vector2(120*forward,0))
		var lone: Dictionary = m.spawn_unit(1-side,2,"knight",p+Vector2(400*forward,0))
		var friend: Dictionary = m.spawn_unit(side,2,"knight",p+Vector2(30*forward,0))
		m.cast_spell({"kind":"chain_lightning","pos":p,"team":side})
		check(a.max_hp-a.hp == B.tier_value("damage","SS"),"first bolt SS"+tag)
		check(b.max_hp-b.hp == B.tier_value("damage","S"),"second bolt one tier lower"+tag)
		check(c.max_hp-c.hp == B.tier_value("damage","A"),"third bolt A"+tag)
		check(lone.hp == lone.max_hp and friend.hp == friend.max_hp,"stops when nothing is in hop reach; never hits allies"+tag)
		m = fresh()
		var swarm: Array = []
		for i: int in range(7): swarm.append(m.spawn_unit(1-side,2,"skeleton",p+Vector2(i*30*forward,0)))
		m.cast_spell({"kind":"chain_lightning","pos":p,"team":side})
		check(swarm.filter(func(u: Dictionary) -> bool: return u.hp < u.max_hp).size() == 5,"at most 1+4 targets"+tag)
		m = fresh()
		var chain_unit: Dictionary = m.spawn_unit(1-side,2,"knight",p)
		var b_cell := Vector2i(5,2) if side == 0 else Vector2i(3,2)
		var chain_bld: Dictionary = m.add_building(1-side,b_cell,"tower")
		m.cast_spell({"kind":"chain_lightning","pos":p,"team":side})
		check(chain_unit.hp < chain_unit.max_hp and chain_bld.hp < chain_bld.max_hp,"chain lightning hops to enemy building"+tag)
		# --- 奧術護盾 ---
		m = fresh()
		var ally: Dictionary = m.spawn_unit(side,2,"militia",p)
		var out: Dictionary = m.spawn_unit(side,2,"militia",p+Vector2(300*forward,0))
		m.cast_spell({"kind":"arcane_shield","pos":p,"team":side})
		var shield: float = B.CARDS.arcane_shield.shield
		m.damage(ally,shield-30,1-side,"militia")
		check(ally.hp == ally.max_hp,"shield absorbs first"+tag)
		m.damage(ally,50,1-side,"militia")
		check(ally.hp == ally.max_hp-20,"overflow reaches hp"+tag)
		m.damage(out,10,1-side,"militia")
		check(out.hp == out.max_hp-10,"no shield outside the radius"+tag)
		m.cast_spell({"kind":"arcane_shield","pos":p,"team":side})
		m.cast_spell({"kind":"arcane_shield","pos":p,"team":side})
		check(ally.shield == shield*2,"spent shield, then two recasts stack"+tag)
		m.elapsed += B.CARDS.arcane_shield.duration+0.1
		var before: float = ally.hp
		m.damage(ally,10,1-side,"militia")
		check(ally.hp == before-10,"shield expires"+tag)
		# --- 時空力場 ---
		m = fresh()
		var slowed: Dictionary = m.spawn_unit(1-side,2,"militia",p)
		var own: Dictionary = m.spawn_unit(side,2,"militia",p)
		var base_speed: float = m.movement_speed(slowed)
		var base_interval: float = m.attack_interval(slowed)
		m.cast_spell({"kind":"time_field","pos":p,"team":side})
		check(is_equal_approx(m.movement_speed(slowed),base_speed*0.5) and is_equal_approx(m.attack_interval(slowed),base_interval*2.0),"enemies in the field: half speed, 2.0x interval"+tag)
		check(is_equal_approx(m.movement_speed(own),B.CARDS.militia.speed),"own troops unaffected"+tag)
		var tf_cell := Vector2i(4,2)
		var foe_tw: Dictionary = m.add_building(1-side,tf_cell,"tower")
		foe_tw.cd = 1.0
		m.step(0.4)
		check(is_equal_approx(foe_tw.cd,0.8),"enemy building in time_field cools down at half rate"+tag)
		m.step(B.CARDS.time_field.duration)
		check(m.fields.is_empty(),"field ends after its duration"+tag)
		# --- 衝鋒號令 ---
		m = fresh()
		var runner: Dictionary = m.spawn_unit(side,2,"militia",p)
		var other_lane: Dictionary = m.spawn_unit(side,1,"militia",L.cell_center(Vector2i(4,1)))
		m.cast_spell({"kind":"charge_horn","pos":p,"team":side})
		check(m.movement_speed(runner) == B.tier_value("speed","C") and m.movement_speed(other_lane) == B.CARDS.militia.speed,"horn: one speed tier in its lane only"+tag)
		m.elapsed += B.CARDS.charge_horn.duration+0.1
		m.step(0.01)
		check(m.movement_speed(runner) == B.CARDS.militia.speed,"horn wears off"+tag)
		# --- 緊急徵召 ---
		m = fresh()
		var home := L.cell_center(Vector2i(1 if side == 0 else 7,2))
		m.decks[side][0] = "levy"
		m.hand_cd[side][0] = 0
		m.ink[side] = 20
		check(not m.can_play(side,0,home),"levy needs intruders"+tag)
		var raiders: Array = []
		for i: int in range(3): raiders.append(m.spawn_unit(1-side,2,"militia",home+Vector2(i*12*forward,0)))
		var outside: Dictionary = m.spawn_unit(1-side,2,"militia",L.cell_center(Vector2i(4,2)))
		check(m.can_play(side,0,home),"levy with intruders"+tag)
		var before_units: int = m.units.size()
		m.cast_spell({"kind":"levy","pos":home,"team":side})
		var levies: Array = m.units.filter(func(u: Dictionary) -> bool: return u.get("levy",false))
		check(levies.size() == 3 and m.units.size() == before_units+3,"one militia per intruder"+tag)
		check(m.movement_speed(levies[0]) == B.tier_value("speed","C") and m.attack_interval(levies[0]) == B.tier_value("interval","B"),"levy militia: one speed and attack-speed tier"+tag)
		check(levies.all(func(u: Dictionary) -> bool: return u.team == side and (u.pos.x-home.x)*forward <= 12*2),"levies stand on our side of the intruders"+tag)
		levies[0].pos = L.cell_center(Vector2i(5 if side == 0 else 3,2))
		m.step(0.01)
		check(not levies[0] in m.units and levies[1] in m.units,"levy outside our territory vanishes"+tag)
		# --- 投網獵人 ---
		m = fresh()
		var net: Dictionary = m.spawn_unit(side,2,"net_hunter",p)
		var prey: Dictionary = m.spawn_unit(1-side,2,"knight",p+Vector2(60*forward,0))
		var bird: Dictionary = m.spawn_unit(1-side,2,"raven",p+Vector2(60*forward,0))
		m.damage(prey,10,side,"net_hunter",net)
		m.damage(bird,1,side,"net_hunter",net)
		check(prey.get("slow_left",0.0) == B.CARDS.net_hunter.net_slow and is_equal_approx(m.movement_speed(prey),B.CARDS.knight.speed*0.5) and is_equal_approx(m.attack_interval(prey),B.CARDS.knight.interval*2.0),"net halves speed and attack speed"+tag)
		check(bird.get("slow_left",0.0) == 0.0,"flying units ignore nets"+tag)
		# --- 瞭望塔 ---
		m = fresh()
		var tower: Dictionary = m.add_building(side,Vector2i(3 if side == 0 else 5,2),"watchtower")
		var sneak: Dictionary = m.spawn_unit(1-side,2,"bandit",tower.pos+Vector2(100*forward,0))
		var archer: Dictionary = m.spawn_unit(side,2,"hunter",tower.pos)
		var far_archer: Dictionary = m.spawn_unit(side,0,"hunter",L.cell_center(Vector2i(8 if side == 0 else 0,0))) # beyond the reach
		m.step(0.01)
		check(not sneak.stealthed,"watchtower reveals stealth"+tag)
		check(F.unit_data(m,archer,B.CARDS.hunter).range == B.tier_value("range","SS") and F.unit_data(m,far_archer,B.CARDS.hunter).range == B.CARDS.hunter.range,"shooters in reach: one range tier"+tag)
		# --- 獻祭 ---
		m = fresh()
		var giant: Dictionary = m.spawn_unit(side,2,"corpse_giant",p)
		for i: int in range(2): m.spawn_unit(side,2,"skeleton",p+Vector2(i*10,0))
		var safe_enemy: Dictionary = m.spawn_unit(1-side,2,"militia",p)
		m.ink[side] = 0
		m.cast_spell({"kind":"sacrifice","pos":p,"team":side})
		m.resolve_deaths()
		check(m.ink[side] == 3*B.CARDS.sacrifice.gold_per_unit,"2 gold per sacrificed troop"+tag)
		check(safe_enemy.hp == safe_enemy.max_hp,"enemies untouched"+tag)
		check(m.units.filter(func(u: Dictionary) -> bool: return u.team == side and u.hp > 0 and u.kind == "skeleton").size() == roundi(1.0/B.CARDS.corpse_giant.burst_step)*B.CARDS.corpse_giant.burst_count,"death effects still happen (the giant bursts on its way down)"+tag)
		# --- 恐懼嚎叫 ---
		m = fresh()
		var scared: Dictionary = m.spawn_unit(1-side,2,"knight",p)
		var calm: Dictionary = m.spawn_unit(1-side,2,"knight",p+Vector2(400*forward,0))
		m.cast_spell({"kind":"dread_howl","pos":p,"team":side})
		var x0: float = scared.pos.x
		m.update_unit(scared,1.0)
		check((scared.pos.x-x0)*forward > 0 and scared.fear_left > 0,"feared troops walk back toward their own gate"+tag)
		check(calm.get("fear_left",0.0) == 0.0,"outside the radius: no fear"+tag)
		m.update_unit(scared,B.CARDS.dread_howl.duration)
		check(scared.fear_left == 0.0,"fear lasts its duration"+tag)
		check(scared.face == (1.0 if scared.team == 0 else -1.0),"after fear the troop faces the enemy again"+tag)
		# --- 亂葬坑 ---
		m = fresh()
		var pit: Dictionary = m.add_building(side,Vector2i(2 if side == 0 else 6,2),"mass_grave")
		var count0: int = m.units.size()
		m.update_buildings(B.CARDS.mass_grave.period-1)
		check(m.units.size() == count0,"pit waits for its period"+tag)
		var victim: Dictionary = m.spawn_unit(1-side,2,"militia",p)
		m.damage(victim,victim.hp,side,"militia")
		m.resolve_deaths()
		check(m.units.filter(func(u: Dictionary) -> bool: return u.kind == "skeleton" and u.team == side).size() == B.CARDS.mass_grave.spawn_count,"a death advances the pit and it raises skeletons"+tag)
		check(pit.production == 0.0,"extra time is not kept"+tag)
		# --- 鮮血塔 ---
		m = fresh()
		var bt: Dictionary = m.add_building(side,Vector2i(2 if side == 0 else 6,2),"blood_tower")
		var wounded: Dictionary = m.spawn_unit(side,2,"knight",p)
		wounded.hp = 100
		m.update_buildings(5.0)
		check(wounded.hp == 100 and is_equal_approx(bt.blood,25.0),"stores 5/s and does not heal below the restart level"+tag)
		var dead: Dictionary = m.spawn_unit(1-side,2,"militia",p)
		m.damage(dead,dead.hp,side,"militia")
		m.resolve_deaths()
		check(is_equal_approx(bt.blood,75.0),"+50 per death in the lane"+tag)
		m.update_buildings(1.0)
		check(is_equal_approx(wounded.hp,100.0+B.CARDS.blood_tower.heal_rate),"heals at configured rate once above 50"+tag)
		m.update_buildings(10.0)
		check(not bt.bleeding and bt.blood < B.CARDS.blood_tower.restart_at,"runs dry and stops"+tag)
		var hp_dry: float = wounded.hp
		m.update_buildings(3.0)
		check(wounded.hp == hp_dry,"must refill past 50 before healing again"+tag)
	# All buffs stack (producer 2026-11-05).
	var sm = fresh()
	var farm: Dictionary = sm.add_building(0,Vector2i(1,2),"farm")
	check(sm.farm_speed(farm) == 1.0,"plain farm x1")
	farm.boost_until = sm.elapsed+10
	farm.harvest_until = sm.elapsed+10
	check(sm.farm_speed(farm) == 4.0,"farmer and harvest multiply")
	sm.add_building(0,Vector2i(2,2),"mill")
	sm.add_building(0,Vector2i(3,2),"mill")
	check(sm.farm_speed(farm) == 4.0*B.MILL_BONUS*B.MILL_BONUS,"every mill in the lane multiplies too")
	sm = fresh()
	var trooper: Dictionary = sm.spawn_unit(0,2,"militia",L.cell_center(Vector2i(3,2)))
	sm.cast_spell({"kind":"charge_horn","pos":trooper.pos,"team":0})
	check(sm.movement_speed(trooper) == B.tier_value("speed","C") and sm.attack_interval(trooper) == B.tier_value("interval","B"),"horn: speed and attack speed one tier")
	sm.cast_spell({"kind":"charge_horn","pos":trooper.pos,"team":0})
	var drummer: Dictionary = sm.spawn_unit(0,0,"drummer",L.cell_center(Vector2i(1,0)))
	check(sm.movement_speed(trooper) == B.tier_value("speed","A") and sm.attack_interval(trooper) == B.tier_value("interval","S"),"two horns and a drum: three tiers")
	sm.spawn_unit(0,1,"drummer",L.cell_center(Vector2i(1,1)))
	check(sm.movement_speed(trooper) == B.tier_value("speed","S"),"a second drum adds another tier, capped at S")
	check(B.tier_value("damage","G") == 20.0,"damage tier G is 20")
	for kind: String in ["healer","drummer"]:
		check(B.CARDS[kind].damage == B.tier_value("damage","F") and B.CARDS[kind].damage*2 >= B.tier_value("hp","G"),"%s hits at F: two hits kill the weakest troop" % kind)
	# Area spells can land on a grid crossing and catch a 2x2 block (two lanes at once).
	var sp = fresh()
	sp.decks[1] = ["rain","harvest","harvest","harvest","harvest","harvest","harvest","harvest"]
	sp.hand_cd[1] = [0.0,99.0,99.0,99.0]
	sp.farm_cd[1] = 999.0
	sp.ink[1] = 40
	sp.elapsed = 30
	var cross: Vector2 = L.GRID_ORIGIN+Vector2(4*L.CELL_SIZE.x,2*L.CELL_SIZE.y)
	for off: Vector2 in [Vector2(-40,-35),Vector2(40,-35),Vector2(-40,35),Vector2(40,35)]:
		sp.spawn_unit(0,1 if off.y < 0 else 2,"knight",cross+off)
	var snap: Dictionary = sp.snapshot(1)
	check(snap.candidates.any(func(c: Dictionary) -> bool: return c.kind == "rain" and c.get("corner",false)),"area spells get grid-crossing candidates")
	var choice: Dictionary = sp.AI.decide(snap)
	check(choice.get("kind","") == "rain" and choice.pos.distance_to(cross+Vector2(B.AI_SPELL_LEAD,0)) < 1.0,"AI leads the selected crossing by the fixed distance: "+str(choice))
	# 腐屍巨人 bursts 4 skeletons each time it loses 25% of its hp; 亡者大軍 is cheap and fast.
	var gm = fresh()
	var giant: Dictionary = gm.spawn_unit(0,2,"corpse_giant",L.cell_center(Vector2i(4,2)))
	var skel_count := func() -> int: return gm.units.filter(func(u: Dictionary) -> bool: return u.kind == "skeleton").size()
	gm.damage(giant,giant.max_hp*0.2,1,"militia")
	check(skel_count.call() == 0,"giant: nothing before 25% lost")
	gm.damage(giant,giant.max_hp*0.05,1,"militia")
	check(skel_count.call() == 4,"giant: 25% lost bursts 4")
	gm.damage(giant,giant.max_hp*0.3,1,"militia")
	check(skel_count.call() == 8,"giant: 50% lost bursts another 4")
	check(B.skill_cooldown("underworld") < B.SKILL_COOLDOWN,"亡者大軍: shorter cooldown than the shared one")
	check(B.skill_cooldown("lion") == B.SKILL_COOLDOWN,"other lords keep the shared cooldown")
	# AI uses the spells when they pay off.
	var m = fresh()
	m.decks[1][0] = "chain_lightning"
	m.hand_cd[1][0] = 0
	m.ink[1] = 30
	m.elapsed = 30
	for i: int in range(4): m.spawn_unit(0,2,"militia",L.cell_center(Vector2i(4,2))+Vector2(i*20,0))
	var pick: Dictionary = m.AI.decide(m.snapshot(1))
	check(pick.get("kind","") == "chain_lightning","AI throws chain lightning into a group: "+str(pick))
	print("Faction cards: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
