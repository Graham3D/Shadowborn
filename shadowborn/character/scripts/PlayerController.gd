extends CharacterBody3D
class_name PlayerController

@export var walk_speed: float = 4.0
@export var run_speed: float = 8.0
@export var acceleration: float = 40.0
@export var deceleration: float = 50.0
@export var air_acceleration: float = 12.0
@export_range(0.0, 60.0, 1.0) var max_walkable_slope_degrees: float = 50.0
@export_range(0.0, 1.0, 0.05) var floor_snap_distance: float = 0.4
@export var keep_constant_speed_on_slopes: bool = true
@export_range(0.05, 5.0, 0.05) var run_acceleration_time: float = 0.35
@export_range(1.0, 2.0, 0.05) var walk_animation_speed: float = 1.5
@export_range(1.0, 2.0, 0.05) var run_animation_speed: float = 1.35
@export_range(0.4, 0.95, 0.05) var cardinal_turn_threshold: float = 0.75
@export_range(0.0, 1.0, 0.05) var running_drift_strength: float = 0.55
@export_range(1.0, 2.5, 0.05) var landing_animation_speed: float = 1.65
@export_range(-1.0, 0.0, 0.05) var slide_direction_threshold: float = -0.85
@export_range(0.0, 1.0, 0.05) var slide_minimum_run_ratio: float = 0.95
@export_range(0.0, 0.5, 0.01) var slide_reversal_grace_time: float = 0.15
@export_range(0.3, 3.0, 0.05) var turn_duration_scale: float = 0.55
@export var jump_height: float = 2.0
@export var walking_jump_distance: float = 2.0
@export var running_jump_distance: float = 6.1
@export_range(1.0, 5.0, 0.1) var jump_rise_gravity_multiplier: float = 2.3
@export_range(1.0, 6.0, 0.1) var jump_fall_gravity_multiplier: float = 3.5
@export_range(1.0, 8.0, 0.1) var jump_release_gravity_multiplier: float = 4.0
@export_range(0.0, 30.0, 0.5) var jump_brake_deceleration: float = 12.0
@export_range(0.0, 1.0, 0.05) var minimum_jump_speed_ratio: float = 0.3
@export_range(1.0, 2.5, 0.05) var jump_animation_speed: float = 1.65
@export_range(1.0, 2.5, 0.05) var fall_animation_speed: float = 1.55
@export var max_fall_speed: float = 30.0
@export_range(2.0, 4.0, 0.1) var mantle_max_height: float = 3.2
@export_range(1.0, 3.0, 0.1) var mantle_min_height: float = 2.4
@export_range(0.0, 2.0, 0.1) var airborne_mantle_min_height: float = 0.4
@export_range(0.5, 2.0, 0.05) var mantle_reach: float = 1.0
@export_range(0.5, 2.0, 0.05) var mantle_duration_scale: float = 1.0
@export_range(0.5, 2.0, 0.05) var sword_slash_speed: float = 1.4

const SWORD_SLASH_ANIMATION: StringName = &"Sword_Combos/Sword_Slash_A"

var _gravity: float = 0.0
var _jump_velocity: float = 0.0
var _spawn_transform: Transform3D
var _spawn_character_rotation: float = 0.0
var _was_on_floor: bool = false
var _time_in_air: float = 0.0
var _has_been_airborne: bool = false
var _is_committed_jump: bool = false
var _jump_started_running: bool = false
var _jump_horizontal_direction: Vector3 = Vector3.ZERO
var _jump_horizontal_speed: float = 0.0
var _jump_initial_horizontal_speed: float = 0.0
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
var _cardinal_facing: Vector3 = Vector3.BACK
var _turn_animation_duration: float = 0.0
var _slide_animation_speed: float = 1.0
var _is_mantling: bool = false
var _mantle_requires_jump_release: bool = false
var _mantle_start_position: Vector3 = Vector3.ZERO
var _mantle_control_position: Vector3 = Vector3.ZERO
var _mantle_target_position: Vector3 = Vector3.ZERO
var _mantle_elapsed: float = 0.0
var _mantle_duration: float = 0.0
var _mantle_animation_speed: float = 1.0
var _is_sword_slashing: bool = false
var _sword_slash_time_remaining: float = 0.0
var _sword_slash_duration: float = 0.0
var _sword_slash_animation_node: AnimationNodeAnimation

