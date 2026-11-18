extends RefCounted
# 肉鴿模式 (2026-11-14 重構): 命運四選牌陣（四選一、單格遞補、特殊情況連鎖變異）、奇遇事件、營火鍛造、
# 秘寶古祠、24 種遺物、自選屬性強化與進階戰役契約。Content lives in roguelike_catalog.gd.
const B = preload("res://balance.gd")
const Battle = preload("res://battle.gd")
const Catalog = preload("res://roguelike_catalog.gd")
const Upgrades = preload("res://card_upgrades.gd")

var run: Dictionary = {} # active run state; empty = no run
var best := 0 # most battles won in one run
var clears := 0 # total victorious runs
var max_contract := 0 # highest contract cleared
var cleared_lords: Array = [] # lords that have completed a full 8-floor run
var phase := "lord" # screen shown when no run is going
var pending_lord := ""
var pending_seed := -1
var pending_contract := 0
var in_battle := false
var outcome := ""
var loaded := false
var selected_slot := -1
var camp_card_index := 0
var camp_stat := ""
var shop_stats: Dictionary = {} # kind -> chosen stat key in shop
var confirm_abandon := false
var save_notice := ""
var save_path := "user://roguelike.json"

# ---- run state & persistence --------------------------------------------------------------------

func read_save(path: String) -> Variant:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK: return null
	return json.data

func load_progress() -> void:
	loaded = true
	run = {}
	best = 0
	clears = 0
	max_contract = 0
	cleared_lords = []
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
		clears = maxi(0,int(parsed.get("clears",0)))
		max_contract = clampi(int(parsed.get("max_contract",0)),0,Catalog.CONTRACTS.size()-1)
		if parsed.get("cleared_lords") is Array:
			for who in parsed.cleared_lords:
				if who is String and B.LORDS.has(who) and not who in cleared_lords: cleared_lords.append(who)
		run = r
		if not run.is_empty():
			run.floor = int(run.floor)
			run.seed = int(run.seed)
			run.gold = int(run.get("gold",0))
			if not run.has("elites"): run.elites = Catalog.elite_schedule(run.seed,run.foes)
			run.elite = bool(run.get("elite",false))
			run.rerolls = int(run.get("rerolls",0))
			run.contract = clampi(int(run.get("contract",0)),0,Catalog.CONTRACTS.size()-1)
			run.draws = maxi(0,int(run.get("draws",0)))
			run.march_steps = clampi(int(run.get("march_steps",2)),0,3)
			run.selected_node = clampi(int(run.get("selected_node",0)),0,3)
			run.board_notice = str(run.get("board_notice",""))
			run.last_relic = str(run.get("last_relic",""))
			run.from_event = bool(run.get("from_event",false))
			if not run.get("gates") is Array or run.gates.size() != 5: run.gates = [B.GATE_HP,B.GATE_HP,B.GATE_HP,B.GATE_HP,B.GATE_HP]
			run.gates = run.gates.map(func(hp) -> float: return clampf(float(hp),0.0,B.GATE_HP))
			run.lord_hp = clampf(float(run.get("lord_hp",lord_max_hp())),1.0,lord_max_hp())
			for key: String in ["upgrades","offer_ups","relics","shop"]:
				if not run.has(key): run[key] = {} if key in ["upgrades","offer_ups"] else []
			run.offer_rerolls = int(run.get("offer_rerolls",0))
			run.last_elite = bool(run.get("last_elite",false))
			for kind: String in run.upgrades:
				for stat: String in run.upgrades[kind]: run.upgrades[kind][stat] = int(run.upgrades[kind][stat])
			for kind: String in run.offer_ups:
				for stat: String in run.offer_ups[kind]: run.offer_ups[kind][stat] = int(run.offer_ups[kind][stat])
			if not run.get("board") is Array or run.board.size() != 4:
				run.board = Catalog.initial_board(run)
			else:
				for i: int in range(4):
					if not run.board[i] is Dictionary: run.board[i] = Catalog.make_slot("battle",run,i)
					run.board[i].bounty = int(run.board[i].get("bounty",0))
					run.board[i].age = int(run.board[i].get("age",0))
			sync_selected_combat()
		if path != save_path: save_notice = "已從備份恢復進度"
		return
	if FileAccess.file_exists(save_path): save_notice = "進度檔無法讀取，可開始新的一輪"

func valid_run(r: Dictionary) -> bool:
	if not r.get("lord") is String or not B.LORDS.has(r.lord): return false
	if r.has("domestic") and str(r.get("domestic","")) != r.lord: return false
	if not r.get("deck") is Array or not Catalog.deck_allowed(r.deck,r.lord): return false
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
	if not r.get("phase","") in ["map","event","camp","shrine","reward","replace","shop","won","lost"]: return false
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
		if (r.floor < 1 and not r.get("from_event",false)) or not r.get("offer") is Array or r.offer.size() != Catalog.OFFER_SIZE: return false
		var pool: Array = Catalog.card_pool(r.lord)
		for k in r.offer:
			if not k is String or not k in pool or r.offer.count(k) != 1: return false
		if r.phase == "replace" and not r.get("pick","") in r.offer: return false
		var oups = r.get("offer_ups",{})
		if not oups is Dictionary: return false
		for ok in oups:
			if not ok in r.offer or not oups[ok] is Dictionary or Upgrades.level(oups[ok]) > Upgrades.MAX_DROP_LEVEL: return false
	return true

