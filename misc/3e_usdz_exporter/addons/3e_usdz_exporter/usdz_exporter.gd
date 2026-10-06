@tool
extends RefCounted

const UsdaWriter := preload("res://addons/3e_usdz_exporter/usda_writer.gd")
const UsdzArchive := preload("res://addons/3e_usdz_exporter/usdz_archive.gd")


static func build_scene_package(scene_root: Node) -> PackedByteArray:
	if scene_root == null:
		return PackedByteArray()

	var writer := UsdaWriter.new()
	var usda_text := writer.write_scene(scene_root)
	if usda_text.is_empty():
		return PackedByteArray()

	var archive := UsdzArchive.new()
	return archive.build([
		{
			"name": "scene.usda",
			"data": usda_text.to_utf8_buffer(),
		}
	])
