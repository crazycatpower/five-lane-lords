extends RefCounted
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

# Grid-snapped spells already match the exact scored box from EnemyAI; keep the center inside the grid.
static func position(_kind: String, origin: Vector2, _team: int) -> Vector2:
	return Vector2(clampf(origin.x,L.GRID_ORIGIN.x+1.0,L.GRID_ORIGIN.x+L.GRID_SIZE.x-1.0),origin.y)
