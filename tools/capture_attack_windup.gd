extends SceneTree
var g
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	call_deferred("run")
func snap(label: String) -> void:
	g.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/windup-preview/"+label+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/windup-preview")
	g=load("res://main.tscn").instantiate()
	root.add_child(g)
	g.set_physics_process(false)
	g.set_process(false)
	g.sound_enabled=false
	g.model=g.Battle.new(18,[],[],"lion","iron")
	g.model.ai_enabled=[false,false]
	g.adventure.index=-1
	g.enter_battle("Windup preview")
	var attackers: Array = []
	for side: int in [0,1]:
		for lane: int in [1,2,3]:
			var p: Vector2 = g.L.cell_center(Vector2i(2 if side == 0 else 6,lane))
			var actor: Dictionary = g.model.spawn_unit(side,lane,["militia","axe_thrower","catapult"][lane-1],p)
			g.model.add_building(1-side,Vector2i((4 if side == 0 else 4) if lane == 3 else (3 if side == 0 else 5),lane),"bonewall")
			if lane != 3: actor.pos.x += 90*(1 if side == 0 else -1)
			attackers.append(actor)
	g.model.build_lookups()
	for actor: Dictionary in attackers:
		g.model.update_unit(actor,0.001)
		if not actor.has("attack_windup"):
			printerr("Missing preview windup")
			quit(1)
			return
		g.model.update_unit(actor,actor.attack_windup.duration*0.7)
		actor.draw=actor.pos+Vector2(0,actor.dy)
	await snap("windup")
	g.attack_animation.observe(g.model)
	for actor: Dictionary in attackers: g.model.update_unit(actor,0.2)
	g.attack_animation.observe(g.model)
	g.model.update_projectiles(0.08)
	g.model.elapsed+=0.08
	await snap("release")
	g.free()
	print("PASS: mirrored melee, thrown axe and catapult windup/release captured")
	quit()
