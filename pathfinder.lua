-----------------
-- Pathfinding --
-----------------

local a_star_alloted_time = tonumber(minetest.settings:get("creatura_a_star_alloted_time")) or 500
local theta_star_alloted_time = tonumber(minetest.settings:get("creatura_theta_star_alloted_time")) or 700

local floor = math.floor
local abs = math.abs

local vec_dist = vector.distance

local moveable = creatura.is_pos_moveable

local function get_distance(start_pos, end_pos)
	local distX = abs(start_pos.x - end_pos.x)
	local distZ = abs(start_pos.z - end_pos.z)

	if distX > distZ then
		return 14 * distZ + 10 * (distX - distZ)
	else
		return 14 * distX + 10 * (distZ - distX)
	end
end

local function get_distance_to_neighbor(start_pos, end_pos)
	local distX = abs(start_pos.x - end_pos.x)
	local distY = abs(start_pos.y - end_pos.y)
	local distZ = abs(start_pos.z - end_pos.z)

	if distX > distZ then
		return (14 * distZ + 10 * (distX - distZ)) * (distY + 1)
	else
		return (14 * distX + 10 * (distZ - distX)) * (distY + 1)
	end
end

local function is_on_ground(pos)
	local ground = {
		x = pos.x,
		y = pos.y - 1,
		z = pos.z
	}
	if creatura.get_node_def(ground).walkable then
		return true
	end
	return false
end

local function vec_raise(v, n)
	return {x = v.x, y = v.y + n, z = v.z}
end

local function get_line_of_sight(a, b)
	local steps = floor(vec_dist(a, b))
	local line = {}

	for i = 0, steps do
		local pos

		if steps > 0 then
			pos = {
				x = a.x + (b.x - a.x) * (i / steps),
				y = a.y + (b.y - a.y) * (i / steps),
				z = a.z + (b.z - a.z) * (i / steps)
			}
		else
			pos = a
		end
		table.insert(line, pos)
	end

	if #line < 1 then
		return false
	else
		for i = 1, #line do
			local node = minetest.get_node(line[i])
			if creatura.get_node_def(node.name).walkable then
				return false
			end
		end
	end
	return true
end

-- Find a path from start to goal