func save_progress() -> bool:
	loaded = true
	var temp := save_path+".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file == null: return save_failed()
	file.store_string(JSON.stringify({"best":best,"clears":clears,"max_contract":max_contract,"cleared_lords":cleared_lords,"run":run}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return save_failed()
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

func begin(lord: String, seed_value: int = -1, contract_level: int = -1) -> void:
	if not B.LORDS.has(lord): return
	confirm_abandon = false
	if seed_value < 0: seed_value = randi() % 1000000
	var c_lv := clampi(contract_level if contract_level >= 0 else pending_contract,0,Catalog.CONTRACTS.size()-1)
	run = {
		"lord":lord,"deck":Catalog.starter_deck(lord,seed_value),
		"floor":0,"foes":Catalog.schedule(seed_value),"seed":seed_value,"phase":"map",
		"offer":[],"offer_ups":{},"offer_rerolls":0,"pick":"","gold":0,"upgrades":{},"relics":[],"shop":[],
		"elite":false,"last_elite":false,"rerolls":0,"contract":c_lv,"draws":0,"march_steps":2,
		"selected_node":0,"board_notice":"命運四選牌陣：點選任一遭遇推進，觸發後僅該格替補新牌（久置或特殊事件將引發牌陣變異）。",
		"last_relic":"","from_event":false,
		"gates":[B.GATE_HP,B.GATE_HP,B.GATE_HP,B.GATE_HP,B.GATE_HP],
		"lord_hp":float(B.lord_data(lord).hp)
	}
	run.elites = Catalog.elite_schedule(seed_value,run.foes)
	run.board = Catalog.initial_board(run)
	sync_selected_combat()
	save_progress()

# ---- 4-slot encounter board management ----------------------------------------------------------

func active_slot() -> Dictionary:
	if run.is_empty() or not run.get("board") is Array or run.board.is_empty(): return {}
	var idx := clampi(int(run.get("selected_node",0)),0,run.board.size()-1)
	return run.board[idx]

func sync_selected_combat() -> void:
	if run.is_empty() or not run.get("board") is Array or run.board.size() != 4: return
	var slot := active_slot()
	if is_boss():
		run.elite = false
	elif slot.get("kind","") == "elite":
		run.elite = true
	elif slot.get("kind","") == "battle":
		run.elite = false

func select_node(index: int) -> void:
	if run.is_empty() or run.phase != "map" or index < 0 or index >= 4: return
	run.selected_node = index
	sync_selected_combat()
	save_progress()

func foe() -> String:
	if run.is_empty(): return "lion"
	if is_boss(): return run.foes[Catalog.FLOORS-1]
	var slot := active_slot()
	if slot.get("kind","") in ["battle","elite"] and not slot.get("foe","").is_empty():
		if (slot.kind == "elite") == bool(run.get("elite",false)):
			return slot.foe
	if run.get("elite",false) and not is_boss(): return run.elites[run.floor]
	return run.foes[run.floor]

# Path choice compatibility (also selects or switches the corresponding board slot).
func set_elite(on: bool) -> void:
	if run.is_empty() or run.phase != "map" or is_boss(): return
	run.elite = on
	if run.get("board") is Array and run.board.size() == 4:
		var target_kind := "elite" if on else "battle"
		var found := -1
		for i: int in range(4):
			if run.board[i].get("kind","") == target_kind:
				found = i
				break
		if found >= 0:
			run.selected_node = found
			run.board[found].foe = run.elites[run.floor] if on else run.foes[run.floor]
		else:
			var idx := clampi(int(run.get("selected_node",0)),0,3)
			run.board[idx] = Catalog.make_slot(target_kind,run,idx)
			run.board[idx].foe = run.elites[run.floor] if on else run.foes[run.floor]
	save_progress()

# Replaces ONLY the triggered slot `idx`, while aging/mutating the other 3 slots on the board.
func consume_board_slot(after_battle: bool, mutation: String = "") -> void:
	if run.is_empty() or not run.get("board") is Array or run.board.size() != 4: return
	var idx := clampi(int(run.get("selected_node",0)),0,3)
	if is_boss() and after_battle:
		run.board = Catalog.boss_board(run)
		run.selected_node = 0
		run.board_notice = "抵達最終王座！四格牌陣已轉換為【魔王決戰】與三項終戰補給。"
		sync_selected_combat()
		return
	if mutation == "all_elite":
		run.board[idx] = Catalog.draw_replacement_slot(run,idx)
		for i: int in range(4):
			if run.board[i].get("kind","") == "battle" and not is_boss():
				run.board[i] = Catalog.make_slot("elite",run,i+10)
				run.board[i].bounty = int(run.board[i].get("bounty",0))+50
			elif run.board[i].get("kind","") == "elite":
				run.board[i].bounty = int(run.board[i].get("bounty",0))+50
		run.board_notice = "烽火強襲！場上所有一般戰鬥已升階為【精英討伐】並附帶 +50 懸賞金。"
	elif mutation == "reroll_plus":
		for i: int in range(4):
			run.board[i] = Catalog.draw_replacement_slot(run,i)
			if run.board[i].get("kind","") in ["battle","elite","boss"]:
				run.board[i].bounty = int(run.board[i].get("bounty",0))+45
		run.board_notice = "斥候改道！四格遭遇已全部重洗，所有戰鬥選項附帶 +45 懸賞金。"
	elif mutation == "board_bounty":
		run.board[idx] = Catalog.draw_replacement_slot(run,idx)
		for i: int in range(4):
			if i != idx and run.board[i].get("kind","") in ["battle","elite","boss"]:
				run.board[i].bounty = int(run.board[i].get("bounty",0))+60
		run.board_notice = "懸賞令張貼完畢！第 %d 格已替補新選項，其餘戰鬥全數附加 +60 懸賞金。" % (idx+1)
	elif mutation == "board_blessing":
		run.board[idx] = Catalog.make_slot("camp",run,idx)
		for i: int in range(4):
			if i != idx:
				if run.board[i].get("kind","") == "event":
					run.board[i] = Catalog.make_slot("shrine",run,i)
				elif run.board[i].get("kind","") in ["battle","elite","boss"]:
					run.board[i].bounty = int(run.board[i].get("bounty",0))+40
		run.board_notice = "泥金禁書改寫命途！場上已湧現營火與秘寶古祠，戰鬥懸賞 +40 金。"
	elif mutation == "transmute_bounty":
		run.board[idx] = Catalog.draw_replacement_slot(run,idx)
		for i: int in range(4):
			if i != idx and not run.board[i].get("kind","") in ["battle","elite","boss"]:
				run.board[i] = Catalog.make_slot("battle",run,i+60)
				run.board[i].bounty = 75
		run.board_notice = "點石成金！其餘非戰鬥格已全部化為附帶 +75 懸賞金的遭遇戰。"
	elif mutation == "sanctuary_board":
		for i: int in range(4):
			run.board[i] = Catalog.draw_replacement_slot(run,i)
		run.board[2] = Catalog.make_slot("camp",run,2)
		run.board[3] = Catalog.make_slot("shrine",run,3)
		run.board_notice = "鏡像聖域展開！全場四格已刷新，並湧現戰地營火與秘寶古祠。"
	elif mutation == "double_bounty":
		run.board[idx] = Catalog.draw_replacement_slot(run,idx)
		for i: int in range(4):
			if run.board[i].get("kind","") in ["battle","elite","boss"]:
				run.board[i].bounty = maxi(60,int(run.board[i].get("bounty",0))*2)
		run.board_notice = "軍令狀生效！場上所有戰鬥遭遇的懸賞金已翻倍（最低 +60 金）。"
	else:
		var notes: Array[String] = ["第 %d 格已替補新遭遇" % (idx+1)]
		var escalated := 0
		var forced_combat := 0
		for i: int in range(4):
			if i == idx: continue
			var s: Dictionary = run.board[i]
			s.age = int(s.get("age",0))+1
			if s.get("kind","") in ["battle","elite","boss"]:
				s.bounty = int(s.get("bounty",0))+(35 if after_battle else 20)
				if after_battle and not is_boss():
					if s.kind == "battle" and s.age >= 2:
						var old_bounty: int = s.bounty
						run.board[i] = Catalog.make_slot("elite",run,i+20)
						run.board[i].bounty = old_bounty
						run.board[i].age = s.age
						escalated += 1
					elif s.kind == "battle" and Catalog.MINIONS.get(s.get("foe",""),{}).get("tier",1) < Catalog.FLOOR_TIER[run.floor]:
						var keep_bounty: int = s.bounty
						var keep_age: int = s.age
						run.board[i] = Catalog.make_slot("battle",run,i+30)
						run.board[i].bounty = keep_bounty
						run.board[i].age = keep_age
			elif not after_battle and int(run.get("march_steps",2)) <= 0:
				var target_k := "boss" if is_boss() else "battle"
				run.board[i] = Catalog.make_slot(target_k,run,i+40)
				run.board[i].bounty = 40
				forced_combat += 1
		run.board[idx] = Catalog.draw_replacement_slot(run,idx)
		if after_battle and not is_boss():
			# Ensure the scheduled floor foe and elite are represented on the board for deterministic access
			var has_normal: bool = run.board.any(func(d: Dictionary) -> bool: return d.get("kind","") == "battle")
			if not has_normal:
				run.board[idx] = Catalog.make_slot("battle",run,idx)
		if escalated > 0: notes.append("%d 處久置敵軍升階為精英" % escalated)
		if forced_combat > 0: notes.append("前鋒逼近，%d 處支援格轉為懸賞戰" % forced_combat)
		else: notes.append("其餘三格保留（戰鬥懸賞增加）")
		run.board_notice = " · ".join(notes)+"。"
	# Select a combat slot by default if available
	if not run.board[idx].get("kind","") in ["battle","elite","boss"]:
		for i: int in range(4):
			if run.board[i].get("kind","") in ["battle","elite","boss"]:
				run.selected_node = i
				break
	sync_selected_combat()

func board_reroll_error() -> String:
	if run.is_empty() or run.phase != "map": return "現在不能換陣"
	if run.gold < Catalog.BOARD_REROLL_PRICE: return "金幣不足"
	return ""

func reroll_board() -> void:
	if not board_reroll_error().is_empty(): return
	run.gold -= Catalog.BOARD_REROLL_PRICE
	for i: int in range(4):
		run.board[i] = Catalog.draw_replacement_slot(run,i)
		if run.board[i].get("kind","") in ["battle","elite","boss"]:
			run.board[i].bounty = 25
	run.board_notice = "斥候探路完成！四個遭遇選項已全部換新，戰鬥附帶 +25 懸賞金。"
	sync_selected_combat()
	save_progress()

func trigger_node(game = null) -> void:
	if run.is_empty() or run.phase != "map": return
	var slot := active_slot()
	var k: String = slot.get("kind","battle")
	if k in ["battle","elite","boss"]:
		sync_selected_combat()
		if game != null: start_battle(game)
	elif k == "event":
		if slot.get("event_id","").is_empty() or not Catalog.EVENTS.has(slot.event_id):
			slot.event_id = Catalog.EVENTS.keys()[0]
		run.phase = "event"
		save_progress()
	elif k == "camp":
		camp_card_index = 0
		camp_stat = ""
		run.phase = "camp"
		save_progress()
	elif k == "shrine":
		camp_card_index = 0
		camp_stat = ""
		run.phase = "shrine"
		save_progress()

# ---- non-combat encounters: camp, shrine, manuscript events -------------------------------------

func has_targeted_upgrade() -> bool:
	return not run.is_empty() and bool(Catalog.side_mods(run.get("lord",""),run.get("relics",[])).get("targeted_upgrade",false))

func targeted_relic_name() -> String:
	for r: Variant in run.get("relics",[]):
		var k := str(r)
		if Catalog.RELICS.get(k,{}).get("mods",{}).get("targeted_upgrade",false):
			return Catalog.RELICS[k].name
	return Catalog.RELICS.artisan_blueprint.name

func roll_upgrade_stat(kind: String, opts: Array, ups: Dictionary, salt: int = 0) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run.get("seed",1))*7+int(run.get("floor",0))*131+int(run.get("draws",0))*23+Upgrades.level(ups)*17+hash(kind)+salt
	return opts[rng.randi_range(0,opts.size()-1)]

func apply_card_upgrade(kind: String, preferred_stat: String = "", salt: int = 0) -> String:
	var ups: Dictionary = run.upgrades.get(kind,{}).duplicate()
	var opts: Array = Upgrades.options(kind,ups)
	if opts.is_empty(): return ""
	var stat := ""
	if has_targeted_upgrade():
		var pick_st := preferred_stat if not preferred_stat.is_empty() else str(shop_stats.get(kind,""))
		stat = pick_st if pick_st in opts else opts[0]
	else:
		stat = roll_upgrade_stat(kind,opts,ups,salt)
	ups[stat] = int(ups.get(stat,0))+1
	run.upgrades[kind] = ups
	return stat

func upgrade_random_cards(count: int) -> int:
	var done := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run.get("seed",1))*113+int(run.get("draws",0))*71+int(run.get("floor",0))*19
	for _step: int in range(count):
		var candidates: Array = []
		for k: String in run.deck:
			if not k in candidates and Upgrades.can_upgrade(k,run.upgrades.get(k,{})):
				candidates.append(k)
		if candidates.is_empty(): break
		var kind: String = candidates[rng.randi_range(0,candidates.size()-1)]
		var ups: Dictionary = run.upgrades.get(kind,{}).duplicate()
		var opts: Array = Upgrades.options(kind,ups)
		if opts.is_empty(): continue
		var st: String = opts[rng.randi_range(0,opts.size()-1)]
		ups[st] = int(ups.get(st,0))+1
		run.upgrades[kind] = ups
		done += 1
	return done

func mend_by_share(gate_share: float, lord_share: float) -> void:
	if gate_share > 0.0:
		run.gates = run.gates.map(func(hp: float) -> float: return minf(B.GATE_HP,hp+(B.GATE_HP-hp)*gate_share))
	if lord_share > 0.0:
		run.lord_hp = minf(lord_max_hp(),float(run.get("lord_hp",lord_max_hp()))+lord_max_hp()*lord_share)

func grant_free_relic(max_price: int = 600) -> String:
	var r_id := Catalog.pick_free_relic(int(run.get("seed",1)),int(run.get("draws",0))+int(run.get("floor",0))*7,run.relics,max_price)
	if r_id.is_empty():
		run.gold += 140
		return ""
	run.relics.append(r_id)
	run.last_relic = r_id
	return r_id

func camp_action(choice: int) -> void:
	if run.is_empty() or run.phase != "camp": return
	run.march_steps = maxi(0,int(run.get("march_steps",2))-1)
	if choice == 0: # 休整築牆
		mend_by_share(0.45,0.50)
	elif choice == 1: # 名匠鍛造（預設隨機屬性 +1；持指定遺物可自選）
		var idx := clampi(camp_card_index,0,run.deck.size()-1)
		var kind: String = run.deck[idx]
		if apply_card_upgrade(kind,camp_stat,11).is_empty():
			upgrade_random_cards(1)
	elif choice == 2: # 軍資徵集
		run.gold += 120
		if upgrade_random_cards(1) == 0: run.gold += 40
	run.phase = "map"
	consume_board_slot(false)
	save_progress()

func shrine_action(choice: int) -> void:
	if run.is_empty() or run.phase != "shrine": return
	run.march_steps = maxi(0,int(run.get("march_steps",2))-1)
	if choice == 0: # 開啟聖物匣
		grant_free_relic(600)
	elif choice == 1: # 精煉主力（預設隨機屬性 +1；持指定遺物可自選）
		var idx := clampi(camp_card_index,0,run.deck.size()-1)
		var kind: String = run.deck[idx]
		if apply_card_upgrade(kind,camp_stat,29).is_empty():
			upgrade_random_cards(1)
		run.gold += 70
	elif choice == 2: # 鮮血奉獻
		run.lord_hp = maxf(1.0,float(run.get("lord_hp",lord_max_hp()))*0.75)
		run.gold += 200
		upgrade_random_cards(1)
	run.phase = "map"
	consume_board_slot(false)
	save_progress()

