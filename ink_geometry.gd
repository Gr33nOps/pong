extends RefCounted
## Shared deterministic geometry for imperfect, hand-drawn UI outlines.


static func rough_rect(control_size: Vector2, inset: float, wobble: float, variant := 0) -> PackedVector2Array:
	var left := inset
	var top := inset
	var right := control_size.x - inset
	var bottom := control_size.y - inset
	var flip := -1.0 if variant % 2 else 1.0
	return PackedVector2Array([
		Vector2(left - wobble * 0.25, top + wobble * 0.35 * flip),
		Vector2(lerpf(left, right, 0.18), top - wobble * 0.55 * flip),
		Vector2(lerpf(left, right, 0.43), top + wobble * 0.25 * flip),
		Vector2(lerpf(left, right, 0.69), top - wobble * 0.35 * flip),
		Vector2(right + wobble * 0.2, top + wobble * 0.45 * flip),
		Vector2(right - wobble * 0.3 * flip, lerpf(top, bottom, 0.31)),
		Vector2(right + wobble * 0.35 * flip, lerpf(top, bottom, 0.66)),
		Vector2(right - wobble * 0.2, bottom + wobble * 0.25 * flip),
		Vector2(lerpf(left, right, 0.76), bottom - wobble * 0.5 * flip),
		Vector2(lerpf(left, right, 0.49), bottom + wobble * 0.35 * flip),
		Vector2(lerpf(left, right, 0.23), bottom - wobble * 0.3 * flip),
		Vector2(left - wobble * 0.15, bottom + wobble * 0.4 * flip),
		Vector2(left + wobble * 0.35 * flip, lerpf(top, bottom, 0.72)),
		Vector2(left - wobble * 0.3 * flip, lerpf(top, bottom, 0.38)),
		Vector2(left - wobble * 0.25, top + wobble * 0.35 * flip),
	])


static func top_scratch(control_size: Vector2, inset: float, wobble: float, variant := 0) -> PackedVector2Array:
	var flip := -1.0 if variant % 2 else 1.0
	return PackedVector2Array([
		Vector2(inset + 7.0, inset + wobble * 0.55 * flip),
		Vector2(control_size.x * 0.27, inset - wobble * 0.35 * flip),
		Vector2(control_size.x * 0.56, inset + wobble * 0.25 * flip),
		Vector2(control_size.x - inset - 10.0, inset - wobble * 0.2 * flip),
	])

