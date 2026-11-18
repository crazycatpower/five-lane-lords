extends SceneTree
## Renders a recorded deterministic replay JSON frame-by-frame for Godot Movie Maker (--write-movie --fixed-fps 60).
const Battle = preload("res://battle.gd")
const B = preload("res://balance.gd")

var game
var ready := false
var post_end_frames := 270 # 4.5s at 60fps to capture finisher bullet-time + result banner

func _initialize() -> void:
	var replay_path := ""
	var theater := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--replay="): replay_path = arg.get_slice("=", 1)
		elif arg == "--theater=1": theater = true
	if replay_path.is_empty():
		push_error("render_replay.gd: missing --replay=<path>")
		quit(1)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_meta("replaying", true)
	call_deferred("_prepare", replay_path, theater)

func _prepare(replay_path: String, theater: bool) -> void:
	var setup: Dictionary = game.recorder.load_replay(replay_path)
	if setup.is_empty() or (setup.has("balance_hash") and setup.balance_hash != FileAccess.get_sha256("res://balance.gd")):
		push_error("render_replay.gd: invalid replay file " + replay_path)
		quit(1)
		return
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.spectating = bool(setup.get("spectating", false))
	game.me = int(setup.get("me", 0))
	game.mirror_view = bool(setup.get("mirror_view", false))
	game.field_mirror = game.mirror_view
	game.difficulty = int(setup.get("difficulty", 1))
	game.cinematic.enabled = true
	game.cinematic.theater_mode = theater
	game.model = Battle.new(
		int(setup.get("seed", 1)),
		setup.get("red_deck", []),
		setup.get("blue_deck", []),
		String(setup.get("red_lord", "lion")),
		String(setup.get("blue_lord", "underworld"))
	)
	game.model.difficulty = game.difficulty
	game.model.ai_enabled = [game.spectating, true]
	game.enter_battle("")
	ready = true

func _process(_dt: float) -> bool:
	if not ready:
		return false
	if game.recorder.tick > game.recorder.replay_total_ticks + 600 and not game.model.ended:
		push_error("Replay did not finish at recorded time; export stopped.")
		quit(1)
		return false
	if game.model != null and game.model.ended:
		post_end_frames -= 1
		if post_end_frames <= 0:
			return true
	return false