func event_choice_error(choice_index: int) -> String:
	if run.is_empty() or run.phase != "event": return "現在不能選擇"
	var ev_id: String = active_slot().get("event_id","wandering_smith")
	var ev: Dictionary = Catalog.EVENTS.get(ev_id,Catalog.EVENTS.wandering_smith)
	if choice_index < 0 or choice_index >= ev.choices.size(): return "選項無效"
	var cost: int = int(ev.choices[choice_index].get("cost",0))
	if run.gold < cost: return "金幣不足（需 %d 金）" % cost
	return ""

func event_action(choice_index: int) -> void:
	if not event_choice_error(choice_index).is_empty(): return
	var ev_id: String = active_slot().get("event_id","wandering_smith")
	var ev: Dictionary = Catalog.EVENTS.get(ev_id,Catalog.EVENTS.wandering_smith)
	var choice: Dictionary = ev.choices[choice_index]
	run.gold -= int(choice.get("cost",0))
	run.march_steps = maxi(0,int(run.get("march_steps",2))-1)
	var eff: String = choice.get("effect","")
	var mutation := ""
	var open_draft := false
	match eff:
		"upgrade_2": upgrade_random_cards(2)
		"gold_and_up":
			run.gold += 110
			upgrade_random_cards(1)
		"mend_both": mend_by_share(0.35,0.30)
		"board_bounty":
			run.gold += 70
			mutation = "board_bounty"
		"draft_plus":
			upgrade_random_cards(1)
			open_draft = true
		"free_relic_low": grant_free_relic(200)
		"blood_relic":
			run.lord_hp = maxf(1.0,float(run.get("lord_hp",lord_max_hp()))*0.70)
			grant_free_relic(600)
		"wall_gold":
			run.gates = run.gates.map(func(hp: float) -> float: return maxf(50.0,hp*0.85))
			run.gold += 200
			upgrade_random_cards(1)
		"cleanse_altar":
			mend_by_share(0.0,0.45)
			run.gold += 90
		"board_all_elite":
			run.gold += 80
			mutation = "all_elite"
		"board_reroll_plus":
			run.gold += 45
			mutation = "reroll_plus"
		"tower_rest":
			mend_by_share(0.30,0.40)
			run.gold += 70
		"caravan_gold":
			run.gold += 160
			mend_by_share(0.20,0.0)
		"caravan_relic": grant_free_relic(400)
		"upgrade_2_free": upgrade_random_cards(2)
		"focus_up_2":
			for k: String in run.deck:
				if Upgrades.can_upgrade(k,run.upgrades.get(k,{})):
					for _n: int in range(2):
						var u: Dictionary = run.upgrades.get(k,{}).duplicate()
						var o: Array = Upgrades.options(k,u)
						if not o.is_empty():
							var st := roll_upgrade_stat(k,o,u,41+_n)
							u[st] = int(u.get(st,0))+1
							run.upgrades[k] = u
					break
		"board_blessing":
			run.gold += 80
			mutation = "board_blessing"
		"sell_book": run.gold += 135
		"full_walls":
			mend_by_share(1.0,0.0)
			upgrade_random_cards(1)
		"full_lord":
			mend_by_share(0.25,1.0)
			run.gold += 60
		"guild_gold": run.gold += 140
		"free_draft":
			run.gold += 80
			open_draft = true
		"armory_up":
			upgrade_random_cards(2)
			run.gold += 60
		"reset_march":
			run.gold += 150
			run.march_steps = 2
		"transmute_bounty":
			run.gold += 90
			mutation = "transmute_bounty"
		"elixir_up":
			mend_by_share(0.0,1.0)
			upgrade_random_cards(2)
		"sell_vials": run.gold += 130
		"mirror_upgrade":
			var best_k := ""
			var best_lv := -1
			for k: String in run.deck:
				var lv := Upgrades.level(run.upgrades.get(k,{}))
				if Upgrades.can_upgrade(k,run.upgrades.get(k,{})) and lv > best_lv:
					best_lv = lv
					best_k = k
			if not best_k.is_empty():
				var u: Dictionary = run.upgrades.get(best_k,{}).duplicate()
				var o: Array = Upgrades.options(best_k,u)
				if not o.is_empty():
					var st := roll_upgrade_stat(best_k,o,u,59)
					u[st] = int(u.get(st,0))+1
					run.upgrades[best_k] = u
			upgrade_random_cards(1)
		"sanctuary_board":
			run.gold += 65
			mutation = "sanctuary_board"
		"arcane_mend":
			run.gold += 125
			mend_by_share(0.25,0.0)
		"double_bounty":
			run.gold += 80
			mutation = "double_bounty"
		"fortify_up":
			mend_by_share(0.50,0.0)
			upgrade_random_cards(1)
		"buy_high_relic":
			var high_pool: Array = Catalog.RELICS.keys().filter(func(k: String) -> bool: return not k in run.relics and Catalog.RELICS[k].price == 600)
			high_pool.sort()
			if not high_pool.is_empty():
				var rng := RandomNumberGenerator.new()
				rng.seed = int(run.get("seed",1))*97+int(run.get("draws",0))*31
				var picked: String = high_pool[rng.randi_range(0,high_pool.size()-1)]
				run.relics.append(picked)
				run.last_relic = picked
			else:
				grant_free_relic(600)
		"bazaar_gold": run.gold += 155
	consume_board_slot(false,mutation)
	if open_draft:
		run.offer = Catalog.offer(run.lord,run.seed+run.draws*97,run.floor,run.deck)
		run.last_elite = false
		run.offer_rerolls = 0
		roll_offer_ups(true)
		run.from_event = true
		run.phase = "reward"
	else:
		run.phase = "map"
	save_progress()

# ---- economy, wounds & rewards ------------------------------------------------------------------

func win_gold(floor_index: int, elite: bool) -> int:
	var base: float = Catalog.gold_for(floor_index)*(Catalog.ELITE_GOLD_MULT if elite else 1.0)
	var c_mult: float = Catalog.CONTRACTS[clampi(int(run.get("contract",0)),0,Catalog.CONTRACTS.size()-1)].gold_mult if not run.is_empty() else 1.0
	var r_bonus: float = 1.0+float(Catalog.side_mods(run.lord,run.relics).get("gold_bonus",0.0)) if not run.is_empty() else 1.0
	return roundi(base*c_mult*r_bonus)

func lord_max_hp() -> float:
	var base := float(B.lord_data(run.get("lord","lion")).hp)
	if run.is_empty() or not run.has("lord"): return base
	var boost := int(Catalog.side_mods(run.lord,run.get("relics",[])).get("lord_boost",0))
	return Upgrades.shifted("hp",base,boost) if boost > 0 else base

func record_wounds(m) -> void:
	if run.is_empty(): return
	run.gates = m.gates[0].duplicate()
	var lord: Dictionary = m.lords[0] if not m.lords.is_empty() else {}
	run.lord_hp = maxf(1.0,lord.hp) if not lord.is_empty() and lord.hp > 0 else lord_max_hp()*Catalog.FALLEN_LORD_SHARE
	var post: Dictionary = Catalog.side_mods(run.lord,run.relics).get("post_heal",{})
	if not post.is_empty():
		var g_heal := float(post.get("gate",0.0))
		var l_heal := float(post.get("lord",0.0))
		if g_heal > 0: run.gates = run.gates.map(func(hp: float) -> float: return minf(B.GATE_HP,hp+g_heal) if hp > 0 else minf(B.GATE_HP,g_heal*0.5))
		if l_heal > 0: run.lord_hp = minf(lord_max_hp(),run.lord_hp+l_heal)

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
	return int(run.get("floor",0)) == Catalog.FLOORS-1

func settle(won: bool) -> void:
	if run.is_empty() or run.phase != "map": return
	if won:
		best = maxi(best,run.floor+1)
		if is_boss():
			run.phase = "won"
			clears += 1
			max_contract = maxi(max_contract,int(run.get("contract",0)))
			if not run.lord in cleared_lords: cleared_lords.append(run.lord)
			outcome = "肉鴿通關！八場全勝（%s）" % Catalog.CONTRACTS[clampi(int(run.get("contract",0)),0,Catalog.CONTRACTS.size()-1)].name
		else:
			var elite: bool = run.get("elite",false)
			var bounty: int = int(active_slot().get("bounty",0))
			var gold := win_gold(run.floor,elite)+bounty
			run.gold += gold
			var prize_note := ""
			run.last_relic = ""
			if elite:
				var dropped := grant_free_relic(600)
				if not dropped.is_empty():
					prize_note = " · 奪得遺物【%s】" % Catalog.RELICS[dropped].name
			run.offer = Catalog.offer(run.lord,run.seed,run.floor,run.deck)
			run.floor += 1
			run.last_elite = elite
			run.offer_rerolls = 0
			roll_offer_ups(false)
			run.march_steps = 2
			run.from_event = false
			run.elite = false
			consume_board_slot(true)
			run.phase = "reward"
			outcome = "第 %d 場%s勝利！獲得 %d 金幣%s" % [run.floor,"精英" if elite else "",gold,prize_note]
	else:
		run.phase = "lost"
		outcome = "敗北：本輪止步第 %d 場" % (run.floor+1)
	save_progress()

func roll_offer_ups(from_event: bool = false) -> void:
	var oups := {}
	if run.is_empty():
		return
	var fl := int(run.get("floor",0))
	var el := bool(run.get("last_elite",false))
	var ct := int(run.get("contract",0))
	var rcount: int = run.get("relics",[]).size()
	var bp := has_targeted_upgrade()
	var rr := int(run.get("offer_rerolls",0))
	for k: String in run.get("offer",[]):
		var info := Upgrades.drop_chance_info(run.lord,k,fl,el,ct,rcount,bp,from_event,rr)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(run.get("seed",1))*193+fl*1009+int(run.get("draws",0))*53+rr*71+hash(k)
		var bonus := Upgrades.roll_drop_upgrades(k,float(info.chance),rng)
		if not bonus.is_empty():
			oups[k] = bonus
	run.offer_ups = oups

func finish_draft() -> void:
	var from_ev: bool = bool(run.get("from_event",false))
	run.pick = ""
	run.offer = []
	run.offer_ups = {}
	run.offer_rerolls = 0
	run.from_event = false
	if from_ev:
		run.phase = "map"
		save_progress()
	else:
		open_shop()

func pick(kind: String) -> void:
	if run.is_empty() or run.phase != "reward" or not kind in run.offer: return
	selected_slot = -1
	run.pick = kind
	run.phase = "replace"
	save_progress()

