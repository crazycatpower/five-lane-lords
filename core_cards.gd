extends RefCounted
# Faction core payoffs (2026-11-18): cards whose strength grows with the archetype around them.
#   咒潮法師 (magic): every spell our side casts adds a tide stack (max spell_stacks). Stacks 1-3 raise its
#     damage one tier each, stacks 4-5 its attack speed. Stacks last until it dies.
#   荊棘母獸 (beast): allies within radius prick melee attackers. Allies that already have thorns get them
#     two tiers higher; allies without get thorns_aura. Her own thorns are on her card.
# Hooks: battle.play (on_card_played), monster_cards.on_hit (thorns), balance.card_description (describe).
const B = preload("res://balance.gd")

static func on_card_played(m, team: int, kind: String) -> void:
	if B.CARDS[kind].type != "spell": return
	for u: Dictionary in m.units:
		if u.hp <= 0 or u.team != team or not B.CARDS[u.kind].has("spell_stacks"): continue
		var d: Dictionary = B.CARDS[u.kind]
		var stacks: int = int(u.get("tide",0))
		if stacks >= int(d.spell_stacks): continue
		stacks += 1
		u.tide = stacks
		if stacks <= 3: u.damage = faster_or_stronger("damage",float(u.get("damage",d.damage)))
		else: u.interval = faster_or_stronger("interval",float(u.get("interval",d.interval)))
		m.link(u.pos,u.pos,team,"mana")

# One tier stronger (damage) or faster (interval), never past S. Both tables list the strongest first.
static func faster_or_stronger(stat: String, value: float) -> float:
	var at: int = B.TIERS[stat].find(value)
	if at < 0:
		return roundf(value*1.35) if stat == "damage" else (snappedf(value/1.3,0.01) if stat == "interval" else value)
	return B.TIERS[stat][maxi(B.tier_index("S"),at-1)]

# 荊棘母獸 aura, read by monster_cards.on_hit for the troop or building that was hit.
static func thorns(m, target: Dictionary, base: float) -> float:
	if not m.has_thorns_aura[target.team]: return base
	for u: Dictionary in m.units:
		if u.hp <= 0 or u.team != target.team or not u.get("has_thorns_aura",false) or u.get("spawn_delay",0.0) > 0: continue
		var d: Dictionary = B.CARDS[u.kind]
		if not d.has("thorns_aura") or edge(u,target) > float(d.radius): continue
		if is_same(u,target): return base
		if base > 0.0:
			var at: int = B.TIERS.damage.find(base)
			return B.TIERS.damage[maxi(B.tier_index("S"),at-2)] if at >= 0 else base*2.0
		return float(d.thorns_aura)
	return base

static func edge(a: Dictionary, b: Dictionary) -> float:
	return maxf(0.0,a.pos.distance_to(b.pos)-float(a.get("body_radius",12.0))-float(b.get("body_radius",12.0)))

static func describe(kind: String) -> Array[String]:
	var lines: Array[String] = []
	var d: Dictionary = B.CARDS[kind]
	if d.has("spell_stacks"):
		lines.append("我方每施放一張法術，獲得 1 層咒潮（最多 %d 層，直到陣亡）：第 1–3 層傷害各升一檔，第 4–5 層攻速各升一檔，最高 S。" % int(d.spell_stacks))
	if d.has("thorns_aura"):
		lines.append("半徑 %s 內的友軍被近戰打中時也會反刺：本來有反傷的升兩檔，沒有的得到 %s 反傷；她本身反傷 %s。" % [B.number(d.radius),B.number(d.thorns_aura),B.number(d.thorns)])
	return lines
