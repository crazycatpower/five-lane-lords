extends RefCounted
# 肉鴿 card upgrades (2026-11-07): each +1 raises one random stat of a card one tier, never past SS.
# Upgrades are per card kind ({stat: steps}) and last for one run. Only stats the battle really
# reads for that card are offered, so an upgrade always shows up in play.
const B = preload("res://balance.gd")
const MAX_LEVEL := 10
const MAX_DROP_LEVEL := 3
const PRICES := [50,75,100,125,150,175,200,225,250,280] # +1 .. +10
const CAP := 1 # TIER_NAMES index of SS
const NAMES := {"hp":"生命","damage":"傷害","area_damage":"範圍傷害","bolt_damage":"閃電傷害","enemy_damage":"法術傷害","explosion_damage":"爆炸傷害","tick_damage":"持續傷害","thorns":"反傷","shield":"護盾","interval":"攻速","range":"射程","speed":"移速","radius":"範圍","building_damage":"建築傷害","gate_damage":"城牆傷害","cycle":"手牌冷卻"}
const BUILDING_UPGRADE_STATS := [["hp","hp"],["damage","damage"],["area_damage","area_damage"],["explosion_damage","area_damage"],["thorns","damage"],["interval","interval"]]
const SPELL_UPGRADE_STATS := [["damage","area_damage"],["building_damage","area_damage"],["gate_damage","area_damage"],["bolt_damage","damage"],["enemy_damage","area_damage"],["tick_damage","area_damage"],["shield","damage"]]

# [stat, tier table] pairs a card can be upgraded in.
static func stats(kind: String) -> Array:
	var d: Dictionary = B.CARDS[kind]
	var result: Array = []
	if d.type == "unit":
		var lead: Dictionary = B.CARDS[d.members[0][0]] if d.has("members") else d
		for key: String in ["hp","interval","range","speed"]: result.append([key,key])
		if lead.has("area_damage"): result.append(["area_damage","area_damage"])
		else: result.append(["damage","damage"])
		result = result.filter(func(p: Array) -> bool: return B.TIERS[p[1]].has(lead.get(p[0],-1.0)))
		result.append(["cycle","cycle"])
		return result
	if d.type == "building":
		for p: Array in BUILDING_UPGRADE_STATS:
			if B.TIERS[p[1]].has(d.get(p[0],-1.0)): result.append(p)
		result.append(["cycle","cycle"])
		return result
	for p: Array in SPELL_UPGRADE_STATS:
		if B.TIERS[p[1]].has(d.get(p[0],-1.0)): result.append(p)
	result.append(["cycle","cycle"])
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
		if p[1] == "cycle":
			if int(ups.get("cycle",0)) < MAX_LEVEL: result.append("cycle")
		elif B.TIERS[p[1]].find(lead_value(kind,p[0]))-int(ups.get(p[0],0)) > CAP: result.append(p[0])
	return result

static func can_upgrade(kind: String, ups: Dictionary) -> bool:
	return level(ups) < MAX_LEVEL and not options(kind,ups).is_empty()

static func price(ups: Dictionary) -> int:
	return PRICES[clampi(level(ups),0,PRICES.size()-1)]


static func shifted(table_name: String, value: float, steps: int, min_cap: int = CAP) -> float:
	if not B.TIERS.has(table_name): return value
	var at: int = B.TIERS[table_name].find(value)
	if at < 0 or steps <= 0: return value
	return B.TIERS[table_name][maxi(min_cap,at-steps)]

# One spawned troop of an upgraded card (legion members shift from their own base values).
static func apply_unit(u: Dictionary, card: String, ups: Dictionary) -> void:
	var d: Dictionary = B.CARDS[u.kind]
	for key: String in ups:
		var steps := int(ups[key])
		if key == "hp":
			u.max_hp = shifted("hp",u.max_hp,steps)
			u.hp = u.max_hp
		elif key in ["damage","area_damage","interval","range","speed"] and d.has(key):
			u[key] = shifted(table_name_for(card,key),d[key],steps)

