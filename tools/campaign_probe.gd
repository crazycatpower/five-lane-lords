extends SceneTree
# Deterministic initial difficulty survey, three runs per territory. Never writes player saves.
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var g = load("res://game.gd").new()
	root.add_child(g)
	g.set_process(false)
	g.set_physics_process(false)
	g.sound_enabled = false
	g.adventure.progress_path = "user://campaign-probe-unused.json"
	g.adventure.cleared = {}
	g.adventure.recruit = ""
	g.adventure.lord = "adventure"
	var rows: Array = []
	for i: int in range(g.adventure.STAGES.size()):
		var d: Dictionary = g.adventure.STAGES[i]
		assert(g.adventure.unlocked(i),"Survey route must be legal")
		var deck: Array = g.adventure.card_pool().slice(0,8)
		g.adventure.custom_deck = deck if deck.size() == 8 else []
		var wins := 0
		var draws := 0
		var times: Array = []
		for trial: int in range(3):
			g.adventure.start(g,i)
			var m = g.model
			m.rng.seed = 11200+i*10+trial
			m.paused = false
			if not d.opening: m.ai_enabled = [true,true]
			while not m.ended and m.elapsed < 900:
				if g.adventure.opening.active:
					g.adventure.opening.advance(g,1.0/30.0)
					m.step(1.0/30.0)
					g.adventure.opening.observe(g)
					if not g.adventure.opening.active: m.ai_enabled = [true,true]
				else: m.step(1.0/30.0)
			if m.ended and m.winner == 0: wins += 1
			elif not m.ended or m.winner == -1: draws += 1
			times.append(snappedf(m.elapsed,0.1))
			print("PROBE %s %d: winner=%d time=%.1f" % [d.id,trial,m.winner if m.ended else -2,m.elapsed])
		var row := {"id":d.id,"name":d.name,"ai":d.ai,"wins":wins,"draws":draws,"games":3,"seconds":times,"deck":g.model.decks[0].duplicate()}
		rows.append(row)
		var out := FileAccess.open("res://.runtime/campaign-probe.json",FileAccess.WRITE)
		out.store_string(JSON.stringify(rows,"\t"))
		g.adventure.cleared[d.id] = true
		if i == 0: g.adventure.recruit = "bandit"
	print("PROBE COMPLETE: 45 battles")
	quit()
