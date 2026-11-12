extends SceneTree
# Two NetMatch peers over 127.0.0.1 in one process: handshake, then lockstep with commands from
# both sides; the two battles must stay identical.
const NetMatch = preload("res://net_match.gd")
const B = preload("res://balance.gd")
const L = preload("res://layout.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: "+label)

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): print("TIMEOUT"); quit(2))
	call_deferred("run")

func run() -> void:
	var host = NetMatch.new()
	var guest = NetMatch.new()
	var deck_a: Array = B.DEFAULT_DECK.duplicate()
	var deck_b: Array = ["militia","hunter","knight","farmer","rain","tower","healer","ox"]
	check(host.host(deck_a,B.DEFAULT_LORD),"host opens")
	check(guest.join("127.0.0.1",deck_b,"lion"),"guest connects")
	var models := [null,null]
	for i: int in range(600):
		if host.poll(): models[0] = host.make_battle()
		if guest.poll(): models[1] = guest.make_battle()
		if models[0] != null and models[1] != null: break
		await process_frame
	check(models[0] != null and models[1] != null,"both sides start: %s / %s (%s %s)" % [host.state,guest.state,host.message,guest.message])
	if models[0] == null or models[1] == null:
		print("Net match: %d checks, %d failures" % [checks,failures])
		quit(1)
		return
	check(host.local_team == 0 and guest.local_team == 1,"host is red, guest is blue")
	check(models[0].lords[0].lord == B.DEFAULT_LORD and models[1].lords[1].lord == "lion","both battles hold both decks and lords")
	for m in models: m.ink = [50.0,50.0]
	var plays := 0
	for t: int in range(1800):
		host.poll()
		guest.poll()
		# Each side plays something now and then (same scripted moments, different cards and spots).
		if t == 30: host.queue(["p",0,L.cell_center(Vector2i(1,2)).x,L.cell_center(Vector2i(1,2)).y])
		if t == 31: guest.queue(["p",0,L.cell_center(Vector2i(7,1)).x,L.cell_center(Vector2i(7,1)).y])
		if t == 200: guest.queue(["p",1,L.cell_center(Vector2i(7,3)).x,L.cell_center(Vector2i(7,3)).y])
		if t == 400: host.queue(["p",2,L.cell_center(Vector2i(2,0)).x,L.cell_center(Vector2i(2,0)).y])
		if t == 1300: guest.queue(["s"])
		host.advance(models[0],1.0/60.0,func(): pass)
		guest.advance(models[1],1.0/60.0,func(): pass)
		if t % 4 == 0: await process_frame
	# Let both catch up to the same tick.
	for i: int in range(300):
		if host.tick == guest.tick: break
		host.poll()
		guest.poll()
		if host.tick < guest.tick: host.advance(models[0],1.0/60.0,func(): pass)
		else: guest.advance(models[1],1.0/60.0,func(): pass)
		await process_frame
	check(host.tick == guest.tick and host.tick > 1000,"both reach the same tick (%d / %d)" % [host.tick,guest.tick])
	check(NetMatch.summary(models[0]) == NetMatch.summary(models[1]),"identical battles: %s vs %s" % [NetMatch.summary(models[0]),NetMatch.summary(models[1])])
	check(not host.desync and not guest.desync,"no desync reported")
	check(models[0].stats[0].plays >= 1 and models[0].stats[1].plays >= 1 and models[1].stats[0].plays == models[0].stats[0].plays and models[1].stats[1].plays == models[0].stats[1].plays,"both players' commands took effect (%d / %d plays)" % [models[0].stats[0].plays,models[0].stats[1].plays])
	host.close()
	for i: int in range(30):
		guest.poll()
		await process_frame
	check(guest.state == "lost","guest notices the host leaving (%s)" % guest.state)
	guest.close()
	print("Net match: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
