extends RefCounted
# Triggered relic effects (producer 2026-11-19: "主動" relics). Side mods (team_mods, the same keys as
# roguelike relics and 內政 lords) that react to moments in battle instead of changing a number:
#   skill_charge_mult   every point of lord-skill charge counts this many times
#   skill_start_charge  share of the charge meter already full when the battle starts (0..1)
#   skill_echo_gold     gold gained each time our lord casts its skill
#   kill_charge         skill charge gained for each enemy troop we kill
#   gate_fall_spell     free spell cast at a gate of ours the moment it falls ({"kind","once"})
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

static func charge_gain(m, team: int, amount: float) -> float:
	return amount*float(m.lord_mod(team,"skill_charge_mult",1.0))

static func battle_start(m, team: int) -> void:
	var share := clampf(float(m.lord_mod(team,"skill_start_charge",0.0)),0.0,1.0)
	if share > 0.0: m.skill_charge[team] = m.skill_need(team)*share

static func on_cast(m, team: int) -> void:
	var gold := float(m.lord_mod(team,"skill_echo_gold",0.0))
	if gold > 0.0:
		m.gain_ink(team,gold)
		m.event("ink",m.lords[team].pos,team)

static func on_kill(m, killer: int) -> void:
	var charge := float(m.lord_mod(killer,"kill_charge",0.0))
	if charge > 0.0: m.add_skill_charge(killer,charge)

static func on_gate_fall(m, side: int, lane: int) -> void:
	var raw = m.lord_mod(side,"gate_fall_spell",null)
	if raw == null: return
	var specs: Array = raw if raw is Array else ([raw] if raw is Dictionary else [])
	if specs.is_empty(): return
	var used: Array = m.get_meta("gate_fall_used",[[],[]])
	var forward := 1.0 if side == 0 else -1.0
	var pos := Vector2(L.gate_stop(side)+forward*L.CELL_SIZE.x*0.6,L.cell_center(Vector2i(0,lane)).y)
	var fired := false
	for spec in specs:
		if not spec is Dictionary or spec.is_empty(): continue
		var kind := String(spec.get("kind",""))
		if not B.CARDS.has(kind): continue
		if bool(spec.get("once",false)) and not used[side].is_empty(): continue
		m.spells.append({"team":side,"kind":kind,"pos":pos,"delay":B.SPELL_DELAY})
		m.event("spell",pos,side,{"card":kind})
		fired = true
	if fired:
		used[side].append(lane)
		m.set_meta("gate_fall_used",used)