function creatura.find_path(self, start, goal, obj_width, obj_height, max_open, climb, fly, swim)
	climb = climb or false
	fly = fly or false
	swim = swim or false

	start = self._path_data.start or start

	self._path_data.start = start

	local path_neighbors = {
		{x = 1, y = 0, z = 0},
		{x = 1, y = 0, z = 1},
		{x = 0, y = 0, z = 1},
		{x = -1, y = 0, z = 1},
		{x = -1, y = 0, z = 0},
		{x = -1, y = 0, z = -1},
		{x = 0, y = 0, z = -1},
		{x = 1, y = 0, z = -1}
	}

	if climb then
		table.insert(path_neighbors, {x = 0, y = 1, z = 0})
	end

	if fly
	or swim then
		path_neighbors = {
			-- Central
			{x = 1, y = 0, z = 0},
			{x = 0, y = 0, z = 1},
			{x = -1, y = 0, z = 0},
			{x = 0, y = 0, z = -1},
			-- Directly Up or Down
			{x = 0, y = 1, z = 0},
			{x = 0, y = -1, z = 0}
		}
	end

	local function get_neighbors(pos, width, height, tbl, open, closed)
		local result = {}
		for i = 1, #tbl do
			local neighbor = vector.add(pos, tbl[i])
			if neighbor.y == pos.y
			and not fly
			and not swim then
				neighbor = creatura.get_ground_level(neighbor, 1)
			end
			local can_move = get_line_of_sight({x = pos.x, y = neighbor.y, z = pos.z}, neighbor)
			if swim then
				can_move = true
			end
			if not moveable(vec_raise(neighbor, -0.49), width, height) then
				can_move = false
				if neighbor.y == pos.y
				and moveable(vec_raise(neighbor, 0.51), width, height) then
					neighbor = vec_raise(neighbor, 1)
					can_move = true
				end
			end
			if vector.equals(neighbor, goal) then
				can_move = true
			end
			if open[minetest.hash_node_position(neighbor)]
			or closed[minetest.hash_node_position(neighbor)] then
				can_move = false
			end
			if can_move
			and ((is_on_ground(neighbor)
			or (fly or swim))
			or (neighbor.x == pos.x
			and neighbor.z == pos.z
			and climb))
			and (not swim
			or creatura.get_node_def(neighbor).drawtype == "liquid") then
				table.insert(result, neighbor)
			end
		end
		return result
	end

	local function find_path(_start, _goal)
		local us_time = minetest.get_us_time()

		_start = {
			x = floor(_start.x + 0.5),
			y = floor(_start.y + 0.5),
			z = floor(_start.z + 0.5)
		}

		_goal = {
			x = floor(_goal.x + 0.5),
			y = floor(_goal.y + 0.5),
			z = floor(_goal.z + 0.5)
		}

		if _goal.x == _start.x
		and _goal.z == _start.z then -- No path can be found
			return nil
		end

		local openSet = self._path_data.open or {}

		local closedSet = self._path_data.closed or {}

		local start_index = minetest.hash_node_position(_start)

		openSet[start_index] = {
			pos = _start,
			parent = nil,
			gScore = 0,
			fScore = get_distance(_start, _goal)
		}

		local count = self._path_data.count or 1

		while count > 0 do
			if minetest.get_us_time() - us_time > a_star_alloted_time then
				self._path_data = {
					start = _start,
					open = openSet,
					closed = closedSet,
					count = count
				}
				return
			end
			-- Initialize ID and data
			local current_id
			local current

			-- Get an initial id in open set
			for i, v in pairs(openSet) do
				current_id = i
				current = v
				break
			end

			-- Find lowest f cost
			for i, v in pairs(openSet) do
				if v.fScore < current.fScore then
					current_id = i
					current = v
				end
			end

			-- Add lowest fScore to closedSet and remove from openSet
			openSet[current_id] = nil
			closedSet[current_id] = current

			self._path_data.open = openSet
			self._path_data.closedSet = closedSet

			-- Reconstruct path if end is reached
			if ((is_on_ground(_goal)
			or fly)
			and current_id == minetest.hash_node_position(_goal))
			or (not fly
			and not is_on_ground(_goal)
			and _goal.x == current.pos.x
			and _goal.z == current.pos.z) then
				local path = {}
				local fail_safe = 0
				for _ in pairs(closedSet) do
					fail_safe = fail_safe + 1
				end
				repeat
					if not closedSet[current_id] then return end
					table.insert(path, closedSet[current_id].pos)
					current_id = closedSet[current_id].parent
				until current_id == start_index or #path >= fail_safe
				if not closedSet[current_id] then self._path_data = {} return nil end
				table.insert(path, closedSet[current_id].pos)
				local reverse_path = {}
				repeat table.insert(reverse_path, table.remove(path)) until #path == 0
				self._path_data = {}
				return reverse_path
			end

			count = count - 1

			local adjacent = get_neighbors(current.pos, obj_width, obj_height, path_neighbors, openSet, closedSet)

			-- Go through neighboring nodes
			for i = 1, #adjacent do
				local neighbor = {
					pos = adjacent[i],
					parent = current_id,
					gScore = 0,
					fScore = 0
				}
				local temp_gScore = current.gScore + get_distance_to_neighbor(current.pos, neighbor.pos)
				local new_gScore = 0
				if openSet[minetest.hash_node_position(neighbor.pos)] then
					new_gScore = openSet[minetest.hash_node_position(neighbor.pos)].gScore
				end
				if (temp_gScore < new_gScore
				or not openSet[minetest.hash_node_position(neighbor.pos)])
				and not closedSet[minetest.hash_node_position(neighbor.pos)] then
					if not openSet[minetest.hash_node_position(neighbor.pos)] then
						count = count + 1
					end
					local hCost = get_distance_to_neighbor(neighbor.pos, _goal)
					neighbor.gScore = temp_gScore
					neighbor.fScore = temp_gScore + hCost
					openSet[minetest.hash_node_position(neighbor.pos)] = neighbor
				end
			end
			if count > (max_open or 100) then
				self._path_data = {}
				return
			end
		end
		self._path_data = {}
		return nil
	end
	return find_path(start, goal)
