local hexutils = {}

-- useful reference for cubic grid math: https://www.redblobgames.com/grids/hexagons/
-- wesnoth is even-q

-- since mainline wesnoth.map.from_cubic is broken as of 1.19.13, reimplement it here
-- (c++ backend expects a cubic_location struct which isn't accessible to lua)
function hexutils.from_cubic(q, r, s)
	local x = q
	local y = r + trunc((q + (math.abs(q) % 2)) / 2)
	return({x, y})
end

hexutils.get_cubic = wesnoth.map.get_cubic

function hexutils.hex_to_cartesian_space(x, y)
	local q, r, s = table.unpack(hexutils.get_cubic({x, y}))
	local x_pixel = 1.5 * q / math.sqrt(3.0)
	local y_pixel = ((q / 2.0) + r)
	return x_pixel, y_pixel
end

function hexutils.find_angle_between_hexes(x1, y1, x2, y2)
	local x1_pixel, y1_pixel = hexutils.hex_to_cartesian_space(x1, y1)
	local x2_pixel, y2_pixel = hexutils.hex_to_cartesian_space(x2, y2)
	local theta = math.atan(math.abs(y2_pixel - y1_pixel) / math.abs(x2_pixel - x1_pixel))
	-- y2 reversed here to account for flipped Y axis
	if x1_pixel >= x2_pixel and y2_pixel <= y1_pixel then -- quadrant II
		theta = math.pi - theta
	elseif x1_pixel >= x2_pixel and y2_pixel > y1_pixel then -- quadrant III
		theta = math.pi + theta
	elseif x1_pixel < x2_pixel and y2_pixel > y1_pixel then -- quadrant IV
		theta = (math.pi * 2) - theta
	end
	return theta
end

-- find the distance between two hexes in a straight line between them
function hexutils.cartesian_distance_between_hexes(x1, y1, x2, y2)
	local x1_pixel, y1_pixel = hexutils.hex_to_cartesian_space(x1, y1)
	local x2_pixel, y2_pixel = hexutils.hex_to_cartesian_space(x2, y2)
	return math.sqrt(((x1_pixel - x2_pixel) ^ 2) + ((y1_pixel - y2_pixel) ^ 2))
end

function hexutils.calc_image_hex_offset(hex_x, hex_y, x, y)
	-- given a reference hex and an offset in pixels
	-- find the hex closest to the target and adjust the offset to be relative to that hex
	-- returns the new hex coordinates followed by the new pixel offset
	local hex_off_x = math.floor((x + 27) / 54)
	local k = 0
	if math.abs(hex_off_x) % 2 == 1 then
		if math.abs(hex_x) % 2 == 0 then
			k = 36
		else
			y = y - 36
		end
	end
	local hex_off_y = math.floor((y + 36) / 72)
	local new_x = x - hex_off_x * 54
	local new_y = y - (hex_off_y * 72) + k
	if new_y > 36 then
		new_y = new_y - 72
		hex_off_y = hex_off_y+1
	end

	return hex_x+hex_off_x, hex_y+hex_off_y, new_x, new_y
end

--[=[
[find_offset_hex_polar]
Author: MadMax (username on the Battle for Wesnoth forum)

Calculates the closest hex from an origin hex and an offest in polar coordinates.

Required keys:
origin_x, origin_y: the first tile
radius: vector length in tiles
theta: angle in radians; note that this is counterclockwise (i.e. not with reversed Y-axis)

Optional keys:
new_x_variable, new_y_variable: variable names to store new hex coordinates
	If not specified, will default to "new_x" and "new_y" respectively

Example:
[find_offset_hex_polar]
	origin_x=30
	origin_y=10
	radius=9
	theta=$(pi()/4)
[/find_offset_hex_polar]
]=]

function hexutils.find_offset_hex_polar(origin_x, origin_y, radius, theta)
	local radius = radius * 72.0
	local theta = theta * -1
	local offset_x = math.cos(theta) * radius
	local offset_y = math.sin(theta) * radius
	local new_x,new_y = hexutils.calc_image_hex_offset(origin_x, origin_y, offset_x, offset_y)
	return new_x, new_y
end

function wesnoth.wml_actions.find_offset_hex_polar(cfg)
	local origin_x = tonumber(cfg.origin_x)
	local origin_y = tonumber(cfg.origin_y)
	local radius = tonumber(cfg.radius)
	local theta = tonumber(cfg.theta)
	local new_x, new_y = hexutils.find_offset_hex_polar(origin_x, origin_y, radius, theta)
	local new_x_varname = cfg.new_x_variable or "new_x"
	local new_y_varname = cfg.new_y_variable or "new_y"
	wml.variables[new_x_varname] = new_x
	wml.variables[new_y_varname] = new_y
end

return hexutils
