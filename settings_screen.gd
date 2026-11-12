extends RefCounted
# 設定 (2026-11-12): music and sound volume, full screen, effects and shake. Opened from the title
# or from the pause banner of a local battle (g.settings_return says where "back" leads).
const PANEL := Rect2(410,130,780,640)
const ROWS := ["音樂音量","音效音量","全螢幕","戰鬥特效","畫面震動"]
const ROW_Y := 268.0
const ROW_STEP := 74.0
const CONTROL_X := 720.0
static var knob_texture: ImageTexture

# A vermilion wax-seal knob with a gold rim for the sliders.
static func knob() -> ImageTexture:
	if knob_texture != null: return knob_texture
	var size := 30
	var img := Image.create(size,size,false,Image.FORMAT_RGBA8)
	var c := Vector2(size*0.5-0.5,size*0.5-0.5)
	for y: int in range(size):
		for x: int in range(size):
			var d := Vector2(x,y).distance_to(c)
			if d > 14.0: continue
			var color := Color("d2ad58") if d > 11.0 else (Color("7a2e22") if d > 9.5 else Color("a84534"))
			color.a = clampf(14.5-d,0,1)
			img.set_pixel(x,y,color)
	knob_texture = ImageTexture.create_from_image(img)
	return knob_texture

static func row_y(i: int) -> float:
	return ROW_Y+i*ROW_STEP

static func slider(g, i: int, value: float, changed: Callable) -> HSlider:
	var s := HSlider.new()
	s.position = Vector2(CONTROL_X,row_y(i)-24)
	s.size = Vector2(330,36)
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("cdb88f")
	track.border_color = Color("846539")
	track.set_border_width_all(2)
	track.set_corner_radius_all(5)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var filled := StyleBoxFlat.new()
	filled.bg_color = Color("b8862b")
	filled.set_corner_radius_all(5)
	s.add_theme_stylebox_override("slider",track)
	s.add_theme_stylebox_override("grabber_area",filled)
	s.add_theme_stylebox_override("grabber_area_highlight",filled)
	for icon: String in ["grabber","grabber_highlight","grabber_disabled"]: s.add_theme_icon_override(icon,knob())
	s.value_changed.connect(func(v: float): changed.call(v))
	s.drag_ended.connect(func(_moved: bool):
		g.save_settings()
		if g.sound != null: g.sound.cue("ui_click")) # a sample at the new level
	g.add_child(s)
	g.ui.append(s)
	return s

static func toggle(g, i: int, on: bool, action: Callable) -> Button:
	return g.title_button(Rect2(CONTROL_X,row_y(i)-30,150,44),"開啟" if on else "關閉",action,on)

static func build(g) -> void:
	g.screen = "settings"
	g.clear_ui()
	slider(g,0,g.music_volume,func(v: float): g.music_volume = v; g.apply_audio_settings())
	slider(g,1,g.sfx_volume,func(v: float): g.sfx_volume = v; g.apply_audio_settings())
	toggle(g,2,g.fullscreen,func(): g.set_fullscreen(not g.fullscreen); build(g))
	toggle(g,3,g.fx_enabled,func(): g.fx_enabled = not g.fx_enabled; g.effects.clear(); g.save_settings(); build(g))
	toggle(g,4,g.shake_enabled,func(): g.shake_enabled = not g.shake_enabled; g.save_settings(); build(g))
	g.title_button(Rect2(650,662,300,54),"回到戰局" if g.settings_return == "battle" else "回到標題",func(): back(g),true)
	g.queue_redraw()

static func back(g) -> void:
	g.save_settings()
	if g.settings_return == "battle" and g.model != null and not g.model.ended:
		g.settings_return = "title"
		g.clear_ui()
		g.screen = "battle" # still paused: the banner is where the player left it
		g.queue_redraw()
	else:
		g.settings_return = "title"
		g.show_title()

static func paint(g) -> void:
	g.panel(PANEL,Color("efe0bd"))
	g.ink_frame(PANEL.grow(-8))
	g.draw_fitted(g.ART.ornament(4),Rect2(PANEL.position.x+PANEL.size.x*0.5-150,PANEL.position.y+18,300,36))
	g.draw_string(g.font,Vector2(PANEL.position.x,PANEL.position.y+100),"設定",HORIZONTAL_ALIGNMENT_CENTER,PANEL.size.x,44,g.INK)
	for i: int in range(ROWS.size()):
		g.label_at(Vector2(PANEL.position.x+90,row_y(i)),ROWS[i],24)
		if i < ROWS.size()-1: g.draw_line(Vector2(PANEL.position.x+70,row_y(i)+30),Vector2(PANEL.end.x-70,row_y(i)+30),Color(g.INK,0.18),1)
	g.draw_string(g.font,Vector2(CONTROL_X+340,row_y(0)),"%d%%" % roundi(g.music_volume*100),HORIZONTAL_ALIGNMENT_RIGHT,70,20,Color("6f5a3e"))
	g.draw_string(g.font,Vector2(CONTROL_X+340,row_y(1)),"%d%%" % roundi(g.sfx_volume*100),HORIZONTAL_ALIGNMENT_RIGHT,70,20,Color("6f5a3e"))
	g.label_at(Vector2(CONTROL_X+170,row_y(2)),"F11 隨時切換",17,Color("6f5a3e"))
	g.label_at(Vector2(CONTROL_X+170,row_y(3)),"光效、飛行金幣與落葉",17,Color("6f5a3e"))
	g.label_at(Vector2(CONTROL_X+170,row_y(4)),"破門時的畫面晃動",17,Color("6f5a3e"))
	g.draw_string(g.font,Vector2(PANEL.position.x,PANEL.end.y-24),"羊皮紙戰記 %s" % g.VERSION,HORIZONTAL_ALIGNMENT_CENTER,PANEL.size.x,15,Color(g.INK,0.55))
