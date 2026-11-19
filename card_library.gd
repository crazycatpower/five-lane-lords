extends RefCounted
const B = preload("res://balance.gd")
const Lore = preload("res://card_lore.gd")
const Keywords = preload("res://card_keywords.gd")
const CardSort = preload("res://card_sort.gd")
const Style = preload("res://command_style.gd")
const Ornament = preload("res://interface_ornament.gd")
const INFO_RECT := Rect2(1418,28,148,48) # top-right corner: the top centre is kept for the clock
const LEFT_PANEL := Rect2(56,52,804,738)
const RIGHT_PANEL := Rect2(886,52,658,798)
var game
var category := "all"
var faction := "all"
var sort_mode := "group"
var page := 0
var selected := "farm"
var return_screen := "title"
var was_paused := false

func _init(owner_game) -> void:
	game = owner_game

func entries() -> Array[String]:
	var result: Array[String] = []
	if category == "lord":
		var lords: Array = []
		for k: String in B.LORDS:
			lords.append("lord_" + k)
		for lk in CardSort.sort_lords(lords, faction):
			result.append(str(lk))
		return result
	var cards: Array = []
	for kind: String in B.CARDS:
		if B.CARDS[kind].get("unreleased", false):
			continue
		if CardSort.matches_category(kind, category) and CardSort.matches_faction(kind, faction, false):
			cards.append(kind)
	for ck in CardSort.sort_cards(cards, sort_mode):
		result.append(str(ck))
	if category == "all":
		var lords: Array = []
		for k: String in B.LORDS:
			lords.append("lord_" + k)
		for lk in CardSort.sort_lords(lords, faction):
			result.append(str(lk))
	return result

func open(kind: String = "", origin: String = "title") -> void:
	return_screen = origin
	if not kind.is_empty():
		selected = kind
		faction = "all"
		if kind.begins_with("lord_"):
			category = "lord"
		elif B.CARDS.has(kind):
			category = ["melee","ranged","spell","building"][B.card_group(kind)]
		else:
			category = "all"
		var idx := entries().find(kind)
		page = maxi(0, idx) / 12
	show_catalog()

func step_page(delta: int) -> void:
	var list := entries()
	var total := maxi(1, ceili(list.size() / 12.0))
	if total <= 1:
		return
	var next_page := clampi(page + delta, 0, total - 1)
	if next_page != page:
		page = next_page
		if game.sound != null:
			game.sound.cue("page_turn")
		show_catalog()

func step_entry(delta: int) -> void:
	var list := entries()
	if list.is_empty():
		return
	var idx := list.find(selected)
	if idx < 0:
		idx = 0
	var next_idx := clampi(idx + delta, 0, list.size() - 1)
	if next_idx != idx:
		selected = list[next_idx]
		page = next_idx / 12
		if game.sound != null:
			game.sound.cue("ui_hover")
		show_catalog()

