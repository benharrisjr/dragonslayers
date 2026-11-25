class_name Gem
extends RefCounted

## The money lying about the world: a gem, cut to its value. Each has its own shape as well as its
## own colour, so they can be told apart at a glance, spinning on the ground:
##   1  green  -- an emerald: a six-sided crystal, pointed at both ends
##   2  red    -- a ruby: a squat four-sided double point
##   5  blue   -- a sapphire: a square cut, flat table on top
##   10 purple -- amethyst: a cluster of three crystal points
##   25 white  -- a diamond: a round brilliant, clear and glinting
## All built from code, as the coin before them was.

## Each gem's worth, largest first.
const VALUES: Array[int] = [25, 10, 5, 2, 1]
const COLORS := {
	1: Color(0.25, 0.85, 0.35),
	2: Color(0.92, 0.18, 0.22),
	5: Color(0.22, 0.42, 0.98),
	10: Color(0.62, 0.3, 0.92),
	25: Color(0.92, 0.97, 1.0),
}
## Never more than this many gems from one drop: a big purse comes out as big gems.
const MOST := 6


## The gems a purse of `gold` is paid in: the largest that fit, then smaller -- a few of them,
## at least one.
static func split(gold: int) -> Array[int]:
	var out: Array[int] = []
	var left := maxi(gold, 1)
	for value in VALUES:
		while left >= value and out.size() < MOST:
			out.append(value)
			left -= value
	if out.is_empty():
		out.append(1)
	return out


## The gem a pickup worth `amount` is shown as: the largest that does not overstate it.
static func value_for(amount: int) -> int:
	for value in VALUES:
		if amount >= value:
			return value
	return 1


static func build(amount: int) -> Node3D:
	var value := value_for(amount)
	var color: Color = COLORS[value]
	var mesh: ArrayMesh
	match value:
		1:
			mesh = _lathe(6, [Vector2(0.0, -0.36), Vector2(0.15, -0.2), Vector2(0.15, 0.2), Vector2(0.0, 0.36)])
		2:
			mesh = _lathe(4, [Vector2(0.0, -0.3), Vector2(0.27, 0.0), Vector2(0.0, 0.3)])
		5:
			mesh = _lathe(4, [Vector2(0.0, -0.28), Vector2(0.27, 0.06), Vector2(0.19, 0.2), Vector2(0.0, 0.2)])
		10:
			mesh = _cluster()
		_:
			mesh = _lathe(8, [Vector2(0.0, -0.32), Vector2(0.34, 0.04), Vector2(0.22, 0.19), Vector2(0.0, 0.19)])
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.15
	material.metallic = 0.15
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.55
	if value == 25:
		## Clear, bright and glinting: see-through, mirror-smooth, lit at its edges.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(color, 0.5)
		material.metallic = 0.6
		material.roughness = 0.02
		material.metallic_specular = 1.0
		material.rim_enabled = true
		material.rim = 1.0
		material.rim_tint = 0.2
		material.emission_energy_multiplier = 0.9
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance := MeshInstance3D.new()
	instance.name = "Gem"
	instance.scale = Vector3.ONE * 1.35
	instance.mesh = mesh
	instance.material_override = material
	return instance


## A faceted solid of revolution: `sides` faces round, through the profile's (radius, height)
## points from bottom to top, flat shaded so every facet catches the light on its own.
static func _lathe(sides: int, profile: Array, offset: Transform3D = Transform3D.IDENTITY,
		surface: SurfaceTool = null) -> ArrayMesh:
	var own := surface == null
	if own:
		surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_smooth_group(-1)
	var rings: Array = []
	for point: Vector2 in profile:
		var ring: Array[Vector3] = []
		for i in sides:
			var angle := TAU * i / sides + PI / sides
			ring.append(offset * Vector3(cos(angle) * point.x, point.y, sin(angle) * point.x))
		rings.append(ring)
	for r in rings.size() - 1:
		var low: Array = rings[r]
		var high: Array = rings[r + 1]
		for i in sides:
			var j := (i + 1) % sides
			if (profile[r] as Vector2).x > 0.0001:
				surface.add_vertex(low[i])
				surface.add_vertex(high[i])
				surface.add_vertex(low[j])
			if (profile[r + 1] as Vector2).x > 0.0001:
				surface.add_vertex(low[j])
				surface.add_vertex(high[i])
				surface.add_vertex(high[j])
	if not own:
		return null
	surface.generate_normals()
	return surface.commit()


## Amethyst: three six-sided points standing out of one base at different heights and leans.
static func _cluster() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var crystal := [Vector2(0.0, -0.05), Vector2(0.1, 0.0), Vector2(0.1, 0.3), Vector2(0.0, 0.46)]
	for lean: Vector3 in [Vector3(0.0, 0.0, 0.0), Vector3(0.45, 0.0, 0.2), Vector3(-0.35, 0.0, -0.4)]:
		var basis := Basis.from_euler(Vector3(lean.x, 0.0, lean.z))
		var scale := 1.0 if lean == Vector3.ZERO else 0.72
		var shift := Vector3(lean.z, -0.25, -lean.x) * 0.3
		_lathe(6, crystal, Transform3D(basis.scaled(Vector3.ONE * scale), shift + Vector3.DOWN * 0.05), surface)
	surface.generate_normals()
	return surface.commit()
