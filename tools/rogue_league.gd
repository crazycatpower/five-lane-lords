extends SceneTree
# 肉鴿強度聯賽: every enabled 小怪領主 and boss fights a few random others (each pairing twice,
# sides swapped), hard AI on both sides, the roguelike time limit deciding stalemates. Prints a
# Bradley-Terry rating per tier. With --apply, re-tiers the 小怪 by rating (weakest third -> tier 1,
# middle -> 2, strongest -> 3) by rewriting the "tier" values in roguelike_catalog.gd.
#   godot_console --headless --path . -s tools/rogue_league.gd -- [--opponents=4] [--workers=4] [--apply]
# Runs the games in parallel worker processes; about 15 minutes for the full roster at 4 opponents.
# --duo instead measures the player: every 內政+戰鬥 pair with its starting deck against the same six
# tier-1 小怪, under real roguelike rules (foe 10 gold and 簡單 AI, player hard AI). About 10 minutes.
const B = preload("res://balance.gd")
const Battle = preload("res://battle.gd")
const Catalog = preload("res://roguelike_catalog.gd")
const CATALOG_PATH := "res://roguelike_catalog.gd"
const Rogue = preload("res://roguelike.gd")
const AI = preload("res://enemy_ai.gd")

func _initialize() -> void: call_deferred("run")

func option(args: PackedStringArray, name: String, default: int) -> int:
	for a: String in args:
		if a.begins_with("--%s=" % name): return int(a.split("=")[1])
	return default

static func roster() -> Array:
	var foes: Array = Catalog.MINIONS.keys().filter(func(k: String) -> bool: return Catalog.MINIONS[k].get("enabled",true))
	foes.append_array(Catalog.BOSSES.keys())
	return foes

# The same pairings in every process: fixed seed, each foe meets `opponents` others.
static func pairings(foes: Array, opponents: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var seen := {}
	for i: int in range(foes.size()):
		var n := 0
		while n < mini(opponents,foes.size()-1):
			var j := rng.randi_range(0,foes.size()-1)
			var key := "%d:%d" % [mini(i,j),maxi(i,j)]
			if j == i or seen.has(key): continue
			seen[key] = true
			n += 1
	var keys: Array = seen.keys()
	keys.sort()
	return keys.map(func(k: String) -> Array: return [foes[int(k.split(":")[0])],foes[int(k.split(":")[1])]])

static func play(red: String, blue: String, seed_value: int) -> int:
	var m := Battle.new(seed_value,Catalog.foe_deck(red),Catalog.foe_deck(blue),red,blue)
	m.difficulty = 2
	m.ai_enabled = [true,true]
	while not m.ended:
		m.step(1.0/30.0)
		if m.elapsed >= Catalog.TIME_LIMIT and not m.ended:
			var g := [0.0,0.0]
			for team: int in range(2):
				for hp: float in m.gates[team]: g[team] += hp
			m.finish(0 if g[0] > g[1] else (1 if g[1] > g[0] else -1))
	return m.winner

# [domestic, combat, foe] for every pair of different lords against six seeded tier-1 小怪.
static func duo_jobs() -> Array:
	var foes: Array = Catalog.MINIONS.keys().filter(func(k: String) -> bool: return Catalog.MINIONS[k].get("enabled",true) and Catalog.MINIONS[k].tier == 1)
	foes.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var picked: Array = []
	while picked.size() < mini(6,foes.size()):
		var f: String = foes[rng.randi_range(0,foes.size()-1)]
		if not f in picked: picked.append(f)
	var jobs: Array = []
	for d: String in B.LORDS:
		for c: String in B.LORDS:
			if d != c:
				for f: String in picked: jobs.append([d,c,f])
	return jobs

static func play_duo(job: Array, index: int, slice: int) -> int:
	var r = Rogue.new()
	r.save_path = "user://rogue-duo-%d.json" % slice
	r.begin(job[0],job[1],300+index)
	r.run.foes[0] = job[2]
	var m = r.make_battle()
	m.difficulty = 0
	m.ai_enabled = [true,true]
	m.ai_params[0] = AI.EVOLVED.duplicate()
	while not m.ended:
		m.step(1.0/30.0)
		Rogue.time_limit(m)
	return m.winner

func spawn_workers(workers: int, extra: Array) -> Array:
	var files: Array = []
	var pids: Array = []
	for k: int in range(workers):
		var file := ProjectSettings.globalize_path("user://rogue_league_%d.tsv" % k)
		files.append(file)
		pids.append(OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"-s","res://tools/rogue_league.gd","--","--worker",str(k),str(workers),file]+extra))
	while pids.any(func(pid: int) -> bool: return OS.is_process_running(pid)): OS.delay_msec(1000)
	var rows: Array = []
	for file: String in files:
		for line: String in FileAccess.get_file_as_string(file).split("\n",false): rows.append(line.split("\t"))
	return rows

