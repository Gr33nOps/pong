class_name ArenaRoom
extends RefCounted
## Online polygon room. The host picks how many sides (2-7), people take seats
## in join order, and the host starts; AI paddles fill every empty seat and take
## over from anyone who drops out mid-match.

const SNAPSHOT_INTERVAL := 1.0 / 40.0
const SIM_STEP := 1.0 / 120.0
const MAX_FRAME_CATCH_UP := 0.25
## Swings that arrive before the tick the player saw are held until then.
const MAX_HELD_HIT_TICKS := 36
const ARENA_SIMULATION_SCRIPT = preload("res://arena_simulation.gd")

var code := ""
var size := 4
var seats: Array[int] = []
var host_peer := -1
var started := false
var simulation = ARENA_SIMULATION_SCRIPT.new()
var _snapshot_timer := 0.0
var _sim_accumulator := 0.0
var _held_hits: Array[Vector2i] = []
var _send_callback: Callable
var _close_callback: Callable


func configure(room_code: String, send_callback: Callable, close_callback: Callable, room_size: int = 4) -> void:
	code = room_code
	_send_callback = send_callback
	_close_callback = close_callback
	_resize(room_size)


func has_peer(peer_id: int) -> bool:
	return seats.has(peer_id)


func is_full() -> bool:
	return not seats.has(-1)


func join_refusal() -> String:
	if is_full():
		return "ROOM IS FULL"
	if started and simulation.state != simulation.STATE_OVER:
		return "MATCH ALREADY STARTED"
	return ""


func peers() -> Array[int]:
	var result: Array[int] = []
	for peer_id in seats:
		if peer_id != -1:
			result.append(peer_id)
	return result


func add_creator(peer_id: int) -> bool:
	if not peers().is_empty():
		return false
	seats[0] = peer_id
	host_peer = peer_id
	_send(peer_id, {"type": "arena_room", "code": code, "seat": 0})
	_broadcast_lobby()
	return true


func add_joiner(peer_id: int) -> bool:
	if has_peer(peer_id) or not join_refusal().is_empty():
		return false
	var seat := seats.find(-1)
	seats[seat] = peer_id
	if host_peer == -1:
		host_peer = peer_id
	_send(peer_id, {"type": "arena_room", "code": code, "seat": seat})
	_broadcast_lobby()
	return true


func remove_peer(peer_id: int) -> Array[int]:
	var seat := seats.find(peer_id)
	if seat != -1:
		seats[seat] = -1
		if started:
			simulation.set_cpu(seat, true)
	if host_peer == peer_id:
		var remaining := peers()
		host_peer = remaining[0] if not remaining.is_empty() else -1
	_broadcast_lobby()
	return peers()


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
		"set_size":
			if peer_id == host_peer and not started:
				_resize(int(message.get("size", size)))
				_broadcast_lobby()
		"start":
			if peer_id == host_peer and not started:
				_start_match()
		"rematch":
			if started and simulation.state == simulation.STATE_OVER:
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
	_snapshot_timer += delta
	if _snapshot_timer >= SNAPSHOT_INTERVAL:
		_snapshot_timer = fmod(_snapshot_timer, SNAPSHOT_INTERVAL)
		_broadcast(simulation.snapshot())


## People already seated always keep a seat; the room never shrinks below them.
func _resize(next_size: int) -> void:
	var humans := peers().size()
	size = clampi(next_size, maxi(simulation.MIN_PLAYERS, humans), simulation.MAX_PLAYERS)
	var kept: Array[int] = []
	for peer_id in seats:
		if peer_id != -1:
			kept.append(peer_id)
	seats.clear()
	for seat in size:
		seats.append(kept[seat] if seat < kept.size() else -1)


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
	var cpu_seats := []
	for peer_id in seats:
		cpu_seats.append(peer_id == -1)
	simulation.reset_match(cpu_seats)
	started = true
	_held_hits.clear()
	_sim_accumulator = 0.0
	_snapshot_timer = 0.0
	_broadcast({"type": "arena_started"})
	_broadcast_lobby()
	_broadcast(simulation.snapshot())


func _broadcast_lobby() -> void:
	var humans := []
	for peer_id in seats:
		humans.append(peer_id != -1)
	for peer_id in peers():
		_send(peer_id, {
			"type": "arena_lobby",
			"code": code,
			"size": size,
			"seats": humans,
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
