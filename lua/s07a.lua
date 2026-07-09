-- Lua code used by scenario 7A (The Open Ocean)

local simplex = wesnoth.require('~add-ons/Flight_Freedom/lua/simplex.lua')

StormHandler = {
	-- lower threshold corresponds to more lightning
	-- 0.7 feels better with 2d noise, 0.57 feels better with 3d noise
	lightning_threshold = 0.57,
	-- lower cloud scale corresponds with larger clouds
	cloud_scale = 0.2,
	-- lower time scale corresponds with slower cloud changes per turn
	time_scale = 0.05,
	cloud_map = {},
	built_turn = 0,
}

function StormHandler:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function StormHandler:init()
	local x_offset = mathx.random(0,99999)
	wml.variables["x_offset"] = x_offset
	local y_offset = mathx.random(0,99999)
	wml.variables["y_offset"] = y_offset
	local z_offset = mathx.random(0,99999)
	wml.variables["z_offset"] = z_offset
end

-- x: input
-- k: depth
function StormHandler:exponential_adjust(x, k)
	local y = x
	if k ~= 0.0 then
		y = (1.0 - math.exp(-1.0 * k * x)) / (1.0 - math.exp(-1.0 * k))
	end
	return y
end

function StormHandler:noise_2d(hex_x, hex_y)
	local x_pixel, y_pixel = hex_to_cartesian_space(hex_x, hex_y)
	local x = (x_pixel * self.cloud_scale) + wml.variables["x_offset"]
	local y = (y_pixel * self.cloud_scale) + wml.variables["y_offset"]
	-- simplex noise ranges [-1, 1]; we want our average to be 0.5
	local r = (simplex.Noise2D(x, y) + 1.0) / 2.0
	return r
end

-- by moving linearly down the z-axis can simulate cloud shifts
function StormHandler:noise_3d(hex_x, hex_y, time_z)
	local x_pixel, y_pixel = hex_to_cartesian_space(hex_x, hex_y)
	local x = (x_pixel * self.cloud_scale) + wml.variables["x_offset"]
	local y = (y_pixel * self.cloud_scale) + wml.variables["y_offset"]
	local z = (time_z * self.time_scale) + wml.variables["z_offset"]
	local r = (simplex.Noise3D(x, y, z) + 1.0) / 2.0
	return r
end

-- build the whole cloud map from scratch
-- use: loaded a save or starting the scenario
function StormHandler:build_cloud_map_2d(turn_number)
	self.cloud_map = {}
	for i = 1, wesnoth.current.map.playable_width do
		local column = {}
		for j = 1, wesnoth.current.map.playable_height do
			-- lightning moves to the left
			local x = i + turn_number
			local y = j
			local noise = self:noise_2d(x, y)
			table.insert(column, noise)
		end
		table.insert(self.cloud_map, column)
	end
	self.built_turn = turn_number
end

