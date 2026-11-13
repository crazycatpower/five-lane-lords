extends "res://tools/quick_test.gd"
# docs/2026-11-13素材擴充設計.md — merchant mercenaries, blood thralls and gunpowder, both teams.
const X = preload("res://expansion_more.gd")
const A = preload("res://arcane_mechanics.gd")
const E = preload("res://expansion_cards.gd")

func fresh():
	var m = bare(91)
	m.ai_enabled = [false,false]
	m.lord_active = [false,false]
	m.units.clear()
	m.build_lookups()
	return m

func run() -> void:
	check(B.validate().is_empty(),"card validation: "+str(B.validate()))
	for kind: String in ["mule_cart","hook_collector","twin_gambler","gatebreaker","disgraced_lancer","runaway_thrall","renegade_artificer","oathless_imp","assassin","vampire_hunter","monster_hunter","spellbreaker","powder_barrel"]:
		check(B.card_faction(kind) == "","merchant cards are neutral: "+kind)
	for side: int in [0,1]:
		var fw := 1.0 if side == 0 else -1.0
		var tag := " (team %d)" % side
		var p := L.cell_center(Vector2i(4,2))
		# 騾馬貨車
		var m = fresh()
		var cart: Dictionary = m.spawn_unit(side,2,"mule_cart",L.spawn_position(side,2))
		m.ink[side] = 0
		for i: int in range(60*40): m.update_unit(cart,1.0/60.0)
		check(m.ink[side] >= B.CARDS.mule_cart.shuttle_income,"cart pays on returning home"+tag)
		m.ink[1-side] = 0
		m.damage(cart,cart.hp,1-side,"militia")
		m.resolve_deaths()
		check(m.ink[1-side] == B.CARDS.mule_cart.shuttle_loot,"a killed cart pays the enemy"+tag)
		# 鉤鐮收債人 bounty, 雙刃賭徒 roll, 破門錘手 x3
		m = fresh()
		var hook: Dictionary = m.spawn_unit(side,2,"hook_collector",p)
		var prey: Dictionary = m.spawn_unit(1-side,2,"skeleton",p+Vector2(20*fw,0))
		m.ink[side] = 0
		m.damage(prey,prey.hp,side,"hook_collector",hook)
		check(m.ink[side] == B.CARDS.hook_collector.kill_income,"kill pays a bounty"+tag)
		var gambler: Dictionary = m.spawn_unit(side,2,"twin_gambler",p)
		var dummy: Dictionary = m.spawn_unit(1-side,2,"knight",p)
		var rolls: Array = []
		for i: int in range(20): rolls.append(X.modify_attack(m,gambler,dummy,0.0))
		check(rolls.all(func(v: float) -> bool: return v >= B.tier_value("damage","E") and v <= B.tier_value("damage","A")) and rolls.min() != rolls.max(),"gambler damage rolls between E and A"+tag)
		var breaker: Dictionary = m.spawn_unit(side,2,"gatebreaker",p)
		var farm: Dictionary = m.add_building(1-side,Vector2i(5 if side == 0 else 3,2),"farm")
		check(X.modify_attack(m,breaker,farm,70.0) == 210.0 and X.gate_amount(m,breaker,70.0) == 210.0 and X.modify_attack(m,breaker,dummy,70.0) == 70.0,"gatebreaker x3 on buildings and gates only"+tag)
		# bonus_vs and spell resistance
		var vh: Dictionary = m.spawn_unit(side,2,"vampire_hunter",p)
		var skel: Dictionary = m.spawn_unit(1-side,2,"skeleton",p)
		check(X.modify_attack(m,vh,skel,50.0) == 100.0 and X.modify_attack(m,vh,dummy,50.0) == 50.0,"vampire hunter x2 against dark only"+tag)
		var assassin: Dictionary = m.spawn_unit(side,2,"assassin",p)
		check(X.modify_attack(m,assassin,m.lords[1-side],95.0) == 285.0,"assassin x3 against lords"+tag)
		var sb: Dictionary = m.spawn_unit(side,2,"spellbreaker",p)
		m.damage(sb,100.0,1-side,"rain")
		check(sb.hp == sb.max_hp-50.0,"spellbreaker halves spell damage"+tag)
		m.damage(sb,100.0,1-side,"militia")
		check(sb.hp == sb.max_hp-150.0,"but not troop damage"+tag)
		# lifesteal, last stand
		var att: Dictionary = m.spawn_unit(side,2,"blood_attendant",p)
		att.hp = 100.0
		m.damage(dummy,100.0,side,"blood_attendant",att)
		check(is_equal_approx(att.hp,130.0),"lifesteal 30%"+tag)
		var imp: Dictionary = m.spawn_unit(side,2,"oathless_imp",p)
		m.damage(imp,9999.0,1-side,"militia")
		check(imp.hp == 1.0,"oathless imp survives the first lethal hit"+tag)
		m.damage(imp,10.0,1-side,"militia")
		check(imp.hp <= 0,"but only once"+tag)
		# 縫屍匠, 殯儀小屋
		m = fresh()
		var stitcher: Dictionary = m.spawn_unit(side,2,"corpse_stitcher",p)
		var cottage: Dictionary = m.add_building(side,Vector2i(3 if side == 0 else 5,2),"funeral_cottage")
		var friend: Dictionary = m.spawn_unit(side,2,"militia",p+Vector2(30*fw,0))
		var foe: Dictionary = m.spawn_unit(1-side,2,"militia",p+Vector2(40*fw,0))
		m.ink[side] = 0
		m.damage(foe,foe.hp,side,"militia")
		m.resolve_deaths()
		check(m.ink[side] == 0,"funeral cottage ignores enemy deaths"+tag)
		var before: int = m.units.filter(func(u: Dictionary) -> bool: return u.kind == "skeleton" and u.team == side).size()
		m.damage(friend,friend.hp,1-side,"militia")
		m.resolve_deaths()
		check(m.ink[side] == 1.0,"funeral cottage pays for our dead"+tag)
		check(m.units.filter(func(u: Dictionary) -> bool: return u.kind == "skeleton" and u.team == side).size() == before+1,"stitcher sews a skeleton from an ally"+tag)
		# 喪鐘侍女, 不眠鐘樓, 血誓祭壇
		m = fresh()
		var maid: Dictionary = m.spawn_unit(side,2,"mourning_maid",p)
		var walker: Dictionary = m.spawn_unit(1-side,2,"militia",p+Vector2(60*fw,0))
		E.update(m,B.CARDS.mourning_maid.period+0.05)
		check(walker.get("slow_left",0.0) > 0,"maid's bell slows enemies"+tag)
		var belfry: Dictionary = m.add_building(side,Vector2i(4,2),"sleepless_belfry")
		var stunned: Dictionary = m.spawn_unit(side,2,"militia",belfry.pos)
		stunned.stun_left = 9.0
		stunned.root_left = 9.0
		E.update(m,B.CARDS.sleepless_belfry.period+0.05)
		check(stunned.stun_left == 0.0 and stunned.root_left == 0.0,"belfry wakes allies"+tag)
		m = fresh()
		var altar: Dictionary = m.add_building(side,Vector2i(4,2),"blood_altar")
		var donors: Array = []
		for i: int in range(4): donors.append(m.spawn_unit(side,2,"knight",altar.pos+Vector2(i*5,0)))
		m.ink[side] = 0
		E.update(m,B.CARDS.blood_altar.period+0.05)
		check(m.ink[side] == B.CARDS.blood_altar.tithe_max and donors.filter(func(u: Dictionary) -> bool: return u.hp < u.max_hp).size() == B.CARDS.blood_altar.tithe_max,"altar tithes at most three allies for gold"+tag)
		# spells
		m = fresh()
		m.cast_spell({"kind":"borrowed_bones","pos":p,"team":side})
		var bones: Array = m.units.filter(func(u: Dictionary) -> bool: return u.card == "borrowed_bones")
		check(bones.size() == B.CARDS.borrowed_bones.summon_count,"borrowed bones rise"+tag)
		m.step(B.CARDS.borrowed_bones.summon_life+0.1)
		check(m.units.filter(func(u: Dictionary) -> bool: return u.get("card","") == "borrowed_bones").is_empty(),"and return to the coffin"+tag)
		m = fresh()
		m.decks[side][0] = "grave_exchange"
		m.hand_cd[side][0] = 0
		m.ink[side] = 20
		check(not m.can_play(side,0,p),"grave exchange needs a building"+tag)
		var tower: Dictionary = m.add_building(side,Vector2i(4,2),"tower")
		check(m.can_play(side,0,p),"grave exchange with a building"+tag)
		m.ink[side] = 0
		m.cast_spell({"kind":"grave_exchange","pos":p,"team":side})
		check(tower.hp <= 0 and m.ink[side] == roundf(B.CARDS.tower.cost*0.5) and m.units.filter(func(u: Dictionary) -> bool: return u.kind == "skeleton").size() == 2,"grave exchange refunds half and raises two skeletons"+tag)
		m = fresh()
		var ward: Dictionary = m.spawn_unit(side,2,"militia",p)
		m.cast_spell({"kind":"mourning_shroud","pos":p,"team":side})
		m.damage(ward,9999.0,1-side,"knight")
		check(ward.hp == 1.0,"shroud saves once"+tag)
		var rooted: Dictionary = m.spawn_unit(1-side,2,"militia",p)
		m.cast_spell({"kind":"sealed_coffin","pos":p,"team":side})
		check(m.movement_speed(rooted) == 0.0,"sealed coffin roots enemies"+tag)
		# gunpowder
		m = fresh()
		var gren: Dictionary = m.spawn_unit(side,2,"funeral_grenadier",p)
		var t1: Dictionary = m.spawn_unit(1-side,2,"knight",p+Vector2(150*fw,0))
		m.attack(gren,t1)
		check(m.projectiles.size() == 1 and m.projectiles[0].has("impact") and t1.hp == t1.max_hp,"grenadier lobs; damage lands later"+tag)
		m.update_projectiles(1.0)
		check(t1.hp == t1.max_hp-B.CARDS.funeral_grenadier.area_damage,"lob hits at the landing point"+tag)
		var bomb: Dictionary = m.spawn_unit(side,2,"imp_bomb_runner",p)
		var t2: Dictionary = m.spawn_unit(1-side,2,"knight",p+Vector2(30*fw,0))
		m.attack(bomb,t2)
		check(bomb.hp <= 0 and t2.hp == t2.max_hp-B.CARDS.imp_bomb_runner.area_damage,"bomb runner blows up on its first target"+tag)
		m = fresh()
		var barrel: Dictionary = m.add_building(side,Vector2i(4,2),"powder_barrel")
		var stepper: Dictionary = m.spawn_unit(1-side,2,"knight",barrel.pos)
		A.update_traps(m)
		check(stepper.hp == stepper.max_hp-B.CARDS.powder_barrel.explosion_damage and barrel.hp <= 0,"powder barrel explodes once"+tag)
	# AI casts the new spells into a crowd.
	var m = fresh()
	m.decks[1] = ["sealed_coffin","harvest","harvest","harvest","harvest","harvest","harvest","harvest"]
	m.hand_cd[1] = [0.0,99.0,99.0,99.0]
	m.farm_cd[1] = 999.0
	m.ink[1] = 30
	m.elapsed = 30
	for i: int in range(4): m.spawn_unit(0,2,"militia",L.cell_center(Vector2i(4,2))+Vector2(i*15,0))
	check(m.AI.decide(m.snapshot(1)).get("kind","") == "sealed_coffin","AI seals a crowd")
	print("Expansion more: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
