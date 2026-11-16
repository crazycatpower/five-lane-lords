extends RefCounted
const B = preload("res://balance.gd")
var seen := {}
var last_time := -10.0

static func open(g) -> void:
	g.replay_enabled = true
	g.save_settings()
	g.screen = "recording"
	g.clear_ui()
	var panel := Panel.new()
	panel.position = Vector2(340, 130)
	panel.size = Vector2(920, 620)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("efe0bd")
	style.border_color = Color("866639")
	style.set_border_width_all(3)
	panel.add_theme_stylebox_override("panel", style)
	g.add_child(panel)
	g.ui.append(panel)
	var text := Label.new()
	text.position = Vector2(390, 165)
	text.size = Vector2(820, 350)
	text.add_theme_font_override("font", g.font)
	text.add_theme_font_size_override("font_size", 25)
	text.add_theme_color_override("font_color", Color("382b20"))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = "錄影模式｜自己打一局\n\n使用目前牌組，對戰電腦。正常操作，不顯示遮擋戰場的卡牌特寫。\n\n結束後自動保存重播與剪輯筆記；在結算頁按「輸出 MP4」。影片會加上卡牌能力說明與大招特寫。\n\n請在更新遊戲或平衡前輸出影片。"
	g.add_child(text)
	g.ui.append(text)
	g.title_button(Rect2(390, 550, 360, 60), "開始錄影對局", func():
		g.net = null
		g.spectating = false
		g.me = 0
		g.mirror_view = false
		g.seed_value = int(Time.get_unix_time_from_system())
		g.roll_practice_opponent()
		g.start_battle(), true)
	g.title_button(Rect2(790, 550, 360, 60), "調整我的牌組", g.show_deck)
	g.title_button(Rect2(590, 650, 420, 50), "回到標題", g.show_title)
	g.queue_redraw()

static func explanation(kind: String) -> String:
	if not B.CARDS.has(kind): return ""
	if kind == "phase_rider":
		return "登場時不會被直接鎖定，也不觸發陷阱。攻擊或被偵查後永久現形；仍會受到範圍傷害。"
	var lines := B.card_description(kind).split("\n", false)
	var detail := String(lines[-1]) if not lines.is_empty() else ""
	# Use the actual rule description, never repeat the role label.
	return detail.split("。", false)[0] + "。" if not detail.is_empty() else ""

func observe(g, event: Dictionary) -> void:
	if not g.recorder.replaying or String(event.get("kind", "")) != "play": return
	var kind := String(event.get("card", ""))
	if seen.has(kind) or g.clock - last_time < 7.0: return
	seen[kind] = true
	last_time = g.clock
	g.cinematic.trigger_spotlight(g, event.get("pos", Vector2(800,394)), int(event.get("team",0)), kind, explanation(kind), 1.12, 2.0, 6.0)