func replace(slot: int) -> void:
	if run.is_empty() or run.phase != "replace" or slot < 0 or slot >= run.deck.size() or not run.pick in run.offer: return
	run.deck[slot] = run.pick
	var bonus: Dictionary = run.get("offer_ups",{}).get(run.pick,{})
	if not bonus.is_empty():
		run.upgrades[run.pick] = Upgrades.merge_upgrades(run.pick,run.upgrades.get(run.pick,{}),bonus)
	finish_draft()

func skip_reward() -> void:
	if run.is_empty() or not run.phase in ["reward","replace"]: return
	run.gold += Catalog.SKIP_REWARD_GOLD
	finish_draft()

func offer_reroll_error() -> String:
	if run.is_empty() or run.phase != "reward": return "現在不能重抽"
	if run.gold < Catalog.OFFER_REROLL_PRICE: return "金幣不足"
	return ""

func reroll_offer() -> void:
	if not offer_reroll_error().is_empty(): return
	run.gold -= Catalog.OFFER_REROLL_PRICE
	run.draws = int(run.get("draws",0))+1
	run.offer_rerolls = int(run.get("offer_rerolls",0))+1
	run.offer = Catalog.offer(run.lord,run.seed+run.draws*311,run.floor,run.deck)
	roll_offer_ups(bool(run.get("from_event",false)))
	save_progress()

# ---- shop: gold buys run-long card upgrades (targeted or seeded) and relics ---------------------

func open_shop() -> void:
	if run.is_empty() or not run.phase in ["map","reward","replace"]: return
	if run.phase != "map" or run.shop.is_empty(): run.shop = Catalog.relic_offer(run.seed,run.floor,run.relics)
	run.phase = "shop"
	save_progress()

func leave_shop() -> void:
	if run.is_empty() or run.phase != "shop": return
	run.phase = "map"
	save_progress()

func upgrade_error(kind: String) -> String:
	if run.is_empty() or run.phase != "shop" or not kind in run.deck: return "現在不能強化"
	var ups: Dictionary = run.upgrades.get(kind,{})
	if Upgrades.level(ups) >= Upgrades.MAX_LEVEL: return "已達 +%d" % Upgrades.MAX_LEVEL
	if Upgrades.options(kind,ups).is_empty(): return "沒有可強化的能力"
	if run.gold < Upgrades.price(ups): return "金幣不足"
	return ""

func upgrade(kind: String, chosen_stat: String = "") -> void:
	if not upgrade_error(kind).is_empty(): return
	var cost := Upgrades.price(run.upgrades.get(kind,{}))
	if apply_card_upgrade(kind,chosen_stat).is_empty(): return
	run.gold -= cost
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

# ---- battles ------------------------------------------------------------------------------------

func battle_floor_number() -> int:
	if run.is_empty(): return 1
	return int(run.get("last_battle_floor",run.get("floor",0)))+1

func make_battle() -> Battle:
	var enemy := foe()
	run.last_battle_floor = run.floor
	var m := Battle.new(run.seed+run.floor*7919,run.deck.duplicate(),Catalog.foe_deck(enemy),run.lord,enemy)
	m.apply_domestic(0,B.home_card(run.lord),Catalog.side_mods(run.lord,run.relics))
	m.card_upgrades[0] = run.upgrades.duplicate(true)
	m.gates[0] = run.get("gates",m.gates[0]).duplicate()
	m.lords[0].hp = minf(m.lords[0].max_hp,run.get("lord_hp",m.lords[0].max_hp))
	m.refresh_territory()
	var boss := is_boss()
	var c_data: Dictionary = Catalog.CONTRACTS[clampi(int(run.get("contract",0)),0,Catalog.CONTRACTS.size()-1)]
	var base_enemy_ink: float = Catalog.BOSS_START_INK if boss else (Catalog.ELITE_START_INK if run.get("elite",false) else Catalog.ENEMY_START_INK)
	m.ink[1] = minf(B.MAX_INK,base_enemy_ink+float(c_data.get("enemy_ink",0.0)))
	m.difficulty = clampi(Catalog.AI_LEVEL[run.floor]+int(c_data.get("ai_boost",0)),0,2)
	var enemy_scale: float = Catalog.enemy_floor_scale(run.floor)
	var enemy_mods: Dictionary = {}
	if c_data.get("enemy_toughen",false) or boss:
		enemy_mods["toughen"] = ["*"]
	if boss:
		enemy_mods["haste"] = ["*"]
		enemy_mods["skill_discount"] = 15.0
		var b_lord: Dictionary = m.lords[1]
		b_lord.max_hp = Upgrades.shifted("hp",b_lord.max_hp,Catalog.BOSS_LORD_BOOST,0)
		b_lord.hp = b_lord.max_hp
		b_lord.damage = Upgrades.shifted("damage",b_lord.damage,Catalog.BOSS_LORD_BOOST,0)
		var boss_ups := {}
		var boss_lv := Catalog.BOSS_CARD_UPGRADES + (1 if c_data.get("enemy_toughen",false) else 0)
		var brng := RandomNumberGenerator.new()
		brng.seed = int(run.get("seed",1))*313+hash(enemy)
		for ck: String in m.decks[1]:
			if not boss_ups.has(ck):
				boss_ups[ck] = Upgrades.roll_fixed_upgrades(ck,boss_lv,brng)
		m.card_upgrades[1] = boss_ups
	if enemy_scale > 1.0:
		enemy_mods["gold_gain_mult"] = enemy_scale
		enemy_mods["cd_speed_mult"] = enemy_scale
	var mut := Catalog.mutator_data(active_slot())
	if mut.has("mods"):
		enemy_mods = Catalog.merge_mods(enemy_mods,mut.mods)
	if not enemy_mods.is_empty():
		m.team_mods[1] = enemy_mods
	if not mut.is_empty():
		m.apply_field_mutator(mut)
	m.ai_enabled = [false,true]
	m.night_decay = false
	return m

func start_battle(game) -> void:
	game.spectating = false
	game.adventure.index = -1
	game.model = make_battle()
	in_battle = true
	outcome = ""
	var c_name: String = Catalog.CONTRACTS[clampi(int(run.get("contract",0)),0,Catalog.CONTRACTS.size()-1)].name
	var enemy_scale: float = Catalog.enemy_floor_scale(run.floor)
	var scale_tag: String = (" · 敵軍金幣／冷卻 ×%.2f" % enemy_scale) if enemy_scale > 1.0 else ""
	var mut := Catalog.mutator_data(active_slot())
	var mut_tag: String = (" · 【%s】%s" % [mut.name,mut.desc]) if not mut.is_empty() else ""
	game.enter_battle("肉鴿 第 %d / %d 場（%s）· 對手：%s%s%s" % [run.floor+1,Catalog.FLOORS,c_name,B.lord_name(foe()),scale_tag,mut_tag])

func update(game) -> void:
	if not in_battle or not outcome.is_empty() or game.model.paused: return
	time_limit(game.model)
	if game.model.ended:
		if game.model.winner == 0: record_wounds(game.model)
		settle(game.model.winner == 0)

static func time_limit(m) -> void:
	if m.ended or m.elapsed < Catalog.TIME_LIMIT: return
	var mine: float = 0.0
	var theirs: float = 0.0
	for hp: float in m.gates[0]: mine += hp
	for hp: float in m.gates[1]: theirs += hp
	m.finish(0 if mine > theirs else 1)

func leave_battle(game) -> void:
	if in_battle and outcome.is_empty(): settle(false)
	in_battle = false
	show(game)

# ---- screens & interactive UI -------------------------------------------------------------------

