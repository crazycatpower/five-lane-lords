extends "res://cinematic_director.gd"
## Episode-specific card headings derived from the actual lord.
func paint_showcase_overlays(g, field: Rect2) -> void:
	if not showcase_card.is_empty():
		var t := 1.0 - float(showcase_card.life) / float(showcase_card.duration)
		var enter := clampf(t / 0.14, 0.0, 1.0)
		var fade := 1.0 - clampf((t - 0.82) / 0.18, 0.0, 1.0)
		var alpha := enter * fade
		var slide := (1.0 - pow(1.0 - enter, 3.0))
		var left_side := int(showcase_card.team) == 0
		var box_w := 430.0
		var box_h := 88.0
		var y := field.position.y + 18.0
		var hidden_x := field.position.x - box_w - 20.0 if left_side else field.end.x + 20.0
		var shown_x := field.position.x + 18.0 if left_side else field.end.x - box_w - 18.0
		var x := lerpf(hidden_x, shown_x, slide)
		var rect := Rect2(x, y, box_w, box_h)
		var accent: Color = Color("c94b3b") if left_side else Color("4a7cc4")
		g.draw_rect(rect, Color(0.11, 0.08, 0.05, 0.88 * alpha))
		g.draw_rect(rect, Color(0.86, 0.71, 0.42, 0.88 * alpha), false, 2.0)
		g.draw_rect(Rect2(rect.position, Vector2(6.0, rect.size.y)), Color(accent, alpha))
		var icon_rect := Rect2(rect.position + Vector2(14.0, 10.0), Vector2(66.0, 68.0))
		g.draw_rect(icon_rect.grow(2.0), Color(0.92, 0.85, 0.70, 0.16 * alpha))
		var art_id: String = B.CARDS.get(showcase_card.kind, {}).get("art", [showcase_card.kind])[0]
		g.draw_fitted(g.art(art_id, int(showcase_card.team)), icon_rect, Color(1, 1, 1, alpha), true)
		var side_txt := B.lord_name(String(g.model.lords[int(showcase_card.team)].lord))
		g.draw_string(g.font, rect.position + Vector2(92.0, 25.0), "%s｜%s" % [side_txt, String(showcase_card.name)], HORIZONTAL_ALIGNMENT_LEFT, 240.0, 21, Color(0.99, 0.91, 0.70, alpha))
		var coin_pos := rect.position + Vector2(rect.size.x - 30.0, 22.0)
		g.draw_circle(coin_pos, 13.0, Color(0.82, 0.62, 0.20, 0.95 * alpha))
		g.draw_arc(coin_pos, 13.0, 0.0, TAU, 20, Color(1.0, 0.93, 0.68, alpha), 1.5, true)
		g.draw_string(g.font, coin_pos + Vector2(-14.0, 6.0), str(int(showcase_card.cost)), HORIZONTAL_ALIGNMENT_CENTER, 28.0, 16, Color(0.14, 0.09, 0.04, alpha))
		g.draw_string(g.font, rect.position + Vector2(92.0, 47.0), "[%s]" % String(showcase_card.role), HORIZONTAL_ALIGNMENT_LEFT, box_w - 106.0, 14, Color(accent.lightened(0.45), alpha))
		g.draw_string(g.font, rect.position + Vector2(92.0, 72.0), String(showcase_card.desc), HORIZONTAL_ALIGNMENT_LEFT, box_w - 106.0, 16, Color(0.95, 0.91, 0.82, alpha))

	if not showcase_chapter.is_empty():
		var t := 1.0 - float(showcase_chapter.life) / float(showcase_chapter.duration)
		var alpha := clampf(t / 0.18, 0.0, 1.0) * (1.0 - clampf((t - 0.76) / 0.24, 0.0, 1.0))
		var cw := 680.0
		var ch := 84.0
		var cx := field.get_center().x - cw * 0.5
		var cy := field.position.y + 114.0
		var rect := Rect2(cx, cy, cw, ch)
		g.draw_rect(rect, Color(0.09, 0.07, 0.05, 0.86 * alpha))
		g.draw_rect(rect.grow(-4.0), Color(0.86, 0.70, 0.40, 0.85 * alpha), false, 1.8)
		g.draw_string(g.font, rect.position + Vector2(0.0, 40.0), String(showcase_chapter.title), HORIZONTAL_ALIGNMENT_CENTER, cw, 28, Color(0.99, 0.92, 0.72, alpha))
		if not String(showcase_chapter.sub).is_empty():
			g.draw_string(g.font, rect.position + Vector2(0.0, 66.0), String(showcase_chapter.sub), HORIZONTAL_ALIGNMENT_CENTER, cw, 16, Color(0.88, 0.81, 0.68, alpha))

	if not showcase_sub.is_empty():
		var t := 1.0 - float(showcase_sub.life) / float(showcase_sub.duration)
		var alpha := clampf(t / 0.12, 0.0, 1.0) * (1.0 - clampf((t - 0.84) / 0.16, 0.0, 1.0))
		var sw := 880.0
		var sh := 36.0
		var rect := Rect2(field.get_center().x - sw * 0.5, field.end.y - sh - 12.0, sw, sh)
		g.draw_rect(rect, Color(0.08, 0.06, 0.04, 0.84 * alpha))
		var rim := Color(0.84, 0.69, 0.42, 0.75 * alpha)
		g.draw_rect(rect, rim, false, 1.4)
		var s_team := int(showcase_sub.team)
		if s_team >= 0:
			var dot_col: Color = g.RED if s_team == 0 else g.BLUE
			g.draw_circle(rect.position + Vector2(22.0, sh * 0.5), 5.5, Color(dot_col.lightened(0.2), alpha))
		g.draw_string(g.font, rect.position + Vector2(0.0, 24.0), String(showcase_sub.text), HORIZONTAL_ALIGNMENT_CENTER, sw, 18, Color(0.98, 0.93, 0.82, alpha))
