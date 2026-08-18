extends Node

const DEFAULT_PORT := 9080
const ROOM_MANAGER_SCRIPT = preload("res://room_manager.gd")

var tcp_server := TCPServer.new()
var peers: Dictionary[int, WebSocketPeer] = {}
var next_peer_id := 1
var rooms = ROOM_MANAGER_SCRIPT.new()
var port := DEFAULT_PORT


func _ready() -> void:
	port = _read_port()
	rooms.configure(_send_to_peer, _close_peer)
	var result := tcp_server.listen(port)
	if result != OK:
		push_error("Unable to listen on port %d: %s" % [port, error_string(result)])
		get_tree().quit(1)
		return
	print("PONG online server listening on port %d" % port)


func _process(delta: float) -> void:
	_accept_connections()
	for peer_id in peers.keys():
		var peer: WebSocketPeer = peers[peer_id]
		peer.poll()
		var peer_state := peer.get_ready_state()
		if peer_state == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count() > 0:
				_handle_packet(peer_id, peer.get_packet(), peer.was_string_packet())
		elif peer_state == WebSocketPeer.STATE_CLOSED:
			_handle_disconnect(peer_id, peer)
	rooms.tick(delta)


func _accept_connections() -> void:
	while tcp_server.is_connection_available():
		var stream := tcp_server.take_connection()
		var peer := WebSocketPeer.new()
		var result := peer.accept_stream(stream)
		if result != OK:
			stream.disconnect_from_host()
			continue
		var peer_id := next_peer_id
		next_peer_id += 1
		peers[peer_id] = peer
		print("+ peer %d connected" % peer_id)


func _handle_packet(peer_id: int, packet: PackedByteArray, string_packet: bool) -> void:
	if not string_packet:
		_send_error(peer_id, "TEXT PACKETS ONLY")
		return
	var text := packet.get_string_from_utf8().strip_edges()
	if text.is_empty() or text.length() > 4096:
		_send_error(peer_id, "INVALID MESSAGE SIZE")
		return
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		_send_error(peer_id, "INVALID JSON MESSAGE")
		return
	rooms.handle_message(peer_id, parsed)


func _handle_disconnect(peer_id: int, peer: WebSocketPeer) -> void:
	rooms.disconnect_peer(peer_id)
	peers.erase(peer_id)
	print("- peer %d closed (%d)" % [peer_id, peer.get_close_code()])


func _send_to_peer(peer_id: int, message: Dictionary) -> void:
	if not peers.has(peer_id):
		return
	var peer: WebSocketPeer = peers[peer_id]
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(JSON.stringify(message))


func _send_error(peer_id: int, message: String) -> void:
	_send_to_peer(peer_id, {"type": "error", "message": message})


func _close_peer(peer_id: int) -> void:
	if peers.has(peer_id):
		var peer: WebSocketPeer = peers[peer_id]
		peer.close(1000, "closed by server")


func _read_port() -> int:
	var environment_port := OS.get_environment("PORT").strip_edges()
	if environment_port.is_valid_int():
		return clampi(int(environment_port), 1, 65535)
	return DEFAULT_PORT
