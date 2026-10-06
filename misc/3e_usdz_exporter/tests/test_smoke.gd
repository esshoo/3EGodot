extends SceneTree

const UsdaWriter := preload("res://addons/3e_usdz_exporter/usda_writer.gd")
const UsdzArchive := preload("res://addons/3e_usdz_exporter/usdz_archive.gd")


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "SmokeScene"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Box"
	mesh_instance.mesh = BoxMesh.new()
	root.add_child(mesh_instance)

	var writer := UsdaWriter.new()
	var usda := writer.write_scene(root)
	if not _require(usda.begins_with("#usda 1.0"), "USDA header is missing."):
		return
	if not _require(usda.contains("def Mesh \"Surface_0\""), "Mesh surface was not authored."):
		return

	var archive := UsdzArchive.new()
	var bytes := archive.build([{"name": "scene.usda", "data": usda.to_utf8_buffer()}])
	if not _require(bytes.size() > 64, "USDZ archive is unexpectedly small."):
		return
	if not _require(_u32(bytes, 0) == 0x04034B50, "ZIP local-file signature is invalid."):
		return

	var name_length := _u16(bytes, 26)
	var extra_length := _u16(bytes, 28)
	var data_offset := 30 + name_length + extra_length
	if not _require(data_offset % 64 == 0, "USDZ first payload is not 64-byte aligned."):
		return
	if not _require(bytes.slice(data_offset, data_offset + 5).get_string_from_utf8() == "#usda", "USDZ default layer is not the first payload."):
		return

	var output_path := "user://3e_usdz_smoke.usdz"
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if not _require(file != null, "Could not open smoke-test output path."):
		return
	file.store_buffer(bytes)
	file.close()

	print("3E USDZ smoke test PASS: %s (%d bytes)" % [ProjectSettings.globalize_path(output_path), bytes.size()])
	root.free()
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("3E USDZ smoke test FAIL: " + message)
	quit(1)
	return false


func _u16(data: PackedByteArray, offset: int) -> int:
	return data[offset] | (data[offset + 1] << 8)


func _u32(data: PackedByteArray, offset: int) -> int:
	return data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24)
