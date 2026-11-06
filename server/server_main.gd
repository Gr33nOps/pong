extends Node
## The online server. It accepts WebSocket connections, passes every message
## to the room manager, and sends messages back to players.

const DEFAULT_PORT := 9080
## A frame-rate cap keeps the server from using more CPU than it needs.
const SERVER_MAX_FPS := 240
const ROOM_MANAGER_SCRIPT = preload("res://room_manager.gd")

var tcp_server := TCPServer.new()
var peers: Dictionary[int, WebSocketPeer] = {}
var next_peer_id := 1
var rooms = ROOM_MANAGER_SCRIPT.new()


func _ready() -> void:
	Engine.max_fps = SERVER_MAX_FPS
	rooms.configure(_send_to_peer)
	var port := _read_port()
	var result := tcp_server.listen(port)
	if result != OK:
		push_error("Unable to listen on port %d: %s" % [port, error_string(result)])
		get_tree().quit(1)
		return
	print("Paddle Polygon server listening on port %d" % port)


func _process(delta: float) -> void:
	_accept_new_players()
	for peer_id in peers.keys():
		var peer: WebSocketPeer = peers[peer_id]
		peer.poll()
		match peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while peer.get_available_packet_count() > 0:
					_handle_packet(peer_id, peer.get_packet(), peer.was_string_packet())
			WebSocketPeer.STATE_CLOSED:
				rooms.disconnect_peer(peer_id)
				peers.erase(peer_id)
	rooms.tick(delta)


func _accept_new_players() -> void:
	while tcp_server.is_connection_available():
		var stream := tcp_server.take_connection()
		# Send small snapshot packets right away instead of batching them.
		stream.set_no_delay(true)
		var peer := WebSocketPeer.new()
		if peer.accept_stream(stream) != OK:
			stream.disconnect_from_host()
			continue
		peers[next_peer_id] = peer
		next_peer_id += 1


func _handle_packet(peer_id: int, packet: PackedByteArray, is_text: bool) -> void:
	if not is_text:
		_send_error(peer_id, "TEXT PACKETS ONLY")
		return
	var text := packet.get_string_from_utf8().strip_edges()
	if text.is_empty() or text.length() > 4096:
		_send_error(peer_id, "INVALID MESSAGE SIZE")
		return
	var message = JSON.parse_string(text)
	if not message is Dictionary:
		_send_error(peer_id, "INVALID JSON MESSAGE")
		return
	rooms.handle_message(peer_id, message)


func _send_to_peer(peer_id: int, message: Dictionary) -> void:
	var peer: WebSocketPeer = peers.get(peer_id)
	if peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(JSON.stringify(message))


func _send_error(peer_id: int, message: String) -> void:
	_send_to_peer(peer_id, {"type": "error", "message": message})


## Hosting services pass the port in the PORT environment variable.
func _read_port() -> int:
	var from_environment := OS.get_environment("PORT").strip_edges()
	if from_environment.is_valid_int():
		return clampi(int(from_environment), 1, 65535)
	return DEFAULT_PORT
