extends SceneTree
const R = preload("res://roguelike.gd")
const C = preload("res://roguelike_catalog.gd")
const B = preload("res://balance.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  printerr(message)
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var r = R.new()
 r.save_path = "user://rogue-resilience-test.json"
 r.begin("harvest","lion",42)
 var lords: Array = B.LORDS.keys()
 for i: int in range(lords.size()):
  var domestic: String = lords[i]
  var combat: String = lords[(i+1)%lords.size()]
  var deck := C.starter_deck(domestic,combat)
  var offer := C.offer(domestic,combat,42,0,deck)
  check(offer == C.offer(domestic,combat,42,0,deck),"seeded rewards")
  var groups := {}
  for k: String in offer:
   check(not k in deck and k in C.card_pool(domestic,combat),"fresh legal reward")
   groups[B.card_group(k)] = true
  check(groups.size() == 3,"different roles")
 var good: Dictionary = r.run.duplicate(true)
 for change: Dictionary in [{"floor":"bad"},{"floor":1.5},{"seed":null},{"foes":["bad"]},{"deck":["bad"]},{"phase":"replace","floor":1,"offer":["rain","fire","hunter"],"pick":"glutton_nest"}]:
  var bad := good.duplicate(true)
  bad.merge(change,true)
  check(not r.valid_run(bad),"reject malformed run")
 var invalid_foes := good.duplicate(true)
 invalid_foes.foes[0] = "unknown_foe"
 check(not r.valid_run(invalid_foes),"reject nonexistent foe")
 r.pick("rain")
 r.replace(-1)
 check(r.run == good,"wrong phase actions do nothing")
 r.settle(true)
 var won: Dictionary = r.run.duplicate(true)
 r.settle(true)
 check(r.run == won,"duplicate settlement does not skip a floor")
 r.pick("glutton_nest")
 check(r.run.phase == "reward","cannot pick outside offer")
 r.pick(r.run.offer[0])
 r.replace(9)
 check(r.run.phase == "replace","invalid slot is ignored")
 var loaded = R.new()
 loaded.save_path = r.save_path
 loaded.load_progress()
 check(loaded.run == r.run,"replacement selection survives reload")
 var f := FileAccess.open(r.save_path,FileAccess.WRITE)
 f.store_string('{"broken":')
 f.close()
 loaded.load_progress()
 check(loaded.run.phase == "reward" and loaded.save_notice.contains("備份"),"corrupt primary recovers previous valid checkpoint")
 var failed = R.new()
 failed.save_path = "user://missing-rogue-directory/save.json"
 failed.begin("harvest","lion",42)
 check(not failed.save_notice.is_empty() and not failed.run.is_empty(),"save failure retains in-memory run with warning")
 print("ROGUE IMPROVEMENTS: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)

