extends CharacterBody3D

# ------------------------
# MOVEMENT CONSTANTS
# ------------------------
const WALK_SPEED := 5.0
const RUN_MULTIPLIER := 1.8
const ACCELERATION := 15.0
const DECELERATION := 25.0
const AIR_CONTROL := 0.9
const AIR_FRICTION := 6.0
const JUMP_VELOCITY := 4.5

# Mesh->Godot forward offset (your mesh needed this earlier)
const ROTATION_OFFSET := deg_to_rad(270.0)

const TURN_SPEED := 12.0

# ------------------------
# VAULTING CONSTANTS (Option A: Zelda-style)
# ------------------------
const VAULT_SPEED := 4.0
const MAX_LEDGE_HEIGHT := 2.0   # max ledge height player can vault (meters)
const MIN_LEDGE_HEIGHT := 0.4   # must be at least this tall to consider (prevents tiny bumps)

var is_vaulting := false
var vault_target_position: Vector3 = Vector3.ZERO

# ------------------------
# RUNTIME VARIABLES
# ------------------------
var is_jumping := false
var has_landed := true
var is_running := false
var target_yaw := 0.0
var current_speed := 0.0
var on_floor := true

# ------------------------
# NODE REFERENCES
# ------------------------
@onready var anim_player := $Character_Skin/Animations
@onready var character_mesh := $Character_Skin

# Raycasts are children of Character_Skin (per your scene). Adjust if different.
@onready var wall_check  := $Character_Skin/wall_check
@onready var ledge_check := $Character_Skin/ledge_check
@onready var ledge_down  := $Character_Skin/ledge_down


# ------------------------
# HELPER: validate ledge top before vaulting
# ------------------------
func get_valid_ledge_top() -> Vector3:
	# ledge_down must hit something
	if not ledge_down.is_colliding():
		return Vector3.INF

	var hit_pos : Vector3 = ledge_down.get_collision_point()
	var normal  : Vector3 = ledge_down.get_collision_normal()

	# must be mostly flat
	if normal.dot(Vector3.UP) < 0.85:
		return Vector3.INF

	# must be reasonably near (prevent jumping across map)
	if global_position.distance_to(hit_pos) > 2.5:
		return Vector3.INF

	# check vertical difference (height of ledge top compared to player feet)
	var height_diff := hit_pos.y - global_position.y
	if height_diff > MAX_LEDGE_HEIGHT or height_diff < MIN_LEDGE_HEIGHT:
		return Vector3.INF

	# small safety offset to place player above surface
	return hit_pos + Vector3(0, 0.15, 0)


