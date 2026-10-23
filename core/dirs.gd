class_name Dirs
## Cardinal facing helpers. North is row - 1, East is col + 1.

enum { NORTH, EAST, SOUTH, WEST }


static func left(d: int) -> int:
	return (d + 3) % 4


static func right(d: int) -> int:
	return (d + 1) % 4


static func opposite(d: int) -> int:
	return (d + 2) % 4


## Grid step for a facing as (d_col, d_row).
static func delta(d: int) -> Vector2i:
	match d:
		NORTH: return Vector2i(0, -1)
		EAST: return Vector2i(1, 0)
		SOUTH: return Vector2i(0, 1)
		_: return Vector2i(-1, 0)


static func from_delta(d_col: int, d_row: int) -> int:
	match Vector2i(d_col, d_row):
		Vector2i(0, -1): return NORTH
		Vector2i(1, 0): return EAST
		Vector2i(0, 1): return SOUTH
		Vector2i(-1, 0): return WEST
	push_error("Cells are not orthogonally adjacent (delta %d,%d)." % [d_col, d_row])
	return NORTH


static func parse(s: String) -> int:
	match s.strip_edges().to_lower():
		"north", "n": return NORTH
		"east", "e": return EAST
		"south", "s": return SOUTH
		"west", "w": return WEST
	push_error("Unknown direction '%s'." % s)
	return NORTH


static func name_of(d: int) -> String:
	return ["North", "East", "South", "West"][d]
