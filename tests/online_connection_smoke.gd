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
	var serve = scene.get_node("serveOverlay")
	serve._open_online_lobby()


func _process(delta: float) -> bool:
	elapsed += delta
	if manager.state == manager.STATE_CONNECTED:
		print("PONG online connection smoke: passed")
		manager.disconnect_from_server()
		quit(0)
		return false
	if elapsed > 10.0:
		print("PONG online connection smoke: timed out. %s" % manager.status_message)
		quit(1)
		return false
	return true
