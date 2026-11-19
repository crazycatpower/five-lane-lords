extends RefCounted
# 結界護衛 (producer 2026-11-19): magic squads were pure backline and fell to one 獸群號角.
# A ward_guard marches in front of the mages and takes a share of the damage its nearby allies
# suffer ("ward_share" within "ward_radius"). Wards and 奧術魔像 are "construct": 工匠 repair them,
# so a guarded line with an artificer behind it keeps standing.
const B = preload("res://balance.gd")

# Living wards per team, rebuilt with the other lookups each step.
static func collect(u: Dictionary, wards: Array) -> void:
	if B.CARDS.get(u.kind,{}).has("ward_share"): wards[u.team].append(u)

static func repairable(u: Dictionary) -> bool:
	return B.CARDS.get(u.kind,{}).get("construct",false)

# Called from battle.damage() after armour and shields: returns what the target itself still takes.
static func share(m, target: Dictionary, amount: float, team: int, kind: String, source: Dictionary) -> float:
	if m.wards[target.team].is_empty() or target.has("cell") or target.kind == "lord" or repairable(target): return amount
	var best: Dictionary = {}
	var best_d := INF
	for w: Dictionary in m.wards[target.team]:
		if w.hp <= 0 or w.get("spawn_delay",0.0) > 0: continue
		var d: float = B.edge_distance(w,target)
		if d <= float(B.CARDS[w.kind].ward_radius) and d < best_d:
			best = w
			best_d = d
	if best.is_empty(): return amount
	var moved: float = amount*float(B.CARDS[best.kind].ward_share)
	m.damage(best,moved,team,kind,source)
	if moved >= 20.0: m.link(target.pos,best.pos,target.team,"mana")
	return amount-moved