func show(game) -> void:
	if not loaded: load_progress()
	in_battle = false
	game.screen = "rogue"
	game.clear_ui()
	var current: String = run.get("phase",phase) if not run.is_empty() else phase
	match current:
		"lord":
			var lords: Array = B.lord_menu_order()
			for i: int in range(lords.size()):
				var lord: String = lords[i]
				var choice := hit(game,lord_rect(i),func():
					pending_lord = lord
					pending_seed = randi() % 1000000
					phase = "confirm"
					show(game))
				choice.tooltip_text = role_text(lord)
		"confirm":
			for c_idx: int in range(Catalog.CONTRACTS.size()):
				var lv := c_idx
				var cb: Button = game.title_button(Rect2(110+c_idx*170,735,160,42),"契約 %d：%s" % [c_idx,Catalog.CONTRACTS[c_idx].name],func(): pending_contract = lv; show(game),pending_contract == c_idx)
				cb.add_theme_font_size_override("font_size",15)
				cb.tooltip_text = Catalog.CONTRACTS[c_idx].desc
			game.title_button(Rect2(860,620,240,46),"重抽起手牌組",func(): pending_seed = randi() % 1000000; show(game))
			game.title_button(Rect2(1180,800,300,56),"出發征討",func(): begin(pending_lord,pending_seed,pending_contract); show(game),true)
			game.title_button(Rect2(100,820,230,46),"重選領主",func(): phase = "lord"; show(game))
		"map":
			for i: int in range(4):
				var idx := i
				var r := board_slot_rect(i)
				var b := hit(game,r,func():
					if int(run.get("selected_node",0)) == idx:
						trigger_node(game)
						if not in_battle: show(game)
					else:
						select_node(idx)
						show(game))
				b.tooltip_text = slot_tooltip(run.board[i])+"\n（點選查看詳情，再點一次或按右下按鈕立即執行）"
			var sel := active_slot()
			var act_label := "出戰：%s" % B.lord_name(foe()) if sel.get("kind","") in ["battle","elite","boss"] else "進入：%s" % slot_title(sel)
			game.title_button(Rect2(1180,800,320,56),act_label,func():
				trigger_node(game)
				if not in_battle: show(game),true)
			var rw_err := board_reroll_error()
			var rw_btn: Button = game.title_button(Rect2(360,808,240,46),("斥候換陣（%d 金）" % Catalog.BOARD_REROLL_PRICE) if rw_err.is_empty() else rw_err,func(): reroll_board(); show(game))
			rw_btn.disabled = not rw_err.is_empty()
			rw_btn.tooltip_text = "花費 %d 金幣刷新全部 4 個遭遇選項，並為新戰鬥附加 +25 懸賞金" % Catalog.BOARD_REROLL_PRICE
			game.title_button(Rect2(620,808,250,46),"軍需商店（%d 金）" % run.gold,func(): open_shop(); show(game))
			game.title_button(Rect2(890,808,260,46),"確定放棄這輪？" if confirm_abandon else "放棄這輪",func():
				if confirm_abandon: abandon()
				else: confirm_abandon = true
				show(game))
		"camp", "shrine":
			var is_camp_phase := current == "camp"
			for i: int in range(run.deck.size()):
				var d_idx := i
				var r := Rect2(130+(i%4)*155,360+(i/4)*155,142,142)
				var b := hit(game,r,func(): camp_card_index = d_idx; camp_stat = ""; show(game))
				b.tooltip_text = desc(run.deck[i])
			var target_kind: String = run.deck[clampi(camp_card_index,0,run.deck.size()-1)]
			var opts: Array = Upgrades.options(target_kind,run.upgrades.get(target_kind,{}))
			var targeted := has_targeted_upgrade()
			if targeted:
				for s_i: int in range(opts.size()):
					var st: String = opts[s_i]
					var sb: Button = game.title_button(Rect2(106+s_i*108,685,102,38),"鍛造"+Upgrades.NAMES.get(st,st),func(): camp_stat = st; show(game),camp_stat == st or (camp_stat.is_empty() and s_i == 0))
					sb.add_theme_font_size_override("font_size",14)
			var forge_name: String = B.CARDS[target_kind].name
			var forge_st: String = Upgrades.NAMES.get(camp_stat if camp_stat in opts else (opts[0] if not opts.is_empty() else ""),"隨機")
			if is_camp_phase:
				game.title_button(Rect2(830,330,630,90),"【休整築牆】城牆修復 45% 缺失血量 · 領主回復 50% 生命",func(): camp_action(0); show(game))
				var camp_label := "【名匠鍛造】免費強化「%s」的【%s】+1 階" % [forge_name,forge_st] if (targeted and not opts.is_empty()) else "【名匠鍛造】免費隨機強化「%s」一項屬性 +1 階" % forge_name
				game.title_button(Rect2(830,450,630,90),camp_label,func(): camp_action(1); show(game),true)
				game.title_button(Rect2(830,570,630,90),"【軍資徵集】獲得 120 金幣，並隨機強化 1 張卡牌 +1",func(): camp_action(2); show(game))
			else:
				game.title_button(Rect2(830,330,630,90),"【開啟聖物匣】免費獲得 1 件未持有的遺物",func(): shrine_action(0); show(game),true)
				var shrine_label := "【精煉主力】強化「%s」的【%s】+1 階，並獲得 70 金幣" % [forge_name,forge_st] if (targeted and not opts.is_empty()) else "【精煉主力】隨機強化「%s」一項屬性 +1 階，並獲得 70 金幣" % forge_name
				game.title_button(Rect2(830,450,630,90),shrine_label,func(): shrine_action(1); show(game))
				game.title_button(Rect2(830,570,630,90),"【鮮血奉獻】領主損耗 25% 生命，換取 200 金幣與隨機 1 卡 +1",func(): shrine_action(2); show(game))
		"event":
			var ev_id: String = active_slot().get("event_id","wandering_smith")
			var ev: Dictionary = Catalog.EVENTS.get(ev_id,Catalog.EVENTS.wandering_smith)
			for i: int in range(ev.choices.size()):
				var c_idx := i
				var ch: Dictionary = ev.choices[i]
				var why := event_choice_error(i)
				var label: String = "【%s】%s" % [ch.label,ch.desc if why.is_empty() else why]
				var eb: Button = game.title_button(Rect2(620,340+i*125,860,96),label,func(): event_action(c_idx); show(game),i == 0 and why.is_empty())
				eb.disabled = not why.is_empty()
				eb.add_theme_font_size_override("font_size",18)
		"reward":
			var detail = game.library.text_box(Rect2(1170,280,345,420),desc(run.offer[0]),19)
			game.library.text_box(Rect2(120,660,990,90),"目前牌組："+"、".join(run.deck.map(func(k: String) -> String: return B.CARDS[k].name)),18)
			for i: int in range(run.offer.size()):
				var kind: String = run.offer[i]
				var choice := hit(game,offer_rect(i),func(): pick(kind); show(game))
				choice.tooltip_text = desc(kind)
				choice.mouse_entered.connect(func(): detail.text = desc(kind))
				choice.focus_entered.connect(func(): detail.text = desc(kind))
			var or_err := offer_reroll_error()
			var or_btn: Button = game.title_button(Rect2(400,800,260,48),("換一批候選（%d 金）" % Catalog.OFFER_REROLL_PRICE) if or_err.is_empty() else or_err,func(): reroll_offer(); show(game))
			or_btn.disabled = not or_err.is_empty()
			game.title_button(Rect2(680,800,280,48),"略過換卡（+%d 金）" % Catalog.SKIP_REWARD_GOLD,func(): skip_reward(); show(game))
		"replace":
			for i: int in range(8):
				var slot := i
				var choice := hit(game,deck_rect(i),func(): selected_slot = slot; show(game))
				choice.tooltip_text = desc(run.deck[i])
			game.title_button(Rect2(680,800,240,48),"重新挑卡",func(): run.phase = "reward"; save_progress(); show(game))
			game.library.text_box(Rect2(100,190,1400,115),desc(run.pick),19)
			if selected_slot >= 0:
				game.title_button(Rect2(1000,800,320,48),"確認替換："+B.CARDS[run.deck[selected_slot]].name,func(): replace(selected_slot); show(game),true)
		"shop":
			var kinds := shop_kinds()
			var targeted := has_targeted_upgrade()
			for i: int in range(kinds.size()):
				var kind: String = kinds[i]
				var ups: Dictionary = run.upgrades.get(kind,{})
				var opts: Array = Upgrades.options(kind,ups)
				var cur_stat: String = str(shop_stats.get(kind,opts[0] if not opts.is_empty() else ""))
				if not cur_stat in opts and not opts.is_empty():
					cur_stat = opts[0]
					shop_stats[kind] = cur_stat
				var r := upgrade_rect(i)
				if targeted and opts.size() > 1:
					var cycle_btn: Button = game.title_button(Rect2(r.position+Vector2(10,r.size.y-80),Vector2(r.size.x-20,30)),"切換屬性："+Upgrades.NAMES.get(cur_stat,cur_stat),func():
						var next_idx := (opts.find(cur_stat)+1) % opts.size()
						shop_stats[kind] = opts[next_idx]
						show(game))
					cycle_btn.add_theme_font_size_override("font_size",14)
					cycle_btn.tooltip_text = "點選切換要強化的屬性（可選：%s）" % "、".join(opts.map(func(s: String) -> String: return Upgrades.NAMES.get(s,s)))
				var why := upgrade_error(kind)
				var label := ""
				if not why.is_empty(): label = why
				elif targeted: label = "強化%s %d金" % [Upgrades.NAMES.get(cur_stat,"") if not cur_stat.is_empty() else "",Upgrades.price(ups)]
				else: label = "隨機強化 %d金" % Upgrades.price(ups)
				var chosen_for_btn := cur_stat if targeted else ""
				var b: Button = game.title_button(Rect2(r.position+Vector2(8,r.size.y-44),Vector2(r.size.x-16,36)),label,func(): upgrade(kind,chosen_for_btn); show(game))
				b.disabled = not why.is_empty()
				b.add_theme_font_size_override("font_size",15)
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
			game.title_button(Rect2(1180,800,300,56),"返回命運牌陣",func(): leave_shop(); show(game),true)
		"won", "lost":
			game.title_button(Rect2(680,640,240,56),"新的一輪",func(): abandon(); show(game),true)
	game.title_button(Rect2(350,820,230,46) if current == "confirm" else Rect2(100,808,230,46),"返回標題",game.show_title)
	if current == "confirm":
		deck_tooltips(game,Catalog.starter_deck(pending_lord,pending_seed),Vector2(860,300))
	if current == "map":
		var sel := active_slot()
		if sel.get("kind","") in ["battle","elite","boss"]:
			deck_tooltips(game,Catalog.foe_deck(foe()),Vector2(1010,352))
		deck_tooltips(game,run.deck,Vector2(1010,574))
		var r_tip_lines: Array[String] = []
		for rk: String in run.get("relics",[]):
			var rd: Dictionary = Catalog.RELICS[rk]
			r_tip_lines.append("【%s】%s" % [rd.name,B.passive_text(rd.mods)])
		var r_hit := hit(game,Rect2(883,704,124,80),func(): pass)
		r_hit.tooltip_text = "\n".join(r_tip_lines) if not r_tip_lines.is_empty() else "尚未持有遺物（可於商店購買或自精英／古祠取得）"
	game.queue_redraw()

# ---- descriptions & layout helpers --------------------------------------------------------------

func slot_title(slot: Dictionary) -> String:
	match slot.get("kind","battle"):
		"boss": return "魔王決戰："+B.lord_name(slot.get("foe",foe()))
		"elite": return "精英討伐："+B.lord_name(slot.get("foe",foe()))
		"battle": return "一般遭遇："+B.lord_name(slot.get("foe",foe()))
		"camp": return "戰地營火"
		"shrine": return "秘寶古祠"
		"event":
			var ev_id: String = slot.get("event_id","wandering_smith")
			return Catalog.EVENTS.get(ev_id,Catalog.EVENTS.wandering_smith).name
	return "未知遭遇"

func slot_subtitle(slot: Dictionary) -> String:
	var bounty: int = int(slot.get("bounty",0))
	var b_tag: String = (" ＋懸賞 %d 金" % bounty) if bounty > 0 else ""
	var mut := Catalog.mutator_data(slot)
	var m_tag := (" · 【%s】" % String(mut.name)) if not mut.is_empty() else ""
	match slot.get("kind","battle"):
		"boss": return "第八層魔王決戰%s" % m_tag
		"elite": return "賞金 %d 金%s · 掉遺物%s" % [win_gold(run.floor,true),b_tag,m_tag]
		"battle":
			var age_tag := " · 久置將升階" if int(slot.get("age",0)) >= 1 else ""
			return "賞金 %d 金%s%s" % [win_gold(run.floor,false),b_tag,age_tag]
		"camp": return "免費修牆療傷 ／ 鍛造強化卡牌 ／ 徵集軍資"
		"shrine": return "免費聖物匣 ／ 精煉主力卡牌 ／ 鮮血奉獻"
		"event": return "手抄本奇遇抉擇 · 可強化或改變牌陣"
	return ""

func slot_tooltip(slot: Dictionary) -> String:
	var k: String = slot.get("kind","battle")
	if k in ["battle","elite","boss"]:
		var f: String = slot.get("foe",foe())
		var rule: String = ("被動："+B.minion_text(f)) if B.is_minion(f) else B.skill_text(f)
		var mut := Catalog.mutator_data(slot)
		var m_line := ("\n戰場異變【%s】：%s" % [String(mut.name),String(mut.desc)]) if not mut.is_empty() else ""
		return "%s\n%s\n%s%s" % [slot_title(slot),slot_subtitle(slot),rule,m_line]
	if k == "event":
		var ev_id: String = slot.get("event_id","wandering_smith")
		var ev: Dictionary = Catalog.EVENTS.get(ev_id,Catalog.EVENTS.wandering_smith)
		return "%s\n%s" % [ev.name,ev.story]
	if k == "camp":
		return "戰地營火\n1. 休整築牆：修復 45% 城牆缺失血量、領主回復 50% 生命\n2. 名匠鍛造：自選 1 張卡牌與屬性免費 +1 階\n3. 軍資徵集：獲得 120 金幣並隨機強化 1 張卡"
	return "秘寶古祠\n1. 開啟聖物匣：免費獲得 1 件未持有的遺物\n2. 精煉主力：指定 1 張卡牌 +1 階並獲得 70 金幣\n3. 鮮血奉獻：損耗 25% 領主生命換取 200 金幣與隨機強化"