# CameraRig and Camera3D are children of Player
@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _character: Node3D = $Character
@onready var _skeleton: Skeleton3D = $Character/RootRotationFix/Skeleton3D
@onready var _anim_player: AnimationPlayer = $Character/AnimationPlayer
@onready var _anim_tree: AnimationTree = $Character/AnimationTree
var _anim_state: AnimationNodeStateMachinePlayback


func _ready() -> void:
	_spawn_transform = global_transform
	_spawn_character_rotation = _character.rotation.y
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_jump_velocity = sqrt(
		2.0 * _gravity * jump_rise_gravity_multiplier * jump_height
	)
	floor_max_angle = deg_to_rad(max_walkable_slope_degrees)
	floor_snap_length = floor_snap_distance
	floor_constant_speed = keep_constant_speed_on_slopes

	_create_in_place_mantle_animation()
	_setup_upper_body_sword_slash()
	_anim_tree.active = true
	_anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_anim_state.travel("idle")   # lowercase idle
	var turn_animation: Animation = _anim_player.get_animation("Turn")
	if turn_animation != null:
		_turn_animation_duration = turn_animation.length
		_slide_duration = _turn_animation_duration * turn_duration_scale
	var land_animation: Animation = _anim_player.get_animation("Land")
	if land_animation != null:
		_landing_duration = land_animation.length / landing_animation_speed


func reset_to_spawn() -> void:
	global_transform = _spawn_transform
	_character.rotation.y = _spawn_character_rotation
	_cardinal_facing = Vector3(
		sin(_spawn_character_rotation),
		0.0,
		cos(_spawn_character_rotation)
	)
	velocity = Vector3.ZERO
	_is_committed_jump = false
	_jump_started_running = false
	_has_been_airborne = false
	_is_landing = false
	_is_sliding = false
	_is_mantling = false
	_is_sword_slashing = false
	_sword_slash_time_remaining = 0.0
	_mantle_requires_jump_release = false
	_run_buildup = 0.0
	_time_in_air = 0.0
	_was_on_floor = false
	_anim_state.travel("idle")
	_anim_tree.set(
		"parameters/Sword_Slash_OneShot/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT
	)


func _create_in_place_mantle_animation() -> void:
	var source: Animation = _anim_player.get_animation("Mantle")
	if source == null or _skeleton.get_bone_count() == 0:
		return

	var in_place: Animation = source.duplicate(true)
	var root_bone_name: StringName = _skeleton.get_bone_name(0)
	for track_index: int in in_place.get_track_count():
		if in_place.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		var track_path: NodePath = in_place.track_get_path(track_index)
		if track_path.get_subname_count() == 0:
			continue
		if track_path.get_subname(track_path.get_subname_count() - 1) != root_bone_name:
			continue
		if in_place.track_get_key_count(track_index) == 0:
			continue

		var root_start_position: Vector3 = in_place.track_get_key_value(track_index, 0)
		for key_index: int in in_place.track_get_key_count(track_index):
			in_place.track_set_key_value(track_index, key_index, root_start_position)

	var library: AnimationLibrary = _anim_player.get_animation_library("")
	if library == null:
		return
	if library.has_animation("Mantle_InPlace"):
		library.remove_animation("Mantle_InPlace")
	library.add_animation("Mantle_InPlace", in_place)

	var state_machine: AnimationNodeStateMachine = _anim_tree.tree_root
	var mantle_node: AnimationNodeAnimation = state_machine.get_node("Mantle")
	if mantle_node != null:
		mantle_node.animation = &"Mantle_InPlace"


