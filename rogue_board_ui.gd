extends RefCounted
# 肉鴿命運牌陣（使用者 2026-11-22：改成四個直條旗幟；選了一個後那個被一刀很帥的斬掉，補上新的一個；
# 不要戰場小地圖、不要上方進度、不要常駐顯示我方卡組、不要異變）。
# 一根橫桿掛四面旗，每面旗寫清楚對手、被動、本場規則與獎勵。點一下選旗，再點一次（或按「斬旗出征」）
# 一刀斬斷那面旗再出發；回到牌陣時，換上的新旗從橫桿上降下。純畫面：按鈕由 roguelike.show() 建立。
const B = preload("res://balance.gd")
const Hud = preload("res://battle_hud.gd")
const Season = preload("res://season.gd")

const BANNER_W := 320.0
const BANNER_H := 560.0
const BANNER_TOP := 168.0
const BANNER_GAP := 26.0
const POLE_Y := 156.0
const SLASH_TIME := 0.7
const UNFURL_TIME := 0.6
const DECK_PANEL := Rect2(260,190,1080,520)
const DECK_ORIGIN := Vector2(300,270)
const CLOTH := {"battle":Color("7d2e22"),"elite":Color("3f1d47"),"boss":Color("2a1414"),"sboss":Color("1d3a2e"),"camp":Color("a8642a"),"shrine":Color("2f5a7a"),"event":Color("4b6043")}
const SEAL_TEXT := {"battle":"戰","elite":"精","boss":"王","sboss":"首","camp":"營","shrine":"祠","event":"遇"}
const KIND_NAME := {"battle":"一般遭遇","elite":"精英討伐","boss":"魔王決戰","sboss":"季節 BOSS","camp":"戰地營火","shrine":"秘寶古祠","event":"手抄本奇遇"}

static func banner_rect(i: int) -> Rect2:
	var total := BANNER_W*4+BANNER_GAP*3
	return Rect2((1600.0-total)*0.5+i*(BANNER_W+BANNER_GAP),BANNER_TOP,BANNER_W,BANNER_H)

static func now() -> float:
	return Time.get_ticks_msec()/1000.0

