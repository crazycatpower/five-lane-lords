extends RefCounted
const B = preload("res://balance.gd")
# A deck is 8 unique rotating cards (the lord's home card is always in its own slot) plus a chosen
# lord. With a lord, every card must also be open to that lord's faction (B.card_allowed).
static func valid(deck: Array, lord: String = "", allow_duplicates: bool = false) -> bool:
	if deck.size() != 8 or deck.any(func(k) -> bool: return B.is_home_card(str(k),lord)): return false
	var unique := {}
	for kind in deck:
		if not kind is String or not B.CARDS.has(kind) or B.CARDS[kind].get("summon_only",false) or B.CARDS[kind].get("boss_only",false) or B.CARDS[kind].get("unreleased",false) or (unique.has(kind) and not allow_duplicates): return false
		if not lord.is_empty() and not B.card_allowed(kind,lord): return false
		unique[kind] = true
	return true

# The cards a lord may put in the eight, in table order.
static func pool(lord: String = "") -> Array:
	return B.CARDS.keys().filter(func(k: String) -> bool: return not B.CARDS[k].get("summon_only",false) and not B.CARDS[k].get("boss_only",false) and not B.CARDS[k].get("unreleased",false) and not B.is_home_card(k,lord) and (lord.is_empty() or B.card_allowed(k,lord)))

# The same deck with every card the lord may not take swapped for the first allowed card not yet in it.
static func fit_to_lord(deck: Array, lord: String) -> Array:
	var result: Array = deck.duplicate()
	var spare: Array = pool(lord).filter(func(k: String) -> bool: return not k in deck)
	for i: int in range(result.size()):
		if (not B.card_allowed(result[i],lord) or B.is_home_card(result[i],lord) or B.CARDS[result[i]].get("summon_only",false) or B.CARDS[result[i]].get("boss_only",false)) and not spare.is_empty(): result[i] = spare.pop_front()
	return result
static func save_deck(deck: Array, path: String = "user://deck.json", lord: String = "lion") -> bool:
	if not B.LORDS.has(lord) or not valid(deck,lord): return false
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"cards":deck,"lord":lord}))
	return true
static func load_deck(path: String = "user://deck.json") -> Array:
	return load_full(path).cards
static func load_full(path: String = "user://deck.json") -> Dictionary:
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.get("cards") is Array and B.LORDS.has(parsed.get("lord","")) and valid(parsed.cards,parsed.lord):
			return {"cards":parsed.cards,"lord":parsed.lord}
	return {"cards":B.DEFAULT_DECK.duplicate(),"lord":B.DEFAULT_LORD}
static func average(deck: Array) -> float:
	var total := 0.0
	for kind: String in deck: total += B.CARDS[kind].cost
	return total/maxi(1,deck.size())

# Random deck: eight different cards, at least three of them troops so the match can end.
static func random_deck(rng: RandomNumberGenerator, lord: String = "") -> Array:
	var units: Array = []
	var others: Array = []
	for kind: String in pool(lord):
		if B.CARDS[kind].type == "unit": units.append(kind)
		else: others.append(kind)
	var deck: Array = []
	for i: int in range(3): deck.append(units.pop_at(rng.randi_range(0,units.size()-1)))
	var rest: Array = units+others
	while deck.size() < 8: deck.append(rest.pop_at(rng.randi_range(0,rest.size()-1)))
	return deck

# 4 selectable 8-card compositions matching B.card_group (3:building, 0:melee, 1:ranged, 2:spell),
# calibrated from 972 two-stage AI matches (2026-11-19).
const PRACTICE_RATIO := {3: 1, 0: 2, 1: 4, 2: 1}
const PRACTICE_RATIOS := [
	{"id":"ranged_heavy","name":"四遠火網","ratio":{3: 1, 0: 2, 1: 4, 2: 1}},
	{"id":"pure_army","name":"零法純兵","ratio":{3: 1, 0: 4, 1: 3, 2: 0}},
	{"id":"fort_melee","name":"三建步戰","ratio":{3: 3, 0: 3, 1: 1, 2: 1}},
	{"id":"spell","name":"砲法控制","ratio":{3: 2, 0: 2, 1: 2, 2: 2}},
]
const LORD_BEST_RATIOS := {
	"adventure":{"id":"fort_melee","name":"三建步戰","ratio":{3: 3, 0: 3, 1: 1, 2: 1}},
	"lion":{"id":"ranged_heavy","name":"四遠火網","ratio":{3: 1, 0: 2, 1: 4, 2: 1}},
	"harvest":{"id":"ranged_heavy","name":"四遠火網","ratio":{3: 1, 0: 2, 1: 4, 2: 1}},
	"iron":{"id":"ranged","name":"遠程火力","ratio":{3: 2, 0: 2, 1: 3, 2: 1}},
	"mage":{"id":"spell","name":"砲法控制","ratio":{3: 2, 0: 2, 1: 2, 2: 2}},
	"rune":{"id":"no_bld_aggro","name":"零建強攻","ratio":{3: 0, 0: 4, 1: 3, 2: 1}},
	"underworld":{"id":"no_bld_aggro","name":"零建強攻","ratio":{3: 0, 0: 4, 1: 3, 2: 1}},
	"vampire":{"id":"rush","name":"強攻推線","ratio":{3: 1, 0: 4, 1: 2, 2: 1}},
	"beast":{"id":"pure_army","name":"零法純兵","ratio":{3: 1, 0: 4, 1: 3, 2: 0}},
}

static func practice_ratio_ids() -> Array:
	return PRACTICE_RATIOS.map(func(entry: Dictionary) -> String: return entry.id)

static func practice_ratio_entry(id: String) -> Dictionary:
	for entry: Dictionary in PRACTICE_RATIOS:
		if entry.id == id: return entry
	return PRACTICE_RATIOS[0]

static func lord_best_entry(lord: String) -> Dictionary:
	return LORD_BEST_RATIOS[lord] if LORD_BEST_RATIOS.has(lord) else PRACTICE_RATIOS[0]

static func lord_best_ratio(lord: String) -> Dictionary:
	return lord_best_entry(lord).ratio

static func practice_ratio_label(ratio: Dictionary) -> String:
	return "建築 %d · 近戰 %d · 遠程 %d · 法術 %d" % [int(ratio.get(3, 0)), int(ratio.get(0, 0)), int(ratio.get(1, 0)), int(ratio.get(2, 0))]

static func balanced_random_deck(rng: RandomNumberGenerator, lord: String = "", ratio: Dictionary = {}) -> Array:
	var chosen_ratio: Dictionary = ratio if not ratio.is_empty() else lord_best_ratio(lord)
	var buckets := {0: [], 1: [], 2: [], 3: []}
	var all_cards: Array = pool(lord)
	for kind: String in all_cards:
		buckets[B.card_group(kind)].append(kind)
	var deck: Array = []
	for group_id: int in [3, 0, 1, 2]:
		var bucket: Array = buckets[group_id]
		var need := mini(int(chosen_ratio.get(group_id, 0)), bucket.size())
		for _i: int in range(need):
			deck.append(bucket.pop_at(rng.randi_range(0, bucket.size() - 1)))
	var spare: Array = all_cards.filter(func(k: String) -> bool: return not k in deck)
	while deck.size() < 8 and not spare.is_empty():
		deck.append(spare.pop_at(rng.randi_range(0, spare.size() - 1)))
	return B.menu_sorted(deck)