func _setup_upper_body_sword_slash() -> void:
	var locomotion_state_machine: AnimationNodeStateMachine = _anim_tree.tree_root
	var blend_tree := AnimationNodeBlendTree.new()
	_sword_slash_animation_node = AnimationNodeAnimation.new()
	var slash_speed := AnimationNodeTimeScale.new()
	var slash_one_shot := AnimationNodeOneShot.new()

	_sword_slash_animation_node.animation = SWORD_SLASH_ANIMATION
	slash_one_shot.fadein_time = 0.03
	slash_one_shot.fadeout_time = 0.05
	slash_one_shot.filter_enabled = true

	var upper_body_tracks: Array[NodePath] = [
		NodePath("IK Chain Right Arm"),
		NodePath("IK Chain Left Arm"),
		NodePath("RootRotationFix/Skeleton3D:stomach"),
		NodePath("RootRotationFix/Skeleton3D:chest"),
		NodePath("RootRotationFix/Skeleton3D:head"),
		NodePath("RootRotationFix/Skeleton3D:right_bicep"),
		NodePath("RootRotationFix/Skeleton3D:left_bicep"),
		NodePath("RootRotationFix/Skeleton3D:right_forearm"),
		NodePath("RootRotationFix/Skeleton3D:left_forearm"),
		NodePath("RootRotationFix/Skeleton3D:left_hand"),
	]
	for track_path: NodePath in upper_body_tracks:
		slash_one_shot.set_filter_path(track_path, true)

	blend_tree.add_node("Locomotion", locomotion_state_machine, Vector2(0.0, 0.0))
	blend_tree.add_node("Sword_Slash", _sword_slash_animation_node, Vector2(0.0, 160.0))
	blend_tree.add_node("Sword_Slash_Speed", slash_speed, Vector2(220.0, 160.0))
	blend_tree.add_node("Sword_Slash_OneShot", slash_one_shot, Vector2(440.0, 0.0))
	blend_tree.connect_node("Sword_Slash_Speed", 0, "Sword_Slash")
	blend_tree.connect_node("Sword_Slash_OneShot", 0, "Locomotion")
	blend_tree.connect_node("Sword_Slash_OneShot", 1, "Sword_Slash_Speed")
	blend_tree.connect_node("output", 0, "Sword_Slash_OneShot")

	_anim_tree.tree_root = blend_tree
	_anim_tree.set("parameters/Sword_Slash_Speed/scale", sword_slash_speed)
	_anim_state = _anim_tree.get("parameters/Locomotion/playback")


func _physics_process(delta: float) -> void:
	var input_dir: Vector3 = _get_input_direction()
	var was_on_floor: bool = is_on_floor()
	var handled_slide: bool = false

	if not Input.is_action_pressed("Jump"):
		_mantle_requires_jump_release = false

	if _is_mantling:
		_update_mantle(delta)
		_update_animation(true, Vector3.ZERO, delta)
		_advance_animation(delta)
		return

	if _try_start_mantle(input_dir, was_on_floor):
		_update_mantle(delta)
		_advance_animation(delta)
		return

	_update_sword_slash(delta)

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

	if not handled_slide and not (_is_committed_jump and not on_floor):
		_update_orientation(input_dir, delta)
	_update_animation(on_floor, input_dir, delta)
	_advance_animation(delta)

	_was_on_floor = on_floor


func _update_sword_slash(delta: float) -> void:
	if _is_sword_slashing:
		_sword_slash_time_remaining = maxf(
			_sword_slash_time_remaining - delta,
			0.0
		)
		if _sword_slash_time_remaining <= 0.0:
			_finish_sword_slash()
		return

	if (
		not _is_mantling
		and not _is_sliding
		and Input.is_action_just_pressed("Sword_Slash")
	):
		_start_sword_slash()


