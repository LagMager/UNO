extends SkeletonModifier3D

## Small nervous tics on top of the rival's animation: a slow wander of the head
## plus, every few seconds, a short sudden jerk that is held and then let go.
## As a SkeletonModifier3D its changes are applied after the animation each frame
## and never accumulate into the stored pose.

var _time := 0.0
var _tic := Vector3.ZERO
var _vel := Vector3.ZERO
var _target := Vector3.ZERO
var _wait := 3.0
var _hold := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_time += delta
	_wait -= delta
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			_target = Vector3.ZERO
	elif _wait <= 0.0:
		_wait = _rng.randf_range(3.0, 8.0)
		_hold = _rng.randf_range(0.5, 1.4)
		_target = Vector3(_rng.randf_range(-0.07, 0.05), _rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.12, 0.12))
	# critically damped spring: the jerk is quick but never snaps, the release is slow
	var stiffness := 40.0 if _hold > 0.0 else 5.0
	var damping := 2.0 * sqrt(stiffness)
	_vel += (stiffness * (_target - _tic) - damping * _vel) * delta
	_tic += _vel * delta
	var wander := Vector3(sin(_time * 0.37) * 0.015, sin(_time * 0.23 + 1.0) * 0.025, sin(_time * 0.29 + 2.0) * 0.02)
	var t := _tic + wander
	for pair: Array in [["head", 0.6], ["neck", 0.4]]:
		var i := sk.find_bone(pair[0])
		if i >= 0:
			sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * Quaternion.from_euler(t * float(pair[1])))
