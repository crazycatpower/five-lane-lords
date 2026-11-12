extends RefCounted
# Presentation only: conquest progress is already saved by adventure.settle().
const Catalog = preload("res://campaign_catalog.gd")

func show(g) -> void:
	g.screen = "adventure_finale"
	g.clear_ui()
	var words := "王都的鐘聲響起，四方的旗幟終於低了下來。\n從第一塊農田出發的領主，走到了空置的王座前。\n\n史官收起各色顏料，在地圖上落下最後一筆朱紅。\n新王接過王冠，說的第一句話卻是：\n「明年的稅，等莊稼收了再談。」"
	var text = g.library.text_box(Rect2(1030,300,460,310),words,23)
	text.scroll_active = false
	g.title_button(Rect2(1060,730,390,56),"返回領地 · 繼續征戰",g.show_adventure,true).grab_focus()
	g.queue_redraw()

func paint(g) -> void:
	g.label_at(Vector2(100,100),"加冕之日",48)
	g.label_at(Vector2(1030,240),"王座有主，故事未完",30)
	g.panel(Rect2(80,170,900,630),Color("e5d1a8"))
	# A commemorative map, not a mutation of the player's conquered territories.
	for d: Dictionary in Catalog.stages():
		var p: Vector2 = Vector2(105,180)+(d.map-Vector2(100,150))*Vector2(0.94,0.86)
		g.ground_wash(p,Vector2(65,55),g.RED,d.chapter*13+7,0.16)
		for id: String in d.links:
			var other: Dictionary = Catalog.stages()[Catalog.index_of(id)]
			var q: Vector2 = Vector2(105,180)+(other.map-Vector2(100,150))*Vector2(0.94,0.86)
			g.ink_line(p,q,d.chapter,Color(g.RED,0.65),3)
		g.draw_circle(p,20,g.RED)
		g.draw_fitted(g.art("crest"),Rect2(p-Vector2(14,16),Vector2(28,32)))
		g.draw_string(g.font,p+Vector2(-75,40),d.name,HORIZONTAL_ALIGNMENT_CENTER,150,17,g.INK)
	g.label_at(Vector2(1030,655),"史官記：王國至此，始得一頁安寧。",20)
	g.label_at(Vector2(1030,690),"冒險完成 · 已征服的領地仍可重打",19)