func role_text(lord: String) -> String:
	return "領主被動：%s\n主動技能：%s\n常駐牌：%s（起手配隨機本陣營 8 張套牌）" % [B.passive_text(Catalog.passive(lord)),B.skill_text(lord),B.CARDS[B.home_card(lord)].name]

func solo_text(lord: String) -> String:
	return "%s · %s\n\n主動技能：%s\n\n領主被動：%s\n常駐牌：%s" % [B.lord_name(lord),B.lord_data(lord).role,B.skill_text(lord),B.passive_text(Catalog.passive(lord)),B.CARDS[B.home_card(lord)].name]

func desc(kind: String) -> String:
	var base_ups: Dictionary = run.get("upgrades",{}) if not run.is_empty() else {}
	var bonus_ups: Dictionary = run.get("offer_ups",{}).get(kind,{}) if (not run.is_empty() and run.get("phase","") in ["reward","replace"]) else {}
	if base_ups.is_empty() and bonus_ups.is_empty():
		return B.card_description(kind)
	var preview := base_ups.duplicate(true)
	if not bonus_ups.is_empty():
		preview[kind] = Upgrades.merge_upgrades(kind,preview.get(kind,{}),bonus_ups)
	if not preview.has(kind): return B.card_description(kind)
	var text := B.card_description(kind,Upgrades.table(preview))
	var cur_u: Dictionary = base_ups.get(kind,{})
	if Upgrades.level(cur_u) > 0:
		text += "\n既有強化 +%d：%s" % [Upgrades.level(cur_u),Upgrades.text(cur_u)]
	if Upgrades.level(bonus_ups) > 0:
		text += "\n獲得時附帶 +%d：%s" % [Upgrades.level(bonus_ups),Upgrades.text(bonus_ups)]
	return text

func deck_tooltips(game, cards: Array, origin: Vector2) -> void:
	for i: int in range(cards.size()):
		var rect := Rect2(origin+Vector2((i%4)*108,(i/4)*88),Vector2(100,82))
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

func board_slot_rect(i: int) -> Rect2:
	return Rect2(85+(i%2)*385,250+(i/2)*250,370,232)

func upgrade_rect(i: int) -> Rect2:
	return Rect2(90+(i%4)*190,215+(i/4)*270,175,255)

func relic_rect(i: int) -> Rect2:
	return Rect2(880,215+i*175,630,160)

func lord_rect(i: int) -> Rect2:
	if B.LORDS.size() <= 8: return Rect2(150+(i%4)*330,176+(i/4)*308,290,252)
	return Rect2(92+(i%5)*286,176+(i/5)*308,272,252)

func offer_rect(i: int) -> Rect2:
	return Rect2(120+i*345,260,240,340)

func deck_rect(i: int) -> Rect2:
	return Rect2(330+(i%4)*240,330+(i/4)*230,200,210)

# ---- painting -----------------------------------------------------------------------------------

func paint(g) -> void:
	g.label_at(Vector2(90,82),"肉鴿模式",42)
	var rec := "八場連戰 · 最佳 %d / %d 場 · 累計通關 %d 次（最高契約 %d）" % [best,Catalog.FLOORS,clears,max_contract]
	g.label_at(Vector2(285,84),rec,20)
	if not save_notice.is_empty(): g.label_at(Vector2(90,115),save_notice,18,g.RED)
	var current: String = run.get("phase",phase) if not run.is_empty() else phase
	match current:
		"lord": paint_lords(g)
		"confirm": paint_confirm(g)
		"map": paint_map(g)
		"camp": paint_camp(g)
		"shrine": paint_shrine(g)
		"event": paint_event(g)
		"reward": paint_reward(g)
		"replace": paint_replace(g)
		"shop": paint_shop(g)
		"won", "lost": paint_end(g)

func paint_lords(g) -> void:
	g.label_at(Vector2(150,145),"選擇出征領主（單領主帶隊，起始搭配隨機本陣營 8 張套牌）",24)
	var lords: Array = B.lord_menu_order()
	for i: int in range(lords.size()):
		var r := lord_rect(i)
		g.panel(Rect2(r.position,Vector2(r.size.x,r.size.y+54)),Color("ecddb9"),Color("8c6e43"))
		g.draw_lord_card(lords[i],r,false)
		if lords[i] in cleared_lords:
			g.draw_circle(r.position+Vector2(r.size.x-24,24),15,Color("d2ad58"))
			g.draw_string(g.font,r.position+Vector2(r.size.x-38,31),"★",HORIZONTAL_ALIGNMENT_CENTER,28,18,g.RED)
		var line: String = "%s · 常駐：%s" % [B.passive_text(Catalog.passive(lords[i])),B.CARDS[B.home_card(lords[i])].name]
		var caption := TextParagraph.new()
		caption.width = r.size.x-12
		caption.alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		g.draw_rect(Rect2(r.position+Vector2(5,r.size.y-4),Vector2(r.size.x-10,48)),Color("ecddb9"))
		preload("res://interface_ornament.gd").rule(g,Vector2(r.position.x+22,r.end.y-1),Vector2(r.end.x-22,r.end.y-1),Color("a68a58"))
		caption.add_string(line,g.font,16)
		caption.draw(g.get_canvas_item(),Vector2(r.position.x+6,r.end.y+3),g.INK)

func paint_confirm(g) -> void:
	g.label_at(Vector2(110,145),"確認出征領主、隨機本陣營套牌與戰役契約",24)
	g.draw_lord_card(pending_lord,Rect2(110,175,260,310),true)
	g.draw_multiline_string(g.font,Vector2(395,185),solo_text(pending_lord),HORIZONTAL_ALIGNMENT_LEFT,390,16,-1,g.INK)
	var c_info: Dictionary = Catalog.CONTRACTS[clampi(pending_contract,0,Catalog.CONTRACTS.size()-1)]
	g.label_at(Vector2(110,715),"戰役契約：%s — %s" % [c_info.name,c_info.desc],17,g.RED)
	var r := Rect2(830,175,690,540)
	g.panel(r,Color("efe0bd"))
	g.draw_string(g.font,r.position+Vector2(0,40),"隨機本陣營起始牌組（%s 8 張 · 種子 %d）" % [B.CARDS[B.home_card(pending_lord)].name,pending_seed],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,20,g.INK)
	var cards := Catalog.starter_deck(pending_lord,pending_seed)
	mini_deck(g,cards,Vector2(860,290),2)
	g.label_at(Vector2(860,545),deck_summary(cards),17)

func mini_deck(g, cards: Array, origin: Vector2, rows: int = 2, ups: Dictionary = {}, compact: bool = false) -> void:
	var per_row := ceili(cards.size()/float(rows))
	var cell_size := Vector2(100,82) if compact else Vector2(100,102)
	var step_y := 88 if compact else 110
	var art_h := 50 if compact else 66
	for i: int in range(cards.size()):
		var cell := Rect2(origin+Vector2((i%per_row)*108,(i/per_row)*step_y),cell_size)
		g.panel(cell,Color("f6ead0"))
		g.draw_fitted(g.art(cards[i]),Rect2(cell.position+Vector2(8,4),Vector2(84,art_h)),Color.WHITE,true)
		var name: String = B.CARDS[cards[i]].name
		g.draw_string(g.font,cell.position+Vector2(0,cell_size.y-8),name,HORIZONTAL_ALIGNMENT_CENTER,cell.size.x,16 if name.length() > 4 else 17,g.INK)
		var lv: int = Upgrades.level(ups.get(cards[i],{}))
		if lv > 0: g.draw_string(g.font,cell.position+Vector2(6,18),"+%d" % lv,HORIZONTAL_ALIGNMENT_LEFT,-1,16,g.RED)

func paint_floors(g, y: float) -> void:
	for i: int in range(Catalog.FLOORS):
		var p := Vector2(440+i*105,y)
		var done: bool = i < run.floor or (i == run.floor and run.phase == "won")
		if i == run.floor and run.phase in ["map","camp","shrine","event","lost"]: g.draw_circle(p,29,Color("d2ad58",0.9))
		g.draw_circle(p,23,g.RED if done else (Color("6f5a3e") if i == Catalog.FLOORS-1 else Color("a89a80")))
		g.draw_arc(p,23,0,TAU,36,Color(g.INK,0.85),2.2,true)
		g.draw_string(g.font,p+Vector2(-24,8),"魔王" if i == Catalog.FLOORS-1 else str(i+1),HORIZONTAL_ALIGNMENT_CENTER,48,17 if i == Catalog.FLOORS-1 else 20,Color("fff0ca"))
		if i < Catalog.FLOORS-1: g.ink_line(p+Vector2(25,0),p+Vector2(80,0),i,Color(g.INK,0.5),2.0)

func paint_status_strip(g) -> void:
	var c_name: String = Catalog.CONTRACTS[clampi(int(run.get("contract",0)),0,Catalog.CONTRACTS.size()-1)].name
	var strip := "第 %d / %d 層（%s） · 金幣 %d · %s · 本層剩餘支援行動：%d 次" % [run.floor+1,Catalog.FLOORS,c_name,run.gold,wounds_text(),int(run.get("march_steps",2))]
	g.label_at(Vector2(90,192),strip,17,g.RED)
	if not str(run.get("board_notice","")).is_empty():
		g.label_at(Vector2(90,218),"牌陣動態："+str(run.board_notice),16,Color("6f5a3e"))