# A copy of a spell's data with its upgrades applied (cast_spell reads this).
static func spell_data(kind: String, ups: Dictionary) -> Dictionary:
	var d: Dictionary = B.CARDS[kind].duplicate()
	for key: String in ups:
		var t: String = table_name_for(kind,key)
		if d.has(key) and B.TIERS.has(t): d[key] = shifted(t,d[key],int(ups[key]))
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

static func merge_upgrades(kind: String, current: Dictionary, bonus: Dictionary) -> Dictionary:
	var out: Dictionary = current.duplicate()
	if not B.CARDS.has(kind): return out
	for key: String in bonus:
		var add_steps := int(bonus[key])
		for _s: int in range(add_steps):
			if level(out) >= MAX_LEVEL: return out
			var opts := options(kind,out)
			if key in opts:
				out[key] = int(out.get(key,0))+1
			elif not opts.is_empty():
				var fb: String = opts[0]
				out[fb] = int(out.get(fb,0))+1
	return out

# Compute pre-upgrade drop probability (0.10 .. 0.92) & human-readable factor tags for a randomly offered card.
static func drop_chance_info(lord: String, kind: String, floor_index: int, elite: bool, contract: int, relic_count: int, has_blueprint: bool, from_event: bool, rerolls: int) -> Dictionary:
	var chance := 0.14
	var reasons: Array[String] = []
	if floor_index > 0:
		var fl_add := minf(0.42, float(floor_index) * 0.07)
		chance += fl_add
		reasons.append("層數 +%d%%" % roundi(fl_add * 100.0))
	if elite:
		chance += 0.22
		reasons.append("精英勝場 +22%")
	if contract > 0:
		var c_add := float(contract) * 0.05
		chance += c_add
		reasons.append("契約 +%d%%" % roundi(c_add * 100.0))
	if has_blueprint:
		chance += 0.14
		reasons.append("名匠鍛圖 +14%")
	if relic_count > 0:
		var r_add := minf(0.14, float(relic_count) * 0.02)
		chance += r_add
		reasons.append("遺物 +%d%%" % roundi(r_add * 100.0))
	if from_event:
		chance += 0.14
		reasons.append("酒館精銳 +14%")
	if rerolls > 0:
		var rr_add := minf(0.18, float(rerolls) * 0.08)
		chance += rr_add
		reasons.append("重抽幸運 +%d%%" % roundi(rr_add * 100.0))
	if not kind.is_empty() and B.CARDS.has(kind):
		var cdata: Dictionary = B.CARDS[kind]
		if not lord.is_empty() and B.card_faction(kind) == B.lord_faction(lord):
			chance += 0.06
		var ccost := int(cdata.get("cost", 0))
		if ccost <= 6: chance += 0.05
		elif ccost >= 14: chance -= 0.05
	return {"chance": clampf(chance, 0.10, 0.92), "reasons": reasons}

static func roll_fixed_upgrades(kind: String, levels: int, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	if not B.CARDS.has(kind) or levels <= 0: return out
	for _i: int in range(mini(levels, MAX_LEVEL)):
		var opts := options(kind, out)
		if opts.is_empty(): break
		var stat: String = opts[rng.randi_range(0, opts.size() - 1)]
		out[stat] = int(out.get(stat, 0)) + 1
	return out

# Roll +0 .. +3 bonus upgrades on a randomly offered card using cascading probability trials.
static func roll_drop_upgrades(kind: String, chance: float, rng: RandomNumberGenerator) -> Dictionary:
	var lv := 0
	var p := clampf(chance, 0.0, 0.95)
	if rng.randf() < p:
		lv += 1
		if rng.randf() < p * 0.65:
			lv += 1
			if rng.randf() < p * 0.50:
				lv += 1
	return roll_fixed_upgrades(kind, mini(lv, MAX_DROP_LEVEL), rng)