func duo_report(rows: Array) -> void:
	var by := {"內政":{},"戰鬥":{}}
	var total := 0
	for f: PackedStringArray in rows:
		if f.size() < 4: continue
		var win := 1 if f[3] == "0" else 0
		total += win
		for pair: Array in [["內政",f[0]],["戰鬥",f[1]]]:
			var bucket: Dictionary = by[pair[0]]
			bucket[pair[1]] = bucket.get(pair[1],[0,0])
			bucket[pair[1]][0] += win
			bucket[pair[1]][1] += 1
	print("player wins %.0f%% of %d games vs tier-1 小怪" % [100.0*total/maxi(1,rows.size()),rows.size()])
	for role: String in by:
		print("\n== 當%s領主 ==" % role)
		var keys: Array = by[role].keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return by[role][a][0]*by[role][b][1] > by[role][b][0]*by[role][a][1])
		for k: String in keys: print("  %3.0f%%  %s" % [100.0*by[role][k][0]/by[role][k][1],B.lord_name(k)])

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var opponents := option(args,"opponents",4)
	var pairs := pairings(roster(),opponents)
	if "--worker" in args and "--duo" in args:
		var at := args.find("--worker")
		var slice := int(args[at+1])
		var count := int(args[at+2])
		var out := FileAccess.open(args[at+3],FileAccess.WRITE)
		var jobs := duo_jobs()
		for i: int in range(jobs.size()):
			if i % count == slice:
				out.store_line("%s\t%s\t%s\t%d" % [jobs[i][0],jobs[i][1],jobs[i][2],play_duo(jobs[i],i,slice)])
				out.flush()
		out.close()
		quit()
		return
	if "--duo" in args:
		print("rogue league --duo: %d games on %d workers" % [duo_jobs().size(),option(args,"workers",4)])
		duo_report(spawn_workers(option(args,"workers",4),["--duo"]))
		quit()
		return
	if "--worker" in args:
		var at := args.find("--worker")
		var slice := int(args[at+1])
		var count := int(args[at+2])
		var out := FileAccess.open(args[at+3],FileAccess.WRITE)
		for p: int in range(pairs.size()):
			if p % count != slice: continue
			for swap: int in range(2):
				var red: String = pairs[p][swap]
				var blue: String = pairs[p][1-swap]
				out.store_line("%s\t%s\t%d" % [red,blue,play(red,blue,5000+p*2+swap)])
				out.flush()
		out.close()
		quit()
		return
	var workers := option(args,"workers",4)
	print("rogue league: %d foes, %d games on %d workers" % [roster().size(),pairs.size()*2,workers])
	var games: Array = []
	for f: PackedStringArray in spawn_workers(workers,["--opponents=%d" % opponents]):
		if f.size() == 3: games.append([f[0],f[1],int(f[2])])
	var rating := ratings(games)
	report(games,rating)
	if "--apply" in args: apply_tiers(rating)
	quit()

# Bradley-Terry strengths from wins (a draw is half a win each), shown on an Elo-like scale.
static func ratings(games: Array) -> Dictionary:
	var score := {}
	var strength := {}
	for g: Array in games:
		for k: String in [g[0],g[1]]:
			score[k] = score.get(k,0.0)
			strength[k] = 1.0
		if g[2] == 0: score[g[0]] += 1.0
		elif g[2] == 1: score[g[1]] += 1.0
		else:
			score[g[0]] += 0.5
			score[g[1]] += 0.5
	for i: int in range(200):
		var next := {}
		for k: String in strength:
			var den := 0.0
			for g: Array in games:
				if g[0] == k or g[1] == k: den += 1.0/(strength[g[0]]+strength[g[1]])
			next[k] = maxf(score[k],0.05)/den
		var mean := 0.0
		for k: String in next: mean += log(next[k])
		mean = exp(mean/next.size())
		for k: String in next: strength[k] = next[k]/mean
	var result := {}
	for k: String in strength: result[k] = 1000.0+400.0*log(strength[k])/log(10.0)
	return result

static func report(games: Array, rating: Dictionary) -> void:
	var labels := {1:"前段 (第 1-2 場)",2:"中段 (第 3-5 場)",3:"後段 (第 6-7 場)",4:"魔王"}
	for tier: int in [1,2,3,4]:
		var ks: Array = rating.keys().filter(func(k: String) -> bool: return (Catalog.MINIONS[k].tier if Catalog.MINIONS.has(k) else 4) == tier)
		ks.sort_custom(func(a: String, b: String) -> bool: return rating[a] > rating[b])
		var values: Array = ks.map(func(k: String) -> float: return rating[k])
		values.sort()
		print("\n== %s  %d 位  中位數 %.0f ==" % [labels[tier],ks.size(),values[values.size()/2] if not values.is_empty() else 0.0])
		for k: String in ks: print("  %5.0f  %s" % [rating[k],B.lord_name(k)])

# Weakest third of the enabled 小怪 -> tier 1, middle third -> 2, strongest third -> 3.
static func apply_tiers(rating: Dictionary) -> void:
	var minions: Array = rating.keys().filter(func(k: String) -> bool: return Catalog.MINIONS.has(k))
	minions.sort_custom(func(a: String, b: String) -> bool: return rating[a] < rating[b])
	var text := FileAccess.get_file_as_string(CATALOG_PATH)
	var changed := 0
	for i: int in range(minions.size()):
		var tier: int = 1+mini(2,i*3/minions.size())
		var old := "\"%s\":{\"tier\":%d" % [minions[i],Catalog.MINIONS[minions[i]].tier]
		if Catalog.MINIONS[minions[i]].tier != tier and text.contains(old):
			text = text.replace(old,"\"%s\":{\"tier\":%d" % [minions[i],tier])
			changed += 1
	var file := FileAccess.open(CATALOG_PATH,FileAccess.WRITE)
	file.store_string(text)
	file.close()
	print("\nre-tiered %d 小怪領主 in roguelike_catalog.gd" % changed)
