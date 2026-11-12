extends SceneTree
const B = preload("res://balance.gd")
const C = preload("res://roguelike_catalog.gd")
const Battle = preload("res://battle.gd")
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
 check(B.validate().is_empty(),str(B.validate()))
 check(C.validate().is_empty(),str(C.validate()))
 var seen := {}
 for seed_value: int in range(500):
  for enemy: String in C.schedule(seed_value): seen[enemy] = true
 for enemy: String in C.MINIONS:
  var enabled: bool = C.MINIONS[enemy].get("enabled",true)
  check(seen.has(enemy) == enabled,"schedule visibility: "+enemy)
  var card: String = B.MINION_LORDS[enemy].card
  var data: Dictionary = B.CARDS[card]
  var deck: Array = C.foe_deck(enemy)
  if not enabled: continue
  if data.get("summon_only",false):
   check(deck.any(func(k: String) -> bool: return B.CARDS[k].get("summon_kind","") == card),"summon-only theme uses a summoner")
   check(not card in deck,"summon-only troop not dealt as a card")
  else: check(card in deck or B.home_card(enemy) == card,"theme card actually available: "+card)
  check(ResourceLoader.exists("res://assets/manuscript-v1/"+card+".png") or data.has("art") or card in ["militia","farmer","farm"],"portrait source: "+card)
 # Only the designated spell on the correct side gains faster cooldown, including when hands rotate.
 var enemy := "card_enemy_rain"
 var m := Battle.new(42,C.starter_deck("harvest","lion"),C.foe_deck(enemy),"lion",enemy)
 m.decks[0] = ["rain","hunter","militia","shieldguard","rain","hunter","militia","shieldguard"]
 m.decks[1] = m.decks[0].duplicate()
 m.hand_cd = [[10.0,10.0,10.0,10.0],[10.0,10.0,10.0,10.0]]
 m.tick_clocks(1.0)
 check(is_equal_approx(m.hand_cd[1][0],8.5),"signature spell cooldown runs at 1.5x")
 check(is_equal_approx(m.hand_cd[1][1],9.0),"other enemy cards unchanged")
 check(is_equal_approx(m.hand_cd[0][0],9.0),"player spell unchanged")
 m.decks[1][0] = "hunter"
 m.decks[1][1] = "rain"
 m.tick_clocks(1.0)
 check(is_equal_approx(m.hand_cd[1][0],7.5) and is_equal_approx(m.hand_cd[1][1],7.5),"bonus follows the card rather than the slot")
 var g = load("res://main.tscn").instantiate()
 root.add_child(g)
 g.set_physics_process(false)
 for enemy_id: String in C.MINIONS:
  check(g.lord_art(enemy_id,0) != null and g.lord_art(enemy_id,1) != null,"both portrait palettes: "+enemy_id)
 g.free()
 print("CARD ENEMIES: %d checks, %d failures; %d cards / %d enemy definitions" % [checks,failures,B.CARDS.size(),C.MINIONS.size()])
 quit(1 if failures else 0)
