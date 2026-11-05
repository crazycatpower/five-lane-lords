extends "res://tools/quick_test.gd"

const Lord = preload("res://lord.gd")

func run() -> void:
	var expected := {"iron":3000.0,"lion":1500.0,"adventure":1500.0,"vampire":1500.0,"rune":900.0,"mage":900.0,"underworld":900.0,"harvest":900.0}
	check(B.validate().is_empty(), "balance validates")
	check(expected.size() == B.LORDS.size(), "every lord covered")
	for kind: String in expected:
		var m := Battle.new(1, [], [], kind, kind)
		for side: int in range(2):
			var lord: Dictionary = m.lords[side]
			check(lord.hp == expected[kind] and lord.max_hp == expected[kind], "spawn health: " + kind)
			lord.hp = 0.0
			lord.respawn = 0.01
			Lord.step(m, lord, 0.02)
			check(lord.hp == expected[kind], "respawn health: " + kind)
	print("Lord health: %s checks, %s failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
