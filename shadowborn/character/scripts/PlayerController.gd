extends CharacterBody3D
class_name PlayerController

@export var walk_speed: float = 3.5
@export var run_speed: float = 7.0
@export var acceleration: float = 18.0
@export var deceleration: float = 24.0
@export var air_acceleration: float = 8.0
@export var jump_height: float = 1.0
@export var max_fall_speed: float = 30.0

var _gravity: float = 0.0
var _jump_velocity: float = 0.0
var _was_on_floor: bool = false
var _time_in_air: float = 0.0

@onready var _camera: Camera3D = $"../CameraRig/Camera3D"
@onready var _anim_tree: AnimationTree = $Character/AnimationTree
@onready var _anim_state: AnimationNodeStateMachinePlayback = _anim_tree.get("parameters/playback")

func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_jump_velocity = sqrt(2.0 * _gravity * jump_height)

	_anim_tree.active = true
	_anim_state.travel("Idle")


func _physics_process(delta: float) -> void:
	var input_dir: Vector3 = _get_input_direction()
	var on_floor: bool = is_on_floor()

	_apply_horizontal_movement(input_dir, on_floor, delta)
	_apply_vertical_movement(on_floor, delta)

	# ✅ Correct CharacterBody3D call
	move_and_slide()

	_update_orientation(input_dir, delta)
	_update_animation(on_floor, input_dir, delta)

	_was_on_floor = on_floor


func _get_input_direction() -> Vector3:
	var input_vector := Vector2.ZERO

	input_vector.y -= Input.get_action_strength("Up")
	input_vector.y += Input.get_action_strength("Down")
	input_vector.x -= Input.get_action_strength("Left")
	input_vector.x += Input.get_action_strength("Right")

	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()

	if input_vector == Vector2.ZERO:
		return Vector3.ZERO

	var cam_basis: Basis = _camera.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right: Vector3 = cam_basis.x
	right.y = 0.0
	right = right.normalized()

	var direction: Vector3 = forward * input_vector.y + right * input_vector.x
	return direction.normalized()


func _apply_horizontal_movement(input_dir: Vector3, on_floor: bool, delta: float) -> void:
	var horizontal_vel: Vector3 = Vector3(velocity.x, 0.0, velocity.z)

	var target_speed: float = 0.0
	var is_running: bool = Input.is_action_pressed("Run")

	if input_dir != Vector3.ZERO:
		target_speed = run_speed if is_running else walk_speed
		var target_velocity: Vector3 = input_dir * target_speed
		var accel: float = acceleration if on_floor else air_acceleration
		horizontal_vel = horizontal_vel.lerp(target_velocity, accel * delta)
	else:
		var decel: float = deceleration if on_floor else air_acceleration
		horizontal_vel = horizontal_vel.move_toward(Vector3.ZERO, decel * delta)

	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.z


func _apply_vertical_movement(on_floor: bool, delta: float) -> void:
	if on_floor:
		_time_in_air = 0.0
		if Input.is_action_just_pressed("Jump"):
			velocity.y = _jump_velocity
			return

	velocity.y -= _gravity * delta
	if velocity.y < -max_fall_speed:
		velocity.y = -max_fall_speed

	if not on_floor:
		_time_in_air += delta


func _update_orientation(input_dir: Vector3, delta: float) -> void:
	if input_dir == Vector3.ZERO:
		return

	var current_forward: Vector3 = -global_transform.basis.z
	current_forward.y = 0.0
	current_forward = current_forward.normalized()

	var target_forward: Vector3 = input_dir.normalized()

	var rotate_speed: float = 14.0
	var t: float = clamp(rotate_speed * delta, 0.0, 1.0)
	var new_forward: Vector3 = current_forward.slerp(target_forward, t)

	look_at(global_transform.origin + new_forward, Vector3.UP)


func _update_animation(on_floor: bool, input_dir: Vector3, _delta: float) -> void:
	var horizontal_speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
	var is_running: bool = Input.is_action_pressed("Run")
	var current: StringName = _anim_state.get_current_node()

	if not on_floor:
		if velocity.y > 0.0:
			if current != "Jump":
				_anim_state.travel("Jump")
		elif _time_in_air > 0.05 and current != "Fall":
			_anim_state.travel("Fall")
		return

	if not _was_on_floor and on_floor:
		_anim_state.travel("Land")
		return

	if horizontal_speed < 0.1 or input_dir == Vector3.ZERO:
		if current != "Idle":
			_anim_state.travel("Idle")
		return

	if is_running:
		if current != "Run":
			_anim_state.travel("Run")
	else:
		if current != "Walk":
			_anim_state.travel("Walk")
