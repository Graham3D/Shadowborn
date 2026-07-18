extends CharacterBody3D
class_name PlayerController

@export var walk_speed: float = 3.5
@export var run_speed: float = 7.0
@export var acceleration: float = 18.0
@export var deceleration: float = 24.0
@export var air_acceleration: float = 8.0
@export_range(0.05, 5.0, 0.05) var run_acceleration_time: float = 1.0
@export_range(1.0, 2.0, 0.05) var walk_animation_speed: float = 1.2
@export_range(1.0, 2.5, 0.05) var landing_animation_speed: float = 1.5
@export_range(-1.0, 0.0, 0.05) var slide_direction_threshold: float = -0.85
@export_range(0.0, 1.0, 0.05) var slide_minimum_run_ratio: float = 0.95
@export_range(0.0, 0.5, 0.01) var slide_reversal_grace_time: float = 0.15
@export_range(0.5, 3.0, 0.05) var turn_duration_scale: float = 0.8
@export var jump_height: float = 1.0
@export var max_fall_speed: float = 30.0

var _gravity: float = 0.0
var _jump_velocity: float = 0.0
var _was_on_floor: bool = false
var _time_in_air: float = 0.0
var _has_been_airborne: bool = false
var _is_landing: bool = false
var _landing_time_remaining: float = 0.0
var _landing_duration: float = 0.0
var _run_buildup: float = 0.0
var _is_sliding: bool = false
var _slide_time_remaining: float = 0.0
var _slide_duration: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO
var _slide_exit_direction: Vector3 = Vector3.ZERO
var _slide_start_speed: float = 0.0
var _slide_reversal_grace_remaining: float = 0.0
var _slide_start_angle: float = 0.0

# CameraRig and Camera3D are children of Player
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _character: Node3D = $Character
@onready var _anim_player: AnimationPlayer = $Character/AnimationPlayer
@onready var _anim_tree: AnimationTree = $Character/AnimationTree
@onready var _anim_state: AnimationNodeStateMachinePlayback = _anim_tree.get("parameters/playback")


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_jump_velocity = sqrt(2.0 * _gravity * jump_height)

	_anim_tree.active = true
	_anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_anim_state.travel("idle")   # lowercase idle
	var turn_animation: Animation = _anim_player.get_animation("Turn")
	if turn_animation != null:
		_slide_duration = turn_animation.length * turn_duration_scale
	var land_animation: Animation = _anim_player.get_animation("Land")
	if land_animation != null:
		_landing_duration = land_animation.length / landing_animation_speed


func _physics_process(delta: float) -> void:
	var input_dir: Vector3 = _get_input_direction()
	var was_on_floor: bool = is_on_floor()
	var handled_slide: bool = false
	_update_slide_reversal_window(delta)

	if _is_sliding:
		handled_slide = true
		_update_slide(delta)
	elif _should_start_slide(input_dir, was_on_floor):
		handled_slide = true
		_start_slide(input_dir)
		_update_slide(delta)
	else:
		_apply_horizontal_movement(input_dir, was_on_floor, delta)
	_apply_vertical_movement(was_on_floor, delta)

	move_and_slide()
	var on_floor: bool = is_on_floor()

	if not handled_slide:
		_update_orientation(input_dir, delta)
	_update_animation(on_floor, input_dir, delta)
	_advance_animation(delta)

	_was_on_floor = on_floor


func _get_input_direction() -> Vector3:
	var input_vector := Vector2.ZERO

	input_vector.y += Input.get_action_strength("Up")
	input_vector.y -= Input.get_action_strength("Down")
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
	var target_velocity: Vector3 = Vector3.ZERO
	var movement_rate: float = deceleration if on_floor else air_acceleration

	if input_dir != Vector3.ZERO:
		var target_speed: float = walk_speed
		if Input.is_action_pressed("Run"):
			_run_buildup = min(_run_buildup + delta / run_acceleration_time, 1.0)
			target_speed = lerp(walk_speed, run_speed, _run_buildup)
		else:
			_run_buildup = 0.0
		target_velocity = input_dir * target_speed
		movement_rate = acceleration if on_floor else air_acceleration
	else:
		_run_buildup = 0.0

	horizontal_vel = horizontal_vel.move_toward(target_velocity, movement_rate * delta)

	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.z


func _should_start_slide(input_dir: Vector3, on_floor: bool) -> bool:
	if not on_floor or _slide_duration <= 0.0:
		return false
	if _slide_reversal_grace_remaining <= 0.0:
		return false

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length() < walk_speed:
		return false

	# Releasing either the Run action or movement at full speed performs a
	# braking turn before returning to walk or idle.
	if not Input.is_action_pressed("Run") or input_dir == Vector3.ZERO:
		return true

	return horizontal_velocity.normalized().dot(input_dir) <= slide_direction_threshold


