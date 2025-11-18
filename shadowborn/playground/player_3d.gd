extends CharacterBody3D

@export var move_speed := 5.0
@export var rotation_speed := 8.0
@export var gravity := 9.8
@export var jump_force := 6.0

@export_group("Camera")
@export var mouse_sensitivity := 0.3
@export var max_look_up := deg_to_rad(45)
@export var max_look_down := deg_to_rad(-30)
@export var max_yaw_left := deg_to_rad(-60)
@export var max_yaw_right := deg_to_rad(60)

@onready var anim: AnimationPlayer = $Animations
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

# NOTE: Do NOT declare `var velocity` here — CharacterBody3D already has `velocity`.
var input_dir := Vector2.ZERO
var camera_rotation := Vector2.ZERO

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Play an animation only if it exists to avoid errors
	if anim and anim.has_animation("Idle"):
		anim.play("Idle")

func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_rotation.x -= event.relative.y * mouse_sensitivity * 0.01
		camera_rotation.y -= event.relative.x * mouse_sensitivity * 0.01
		camera_rotation.x = clamp(camera_rotation.x, max_look_down, max_look_up)
		camera_rotation.y = clamp(camera_rotation.y, max_yaw_left, max_yaw_right)
		camera_pivot.rotation.x = camera_rotation.x
		camera_pivot.rotation.y = camera_rotation.y

func _physics_process(delta):
	_handle_input()
	_move_character(delta)
	_update_animation()

func _handle_input():
	# Using get_action_strength to avoid any confusion about ordering in get_vector
	var left := Input.get_action_strength("move_left")
	var right := Input.get_action_strength("move_right")
	var forward := Input.get_action_strength("move_forward")
	var backward := Input.get_action_strength("move_backward")
	input_dir.x = right - left
	input_dir.y = backward - forward

func _move_character(delta):
	# Build 3D direction relative to camera yaw (so W moves toward camera forward)
	var dir3 := Vector3.ZERO
	dir3.x = input_dir.x
	dir3.z = input_dir.y
	# Rotate direction by camera yaw (so movement is camera-relative)
	dir3 = dir3.rotated(Vector3.UP, camera_pivot.rotation.y).normalized()

	if dir3 != Vector3.ZERO:
		velocity.x = dir3.x * move_speed
		velocity.z = dir3.z * move_speed
		# smooth rotation toward move direction
		var target_angle := atan2(-dir3.x, -dir3.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
	else:
		# gradually slow to stop (basic damping)
		velocity.x = move_toward(velocity.x, 0.0, move_speed * delta * 5.0)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * delta * 5.0)

	# Gravity & jump (use the built-in `velocity.y`)
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_force

	move_and_slide()

func _update_animation():
	# Safety: don't try to play an animation that doesn't exist
	if not anim:
		return

	# Air animation
	if not is_on_floor():
		if anim.has_animation("Jump Idle"):
			_play_animation("Jump Idle")
		return

	# Movement animations
	if input_dir.length() > 0:
		# Use Run when sprinting, otherwise Walk
		if Input.is_action_pressed("sprint") and anim.has_animation("Run"):
			_play_animation("Run")
		elif anim.has_animation("Walk"):
			_play_animation("Walk")
		else:
			_play_animation("Idle")
	else:
		if anim.has_animation("Idle"):
			_play_animation("Idle")

func _play_animation(anim_name: String):
	if not anim:
		return
	var full_name = "Player/" + anim_name
	if anim.has_animation(full_name):
		if anim.current_animation != full_name:
			anim.play(full_name)