func paint_map(g) -> void:
	paint_floors(g,142)
	paint_status_strip(g)
	# Left: 4-slot Encounter Board (2x2 cards)
	for i: int in range(4):
		var slot: Dictionary = run.board[i]
		var r := board_slot_rect(i)
		var selected: bool = (i == int(run.get("selected_node",0)))
		var k: String = slot.get("kind","battle")
		var bg := Color("f6ead0")
		var header_col := Color("6f5a3e")
		var badge := "一般遭遇"
		match k:
			"boss":
				bg = Color("f4dfcf")
				header_col = g.RED
				badge = "最終魔王決戰"
			"elite":
				bg = Color("f5e1cf")
				header_col = g.RED
				badge = "精英討伐 · 掉遺物"
			"battle":
				bg = Color("f6ead0")
				header_col = Color("5a4632")
				badge = "一般遭遇戰"
			"camp":
				bg = Color("f7ebd2")
				header_col = Color("b5592a")
				badge = "戰地營火 · 休整鍛造"
			"shrine":
				bg = Color("e9ead8")
				header_col = Color("355b78")
				badge = "秘寶古祠 · 聖物精煉"
			"event":
				bg = Color("ece6cf")
				header_col = Color("4b6043")
				badge = "手抄本奇遇 · 抉擇"
		g.panel(r,bg,g.RED if selected else g.INK)
		if selected:
			g.draw_rect(r.grow(-4),Color("d2ad58"),false,3.5)
		g.draw_rect(Rect2(r.position+Vector2(4,4),Vector2(r.size.x-8,34)),Color(header_col,0.9))
		g.draw_string(g.font,r.position+Vector2(14,28),"【%d】%s" % [i+1,badge],HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("fff0ca"))
		if int(slot.get("bounty",0)) > 0:
			g.draw_string(g.font,r.position+Vector2(r.size.x-135,28),"懸賞 +%d金" % int(slot.bounty),HORIZONTAL_ALIGNMENT_RIGHT,125,16,Color("ffd97d"))
		var art_rect := Rect2(r.position+Vector2(16,48),Vector2(105,115))
		if k in ["battle","elite","boss"]:
			var f_id: String = slot.get("foe",foe())
			g.draw_fitted(g.lord_art(f_id,1),art_rect,Color.WHITE,true)
			g.label_at(r.position+Vector2(132,76),B.lord_name(f_id),23,g.INK)
			var ai_lv := clampi(Catalog.AI_LEVEL[run.floor]+int(Catalog.CONTRACTS[clampi(int(run.get("contract",0)),0,Catalog.CONTRACTS.size()-1)].get("ai_boost",0)),0,2)
			g.label_at(r.position+Vector2(132,104),"%s · AI %s" % [B.lord_data(f_id).role,["簡單","普通","困難"][ai_lv]],15,Color("6f5a3e"))
			var rule: String = (B.minion_text(f_id)+"\n"+B.skill_text(f_id)) if B.is_minion(f_id) else B.LORDS[f_id].skill
			g.draw_multiline_string(g.font,r.position+Vector2(132,128),rule,HORIZONTAL_ALIGNMENT_LEFT,224,14,2,g.INK)
		else:
			var icon_card: String = "field_smithy" if k == "camp" else ("blood_altar" if k == "shrine" else str(Catalog.EVENTS.get(slot.get("event_id","wandering_smith"),Catalog.EVENTS.wandering_smith).art))
			g.draw_fitted(g.art(icon_card),art_rect,Color.WHITE,true)
			g.label_at(r.position+Vector2(132,76),slot_title(slot),22,g.INK)
			var desc_txt: String = "休整築牆／鍛造卡牌／徵集軍資" if k == "camp" else ("免費聖物匣／主力精煉／鮮血奉獻" if k == "shrine" else str(Catalog.EVENTS.get(slot.get("event_id","wandering_smith"),Catalog.EVENTS.wandering_smith).story))
			g.draw_multiline_string(g.font,r.position+Vector2(132,106),desc_txt,HORIZONTAL_ALIGNMENT_LEFT,224,14,3,Color("5a4632"))
		g.draw_line(r.position+Vector2(12,176),r.position+Vector2(r.size.x-12,176),Color(g.INK,0.22),1.0)
		g.draw_string(g.font,r.position+Vector2(14,200),slot_subtitle(slot),HORIZONTAL_ALIGNMENT_LEFT,r.size.x-28,15,g.RED if k in ["elite","boss"] else Color("5a4632"))
		g.draw_string(g.font,r.position+Vector2(14,222),"▶ 已選取（再點一次立即觸發）" if selected else "點選查看詳情",HORIZONTAL_ALIGNMENT_LEFT,r.size.x-28,14,g.RED if selected else Color(g.INK,0.55))

	# Right panel: Selected encounter details + My Army & Deck
	var right := Rect2(865,250,650,535)
	g.panel(right,Color("efe0bd"))
	var sel := active_slot()
	var sel_k: String = sel.get("kind","battle")
	if sel_k in ["battle","elite","boss"]:
		var enemy := foe()
		g.draw_string(g.font,right.position+Vector2(0,32),"選中目標：%s（%s）" % [B.lord_name(enemy),"精英討伐" if sel_k == "elite" else ("最終魔王" if sel_k == "boss" else "一般遭遇")],HORIZONTAL_ALIGNMENT_CENTER,right.size.x,21,g.RED if sel_k != "battle" else g.INK)
		var rule_line: String = ("敵方特性：%s\n敵方技能：%s" % [B.minion_text(enemy), B.skill_text(enemy)]) if B.is_minion(enemy) else ("敵方技能："+B.skill_text(enemy))
		var sel_mut := Catalog.mutator_data(sel)
		if not sel_mut.is_empty():
			rule_line += "\n異變【%s】：%s" % [String(sel_mut.name),String(sel_mut.desc)]
		g.draw_multiline_string(g.font,right.position+Vector2(20,54),rule_line,HORIZONTAL_ALIGNMENT_LEFT,right.size.x-40,14,3,g.RED if not sel_mut.is_empty() else Color("5a4632"))
		var enemy_scale: float = Catalog.enemy_floor_scale(run.floor)
		var deck_hdr: String = ("敵方牌組（金幣獲得／冷卻速度 ×%.2f）：" % enemy_scale) if enemy_scale > 1.0 else "敵方牌組："
		g.label_at(right.position+Vector2(20,132),deck_hdr,16,g.INK)
		mini_deck(g,Catalog.foe_deck(enemy),Vector2(1010,352),2,{},true)
	else:
		g.draw_string(g.font,right.position+Vector2(0,32),"選中遭遇：%s" % slot_title(sel),HORIZONTAL_ALIGNMENT_CENTER,right.size.x,22,g.RED)
		g.draw_multiline_string(g.font,right.position+Vector2(24,68),slot_tooltip(sel),HORIZONTAL_ALIGNMENT_LEFT,right.size.x-48,16,7,g.INK)
		g.label_at(right.position+Vector2(24,255),"觸發後僅此格替補新牌；本層還可進行 %d 次非戰鬥支援行動。" % int(run.get("march_steps",2)),16,Color("6f5a3e"))

	g.draw_line(right.position+Vector2(16,288),right.position+Vector2(right.size.x-16,288),Color(g.INK,0.3),1.5)
	g.draw_string(g.font,right.position+Vector2(0,314),"我軍編制 · %s" % B.lord_name(run.lord),HORIZONTAL_ALIGNMENT_CENTER,right.size.x,20,g.INK)
	g.draw_fitted(g.lord_art(run.lord),Rect2(right.position+Vector2(28,332),Vector2(90,115)),Color.WHITE,true)
	mini_deck(g,run.deck,Vector2(1010,574),2,run.upgrades,true)
	var relic_names: String = "、".join(run.relics.map(func(k: String) -> String: return Catalog.RELICS[k].name)) if not run.relics.is_empty() else "無"
	g.draw_multiline_string(g.font,right.position+Vector2(18,458),"持有遺物（%d）：%s" % [run.relics.size(),relic_names],HORIZONTAL_ALIGNMENT_LEFT,120,14,4,Color("5a4632"))
	g.label_at(right.position+Vector2(145,518),deck_summary(run.deck),15,Color("6f5a3e"))

func paint_camp(g) -> void:
	paint_floors(g,142)
	paint_status_strip(g)
	var left := Rect2(90,250,680,500)
	var right := Rect2(800,250,710,500)
	g.panel(left,Color("efe0bd"))
	g.panel(right,Color("efe0bd"))
	g.draw_string(g.font,left.position+Vector2(0,42),"點選要鍛造的卡牌（目前選擇：%s）" % B.CARDS[run.deck[clampi(camp_card_index,0,run.deck.size()-1)]].name,HORIZONTAL_ALIGNMENT_CENTER,left.size.x,22,g.INK)
	for i: int in range(run.deck.size()):
		var r := Rect2(130+(i%4)*155,360+(i/4)*155,142,142)
		g.panel(r,Color("f6ead0"),g.RED if i == camp_card_index else g.INK)
		if i == camp_card_index: g.draw_rect(r.grow(-3),Color("d2ad58"),false,3)
		g.draw_fitted(g.art(run.deck[i]),Rect2(r.position+Vector2(14,8),Vector2(114,84)),Color.WHITE,true)
		g.draw_string(g.font,r.position+Vector2(0,115),B.CARDS[run.deck[i]].name,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,16,g.INK)
		var ups: Dictionary = run.upgrades.get(run.deck[i],{})
		var lv := Upgrades.level(ups)
		g.draw_string(g.font,r.position+Vector2(0,135),("+%d (%s)" % [lv,Upgrades.text(ups)]) if lv > 0 else "未強化",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,13,g.RED if lv > 0 else Color("6f5a3e"))
	g.draw_string(g.font,right.position+Vector2(0,48),"戰地營火 · 三選一行動",HORIZONTAL_ALIGNMENT_CENTER,right.size.x,26,g.RED)
	g.label_at(right.position+Vector2(35,455),"提示：營火完成後，僅此格會替補新遭遇，場上其餘三格將保留。",17,Color("6f5a3e"))

func paint_shrine(g) -> void:
	paint_floors(g,142)
	paint_status_strip(g)
	var left := Rect2(90,250,680,500)
	var right := Rect2(800,250,710,500)
	g.panel(left,Color("efe0bd"))
	g.panel(right,Color("efe0bd"))
	g.draw_string(g.font,left.position+Vector2(0,42),"點選要精煉的卡牌（目前選擇：%s）" % B.CARDS[run.deck[clampi(camp_card_index,0,run.deck.size()-1)]].name,HORIZONTAL_ALIGNMENT_CENTER,left.size.x,22,g.INK)
	for i: int in range(run.deck.size()):
		var r := Rect2(130+(i%4)*155,360+(i/4)*155,142,142)
		g.panel(r,Color("f6ead0"),g.RED if i == camp_card_index else g.INK)
		if i == camp_card_index: g.draw_rect(r.grow(-3),Color("d2ad58"),false,3)
		g.draw_fitted(g.art(run.deck[i]),Rect2(r.position+Vector2(14,8),Vector2(114,84)),Color.WHITE,true)
		g.draw_string(g.font,r.position+Vector2(0,115),B.CARDS[run.deck[i]].name,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,16,g.INK)
		var ups: Dictionary = run.upgrades.get(run.deck[i],{})
		var lv := Upgrades.level(ups)
		g.draw_string(g.font,r.position+Vector2(0,135),("+%d (%s)" % [lv,Upgrades.text(ups)]) if lv > 0 else "未強化",HORIZONTAL_ALIGNMENT_CENTER,r.size.x,13,g.RED if lv > 0 else Color("6f5a3e"))
	g.draw_string(g.font,right.position+Vector2(0,48),"秘寶古祠 · 聖物與精煉",HORIZONTAL_ALIGNMENT_CENTER,right.size.x,26,g.RED)
	g.label_at(right.position+Vector2(35,455),"提示：古祠賜福後，僅此格會替補新遭遇，場上其餘三格將保留。",17,Color("6f5a3e"))

