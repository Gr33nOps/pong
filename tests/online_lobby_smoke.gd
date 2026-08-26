extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var serve = scene.get_node("serveOverlay")
	serve._open_online_lobby()
	var valid: bool = serve._step == serve.Step.ONLINE and serve.online_overlay.visible and serve.online_option_bgs.size() == 3
	serve._close_online_lobby()
	scene.free()
	print("PONG online lobby smoke: %s" % ("passed" if valid else "failed"))
	quit(0 if valid else 1)
