extends "res://tools/quick_test.gd"
# Presentation regression: event conversion must leave simulation data and RNG alone.
func run() -> void:
	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	g.set_process(false)
	g.set_physics_process(false)
	g.sound_enabled = false
	g.sound = null
	check(not g.team_material("sacrifice",Vector2(0.5,0.5),Color.RED),"ritual blood stays red")
	check(not g.team_material("blood_tower",Vector2(0.5,0.35),Color.RED),"reservoir stays red")
	check(g.team_material("blood_tower",Vector2(0.5,0.75),Color.RED),"tower banners use team colour")
	for team: int in [0,1]:
		g.model = bare(77)
		g.model.ai_enabled = [false,false]
		g.effects.clear()
		var p := L.cell_center(Vector2i(2 if team == 0 else 6,2))
		for i: int in range(5): g.model.spawn_unit(1-team,2,"knight",p+Vector2(i*45,0))
		g.model.cast_spell({"kind":"chain_lightning","pos":p,"team":team})
		var rng_state: int = g.model.rng.state
		var original: Array = g.model.events.duplicate(true)
		g.consume_events()
		var bolts: Array = g.effects.filter(func(e: Dictionary) -> bool: return e.kind == "link" and e.style == "lightning")
		check(bolts.size() == 5,"five visible lightning hops")
		for i: int in range(bolts.size()):
			check(bolts[i].hop == i and is_equal_approx(bolts[i].life,0.3),"ordered thinning lightning, 0.3 seconds")
		check(not original[1].has("hop"),"visual metadata is not written into battle events")
		check(g.model.rng.state == rng_state,"presentation leaves RNG untouched")
		g.effects.clear()
		g.model.spawn_unit(team,2,"militia",p)
		g.model.cast_spell({"kind":"sacrifice","pos":p,"team":team})
		# A blood-tower relation can share the cast location but must still feed the tower.
		g.model.link(p+Vector2(20,0),p,team,"devour")
		g.consume_events()
		var purse: Vector2 = preload("res://economy_hud.gd").PURSE.get_center() if team == 0 else Vector2(1322,35)
		check(g.effects.any(func(e: Dictionary) -> bool: return e.kind == "link" and e.get("to",Vector2.ZERO) == purse),"sacrifice red light reaches correct purse")
		check(g.effects.any(func(e: Dictionary) -> bool: return e.kind == "link" and e.get("to",Vector2.ZERO) == p),"blood-tower links keep their building destination")
		g.effects.clear()
		g.model.units.clear()
		g.model.spawn_unit(1-team,2,"knight",p)
		g.model.cast_spell({"kind":"levy","pos":p,"team":team})
		g.consume_events()
		check(g.effects.any(func(e: Dictionary) -> bool: return e.kind == "levy_summon"),"levy uses horn halo")
		var militia: Dictionary = g.model.units.filter(func(u: Dictionary) -> bool: return u.get("levy",false))[0]
		militia.pos = L.cell_center(Vector2i(7 if team == 0 else 1,2))
		g.model.units.erase(militia)
		g.effects.clear()
		g.consume_events()
		check(g.effects.any(func(e: Dictionary) -> bool: return e.kind == "levy_dust"),"departing levy becomes dust")
		g.fx_enabled = false
		g.effects.clear()
		g.model.event("spell",p,team,{"card":"sacrifice","radius":100.0})
		g.consume_events()
		check(g.effects.is_empty(),"disabled effects add no particles")
		g.fx_enabled = true
	g.free()
	print("Faction visuals: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
