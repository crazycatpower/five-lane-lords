extends RefCounted
# 肉鴿季節魔王巨獸的招牌技（使用者 2026-11-24）。一般卡也變成 2×2 巨獸之後，魔王版靠「特殊效果」拉開差距。
# A boss_only card carries "boss_trait":{"type":..., "name":..., ...}; once it has stepped out it fires every
# `period` seconds (rebirth fires once):
#   strike  the `count` nearest enemy troops or buildings within `radius` each take `damage` (落雷、齊射)
#   pulse   every enemy troop and building within `radius` takes `damage` (荊棘爆發)
#   summon  `count` × `kind` beside it in each of the lanes it straddles (屍潮、育幼、亡者合唱)
#   rally   our whole side hears a war drum: one speed and attack-speed step for 3 s (號令衝鋒)
#   rebirth the first time its health drops below `below` of max, it heals `heal` of max at once (斷頭再生)
# Hook: battle.step (update); balance.card_description (describe).
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
const Giant = preload("res://giant_unit.gd")
const GluttonNest = preload("res://glutton_nest.gd")

static func update(m, dt: float) -> void:
	var count: int = m.units.size()
	for idx: int in range(count):
		var u: Dictionary = m.units[idx]
		if u.hp <= 0 or u.get("spawn_delay",0.0) > 0 or m.frozen(u.team): continue
		var d: Dictionary = B.CARDS.get(u.kind,{})
		if not d.has("boss_trait"): continue
		var t: Dictionary = d.boss_trait
		if t.type == "rebirth":
			if not u.get("reborn",false) and u.hp <= u.max_hp*float(t.below):
				u.reborn = true
				u.hp = minf(u.max_hp,u.hp+u.max_hp*float(t.heal))
				m.event("heal",u.pos,u.team)
				m.event("roar",u.pos,u.team,{"radius":120.0})
			continue
		u.trait_cd = float(u.get("trait_cd",t.period))-dt
		if u.trait_cd > 0.0: continue
		u.trait_cd += float(t.period)
		fire(m,u,t)

static func fire(m, u: Dictionary, t: Dictionary) -> void:
	match String(t.type):
		"strike":
			var picks: Array = []
			for foe: Dictionary in targets(m,u):
				var dist := B.edge_distance(u,foe)
				if dist <= float(t.radius): picks.append([dist,foe])
			picks.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			var prev_ranged: bool = m.ranged_hit
			m.ranged_hit = true
			for i: int in range(mini(int(t.count),picks.size())):
				var foe: Dictionary = picks[i][1]
				m.link(u.pos,foe.pos,u.team,"lightning")
				m.damage(foe,float(t.damage),u.team,u.kind,u)
			m.ranged_hit = prev_ranged
		"pulse":
			var prev_ranged_p: bool = m.ranged_hit
			m.ranged_hit = true
			for foe: Dictionary in targets(m,u):
				if B.edge_distance(u,foe) <= float(t.radius): m.damage(foe,float(t.damage),u.team,u.kind,u)
			m.ranged_hit = prev_ranged_p
			m.event("roar",u.pos,u.team,{"radius":float(t.radius)})
		"summon":
			var back := -40.0 if u.team == 0 else 40.0
			for lane in Giant.lanes(u):
				if not int(lane) in m.active_lanes: continue
				for i: int in range(int(t.count)):
					var spot := Vector2(clampf(u.pos.x+back,L.GRID_ORIGIN.x+12.0,L.GRID_ORIGIN.x+L.GRID_SIZE.x-12.0),L.cell_center(Vector2i(0,int(lane))).y+(i-(int(t.count)-1)*0.5)*14.0)
					var child: Dictionary = m.spawn_unit(u.team,int(lane),String(t.kind),spot)
					child.card = u.get("card",u.kind)
					m.event("summoned",child.pos,u.team)
					m.link(u.pos,child.pos,u.team,"summon")
		"rally":
			m.trigger_drum(u)

# Living enemy troops (not hidden), enemy buildings (not traps/hidden nests), and exposed enemy lords.
static func targets(m, u: Dictionary) -> Array:
	var out: Array = []
	for foe: Dictionary in m.units:
		if foe.hp > 0 and foe.team != u.team and not foe.get("stealthed",false) and foe.get("spawn_delay",0.0) <= 0 and foe.get("phase_left",0.0) <= 0.0: out.append(foe)
	for b: Dictionary in m.buildings:
		if b.hp > 0 and b.team != u.team and not B.CARDS[b.kind].has("trap") and not GluttonNest.hidden(b): out.append(b)
	for lord: Dictionary in m.lords:
		if lord.hp > 0 and lord.team != u.team and m.lord_active[lord.team] and m.gates[lord.team][m.lord_lane(lord)] <= 0: out.append(lord)
	return out

static func describe(kind: String) -> Array[String]:
	var lines: Array[String] = []
	var d: Dictionary = B.CARDS.get(kind,{})
	if not d.has("boss_trait"): return lines
	var t: Dictionary = d.boss_trait
	var head := "魔王招牌技「%s」：" % String(t.name)
	match String(t.type):
		"strike": lines.append(head+"每 %s 秒打 %s 內最近的 %d 個敵方部隊或建築，各 %s 傷害。" % [B.number(t.period),B.number(t.radius),int(t.count),B.number(t.damage)])
		"pulse": lines.append(head+"每 %s 秒對 %s 內所有敵方部隊與建築造成 %s 傷害。" % [B.number(t.period),B.number(t.radius),B.number(t.damage)])
		"summon": lines.append(head+"每 %s 秒在牠跨的兩路各召出 %d 名%s。" % [B.number(t.period),int(t.count),B.CARDS[t.kind].name])
		"rally": lines.append(head+"每 %s 秒擊響戰鼓：全場友軍移速、攻速升一檔 3 秒。" % B.number(t.period))
		"rebirth": lines.append(head+"生命第一次掉到 %d%% 以下時，立刻回復最大生命的 %d%%。" % [roundi(float(t.below)*100.0),roundi(float(t.heal)*100.0)])
	return lines
