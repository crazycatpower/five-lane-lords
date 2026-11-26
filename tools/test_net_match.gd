extends SceneTree
# End-to-end test of WebSocket matchmaking, private room codes, deterministic lockstep, and AI fallback.
const NetMatch = preload("res://net_match.gd")
const DeckStore = preload("res://deck_store.gd")
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")

const TEST_PORT := 24681
var checks := 0
var failures := 0
var server_pid := -1

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	create_timer(120).timeout.connect(func():
		_stop_server()
		print("TIMEOUT")
		quit(2))
	call_deferred("run")

func _stop_server() -> void:
	if server_pid > 0 and OS.is_process_running(server_pid):
		OS.kill(server_pid)
	server_pid = -1

func run() -> void:
	var srv_path := ProjectSettings.globalize_path("res://server/matchmaker.mjs")
	# Pass PORT via node wrapper or cmd env? Let's spawn node with --eval setting process.env.PORT
	var srv_url := "file:///" + srv_path.replace("\\", "/")
	var env_code := "process.env.PORT='%d'; import('%s');" % [TEST_PORT, srv_url]
	server_pid = OS.create_process("node", PackedStringArray(["--input-type=module", "-e", env_code]), false)
	check(server_pid > 0, "started matchmaker server on port %d" % TEST_PORT)
	for _w: int in range(25):
		await process_frame

	var url := "ws://127.0.0.1:%d" % TEST_PORT
	var deck_a: Array = B.DEFAULT_DECK.duplicate()
	var deck_b: Array = ["militia","hunter","knight","farmer","rain","tower","healer","ox"]

	# 1. Queue matchmaking + lockstep
	var a = NetMatch.new()
	var b = NetMatch.new()
	check(a.search_match(deck_a, B.DEFAULT_LORD, 1, url, false), "player A queues")
	check(b.search_match(deck_b, "lion", 1, url, false), "player B queues")
	var models := [null, null]
	for _i: int in range(600):
		if a.poll(1.0 / 60.0): models[a.local_team] = a.make_battle()
		if b.poll(1.0 / 60.0): models[b.local_team] = b.make_battle()
		if models[0] != null and models[1] != null: break
		await process_frame
	check(models[0] != null and models[1] != null, "queue matched both players (%s / %s)" % [a.state, b.state])
	if models[0] == null or models[1] == null:
		_stop_server()
		print("Net match: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var red = a if a.local_team == 0 else b
	var blue = b if red == a else a
	check(red.local_team == 0 and blue.local_team == 1, "assigned red (0) and blue (1)")
	check(not red.is_ai_match and not blue.is_ai_match, "human vs human match")
	check(models[0].lords[0].lord == red.my_lord and models[1].lords[1].lord == blue.my_lord and red.peer_name == B.lord_name(blue.my_lord) and blue.peer_name == B.lord_name(red.my_lord), "both battles hold both decks, lords and resolved opponent names")
	for m in models: m.ink = [50.0, 50.0]
	for t: int in range(1800):
		red.poll(1.0 / 60.0)
		blue.poll(1.0 / 60.0)
		if t == 30: red.queue(["p", 0, L.cell_center(Vector2i(1, 2)).x, L.cell_center(Vector2i(1, 2)).y])
		if t == 31: blue.queue(["p", 0, L.cell_center(Vector2i(7, 1)).x, L.cell_center(Vector2i(7, 1)).y])
		if t == 200: blue.queue(["p", 1, L.cell_center(Vector2i(7, 3)).x, L.cell_center(Vector2i(7, 3)).y])
		if t == 400: red.queue(["p", 2, L.cell_center(Vector2i(2, 0)).x, L.cell_center(Vector2i(2, 0)).y])
		if t == 1300: blue.queue(["s"])
		red.advance(models[0], 1.0 / 60.0, func(): pass)
		blue.advance(models[1], 1.0 / 60.0, func(): pass)
		if t % 4 == 0: await process_frame
	for _i: int in range(300):
		if red.tick == blue.tick: break
		red.poll(1.0 / 60.0)
		blue.poll(1.0 / 60.0)
		if red.tick < blue.tick: red.advance(models[0], 1.0 / 60.0, func(): pass)
		else: blue.advance(models[1], 1.0 / 60.0, func(): pass)
		await process_frame
	check(red.tick == blue.tick and red.tick > 1000, "both reach same tick (%d / %d)" % [red.tick, blue.tick])
	check(NetMatch.summary(models[0]) == NetMatch.summary(models[1]), "identical battles: %s vs %s" % [NetMatch.summary(models[0]), NetMatch.summary(models[1])])
	check(not red.desync and not blue.desync, "no desync reported")
	check(models[0].stats[0].plays >= 1 and models[0].stats[1].plays >= 1 and models[1].stats[0].plays == models[0].stats[0].plays and models[1].stats[1].plays == models[0].stats[1].plays, "both players commands executed identically")
	red.close()
	for _i: int in range(40):
		blue.poll(1.0 / 60.0)
		if blue.state == "lost": break
		await process_frame
	check(blue.state == "lost", "guest detects peer disconnect (%s)" % blue.state)
	blue.close()

	# 2. Private room code flow
	var r_host = NetMatch.new()
	var r_guest = NetMatch.new()
	check(r_host.host_room(deck_a, B.DEFAULT_LORD, url), "host room initiated")
	for _i: int in range(120):
		r_host.poll(1.0 / 60.0)
		if not r_host.room_code.is_empty(): break
		await process_frame
	check(r_host.room_code.length() == 4, "received 4-char room code (%s)" % r_host.room_code)
	check(r_guest.join_room(r_host.room_code, deck_b, "beast", url), "guest joins room code")
	var room_started := [false, false]
	for _i: int in range(180):
		if r_host.poll(1.0 / 60.0): room_started[0] = true
		if r_guest.poll(1.0 / 60.0): room_started[1] = true
		if room_started[0] and room_started[1]: break
		await process_frame
	check(room_started[0] and room_started[1], "room match started for both host and guest")
	r_host.close()
	r_guest.close()

	# 3. AI fallback when searching alone (timeout + unreachable server)
	var solo = NetMatch.new()
	check(solo.search_match(deck_a, B.DEFAULT_LORD, 2, url, true, 0.2), "solo search starts")
	var solo_model = null
	for _i: int in range(60):
		if solo.poll(0.05):
			solo_model = solo.make_battle()
			break
		await process_frame
	check(solo.is_ai_match and solo_model != null, "solo queue falls back to AI opponent (%s)" % solo.ai_opponent_name)
	if solo_model != null:
		check(solo_model.ai_enabled == [false, true], "AI enabled on team 1 only")
		check(DeckStore.valid(solo_model.decks[1], solo_model.lords[1].lord), "AI fallback deck is valid for its lord")
	solo.close()

	var offline_solo = NetMatch.new()
	check(offline_solo.search_match(deck_a, B.DEFAULT_LORD, 1, "ws://127.0.0.1:19999", true, 0.15), "offline search starts")
	var offline_model = null
	for _i: int in range(60):
		if offline_solo.poll(0.05):
			offline_model = offline_solo.make_battle()
			break
		await process_frame
	check(offline_solo.is_ai_match and offline_model != null, "unreachable server falls back cleanly to AI opponent")
	offline_solo.close()

	_stop_server()
	print("Net match: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
