extends RefCounted
# Final coronation & multi-world summary after clearing 5-10 王都鐵壁城門.
const Catalog = preload("res://campaign_catalog.gd")

func show(g) -> void:
	g.screen = "adventure_finale"
	g.clear_ui()
	var a = g.adventure
	g.title_button(Rect2(1060,664,390,52),"開啟第 %d 周目（保留解鎖與詔令）" % (a.ng_plus + 2),func(): a.start_ng_plus(g),true).grab_focus()
	g.title_button(Rect2(1060,730,390,52),"返回五路遠征地圖",g.show_adventure)
	g.queue_redraw()

func paint(g) -> void:
	var a = g.adventure
	var per := Catalog.STAGES_PER_WORLD
	g.label_at(Vector2(100,100),"五域凱旋 · 加冕之日",44)
	g.label_at(Vector2(1030,220),"王座有主，故事未完",30)
	var words := "王都的鐘聲響起，五域破損的古碑重歸正軌。\n從老隊長的「第一道命令」學起的邊境領主，踏過運河、星塔與冥澤，走到鐵壁王座前。\n\n本輪遠征累計獲得 ★ %d / %d。\n你可以挑戰更高難度拿滿 %d ★，或直接開啟第 %d 周目繼續征戰！" % [a.total_stars(), a.max_stars(), a.max_stars(), a.ng_plus + 2]
	g.draw_multiline_string(g.font, Vector2(1030,275), words, HORIZONTAL_ALIGNMENT_LEFT, 460, 21, 8, g.INK)
	g.panel(Rect2(80,170,900,630),Color("e5d1a8"))
	for w: int in range(Catalog.WORLDS.size()):
		var winfo: Dictionary = Catalog.WORLDS[w]
		var wy: float = 224.0 + w * 112.0
		g.draw_line(Vector2(138, wy), Vector2(896, wy), Color(g.RED, 0.72), 4.0, true)
		g.label_at(Vector2(115, wy - 28), winfo.name, 20, winfo.color.darkened(0.15))
		g.draw_string(g.font, Vector2(760, wy - 28), "★ %d / %d" % [a.world_stars(w), per * Catalog.MAX_STARS_PER_STAGE], HORIZONTAL_ALIGNMENT_RIGHT, 170, 18, Color("7c4914"))
		for k: int in range(per):
			var idx := w * per + k
			var sd: Dictionary = a.STAGES[idx]
			var px := 148.0 + k * 82.0
			var p := Vector2(px, wy)
			var r := 19.0 if k == 9 else (16.0 if k == 4 else 13.0)
			g.draw_circle(p, r, g.RED)
			if k == 4 or k == 9:
				g.draw_arc(p, r + 2.5, 0, TAU, 24, Color("e6b830"), 2.0, true)
			g.draw_fitted(g.art("crest"), Rect2(p - Vector2(r * 0.65, r * 0.70), Vector2(r * 1.3, r * 1.4)))
			g.draw_string(g.font, p + Vector2(-28, r + 18), sd.code, HORIZONTAL_ALIGNMENT_CENTER, 56, 13, Color("7c4914") if (k == 4 or k == 9) else g.INK)
	g.label_at(Vector2(1030,618),"已收集 %d 張冒險卡牌 · %d 位出征領主" % [a.unlocked_cards().size(), a.unlocked_lords().size()],19,Color("5a4632"))