func _physics_process(delta: float) -> void:
	# ------------------------
	# Ensure raycasts point in the true forward direction for your mesh
	# This corrects the earlier problem where the mesh had a rotation offset
	# and rays ended up pointing diagonally (causing corner-only vaulting).
	# ------------------------
	var base := global_transform.basis
	# rotate base by rotation offset so "forward" for rays matches mesh forward
	base = base.rotated(Vector3.UP, ROTATION_OFFSET)

	# assign corrected basis to raycasts so their "Target Position" is interpreted in the correct forward
	wall_check.global_transform.basis  = base
	ledge_check.global_transform.basis = base
	ledge_down.global_transform.basis  = base

	# ------------------------
	# Floor detection (slope-safe)
	# ------------------------
	on_floor = is_on_floor() or (get_floor_normal().dot(Vector3.UP) > 0.7)

	# ------------------------
	# Vault movement (handled first; vault disables other movement)
	# ------------------------
	if is_vaulting:
		global_position = global_position.move_toward(vault_target_position, VAULT_SPEED * delta)
		if global_position.distance_to(vault_target_position) < 0.1:
			is_vaulting = false
			has_landed = true
			is_jumping = false
			velocity = Vector3.ZERO
			anim_player.play("Player/Idle")
		return  # skip usual movement while vaulting

	# ------------------------
	# Gravity
	# ------------------------
	if not on_floor:
		velocity.y += get_gravity().y * delta * 1.2

	# ------------------------
	# Jump input
	# ------------------------
	if Input.is_action_just_pressed("ui_accept") and on_floor and has_landed:
		velocity.y = JUMP_VELOCITY
		velocity.x *= 0.3
		velocity.z *= 0.3
		is_jumping = true
		has_landed = false

		anim_player.play("Player/Jump_Start")
		await anim_player.animation_finished
		if not is_on_floor():
			anim_player.play("Player/Jump_Loop")

	# ------------------------
	# Ground-vault check: hold Jump next to a wall to climb up
	# ------------------------
	if not is_vaulting and on_floor and Input.is_action_pressed("ui_accept"):
		if wall_check.is_colliding() and ledge_check.is_colliding():
			var top_pos := get_valid_ledge_top()
			if top_pos != Vector3.INF:
				vault_target_position = top_pos
				is_vaulting = true
				has_landed = false
				anim_player.play("Player/Walk")  # placeholder until proper vault anim exists
				return

	# ------------------------
	# Mid-air ledge grab: while airborne, hit wall & hold jump to grab
	# ------------------------
	if not is_vaulting and is_jumping and Input.is_action_pressed("ui_accept"):
		if wall_check.is_colliding() and ledge_check.is_colliding():
			var top_pos2 := get_valid_ledge_top()
			if top_pos2 != Vector3.INF:
				vault_target_position = top_pos2
				is_vaulting = true
				velocity = Vector3.ZERO
				anim_player.play("Player/Walk")
				return

	# ------------------------
	# Landing detection
	# ------------------------
	if is_jumping and on_floor and velocity.y <= 0.0:
		is_jumping = false
		velocity.x = 0.0
		velocity.z = 0.0
		anim_player.play("Player/Jump_End")
		has_landed = true

	# ------------------------
	# Run input
	# ------------------------
	is_running = Input.is_action_pressed("Run")

	# ------------------------
	# Movement input
	# ------------------------
	var input_dir := Input.get_vector("Left", "Right", "Up", "Down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# ------------------------
	# Smooth rotation of mesh (visual only)
	# ------------------------
	if input_dir != Vector2.ZERO:
		target_yaw = atan2(direction.x, direction.z) + ROTATION_OFFSET
	var current_yaw: float = character_mesh.rotation.y
	character_mesh.rotation.y = lerp_angle(current_yaw, target_yaw, TURN_SPEED * delta)

	# ------------------------
	# Determine base speed (walk or run)
	# ------------------------
	var target_speed := WALK_SPEED
	if is_running:
		target_speed *= RUN_MULTIPLIER

	# ------------------------
	# Ground movement
	# ------------------------
	if on_floor and has_landed:
		if input_dir != Vector2.ZERO:
			current_speed = move_toward(current_speed, target_speed, ACCELERATION * delta)

			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed

			if is_running:
				anim_player.play("Player/Run")
			else:
				anim_player.play("Player/Walk")

		else:
			current_speed = move_toward(current_speed, 0.0, DECELERATION * delta)
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed

			if current_speed <= 0.05:
				velocity.x = 0.0
				velocity.z = 0.0
				anim_player.play("Player/Idle")
	else:
		# ------------------------
		# Air movement (responsive steering)
		# ------------------------
		var target_vel_x := direction.x * target_speed
		var target_vel_z := direction.z * target_speed
		velocity.x = lerp(velocity.x, target_vel_x, clamp(AIR_CONTROL * AIR_FRICTION * delta, 0, 1))
		velocity.z = lerp(velocity.z, target_vel_z, clamp(AIR_CONTROL * AIR_FRICTION * delta, 0, 1))

	# ------------------------
	# Floor snap / stairs tuning
	# ------------------------
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.5
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_block_on_wall = false

	move_and_slide()
