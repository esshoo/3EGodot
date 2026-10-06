@tool
extends RefCounted


func write_scene(scene_root: Node) -> String:
	var lines := PackedStringArray()
	lines.append("#usda 1.0")
	lines.append("(")
	lines.append("    defaultPrim = \"Root\"")
	lines.append("    metersPerUnit = 1")
	lines.append("    upAxis = \"Y\"")
	lines.append(")")
	lines.append("")
	lines.append("def Xform \"Root\"")
	lines.append("{")
	_write_node(scene_root, lines, 1)
	lines.append("}")
	return "\n".join(lines) + "\n"


func _write_node(node: Node, lines: PackedStringArray, depth: int) -> void:
	if node is Node3D:
		var node_3d := node as Node3D
		var name := _usd_identifier(node.name)
		_append_line(lines, depth, "def Xform \"%s\"" % name)
		_append_line(lines, depth, "{")
		_write_transform(node_3d.transform, lines, depth + 1)

		if node is MeshInstance3D:
			_write_mesh((node as MeshInstance3D).mesh, lines, depth + 1)

		for child in node.get_children():
			_write_node(child, lines, depth + 1)

		_append_line(lines, depth, "}")
	else:
		# Non-3D helper nodes do not become USD prims, but their Node3D descendants do.
		for child in node.get_children():
			_write_node(child, lines, depth)


func _write_transform(transform: Transform3D, lines: PackedStringArray, depth: int) -> void:
	var b := transform.basis
	var o := transform.origin
	var matrix := "((%s, %s, %s, 0), (%s, %s, %s, 0), (%s, %s, %s, 0), (%s, %s, %s, 1))" % [
		_num(b.x.x), _num(b.x.y), _num(b.x.z),
		_num(b.y.x), _num(b.y.y), _num(b.y.z),
		_num(b.z.x), _num(b.z.y), _num(b.z.z),
		_num(o.x), _num(o.y), _num(o.z),
	]
	_append_line(lines, depth, "matrix4d xformOp:transform = %s" % matrix)
	_append_line(lines, depth, "uniform token[] xformOpOrder = [\"xformOp:transform\"]")


func _write_mesh(mesh: Mesh, lines: PackedStringArray, depth: int) -> void:
	if mesh == null:
		return

	for surface in mesh.get_surface_count():
		# surface_get_primitive_type() is public on ArrayMesh, but not on the
		# Mesh base class/PrimitiveMesh in Godot 4.7. PrimitiveMesh surfaces
		# such as BoxMesh are triangle-based and can still be exported through
		# Mesh.surface_get_arrays(). PointMesh is explicitly non-triangular.
		if mesh is ArrayMesh:
			var array_mesh := mesh as ArrayMesh
			if array_mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				push_warning("3E USDZ Exporter: Skipping non-triangle ArrayMesh surface %d." % surface)
				continue
		elif mesh is PointMesh:
			push_warning("3E USDZ Exporter: Skipping PointMesh surface %d." % surface)
			continue

		var arrays := mesh.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue

		var raw_vertices = arrays[Mesh.ARRAY_VERTEX]
		if typeof(raw_vertices) != TYPE_PACKED_VECTOR3_ARRAY:
			continue
		var vertices: PackedVector3Array = raw_vertices
		if vertices.is_empty():
			continue

		var raw_indices = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else null
		var indices := PackedInt32Array()
		if typeof(raw_indices) == TYPE_PACKED_INT32_ARRAY:
			indices = raw_indices

		var face_indices := _triangle_indices(vertices.size(), indices)
		if face_indices.is_empty():
			continue

		_append_line(lines, depth, "def Mesh \"Surface_%d\"" % surface)
		_append_line(lines, depth, "{")
		_append_line(lines, depth + 1, "uniform token subdivisionScheme = \"none\"")
		_append_line(lines, depth + 1, "point3f[] points = %s" % _vector3_array(vertices))
		_append_line(lines, depth + 1, "int[] faceVertexCounts = %s" % _triangle_counts(int(face_indices.size() / 3)))
		_append_line(lines, depth + 1, "int[] faceVertexIndices = %s" % _int_array(face_indices))

		var raw_normals = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL else null
		if typeof(raw_normals) == TYPE_PACKED_VECTOR3_ARRAY:
			var normals: PackedVector3Array = raw_normals
			if normals.size() == vertices.size():
				_append_line(lines, depth + 1, "normal3f[] normals = %s (" % _vector3_array(normals))
				_append_line(lines, depth + 2, "interpolation = \"vertex\"")
				_append_line(lines, depth + 1, ")")

		var raw_uvs = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV else null
		if typeof(raw_uvs) == TYPE_PACKED_VECTOR2_ARRAY:
			var uvs: PackedVector2Array = raw_uvs
			if uvs.size() == vertices.size():
				_append_line(lines, depth + 1, "texCoord2f[] primvars:st = %s (" % _vector2_array(uvs))
				_append_line(lines, depth + 2, "interpolation = \"vertex\"")
				_append_line(lines, depth + 1, ")")

		_append_line(lines, depth, "}")


func _triangle_indices(vertex_count: int, source_indices: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	if source_indices.is_empty():
		if vertex_count < 3 or vertex_count % 3 != 0:
			return result
		result.resize(vertex_count)
		for triangle in range(int(vertex_count / 3)):
			var base := triangle * 3
			# Godot triangle front faces use clockwise winding. USD's default
			# right-handed orientation expects the opposite winding, so swap 1/2.
			result[base] = base
			result[base + 1] = base + 2
			result[base + 2] = base + 1
		return result

	if source_indices.size() % 3 != 0:
		return result

	result.resize(source_indices.size())
	for triangle in range(int(source_indices.size() / 3)):
		var base := triangle * 3
		result[base] = source_indices[base]
		result[base + 1] = source_indices[base + 2]
		result[base + 2] = source_indices[base + 1]
	return result


func _triangle_counts(triangle_count: int) -> String:
	var values := PackedStringArray()
	values.resize(triangle_count)
	for index in triangle_count:
		values[index] = "3"
	return "[" + ", ".join(values) + "]"


func _int_array(values: PackedInt32Array) -> String:
	var text := PackedStringArray()
	text.resize(values.size())
	for index in values.size():
		text[index] = str(values[index])
	return "[" + ", ".join(text) + "]"


func _vector3_array(values: PackedVector3Array) -> String:
	var text := PackedStringArray()
	text.resize(values.size())
	for index in values.size():
		var value := values[index]
		text[index] = "(%s, %s, %s)" % [_num(value.x), _num(value.y), _num(value.z)]
	return "[" + ", ".join(text) + "]"


func _vector2_array(values: PackedVector2Array) -> String:
	var text := PackedStringArray()
	text.resize(values.size())
	for index in values.size():
		var value := values[index]
		text[index] = "(%s, %s)" % [_num(value.x), _num(value.y)]
	return "[" + ", ".join(text) + "]"


func _usd_identifier(value: String) -> String:
	var result := ""
	for index in value.length():
		var code := value.unicode_at(index)
		var valid := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95
		result += value.substr(index, 1) if valid else "_"
	if result.is_empty():
		result = "Node"
	var first := result.unicode_at(0)
	if first >= 48 and first <= 57:
		result = "_" + result
	return result


func _num(value: float) -> String:
	if is_zero_approx(value):
		return "0"
	return String.num(value, 9)


func _append_line(lines: PackedStringArray, depth: int, value: String) -> void:
	lines.append("    ".repeat(depth) + value)
