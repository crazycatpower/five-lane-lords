extends RefCounted
# 肉鴿模式 (2026-11-06): run state, saving, battles and screens. Content lives in roguelike_catalog.gd.
# Screens (phase): lord (內政) -> combat (戰鬥) -> confirm -> map -> battle -> reward -> replace -> map
# ... -> won / lost. run.lord is the 戰鬥領主 on the field; run.domestic the 內政領主 at home.
const B = preload("res://balance.gd")
const Battle = preload("res://battle.gd")
const Catalog = preload("res://roguelike_catalog.gd")
const Upgrades = preload("res://card_upgrades.gd")

var run: Dictionary = {} # {lord, domestic, deck, floor, foes, seed, phase, offer, pick, gold, upgrades, relics, shop}; empty = no run
var best := 0 # most battles won in one run
var phase := "lord" # the screen shown when no run is going
var pending_domestic := ""
var pending_combat := ""
var in_battle := false
var outcome := ""
var loaded := false
var selected_slot := -1
var confirm_abandon := false
var save_notice := ""
var save_path := "user://roguelike.json"

# ---- run state ------------------------------------------------------------------------------

func read_save(path: String) -> Variant:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK: return null
	return json.data

func load_progress() -> void:
	loaded = true
	run = {}
	best = 0
	save_notice = ""
	for path: String in [save_path,save_path+".bak"]:
		if not FileAccess.file_exists(path): continue
		var parsed = read_save(path)
		if not parsed is Dictionary: continue
		var saved_best = parsed.get("best",0)
		if not (saved_best is int or saved_best is float): continue
		var r = parsed.get("run",{})
		if not r is Dictionary or (not r.is_empty() and not valid_run(r)): continue
		best = clampi(int(saved_best),0,Catalog.FLOORS)
		run = r
		if not run.is_empty():
			run.floor = int(run.floor)
			run.seed = int(run.seed)
			run.gold = int(run.get("gold",0))
			if not run.has("elites"): run.elites = Catalog.elite_schedule(run.seed,run.foes) # runs saved before path choice
			run.elite = bool(run.get("elite",false))
			run.rerolls = int(run.get("rerolls",0))
			if not run.get("gates") is Array or run.gates.size() != 5: run.gates = [B.GATE_HP,B.GATE_HP,B.GATE_HP,B.GATE_HP,B.GATE_HP] # runs saved before wounds carried over
			run.gates = run.gates.map(func(hp) -> float: return clampf(float(hp),0.0,B.GATE_HP))
			run.lord_hp = clampf(float(run.get("lord_hp",lord_max_hp())),1.0,lord_max_hp())
			for key: String in ["upgrades","relics","shop"]:
				if not run.has(key): run[key] = {} if key == "upgrades" else []
			for kind: String in run.upgrades: # JSON reads whole numbers back as floats
				for stat: String in run.upgrades[kind]: run.upgrades[kind][stat] = int(run.upgrades[kind][stat])
		if path != save_path: save_notice = "已從備份恢復進度"
		return
	if FileAccess.file_exists(save_path): save_notice = "進度檔無法讀取，可開始新的一輪"

func valid_run(r: Dictionary) -> bool:
	if not r.get("lord") is String or not B.LORDS.has(r.lord): return false
	if not r.get("domestic") is String or not B.LORDS.has(r.domestic) or r.domestic == r.lord: return false
	if not r.get("deck") is Array or not Catalog.deck_allowed(r.deck,r.domestic,r.lord): return false
	for key: String in ["floor","seed"]:
		var value = r.get(key)
		if not (value is int or value is float): return false
		if not is_finite(float(value)) or float(value) != floor(float(value)): return false
	if r.floor < 0 or r.floor >= Catalog.FLOORS or r.seed < 0: return false
	if not r.get("foes") is Array or r.foes.size() != Catalog.FLOORS: return false
	for i: int in range(Catalog.FLOORS):
		var enemy = r.foes[i]
		if not enemy is String: return false
		if i == Catalog.FLOORS-1:
			if not Catalog.BOSSES.has(enemy): return false
		elif not Catalog.MINIONS.has(enemy) or Catalog.MINIONS[enemy].tier != Catalog.FLOOR_TIER[i] or r.foes.count(enemy) > 1: return false
	if not r.get("phase","") in ["map","reward","replace","shop","won","lost"]: return false
	if r.has("elites"):
		if not r.elites is Array or r.elites.size() != Catalog.FLOOR_TIER.size(): return false
		for i: int in range(r.elites.size()):
			var e = r.elites[i]
			if not e is String or not Catalog.MINIONS.has(e) or Catalog.MINIONS[e].tier != Catalog.elite_tier(i) or r.elites.count(e) > 1: return false
	if r.get("elite",false) and int(r.get("floor",0)) >= Catalog.FLOORS-1: return false
	var gold = r.get("gold",0)
	if not (gold is int or gold is float) or gold < 0: return false
	if not r.get("relics",[]) is Array or r.get("relics",[]).any(func(k) -> bool: return not Catalog.RELICS.has(k)): return false
	if not r.get("shop",[]) is Array or r.get("shop",[]).any(func(k) -> bool: return not Catalog.RELICS.has(k)): return false
	var ups = r.get("upgrades",{})
	if not ups is Dictionary: return false
	for k in ups:
		if not B.CARDS.has(k) or not ups[k] is Dictionary or Upgrades.level(ups[k]) > Upgrades.MAX_LEVEL: return false
	if r.phase == "won" and int(r.floor) != Catalog.FLOORS-1: return false
	if r.phase in ["reward","replace"]:
		if r.floor < 1 or not r.get("offer") is Array or r.offer.size() != Catalog.OFFER_SIZE: return false
		var pool: Array = Catalog.card_pool(r.domestic,r.lord)
		for k in r.offer:
			if not k is String or not k in pool or r.offer.count(k) != 1: return false
		if r.phase == "replace" and not r.get("pick","") in r.offer: return false
	return true

