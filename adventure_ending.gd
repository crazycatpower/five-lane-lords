extends RefCounted
# First victory recruitment scene. Decisions are saved before leaving the scene.
const BANDIT = preload("res://assets/manuscript-v1/bandit.png")
const KNIGHT = preload("res://assets/manuscript-v1/knight.png")
var step := 0
var error := ""

func begin(g) -> void:
	step = 0
	error = ""
	show(g)

func show(g) -> void:
	g.screen = "adventure_ending"
	g.clear_ui()
	var speaker := "強盜"
	var words := "老王一死，各地領主都在搶地盤，我們村子三天換了三面旗。\n搶您的田是我們不對。領主大人若肯收留，前面的路我們替您帶。"
	if step == 1:
		speaker = "騎士"
		words = "別信盜賊！我原本替老王巡路，如今王座空著，路上全是這種人。\n請讓我為您效力。至少您的田，是自己種的。"
	elif step == 2:
		speaker = "領主的抉擇"
		words = "收留強盜，讓他們帶路贖罪；或接受騎士效忠。\n只能招募其中一方。"
	elif step == 3:
		var bandit: bool = g.adventure.recruit == "bandit"
		speaker = "強盜歸順" if bandit else "騎士宣誓"
		words = ("領主：再搶百姓的糧，我絕不寬恕。\n強盜：記住了，大人。前面的驛站，我熟。" if bandit else "領主：留下吧。這條路上需要一個說真話的人。\n騎士：以我的劍起誓。")
	g.library.text_box(Rect2(115,610,1370,48),speaker,30)
	var dialogue = g.library.text_box(Rect2(115,666,1370,100),words,26)
	dialogue.scroll_active = false
	if step < 2:
		g.title_button(Rect2(1200,784,280,54),"繼續",func(): step += 1; show(g),true).grab_focus()
	elif step == 2:
		g.title_button(Rect2(130,782,620,58),"留活口 盜賊加入",func(): choose(g,"bandit"))
		g.title_button(Rect2(850,782,620,58),"一個不留 騎士加入",func(): choose(g,"knight"))
	else:
		g.title_button(Rect2(1200,784,280,54),"前往征服地圖",g.show_adventure,true).grab_focus()
	if not error.is_empty(): g.library.text_box(Rect2(115,852,1370,30),error,18)
	g.queue_redraw()

func choose(g, kind: String) -> void:
	if step != 2 or not kind in ["bandit","knight"]: return
	if not g.adventure.recruit.is_empty(): return
	var was_cleared: bool = g.adventure.is_cleared(g.adventure.index)
	g.adventure.recruit = kind
	g.adventure.cleared[g.adventure.STAGES[g.adventure.index].id] = true
	if not g.adventure.save_progress():
		g.adventure.recruit = ""
		if not was_cleared: g.adventure.cleared.erase(g.adventure.STAGES[g.adventure.index].id)
		error = "進度儲存失敗，請再試一次。"
		show(g)
		return
	g.adventure.outcome = "守住第一塊農田！獲得："+g.B.CARDS[kind].name
	g.adventure.selected = g.adventure.frontier()
	step = 3
	error = ""
	show(g)

func portrait(g, texture: Texture2D, box: Rect2, dim: bool, mirror: bool = true) -> void:
	var rect: Rect2 = g.fitted_rect(texture.get_size(),box,true)
	if mirror: g.draw_set_transform(Vector2(rect.position.x*2+rect.size.x,0),0,Vector2(-1,1))
	g.draw_texture_rect(texture,rect,false,Color(0.60,0.57,0.51,0.75) if dim else Color.WHITE)
	g.draw_set_transform(Vector2.ZERO)

func paint(g) -> void:
	g.draw_rect(Rect2(28,28,1544,844),Color(0.18,0.15,0.10,0.18))
	g.label_at(Vector2(80,85),"邊境 · 戰後抉擇",36)
	g.label_at(Vector2(80,123),"抓到了俘虜，還有個路過的騎士。",22)
	portrait(g,BANDIT,Rect2(125,150,600,430),step == 1 or (step == 3 and g.adventure.recruit == "knight"),false) # left side, art already faces right
	if step >= 1:
		portrait(g,KNIGHT,Rect2(875,135,600,445),step == 0 or (step == 3 and g.adventure.recruit == "bandit"))
	g.panel(Rect2(80,590,1440,270),Color("eddfbc"))
	g.draw_line(Vector2(110,655),Vector2(1490,655),Color("ad8b50"),2)
