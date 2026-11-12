extends SceneTree
const B = preload("res://balance.gd")
const Battle = preload("res://battle.gd")
const Nest = preload("res://glutton_nest.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	check(B.validate().is_empty(),str(B.validate()))
	for pair: Array in [[0,0],[99,0],[100,1],[219,1],[220,2],[359,2],[360,3],[520,4],[700,5],[900,6],[1120,7]]:
		check(Nest.gold_for_health(pair[0]) == pair[1],"gold threshold %s" % pair[0])
	for lord: String in B.LORDS: check(not B.card_allowed("glutton_nest",lord),"unreleased for "+lord)
	check(not "glutton_nest" in preload("res://deck_store.gd").pool(),"excluded from unrestricted random pool")
	check("glutton_nest" in preload("res://card_library.gd").new(null).entries(),"visible in codex")
	for team: int in range(2):
		var m := Battle.new(1,[],[],"","")
		m.buildings.clear()
		m.record_events = false
		m.ink[team] = 0.0
		var b := m.add_building(team,Vector2i(3,2),"glutton_nest")
		m.build_lookups()
		check(Nest.hidden(b),"starts hidden")
		check(not b in m.lane_foe_buildings[1-team][2],"not targetable while hidden")
		m.damage(b,9999,1-team,"rain")
		check(b.hp == b.max_hp,"hidden immune to area damage")
		var ally := m.spawn_unit(team,2,"militia",b.pos)
		var foe := m.spawn_unit(1-team,2,"dark_wizard",b.pos+Vector2(50,0))
		ally.hp = 100.0
		foe.hp = 120.0
		foe.shield = 500.0
		var far := m.spawn_unit(1-team,2,"militia",b.pos+Vector2(90,0))
		var flying := m.spawn_unit(1-team,2,"hooknose_flyer",b.pos)
		var delayed := m.spawn_unit(1-team,2,"militia",b.pos)
		delayed.spawn_delay = 1.0
		var phased := m.spawn_unit(1-team,2,"phase_rider",b.pos)
		phased.phased = true
		Nest.update(m,b,0.1)
		check(ally.hp <= 0 and foe.hp <= 0,"both teams consumed; bypass shields/rescue")
		check(far.hp > 0 and flying.hp > 0 and delayed.hp > 0 and phased.hp > 0,"outside and ineligible survive")
		check(m.ink[team] == 2,"220 current HP yields 2 gold without visual events")
		check(b in m.lane_foe_buildings[1-team][2],"exposed nest targetable immediately")
		m.damage(b,100,1-team,"militia")
		check(b.hp == b.max_hp-100,"digesting nest takes damage")
		m.resolve_deaths()
		m.remove_dead()
		var next := m.spawn_unit(1-team,2,"militia",b.pos)
		next.hp = 100.0
		Nest.update(m,b,14.9)
		check(next.hp > 0,"no eating during digestion")
		Nest.update(m,b,0.2)
		check(Nest.hidden(b),"rearms after 15 seconds")
		Nest.update(m,b,0.1)
		check(next.hp <= 0 and m.ink[team] == 3,"second cycle produces once")
		m.damage(b,9999,1-team,"militia")
		var gold: float = m.ink[team]
		Nest.update(m,b,30)
		check(b.hp <= 0 and m.ink[team] == gold,"destroyed nest never rearms")
	print("GLUTTON NEST: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