func text_box(rect: Rect2, text: String, size: int = 20) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.position = rect.position
	label.size = rect.size
	label.bbcode_enabled = true
	label.text = Keywords.colorize_bbcode(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("line_separation",4)
	label.add_theme_font_override("normal_font",game.font)
	label.add_theme_font_size_override("normal_font_size",size)
	label.add_theme_color_override("default_color",game.INK)
	game.add_child(label)
	game.ui.append(label)
	return label

func _compact_filter_button(rect: Rect2, caption: String, action: Callable, active: bool, active_fill: Color) -> Button:
	var b: Button = game.title_button(rect, caption, action, active)
	b.add_theme_font_size_override("font_size", 15)
	if active:
		for state: String in ["normal","hover","pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = active_fill.lightened(0.12) if state == "hover" else (active_fill.darkened(0.12) if state == "pressed" else active_fill)
			style.border_color = Color("d2ad58")
			style.set_border_width_all(2)
			style.set_corner_radius_all(2)
			b.add_theme_stylebox_override(state, style)
	return b

func show_catalog() -> void:
	game.screen = "codex"
	game.clear_ui()
	var tabs := [["all","全部"],["melee","近戰"],["ranged","遠程"],["spell","法術"],["building","建築"],["lord","領主"]]
	for i: int in range(tabs.size()):
		var filter: String = tabs[i][0]
		var tb: Button = game.title_button(Rect2(80+i*128,108,120,36),tabs[i][1],func(): category = filter; page = 0; show_catalog(),category == filter)
		tb.add_theme_font_size_override("font_size", 18)
	for i: int in range(CardSort.FACTION_FILTERS.size()):
		var f_key: String = CardSort.FACTION_FILTERS[i][0]
		var f_name: String = CardSort.FACTION_FILTERS[i][1]
		var f_col: Color = Style.TAGS.get(f_key, Style.TAGS[""]) if f_key != "all" else Color("963f30")
		_compact_filter_button(Rect2(80+i*128,150,120,30), f_name, func(): faction = f_key; page = 0; show_catalog(), faction == f_key, f_col)
	if category != "lord":
		var sort_btn: Button = game.title_button(Rect2(624,64,214,34),"排序：%s ▾" % CardSort.mode_label(sort_mode),func(): sort_mode = CardSort.next_mode(sort_mode); page = 0; show_catalog())
		sort_btn.add_theme_font_size_override("font_size", 15)
	var list := entries()
	var total_pages := maxi(1, ceili(list.size() / 12.0))
	page = clampi(page, 0, total_pages - 1)
	if not list.is_empty() and not selected in list:
		selected = list[0]
	for i: int in range(page*12,mini((page+1)*12,list.size())):
		var kind := list[i]
		var r := catalog_rect(i%12)
		var hit = game.button(r,"",func(): selected = kind; show_catalog())
		hit.modulate.a = 0.01
		hit.tooltip_text = entry_name(kind)
	game.title_button(Rect2(56,804,168,46),"返回",back)
	var prev_btn: Button = game.title_button(Rect2(436,804,132,46),"上一頁",func(): step_page(-1))
	prev_btn.disabled = page <= 0
	var next_btn: Button = game.title_button(Rect2(728,804,132,46),"下一頁",func(): step_page(1))
	next_btn.disabled = (page + 1) * 12 >= list.size()
	if not list.is_empty() and (selected.begins_with("lord_") and B.LORDS.has(selected.trim_prefix("lord_")) or B.CARDS.has(selected)):
		var lord := selected.begins_with("lord_")
		var lord_id := selected.trim_prefix("lord_")
		var rules: String = B.skill_text(lord_id) if lord else B.card_description(selected)
		# The cost / cooldown line is already on the header strip above, so the codex drops it here.
		if not lord and rules.contains("\n"): rules = rules.substr(rules.find("\n")+1)
		text_box(Rect2(926,434,578,202),rules,18)
		text_box(Rect2(926,684,578,122),Lore.TEXT.get(selected,""),18)
	game.queue_redraw()

func back() -> void:
	if return_screen == "battle_info": show_battle_info(false)
	else: game.show_title()

static func catalog_rect(index: int) -> Rect2:
	return Rect2(100+(index%4)*186,192+(index/4)*194,158,178)

static func entry_name(kind: String) -> String:
	if kind.begins_with("lord_"):
		var lk := kind.trim_prefix("lord_")
		return B.LORDS[lk].name if B.LORDS.has(lk) else lk
	return B.CARDS[kind].name if B.CARDS.has(kind) else kind

func draw_catalog() -> void:
	var list := entries()
	var total_pages := maxi(1, ceili(list.size() / 12.0))
	var mouse: Vector2 = game.get_global_mouse_position()
	game.panel(LEFT_PANEL)
	game.label_at(Vector2(80,92),"卡牌圖鑑",30)
	game.label_at(Vector2(218,90),"共 %d 項" % list.size(),16,Color("6f5a3e"))
	if list.is_empty():
		game.draw_string(game.font,Vector2(LEFT_PANEL.position.x,470),"此篩選條件下沒有符合的條目",HORIZONTAL_ALIGNMENT_CENTER,LEFT_PANEL.size.x,22,Color("6f5a3e"))
	else:
		for i: int in range(page*12,mini((page+1)*12,list.size())):
			var kind: String = list[i]
			var r := catalog_rect(i%12)
			var hv: float = game.polish.hover_val("codex_card_%s" % kind, r.has_point(mouse), game.is_processing())
			r.position.y -= 4.0 * hv
			if kind == selected:
				game.panel(r.grow(4),Color("b8c594"),Color("52633c"))
			elif hv > 0.01:
				game.polish.draw_card_hover_glow(game, r, hv)
			if kind.begins_with("lord_"):
				game.draw_lord_card(kind.trim_prefix("lord_"), r, false)
			else:
				game.draw_card(kind,r)
	game.draw_string(game.font,Vector2(568,834),"%d / %d" % [page+1,total_pages],HORIZONTAL_ALIGNMENT_CENTER,160,19,game.INK)
	game.panel(RIGHT_PANEL)
	game.draw_fitted(game.ART.ornament(4),Rect2(RIGHT_PANEL.position.x+RIGHT_PANEL.size.x*0.5-150.0,60,300,32))
	var valid_sel := (selected.begins_with("lord_") and B.LORDS.has(selected.trim_prefix("lord_"))) or B.CARDS.has(selected)
	if valid_sel:
		var is_lord := selected.begins_with("lord_")
		var lord_id := selected.trim_prefix("lord_")
		var f_key: String = B.lord_faction(lord_id) if is_lord else B.card_faction(selected)
		var f_tint: Color = Style.TINTS.get(f_key, Color("efe3c8"))
		game.draw_string(game.font,Vector2(906,118),entry_name(selected),HORIZONTAL_ALIGNMENT_CENTER,618,34,game.INK)
		var art_frame := Rect2(926,134,578,206)
		game.panel(art_frame, Color("f4ebd4").lerp(f_tint, 0.30), Color("8c6e43"))
		var art_box := Rect2(1038,140,354,194)
		if is_lord: game.draw_fitted(game.art(selected),art_box)
		else: game.draw_card_art(selected,art_box)
		var sum_rect := Rect2(926,350,578,40)
		game.panel(sum_rect, Color("f4ead0"), Color("8a6f4a"))
		var tag_col: Color = Style.TAGS.get(f_key, Style.TAGS[""])
		Ornament.ribbon_tag(game, Rect2(sum_rect.position.x+12, sum_rect.position.y+9, 54, 22), B.FACTIONS[f_key], tag_col, 13)
		if is_lord:
			var ldata: Dictionary = B.lord_data(lord_id)
			var home := B.home_card(lord_id)
			var meta_l := "領主 · %s" % String(ldata.get("role",""))
			game.label_at(Vector2(sum_rect.position.x+78, sum_rect.position.y+26), meta_l, 15, game.INK)
			var right_l := "生命 %d · 充能 %d" % [int(ldata.get("hp",0)), int(B.skill_charge_need(lord_id))]
			if not home.is_empty() and B.CARDS.has(home):
				right_l += " · 常駐 %s" % B.CARDS[home].name
			game.draw_string(game.font, Vector2(sum_rect.position.x+210, sum_rect.position.y+26), right_l, HORIZONTAL_ALIGNMENT_RIGHT, sum_rect.size.x-222, 15, Color("5a4632"))
		else:
			var cdata: Dictionary = B.CARDS[selected]
			var grp_name: String = CardSort.GROUP_NAMES[B.card_group(selected)]
			var meta_c := "%s · %s" % [grp_name, String(cdata.get("role",""))]
			if cdata.get("summon_only", false):
				meta_c += "（召喚限定）"
			game.label_at(Vector2(sum_rect.position.x+78, sum_rect.position.y+26), meta_c, 15, game.INK)
			var cost_txt := "消耗全部金幣" if cdata.get("pay_all", false) else "金幣 %d" % int(cdata.cost)
			var right_c := "%s · 冷卻 %s 秒" % [cost_txt, B.number(cdata.cooldown)]
			game.draw_string(game.font, Vector2(sum_rect.position.x+270, sum_rect.position.y+26), right_c, HORIZONTAL_ALIGNMENT_RIGHT, sum_rect.size.x-282, 15, Color("5a4632"))
		game.label_at(Vector2(926,418),"卡牌說明",21)
		var kws: Array[String] = Keywords.for_lord(lord_id) if is_lord else Keywords.for_card(selected)
		Keywords.draw_badges(game,Vector2(1028,417),kws,14,476.0)
		Ornament.rule(game, Vector2(926,646), Vector2(1504,646), game.INK)
		game.label_at(Vector2(926,674),"卡牌趣聞",21)
	game.draw_string(game.font,Vector2(926,832),"滾輪翻頁 · ← → 切換條目 · Esc 返回",HORIZONTAL_ALIGNMENT_CENTER,578,14,Color("766248"))

func show_battle_info(entering: bool = true) -> void:
	if entering:
		was_paused = game.model.paused
		game.model.paused = true
		game.dragging = false
	game.screen = "battle_info"
	game.clear_ui()
	game.title_button(Rect2(90,804,220,48),"返回對戰",close_battle_info)
	game.title_button(Rect2(1270,804,230,48),"完整圖鑑",func(): open("","battle_info"))
	for team: int in range(2):
		var kinds: Array = [game.model.home_cards[team]]+game.model.decks[team].duplicate()
		for i: int in range(kinds.size()):
			var kind: String = kinds[i]
			if kind.is_empty(): continue
			var hit = game.button(deck_rect(team,i),"",func(): open(kind,"battle_info"))
			hit.modulate.a = 0.01
			hit.tooltip_text = game.card_description(kind)+"\n\n（點擊開啟完整圖鑑）"
		var raw_lord: String = game.model.lords[team].lord
		var is_camp: bool = team == 1 and game.adventure.index >= 0 and game.adventure.STAGES[game.adventure.index].enemy_camp
		var target_entry: String = "bandit" if is_camp else (B.MINION_LORDS[raw_lord].card if B.is_minion(raw_lord) else "lord_"+raw_lord)
		var hit = game.button(Rect2(95,215+team*285,132,170),"",func(): open(target_entry,"battle_info"))
		hit.modulate.a = 0.01
		hit.tooltip_text = game.Ceremony.side_name(game,team)+" · 查看圖鑑"
	game.queue_redraw()

func close_battle_info() -> void:
	game.clear_ui()
	game.screen = "battle"
	game.model.paused = was_paused
	game.queue_redraw()

static func deck_rect(team: int, index: int) -> Rect2:
	return Rect2(248+index*139,215+team*285,122,174)

func composition(team: int) -> String:
	var counts := {"unit":0,"building":0,"spell":0}
	for kind: String in game.model.decks[team]: counts[B.CARDS[kind].type] += 1
	return "八張輪轉牌：部隊 %d · 建築 %d · 法術 %d" % [counts.unit,counts.building,counts.spell]

func draw_battle_info() -> void:
	game.panel(Rect2(62,62,1476,712))
	game.label_at(Vector2(90,111),"戰局資料",38)
	var mode_line: String = "難度："+["簡單","普通","困難"][game.model.difficulty]
	if game.rogue.in_battle and not game.rogue.run.is_empty():
		mode_line = "肉鴿 第 %d / %d 場 · AI %s" % [game.rogue.battle_floor_number(),game.rogue.Catalog.FLOORS,["簡單","普通","困難"][game.model.difficulty]]
	elif game.adventure.index >= 0:
		mode_line = "征服 · %s（%s）" % [game.adventure.STAGES[game.adventure.index].name,["簡單","普通","困難"][game.model.difficulty]]
	game.label_at(Vector2(310,107),mode_line,24)
	game.label_at(Vector2(1120,107),"閱讀中暫停 · 點卡牌查看趣聞",19)
	for team: int in range(2):
		var y := 175+team*285
		var lord: String = game.model.lords[team].lord
		var side_title: String = ["紅方","藍方"][team]+" · "+game.Ceremony.side_name(game,team)
		game.label_at(Vector2(95,y),side_title,24,game.RED if team == 0 else game.BLUE)
		game.label_at(Vector2(650,y),composition(team),21)
		if game.rogue.in_battle and not game.rogue.run.is_empty():
			var sub_note: String = ""
			if team == 0:
				var r_names: Array = game.rogue.run.get("relics",[]).map(func(k: String) -> String: return game.rogue.Catalog.RELICS[k].name)
				sub_note = "持有遺物："+("、".join(r_names) if not r_names.is_empty() else "無")
			else:
				var mut: Dictionary = game.rogue.Catalog.mutator_data(game.rogue.active_slot())
				var m_line: String = (" · 異變【%s】%s" % [String(mut.name),String(mut.desc)]) if not mut.is_empty() else ""
				sub_note = (("敵方被動："+B.minion_text(lord)) if B.is_minion(lord) else ("敵方技能："+B.skill_text(lord)))+m_line
			game.label_at(Vector2(248,y+28),sub_note,16,Color("5a4632"))
		elif game.adventure.index >= 0 and team == 1 and not game.adventure.STAGES[game.adventure.index].enemy_camp:
			var adv_note: String = ("守將特性："+B.minion_text(lord)) if B.is_minion(lord) else ("守將技能："+B.skill_text(lord))
			game.label_at(Vector2(248,y+28),adv_note,16,Color("5a4632"))
		game.draw_fitted(game.Ceremony.side_portrait(game,team),Rect2(95,y+40,132,170))
		var kinds: Array = [game.model.home_cards[team]]+game.model.decks[team].duplicate()
		for i: int in range(kinds.size()):
			if not kinds[i].is_empty(): game.draw_card(kinds[i],deck_rect(team,i)) # a lord without farms has no home card
		game.label_at(Vector2(275,y+241),"常駐牌",16)
	game.label_at(Vector2(95,750),"牌組構成依本局實際配置顯示；輪轉順序會隨出牌改變。",19)
