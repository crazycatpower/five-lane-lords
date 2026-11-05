extends "res://tools/quick_test.gd"
const Windup = preload("res://attack_windup.gd")
func run() -> void:
	check(load("res://game.gd") != null,"game parses")
	var durations: Array[float] = []
	for side: int in [0,1]:
		var forward := 1.0 if side == 0 else -1.0
		for kind: String in B.CARDS:
			var data: Dictionary = B.CARDS[kind]
			if data.type != "unit" or not data.has("hp"): continue
			var m = bare(120)
			m.ai_enabled = [false,false]
			var target: Dictionary = m.add_building(1-side,Vector2i(4,2),"farm")
			var distance: float = 150 if kind == "catapult" else 20
			var u: Dictionary = m.spawn_unit(side,2,kind,target.pos-Vector2(distance*forward,0))
			m.build_lookups()
			m.update_unit(u,0.001)
			check(u.has("attack_windup") and u.cd == 0,"windup starts before attack: "+kind)
			if not u.has("attack_windup"): continue
			var duration: float = u.attack_windup.duration
			check(duration >= 0.05 and duration <= 0.2,"duration range: "+kind)
			var hp: float = target.hp
			m.update_unit(u,0.025)
			check(target.hp == hp and u.cd == 0,"no premature damage: "+kind)
			m.update_unit(u,0.2)
			check(u.cd > 0 and not u.has("attack_windup"),"attack releases after windup: "+kind)
		var m = bare(3)
		var u: Dictionary = m.spawn_unit(side,2,"militia",L.cell_center(Vector2i(4,2)))
		for i: int in range(30):
			u.cd = 0
			check(not Windup.ready(m,u,"same",0.01),"new attack waits")
			durations.append(u.attack_windup.duration)
			check(Windup.ready(m,u,"same",0.2),"windup releases")
		var target: Dictionary = m.spawn_unit(1-side,2,"knight",u.pos+Vector2(20*forward,0))
		m.build_lookups()
		u.cd = 0
		m.update_unit(u,0.01)
		target.hp = 0
		m.build_lookups()
		m.update_unit(u,0.01)
		check(not u.has("attack_windup"),"dead target cancels windup")
		target.hp = target.max_hp
		m.build_lookups()
		m.update_unit(u,0.01)
		u.stun_left = 1
		m.update_unit(u,0.1)
		check(not u.has("attack_windup"),"stun cancels windup")
		u.stun_left = 0
		m.units.clear()
		m.units.append(u)
		m.build_lookups()
		u.pos = Vector2(L.gate_stop(1-side),L.cell_center(Vector2i(0,2)).y)
		u.cd = 0
		var gate_hp: float = m.gates[1-side][2]
		m.update_unit(u,0.01)
		check(m.gates[1-side][2] == gate_hp and u.has("attack_windup"),"gate attack winds up")
		m.update_unit(u,0.2)
		check(m.gates[1-side][2] < gate_hp,"gate attack releases")
		check(not m.lords[side].has("attack_windup"),"lords excluded")
	check(durations.min() != durations.max(),"random per swing, not a fixed delay")
	print("Attack windup: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
