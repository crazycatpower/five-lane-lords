extends SceneTree
# Focused visual QA. No settings or player saves are written.
const KEYS := ["mana_spring","chain_lightning","arcane_shield","time_field","charge_horn","levy","net_hunter","watchtower","sacrifice","dread_howl","mass_grave","blood_tower"]
var g
class Cards extends "res://game.gd":
	func _draw() -> void:
		draw_rect(Rect2(0,0,1600,900),Color("e0d3b4"))
		for i: int in range(12):
			draw_card(KEYS[i],Rect2(Vector2(120+(i%4)*400,45+(i/4)*285),Vector2(145,202)))
class Sheet extends Node2D:
	var game
	func _draw() -> void:
		draw_rect(Rect2(0,0,1600,900),Color("e0d3b4"))
		for i: int in range(12):
			var key: String = KEYS[i]
			var at := Vector2((i%4)*400,(i/4)*300)
			draw_string(ThemeDB.fallback_font,at+Vector2(12,24),key,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("382817"))
			for side: int in [0,1]:
				var box := Rect2(at+Vector2(12+side*195,35),Vector2(180,170))
				draw_rect(box,Color("f9efd8") if side == 0 else Color("273128"))
				var tex: Texture2D = game.art(key,side)
				draw_texture_rect(tex,game.fitted_rect(tex.get_size(),box,false),false)
				var small := Rect2(at+Vector2(65+side*195,220),Vector2(60,60))
				draw_texture_rect(tex,game.fitted_rect(tex.get_size(),small,true),false)
			draw_line(at+Vector2(0,299),at+Vector2(400,299),Color("b1a180"),1)

func _initialize() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	call_deferred("run")

func snap(label: String) -> void:
	g.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/faction-preview/"+label+".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/faction-preview")
	g = load("res://main.tscn").instantiate()
	root.add_child(g)
	g.set_process(false)
	g.set_physics_process(false)
	g.sound_enabled = false
	g.fx_enabled = true
	g.hide()
	var sheet := Sheet.new()
	sheet.game = g
	root.add_child(sheet)
	await snap("art-sheet")
	sheet.free()
	var cards := Cards.new()
	cards.deck_path = "user://faction-art-preview-deck.json"
	root.add_child(cards)
	for control: Control in cards.ui: control.hide()
	cards.clear_ui()
	cards.set_process(false)
	cards.set_physics_process(false)
	cards.sound_enabled = false
	await snap("cards")
	cards.free()
	g.show()
	g.model = g.Battle.new(77)
	g.model.ai_enabled = [false,false]
	g.model.units.clear()
	g.model.buildings.clear()
	g.model.elapsed = 1.2
	g.adventure.index = -1
	g.enter_battle("")
	for side: int in [0,1]:
		var col := 1 if side == 0 else 7
		for lane: int in range(1,4):
			var kind: String = ["watchtower","mass_grave","blood_tower"][lane-1]
			var b: Dictionary = g.model.add_building(side,Vector2i(col,lane),kind)
			if kind == "mass_grave": b.production = 17
			if kind == "blood_tower":
				b.blood = 250
				b.bleeding = true
		for i: int in range(3):
			var p: Vector2 = g.L.cell_center(Vector2i(3 if side == 0 else 5,1))+Vector2((i-1)*40,0)
			g.model.spawn_unit(side,1,"net_hunter",p)
		g.model.cast_spell({"kind":"charge_horn","team":side,"pos":g.L.cell_center(Vector2i(col,1))})
		var scared: Dictionary = g.model.spawn_unit(side,0,"militia",g.L.cell_center(Vector2i(3 if side == 0 else 5,0)))
		scared.fear_left = 5
		var p: Vector2 = g.L.cell_center(Vector2i(col,4))
		g.model.spawn_unit(1-side,4,"knight",p)
		g.model.cast_spell({"kind":"levy","team":side,"pos":p})
	var strike: Vector2 = g.L.cell_center(Vector2i(3,2))
	for i: int in range(5): g.model.spawn_unit(1,2,"knight",strike+Vector2(i*50,0))
	g.model.cast_spell({"kind":"chain_lightning","team":0,"pos":strike})
	for side: int in [0,1]:
		var p: Vector2 = g.L.cell_center(Vector2i(3 if side == 0 else 5,3))
		g.model.spawn_unit(side,3,"militia",p)
		g.model.cast_spell({"kind":"sacrifice","team":side,"pos":p})
	for u: Dictionary in g.model.units: u.draw = u.pos+Vector2(0,u.dy)
	g.consume_events()
	g._process(0.1)
	await snap("battle-cast")
	g._process(0.25)
	await snap("battle-travel")
	for u: Dictionary in g.model.units.duplicate():
		if u.get("levy",false):
			u.pos = g.L.cell_center(Vector2i(7 if u.team == 0 else 1,4))
			g.model.units.erase(u)
	g.consume_events()
	g._process(0.15)
	await snap("battle-dust")
	g.free()
	print("PASS faction art and both-team effects captured")
	quit()
