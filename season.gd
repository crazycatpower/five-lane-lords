extends RefCounted
# 四季（使用者 2026-11-21：冒險關卡要有春夏秋冬，外觀＋小規則）。一場戰鬥最多一個季節，雙方同樣受影響。
# 規則只有一條、寫在關卡說明裡；其餘都是畫面：地面配色、地上點綴（花、落葉、積雪）、飄落的天氣。
#   春：春暖，雙方出牌冷卻快 10%
#   夏：長晝，入夜延後 60 秒（沒有夜晚的關卡不受影響）
#   秋：秋收，雙方農田產出 ×1.25
#   冬：積雪，雙方地面部隊移速降一檔（飛行不受影響）
# battle.gd 只在 movement_speed() 讀 snow_step()；adventure.gd 開戰時呼叫 apply()；game.gd 畫圖時呼叫 tint/ground/weather。
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

const SEASONS := {
	"spring":{"name":"春","title":"春暖","rule":"春暖：雙方出牌冷卻快 10%。","mods":{"cd_speed_mult":1.1},"tint":Color("b8d08a"),"mix":0.28},
	"summer":{"name":"夏","title":"長晝","rule":"長晝：入夜延後 60 秒。","night_delay":60.0,"tint":Color("4f8a2e"),"mix":0.34},
	"autumn":{"name":"秋","title":"秋收","rule":"秋收：雙方農田產出 ×1.25。","mods":{"farm_mult":1.25},"tint":Color("b8853a"),"mix":0.42},
	"winter":{"name":"冬","title":"積雪","rule":"積雪：雙方地面部隊移速降一檔（飛行不受影響）。","tint":Color("e4e8ec"),"mix":0.62},
}

static func valid(season: String) -> bool:
	return season.is_empty() or SEASONS.has(season)

static func rule_text(season: String) -> String:
	return String(SEASONS.get(season,{}).get("rule",""))

static func label(season: String, rule: bool = true) -> String:
	if not SEASONS.has(season): return ""
	if not rule: return "%s（景色）" % SEASONS[season].name
	return "%s · %s" % [SEASONS[season].name,SEASONS[season].title]

# Set the season on a fresh battle and give both sides its rule.
# rule = false: only the look of the season (a battle already carrying enough rules).
static func apply(m, season: String, rule: bool = true) -> void:
	if not SEASONS.has(season): return
	m.season = season
	m.season_rule = rule
	if not rule: return
	var d: Dictionary = SEASONS[season]
	var mods: Dictionary = d.get("mods",{})
	if not mods.is_empty():
		m.apply_campaign_mods(0,mods)
		m.apply_campaign_mods(1,mods)
	if d.has("night_delay") and m.night_decay:
		m.night_start_override = m.night_start_time()+float(d.night_delay)

# Winter snow costs ground troops one speed tier.
static func snow_step(m, u: Dictionary) -> int:
	return 1 if m.season == "winter" and m.season_rule and not u.get("flying",false) else 0

# ---------------- drawing (never touches the battle's RNG) ----------------

# The ground palette pulled toward the season's colour.
static func tint(pal: Array, season: String) -> Array:
	if not SEASONS.has(season): return pal
	var d: Dictionary = SEASONS[season]
	var out: Array = []
	for c: Color in pal: out.append(c.lerp(d.tint,float(d.mix)))
	return out

# Things lying on the ground: blossom, wildflowers, fallen leaves, drifts of snow.
static func ground(g, grid: Rect2) -> void:
	var season: String = g.model.season
	if not SEASONS.has(season): return
	match season:
		"spring":
			for i: int in range(120):
				var p := spot(g,grid,i,901)
				var col: Color = [Color("f2c6d2"),Color("fbeef0"),Color("f6d77a")][i%3]
				for k: int in range(5):
					g.draw_circle(p+Vector2.from_angle(k*TAU/5.0+i)*3.2,2.2,Color(col,0.85))
				g.draw_circle(p,1.6,Color("d9a23a"))
		"summer":
			for i: int in range(130):
				var p := spot(g,grid,i,911)
				for k: int in range(5):
					var lean := (k-2.0)*3.0
					g.draw_line(p,p+Vector2(lean,-12.0-(k%2)*6.0),Color("3d6a22",0.8),1.6,true)
				if i%3 == 0: g.draw_circle(p+Vector2(0,-17),3.2,Color(["e8c33a","c9483a","f4f0e6"][(i/3)%3]))
		"autumn":
			for i: int in range(110):
				var p := spot(g,grid,i,921)
				var col: Color = [Color("c4622e"),Color("d99a2b"),Color("9e3b22"),Color("b97a3a")][i%4]
				g.tf(p,g.scenery_noise(i,922)*TAU,Vector2(1.0,0.55))
				g.draw_circle(Vector2.ZERO,4.0+g.scenery_noise(i,923)*2.5,Color(col,0.8))
				g.tf()
		"winter":
			for i: int in range(26):
				var c := spot(g,grid,i,931)
				g.ground_wash(c,Vector2(40.0+g.scenery_noise(i,932)*70.0,8.0+g.scenery_noise(i,933)*10.0),Color("ffffff"),i+930,0.55)
			for i: int in range(40):
				var p := spot(g,grid,i,941)
				g.draw_line(p,p+Vector2(5,-3),Color("9fb3c4",0.5),1.2,true)

# Falling weather over the field, drawn after the troops: petals, leaves or snow. Summer is clear.
static func weather(g, grid: Rect2) -> void:
	var season: String = g.model.season
	if not season in ["spring","autumn","winter"]: return
	var t: float = g.clock
	var count := 60 if season == "winter" else 22
	for i: int in range(count):
		var fall: float = 26.0+g.scenery_noise(i,951)*22.0
		var drift: float = 18.0+g.scenery_noise(i,952)*20.0
		var y: float = grid.position.y+fposmod(g.scenery_noise(i,953)*grid.size.y+t*fall,grid.size.y)
		var x: float = grid.position.x+fposmod(g.scenery_noise(i,954)*grid.size.x+t*drift*0.6+sin(t*1.3+i)*14.0,grid.size.x)
		var p := Vector2(x,y)
		match season:
			"winter": g.draw_circle(p,1.4+g.scenery_noise(i,955)*1.6,Color(1,1,1,0.85))
			"spring":
				g.tf(p,t*2.0+i,Vector2(1.0,0.5))
				g.draw_circle(Vector2.ZERO,3.0,Color("f4c9d4",0.85))
				g.tf()
			"autumn":
				g.tf(p,t*2.5+i,Vector2(1.0,0.45))
				g.draw_circle(Vector2.ZERO,4.2,Color(["c4622e","d99a2b","9e3b22"][i%3],0.85))
				g.tf()

static func spot(g, grid: Rect2, i: int, salt: int) -> Vector2:
	return grid.position+Vector2(12.0+g.scenery_noise(i,salt)*(grid.size.x-24.0),10.0+g.scenery_noise(i,salt+1)*(grid.size.y-16.0))
