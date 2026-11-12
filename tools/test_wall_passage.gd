extends SceneTree
const Battle = preload("res://battle.gd")
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
 if not ok:
  failures += 1
  printerr(message)
func _initialize() -> void:
 for team in range(2):
  var m := Battle.new(3,[],[],"iron","iron")
  m.buildings.clear()
  m.build_lookups()
  var foe := 1-team
  var u := m.spawn_unit(team,2,"militia",Vector2(L.gate_stop(foe),L.cell_center(Vector2i(0,2)).y))
  var before: Vector2 = u.pos
  m.gates[foe][2] = 0
  m.march(u,B.CARDS.militia,0.1)
  check(u.pos.distance_to(before) > 0,"broken wall movement starts immediately")
  check(u.get("climb",0.0) == 0,"no rubble timer")
  for i in range(60):
   if m.march(u,B.CARDS.militia,0.1): break
  check(m.ended and m.winner == team,"broken wall can be crossed")
  m = Battle.new(3,[],[],"iron","iron")
  m.buildings.clear()
  m.build_lookups()
  u = m.spawn_unit(team,2,"militia",before)
  m.gates[foe][2] = 0
  m.ink[foe] = 50
  m.skill_cd[foe] = 0
  check(m.cast_skill(foe),"wall restoration works")
  m.march(u,B.CARDS.militia,0.1)
  check(u.pos == before and not m.ended,"restored wall stops passage")
 print("WALL PASSAGE: 10 checks, ",failures," failures")
 quit(1 if failures else 0)
