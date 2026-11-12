extends RefCounted
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

# Applied once to the selected AI action. Buildings, deployment and manual casts stay exact.
static func position(kind: String, origin: Vector2, team: int) -> Vector2:
	var direction := 0.0
	if kind in ["rain","plague","curse","chain_lightning","dread_howl","time_field"]:
		direction = -1.0 if team == 0 else 1.0
	elif kind in ["arcane_shield","charge_horn"]:
		direction = 1.0 if team == 0 else -1.0
	if direction == 0.0: return origin
	return Vector2(clampf(origin.x+direction*B.AI_SPELL_LEAD,L.GRID_ORIGIN.x+1,L.GRID_ORIGIN.x+L.GRID_SIZE.x-1),origin.y)
