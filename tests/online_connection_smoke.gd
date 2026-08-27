extends SceneTree

var elapsed := 0.0
var scene: Node
var manager: Node


func _initialize() -> void:
	manager = get_root().get_node("NetworkManager")
	var packed: PackedScene = load("res://main.tscn")
	scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var url := OS.get_environment("PONG_TEST_SERVER_URL").strip_edges()
	if url.is_empty():
		url = "ws://127.0.0.1:9081"
	manager.connect_to_server(url)


func _process(delta: float) -> bool:
	elapsed += delta
	if manager.state == manager.STATE_CONNECTED:
		print("PONG online connection smoke: passed")
		manager.disconnect_from_server()
		quit(0)
		return true
	if elapsed > 10.0:
		print("PONG online connection smoke: timed out. %s" % manager.status_message)
		quit(1)
		return true
	return false