func paint_event(g) -> void:
	paint_floors(g,142)
	paint_status_strip(g)
	var ev_id: String = active_slot().get("event_id","wandering_smith")
	var ev: Dictionary = Catalog.EVENTS.get(ev_id,Catalog.EVENTS.wandering_smith)
	var panel_rect := Rect2(90,245,1425,520)
	g.panel(panel_rect,Color("efe0bd"))
	g.draw_fitted(g.art(ev.art),Rect2(130,285,220,230),Color.WHITE,true)
	g.label_at(Vector2(380,305),"奇遇事件 · "+ev.name,30,g.RED)
	g.draw_multiline_string(g.font,Vector2(130,545),ev.story,HORIZONTAL_ALIGNMENT_LEFT,450,18,6,g.INK)

func paint_reward(g) -> void:
	g.panel(Rect2(1145,260,395,455),Color("efe0bd"))
	paint_floors(g,142)
	if not outcome.is_empty():
		g.draw_string(g.font,Vector2(0,196),outcome,HORIZONTAL_ALIGNMENT_CENTER,1600,20,g.RED)
	var chance_info := Upgrades.drop_chance_info(run.lord,"",int(run.get("floor",0)),bool(run.get("last_elite",false)),int(run.get("contract",0)),run.get("relics",[]).size(),has_targeted_upgrade(),bool(run.get("from_event",false)),int(run.get("offer_rerolls",0)))
	var reason_txt := ("（" + " · ".join(chance_info.reasons) + "）") if not chance_info.reasons.is_empty() else "（基礎機率，高層數／精英／契約／遺物／重抽可提升）"
	g.draw_string(g.font,Vector2(0,224),"選一張卡加入牌組（目前金幣 %d · 略過可領 +%d 金）" % [run.gold,Catalog.SKIP_REWARD_GOLD],HORIZONTAL_ALIGNMENT_CENTER,1600,22,g.INK)
	g.draw_string(g.font,Vector2(0,248),"隨機預強化機率 約 %d%%（最高 +3）%s" % [roundi(float(chance_info.chance)*100.0),reason_txt],HORIZONTAL_ALIGNMENT_CENTER,1600,15,Color("6b4c33"))
	var Ornament = preload("res://interface_ornament.gd")
	for i: int in range(run.offer.size()):
		var kind: String = run.offer[i]
		var r := offer_rect(i)
		g.draw_card(kind,r)
		var bonus: Dictionary = run.get("offer_ups",{}).get(kind,{})
		var bonus_lv := Upgrades.level(bonus)
		if bonus_lv > 0:
			Ornament.wax_upgrade_seal(g,r.position+Vector2(r.size.x-26,r.size.y*0.62),17.0,bonus_lv)
		var ups: Dictionary = run.upgrades.get(kind,{})
		var up_txt: String = (" · 既有 +%d" % Upgrades.level(ups)) if Upgrades.level(ups) > 0 else ""
		g.label_at(r.position+Vector2(0,370),"目前持有 %d 張%s" % [run.deck.count(kind),up_txt],17)
		if bonus_lv > 0:
			g.label_at(r.position+Vector2(0,396),"附帶強化 +%d：%s" % [bonus_lv,Upgrades.text(bonus)],15,g.RED)
	g.label_at(Vector2(1170,250),"卡牌效果",22)

func paint_replace(g) -> void:
	g.panel(Rect2(80,180,1440,135),Color("efe0bd"))
	if selected_slot >= 0:
		var old: String = run.deck[selected_slot]
		g.label_at(Vector2(80,660),"移除："+B.CARDS[old].name,20)
		g.label_at(Vector2(80,695),"費用 %d → %d" % [B.CARDS[old].cost,B.CARDS[run.pick].cost],20)
	g.draw_string(g.font,Vector2(0,160),"新卡：%s　→　點一張要換掉的卡" % B.CARDS[run.pick].name,HORIZONTAL_ALIGNMENT_CENTER,1600,28,g.RED)
	var pick_r := Rect2(80,330,200,280)
	g.draw_card(run.pick,pick_r)
	var pick_bonus: Dictionary = run.get("offer_ups",{}).get(run.pick,{})
	var pick_blv := Upgrades.level(pick_bonus)
	if pick_blv > 0:
		preload("res://interface_ornament.gd").wax_upgrade_seal(g,pick_r.position+Vector2(pick_r.size.x-24,pick_r.size.y*0.62),16.0,pick_blv)
		g.label_at(Vector2(80,625),"附帶強化 +%d（加入後疊加至上限 +10）" % pick_blv,15,g.RED)
	for i: int in range(8):
		var r := deck_rect(i)
		var kind: String = run.deck[i]
		var ups: Dictionary = run.upgrades.get(kind,{})
		var lv := Upgrades.level(ups)
		g.panel(r,Color("f6ead0"))
		if i == selected_slot: g.draw_rect(r,Color("b08b2f"),false,4)
		g.draw_fitted(g.art(kind),Rect2(r.position+Vector2(14,10),Vector2(r.size.x-28,140)),Color.WHITE,true)
		if lv > 0:
			g.draw_string(g.font,r.position+Vector2(10,28),"+%d" % lv,HORIZONTAL_ALIGNMENT_LEFT,-1,17,g.RED)
		g.draw_string(g.font,r.position+Vector2(0,178),B.CARDS[kind].name,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,20,g.INK)
		var sub_txt: String = ("%d 金 · %s" % [B.CARDS[kind].cost,Upgrades.text(ups)]) if lv > 0 else ("%d 金幣" % B.CARDS[kind].cost)
		g.draw_string(g.font,r.position+Vector2(0,200),sub_txt,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,14,g.RED if lv > 0 else Color("6f5a3e"))

func paint_shop(g) -> void:
	var up_hint := ("【%s】生效中：可點選切換要升階的屬性，最高 SS" % targeted_relic_name()) if has_targeted_upgrade() else ("隨機提升一項屬性，最高 SS · 持有「%s」遺物可改為自選" % Catalog.RELICS.artisan_blueprint.name)
	g.label_at(Vector2(90,180),"軍需商店 · 金幣 %d · 卡牌強化（%s）" % [run.gold,up_hint],20,g.RED)
	var kinds := shop_kinds()
	for i: int in range(kinds.size()):
		var kind: String = kinds[i]
		var r := upgrade_rect(i)
		var ups: Dictionary = run.upgrades.get(kind,{})
		g.panel(r,Color("f6ead0"))
		g.draw_fitted(g.art(kind),Rect2(r.position+Vector2(12,6),Vector2(r.size.x-24,92)),Color.WHITE,true)
		g.draw_string(g.font,r.position+Vector2(0,118),"%s ×%d" % [B.CARDS[kind].name,run.deck.count(kind)],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,17,g.INK)
		g.draw_string(g.font,r.position+Vector2(0,140),"+%d / %d" % [Upgrades.level(ups),Upgrades.MAX_LEVEL],HORIZONTAL_ALIGNMENT_CENTER,r.size.x,16,g.RED if Upgrades.level(ups) > 0 else Color("6f5a3e"))
		g.draw_string(g.font,r.position+Vector2(0,162),Upgrades.text(ups),HORIZONTAL_ALIGNMENT_CENTER,r.size.x,13,Color("6f5a3e"))
	g.label_at(Vector2(880,200),"遺物櫃檯（共 %d 種遺物，效果可疊加）" % Catalog.RELICS.size(),22,g.RED)
	for i: int in range(run.shop.size()):
		var relic: Dictionary = Catalog.RELICS[run.shop[i]]
		var r := relic_rect(i)
		g.panel(r,Color("efe0bd"))
		g.draw_string(g.font,r.position+Vector2(20,38),"%s　%d 金" % [relic.name,relic.price],HORIZONTAL_ALIGNMENT_LEFT,-1,24,g.INK)
		g.draw_multiline_string(g.font,r.position+Vector2(20,62),B.passive_text(relic.mods),HORIZONTAL_ALIGNMENT_LEFT,r.size.x-40,16,2,Color("6f5a3e"))
	if run.shop.is_empty(): g.label_at(Vector2(880,260),"這一站的遺物已經買完了",18)
	g.label_at(Vector2(340,782),wounds_text()+" · 城牆每 1 金修 %d 血、領主每 1 金治 %d 血" % [int(Catalog.GATE_HP_PER_GOLD),int(Catalog.LORD_HP_PER_GOLD)],16,g.RED)
	g.label_at(Vector2(880,760),"已有遺物："+("、".join(run.relics.map(func(k: String) -> String: return Catalog.RELICS[k].name)) if not run.relics.is_empty() else "無"),16)

func wounds_text() -> String:
	var standing: int = run.get("gates",[]).filter(func(hp: float) -> bool: return hp > 0).size()
	var total := 0.0
	for hp: float in run.get("gates",[]): total += hp
	return "城牆 %d/5 座 · 總血量 %d%% · 領主 %d/%d" % [standing,roundi(100.0*total/(5*B.GATE_HP)),int(run.get("lord_hp",0)),int(lord_max_hp())]

func paint_end(g) -> void:
	paint_floors(g,230)
	var won: bool = run.phase == "won"
	var c_name: String = Catalog.CONTRACTS[clampi(int(run.get("contract",0)),0,Catalog.CONTRACTS.size()-1)].name
	g.draw_string(g.font,Vector2(0,370),"肉鴿通關！（%s）" % c_name if won else "本輪結束",HORIZONTAL_ALIGNMENT_CENTER,1600,52,g.RED if won else g.INK)
	var text := ("%s與%s帶著這副牌打完了八場。" % [B.lord_name(run.lord),B.lord_name(run.domestic)]) if won else ("止步第 %d 場，敗給%s。" % [run.floor+1,B.lord_name(foe())])
	g.draw_string(g.font,Vector2(0,435),text,HORIZONTAL_ALIGNMENT_CENTER,1600,24,g.INK)
	g.draw_string(g.font,Vector2(0,485),"最終牌組：" + "、".join(run.deck.map(func(k: String) -> String: return B.CARDS[k].name)),HORIZONTAL_ALIGNMENT_CENTER,1600,18,Color("6f5a3e"))
	var relic_line := "持有遺物：" + ("、".join(run.relics.map(func(k: String) -> String: return Catalog.RELICS[k].name)) if not run.relics.is_empty() else "無")
	g.draw_string(g.font,Vector2(0,525),relic_line,HORIZONTAL_ALIGNMENT_CENTER,1600,18,Color("6f5a3e"))