func save_progress() -> bool:
	loaded = true
	var temp := save_path+".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file == null: return save_failed()
	file.store_string(JSON.stringify({"best":best,"run":run}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return save_failed()
	# Keep the last complete valid save; never replace it with a truncated/corrupt primary.
	if FileAccess.file_exists(save_path):
		var old = read_save(save_path)
		if old is Dictionary and old.get("run") is Dictionary and (old.run.is_empty() or valid_run(old.run)):
			if DirAccess.copy_absolute(save_path,save_path+".bak") != OK: return save_failed()
	if DirAccess.rename_absolute(temp,save_path) != OK: return save_failed()
	save_notice = ""
	return true

func save_failed() -> bool:
	save_notice = "儲存失敗，請先不要關閉遊戲"
	return false

func begin(domestic: String, combat: String, seed_value: int = -1) -> void:
	if not Catalog.LORD_ROLES.has(domestic) or not Catalog.LORD_ROLES.has(combat) or domestic == combat: return
	confirm_abandon = false
	if seed_value < 0: seed_value = randi() % 1000000
	run = {"lord":combat,"domestic":domestic,"deck":Catalog.starter_deck(domestic,combat),"floor":0,"foes":Catalog.schedule(seed_value),"seed":seed_value,"phase":"map","offer":[],"pick":"","gold":0,"upgrades":{},"relics":[],"shop":[],"elite":false,"rerolls":0,"gates":[B.GATE_HP,B.GATE_HP,B.GATE_HP,B.GATE_HP,B.GATE_HP],"lord_hp":float(B.lord_data(combat).hp)}
	run.elites = Catalog.elite_schedule(seed_value,run.foes)
	save_progress()

func foe() -> String:
	if run.get("elite",false) and not is_boss(): return run.elites[run.floor]
	return run.foes[run.floor]

# Path choice on the map: the floor's normal foe or its elite (not on the boss floor).
func set_elite(on: bool) -> void:
	if run.is_empty() or run.phase != "map" or is_boss(): return
	run.elite = on
	save_progress()

func win_gold(floor_index: int, elite: bool) -> int:
	return int(Catalog.gold_for(floor_index)*(Catalog.ELITE_GOLD_MULT if elite else 1.0))

func lord_max_hp() -> float:
	return float(B.lord_data(run.get("lord","lion")).hp)

# After a battle: our gates and lord keep what is left (a lord who is down comes back weak).
func record_wounds(m) -> void:
	if run.is_empty(): return
	run.gates = m.gates[0].duplicate()
	var lord: Dictionary = m.lords[0] if not m.lords.is_empty() else {}
	run.lord_hp = maxf(1.0,lord.hp) if not lord.is_empty() and lord.hp > 0 else lord_max_hp()*Catalog.FALLEN_LORD_SHARE

func gate_missing() -> float:
	var missing := 0.0
	for hp: float in run.get("gates",[]): missing += B.GATE_HP-hp
	return missing

func repair_cost() -> int:
	return ceili(gate_missing()/Catalog.GATE_HP_PER_GOLD)

func heal_cost() -> int:
	return ceili((lord_max_hp()-run.get("lord_hp",lord_max_hp()))/Catalog.LORD_HP_PER_GOLD)

func repair_error() -> String:
	if run.is_empty() or run.phase != "shop": return "現在不能修理"
	if gate_missing() <= 0.0: return "城牆完好"
	if run.gold <= 0: return "金幣不足"
	return ""

func heal_error() -> String:
	if run.is_empty() or run.phase != "shop": return "現在不能治療"
	if run.lord_hp >= lord_max_hp(): return "領主無傷"
	if run.gold <= 0: return "金幣不足"
	return ""

# Spend up to the full price; short of gold, every gate is mended by the same share.
func repair_gates() -> void:
	if not repair_error().is_empty(): return
	var spend := mini(run.gold,repair_cost())
	var share := minf(1.0,spend*Catalog.GATE_HP_PER_GOLD/gate_missing())
	run.gates = run.gates.map(func(hp: float) -> float: return minf(B.GATE_HP,hp+(B.GATE_HP-hp)*share))
	run.gold -= spend
	save_progress()

func heal_lord() -> void:
	if not heal_error().is_empty(): return
	var spend := mini(run.gold,heal_cost())
	run.lord_hp = minf(lord_max_hp(),run.lord_hp+spend*Catalog.LORD_HP_PER_GOLD)
	run.gold -= spend
	save_progress()

func is_boss() -> bool:
	return run.floor == Catalog.FLOORS-1

func settle(won: bool) -> void:
	if run.is_empty() or run.phase != "map": return
	if won:
		best = maxi(best,run.floor+1)
		if is_boss():
			run.phase = "won"
			outcome = "肉鴿通關！八場全勝"
		else:
			var elite: bool = run.get("elite",false)
			var gold := win_gold(run.floor,elite)
			run.gold += gold
			run.offer = Catalog.offer(run.domestic,run.lord,run.seed,run.floor,run.deck)
			run.floor += 1
			run.elite = false
			run.phase = "reward"
			outcome = "第 %d 場%s勝利！獲得 %d 金幣" % [run.floor,"精英" if elite else "",gold]
	else:
		run.phase = "lost"
		outcome = "敗北：本輪止步第 %d 場" % (run.floor+1)
	save_progress()

func pick(kind: String) -> void:
	if run.is_empty() or run.phase != "reward" or not kind in run.offer: return
	selected_slot = -1
	run.pick = kind
	run.phase = "replace"
	save_progress()

func replace(slot: int) -> void:
	if run.is_empty() or run.phase != "replace" or slot < 0 or slot >= run.deck.size() or not run.pick in run.offer: return
	run.deck[slot] = run.pick
	run.pick = ""
	run.offer = []
	open_shop()

func skip_reward() -> void:
	if run.is_empty() or not run.phase in ["reward","replace"]: return
	run.pick = ""
	run.offer = []
	open_shop()

# ---- shop: gold buys run-long card upgrades and relics ----------------------------------------

func open_shop() -> void:
	if run.is_empty() or not run.phase in ["map","reward","replace"]: return
	if run.phase != "map" or run.shop.is_empty(): run.shop = Catalog.relic_offer(run.seed,run.floor,run.relics)
	run.phase = "shop"
	save_progress()

func leave_shop() -> void:
	if run.is_empty() or run.phase != "shop": return
	run.phase = "map"
	save_progress()

# "" = can buy; otherwise why not.
func upgrade_error(kind: String) -> String:
	if run.is_empty() or run.phase != "shop" or not kind in run.deck: return "現在不能強化"
	var ups: Dictionary = run.upgrades.get(kind,{})
	if Upgrades.level(ups) >= Upgrades.MAX_LEVEL: return "已達 +%d" % Upgrades.MAX_LEVEL
	if Upgrades.options(kind,ups).is_empty(): return "沒有可強化的能力"
	if run.gold < Upgrades.price(ups): return "金幣不足"
	return ""

func upgrade(kind: String) -> void:
	if not upgrade_error(kind).is_empty(): return
	var ups: Dictionary = run.upgrades.get(kind,{}).duplicate()
	var choices: Array = Upgrades.options(kind,ups)
	var rng := RandomNumberGenerator.new()
	rng.seed = run.seed*7+run.floor*131+Upgrades.level(ups)*17+hash(kind)
	var stat: String = choices[rng.randi_range(0,choices.size()-1)]
	run.gold -= Upgrades.price(ups)
	ups[stat] = int(ups.get(stat,0))+1
	run.upgrades[kind] = ups
	save_progress()

func reroll_error() -> String:
	if run.is_empty() or run.phase != "shop": return "現在不能刷新"
	if run.gold < Catalog.REROLL_PRICE: return "金幣不足"
	return ""

func reroll() -> void:
	if not reroll_error().is_empty(): return
	run.gold -= Catalog.REROLL_PRICE
	run.rerolls = int(run.get("rerolls",0))+1
	run.shop = Catalog.relic_offer(run.seed+run.rerolls*7777,run.floor,run.relics)
	save_progress()

func relic_error(relic: String) -> String:
	if run.is_empty() or run.phase != "shop" or not relic in run.shop: return "現在不能購買"
	if run.gold < Catalog.RELICS[relic].price: return "金幣不足"
	return ""

func buy_relic(relic: String) -> void:
	if not relic_error(relic).is_empty(): return
	run.gold -= Catalog.RELICS[relic].price
	run.relics.append(relic)
	run.shop.erase(relic)
	save_progress()

func abandon() -> void:
	run = {}
	phase = "lord"
	save_progress()

# ---- battles -----------------------------------------------------------------------------------

func make_battle() -> Battle:
	var enemy := foe()
	var m := Battle.new(run.seed+run.floor*7919,run.deck.duplicate(),Catalog.foe_deck(enemy),run.lord,enemy)
	m.apply_domestic(0,B.home_card(run.lord),Catalog.side_mods(run.domestic,run.relics)) # the 戰鬥 lord picks the home card
	m.card_upgrades[0] = run.upgrades.duplicate(true)
	m.gates[0] = run.get("gates",m.gates[0]).duplicate()
	m.lords[0].hp = minf(m.lords[0].max_hp,run.get("lord_hp",m.lords[0].max_hp))
	m.refresh_territory()
	m.ink[1] = Catalog.ELITE_START_INK if run.get("elite",false) and not is_boss() else Catalog.ENEMY_START_INK
	m.difficulty = Catalog.AI_LEVEL[run.floor]
	m.ai_enabled = [false,true]
	m.night_decay = false # gate wounds carry over; Catalog.TIME_LIMIT ends a drawn-out battle instead
	return m

func start_battle(game) -> void:
	game.spectating = false
	game.adventure.index = -1
	game.model = make_battle()
	in_battle = true
	outcome = ""
	game.enter_battle("肉鴿 第 %d / %d 場 · 對手：%s · %d 分鐘未分勝負時，城牆血量多的一方獲勝" % [run.floor+1,Catalog.FLOORS,B.lord_name(foe()),int(Catalog.TIME_LIMIT/60)])

# Called every physics frame: settles the battle once it ends.
func update(game) -> void:
	if not in_battle or not outcome.is_empty() or game.model.paused: return
	time_limit(game.model)
	if game.model.ended:
		if game.model.winner == 0: record_wounds(game.model)
		settle(game.model.winner == 0)

# Past Catalog.TIME_LIMIT the side with more gate health left wins; a tie goes to the foe.
static func time_limit(m) -> void:
	if m.ended or m.elapsed < Catalog.TIME_LIMIT: return
	var mine: float = 0.0
	var theirs: float = 0.0
	for hp: float in m.gates[0]: mine += hp
	for hp: float in m.gates[1]: theirs += hp
	m.finish(0 if mine > theirs else 1)

# Leaving a battle that is still going counts as a loss.
func leave_battle(game) -> void:
	if in_battle and outcome.is_empty(): settle(false)
	in_battle = false
	show(game)

# ---- screens -----------------------------------------------------------------------------------

func show(game) -> void:
	if not loaded: load_progress()
	in_battle = false
	game.screen = "rogue"
	game.clear_ui()
	var current: String = run.get("phase",phase) if not run.is_empty() else phase
	match current:
		"lord", "combat":
			var lords: Array = B.lord_menu_order()
			for i: int in range(lords.size()):
				var lord: String = lords[i]
				if current == "combat" and lord == pending_domestic: continue # two different lords
				var choice := hit(game,lord_rect(i),func():
					if current == "lord":
						pending_domestic = lord
						phase = "combat"
					else:
						pending_combat = lord
						phase = "confirm"
					show(game))
				choice.tooltip_text = role_text(lord,current == "lord")
			if current == "combat": game.title_button(Rect2(100,820,230,46),"重選內政",func(): phase = "lord"; show(game))
		"confirm":
			game.title_button(Rect2(1180,800,300,56),"出發",func(): begin(pending_domestic,pending_combat); show(game),true)
			game.title_button(Rect2(100,820,230,46),"重選戰鬥",func(): phase = "combat"; show(game))
		"map":
			if not is_boss():
				var elite: bool = run.get("elite",false)
				var paths: Array = [game.title_button(Rect2(105,252,330,40),"一般：%s（+%d 金）" % [B.lord_name(run.foes[run.floor]),win_gold(run.floor,false)],func(): set_elite(false); show(game),not elite),
					game.title_button(Rect2(445,252,330,40),"精英：%s（+%d 金）" % [B.lord_name(run.elites[run.floor]),win_gold(run.floor,true)],func(): set_elite(true); show(game),elite)]
				for b: Button in paths: b.add_theme_font_size_override("font_size",18)
			game.title_button(Rect2(1180,800,300,56),"出戰",func(): start_battle(game),true)
			game.title_button(Rect2(470,808,300,46),"商店（%d 金）" % run.gold,func(): open_shop(); show(game))
			game.title_button(Rect2(820,808,300,46),"確定放棄這輪？" if confirm_abandon else "放棄這輪",func():
				if confirm_abandon: abandon()
				else: confirm_abandon = true
				show(game))
		"reward":
			var detail = game.library.text_box(Rect2(1170,280,345,420),desc(run.offer[0]),19)
			game.library.text_box(Rect2(120,660,990,90),"目前牌組："+"、".join(run.deck.map(func(k: String) -> String: return B.CARDS[k].name)),18)
			for i: int in range(run.offer.size()):
				var kind: String = run.offer[i]
				var choice := hit(game,offer_rect(i),func(): pick(kind); show(game))
				choice.tooltip_text = desc(kind)
				choice.mouse_entered.connect(func(): detail.text = desc(kind))
				choice.focus_entered.connect(func(): detail.text = desc(kind))
			game.title_button(Rect2(680,800,240,48),"不換，跳過",func(): skip_reward(); show(game))
		"replace":
			for i: int in range(8):
				var slot := i
				var choice := hit(game,deck_rect(i),func(): selected_slot = slot; show(game))
				choice.tooltip_text = desc(run.deck[i])
			game.title_button(Rect2(680,800,240,48),"重新挑卡",func(): run.phase = "reward"; save_progress(); show(game))
			game.library.text_box(Rect2(100,190,1400,115),desc(run.pick),19)
			if selected_slot >= 0:
				game.title_button(Rect2(1000,800,300,48),"確認替換："+B.CARDS[run.deck[selected_slot]].name,func(): replace(selected_slot); show(game),true)
		"shop":
			var kinds := shop_kinds()
			for i: int in range(kinds.size()):
				var kind: String = kinds[i]
				var why := upgrade_error(kind)
				var label: String = ("強化 %d 金" % Upgrades.price(run.upgrades.get(kind,{}))) if why.is_empty() else why
				var b: Button = game.title_button(Rect2(upgrade_rect(i).position+Vector2(10,upgrade_rect(i).size.y-44),Vector2(upgrade_rect(i).size.x-20,36)),label,func(): upgrade(kind); show(game))
				b.disabled = not why.is_empty()
				b.tooltip_text = desc(kind)
			for i: int in range(run.shop.size()):
				var relic: String = run.shop[i]
				var why := relic_error(relic)
				var b: Button = game.title_button(Rect2(relic_rect(i).position+Vector2(20,relic_rect(i).size.y-50),Vector2(relic_rect(i).size.x-40,40)),("購買 %d 金" % Catalog.RELICS[relic].price) if why.is_empty() else why,func(): buy_relic(relic); show(game))
				b.disabled = not why.is_empty()
			var fix := repair_error()
			var mend: Button = game.title_button(Rect2(340,795,370,44),("修城牆 %d 金" % mini(run.gold,repair_cost())) if fix.is_empty() else fix,func(): repair_gates(); show(game))
			mend.disabled = not fix.is_empty()
			var cure := heal_error()
			var heal: Button = game.title_button(Rect2(730,795,370,44),("治療領主 %d 金" % mini(run.gold,heal_cost())) if cure.is_empty() else cure,func(): heal_lord(); show(game))
			heal.disabled = not cure.is_empty()
			var why := reroll_error()
			var again: Button = game.title_button(Rect2(1180,740,300,44),("刷新遺物 %d 金" % Catalog.REROLL_PRICE) if why.is_empty() else why,func(): reroll(); show(game))
			again.disabled = not why.is_empty()
			game.title_button(Rect2(1180,800,300,56),"離開商店",func(): leave_shop(); show(game),true)
		"won", "lost":
			game.title_button(Rect2(680,640,240,56),"新的一輪",func(): abandon(); show(game),true)
	game.title_button(Rect2(350,820,230,46) if current in ["combat","confirm"] else Rect2(100,820,230,46),"返回標題",game.show_title)
	if current == "confirm":
		deck_tooltips(game,Catalog.starter_deck(pending_domestic,pending_combat),Vector2(860,300))
	if current == "map":
		deck_tooltips(game,Catalog.foe_deck(foe()),Vector2(220,520))
		deck_tooltips(game,run.deck,Vector2(950,520))
		var enemy := foe()
		game.library.text_box(Rect2(310,410,440,86),("被動："+B.minion_text(enemy)) if B.is_minion(enemy) else B.skill_text(enemy),17)
		game.library.text_box(Rect2(1020,325,460,170),duo_text(run.domestic,run.lord),16)
	game.queue_redraw()

# What a lord brings in one role: 內政 (passive, ranged troop, card) or 戰鬥 (skill, melee troop, card).
func role_text(lord: String, domestic: bool) -> String:
	var faction_troops: Array = Catalog.STARTER_CORE[B.lord_faction(lord)]
	if domestic:
		return "內政被動：%s\n遠程部隊：%s ×3 · 內政卡：%s" % [B.passive_text(Catalog.passive(lord)),B.CARDS[faction_troops[1]].name,B.CARDS[Catalog.LORD_ROLES[lord].domestic.card].name]
	return "戰鬥技能：%s\n近戰部隊：%s ×3 · 戰鬥卡：%s\n常駐牌：%s" % [B.skill_text(lord),B.CARDS[faction_troops[0]].name,B.CARDS[Catalog.LORD_ROLES[lord].combat.card].name,B.CARDS[B.home_card(lord)].name]

func duo_text(domestic: String, combat: String) -> String:
	return "戰鬥 · %s\n%s常駐牌：%s。\n\n內政 · %s\n%s" % [B.lord_name(combat),B.skill_text(combat),B.CARDS[B.home_card(combat)].name,B.lord_name(domestic),B.passive_text(Catalog.passive(domestic))]

# A card's text with this run's upgrades in its numbers.
func desc(kind: String) -> String:
	if run.is_empty() or not run.get("upgrades",{}).has(kind): return B.card_description(kind)
	return B.card_description(kind,Upgrades.table(run.upgrades))+"\n強化 +%d：%s" % [Upgrades.level(run.upgrades[kind]),Upgrades.text(run.upgrades[kind])]

func deck_tooltips(game, cards: Array, origin: Vector2) -> void:
	for i: int in range(cards.size()):
		var rect := Rect2(origin+Vector2((i%4)*108,(i/4)*110),Vector2(100,102))
		var tile := hit(game,rect,func(): pass)
		tile.tooltip_text = desc(cards[i])

func deck_summary(cards: Array) -> String:
	var counts := {"unit":0,"spell":0,"building":0}
	var cost := 0.0
	for kind: String in cards:
		counts[B.CARDS[kind].type] += 1
		cost += B.CARDS[kind].cost
	return "部隊 %d · 法術 %d · 建築 %d · 平均費用 %.1f" % [counts.unit,counts.spell,counts.building,cost/maxi(1,cards.size())]

func hit(game, rect: Rect2, action: Callable) -> Button:
	var b: Button = game.button(rect,"",action)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1,0.9,0.6,0.22) if state == "hover" else Color.TRANSPARENT
		if state == "focus":
			style.border_color = Color("d2ad58")
			style.set_border_width_all(2)
		b.add_theme_stylebox_override(state,style)
	return b

func shop_kinds() -> Array:
	var kinds: Array = []
	for k: String in run.deck:
		if not k in kinds: kinds.append(k)
	return kinds

func upgrade_rect(i: int) -> Rect2:
	return Rect2(90+(i%4)*190,215+(i/4)*270,175,255)

func relic_rect(i: int) -> Rect2:
	return Rect2(880,215+i*175,630,160)

func lord_rect(i: int) -> Rect2:
	if B.LORDS.size() <= 8: return Rect2(150+(i%4)*330,176+(i/4)*308,290,252)
	return Rect2(92+(i%5)*286,176+(i/5)*308,272,252) # nine lords: five to a row


func offer_rect(i: int) -> Rect2:
	return Rect2(120+i*345,260,240,340)

func deck_rect(i: int) -> Rect2:
	return Rect2(330+(i%4)*240,330+(i/4)*230,200,210)

func paint(g) -> void:
	g.label_at(Vector2(90,88),"肉鴿模式",44)
	g.label_at(Vector2(300,88),"八場連戰，輸一場就結束 · 最佳紀錄 %d / %d 場" % [best,Catalog.FLOORS],22)
	if not save_notice.is_empty(): g.label_at(Vector2(90,120),save_notice,18,g.RED)
	var current: String = run.get("phase",phase) if not run.is_empty() else phase
	match current:
		"lord", "combat": paint_lords(g,current == "lord")
		"confirm": paint_confirm(g)
		"map": paint_map(g)
		"reward": paint_reward(g)
		"replace": paint_replace(g)
		"shop": paint_shop(g)
		"won", "lost": paint_end(g)

func paint_lords(g, domestic: bool) -> void:
	if domestic: g.label_at(Vector2(150,150),"第一步：選內政領主（坐鎮後方：提供被動與遠程部隊）",24)
	else: g.label_at(Vector2(150,150),"第二步：選戰鬥領主（親自上場：提供技能、常駐牌與近戰部隊）· 內政：%s" % B.lord_name(pending_domestic),24)
	var lords: Array = B.lord_menu_order()
	for i: int in range(lords.size()):
		var r := lord_rect(i)
		if not domestic and lords[i] == pending_domestic:
			g.panel(r,Color(0.85,0.80,0.70,0.5),Color("a89a80"))
			g.draw_string(g.font,r.position+Vector2(0,r.size.y/2),"已是內政領主",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,20,Color(g.INK,0.6))
			continue
		g.draw_lord_card(lords[i],r,false)
		var troops: Array = Catalog.STARTER_CORE[B.lord_faction(lords[i])]
		var line: String = (B.passive_text(Catalog.passive(lords[i]))+" 遠程："+B.CARDS[troops[1]].name) if domestic else ("近戰："+B.CARDS[troops[0]].name+" · 戰鬥卡："+B.CARDS[Catalog.LORD_ROLES[lords[i]].combat.card].name+" · 常駐："+B.CARDS[B.home_card(lords[i])].name)
		var caption := TextParagraph.new()
		caption.width = r.size.x-12
		caption.alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		caption.add_string(line,g.font,14)
		caption.draw(g.get_canvas_item(),Vector2(r.position.x+6,r.end.y+4),g.RED if domestic else g.INK)

func paint_confirm(g) -> void:
	g.label_at(Vector2(150,150),"兩位領主組成的起始牌組",24)
	g.draw_lord_card(pending_domestic,Rect2(110,190,250,300),false)
	g.draw_lord_card(pending_combat,Rect2(390,190,250,300),true)
	g.draw_string(g.font,Vector2(110,520),"內政",HORIZONTAL_ALIGNMENT_CENTER,250,22,g.RED)
	g.draw_string(g.font,Vector2(390,520),"戰鬥（上場）",HORIZONTAL_ALIGNMENT_CENTER,250,22,g.RED)
	g.draw_multiline_string(g.font,Vector2(110,560),duo_text(pending_domestic,pending_combat),HORIZONTAL_ALIGNMENT_LEFT,560,16,-1,g.INK)
	var r := Rect2(830,190,690,560)
	g.panel(r,Color("efe0bd"))
	g.draw_string(g.font,r.position+Vector2(0,40),"起始牌組（遠程 ×3 · 近戰 ×3 · 內政卡 · 戰鬥卡）",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,20,g.INK)
	var cards := Catalog.starter_deck(pending_domestic,pending_combat)
	mini_deck(g,cards,Vector2(860,300),2)
	g.label_at(Vector2(860,560),deck_summary(cards),17)

# Eight small tiles: picture and name.
func mini_deck(g, cards: Array, origin: Vector2, rows: int = 2, ups: Dictionary = {}) -> void:
	var per_row := ceili(cards.size()/float(rows))
	for i: int in range(cards.size()):
		var cell := Rect2(origin+Vector2((i%per_row)*108,(i/per_row)*110),Vector2(100,102))
		g.panel(cell,Color("f6ead0"))
		g.draw_fitted(g.art(cards[i]),Rect2(cell.position+Vector2(8,4),Vector2(84,66)),Color.WHITE,true)
		var name: String = B.CARDS[cards[i]].name
		g.draw_string(g.font,cell.position+Vector2(0,92),name,HORIZONTAL_ALIGNMENT_CENTER,cell.size.x,14 if name.length() > 4 else 16,g.INK)
		var lv: int = Upgrades.level(ups.get(cards[i],{}))
		if lv > 0: g.draw_string(g.font,cell.position+Vector2(6,20),"+%d" % lv,HORIZONTAL_ALIGNMENT_LEFT,-1,18,g.RED)

func paint_floors(g, y: float) -> void:
	for i: int in range(Catalog.FLOORS):
		var p := Vector2(420+i*110,y)
		var done: bool = i < run.floor or (i == run.floor and run.phase == "won")
		if i == run.floor and run.phase in ["map","lost"]: g.draw_circle(p,34,Color("d2ad58",0.9))
		g.draw_circle(p,27,g.RED if done else (Color("6f5a3e") if i == Catalog.FLOORS-1 else Color("a89a80")))
		g.draw_arc(p,27,0,TAU,36,Color(g.INK,0.85),2.5,true)
		g.draw_string(g.font,p+Vector2(-27,9),"魔王" if i == Catalog.FLOORS-1 else str(i+1),HORIZONTAL_ALIGNMENT_CENTER,54,20 if i == Catalog.FLOORS-1 else 24,Color("fff0ca"))
		if i < Catalog.FLOORS-1: g.ink_line(p+Vector2(30,0),p+Vector2(80,0),i,Color(g.INK,0.5),2.0)

func paint_map(g) -> void:
	paint_floors(g,175)
	var enemy := foe()
	var left := Rect2(90,240,700,540)
	g.panel(left,Color("efe0bd"))
	if is_boss(): g.draw_string(g.font,left.position+Vector2(0,42),"第 %d 場：魔王" % (run.floor+1),HORIZONTAL_ALIGNMENT_CENTER,left.size.x,24,g.RED)
	elif run.get("elite",false): g.label_at(Vector2(left.position.x+220,left.position.y+260),"精英 · 開局 %d 金 · 勝利 ×%s 金幣" % [int(Catalog.ELITE_START_INK),B.number(Catalog.ELITE_GOLD_MULT)],17,g.RED)
	g.draw_fitted(g.lord_art(enemy,1),Rect2(left.position+Vector2(30,60),Vector2(170,170)),Color.WHITE,true)
	var x := left.position.x+220
	g.label_at(Vector2(x,left.position.y+100),B.lord_name(enemy),30)
	g.label_at(Vector2(x,left.position.y+136),"%s · AI %s" % [B.lord_data(enemy).role,["簡單","普通","困難"][Catalog.AI_LEVEL[run.floor]]],18,Color("6f5a3e"))
	g.draw_string(g.font,left.position+Vector2(30,262),"敵方牌組：",HORIZONTAL_ALIGNMENT_LEFT,-1,18,g.INK)
	mini_deck(g,Catalog.foe_deck(enemy),left.position+Vector2(130,280),2)
	var right := Rect2(820,240,690,540)
	g.panel(right,Color("efe0bd"))
	g.draw_string(g.font,right.position+Vector2(0,42),"我的部隊 · 戰鬥%s ＋ 內政%s" % [B.lord_name(run.lord).trim_suffix("領主"),B.lord_name(run.domestic).trim_suffix("領主")],HORIZONTAL_ALIGNMENT_CENTER,right.size.x,22,g.INK)
	g.draw_fitted(g.lord_art(run.lord),Rect2(right.position+Vector2(20,60),Vector2(110,170)),Color.WHITE,true)
	g.draw_fitted(g.lord_art(run.domestic),Rect2(right.position+Vector2(110,110),Vector2(80,120)),Color(1,1,1,0.85),true)
	mini_deck(g,run.deck,right.position+Vector2(130,280),2,run.upgrades)
	g.label_at(Vector2(right.position.x+20,right.position.y+236),wounds_text(),15,g.RED)
	g.label_at(Vector2(right.position.x+20,right.position.y+258),"金幣 %d · 遺物：%s" % [run.gold,"、".join(run.relics.map(func(k: String) -> String: return Catalog.RELICS[k].name)) if not run.relics.is_empty() else "無"],15,Color("6f5a3e"))
	g.label_at(Vector2(950,758),deck_summary(run.deck),17)
	g.label_at(Vector2(220,758),deck_summary(Catalog.foe_deck(enemy)),17)

func paint_reward(g) -> void:
	g.panel(Rect2(1145,260,395,455),Color("efe0bd"))
	paint_floors(g,175)
	g.draw_string(g.font,Vector2(0,240),"選一張卡加入牌組（之後選要換掉哪一張）",HORIZONTAL_ALIGNMENT_CENTER,1600,26,g.INK)
	for i: int in range(run.offer.size()):
		g.draw_card(run.offer[i],offer_rect(i))
		g.label_at(offer_rect(i).position+Vector2(0,370),"目前持有 %d 張" % run.deck.count(run.offer[i]),18)
	g.label_at(Vector2(1170,250),"卡牌效果",22)

func paint_replace(g) -> void:
	g.panel(Rect2(80,180,1440,135),Color("efe0bd"))
	if selected_slot >= 0:
		var old: String = run.deck[selected_slot]
		g.label_at(Vector2(80,660),"移除："+B.CARDS[old].name,20)
		g.label_at(Vector2(80,695),"費用 %d → %d" % [B.CARDS[old].cost,B.CARDS[run.pick].cost],20)
	g.draw_string(g.font,Vector2(0,160),"新卡：%s　→　點一張要換掉的卡" % B.CARDS[run.pick].name,HORIZONTAL_ALIGNMENT_CENTER,1600,28,g.RED)
	g.draw_card(run.pick,Rect2(80,330,200,280))
	for i: int in range(8):
		var r := deck_rect(i)
		g.panel(r,Color("f6ead0"))
		if i == selected_slot: g.draw_rect(r,Color("b08b2f"),false,4)
		g.draw_fitted(g.art(run.deck[i]),Rect2(r.position+Vector2(14,10),Vector2(r.size.x-28,140)),Color.WHITE,true)
		g.draw_string(g.font,r.position+Vector2(0,178),B.CARDS[run.deck[i]].name,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,20,g.INK)
		g.draw_string(g.font,r.position+Vector2(0,200),"%d 金幣" % B.CARDS[run.deck[i]].cost,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,15,Color("6f5a3e"))

func paint_shop(g) -> void:
	g.label_at(Vector2(90,180),"商店 · 金幣 %d · 卡牌強化（本輪有效，每次隨機一項能力升一檔，最高 SS）" % run.gold,22,g.RED)
	var kinds := shop_kinds()
	for i: int in range(kinds.size()):
		var kind: String = kinds[i]
		var r := upgrade_rect(i)
		var ups: Dictionary = run.upgrades.get(kind,{})
		g.panel(r,Color("f6ead0"))
		g.draw_fitted(g.art(kind),Rect2(r.position+Vector2(12,8),Vector2(r.size.x-24,110)),Color.WHITE,true)
		g.draw_string(g.font,r.position+Vector2(0,140),"%s ×%d" % [B.CARDS[kind].name,run.deck.count(kind)],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,18,g.INK)
		g.draw_string(g.font,r.position+Vector2(0,166),"+%d / %d" % [Upgrades.level(ups),Upgrades.MAX_LEVEL],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,17,g.RED if Upgrades.level(ups) > 0 else Color("6f5a3e"))
		g.draw_string(g.font,r.position+Vector2(0,190),Upgrades.text(ups),HORIZONTAL_ALIGNMENT_CENTER,r.size.x,14,Color("6f5a3e"))
	g.label_at(Vector2(880,200),"遺物",22,g.RED)
	for i: int in range(run.shop.size()):
		var relic: Dictionary = Catalog.RELICS[run.shop[i]]
		var r := relic_rect(i)
		g.panel(r,Color("efe0bd"))
		g.draw_string(g.font,r.position+Vector2(20,38),"%s　%d 金" % [relic.name,relic.price],HORIZONTAL_ALIGNMENT_LEFT,-1,24,g.INK)
		g.draw_string(g.font,r.position+Vector2(20,74),B.passive_text(relic.mods),HORIZONTAL_ALIGNMENT_LEFT,r.size.x-40,18,Color("6f5a3e"))
	if run.shop.is_empty(): g.label_at(Vector2(880,260),"這一站的遺物已經買完了",18)
	g.label_at(Vector2(340,782),wounds_text()+" · 城牆每 1 金修 %d 血、領主每 1 金治 %d 血" % [int(Catalog.GATE_HP_PER_GOLD),int(Catalog.LORD_HP_PER_GOLD)],16,g.RED)
	g.label_at(Vector2(880,760),"已有遺物："+("、".join(run.relics.map(func(k: String) -> String: return Catalog.RELICS[k].name)) if not run.relics.is_empty() else "無"),17)

func wounds_text() -> String:
	var standing: int = run.get("gates",[]).filter(func(hp: float) -> bool: return hp > 0).size()
	var total := 0.0
	for hp: float in run.get("gates",[]): total += hp
	return "城牆 %d/5 座 · 總血量 %d%% · 領主 %d/%d" % [standing,roundi(100.0*total/(5*B.GATE_HP)),int(run.get("lord_hp",0)),int(lord_max_hp())]

func paint_end(g) -> void:
	paint_floors(g,250)
	var won: bool = run.phase == "won"
	g.draw_string(g.font,Vector2(0,400),"肉鴿通關！" if won else "本輪結束",HORIZONTAL_ALIGNMENT_CENTER,1600,52,g.RED if won else g.INK)
	var text := ("%s帶著這副牌打完了八場。" % B.lord_name(run.lord)) if won else ("止步第 %d 場，敗給%s。" % [run.floor+1,B.lord_name(foe())])
	g.draw_string(g.font,Vector2(0,470),text,HORIZONTAL_ALIGNMENT_CENTER,1600,24,g.INK)
	g.draw_string(g.font,Vector2(0,520),"最終牌組：" + "、".join(run.deck.map(func(k: String) -> String: return B.CARDS[k].name)),HORIZONTAL_ALIGNMENT_CENTER,1600,18,Color("6f5a3e"))
