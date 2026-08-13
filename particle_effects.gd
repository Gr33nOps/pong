extends Node
# Burst FX via CPUParticles2D (GPUParticles2D does not expose CPU-style properties).

var _particle_pool: Array[CPUParticles2D] = []
const POOL_SIZE = 20


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(POOL_SIZE):
		_particle_pool.append(_make_particle())


func _exit_tree() -> void:
	for p in _particle_pool:
		p.queue_free()
	_particle_pool.clear()


func _make_particle() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.emitting = false
	p.one_shot = true
	p.texture = preload("res://circle-128.png")
	return p


func _get_particle() -> CPUParticles2D:
	if _particle_pool.size() > 0:
		return _particle_pool.pop_back()
	return _make_particle()


func _return_particle(particle: CPUParticles2D) -> void:
	if not is_instance_valid(particle):
		return
	particle.emitting = false
	if particle.is_inside_tree():
		particle.get_parent().remove_child(particle)
	if _particle_pool.size() < POOL_SIZE:
		_particle_pool.append(particle)
	else:
		particle.queue_free()


func _setup_particles(particles: CPUParticles2D, amount: int, lifetime: float, speed: float, gravity: Vector2, color: Color) -> void:
	particles.emitting = false
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = gravity
	particles.initial_velocity_min = speed * 0.45
	particles.initial_velocity_max = speed
	particles.scale_amount_min = 0.04
	particles.scale_amount_max = 0.1
	particles.damping_min = 2.0
	particles.damping_max = 8.0
	particles.color = color
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([color, Color(color, 0.0)])
	particles.color_ramp = ramp


func _burst(world_position: Vector2, amount: int, lifetime: float, speed: float, gravity: Vector2, color: Color) -> void:
	var particles := _get_particle()
	_setup_particles(particles, amount, lifetime, speed, gravity, color)
	var scene := get_tree().current_scene
	if scene == null:
		_return_particle(particles)
		return
	scene.add_child(particles)
	particles.global_position = world_position
	particles.restart()
	particles.emitting = true
	await get_tree().create_timer(lifetime + 0.2, true).timeout
	_return_particle(particles)


func spawn_paddle_hit(world_position: Vector2, color: Color) -> void:
	_burst(world_position, 15, 0.3, 200.0, Vector2(0, 100), color)


func spawn_wall_bounce(world_position: Vector2) -> void:
	_burst(world_position, 8, 0.2, 150.0, Vector2(0, 50), Color(0.8, 0.8, 0.8, 1))


func spawn_score(world_position: Vector2) -> void:
	_burst(world_position, 30, 0.6, 300.0, Vector2(0, 200), Color(1, 1, 0, 1))
