class_name ArenaRoom
extends RefCounted
## One online room. People join in order (up to 10) and the court gets one
## side per person. The host (whoever made the room, or the next person if
## they leave) starts the match. Anyone who leaves mid-match is knocked out
## and the others play on. When the match ends the room waits again, so the
## host can start another one.

const SNAPSHOT_INTERVAL := 1.0 / 40.0
const SIM_STEP := 1.0 / 120.0
const MAX_FRAME_CATCH_UP := 0.25
## Swings that arrive before the tick the player saw are held until then.
const MAX_HELD_HIT_TICKS := 36
const MAX_NAME_LENGTH := 12
const ARENA_SIMULATION_SCRIPT = preload("res://arena_simulation.gd")

var code := ""
## Peer ids in seat order. During a match a leaver's seat becomes -1 so
## everyone else keeps their seat; the gaps close when the match ends.
var seats: Array[int] = []
var names: Array[String] = []
var host_peer := -1
var started := false
var simulation = ARENA_SIMULATION_SCRIPT.new()
var _snapshot_timer := 0.0
var _sim_accumulator := 0.0
var _held_hits: Array[Vector2i] = []
var _send_callback: Callable


func configure(room_code: String, send_callback: Callable) -> void:
	code = room_code
	_send_callback = send_callback


func has_peer(peer_id: int) -> bool:
	return seats.has(peer_id)


## Why someone can't join right now, or "" if they can.
func join_refusal() -> String:
	if started:
		return "MATCH ALREADY STARTED"
	if seats.size() >= simulation.MAX_PLAYERS:
		return "ROOM IS FULL"
	return ""


func peers() -> Array[int]:
	var result: Array[int] = []
	for peer_id in seats:
		if peer_id != -1:
			result.append(peer_id)
	return result


func add_player(peer_id: int, player_name: String) -> bool:
	if has_peer(peer_id) or not join_refusal().is_empty():
		return false
	seats.append(peer_id)
	names.append(clean_name(player_name, seats.size()))
	if host_peer == -1:
		host_peer = peer_id
	_send(peer_id, {"type": "arena_room", "code": code, "seat": seats.size() - 1})
	_broadcast_lobby()
	return true


func remove_peer(peer_id: int) -> void:
	var seat := seats.find(peer_id)
	if seat == -1:
		return
	if started:
		seats[seat] = -1
		simulation.knock_out(seat)
	else:
		seats.remove_at(seat)
		names.remove_at(seat)
	if host_peer == peer_id:
		var remaining := peers()
		host_peer = remaining[0] if not remaining.is_empty() else -1
	_broadcast_lobby()


func handle_message(peer_id: int, message: Dictionary) -> bool:
	var seat := seats.find(peer_id)
	if seat == -1:
		return false
	match str(message.get("type", "")):
		"input":
			if started:
				var target := float(message.get("target_y", -1.0))
				if target >= 0.0:
					simulation.set_target(seat, target)
				else:
					simulation.set_axis(seat, float(message.get("axis", 0.0)))
		"hit":
			if started:
				_queue_hit(seat, int(message.get("tick", -1)))
		"start":
			if peer_id != host_peer or started:
				return true
			if seats.size() < simulation.MIN_PLAYERS:
				_send(peer_id, {"type": "error", "message": "NEED AT LEAST 2 PLAYERS"})
				return true
			_start_match()
		_:
			return false
	return true


func tick(delta: float) -> void:
	if not started:
		return
	_sim_accumulator = minf(_sim_accumulator + delta, MAX_FRAME_CATCH_UP)
	while _sim_accumulator >= SIM_STEP:
		_apply_due_hits()
		simulation.tick(SIM_STEP)
		simulation.events.clear()
		_sim_accumulator -= SIM_STEP
	if simulation.state == simulation.STATE_OVER:
		_broadcast(simulation.snapshot())
		_end_match()
		return
	_snapshot_timer += delta
	if _snapshot_timer >= SNAPSHOT_INTERVAL:
		_snapshot_timer = fmod(_snapshot_timer, SNAPSHOT_INTERVAL)
		_broadcast(simulation.snapshot())


## Capital letters, digits and single spaces, at most 12 characters.
## An empty name becomes "PLAYER 3" (by seat number).
static func clean_name(raw: String, number: int) -> String:
	var allowed := RegEx.new()
	allowed.compile("[^A-Z0-9 ]")
	var spaces := RegEx.new()
	spaces.compile(" +")
	var text := spaces.sub(allowed.sub(raw.to_upper(), "", true), " ", true).strip_edges()
	text = text.substr(0, MAX_NAME_LENGTH).strip_edges()
	return text if not text.is_empty() else "PLAYER %d" % number


func _queue_hit(seat: int, at_tick: int) -> void:
	var now: int = simulation.tick_number
	if at_tick > now and at_tick - now <= MAX_HELD_HIT_TICKS:
		_held_hits.append(Vector2i(seat, at_tick))
	else:
		simulation.press_hit(seat, at_tick if at_tick >= 0 else -1)


func _apply_due_hits() -> void:
	var now: int = simulation.tick_number
	for index in range(_held_hits.size() - 1, -1, -1):
		var held := _held_hits[index]
		if held.y <= now:
			_held_hits.remove_at(index)
			simulation.press_hit(held.x)


func _start_match() -> void:
	simulation.reset_match(seats.size())
	started = true
	_held_hits.clear()
	_sim_accumulator = 0.0
	_snapshot_timer = 0.0
	_broadcast({"type": "arena_started", "names": names.duplicate()})
	_broadcast_lobby()
	_broadcast(simulation.snapshot())


## Back to waiting: people who left during the match lose their seats.
func _end_match() -> void:
	started = false
	for seat in range(seats.size() - 1, -1, -1):
		if seats[seat] == -1:
			seats.remove_at(seat)
			names.remove_at(seat)
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	for peer_id in peers():
		_send(peer_id, {
			"type": "arena_lobby",
			"code": code,
			"names": names.duplicate(),
			"you": seats.find(peer_id),
			"host": seats.find(host_peer),
			"started": started,
		})


func _broadcast(message: Dictionary) -> void:
	for peer_id in peers():
		_send(peer_id, message)


func _send(peer_id: int, message: Dictionary) -> void:
	if peer_id == -1 or not _send_callback.is_valid():
		return
	_send_callback.call(peer_id, message)
