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
# Saved deck slots (使用者 2026-11-25「做玩家可以保存卡組」；「給卡組保存上限增加到18個」): SLOT_COUNT entries of {"cards","lord"} or null,
# kept apart from the deck the deck screen remembers by itself (user://deck.json).
const SLOT_COUNT := 18
const SLOTS_PATH := "user://deck_slots.json"
# What 我的牌組 holds before the player has saved anything (使用者 2026-11-26「繼續找找最強卡組」):
# 2 strongest distinct builds per lord across all 9 lords under the Wave 15-20 rules, AI and prices (tools/autobalance_runs/deck_search.py --mode per_lord, Wave 21).
const DEFAULT_SLOTS := [
	{"lord":"mage","cards":["spell_mirror","mana_battery","rune_workshop","phase_shift","bandit","crystal_colossus","warp_beacon","ward_phalanx"]}, # 精銳 88.9% · 隨機 100.0%
	{"lord":"mage","cards":["spell_mirror","mana_spring","rune_workshop","rain","bandit","crystal_colossus","warp_beacon","ward_phalanx"]}, # 精銳 66.7% · 隨機 100.0%
	{"lord":"vampire","cards":["mourning_maid","ossuary","pallbearer","barricade","sacrifice","funeral_cottage","funeral_grenadier","dread_howl"]}, # 精銳 83.3% · 隨機 100.0%
	{"lord":"vampire","cards":["corpse_giant","flesh_abomination","dread_howl","pallbearer","barricade","ossuary","blood_altar","raven"]}, # 精銳 77.8% · 隨機 100.0%
	{"lord":"beast","cards":["monster_hatchery","bog_troll","pouch_beast","tusk_boar","devouring_maw","long_dragon","bandit","catapult"]}, # 精銳 66.7% · 隨機 100.0%
	{"lord":"beast","cards":["monster_hatchery","bog_troll","pouch_beast","tusk_boar","monster_hunter","long_dragon","corrosive_bile","catapult"]}, # 精銳 50.0% · 隨機 100.0%
	{"lord":"underworld","cards":["seal_altar","ghoul","old_witch","catapult","plague","sealed_coffin","curse","corpse_giant"]}, # 精銳 55.6% · 隨機 83.3%
	{"lord":"underworld","cards":["gatebreaker","pallbearer","corpse_giant","bandit","shroud_arbalist","funeral_grenadier","corpse_stitcher","plague"]}, # 精銳 27.8% · 隨機 66.7%
	{"lord":"adventure","cards":["twin_gambler","guard","harvest","catapult","macebreaker","rolling_boulder","beekeeper","mill"]}, # 精銳 50.0% · 隨機 100.0%
	{"lord":"adventure","cards":["granary","manor_retainer","mob","mule_cart","guard","disgraced_lancer","catapult","healer"]}, # 精銳 27.8% · 隨機 100.0%
	{"lord":"rune","cards":["crystal_colossus","spellbreaker","ward_phalanx","powder_barrel","gravity_well","spell_mirror","orrery_walker","catapult"]}, # 精銳 38.9% · 隨機 100.0%
	{"lord":"rune","cards":["mana_battery","mana_drain","crystal_colossus","gold_monster","bandit","arcane_golem","mana_spring","ward_phalanx"]}, # 精銳 33.3% · 隨機 100.0%
	{"lord":"lion","cards":["catapult","archer","scarecrow","charge_horn","net_hunter","rolling_boulder","harvest","supply_depot"]}, # 精銳 38.9% · 隨機 83.3%
	{"lord":"lion","cards":["watchtower","guard","gatebreaker","catapult","beekeeper","old_witch","hunter","charge_horn"]}, # 精銳 22.2% · 隨機 83.3%
	{"lord":"harvest","cards":["axe_thrower","archer","watchtower","charge_horn","rolling_boulder","militia","knight","vampire_hunter"]}, # 精銳 33.3% · 隨機 100.0%
	{"lord":"harvest","cards":["archer_phalanx","healer","net_hunter","axe_thrower","macebreaker","drummer","rain","manor_retainer"]}, # 精銳 33.3% · 隨機 100.0%
	{"lord":"iron","cards":["watchtower","field_smithy","guard","monster_hunter","vampire_hunter","archer","beekeeper","rain"]}, # 精銳 33.3% · 隨機 100.0%
	{"lord":"iron","cards":["supply_depot","axe_thrower","healer","flaming_pitch","mule_cart","disgraced_lancer","barricade","guard"]}, # 精銳 33.3% · 隨機 100.0%
]

