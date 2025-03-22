# Create a new script: RegionManager.gd
class_name RegionManager
extends Node

var regions = {}
var active_regions = []
var region_size = 4  # Regions are 4x4 chunks

# Register a chunk with its region
func register_chunk(chunk_pos):
	var region_pos = Vector2(floor(chunk_pos.x / region_size), floor(chunk_pos.y / region_size))
	
	if not regions.has(region_pos):
		regions[region_pos] = []
	
	if not chunk_pos in regions[region_pos]:
		regions[region_pos].append(chunk_pos)
	
	if not region_pos in active_regions:
		active_regions.append(region_pos)

# Check if a region should be active based on position
func should_region_be_active(region_pos, current_positions, distance):
	for pos in current_positions:
		var pos_region = Vector2(floor(pos.x / region_size), floor(pos.y / region_size))
		if (pos_region - region_pos).length() <= distance:
			return true
	return false

# Get all chunks in active regions
func get_active_chunks(current_positions, distance):
	var active_chunks = []
	var regions_to_remove = []
	
	for region_pos in active_regions:
		if should_region_be_active(region_pos, current_positions, distance):
			for chunk_pos in regions[region_pos]:
				active_chunks.append(chunk_pos)
		else:
			regions_to_remove.append(region_pos)
	
	# Remove inactive regions
	for region_pos in regions_to_remove:
		active_regions.erase(region_pos)
	
	return active_chunks
