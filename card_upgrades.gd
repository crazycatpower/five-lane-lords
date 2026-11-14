extends RefCounted
# 肉鴿 card upgrades (2026-11-07): each +1 raises one random stat of a card one tier, never past SS.
# Upgrades are per card kind ({stat: steps}) and last for one run. Only stats the battle really
# reads for that card are offered, so an upgrade always shows up in play.
const B = preload("res://balance.gd")
const MAX_LEVEL := 3
const PRICES := [50,100,150] # +1, +2, +3
const CAP := 1 # TIER_NAMES index of SS
const NAMES := {"hp":"生命","damage":"傷害","interval":"攻速","range":"射程","speed":"移速","radius":"範圍","building_damage":"建築傷害","gate_damage":"城牆傷害"}
const DAMAGE_SPELLS := ["rain","fire"] # spells cast_spell reads damage from
const RADIUS_SPELLS := ["rain","fire","harvest","plague","curse"] # spells cast_spell reads radius from

# [stat, tier table] pairs a card can be upgraded in.
static func stats(kind: String) -> Array:
	var d: Dictionary = B.CARDS[kind]
	var result: Array = []
	if d.type == "unit":
		var lead: Dictionary = B.CARDS[d.members[0][0]] if d.has("members") else d
		for key: String in ["hp","interval","range","speed"]: result.append([key,key])
		if not lead.has("area_damage"): result.append(["damage","damage"])
		return result.filter(func(p: Array) -> bool: return B.TIERS[p[1]].has(lead.get(p[0],-1.0)))
	if d.type == "building": return [["hp","hp"]] if B.TIERS.hp.has(d.hp) else []
	if kind in RADIUS_SPELLS and B.TIERS.radius.has(d.radius): result.append(["radius","radius"])
	if kind in DAMAGE_SPELLS:
		for key: String in ["damage","building_damage","gate_damage"]:
			if B.TIERS.area_damage.has(d.get(key,-1.0)): result.append([key,"area_damage"])
	return result

static func level(ups: Dictionary) -> int:
	var total := 0
	for key: String in ups: total += int(ups[key])
	return total

static func lead_value(kind: String, key: String) -> float:
	var d: Dictionary = B.CARDS[kind]
	return (B.CARDS[d.members[0][0]] if d.has("members") else d).get(key,-1.0)

# Stats that can still go one tier up without passing SS.
static func options(kind: String, ups: Dictionary) -> Array:
	var result: Array = []
	for p: Array in stats(kind):
		if B.TIERS[p[1]].find(lead_value(kind,p[0]))-int(ups.get(p[0],0)) > CAP: result.append(p[0])
	return result

static func can_upgrade(kind: String, ups: Dictionary) -> bool:
	return level(ups) < MAX_LEVEL and not options(kind,ups).is_empty()

static func price(ups: Dictionary) -> int:
	return PRICES[mini(level(ups),MAX_LEVEL-1)]


static func shifted(table_name: String, value: float, steps: int) -> float:
	var at: int = B.TIERS[table_name].find(value)
	if at < 0 or steps <= 0: return value
	return B.TIERS[table_name][maxi(CAP,at-steps)]

# One spawned troop of an upgraded card (legion members shift from their own base values).
static func apply_unit(u: Dictionary, card: String, ups: Dictionary) -> void:
	var d: Dictionary = B.CARDS[u.kind]
	for key: String in ups:
		var steps := int(ups[key])
		if key == "hp":
			u.max_hp = shifted("hp",u.max_hp,steps)
			u.hp = u.max_hp
		elif key in ["damage","interval","range","speed"] and d.has(key):
			u[key] = shifted(table_name_for(card,key),d[key],steps)

# A copy of a spell's data with its upgrades applied (cast_spell reads this).
static func spell_data(kind: String, ups: Dictionary) -> Dictionary:
	var d: Dictionary = B.CARDS[kind].duplicate()
	for key: String in ups:
		if d.has(key): d[key] = shifted(table_name_for(kind,key),d[key],int(ups[key]))
	return d

# A copy of the card table with a run's upgrades applied, for card_description() to show the real
# numbers. A legion's members all shift, the same way apply_unit() treats them in battle.
static func table(all_ups: Dictionary) -> Dictionary:
	var cards: Dictionary = B.CARDS.duplicate(true)
	for card: String in all_ups:
		if not cards.has(card): continue
		var d: Dictionary = B.CARDS[card]
		if d.type == "spell":
			cards[card] = spell_data(card,all_ups[card])
			continue
		var kinds: Array = d.members.map(func(g: Array) -> String: return g[0]) if d.has("members") else [card]
		for kind: String in kinds:
			for key: String in all_ups[card]:
				var t: String = table_name_for(card,key)
				if cards[kind].has(key) and B.TIERS.has(t): cards[kind][key] = shifted(t,B.CARDS[kind][key],int(all_ups[card][key]))
	return cards

static func table_name_for(card: String, key: String) -> String:
	for p: Array in stats(card):
		if p[0] == key: return p[1]
	return key

static func text(ups: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in ups: parts.append("%s+%d" % [NAMES.get(key,key),int(ups[key])])
	return " ".join(parts)
