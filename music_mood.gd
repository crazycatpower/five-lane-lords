extends RefCounted
# What the battle music should feel like (2026-11-22). Pure reading of the match: the theme comes from
# the enemy lord's faction, the tension from how close either side is to breaking. music_player.gd
# turns these into layers; the simulation never reads this file.
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

const THEMES := {"normal":"normal","magic":"magic","dark":"dark","beast":"beast"}
const FACTION_POOLS := {
	"normal": ["charge","duel","normal","conveyor","crimson"],
	"magic": ["duel","magic","conveyor","crimson"],
	"dark": ["crimson","dark","duel"],
	"beast": ["charge","beast","crimson"],
}
const SKILL_HOLD := 6.0 # seconds a lord's skill keeps the music raised

static var skills_seen := {} # model id -> [team 0 skills, team 1 skills]
static var skill_until := {} # model id -> elapsed time the skill swell ends
static var match_themes := {} # model id -> locked battle theme name (matches don't swap mid-fight)

static func _pick_from(seed_val: int, tag: String, lord_a: String, lord_b: String, pool: Array) -> String:
	var h := absi(seed_val)
	for byte: int in (tag + "|" + lord_a + "|" + lord_b).to_utf8_buffer():
		h = (h * 33 + byte) & 0x7fffffff
	return String(pool[h % pool.size()])

# Selects and caches a battle theme once per match without touching simulation RNG.
static func theme(m, me: int) -> String:
	var id: int = m.get_instance_id()
	if match_themes.has(id): return String(match_themes[id])
	var foe := 1-me
	var picked := "normal"
	if m.is_conveyor(me):
		picked = "conveyor"
	else:
		var rule_tag := String(m.get("stage_rule_tag")) if m.get("stage_rule_tag") != null else ""
		var my_lord := String(m.lords[me].lord)
		var foe_lord := String(m.lords[foe].lord)
		var pool: Array
		if "大考" in rule_tag or "畢業考" in rule_tag:
			pool = ["crimson","duel","charge","conveyor"]
		elif not bool(m.lord_active[foe]) and m.has_meta("camp_team"):
			pool = ["charge","normal","duel","conveyor"]
		else:
			var faction: String = B.lord_faction(foe_lord)
			pool = FACTION_POOLS.get(faction, ["charge","duel","normal"])
		picked = _pick_from(int(m.rng.seed), rule_tag, my_lord, foe_lord, pool)
	match_themes[id] = picked
	if match_themes.size() > 8:
		match_themes = {id: picked}
	return picked

# 0 calm .. 1 everything at stake: our walls falling, raiders at our gate, their walls about to fall,
# or a lord's skill just cast.
static func tension(m, me: int) -> float:
	var foe := 1-me
	var ours := 1.0
	var theirs := 1.0
	for lane: int in m.active_lanes:
		ours = minf(ours,float(m.gates[me][lane])/B.GATE_HP)
		theirs = minf(theirs,float(m.gates[foe][lane])/B.GATE_HP)
	var near := 0
	var gate_x: float = L.GRID_ORIGIN.x if me == 0 else L.GRID_ORIGIN.x+L.GRID_SIZE.x
	for u: Dictionary in m.units:
		if int(u.team) == foe and float(u.hp) > 0.0 and absf(float(u.pos.x)-gate_x) < L.CELL_SIZE.x*3.0: near += 1
	var t := clampf((0.75-ours)/0.5,0.0,1.0)
	t = maxf(t,clampf((float(near)-2.0)/8.0,0.0,1.0))
	t = maxf(t,clampf((0.55-theirs)/0.45,0.0,1.0)*0.85)
	var id: int = m.get_instance_id()
	var now := [int(m.stats[0].get("skills",0)),int(m.stats[1].get("skills",0))]
	if skills_seen.has(id) and (now[0] > skills_seen[id][0] or now[1] > skills_seen[id][1]):
		skill_until[id] = float(m.elapsed)+SKILL_HOLD
	skills_seen[id] = now
	if float(m.elapsed) < float(skill_until.get(id,-1.0)): t = maxf(t,0.7)
	if skills_seen.size() > 8: # old matches
		skills_seen = {id:now}
		skill_until = {id:skill_until.get(id,-1.0)}
	return t