end


------------
-- Theta* --
------------

function creatura.find_theta_path(self, start, goal, obj_width, obj_height, max_open, climb, fly, swim)
	climb = climb or false
	fly = fly or false
	swim = swim or false

	start = self._path_data.start or start

	self._path_data.start = start

	local path_neighbors = {
		{x = 1, y = 0, z = 0},
		{x = 0, y = 0, z = 1},
		{x = -1, y = 0, z = 0},
		{x = 0, y = 0, z = -1},
	}

	if climb then
		table.insert(path_neighbors, {x = 0, y = 1, z = 0})
	end

	if fly
	or swim then
		path_neighbors = {
			-- Central
			{x = 1, y = 0, z = 0},
			{x = 0, y = 0, z = 1},
			{x = -1, y = 0, z = 0},
			{x = 0, y = 0, z = -1},
			-- Directly Up or Down
			{x = 0, y = 1, z = 0},
			{x = 0, y = -1, z = 0}
		}
	end

	local function get_neighbors(pos, width, height, tbl, open, closed)
		local result = {}
		for i = 1, #tbl do
			local neighbor = vector.add(pos, tbl[i])
			if neighbor.y == pos.y
			and not fly
			and not swim then
				neighbor = creatura.get_ground_level(neighbor, 1)
			end
			local can_move = get_line_of_sight({x = pos.x, y = neighbor.y, z = pos.z}, neighbor)
			if swim then
				can_move = true
			end
			if not moveable(vec_raise(neighbor, -0.49), width, height) then
				can_move = false
				if neighbor.y == pos.y
				and moveable(vec_raise(neighbor, 0.51), width, height) then
					neighbor = vec_raise(neighbor, 1)
					can_move = true
				end
			end
			if vector.equals(neighbor, goal) then
				can_move = true
			end
			if open[minetest.hash_node_position(neighbor)]
			or closed[minetest.hash_node_position(neighbor)] then
				can_move = false
			end
			if can_move
			and ((is_on_ground(neighbor)
			or (fly or swim))
			or (neighbor.x == pos.x
			and neighbor.z == pos.z
			and climb))
			and (not swim
			or creatura.get_node_def(neighbor).drawtype == "liquid") then
				table.insert(result, neighbor)
			end
		end
		return result
	end

	local function find_path(_start, _goal)
		local us_time = minetest.get_us_time()

		_start = {
			x = floor(_start.x + 0.5),
			y = floor(_start.y + 0.5),
			z = floor(_start.z + 0.5)
		}

		_goal = {
			x = floor(_goal.x + 0.5),
			y = floor(_goal.y + 0.5),
			z = floor(_goal.z + 0.5)
		}

		if _goal.x == _start.x
		and _goal.z == _start.z then -- No path can be found
			return nil
		end

		local openSet = self._path_data.open or {}

		local closedSet = self._path_data.closed or {}

		local start_index = minetest.hash_node_position(_start)

		openSet[start_index] = {
			pos = _start,
			parent = nil,
			gScore = 0,
			fScore = get_distance(_start, _goal)
		}

		local count = self._path_data.count or 1

		while count > 0 do
			if minetest.get_us_time() - us_time > theta_star_alloted_time then
				self._path_data = {
					start = _start,
					open = openSet,
					closed = closedSet,
					count = count
				}
				return
			end

			-- Initialize ID and data
			local current_id
			local current

			-- Get an initial id in open set
			for i, v in pairs(openSet) do
				current_id = i
				current = v
				break
			end

			-- Find lowest f cost
			for i, v in pairs(openSet) do
				if v.fScore < current.fScore then
					current_id = i
					current = v
				end
			end

			-- Add lowest fScore to closedSet and remove from openSet
			openSet[current_id] = nil
			closedSet[current_id] = current

			-- Reconstruct path if end is reached
			if (is_on_ground(_goal)
			and current_id == minetest.hash_node_position(_goal))
			or (not is_on_ground(_goal)
			and _goal.x == current.pos.x
			and _goal.z == current.pos.z) then
				local path = {}
				local fail_safe = 0
				for _ in pairs(closedSet) do
					fail_safe = fail_safe + 1
				end
				repeat
					if not closedSet[current_id] then return end
					table.insert(path, closedSet[current_id].pos)
					current_id = closedSet[current_id].parent
				until current_id == start_index or #path >= fail_safe
				if not closedSet[current_id] then self._path_data = {} return nil end
				table.insert(path, closedSet[current_id].pos)
				local reverse_path = {}
				repeat table.insert(reverse_path, table.remove(path)) until #path == 0
				self._path_data = {}
				return reverse_path
			end

			count = count - 1

			local adjacent = get_neighbors(current.pos, obj_width, obj_height, path_neighbors, openSet, closedSet)

			-- Go through neighboring nodes
			for i = 1, #adjacent do
				local neighbor = {
					pos = adjacent[i],
					parent = current_id,
					gScore = 0,
					fScore = 0
				}
				if not openSet[minetest.hash_node_position(neighbor.pos)]
				and not closedSet[minetest.hash_node_position(neighbor.pos)] then
					local current_parent = closedSet[current.parent] or closedSet[start_index]
					if not current_parent then
						current_parent = openSet[current.parent] or openSet[start_index]
					end
					if current_parent
					and get_line_of_sight(current_parent.pos, neighbor.pos) then
						local temp_gScore = current_parent.gScore + get_distance_to_neighbor(current_parent.pos, neighbor.pos)
						local new_gScore = 999
						if openSet[minetest.hash_node_position(neighbor.pos)] then
							new_gScore = openSet[minetest.hash_node_position(neighbor.pos)].gScore
						end
						if temp_gScore < new_gScore then
							local hCost = get_distance_to_neighbor(neighbor.pos, _goal)
							neighbor.gScore = temp_gScore
							neighbor.fScore = temp_gScore + hCost
							neighbor.parent = minetest.hash_node_position(current_parent.pos)
							if openSet[minetest.hash_node_position(neighbor.pos)] then
								openSet[minetest.hash_node_position(neighbor.pos)] = nil
							end
							openSet[minetest.hash_node_position(neighbor.pos)] = neighbor
							count = count + 1
						end
					else
						local temp_gScore = current.gScore + get_distance_to_neighbor(current_parent.pos, neighbor.pos)
						local new_gScore = 999
						if openSet[minetest.hash_node_position(neighbor.pos)] then
							new_gScore = openSet[minetest.hash_node_position(neighbor.pos)].gScore
						end
						if temp_gScore < new_gScore then
							local hCost = get_distance_to_neighbor(neighbor.pos, _goal)
							neighbor.gScore = temp_gScore
							neighbor.fScore = temp_gScore + hCost
							if openSet[minetest.hash_node_position(neighbor.pos)] then
								openSet[minetest.hash_node_position(neighbor.pos)] = nil
							end
							openSet[minetest.hash_node_position(neighbor.pos)] = neighbor
							count = count + 1
						end
					end
				end
			end
			if count > (max_open or 100) then
				self._path_data = {}
				return
			end
		end
		self._path_data = {}
		return nil
	end
	return find_path(start, goal)
end
