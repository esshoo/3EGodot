@tool
extends RefCounted

# Minimal USDZ package writer.
# USDZ requires a zero-compression ZIP archive whose file data starts at
# 64-byte-aligned offsets. Standard ZIP packers generally do not guarantee
# that alignment, so this writer emits the small ZIP subset we need directly.

const LOCAL_FILE_HEADER := 0x04034B50
const CENTRAL_DIRECTORY_HEADER := 0x02014B50
const END_OF_CENTRAL_DIRECTORY := 0x06054B50
const STORE_METHOD := 0
const ZIP_VERSION := 20
const USDZ_ALIGNMENT := 64
const ALIGNMENT_EXTRA_FIELD_ID := 0x1986


func build(entries: Array) -> PackedByteArray:
	if entries.is_empty() or entries.size() > 65535:
		return PackedByteArray()

	var output := PackedByteArray()
	var central_entries: Array[Dictionary] = []

	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("name") or not entry.has("data"):
			return PackedByteArray()
		if typeof(entry["data"]) != TYPE_PACKED_BYTE_ARRAY:
			return PackedByteArray()

		var name := String(entry["name"])
		var data: PackedByteArray = entry["data"]
		if name.is_empty() or data.size() > 0xFFFFFFFF:
			return PackedByteArray()

		var name_bytes := name.to_utf8_buffer()
		if name_bytes.size() > 65535:
			return PackedByteArray()

		var local_offset := output.size()
		var crc := _crc32(data)
		var extra := _alignment_extra(local_offset, name_bytes.size())

		_append_u32(output, LOCAL_FILE_HEADER)
		_append_u16(output, ZIP_VERSION)
		_append_u16(output, 0) # General-purpose flags.
		_append_u16(output, STORE_METHOD)
		_append_u16(output, 0) # DOS time.
		_append_u16(output, 0) # DOS date.
		_append_u32(output, crc)
		_append_u32(output, data.size())
		_append_u32(output, data.size())
		_append_u16(output, name_bytes.size())
		_append_u16(output, extra.size())
		output.append_array(name_bytes)
		output.append_array(extra)

		# The defining USDZ layout rule.
		if output.size() % USDZ_ALIGNMENT != 0:
			push_error("3E USDZ Exporter: Internal USDZ alignment error.")
			return PackedByteArray()

		output.append_array(data)
		central_entries.append({
			"name": name_bytes,
			"crc": crc,
			"size": data.size(),
			"offset": local_offset,
		})

	var central_offset := output.size()
	for record in central_entries:
		var name_bytes: PackedByteArray = record["name"]
		_append_u32(output, CENTRAL_DIRECTORY_HEADER)
		_append_u16(output, ZIP_VERSION) # Version made by.
		_append_u16(output, ZIP_VERSION) # Version needed.
		_append_u16(output, 0)
		_append_u16(output, STORE_METHOD)
		_append_u16(output, 0)
		_append_u16(output, 0)
		_append_u32(output, int(record["crc"]))
		_append_u32(output, int(record["size"]))
		_append_u32(output, int(record["size"]))
		_append_u16(output, name_bytes.size())
		_append_u16(output, 0) # Central extra length.
		_append_u16(output, 0) # Comment length.
		_append_u16(output, 0) # Disk start.
		_append_u16(output, 0) # Internal attributes.
		_append_u32(output, 0) # External attributes.
		_append_u32(output, int(record["offset"]))
		output.append_array(name_bytes)

	var central_size := output.size() - central_offset
	_append_u32(output, END_OF_CENTRAL_DIRECTORY)
	_append_u16(output, 0)
	_append_u16(output, 0)
	_append_u16(output, central_entries.size())
	_append_u16(output, central_entries.size())
	_append_u32(output, central_size)
	_append_u32(output, central_offset)
	_append_u16(output, 0)

	return output


func _alignment_extra(local_offset: int, name_length: int) -> PackedByteArray:
	# Local file header is 30 bytes before name and extra fields.
	var base_data_offset := local_offset + 30 + name_length
	var padding := (USDZ_ALIGNMENT - (base_data_offset % USDZ_ALIGNMENT)) % USDZ_ALIGNMENT

	# ZIP extra fields have a 4-byte ID/length header. If the exact padding is
	# 1..3 bytes, add one full alignment block so the field remains well-formed.
	if padding > 0 and padding < 4:
		padding += USDZ_ALIGNMENT

	var extra := PackedByteArray()
	if padding == 0:
		return extra

	_append_u16(extra, ALIGNMENT_EXTRA_FIELD_ID)
	_append_u16(extra, padding - 4)
	for _index in range(padding - 4):
		extra.append(0)
	return extra


func _crc32(data: PackedByteArray) -> int:
	var crc: int = 0xFFFFFFFF
	for byte in data:
		crc = (crc ^ byte) & 0xFFFFFFFF
		for _bit in 8:
			if crc & 1:
				crc = ((crc >> 1) ^ 0xEDB88320) & 0xFFFFFFFF
			else:
				crc = (crc >> 1) & 0xFFFFFFFF
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF


func _append_u16(buffer: PackedByteArray, value: int) -> void:
	buffer.append(value & 0xFF)
	buffer.append((value >> 8) & 0xFF)


func _append_u32(buffer: PackedByteArray, value: int) -> void:
	buffer.append(value & 0xFF)
	buffer.append((value >> 8) & 0xFF)
	buffer.append((value >> 16) & 0xFF)
	buffer.append((value >> 24) & 0xFF)
