extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var g = load("res://game.gd").new()
	root.add_child(g)
	g.set_process(false)
	g.set_physics_process(false)
	g.sound_enabled = false
	var a = g.adventure
	a.progress_path = "user://finale-test.json"
	a.cleared = {}
	a.recruit = "bandit"
	a.lord = "adventure"
	for d: Dictionary in a.STAGES:
		if d.id != "royal_seat": a.cleared[d.id] = true
	var last: int = a.Catalog.index_of("royal_seat")
	a.start(g,last)
	g.model.paused = false
	g.model.finish(1)
	a.update(g)
	assert(g.screen != "adventure_finale" and not a.is_cleared(last))
	a.start(g,last)
	g.model.paused = false
	g.model.finish(0)
	a.update(g)
	assert(g.screen == "adventure_finale" and a.is_cleared(last))
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.runtime/coronation.png")
		for control in g.ui:
			if control is RichTextLabel: assert(control.get_content_height() <= control.size.y)
	a.show(g)
	assert(a.is_cleared(last) and a.unlocked(last))
	a.start(g,last)
	g.model.paused = false
	g.model.finish(0)
	a.update(g)
	assert(g.screen != "adventure_finale","Replay must not repeat first coronation")
	DirAccess.remove_absolute(a.progress_path)
	print("PASS: defeat, first coronation, save/reload, replay, text bounds")
	quit()