func _start_sword_slash() -> void:
	var animation: Animation = _anim_player.get_animation(SWORD_SLASH_ANIMATION)
	if animation == null:
		push_warning("Missing sword slash animation: %s" % SWORD_SLASH_ANIMATION)
		_finish_sword_slash()
		return

	_is_sword_slashing = true
	_sword_slash_duration = animation.length / sword_slash_speed
	_sword_slash_time_remaining = _sword_slash_duration
	_sword_slash_animation_node.animation = SWORD_SLASH_ANIMATION
	_anim_tree.set(
		"parameters/Sword_Slash_OneShot/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)

func _finish_sword_slash() -> void:
	_is_sword_slashing = false
	_sword_slash_time_remaining = 0.0


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


func _try_start_mantle(input_dir: Vector3, on_floor: bool) -> bool:
	var can_air_mantle: bool = (
		not on_floor
		and _is_committed_jump
		and _jump_started_running
	)
	if (
		(not on_floor and not can_air_mantle)
		or (input_dir == Vector3.ZERO and not can_air_mantle)
		or not Input.is_action_pressed("Jump")
		or _mantle_requires_jump_release
	):
		return false

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var feet_position: Vector3 = global_position
	var forward: Vector3 = (
		input_dir.normalized()
		if input_dir != Vector3.ZERO
		else _jump_horizontal_direction
	)
	var exclusions: Array[RID] = [get_rid()]
	var wall_probe_height: float = 0.5 if can_air_mantle else 1.2

	var wall_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		feet_position + Vector3.UP * wall_probe_height,
		feet_position + Vector3.UP * wall_probe_height + forward * mantle_reach,
		collision_mask,
		exclusions
	)
	var wall_hit: Dictionary = space_state.intersect_ray(wall_query)
	if wall_hit.is_empty():
		return false

	var wall_normal: Vector3 = wall_hit["normal"]
	if absf(wall_normal.dot(Vector3.UP)) > 0.2:
		return false

	var wall_point: Vector3 = wall_hit["position"]
	var clearance_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		feet_position + Vector3.UP * (mantle_max_height + 0.2),
		feet_position + Vector3.UP * (mantle_max_height + 0.2) + forward * (mantle_reach + 0.5),
		collision_mask,
		exclusions
	)
	if not space_state.intersect_ray(clearance_query).is_empty():
		return false

	var down_start: Vector3 = Vector3(
		wall_point.x + forward.x * 0.7,
		feet_position.y + mantle_max_height + 0.5,
		wall_point.z + forward.z * 0.7
	)
	var down_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		down_start,
		down_start + Vector3.DOWN * (mantle_max_height + 1.0),
		collision_mask,
		exclusions
	)
	var top_hit: Dictionary = space_state.intersect_ray(down_query)
	if top_hit.is_empty():
		return false

	var top_normal: Vector3 = top_hit["normal"]
	var top_position: Vector3 = top_hit["position"]
	var ledge_height: float = top_position.y - feet_position.y
	var minimum_height: float = (
		airborne_mantle_min_height if can_air_mantle else mantle_min_height
	)
	if (
		top_normal.dot(Vector3.UP) < 0.85
		or ledge_height < minimum_height
		or ledge_height > mantle_max_height
	):
		return false

	_start_mantle(wall_point, top_position, forward)
	return true


func _start_mantle(
	wall_position: Vector3,
	top_position: Vector3,
	forward: Vector3
) -> void:
	_is_mantling = true
	_mantle_requires_jump_release = true
	_mantle_elapsed = 0.0
	_mantle_start_position = global_position
	_mantle_target_position = Vector3(
		wall_position.x + forward.x * 0.9,
		top_position.y + 0.05,
		wall_position.z + forward.z * 0.9
	)
	_mantle_control_position = Vector3(
		_mantle_start_position.x,
		_mantle_target_position.y,
		_mantle_start_position.z
	)
	velocity = Vector3.ZERO
	_is_committed_jump = false
	_jump_started_running = false
	_has_been_airborne = false
	_run_buildup = 0.0
	_is_landing = false
	_is_sliding = false

	var mantle_animation: Animation = _anim_player.get_animation("Mantle")
	var source_duration: float = mantle_animation.length if mantle_animation != null else 0.7
	_mantle_duration = source_duration * mantle_duration_scale
	_mantle_animation_speed = source_duration / maxf(_mantle_duration, 0.01)
	_anim_state.travel("Mantle")


