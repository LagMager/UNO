extends SkeletonModifier3D

## The shopkeeper's live layer, on top of his baked clips (bunny.glb):
## - ears: they hang a beat behind the head (a bouncy spring driven by how fast the head
##   turns), take the mood the shop gives them (perked when you look at the goods, pinned
##   back when you can't pay) and flick on their own now and then;
## - eyes: blinks (sometimes double); the clip's own lid poses (squint, wide) are kept;
## - head: turns a little toward what the player is looking at.
## As a SkeletonModifier3D its changes never accumulate into the animated pose.

## Where the head should look (global position); `look_weight` 0..1.
var look_target := Vector3.ZERO
var look_weight := 0.0
## Ear mood, both in degrees: + back = pinned back, - = pricked forward; + out = splayed.
var ear_back := 0.0
var ear_out := 0.0

const EAR_SPLIT := [0.4, 0.3, 0.2, 0.1]
const TIP_SPLIT := [0.0, 0.2, 0.35, 0.45]
const EAR_SWING := [0.15, 0.25, 0.3, 0.3]   # how much of the spring each bone takes (tip moves most)

var _rng := RandomNumberGenerator.new()
var _bones := {}
var _last_head := Basis.IDENTITY
var _has_last := false
# per ear: spring angle (skeleton-space rotation vector, radians) and its velocity
var _swing := {"L": Vector3.ZERO, "R": Vector3.ZERO}
var _swing_v := {"L": Vector3.ZERO, "R": Vector3.ZERO}
var _mood := Vector2.ZERO          # smoothed (back, out)
var _flick_wait := 3.0
var _blink := 0.0
var _blink_t := -1.0
var _blink_wait := 2.0
var _double := false
var _look := Vector2.ZERO          # smoothed (yaw, pitch)


func _ready() -> void:
	_rng.randomize()


func _bone(n: String) -> int:
	if not _bones.has(n):
		_bones[n] = get_skeleton().find_bone(n)
	return _bones[n]


## A rotation about an axis of the skeleton's space, written in the bone's own (rest) frame.
func _about(sk: Skeleton3D, i: int, axis: Vector3, angle: float) -> Quaternion:
	var r := sk.get_bone_global_rest(i).basis.get_rotation_quaternion()
	return r.inverse() * Quaternion(axis.normalized(), angle) * r


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or delta <= 0.0:
		return
	delta = minf(delta, 0.05)
	_update_look(sk, delta)
	_update_ears(sk, delta)
	_update_blink(sk, delta)


func _update_look(sk: Skeleton3D, delta: float) -> void:
	var head := _bone("head")
	var neck := _bone("neck")
	if head < 0 or neck < 0:
		return
	var want := Vector2.ZERO
	if look_weight > 0.0:
		var from := sk.global_transform * sk.get_bone_global_pose(head).origin
		var local := sk.global_transform.affine_inverse().basis * (look_target - from)
		# he faces +Z in his skeleton
		var yaw := atan2(local.x, local.z)
		var pitch := atan2(-local.y, Vector2(local.x, local.z).length())
		want = Vector2(clampf(yaw, -0.35, 0.35), clampf(pitch, -0.2, 0.25)) * look_weight
	_look = _look.lerp(want, 1.0 - exp(-delta * 3.0))
	for pair: Array in [[neck, 0.4], [head, 0.6]]:
		var i: int = pair[0]
		var k: float = pair[1]
		var q := _about(sk, i, Vector3.UP, _look.x * k) * _about(sk, i, Vector3.RIGHT, _look.y * k)
		sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * q)


