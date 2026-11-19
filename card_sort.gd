extends RefCounted
## Unified card & lord sorting and filtering for Deck Builder and Card Codex.
## Presentation/UI only — never modifies B.menu_sorted() or simulation RNG.
const B = preload("res://balance.gd")

const FACTION_ORDER := ["normal", "magic", "dark", "beast", ""]
const FACTION_FILTERS := [
	["all", "全陣營"],
	["normal", "經典"],
	["magic", "魔法"],
	["dark", "黑暗"],
	["beast", "魔物"],
	["neutral", "中立"],
]
const MODES := [
	["group", "預設分類"],
	["cost_asc", "費用低→高"],
	["cost_desc", "費用高→低"],
	["faction", "陣營優先"],
	["cooldown", "冷卻短→長"],
]
const GROUP_NAMES := {0: "近戰", 1: "遠程", 2: "法術", 3: "建築"}

static func mode_label(mode: String) -> String:
	for entry: Array in MODES:
		if entry[0] == mode:
			return entry[1]
	return MODES[0][1]

static func next_mode(mode: String) -> String:
	for i: int in range(MODES.size()):
		if MODES[i][0] == mode:
			return MODES[(i + 1) % MODES.size()][0]
	return MODES[0][0]

static func faction_rank(faction: String, preferred: String = "") -> int:
	if not preferred.is_empty() and faction == preferred:
		return -1
	var idx: int = FACTION_ORDER.find(faction)
	return idx if idx >= 0 else FACTION_ORDER.size()

static func effective_cost(kind: String) -> float:
	var data: Dictionary = B.CARDS[kind]
	if data.get("pay_all", false):
		return 999.0
	return float(data.cost)

static func matches_category(kind: String, category: String) -> bool:
	if not B.CARDS.has(kind):
		return false
	if category == "all":
		return true
	match category:
		"melee": return B.card_group(kind) == 0
		"ranged": return B.card_group(kind) == 1
		"spell": return B.card_group(kind) == 2
		"building": return B.card_group(kind) == 3
		"unit": return B.CARDS[kind].type == "unit"
	return B.CARDS[kind].type == category

static func matches_faction(kind: String, faction_filter: String, is_lord: bool = false) -> bool:
	if faction_filter == "all":
		return true
	if is_lord:
		if faction_filter == "neutral":
			return false
		return B.lord_faction(kind.trim_prefix("lord_")) == faction_filter
	if not B.CARDS.has(kind):
		return false
	var f: String = B.card_faction(kind)
	if faction_filter == "neutral":
		return f.is_empty()
	return f == faction_filter

static func sort_cards(kinds: Array, mode: String = "group", preferred_faction: String = "", pinned: Array = []) -> Array:
	var table_index := {}
	var idx := 0
	for k: String in B.CARDS:
		table_index[k] = idx
		idx += 1
	var pin_set := {}
	for p in pinned:
		pin_set[str(p)] = true
	var use_pin := not pin_set.is_empty()
	var result: Array = kinds.duplicate()
	result.sort_custom(func(a: String, b: String) -> bool:
		var ka := _sort_key(a, mode, preferred_faction, use_pin, pin_set, table_index)
		var kb := _sort_key(b, mode, preferred_faction, use_pin, pin_set, table_index)
		for i: int in range(ka.size()):
			if ka[i] != kb[i]:
				return ka[i] < kb[i]
		return false
	)
	return result

static func _sort_key(kind: String, mode: String, preferred_faction: String, use_pin: bool, pin_set: Dictionary, table_index: Dictionary) -> Array:
	var pin := 0 if (use_pin and pin_set.has(kind)) else 1
	var summon_rank := 1 if B.CARDS[kind].get("summon_only", false) else 0
	var group: int = B.card_group(kind)
	var cost := effective_cost(kind)
	var f_rank := faction_rank(B.card_faction(kind), preferred_faction)
	var cd := float(B.CARDS[kind].cooldown)
	var t_idx := int(table_index.get(kind, 9999))
	match mode:
		"cost_asc":
			return [pin, summon_rank, cost, group, f_rank, t_idx]
		"cost_desc":
			return [pin, summon_rank, -cost, group, f_rank, t_idx]
		"faction":
			return [pin, f_rank, summon_rank, group, cost, t_idx]
		"cooldown":
			return [pin, summon_rank, cd, cost, group, t_idx]
		_:
			return [pin, summon_rank, group, cost, f_rank, t_idx]

static func sort_lords(lords: Array, faction_filter: String = "all") -> Array:
	var order: Array = B.lord_menu_order()
	var rank := {}
	for i: int in range(order.size()):
		rank[order[i]] = i
	var result: Array = []
	for item in lords:
		var lk := str(item)
		var clean := lk.trim_prefix("lord_")
		if not B.LORDS.has(clean):
			continue
		if not matches_faction(clean, faction_filter, true):
			continue
		result.append(lk)
	result.sort_custom(func(a: String, b: String) -> bool:
		return int(rank.get(a.trim_prefix("lord_"), 999)) < int(rank.get(b.trim_prefix("lord_"), 999))
	)
	return result

static func deck_composition(deck: Array) -> Dictionary:
	var counts := {0: 0, 1: 0, 2: 0, 3: 0}
	for item in deck:
		var kind := str(item)
		if B.CARDS.has(kind):
			var g: int = B.card_group(kind)
			counts[g] = int(counts.get(g, 0)) + 1
	return counts
