extends "res://tools/quick_test.gd"
const Lead = preload("res://spell_lead.gd")

func run() -> void:
	check(load("res://game.gd") != null,"game parses")
	for side: int in [0,1]:
		var p := L.cell_center(Vector2i(4,2))
		var direction := 1.0 if side == 0 else -1.0
		for kind: String in ["rain","plague","curse","chain_lightning","dread_howl","time_field"]:
			check(Lead.position(kind,p,side) == p-Vector2(direction*24,0),"enemy lead: "+kind)
		for kind: String in ["arcane_shield","charge_horn"]:
			check(Lead.position(kind,p,side) == p+Vector2(direction*24,0),"friendly lead: "+kind)
		for kind: String in ["fire","harvest","mana_spring","sacrifice","levy","rolling_boulder","hunter","blood_tower"]:
			check(Lead.position(kind,p,side) == p,"fixed aim: "+kind)
		check(Lead.position("rain",L.GRID_ORIGIN,side).x >= L.GRID_ORIGIN.x,"lead stays in board")
		var m := bare()
		var tower: Dictionary = m.add_building(side,Vector2i(4,2),"blood_tower")
		tower.blood = 100.0
		var a: Dictionary = m.spawn_unit(side,2,"knight",p)
		var b: Dictionary = m.spawn_unit(side,2,"knight",p+Vector2(90,0))
		var delayed: Dictionary = m.spawn_unit(side,2,"knight",p)
		a.hp = 100.0
		b.hp = 100.0
		delayed.hp = 100.0
		delayed.spawn_delay = 2.0
		m.events.clear()
		m.update_buildings(1.0)
		check(a.hp == 125 and b.hp == 125,"50 healing per second shared")
		check(delayed.hp == 100,"unspawned units excluded")
		check(tower.blood == 55,"healing consumes stored blood")
		check(m.events.filter(func(e): return e.kind == "blood_transfer").size() == 2,"healing links emitted")
		m.events.clear()
		m.update_buildings(0.1)
		check(m.events.is_empty(),"links throttled")
		m.record_events = false
		m.update_buildings(1.0)
		check(a.hp > 127.5 and m.events.is_empty(),"headless healing works without events")
		m.update_buildings(1.0)
		check(not tower.bleeding,"empty tower stops")
		var hp: float = a.hp
		m.update_buildings(1.0)
		check(a.hp == hp,"empty tower must recharge")
	print("Blood tower / spell lead: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