func _update_mantle(delta: float) -> void:
	_mantle_elapsed = minf(_mantle_elapsed + delta, _mantle_duration)
	var progress: float = _mantle_elapsed / maxf(_mantle_duration, 0.01)
	var vertical_phase_end: float = 0.7
	if progress < vertical_phase_end:
		var vertical_progress: float = smoothstep(
			0.0,
			1.0,
			progress / vertical_phase_end
		)
		global_position = _mantle_start_position.lerp(
			_mantle_control_position,
			vertical_progress
		)
	else:
		var forward_progress: float = smoothstep(
			0.0,
			1.0,
			(progress - vertical_phase_end) / (1.0 - vertical_phase_end)
		)
		global_position = _mantle_control_position.lerp(
			_mantle_target_position,
			forward_progress
		)

	if progress < 1.0:
		return

	_is_mantling = false
	velocity = Vector3.ZERO
	_anim_state.travel("idle")


func _apply_horizontal_movement(input_dir: Vector3, on_floor: bool, delta: float) -> void:
	if _is_committed_jump and not on_floor:
		var opposing_input: float = maxf(
			-_jump_horizontal_direction.dot(input_dir),
			0.0
		)
		if opposing_input > 0.0:
			var minimum_jump_speed: float = (
				_jump_initial_horizontal_speed * minimum_jump_speed_ratio
			)
			_jump_horizontal_speed = move_toward(
				_jump_horizontal_speed,
				minimum_jump_speed,
				jump_brake_deceleration * opposing_input * delta
			)
		velocity.x = _jump_horizontal_direction.x * _jump_horizontal_speed
		velocity.z = _jump_horizontal_direction.z * _jump_horizontal_speed
		return

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
		if Input.is_action_pressed("Run") and _is_cardinal_drift_input(input_dir):
			var facing_right := Vector3(
				_cardinal_facing.z,
				0.0,
				-_cardinal_facing.x
			)
			var lateral_amount: float = input_dir.dot(facing_right)
			target_velocity = (
				_cardinal_facing * target_speed
				+ facing_right * lateral_amount * target_speed * running_drift_strength
			)
		else:
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


func _start_slide(exit_direction: Vector3, forced_distance: float = 0.0) -> void:
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	_is_sliding = true
	_slide_direction = horizontal_velocity.normalized()
	_slide_exit_direction = exit_direction
	_slide_start_speed = horizontal_velocity.length()
	var exit_speed: float = walk_speed if exit_direction != Vector3.ZERO else 0.0
	if forced_distance > 0.0:
		_slide_duration = 2.0 * forced_distance / maxf(_slide_start_speed + exit_speed, 0.01)
	else:
		_slide_duration = _turn_animation_duration * turn_duration_scale
	_slide_time_remaining = _slide_duration
	_slide_animation_speed = _turn_animation_duration / maxf(_slide_duration, 0.01)
	_slide_reversal_grace_remaining = 0.0
	_slide_start_angle = _character.rotation.y
	_run_buildup = 0.0
	_anim_state.travel("Turn")