func _update_slide_reversal_window(delta: float) -> void:
	var horizontal_speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
	var at_full_run: bool = (
		_run_buildup >= slide_minimum_run_ratio
		and horizontal_speed >= run_speed * slide_minimum_run_ratio
	)
	if at_full_run:
		_slide_reversal_grace_remaining = slide_reversal_grace_time
	else:
		_slide_reversal_grace_remaining = maxf(
			_slide_reversal_grace_remaining - delta,
			0.0
		)


func _start_slide(exit_direction: Vector3) -> void:
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	_is_sliding = true
	_slide_time_remaining = _slide_duration
	_slide_direction = horizontal_velocity.normalized()
	_slide_exit_direction = exit_direction
	_slide_start_speed = horizontal_velocity.length()
	_slide_reversal_grace_remaining = 0.0
	_slide_start_angle = _character.rotation.y
	_run_buildup = 0.0
	_anim_state.travel("Turn")


func _update_slide(delta: float) -> void:
	_slide_time_remaining = max(_slide_time_remaining - delta, 0.0)
	var progress: float = 1.0 - _slide_time_remaining / _slide_duration
	var exit_speed: float = walk_speed if _slide_exit_direction != Vector3.ZERO else 0.0
	var slide_speed: float = lerpf(_slide_start_speed, exit_speed, progress)
	velocity.x = _slide_direction.x * slide_speed
	velocity.z = _slide_direction.z * slide_speed
	# The braking animation stays locked to the direction the run began in.
	_character.rotation.y = _slide_start_angle

	if _slide_time_remaining > 0.0:
		return

	_is_sliding = false
	velocity.x = _slide_exit_direction.x * exit_speed
	velocity.z = _slide_exit_direction.z * exit_speed
	if _slide_exit_direction == Vector3.ZERO:
		_anim_state.travel("idle")
	else:
		_anim_state.travel("walk")


func _apply_vertical_movement(on_floor: bool, delta: float) -> void:
	if on_floor:
		_time_in_air = 0.0
		if Input.is_action_just_pressed("Jump"):
			# A fresh jump always wins over the remainder of a landing clip.
			_is_landing = false
			_landing_time_remaining = 0.0
			_has_been_airborne = true
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

	var target_angle: float = atan2(input_dir.x, input_dir.z)
	var rotation_weight: float = clamp(14.0 * delta, 0.0, 1.0)
	_character.rotation.y = lerp_angle(
		_character.rotation.y,
		target_angle,
		rotation_weight
	)


func _update_animation(on_floor: bool, input_dir: Vector3, delta: float) -> void:
	var horizontal_speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
	var is_running: bool = Input.is_action_pressed("Run") and _run_buildup >= 0.5
	var current: StringName = _anim_state.get_current_node()

	if _is_sliding:
		if current != "Turn":
			_anim_state.travel("Turn")
		return

	if _is_landing:
		_landing_time_remaining = maxf(_landing_time_remaining - delta, 0.0)
		if _landing_time_remaining > 0.0:
			if current != "Land":
				_anim_state.travel("Land")
			return
		_is_landing = false

	# Jump / Fall
	if not on_floor:
		if _time_in_air > 0.05:
			_has_been_airborne = true
		if velocity.y > 0.0:
			if current != "jump":
				_anim_state.travel("jump")
		elif _time_in_air > 0.05 and current != "Fall":
			_anim_state.travel("Fall")  # capital F
		return

	# Landing
	if _has_been_airborne and not _was_on_floor and on_floor:
		_has_been_airborne = false
		_is_landing = true
		_landing_time_remaining = _landing_duration
		_anim_state.travel("Land")
		return

	# Idle
	if horizontal_speed < 0.1 or input_dir == Vector3.ZERO:
		if current != "idle":
			_anim_state.travel("idle")
		return

	# Walk / Run
	if is_running:
		if current != "run":
			_anim_state.travel("run")
	else:
		if current != "walk":
			_anim_state.travel("walk")


func _advance_animation(delta: float) -> void:
	var playback_speed: float = 1.0
	if _is_sliding:
		playback_speed = 1.0 / turn_duration_scale
	elif _is_landing or _anim_state.get_current_node() == "Land":
		playback_speed = landing_animation_speed
	elif _anim_state.get_current_node() == "walk":
		playback_speed = walk_animation_speed
	_anim_tree.advance(delta * playback_speed)
