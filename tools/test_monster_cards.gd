extends SceneTree
# 魔物 cards (monster_cards.gd): roar, reveal, steal, thorns, plus the reused flying / farm / breath rules.
# Standalone: godot_console --headless --path . -s tools/test_monster_cards.gd

const Battle = preload("res://battle.gd")
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const MONSTERS := ["eyewing_dragon","belly_eye","fishbeak","bearded_imp","hooknose_flyer","long_dragon","thorn_dragon"]

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run_standalone")

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + msg)

func run_standalone() -> void:
	run(self)
	if failures > 0:
		printerr("TEST FAIL: %d checks, %d failures" % [checks, failures])
		quit(1)
	else:
		print("MONSTER CARDS PASS: %d checks, 0 failures" % checks)
		quit(0)

static func bare(seed_value: int = 1) -> Battle:
	var m := Battle.new(seed_value, [], [], "", "")
	m.buildings.clear()
	m.serials_in_use.clear()
	for team: int in range(2):
		for lane: int in range(5):
			m.claim_around(team, Vector2i(1 if team == 0 else 7, lane))
	return m

static func run(t) -> void:
	var y: float = L.cell_center(Vector2i(0,2)).y
	for kind: String in MONSTERS:
		t.check(B.CARDS.has(kind) and B.card_faction(kind) == "beast","monster card in the 魔物 faction: "+kind)
		t.check(ResourceLoader.exists("res://assets/manuscript-v1/%s.png" % kind),"monster art exists: "+kind)
		t.check(ResourceLoader.exists("res://assets/generated-palette/%s.png" % kind),"monster blue art prepared: "+kind)
		t.check(B.card_description(kind).split("\n").size() >= 3,"monster card explains its rule: "+kind)
	t.check(B.FACTIONS.get("beast","") == "魔物","faction name")
	t.check(not B.card_allowed("thorn_dragon","lion") and B.card_allowed("bandit","lion"),"other lords cannot take 魔物 cards")

	# 眼翼龍: the roar scares enemies within its radius only, and never its own side.
	var m := bare()
	var near := m.spawn_unit(1,2,"militia",Vector2(700,y))
	var far := m.spawn_unit(1,2,"militia",Vector2(900,y))
	var friend := m.spawn_unit(0,2,"militia",Vector2(640,y))
	m.spawn_unit(0,2,"eyewing_dragon",Vector2(620,y))
	t.check(is_equal_approx(near.get("fear_left",0.0),B.CARDS.eyewing_dragon.roar_fear),"roar scares a nearby enemy")
	t.check(far.get("fear_left",0.0) == 0.0 and friend.get("fear_left",0.0) == 0.0,"roar spares far enemies and friends")
	var x_before: float = near.pos.x
	for i: int in range(30): m.step(1.0/60.0)
	t.check(near.pos.x > x_before,"a scared blue troop runs back toward its own gate")
	# Dragon has roar_cd ticking down from 5.0s; step 4.4s more to reach 4.9s
	for i: int in range(roundi(4.4 * 60)): m.step(1.0/60.0)
	var eye: Dictionary = m.units.filter(func(u: Dictionary) -> bool: return u.kind == "eyewing_dragon")[0]
	var wave_foe := m.spawn_unit(1,2,"militia",eye.pos+Vector2(40,0))
	m.build_lookups()
	t.check(wave_foe.get("fear_left",0.0) == 0.0,"new foe not yet scared")
	# Step past the 5.0s mark (0.2s)
	for i: int in range(roundi(0.2 * 60)): m.step(1.0/60.0)
	t.check(wave_foe.get("fear_left",0.0) > 0.0,"roar triggers again after 5s period")

	# 腹眼魔: 偵查揭露範圍內所有潛行（強盜與相位騎兵），遠處不受影響，揭露後永久失去潛行。
	m = bare()
	m.spawn_unit(0,2,"belly_eye",Vector2(600,y))
	var bandit := m.spawn_unit(1,2,"bandit",Vector2(700,y))
	var far_bandit := m.spawn_unit(1,2,"bandit",Vector2(1000,y))
	var rider := m.spawn_unit(1,2,"phase_rider",Vector2(680,y))
	t.check(bandit.stealthed and far_bandit.stealthed and rider.stealthed,"units start stealthed")
	m.step(1.0/60.0)
	t.check(not bandit.stealthed,"belly eye reveals a bandit in reach")
	t.check(far_bandit.stealthed,"belly eye does not reveal far away")
	t.check(not rider.stealthed and not rider.phased,"detection reveals phase rider as well")
	# Verify permanent loss: move bandit far away and step again
	bandit.pos.x = 1000
	m.step(1.0/60.0)
	t.check(not bandit.stealthed,"stealth loss is permanent")

	# 鬍子魔: steals from buildings and gates, never below zero.
	m = bare()
	var imp := m.spawn_unit(0,2,"bearded_imp",Vector2(800,y))
	var farm := m.add_building(1,Vector2i(6,2),"farm")
	m.ink = [0.0,10.0]
	m.damage(farm,50.0,0,"bearded_imp",imp)
	t.check(is_equal_approx(m.ink[1],9.0) and is_equal_approx(m.ink[0],1.0),"hitting a building steals one gold")
	m.hit_gate(1,2,50.0,"bearded_imp",imp)
	t.check(is_equal_approx(m.ink[1],8.0) and is_equal_approx(m.ink[0],2.0),"hitting a gate steals one gold")
	m.ink = [0.0,0.0]
	m.damage(farm,50.0,0,"bearded_imp",imp)
	t.check(m.ink[0] == 0.0 and m.ink[1] == 0.0,"nothing to steal from an empty purse")
	var victim := m.spawn_unit(1,2,"militia",Vector2(820,y))
	m.ink = [0.0,10.0]
	m.damage(victim,50.0,0,"bearded_imp",imp)
	t.check(is_equal_approx(m.ink[1],10.0),"hitting troops steals nothing")

	# 骨刺龍: melee attackers take thorns; archers, lords and spells do not; no endless bounce.
	m = bare()
	var dragon := m.spawn_unit(0,2,"thorn_dragon",Vector2(700,y))
	var brute := m.spawn_unit(1,2,"militia",Vector2(740,y))
	var archer := m.spawn_unit(1,2,"hunter",Vector2(900,y))
	m.damage(dragon,50.0,1,"militia",brute)
	t.check(is_equal_approx(brute.hp,B.CARDS.militia.hp-B.CARDS.thorn_dragon.thorns),"thorns prick a melee attacker")
	m.damage(dragon,36.0,1,"hunter",archer)
	t.check(is_equal_approx(archer.hp,B.CARDS.hunter.hp),"thorns spare an archer")
	m.damage(dragon,370.0,1,"fire")
	t.check(is_equal_approx(dragon.hp,B.CARDS.thorn_dragon.hp-50.0-36.0-370.0),"spells hurt the dragon normally")
	var twin := m.spawn_unit(1,2,"thorn_dragon",Vector2(745,y))
	var twin_hp: float = twin.hp
	m.damage(dragon,130.0,1,"thorn_dragon",twin)
	t.check(is_equal_approx(twin.hp,twin_hp-B.CARDS.thorn_dragon.thorns) and dragon.hp > 0,"two thorn dragons prick once, no endless bounce")

	# 鉤鼻飛魔: melee cannot reach it; it can hit ground troops.
	m = bare()
	var flyer := m.spawn_unit(0,2,"hooknose_flyer",Vector2(700,y))
	var footman := m.spawn_unit(1,2,"militia",Vector2(730,y))
	m.build_lookups()
	t.check(m.choose_target(footman,B.CARDS.militia).is_empty(),"melee troops cannot hit the flyer")
	t.check(m.choose_target(flyer,B.CARDS.hooknose_flyer) == footman,"the flyer attacks ground troops")

	# 魚喙怪: switches lanes to hunt down the nearest enemy.
	m = bare()
	var beak := m.spawn_unit(0,2,"fishbeak",Vector2(400,y))
	var foe_far := m.spawn_unit(1,2,"militia",Vector2(750,y))
	var lane3_y: float = L.cell_center(Vector2i(0,3)).y
	var foe_near := m.spawn_unit(1,3,"militia",Vector2(420,lane3_y))
	m.build_lookups()
	t.check(m.nearest_enemy_lane(beak,B.CARDS.fishbeak) == 3,"fishbeak targets adjacent lane with closer foe")
	for i: int in range(30):
		m.step(1.0/60.0)
	t.check(beak.pos.y > y,"fishbeak moves down toward lane 3")

	# 長身龍: the breath burns every enemy in front within its reach, once each.
	m = bare()
	var wyrm := m.spawn_unit(0,2,"long_dragon",Vector2(600,y))
	var a := m.spawn_unit(1,2,"militia",Vector2(680,y))
	var b := m.spawn_unit(1,2,"militia",Vector2(730,y))
	var c := m.spawn_unit(1,2,"militia",Vector2(800,y))
	m.build_lookups()
	m.attack(wyrm,a)
	for i: int in range(30): m.update_projectiles(1.0/60.0)
	t.check(a.hp < a.max_hp and b.hp < b.max_hp,"breath burns both troops in reach")
	t.check(is_equal_approx(c.hp,c.max_hp),"breath stops at its reach")
	t.check(is_equal_approx(a.hp,a.max_hp-B.CARDS.long_dragon.damage),"each troop is burnt once")

	# All seven fight a mixed army for a while without errors.
	m = bare(7)
	for lane: int in range(5):
		var ly: float = L.cell_center(Vector2i(0,lane)).y
		m.spawn_unit(0,lane,MONSTERS[lane],Vector2(500,ly))
		m.spawn_unit(0,lane,MONSTERS[lane+2],Vector2(470,ly))
		m.spawn_unit(1,lane,["bandit","militia","knight","hunter","skeleton"][lane],Vector2(1000,ly))
	for i: int in range(60*30): m.step(1.0/60.0)
	t.check(m.units.any(func(u: Dictionary) -> bool: return u.team == 0),"monsters survive a 30 s brawl in some lane")
