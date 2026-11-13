extends RefCounted
const B = preload("res://balance.gd")
# Card background by role (producer 2026-11-05); the faction is the coloured outer band (BAND_COLORS).
const ROLES := {
 "economy":["glutton_nest","crystal","farm","grave","farmer","mill","harvest","artificer","mana_spring","sacrifice","mule_cart","funeral_cottage","blood_altar","grave_exchange","granary","soul_well"],
 "melee":["militia","knight","shieldguard","corpse_giant","skeleton","ghoul","reaper","ram","spearbow","manor_retainer","chimera","arcane_golem","ox","levy","mass_grave","eyewing_dragon","belly_eye","thorn_dragon","hook_collector","gatebreaker","disgraced_lancer","monster_hunter","spellbreaker","pallbearer","blood_attendant","borrowed_bones","macebreaker","bog_troll","tusk_boar","ossuary","monster_hatchery"],
 "harass":["bandit","raven","mob","phase_rider","blink_blade","fishbeak","bearded_imp","hooknose_flyer","twin_gambler","runaway_thrall","oathless_imp","assassin","imp_bomb_runner"],
 "ranged":["arcane_tower","hunter","catapult","tower","rain","fire","axe_thrower","rolling_boulder","arcane_archer","dark_wizard","chain_lightning","watchtower","long_dragon","vampire_hunter","arquebusier","funeral_grenadier","dog_cannon","orrery_walker","seal_bearer","shroud_arbalist","astrolabe_surveyor"],
 "support":["healer","drummer","necromancer","guard","arcane_shield","charge_horn","blood_tower","corpse_stitcher","sleepless_belfry","mourning_shroud","bellbearer","sigil_weaver","field_smithy","rune_workshop","observatory","war_lodge"],
 "control":["teleport_trap","blast_trap","barricade","curse","plague","bonewall","scarecrow","summon_trap","chronomancer","time_field","net_hunter","dread_howl","renegade_artificer","powder_barrel","mourning_maid","sealed_coffin","beekeeper"]
}
const ROLE_TINTS := {"economy":Color("f3d079"),"melee":Color("e7ac9b"),"ranged":Color("a9cbe6"),"support":Color("b2d5a2"),"control":Color("cbb0df"),"harass":Color("c98078")}
# Faction label colours (the small tag on the card face).
const TAGS := {"normal":Color("55722f"),"dark":Color("5b4366"),"magic":Color("38598f"),"beast":Color("8a4524"),"":Color("7d7466")}
# Lord cards have no role: a light wash of their faction colour.
const TINTS := {"normal":Color("c6dba0"),"dark":Color("bba3bd"),"magic":Color("a9c3ec"),"beast":Color("e2bc98"),"":Color("efe3c8")}
static func role(kind: String) -> String:
	for r: String in ROLES:
		if kind in ROLES[r]: return r
	# A card not listed yet: troops by reach, spells deal damage, buildings hold the line.
	match B.card_group(kind):
		0: return "melee"
		1: return "ranged"
		2: return "ranged"
	return "control"
static func card_tint(kind: String) -> Color:
	return ROLE_TINTS[role(kind)]
static func tag_color(kind: String) -> Color:
	return TAGS.get(B.card_faction(kind),TAGS[""])
# Faction border (producer 2026-11-05): the card's own gold outer band, recoloured to the faction.
# Only the band's pixels are kept (an overlay drawn untinted over the role-tinted card), so the
# frame keeps its hand-drawn shading. Neutral cards keep the plain gold band.
const BAND_COLORS := {"normal":Color("6fa33a"),"dark":Color("9a62b8"),"magic":Color("4d8ad8"),"beast":Color("c4622e")}
static var bands := {}
static func faction_band(faction: String, selected: bool) -> Texture2D:
	var key := faction+str(selected)
	if bands.has(key): return bands[key]
	var src: Image = preload("res://manuscript_art.gd").card(selected).get_image()
	src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w,h,false,Image.FORMAT_RGBA8)
	var tint: Color = BAND_COLORS[faction]
	for y: int in range(h):
		var edge_row := y <= 24 or y >= h-25
		for x: int in (range(w) if edge_row else range(25)+range(w-25,w)): # the band runs ~14-20 px from the edge
			var c := src.get_pixel(x,y)
			if c.a < 0.5 or c.s < 0.5 or c.v < 0.45 or c.h < 0.05 or c.h > 0.17: continue # gold only
			var k := c.v/0.80
			out.set_pixel(x,y,Color(clampf(tint.r*k,0,1),clampf(tint.g*k,0,1),clampf(tint.b*k,0,1),c.a))
	bands[key] = ImageTexture.create_from_image(out)
	return bands[key]
