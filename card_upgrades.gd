extends RefCounted
# 肉鴿 card upgrades (2026-11-23): each +1 adds a fixed additive percentage to a stat (no SS tier cap).
# Upgrades are per card kind ({stat: steps}) and last for one run. Only stats the battle really
# reads for that card are offered, so an upgrade always shows up in play.
const B = preload("res://balance.gd")
const MAX_LEVEL := 10
const MAX_DROP_LEVEL := MAX_LEVEL # 2026-11-22：打怪拿到的卡不再鎖 +3，連續擲骰成功就一直往上（最多到卡牌上限）
const PRICES := [50,75,100,125,150,175,200,225,250,280] # +1 .. +10
const CAP := 1 # TIER_NAMES index of SS (legacy shifted())
const NAMES := {"hp":"生命","damage":"傷害","area_damage":"範圍傷害","bolt_damage":"閃電傷害","enemy_damage":"法術傷害","explosion_damage":"爆炸傷害","tick_damage":"持續傷害","thorns":"反傷","shield":"護盾","interval":"攻速","range":"射程","speed":"移速","radius":"範圍","building_damage":"建築傷害","gate_damage":"城牆傷害","cycle":"手牌冷卻"}
const STEP_PCT := {
	"hp":0.25,"damage":0.20,"area_damage":0.20,"bolt_damage":0.20,"enemy_damage":0.20,
	"explosion_damage":0.20,"tick_damage":0.20,"building_damage":0.20,"gate_damage":0.20,
	"thorns":0.20,"shield":0.20,"interval":0.15,"speed":0.15,"range":0.15,"cycle":0.20,
}
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
		result = result.filter(func(p: Array) -> bool: return B.TIERS[p[1]].has(lead.get(p[0],-1.0)) and (p[0] != "range" or float(lead.get("range",0.0)) > 0.0))
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

# Stats that can still be upgraded (no tier cap; each stat caps at MAX_LEVEL per run).
static func options(kind: String, ups: Dictionary) -> Array:
	var result: Array = []
	for p: Array in stats(kind):
		if int(ups.get(p[0],0)) < MAX_LEVEL: result.append(p[0])
	return result

static func can_upgrade(kind: String, ups: Dictionary) -> bool:
	return level(ups) < MAX_LEVEL and not options(kind,ups).is_empty()

static func price(ups: Dictionary) -> int:
	return PRICES[clampi(level(ups),0,PRICES.size()-1)]

static func step_pct(key: String) -> float:
	return float(STEP_PCT.get(key,0.20))

static func stat_pct(key: String, steps: int) -> float:
	return maxf(0.0,float(steps))*step_pct(key)

static func scaled(key: String, base: float, steps: int) -> float:
	var pct := stat_pct(key,steps)
	if pct <= 0.0: return base
	if key == "interval": return snappedf(base/(1.0+pct),0.01)
	if key in ["range","speed"]: return roundf(base*(1.0+pct))
	return roundf(base*(1.0+pct))

static func shifted(table_name: String, value: float, steps: int, min_cap: int = CAP) -> float:
	if not B.TIERS.has(table_name): return value
	var at: int = B.TIERS[table_name].find(value)
	if at < 0 or steps <= 0 or at <= min_cap: return value
	return B.TIERS[table_name][maxi(min_cap,at-steps)]

# One spawned troop of an upgraded card (percentage bonuses stack additively with side mods).
static func apply_unit(u: Dictionary, card: String, ups: Dictionary) -> void:
	var d: Dictionary = B.CARDS[u.kind]
	for key: String in ups:
		var steps := int(ups[key])
		if steps <= 0: continue
		if key == "hp":
			u.hp_pct = float(u.get("hp_pct",0.0))+stat_pct("hp",steps)
			u.max_hp = roundf(float(u.get("base_hp",d.hp))*maxf(0.1,1.0+float(u.hp_pct)))
			u.hp = u.max_hp
		elif key in ["damage","area_damage"] and d.has(key):
			u[key] = scaled(key,float(d[key]),steps)
			u[key+"_mult"] = 1.0+stat_pct(key,steps)
		elif key == "interval" and d.has("interval"):
			u.atk_speed_pct = float(u.get("atk_speed_pct",0.0))+stat_pct("interval",steps)
		elif key == "speed" and d.has("speed"):
			u.speed_pct = float(u.get("speed_pct",0.0))+stat_pct("speed",steps)
		elif key == "range" and d.has("range"):
			u.range_pct = float(u.get("range_pct",0.0))+stat_pct("range",steps)

# A copy of a spell's data with its upgrades applied (cast_spell reads this).
static func spell_data(kind: String, ups: Dictionary) -> Dictionary:
	var d: Dictionary = B.CARDS[kind].duplicate()
	for key: String in ups:
		if key != "cycle" and d.has(key): d[key] = scaled(key,float(d[key]),int(ups[key]))
	return d

# A copy of the card table with a run's upgrades applied, for card_description() to show the real
# numbers. A legion's members all scale, the same way apply_unit() treats them in battle.
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
				if key != "cycle" and cards[kind].has(key): cards[kind][key] = scaled(key,float(B.CARDS[kind][key]),int(all_ups[card][key]))
	return cards

static func table_name_for(card: String, key: String) -> String:
	for p: Array in stats(card):
		if p[0] == key: return p[1]
	return key

static func text(ups: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in ups: parts.append("%s+%d%%" % [NAMES.get(key,key),roundi(stat_pct(key,int(ups[key]))*100.0)])
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
		var fl_add := minf(0.54, float(floor_index) * 0.09) # 2026-11-22：每層 +7% → +9%
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

# Roll bonus upgrades on a randomly offered card with cascading trials: each success rolls again at
# lower odds (p, p×0.65, p×0.5, then ×0.75 per further step), with no fixed cap below the card's limit.
# min_level is the floor's guaranteed bonus (see DROP_MIN_BY_FLOOR); the trials stack on top of it.
static func roll_drop_upgrades(kind: String, chance: float, rng: RandomNumberGenerator, min_level: int = 0) -> Dictionary:
	var lv := 0
	var p := clampf(chance, 0.0, 0.95)
	var q := p
	while lv < MAX_DROP_LEVEL and rng.randf() < q:
		lv += 1
		q = p * 0.65 if lv == 1 else (p * 0.50 if lv == 2 else q * 0.75)
	return roll_fixed_upgrades(kind, mini(lv + maxi(0, min_level), MAX_DROP_LEVEL), rng)

# 2026-11-22：獎勵卡保底強化隨層數提高（索引＝已打過的層數；精英再 +1）。
const DROP_MIN_BY_FLOOR := [0,0,0,1,1,2,2,3]
static func drop_min_level(floor_index: int, elite: bool) -> int:
	return int(DROP_MIN_BY_FLOOR[clampi(floor_index, 0, DROP_MIN_BY_FLOOR.size() - 1)]) + (1 if elite else 0)