func _update_slide(delta: float) -> void:
	_slide_time_remaining = max(_slide_time_remaining - delta, 0.0)
	var progress: float = 1.0 - _slide_time_remaining / _slide_duration
	var exit_speed: float = walk_speed if _slide_exit_direction != Vector3.ZERO else 0.0
	var braking_weight: float = 1.0 - pow(1.0 - progress, 3.0)
	var slide_speed: float = lerpf(_slide_start_speed, exit_speed, braking_weight)
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
			var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
			_jump_started_running = (
				Input.is_action_pressed("Run")
				and _run_buildup >= 0.5
				and horizontal_velocity.length() > walk_speed
			)
			_is_committed_jump = horizontal_velocity.length() > 0.1
			if _is_committed_jump:
				_jump_horizontal_direction = horizontal_velocity.normalized()
				var jump_distance: float = (
					running_jump_distance
					if _jump_started_running
					else walking_jump_distance
				)
				_jump_horizontal_speed = jump_distance / _get_jump_flight_time()
				_jump_initial_horizontal_speed = _jump_horizontal_speed
			velocity.y = _jump_velocity
			return

	var gravity_multiplier: float = jump_fall_gravity_multiplier
	if velocity.y > 0.0:
		gravity_multiplier = jump_rise_gravity_multiplier
		if not _is_committed_jump and not Input.is_action_pressed("Jump"):
			gravity_multiplier = jump_release_gravity_multiplier

	velocity.y -= _gravity * gravity_multiplier * delta
	if velocity.y < -max_fall_speed:
		velocity.y = -max_fall_speed

	if not on_floor:
		_time_in_air += delta


func _update_orientation(input_dir: Vector3, _delta: float) -> void:
	if input_dir == Vector3.ZERO:
		return

	var facing_right := Vector3(
		_cardinal_facing.z,
		0.0,
		-_cardinal_facing.x
	)
	var forward_amount: float = input_dir.dot(_cardinal_facing)
	var lateral_amount: float = input_dir.dot(facing_right)

	if forward_amount <= -cardinal_turn_threshold:
		_cardinal_facing = -_cardinal_facing
	elif absf(lateral_amount) >= cardinal_turn_threshold:
		_cardinal_facing = facing_right * signf(lateral_amount)
	elif forward_amount <= 0.0 and absf(lateral_amount) > 0.25:
		_cardinal_facing = facing_right * signf(lateral_amount)

	_character.rotation.y = atan2(_cardinal_facing.x, _cardinal_facing.z)


func _is_cardinal_drift_input(input_dir: Vector3) -> bool:
	var facing_right := Vector3(
		_cardinal_facing.z,
		0.0,
		-_cardinal_facing.x
	)
	var forward_amount: float = input_dir.dot(_cardinal_facing)
	var lateral_amount: float = absf(input_dir.dot(facing_right))
	return forward_amount > 0.0 and lateral_amount < cardinal_turn_threshold


func _update_animation(on_floor: bool, input_dir: Vector3, delta: float) -> void:
	var horizontal_speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
	var is_running: bool = Input.is_action_pressed("Run") and _run_buildup >= 0.5
	var current: StringName = _anim_state.get_current_node()

	if _is_mantling:
		if current != "Mantle":
			_anim_state.travel("Mantle")
		return

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
		_is_committed_jump = false
		_jump_started_running = false
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
		playback_speed = _slide_animation_speed
	elif _is_mantling or _anim_state.get_current_node() == "Mantle":
		playback_speed = _mantle_animation_speed
	elif _is_landing or _anim_state.get_current_node() == "Land":
		playback_speed = landing_animation_speed
	elif _anim_state.get_current_node() == "jump":
		playback_speed = jump_animation_speed
	elif _anim_state.get_current_node() == "Fall":
		playback_speed = fall_animation_speed
	elif _anim_state.get_current_node() == "run":
		playback_speed = run_animation_speed
	elif _anim_state.get_current_node() == "walk":
		playback_speed = walk_animation_speed
	_anim_tree.advance(delta * playback_speed)


func _get_jump_flight_time() -> float:
	var rise_gravity: float = _gravity * jump_rise_gravity_multiplier
	var fall_gravity: float = _gravity * jump_fall_gravity_multiplier
	var rise_time: float = _jump_velocity / rise_gravity
	var fall_time: float = sqrt(2.0 * jump_height / fall_gravity)
	return rise_time + fall_time