static func faction_frame(g, r: Rect2, kind: String, selected: bool = false) -> void:
	var faction: String = B.card_faction(kind)
	if not BAND_COLORS.has(faction): return
	g.draw_texture_rect(faction_band(faction,selected),r,false)
static func type_frame(g, r: Rect2, type: String) -> void:
	var box := Rect2(r.position+r.size*Vector2(0.09,0.17),r.size*Vector2(0.82,0.48))
	var p := box.position
	var s := box.size
	var ink := Color(0.30,0.25,0.18,0.62)
	if type == "unit":
		# Shield silhouette and diagonal heraldic hatching.
		var points := PackedVector2Array([p,p+Vector2(s.x,0),p+Vector2(s.x,s.y*0.72),p+Vector2(s.x*0.5,s.y),p+Vector2(0,s.y*0.72),p])
		g.draw_polyline(points,ink,1.5,true)
		for i: int in range(4):
			g.draw_line(p+Vector2(3+i*5,3),p+Vector2(3,3+i*5),Color(ink,0.35),1)
	elif type == "building":
		# Square masonry with a crenellated top.
		g.draw_rect(box,ink,false,1.5)
		for i: int in range(5):
			g.draw_rect(Rect2(p+Vector2(i*s.x/5,-5),Vector2(s.x/10,5)),ink,false,1.2)
		for i: int in range(3):
			g.draw_line(p+Vector2(0,12+i*13),p+Vector2(9,12+i*13),Color(ink,0.45),1)
	else:
		# Oval seal with orbiting diamond marks.
		g.tf(box.get_center(),0,Vector2(1,s.y/s.x))
		g.draw_arc(Vector2.ZERO,s.x*0.5,0,TAU,48,ink,1.5,true)
		g.tf()
		for side: int in [-1,1]:
			var c := box.get_center()+Vector2(side*s.x*0.5,0)
			g.draw_polyline(PackedVector2Array([c+Vector2(0,-5),c+Vector2(4,0),c+Vector2(0,5),c-Vector2(4,0),c+Vector2(0,-5)]),ink,1,true)
static func stone(g, r: Rect2) -> void:
	g.draw_rect(r,Color("8c785c"))
	var inner := r.grow(-5)
	for row: int in range(4):
		var y := inner.position.y+row*45
		for col: int in range(12):
			var x := inner.position.x+col*149-(74 if row%2 else 0)
			var tile := Rect2(x+2,y+2,145,41).intersection(inner)
			if not tile.has_area(): continue
			var variation := float((row*7+col*3)%5)*0.012
			g.draw_rect(tile,Color(0.73+variation,0.66+variation,0.53+variation))
			g.draw_line(tile.position,tile.position+Vector2(tile.size.x,0),Color(0.91,0.83,0.67,0.5),1)
			g.draw_line(tile.position,tile.position+Vector2(0,tile.size.y),Color(0.91,0.83,0.67,0.4),1)
	# A quiet wash keeps small HUD text readable over mortar joints.
	g.draw_rect(inner,Color(0.80,0.73,0.60,0.58))
	for i: int in range(180):
		var point := inner.position+Vector2(fmod(i*83.7,inner.size.x),fmod(i*31.3,inner.size.y))
		g.draw_line(point,point+Vector2(2+(i%3),0.5),Color(0.38,0.30,0.21,0.10),1)
	g.draw_rect(r,Color("756247"),false,3)
	g.draw_rect(r.grow(-3),Color("d9c6a0"),false,1)
