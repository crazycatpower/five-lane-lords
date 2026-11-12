extends SceneTree
const Lord = preload("res://lord.gd")
const Battle = preload("res://battle.gd")
const L = preload("res://layout.gd")
var failed := false
func check(ok: bool, message: String) -> void:
 if not ok:
  failed = true
  printerr(message)
func _initialize() -> void:
 for team: int in range(2):
  var m := Battle.new()
  var lord: Dictionary = m.lords[team]
  var forward := 1.0 if team == 0 else -1.0
  check((lord.pos.x-L.gate_icon_x(team))*forward < 0,"spawn behind gate")
  var foe := m.spawn_unit(1-team,2,"militia",Vector2(L.gate_stop(team),lord.pos.y))
  var hp: float = foe.hp
  Lord.step(m,lord,0.1)
  check(foe.hp < hp,"can defend against gate attacker")
  for i in range(30): Lord.step(m,lord,0.1)
  check((lord.pos.x-L.gate_icon_x(team))*forward < 0,"pursuit stays behind gate")
  m.gates[team][2] = 0
  foe.hp = 100
  foe.pos.x = L.gate_icon_x(team)+forward*10
  lord.cd = 0
  Lord.step(m,lord,0.1)
  check(foe.hp < 100,"intercepts breached gate")
  lord.hp = 0
  lord.respawn = 0
  Lord.step(m,lord,0.1)
  check(lord.pos == Lord.home(team),"respawn behind gate")
 print("GATE LORD CHECKS: ","FAIL" if failed else "PASS (10)")
 quit(1 if failed else 0)
