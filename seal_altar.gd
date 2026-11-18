extends RefCounted
# 封印祭壇 → 瘟疫主教 (2026-11-18): the dark faction's payoff for its death engines.
# One altar per side. Every troop that dies (either side) feeds it souls: soul_lane in the altar's own
# lane, soul_other elsewhere. Each seal that breaks makes nearby foes flee for seal_fear seconds; the
# last one shatters the altar and the heretic bishop walks out with his hooded funeral monks.
# The bishop's bell (support "slow"), the monks' healing (support "heal") and his arrival roar
# (roar_fear) reuse the existing data-driven rules; only the rotting trail lives here.
# Hooks: battle.resolve_deaths (on_death), battle.step (update), battle.play_check (is_duplicate),
# game.gd building overlays (draw_bar).
const B = preload("res://balance.gd")

# Battle setup, right after the shuffle: "no_opening" cards leave the four opening slots for the
# back of the draw queue, in their shuffled order. Uses no random numbers, so other decks are unchanged.
static func keep_out_of_opening(deck: Array) -> void:
	var held: Array = []
	for i: int in range(mini(4,deck.size())-1,-1,-1):
		if B.CARDS.get(deck[i],{}).get("no_opening",false): held.push_front(deck.pop_at(i))
	deck.append_array(held)

static func is_duplicate(m, team: int, kind: String, cell: Vector2i) -> bool:
	if not B.CARDS.get(kind,{}).get("unique",false): return false
	for b: Dictionary in m.buildings:
		if b.hp > 0 and b.team == team and b.kind == kind and b.cell != cell: return true
	return false

static func on_death(m, dead: Dictionary) -> void:
	var d: Dictionary = B.CARDS.seal_altar
	var count: int = m.buildings.size()
	for i: int in range(count):
		var b: Dictionary = m.buildings[i]
		if b.hp <= 0 or b.kind != "seal_altar": continue
		var before: float = b.get("souls",0.0)
		b.souls = before+(float(d.soul_lane) if b.cell.y == dead.lane else float(d.soul_other))
		m.link(dead.pos,b.pos,b.team,"soul")
		var seals: Array = d.seals
		for s: int in range(seals.size()):
			if before < float(seals[s]) and b.souls >= float(seals[s]):
				if s == seals.size()-1:
					release(m,b)
					break
				seal_break(m,b,s)

# enemy_ai: raise the altar early, at the back of the busiest lane (own-lane deaths count double);
# top up an existing one only when it is badly hurt. -INF = leave it to the normal rules.
static func ai_score(c: Dictionary, s: Dictionary, team: int, col: int) -> float:
	if c.kind != "seal_altar": return -INF
	for b: Dictionary in s.buildings:
		if b.team == team and b.kind == "seal_altar" and b.hp > 0:
			return 720.0 if b.cell == c.cell and b.hp < b.max_hp*0.4 else -INF
	var busy := 0
	for u: Dictionary in s.units:
		if u.hp > 0 and u.lane == c.cell.y: busy += 1
	return 760.0-col*40.0+busy*4.0

static func seals_broken(b: Dictionary) -> int:
	var n := 0
	for t in B.CARDS.seal_altar.seals:
		if b.get("souls",0.0) >= float(t): n += 1
	return n

# Gap between two bodies (centre distance minus both body radii); local so this file needs no newer helpers.
static func edge(a: Dictionary, b: Dictionary) -> float:
	return maxf(0.0,a.pos.distance_to(b.pos)-float(a.get("body_radius",20.0))-float(b.get("body_radius",12.0)))

static func seal_break(m, b: Dictionary, index: int) -> void:
	var d: Dictionary = B.CARDS.seal_altar
	for u: Dictionary in m.units:
		if u.hp > 0 and u.team != b.team and edge(b,u) <= d.radius:
			u.fear_left = maxf(u.get("fear_left",0.0),d.seal_fear)
	m.event("roar",b.pos,b.team,{"radius":d.radius,"seal":index+1})

# The last seal: the altar shatters and the bishop leads his procession out of it.
static func release(m, b: Dictionary) -> void:
	var d: Dictionary = B.CARDS.seal_altar
	b.hp = 0
	m.refresh_territory()
	var forward := 1.0 if b.team == 0 else -1.0
	var bishop: Dictionary = m.spawn_unit(b.team,b.cell.y,d.summon,b.pos)
	bishop.card = "seal_altar"
	var escort: Array = d.escort
	for i: int in range(int(escort[1])):
		var row := (i % 2)*2-1
		var monk: Dictionary = m.spawn_unit(b.team,b.cell.y,escort[0],b.pos-Vector2(forward*(26.0+14.0*int(i/2)),row*12.0))
		monk.card = "seal_altar"
		monk.spawn_delay = 0.12*(i+1)
	m.event("summoned",b.pos,b.team)
	m.event("boneburst",b.pos,b.team) # not "breach": that one means a broken wall (hitstop, warhorn, lane flash)

# 瘟疫主教: the ground rots behind him (a small plague cloud every rot_period seconds).
static func update(m, dt: float) -> void:
	for u: Dictionary in m.units:
		if u.hp <= 0 or u.kind != "plague_bishop" or u.get("spawn_delay",0.0) > 0: continue
		var d: Dictionary = B.CARDS.plague_bishop
		u.rot_clock = u.get("rot_clock",0.0)+dt
		while u.rot_clock >= d.rot_period:
			u.rot_clock -= d.rot_period
			m.add_zone(u.pos,u.team,d.rot_radius,d.rot_duration)

static func draw_bar(g, b: Dictionary) -> void:
	if b.kind != "seal_altar": return
	var seals: Array = B.CARDS.seal_altar.seals
	var top: float = float(seals[-1])
	var r := Rect2(b.pos+Vector2(-30,36),Vector2(60,5))
	g.bar(r,b.get("souls",0.0),top,Color("c9c1dc"))
	for t in seals:
		var x: float = r.position.x+r.size.x*float(t)/top
		g.draw_line(Vector2(x,r.position.y-2),Vector2(x,r.end.y+2),Color("6e3030"),1.5)

static func describe(kind: String) -> Array[String]:
	var lines: Array[String] = []
	if kind == "seal_altar":
		var d: Dictionary = B.CARDS.seal_altar
		var bishop: Dictionary = B.CARDS[d.summon]
		lines.append("不會出現在起手牌；每方只能有一座。本路每死 1 名部隊（敵我皆算）得 %s 魂，其他路得 %s 魂。" % [B.number(d.soul_lane),B.number(d.soul_other)])
		lines.append("%s 魂時封印依序碎裂，每破一道使半徑 %s 內敵兵恐懼 %s 秒；集滿 %s 魂祭壇碎裂，召喚%s與 %d 名%s。祭壇被拆則靈魂散去。" % ["／".join(d.seals.map(func(x) -> String: return str(x))),B.number(d.radius),B.number(d.seal_fear),str(d.seals[-1]),bishop.name,int(d.escort[1]),B.CARDS[d.escort[0]].name])
	elif kind == "plague_bishop":
		var p: Dictionary = B.CARDS.plague_bishop
		lines.append("出場時半徑 %s 內敵兵恐懼 %s 秒；鐘聲隨行。" % [B.number(p.radius),B.number(p.roar_fear)])
		lines.append("所經之處土地腐敗：每 %s 秒在腳下留下半徑 %s、持續 %s 秒的毒霧。" % [B.number(p.rot_period),B.number(p.rot_radius),B.number(p.rot_duration)])
	return lines
