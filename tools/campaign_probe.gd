extends SceneTree
# Conditional territory difficulty, never a player save or a full-run success claim.
# --samples=10 --seed=11300 --stage=all --out=res://.runtime/campaign-probe.json
const B = preload("res://balance.gd")
const Battle = preload("res://battle.gd")
const Adventure = preload("res://adventure.gd")
const Catalog = preload("res://campaign_catalog.gd")
const AI = preload("res://enemy_ai.gd")

class Host extends RefCounted:
	var adventure = Adventure.new()
	var model
	var player_deck: Array = []
	var notice := ""

func _initialize() -> void: call_deferred("run")

func option(name: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--"+name+"="): return arg.substr(name.length()+3)
	return fallback

func value(kind: String) -> float:
	var d: Dictionary = B.CARDS[kind]
	var cost := maxf(1.0,float(d.cost))
	if d.type == "unit":
		if d.has("members"):
			var total := 0.0
			for member: Array in d.members:
				var troop: Dictionary = B.CARDS[member[0]]
				total += float(member[1])*(sqrt(float(troop.hp))+float(troop.damage)/float(troop.interval)*1.5)
			return total/cost
		return (sqrt(float(d.hp))*float(d.get("count",1))+float(d.damage)/float(d.interval)*1.5)/cost
	if d.type == "spell": return float(d.get("damage",d.get("area_damage",100)))/cost
	return sqrt(float(d.get("hp",100)))/cost

func choose_deck(a, seed_value: int) -> Array:
	var pool: Array = a.card_pool()
	var random := RandomNumberGenerator.new()
	random.seed = seed_value # Never consumes the battle RNG.
	var scores := {}
	for kind: String in pool: scores[kind] = value(kind)*random.randf_range(0.85,1.15)
	pool.sort_custom(func(x: String,y: String) -> bool: return scores[x] > scores[y])
	var result: Array = []
	# Two melee, two ranged, utility troop, spell, building, and a flexible slot.
	for role: String in ["melee","melee","ranged","ranged","unit","spell","building","any"]:
		for kind: String in pool:
			if kind in result: continue
			var d: Dictionary = B.CARDS[kind]
			var matches: bool = role == "any" or role == d.type
			if role in ["melee","ranged"]: matches = d.type == "unit" and (bool(d.get("projectile",false)) == (role == "ranged"))
			if matches:
				result.append(kind)
				break
	for kind: String in pool:
		if result.size() >= 8: break
		if not kind in result: result.append(kind)
	return result

func make_battle(g: Host, index: int, seed_value: int):
	var a = g.adventure
	var d: Dictionary = a.STAGES[index]
	a.index = index
	# Adventure.start setup without menus, texture preparation or saving.
	var m = Battle.new(seed_value,a.stage_deck(g,index),d.enemy_deck,a.stage_lord(g,index),d.enemy_lord)
	g.model = m
	m.active_lanes.assign(d.active_lanes)
	if not d.enemy_lord_active:
		m.lord_active[1] = false
		m.lords[1].hp = 0
	if d.enemy_camp:
		m.home_cards[1] = ""
		m.buildings = m.buildings.filter(func(b): return b.team == 0)
	m.refresh_territory()
	m.difficulty = d.ai
	m.ai_enabled = [true,true]
	m.ai_params[0] = AI.EVOLVED.duplicate()
	m.invasion_victory.assign([true,true])
	for b: Array in d.buildings: m.add_building(1,Vector2i(b[0],b[1]),b[2])
	m.night_decay = not d.opening
	m.record_events = false
	a.opening.active = false
	if d.opening: a.opening.start(g)
	return m

func run() -> void:
	var samples := maxi(1,int(option("samples","10")))
	var seed_base := int(option("seed","11300"))
	var wanted := option("stage","all")
	var output := option("out","res://.runtime/campaign-probe.json")
	var source_hashes := {}
	for path: String in ["balance.gd","battle.gd","enemy_ai.gd","expansion_more.gd","campaign_catalog.gd","tools/campaign_probe.gd"]:
		source_hashes[path] = FileAccess.get_sha256("res://"+path)
	var rows: Array = []
	for index: int in range(Catalog.stages().size()):
		var d: Dictionary = Catalog.stages()[index]
		if wanted != "all" and d.id != wanted: continue
		var row := {"id":d.id,"name":d.name,"ai":d.ai,"wins":0,"draws":0,"timeouts":0,"games":samples,"trials":[]}
		for trial: int in range(samples):
			var g := Host.new()
			var a = g.adventure
			# Conditional difficulty, not survivor-biased full campaign completion.
			for prior: int in range(index):
				assert(a.unlocked(prior),"Survey route must be legal")
				a.cleared[a.STAGES[prior].id] = true
			if index > 0: a.recruit = "bandit" if trial % 2 == 0 else "knight"
			assert(a.unlocked(index),"Survey route must be legal")
			var lords: Array = a.unlocked_lords()
			a.lord = lords[0] if lords.size() == 1 else lords[1+trial%(lords.size()-1)]
			var seed_value := seed_base+index*100+trial
			a.custom_deck = choose_deck(a,seed_value)
			var m = make_battle(g,index,seed_value)
			var started := Time.get_ticks_msec()
			while not m.ended and m.elapsed < 900:
				if a.opening.active:
					a.opening.advance(g,1.0/30.0)
					m.step(1.0/30.0)
					a.opening.observe(g)
					if not a.opening.active: m.ai_enabled = [true,true]
				else: m.step(1.0/30.0)
			var winner: int = m.winner if m.ended else -2
			if winner == 0: row.wins += 1
			elif winner == -1: row.draws += 1
			elif winner == -2: row.timeouts += 1
			row.trials.append({"seed":seed_value,"winner":winner,"seconds":snappedf(m.elapsed,0.1),"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"lord":a.stage_lord(g,index),"deck":a.stage_deck(g,index),"opening_completed":not a.opening.active})
			print("PROBE %s %d/%d lord=%s winner=%d time=%.1f" % [d.id,trial+1,samples,a.stage_lord(g,index),winner,m.elapsed])
		rows.append(row)
		var file := FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify({"source_sha256":source_hashes,"seed":seed_base,"samples_per_stage":samples,"method":"conditional legal route; role/value deck; player EVOLVED; shared stage reaction delay; no saves","rows":rows},"\t"))
		file.close()
	print("PROBE COMPLETE: %d battles" % (rows.size()*samples))
	quit()