static func load_slots(path: String = SLOTS_PATH) -> Array:
	var out: Array = []
	out.resize(SLOT_COUNT)
	if not FileAccess.file_exists(path) and path == SLOTS_PATH: # a fresh player: the preset decks
		for i: int in range(mini(SLOT_COUNT,DEFAULT_SLOTS.size())):
			var d: Dictionary = DEFAULT_SLOTS[i]
			if valid(d.cards,d.lord): out[i] = {"cards":d.cards.duplicate(),"lord":d.lord}
		return out
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			for i: int in range(mini(SLOT_COUNT,parsed.size())):
				var e = parsed[i]
				if e is Dictionary and e.get("cards") is Array and B.LORDS.has(e.get("lord","")) and valid(e.cards,e.lord): out[i] = {"cards":e.cards.duplicate(),"lord":e.lord}
			if path == SLOTS_PATH and parsed.size() < SLOT_COUNT:
				for i: int in range(parsed.size(),mini(SLOT_COUNT,DEFAULT_SLOTS.size())):
					var d: Dictionary = DEFAULT_SLOTS[i]
					if valid(d.cards,d.lord): out[i] = {"cards":d.cards.duplicate(),"lord":d.lord}
	return out

static func save_slot(index: int, deck: Array, lord: String, path: String = SLOTS_PATH) -> bool:
	if index < 0 or index >= SLOT_COUNT or not B.LORDS.has(lord) or not valid(deck,lord): return false
	var slots := load_slots(path)
	slots[index] = {"cards":deck.duplicate(),"lord":lord}
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(slots))
	return true

static func clear_slot(index: int, path: String = SLOTS_PATH) -> void:
	if index < 0 or index >= SLOT_COUNT: return
	var slots := load_slots(path)
	slots[index] = null
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(slots))

# Share code & clipboard codec for deck copy/paste (supports "FLL1:<lord>:<c1>,...,<c8>", JSON, and Chinese/English card names).
static func encode_deck(deck: Array, lord: String) -> String:
	if not B.LORDS.has(lord) or not valid(deck,lord): return ""
	return "FLL1:%s:%s" % [lord,",".join(deck)]

static func _resolve_lord_token(token: String) -> String:
	var t := token.strip_edges()
	if t.is_empty(): return ""
	if B.LORDS.has(t): return t
	for lk: String in B.LORDS:
		var lname: String = String(B.LORDS[lk].name)
		if t == lname or (lname.ends_with("領主") and t == lname.trim_suffix("領主")): return lk
	return ""

static func decode_deck(raw: String, fallback_lord: String = "") -> Dictionary:
	var text := raw.strip_edges()
	if text.is_empty(): return {"ok":false,"error":"剪貼簿是空的。"}
	var lord := ""
	var tokens: Array = []
	var code_rx := RegEx.new()
	code_rx.compile("FLL1:([a-z_]+):([a-z0-9_,]+)")
	var cm := code_rx.search(text)
	if cm != null:
		lord = cm.get_string(1)
		for part: String in cm.get_string(2).split(",",false): tokens.append(part.strip_edges())
	else:
		var parsed = JSON.parse_string(text) if text.begins_with("{") else null
		if parsed is Dictionary and parsed.get("cards") is Array:
			lord = _resolve_lord_token(str(parsed.get("lord","")))
			for item in parsed.cards: tokens.append(str(item).strip_edges())
		else:
			var body := text
			var colon := body.find("：")
			if colon < 0: colon = body.find(":")
			if colon >= 0:
				var maybe_lord := _resolve_lord_token(body.substr(0,colon))
				if not maybe_lord.is_empty():
					lord = maybe_lord
					body = body.substr(colon+1)
			var sep_rx := RegEx.new()
			sep_rx.compile("[\\s,，、/|;；\\[\\]()（）「」]+")
			for part: String in sep_rx.sub(body," ",true).split(" ",false):
				var p := part.strip_edges()
				if not p.is_empty(): tokens.append(p)
	if lord.is_empty(): lord = fallback_lord if B.LORDS.has(fallback_lord) else ""
	if not B.LORDS.has(lord): return {"ok":false,"error":"剪貼簿內容不是有效的牌組格式。"}
	var name_map := {}
	for k: String in B.CARDS:
		var cd: Dictionary = B.CARDS[k]
		if cd.get("summon_only",false) or cd.get("boss_only",false) or cd.get("unreleased",false): continue
		name_map[String(cd.name)] = k
	var cards: Array = []
	for tok in tokens:
		var s := str(tok).strip_edges()
		if s.is_empty(): continue
		if B.CARDS.has(s): cards.append(s)
		elif name_map.has(s): cards.append(name_map[s])
		else: return {"ok":false,"error":"剪貼簿內有無法認出的卡牌：%s。" % s}
	var uniq := {}
	for c: String in cards: uniq[c] = true
	if cards.size() != 8 or uniq.size() != 8: return {"ok":false,"error":"牌組要剛好 8 張不重複的卡牌。"}
	if not valid(cards,lord): return {"ok":false,"error":"牌組內有不符合%s陣營的卡牌。" % B.LORDS[lord].name}
	return {"ok":true,"lord":lord,"cards":cards}

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