func _update_ears(sk: Skeleton3D, delta: float) -> void:
	var head := _bone("head")
	if head < 0:
		return
	# how fast the head turned this frame (skeleton space): the ears trail behind it
	var hb := sk.get_bone_global_pose(head).basis.orthonormalized()
	var omega := Vector3.ZERO
	if _has_last:
		var dq := (hb * _last_head.inverse()).get_rotation_quaternion()
		var ang := dq.get_angle()
		if ang > 0.0001 and ang < 1.0:
			omega = dq.get_axis() * ang / delta
	_last_head = hb
	_has_last = true
	_mood = _mood.lerp(Vector2(ear_back, ear_out), 1.0 - exp(-delta * 6.0))
	# now and then one ear flicks on its own (a rabbit listening to the room)
	_flick_wait -= delta
	if _flick_wait <= 0.0:
		_flick_wait = _rng.randf_range(2.5, 7.0)
		var side: String = ["L", "R"][_rng.randi() % 2]
		_swing_v[side] += Vector3(_rng.randf_range(-1.0, 1.0) * 5.0, _rng.randf_range(-1.0, 1.0) * 6.0, _rng.randf_range(-1.0, 1.0) * 3.0)
	for side: String in ["L", "R"]:
		var sg := 1.0 if side == "L" else -1.0
		# soft and bouncy: the long ears overshoot and wobble back
		var target: Vector3 = -omega * 0.09
		var v: Vector3 = _swing_v[side]
		var x: Vector3 = _swing[side]
		v += (60.0 * (target - x) - 4.5 * v) * delta
		x += v * delta
		x = x.limit_length(0.6)
		_swing[side] = x
		_swing_v[side] = v
		# his left ear is folded: "alert" (back < 0) lifts and unfolds it instead of drooping it
		var back := _mood.x
		var tip := 0.0
		if side == "L" and back < 0.0:
			tip = back * 0.8
			back = -back * 0.7
		for k: int in range(4):
			var i := _bone("ear%d.%s" % [k + 1, side])
			if i < 0:
				continue
			var q := _about(sk, i, Vector3.RIGHT, deg_to_rad(-back * EAR_SPLIT[k] + tip * TIP_SPLIT[k]))
			q = q * _about(sk, i, Vector3(0, 0, -sg), deg_to_rad(_mood.y * EAR_SPLIT[k]))
			var amount: float = x.length() * EAR_SWING[k]
			if amount > 0.0001:
				q = q * _about(sk, i, x, amount)
			sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * q)


func _update_blink(sk: Skeleton3D, delta: float) -> void:
	_blink_wait -= delta
	if _blink_t < 0.0 and _blink_wait <= 0.0:
		_blink_t = 0.0
		_double = _rng.randf() < 0.25
		_blink_wait = _rng.randf_range(2.2, 6.0)
	if _blink_t >= 0.0:
		_blink_t += delta
		var length := 0.17
		var u := _blink_t / length
		if _double and u >= 1.0 and u < 2.2:
			u = u - 1.2 if u >= 1.2 else 1.0
		_blink = sin(clampf(u, 0.0, 1.0) * PI)
		if _blink_t > length * (2.4 if _double else 1.0):
			_blink_t = -1.0
			_blink = 0.0
	if _blink <= 0.001:
		return
	for side: String in ["L", "R"]:
		var up := _bone("lid_up." + side)
		var lo := _bone("lid_lo." + side)
		if up >= 0:
			var q := sk.get_bone_pose_rotation(up)
			# how open the clip has it (rotation about the lid's own X), closed by the blink
			var open := (sk.get_bone_rest(up).basis.get_rotation_quaternion().inverse() * q).get_euler().x
			if open > 0.0:
				sk.set_bone_pose_rotation(up, q * Quaternion(Vector3.RIGHT, -open * _blink))
		if lo >= 0:
			var q2 := sk.get_bone_pose_rotation(lo)
			var open2 := (sk.get_bone_rest(lo).basis.get_rotation_quaternion().inverse() * q2).get_euler().x
			if open2 < 0.0:
				sk.set_bone_pose_rotation(lo, q2 * Quaternion(Vector3.RIGHT, -open2 * _blink * 0.35))