-- avoid sampling the whole map unless we have to
function StormHandler:update_map_2d(turn_number)
	if math.abs(turn_number - self.built_turn) >= wesnoth.current.map.playable_width then
		-- we've skipped too far off the cached map
		self:build_cloud_map_3d(turn_number)
	elseif turn_number > self.built_turn then
		-- moving forward in time
		for i = self.built_turn + 1, turn_number do
			table.remove(self.cloud_map, 1)
			local column = {}
			for j = 1, wesnoth.current.map.playable_height do
				local x = i + wesnoth.current.map.playable_width
				local y = j
				local noise = self:noise_2d(x, y)
				table.insert(column, noise)
			end
			table.insert(self.cloud_map, column)
		end
	elseif turn_number < self.built_turn then
		-- moving backward in time
		for i = self.built_turn - 1, turn_number, -1 do
			table.remove(self.cloud_map, #self.cloud_map)
			local column = {}
			for j = 1, wesnoth.current.map.playable_height do
				local x = i
				local y = j
				local noise = self:noise_2d(x, y)
				table.insert(column, noise)
			end
			table.insert(self.cloud_map, column, 1)
		end
	end
	self.built_turn = turn_number
end

function StormHandler:build_cloud_map_3d(turn_number)
	self.cloud_map = {}
	for i = 1, wesnoth.current.map.playable_width do
		local column = {}
		for j = 1, wesnoth.current.map.playable_height do
			-- lightning moves to the left
			local x = i + turn_number
			local y = j
			local noise = self:noise_3d(x, y, turn_number)
			table.insert(column, noise)
		end
		table.insert(self.cloud_map, column)
	end
	self.built_turn = turn_number
end

-- when traversing in 3d, can't benefit from caching
function StormHandler:update_map_3d(turn_number)
	self:build_cloud_map_3d(turn_number)
end

function StormHandler:get_lightning_hexes()
	local lightning_locs = {}
	for i = 1, wesnoth.current.map.playable_width do
		for j = 1, wesnoth.current.map.playable_height do
			if self.cloud_map[i][j] > self.lightning_threshold then
				local hex = {i, j}
				table.insert(lightning_locs, hex)
			end
		end
	end
	return lightning_locs
end

function StormHandler:debug_show_cloud_map()
	for i = 1, wesnoth.current.map.playable_width do
		for j = 1, wesnoth.current.map.playable_height do
			wesnoth.map.remove_label{x=i, y=j}
			wesnoth.map.add_label{x=i, y=j, text=string.format("%.3f",self.cloud_map[i][j])}
		end
	end
end

storm_handler = StormHandler:new()

function add_hex_highlights(locs)
	for i, hex in ipairs(locs) do
		wesnoth.interface.add_item_image(hex[1], hex[2], "halo/highlight-hex.png")
	end
end

function remove_hex_highlights(locs)
	for i, hex in ipairs(locs) do
		wesnoth.interface.remove_item(hex[1], hex[2], "halo/highlight-hex.png")
	end
end

function lightning_strike_damage(locs)
	mathx.shuffle(locs)
	for i, hex in ipairs(locs) do
		local unit = wesnoth.units.get(hex[1], hex[2])
		if unit ~= nil and unit.side == 1 then
			wesnoth.audio.play("lightning.ogg")
			local bolt_var = mathx.random(1,3)
			for j = 1, 4 do
				local image_path = "halo/lightning-bolt-" .. tostring(bolt_var) .. "-" .. tostring(j) .. ".png~PAD(b=250)"
				wesnoth.interface.add_hex_overlay(hex[1], hex[2], {halo = image_path})
				wesnoth.interface.delay(100)
				wesnoth.interface.remove_hex_overlay(hex[1], hex[2], image_path)
			end
			wesnoth.wml_actions.harm_unit{wml.tag.filter{x=hex[1], y=hex[2]}, amount=12, kill=true, fire_event=true}
			wesnoth.interface.delay(500)
		end
	end
end

-- regenerate the cloud map on save load (when called by preload event)
if wml.variables["storm_initial_setup"] == 1 then
	storm_handler:build_cloud_map_3d(wesnoth.current.turn)
end

-- must be done in prestart instead of preload for replay safety
function storm_initial_setup()
	storm_handler:init()
	storm_handler:build_cloud_map_3d(1)
	local lightning_locs = storm_handler:get_lightning_hexes()
	add_hex_highlights(lightning_locs)
	wml.variables["storm_initial_setup"] = 1
	--storm_handler:debug_show_cloud_map()
end

function storm_turn_update()
	if wesnoth.current.turn >= 2 then
		local lightning_locs = storm_handler:get_lightning_hexes()
		lightning_strike_damage(lightning_locs)
		remove_hex_highlights(lightning_locs)
		storm_handler:update_map_3d(wesnoth.current.turn)
		lightning_locs = storm_handler:get_lightning_hexes()
		add_hex_highlights(lightning_locs)
	end
	--storm_handler:debug_show_cloud_map()
end

function wesnoth.wml_actions.storm_initial_setup(cfg)
	storm_initial_setup()
end

function wesnoth.wml_actions.storm_turn_update(cfg)
	storm_turn_update()
end