# The banner's outline: a straight top hung from the pole, a swallowtail at the foot, swaying a little.
static func cloth(r: Rect2, sway: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 8
	for k: int in range(steps+1):
		var y := lerpf(r.position.y,r.end.y-40.0,k/float(steps))
		pts.append(Vector2(r.end.x+sway*(y-r.position.y)/r.size.y,y))
	pts.append(Vector2(r.end.x+sway,r.end.y))
	pts.append(Vector2(r.position.x+r.size.x*0.5+sway,r.end.y-46.0))
	pts.append(Vector2(r.position.x+sway,r.end.y))
	for k: int in range(steps,-1,-1):
		var y := lerpf(r.position.y,r.end.y-40.0,k/float(steps))
		pts.append(Vector2(r.position.x+sway*(y-r.position.y)/r.size.y,y))
	return pts

static func header(g, rogue) -> void:
	var Catalog = rogue.Catalog
	var run: Dictionary = rogue.run
	var standing: int = run.get("gates",[]).filter(func(hp: float) -> bool: return hp > 0).size()
	var line := "%s · 過牌 %d（敵主 +%d%%） · 金幣 %d · 遺物 %d · 城牆 %d / 5 · 領主 %d / %d · 支援行動 %d" % [rogue.season_label(),int(run.get("cards_cleared",0)),roundi(rogue.enemy_lord_card_bonus()*100.0),int(run.gold),run.get("relics",[]).size(),standing,int(run.get("lord_hp",0)),int(rogue.lord_max_hp()),int(run.get("march_steps",2))]
	g.draw_string(g.font,Vector2(90,124),line,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("5a3818"))
	if not str(run.get("board_notice","")).is_empty():
		g.draw_string(g.font,Vector2(90,146),str(run.board_notice),HORIZONTAL_ALIGNMENT_LEFT,1420,14,Color("6f5a3e"))

static func pole(g) -> void:
	var a := Vector2(banner_rect(0).position.x-40,POLE_Y)
	var b := Vector2(banner_rect(3).end.x+40,POLE_Y)
	g.draw_line(a+Vector2(0,4),b+Vector2(0,4),Color(0,0,0,0.3),10.0,true)
	g.draw_line(a,b,Color("4a2f1a"),9.0,true)
	g.draw_line(a+Vector2(0,-2),b+Vector2(0,-2),Color("7a5232"),2.0,true)
	for p: Vector2 in [a,b]:
		g.draw_circle(p,11,Hud.GOLD.darkened(0.2))
		g.draw_circle(p,6,Hud.GOLD_LIT)

# Everything this slot's battle carries: the foe's passive, the elite trait, and the capped rules.
static func battle_lines(rogue, slot: Dictionary) -> Array:
	var Catalog = rogue.Catalog
	var k: String = slot.get("kind","battle")
	var f: String = slot.get("foe",rogue.foe())
	var lines: Array = []
	if B.is_minion(f):
		lines.append(["被動",B.minion_text(f)])
		var m_shot: Dictionary = Catalog.minion_shot(f)
		if not m_shot.is_empty(): lines.append(["領主射擊",shot_text(m_shot)])
	if k == "elite":
		var elite_mod: Array = Catalog.Terrain.elite_trait(f)
		if not elite_mod.is_empty(): lines.append(["精英：%s" % elite_mod[0],elite_mod[1]])
	if k == "sboss":
		var sb_key: String = rogue.run.sbosses[int(rogue.run.season)]
		var sb: Dictionary = Catalog.SEASON_BOSSES[sb_key]
		lines.append(["技能",Catalog.season_boss_skill_text(sb_key)])
		var sb_pct := roundi(Catalog.SEASON_BOSS_LORD_PCT*100.0)
		var sb_total_pct := roundi((Catalog.SEASON_BOSS_LORD_PCT+rogue.enemy_lord_card_bonus())*100.0)
		lines.append(["首領之力","牌組中的 1 張代表卡強化為 2×2 單體巨獸【%s】（生命 %s）；本人生命與傷害 +%d%%（含過牌共 +%d%%）" % [B.CARDS[sb.giant].name,B.number(B.CARDS[sb.giant].hp),sb_pct,sb_total_pct]])
		var sb_shot: Dictionary = Catalog.minion_shot(f)
		lines.append(["BOSS 射擊",shot_text(sb_shot if not sb_shot.is_empty() else Catalog.SEASON_BOSS_SHOT)])
	if k == "boss":
		var mut: Dictionary = Catalog.mutator_data(slot)
		if not mut.is_empty(): lines.append([String(mut.get("name","")),String(mut.get("desc",""))])
		var b_pct := roundi(Catalog.BOSS_LORD_PCT*100.0)
		var b_total_pct := roundi((Catalog.BOSS_LORD_PCT+rogue.enemy_lord_card_bonus())*100.0)
		lines.append(["魔王之力","本人生命與傷害 +%d%%（含過牌加成共 +%d%%）" % [b_pct,b_total_pct]])
		lines.append(["技能",B.skill_text(f)])
		var shot: Dictionary = Catalog.BOSS_SHOTS.get(f,{})
		if not shot.is_empty():
			lines.append(["魔王射擊",shot_text(shot)])
		lines.append(ups_line(rogue,f,k))
		return lines
	var cleared := int(rogue.run.get("cards_cleared",0))
	if k != "sboss" and cleared > 0:
		lines.append(["敵主強度","已過 %d 張牌：敵方領主生命與傷害 +%d%%" % [cleared,roundi(rogue.enemy_lord_card_bonus()*100.0)]])
	var plan: Dictionary = rogue.seasonal(Catalog.Terrain.plan(f,"elite" if k == "sboss" else k,{}))
	if not plan.is_empty():
		lines.append(["戰場",String(plan.name)+" · %d 路" % plan.lanes.size()+((" · "+Season.label(String(plan.season),bool(plan.season_rule))) if not String(plan.season).is_empty() else "")])
		for rule: Array in plan.rules: lines.append([String(rule[0]),String(rule[1])])
	lines.append(ups_line(rogue,f,k))
	return lines

# 魔王／小怪領主的帶屬性射擊（roguelike_catalog.BOSS_SHOTS、minion_shot）。
static func shot_text(shot: Dictionary) -> String:
	var reach := "，爆炸直徑約 %.1f 格" % (float(shot.radius)*2.0/118.0) if shot.has("radius") else ""
	return "%s：%s%s，每 %s 秒一發，射程 %s 格" % [shot.name,shot.desc,reach,B.number(float(shot.interval)),B.number(float(shot.range)/118.0)]

# 敵方卡牌這一戰的隨機強化（戰前就定好）。
static func ups_line(rogue, f: String, k: String) -> Array:
	var span: Array = rogue.Catalog.enemy_ups_range(int(rogue.run.get("floor",0)),k)
	var ups: Dictionary = rogue.enemy_upgrades(f,k)
	if ups.is_empty(): return ["敵牌強化","本層敵方卡牌沒有強化"]
	var head := ("每張牌 +%d 級：" % int(span[0])) if int(span[0]) == int(span[1]) else ("每張牌 +%d～+%d 級：" % [int(span[0]),int(span[1])])
	return ["敵牌強化",head+"、".join(ups.keys().map(func(ck: String) -> String: return "%s+%d" % [B.CARDS[ck].name,rogue.Upgrades.level(ups[ck])]))]

static func paragraph(g, text: String, pos: Vector2, width: float, size: int, color: Color, max_lines: int) -> float:
	var para := TextParagraph.new()
	para.width = width
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	para.add_string(text,g.font,size)
	para.max_lines_visible = max_lines
	para.draw(g.get_canvas_item(),pos,color)
	return minf(para.get_size().y,(size+4)*max_lines)

# The banner's face: seal, portrait, name, then the lines, the reward and the hint.
static func face(g, rogue, i: int, r: Rect2, selected: bool, detail: bool) -> void:
	var Catalog = rogue.Catalog
	var run: Dictionary = rogue.run
	var slot: Dictionary = run.board[i]
	var k: String = slot.get("kind","battle")
	var inner := Rect2(r.position+Vector2(18,56),Vector2(r.size.x-36,r.size.y-150))
	g.draw_rect(inner,Color(Hud.VELLUM,0.96))
	g.draw_rect(inner,Color(Hud.GOLD.darkened(0.3),0.8),false,1.5)
	var c := Vector2(r.position.x+r.size.x*0.5,r.position.y+36)
	g.draw_circle(c+Vector2(0,2),24,Color(0,0,0,0.3))
	g.draw_circle(c,24,Color("9b2f2f") if k in ["battle","elite","boss","sboss"] else Hud.GOLD.darkened(0.25))
	g.draw_arc(c,19,0,TAU,28,Color(1,0.9,0.7,0.4),1.4,true)
	g.draw_string(g.font,c+Vector2(-20,8),SEAL_TEXT.get(k,"?"),HORIZONTAL_ALIGNMENT_CENTER,40,22,Color("fff0ca"))
	g.draw_string(g.font,Vector2(r.position.x+14,r.position.y+30),KIND_NAME.get(k,""),HORIZONTAL_ALIGNMENT_LEFT,110,14,Color("ffe7b0"))
	var bounty := int(slot.get("bounty",0))
	if bounty > 0: g.draw_string(g.font,Vector2(r.end.x-124,r.position.y+30),"懸賞 +%d" % bounty,HORIZONTAL_ALIGNMENT_RIGHT,110,14,Color("ffd97d"))
	var art := Rect2(inner.position+Vector2(inner.size.x*0.5-55,6),Vector2(110,96)) if k in ["battle","elite","boss","sboss"] else Rect2(inner.position+Vector2(inner.size.x*0.5-60,8),Vector2(120,124))
	var title := ""
	if k in ["battle","elite","boss","sboss"]:
		var f: String = slot.get("foe",rogue.foe())
		g.draw_fitted(g.lord_art(f,1),art,Color.WHITE,true)
		title = rogue.foe_name(slot)
	else:
		var ev: Dictionary = Catalog.EVENTS.get(slot.get("event_id","wandering_smith"),Catalog.EVENTS.wandering_smith)
		g.draw_fitted(g.art("field_smithy" if k == "camp" else ("blood_altar" if k == "shrine" else str(ev.art))),art,Color.WHITE,true)
		title = rogue.slot_title(slot)
	g.draw_string(g.font,Vector2(inner.position.x,art.end.y+30),title,HORIZONTAL_ALIGNMENT_CENTER,inner.size.x,24,g.INK)
	var y: float = art.end.y+44
	if k in ["battle","elite","boss","sboss"]:
		var f2: String = slot.get("foe",rogue.foe())
		var ai_lv := 2 if k == "sboss" else clampi(Catalog.AI_LEVEL[run.floor]+int(Catalog.CONTRACTS[clampi(int(run.get("contract",0)),0,Catalog.CONTRACTS.size()-1)].get("ai_boost",0)),0,2)
		g.draw_string(g.font,Vector2(inner.position.x,y+8),"%s · AI %s" % [B.lord_data(f2).role,["簡單","普通","困難"][ai_lv]],HORIZONTAL_ALIGNMENT_CENTER,inner.size.x,14,Color("6f5a3e"))
		y += 22
		if detail:
			for line: Array in battle_lines(rogue,slot):
				if y > inner.end.y-40: break
				g.draw_string(g.font,Vector2(inner.position.x+10,y+16),String(line[0]),HORIZONTAL_ALIGNMENT_LEFT,inner.size.x-20,15,Color("8a3a2c"))
				y += 20
				var room := floori((inner.end.y-6.0-y)/17.0)
				if room < 1: break
				y += paragraph(g,String(line[1]),Vector2(inner.position.x+10,y),inner.size.x-20,13,g.INK,mini(2,room))+4
	elif detail:
		var body := ""
		if k == "event": body = str(Catalog.EVENTS.get(slot.get("event_id","wandering_smith"),Catalog.EVENTS.wandering_smith).story)
		elif k == "camp": body = "休整築牆：修 45% 城牆、領主回 50%\n名匠鍛造：自選 1 張卡與屬性百分比強化\n軍資徵集：120 金並強化 1 張卡"
		elif k == "shrine": body = "聖物匣：免費 1 件遺物\n精煉主力：自選 1 張卡與屬性百分比強化並得 70 金\n鮮血奉獻：損 25% 領主生命換 200 金"
		paragraph(g,body,Vector2(inner.position.x+10,y+6),inner.size.x-20,14,g.INK,9)
	# Reward under the vellum, the hint on the tail.
	var reward: String = rogue.slot_subtitle(slot) if k in ["battle","elite","boss","sboss"] else ""
	if not reward.is_empty(): g.draw_string(g.font,Vector2(r.position.x,inner.end.y+26),reward,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,14,Color("ffe7b0"))
	var hint := "再點一次：進入" if selected else "點選此旗"
	g.draw_string(g.font,Vector2(r.position.x,inner.end.y+50),hint,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,15 if selected else 13,Color("ffd97d") if selected else Color(1,0.92,0.75,0.6))

static func banner(g, rogue, i: int) -> void:
	var run: Dictionary = rogue.run
	var r := banner_rect(i)
	var t: float = g.clock
	var selected: bool = i == int(run.get("selected_node",0))
	var k: String = run.board[i].get("kind","battle")
	var hover: bool = r.has_point(g.get_local_mouse_position())
	var lift := (-10.0 if selected else (-5.0 if hover else 0.0))
	var sway := sin(t*1.3+i*1.7)*(4.0 if selected else 2.5)
	# A new banner drops down from the pole (the slot was just refilled).
	var born: float = float(rogue.banner_born[i]) if i < rogue.banner_born.size() else -100.0
	var grow := clampf((now()-born)/UNFURL_TIME,0.0,1.0)
	var unfurl := 1.0-pow(1.0-grow,3.0)
	r.position.y += lift
	g.draw_set_transform(Vector2(0,r.position.y),0.0,Vector2(1.0,maxf(0.02,unfurl)))
	var local := Rect2(Vector2(r.position.x,0),r.size)
	var body := cloth(local,sway)
	var shadow := PackedVector2Array()
	for p: Vector2 in body: shadow.append(p+Vector2(5,8))
	g.draw_colored_polygon(shadow,Color(0,0,0,0.3))
	var col: Color = CLOTH.get(k,CLOTH.battle)
	g.draw_colored_polygon(body,col)
	if selected or hover:
		var o := body.duplicate()
		o.append(body[0])
		g.draw_polyline(o,Color(Hud.GOLD_LIT,0.9 if selected else 0.5),4.0 if selected else 2.0,true)
	var edge := body.duplicate()
	edge.append(body[0])
	g.draw_polyline(edge,Color(g.INK,0.9),1.6,true)
	# Gold trim stripes down both sides.
	for side: float in [10.0,BANNER_W-14.0]:
		g.draw_line(Vector2(local.position.x+side,6),Vector2(local.position.x+side+sway*0.9,local.end.y-60),Color(Hud.GOLD,0.55),2.0,true)
	face(g,rogue,i,local,selected,grow > 0.85)
	g.draw_set_transform(Vector2.ZERO)
	# The ring that hangs it on the pole.
	for dx: float in [30.0,BANNER_W-30.0]:
		g.draw_arc(Vector2(r.position.x+dx,POLE_Y+4),9,PI*0.9,TAU+PI*0.1,14,Hud.GOLD.darkened(0.15),3.0,true)

# The cut: a bright stroke across the banner, the lower half falling away while the upper half swings.
static func slash(g, rogue, i: int) -> void:
	var r := banner_rect(i)
	r.position.y -= 10.0
	var k: String = rogue.slash_slot.get("kind",rogue.run.board[i].get("kind","battle"))
	var p := clampf((now()-float(rogue.slash_at))/SLASH_TIME,0.0,1.0)
	var col: Color = CLOTH.get(k,CLOTH.battle)
	var body := cloth(r,0.0)
	var a := Vector2(r.end.x+30,r.position.y+r.size.y*0.30)
	var b := Vector2(r.position.x-30,r.position.y+r.size.y*0.58)
	var n := (b-a).orthogonal().normalized()
	var big := 2000.0
	var upper_cut := PackedVector2Array([a-(b-a)*2.0,b+(b-a)*2.0,b+(b-a)*2.0-n*big,a-(b-a)*2.0-n*big])
	var lower_cut := PackedVector2Array([a-(b-a)*2.0,b+(b-a)*2.0,b+(b-a)*2.0+n*big,a-(b-a)*2.0+n*big])
	var top_piece: Array = Geometry2D.intersect_polygons(body,upper_cut)
	var low_piece: Array = Geometry2D.intersect_polygons(body,lower_cut)
	var fall := maxf(0.0,p-0.12)/0.88
	var swing := sin(fall*9.0)*(1.0-fall)*0.05
	var hang := Vector2(r.position.x+r.size.x*0.5,r.position.y)
	for poly: PackedVector2Array in top_piece:
		g.draw_set_transform(hang,swing,Vector2.ONE)
		var moved := PackedVector2Array()
		for q: Vector2 in poly: moved.append(q-hang)
		g.draw_colored_polygon(moved,Color(col,1.0-fall*0.6))
		g.draw_set_transform(Vector2.ZERO)
	var drop := Vector2(fall*-30.0,fall*fall*520.0)
	var spin := fall*-0.6
	var pivot := (a+b)*0.5
	for poly: PackedVector2Array in low_piece:
		g.draw_set_transform(pivot+drop,spin,Vector2.ONE)
		var moved := PackedVector2Array()
		for q: Vector2 in poly: moved.append(q-pivot)
		g.draw_colored_polygon(moved,Color(col.darkened(0.1),1.0-fall))
		g.draw_set_transform(Vector2.ZERO)
	# The stroke itself: a sweep of light along the cut, then sparks scattering.
	var sweep := clampf(p/0.14,0.0,1.0)
	var glow := 1.0-clampf((p-0.14)/0.4,0.0,1.0)
	if glow > 0.0:
		var head := a.lerp(b,sweep)
		for w: Array in [[22.0,0.18],[10.0,0.45],[4.0,1.0]]:
			g.draw_line(a,head,Color(1.0,0.95,0.75,float(w[1])*glow),float(w[0]),true)
		for s: int in range(14):
			var d := Vector2.from_angle(s*TAU/14.0+0.3)
			var q := a.lerp(b,(s+0.5)/14.0)+d*(20.0+p*120.0)
			g.draw_circle(q,2.5*glow,Color(1.0,0.85,0.4,glow))
	if p < 0.12: g.draw_rect(Rect2(0,0,1600,900),Color(1,1,1,0.18*(1.0-p/0.12)))

static func deck_panel(g, rogue) -> void:
	var Catalog = rogue.Catalog
	var run: Dictionary = rogue.run
	g.draw_rect(Rect2(0,0,1600,900),Color(0,0,0,0.45))
	Hud.plate(g,Hud.slanted(DECK_PANEL,12.0,12.0),Color("efe0bd"),Color(g.INK,0.85))
	g.draw_string(g.font,DECK_PANEL.position+Vector2(36,44),"我軍 · %s" % B.lord_name(run.lord),HORIZONTAL_ALIGNMENT_LEFT,-1,24,g.INK)
	g.draw_string(g.font,DECK_PANEL.position+Vector2(36,70),rogue.deck_summary(run.deck),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("6f5a3e"))
	rogue.mini_deck(g,run.deck,DECK_ORIGIN+Vector2(0,30),2,run.upgrades)
	var rx := DECK_PANEL.position.x+520
	g.draw_string(g.font,Vector2(rx,DECK_PANEL.position.y+110),"遺物 %d 件" % run.relics.size(),HORIZONTAL_ALIGNMENT_LEFT,-1,18,g.INK)
	var y := DECK_PANEL.position.y+130
	if run.relics.is_empty(): g.draw_string(g.font,Vector2(rx,y+20),"尚無（商店購買或精英、古祠取得）",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("6f5a3e"))
	for rk: String in run.relics:
		if y > DECK_PANEL.end.y-40: break
		var rd: Dictionary = Catalog.RELICS[rk]
		y += paragraph(g,"【%s】%s" % [rd.name,B.passive_text(rd.mods)],Vector2(rx,y),500,14,g.INK,2)+6

static func deck_tile(i: int) -> Rect2:
	var origin := DECK_ORIGIN+Vector2(0,30)
	return Rect2(origin+Vector2((i%4)*108,(i/4)*110),Vector2(100,102))

static func paint_map(g, rogue) -> void:
	header(g,rogue)
	var t := now()
	while rogue.banner_sig.size() < 4:
		rogue.banner_sig.append("")
		rogue.banner_born.append(-100.0)
	# Back from the banner we went into: cut it down now, and let its replacement drop in afterwards.
	if not rogue.slash_pending.is_empty() and rogue.slash_index < 0:
		var idx := int(rogue.slash_pending.index)
		rogue.slash_slot = rogue.slash_pending.slot
		rogue.slash_pending = {}
		rogue.slash_index = idx
		rogue.slash_at = t
		var fresh: Dictionary = rogue.run.board[idx]
		rogue.banner_sig[idx] = "%s|%s|%s" % [fresh.get("kind",""),fresh.get("foe",""),fresh.get("event_id","")]
		rogue.banner_born[idx] = t+SLASH_TIME
	if rogue.slash_index >= 0 and t-float(rogue.slash_at) >= SLASH_TIME:
		rogue.slash_index = -1
		rogue.slash_slot = {}
	# Track which banners changed since we last drew them: those unfurl.
	for i: int in range(4):
		var slot: Dictionary = rogue.run.board[i]
		var sig := "%s|%s|%s" % [slot.get("kind",""),slot.get("foe",""),slot.get("event_id","")]
		if sig != rogue.banner_sig[i]:
			rogue.banner_sig[i] = sig
			rogue.banner_born[i] = t+i*0.12
	pole(g)
	for i: int in range(4):
		if i == rogue.slash_index: slash(g,rogue,i)
		else: banner(g,rogue,i)
	if rogue.deck_open: deck_panel(g,rogue)
