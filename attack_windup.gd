extends RefCounted
const MIN_SECONDS := 0.05
const MAX_SECONDS := 0.2

static func target_key(target: Dictionary) -> String:
	return "lord:%d" % target.team if target.kind == "lord" else "actor:%d" % target.id

static func cancel(unit: Dictionary) -> void:
	unit.erase("attack_windup")

# Called only while a live target is in reach. Re-targeting starts a fresh windup.
static func ready(model, unit: Dictionary, key: String, dt: float) -> bool:
	if unit.cd > 0:
		cancel(unit)
		return false
	var windup: Dictionary = unit.get("attack_windup",{})
	if windup.is_empty() or windup.target != key:
		var duration: float = model.rng.randf_range(MIN_SECONDS,MAX_SECONDS)
		unit.attack_windup = {"target":key,"duration":duration,"left":duration}
		return false
	windup.left -= dt
	if windup.left > 0.000001: return false
	cancel(unit)
	return true
