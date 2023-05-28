
require("util")

local ignored_entity_types = {
  ["straight-rail"] = true,
  ["pwer-pole"] = true,
  ["radar"] = true,
  ['rail-signal'] = true,
  ['rail-chain-signal'] = true,
  ['wall'] = true,
  ['gate'] = true,
  ['car'] = true,
  ['locomotive'] = true,
  ['cargo-wagon'] = true,
  ['fluid-wagon'] = true,
  ['artillery-wagon'] = true,
  ['artillery-turret'] = true,
}

local function chatty_print(message)
  global.chatty_print = false
  if not global.chatty_print then return end
  game.print(message)
end

---@param position MapPosition
---@param radius number
---@return MapPosition
local function random_position_in_radius(position, radius)
  local angle = math.random() * 2 * math.pi
  local distance = math.random() * radius
  return {
    x = position.x + math.cos(angle) * distance,
    y = position.y + math.sin(angle) * distance
  }
end

---@param spidertron LuaEntity
local function send_spider_wandering(spidertron)
  local surface = spidertron.surface
  local position = spidertron.position
  local player_built_entities = {}
  for i = 1, 5 do
    if player_built_entities[1] then break end
    local wander_position = random_position_in_radius(position, 250)
    local find_entities_filter = { ---@type LuaSurface.find_entities_filtered_param
      force = spidertron.force,
      position = wander_position,
      radius = 10,
      to_be_deconstructed = false,
      -- is_military_target = true,
      limit = 1,
    }
    player_built_entities = surface.find_entities_filtered(find_entities_filter)
  end
  local entity = player_built_entities[1]
  if not entity then return end
  chatty_print("Spidertron found a player built entity to wander to")
  if ignored_entity_types[entity.type] then return end
  local legs = spidertron.get_spider_legs()
  local path_request_parameters = { ---@type LuaSurface.request_path_param
    -- bounding_box = spidertron.bounding_box,
    -- collision_mask = spidertron.prototype.collision_mask,
    bounding_box = legs[1].bounding_box,
    collision_mask = legs[1].prototype.collision_mask,
    start = position,
    goal = player_built_entities[1].position,
    force = spidertron.force,
    radius = 10,
    pathfind_flags = {low_priority = true, cache = false},
    path_resolution_modifier = -3,
  }
  local request_path_id = surface.request_path(path_request_parameters)
  global.request_path_ids = global.request_path_ids or {} ---@type table<uint, LuaEntity>
  global.request_path_ids[request_path_id] = spidertron
  chatty_print("Spidertron requested a path to the entity")
end

---@param spidertron LuaEntity
local function nudge_spidertron(spidertron)
  local autopilot_destinations = spidertron.autopilot_destinations
  local destination_count = #autopilot_destinations
  if destination_count >= 1 then
    local legs = spidertron.get_spider_legs()
    local path_request_parameters = { ---@type LuaSurface.request_path_param
      bounding_box = legs[1].bounding_box,
      collision_mask = legs[1].prototype.collision_mask,
      start = spidertron.position,
      goal = autopilot_destinations[destination_count],
      force = spidertron.force,
      radius = 10,
      pathfind_flags = {
        low_priority = false,
        cache = false,
        -- prefer_straight_paths = true
      },
      path_resolution_modifier = -2,
    }
  local request_path_id = spidertron.surface.request_path(path_request_parameters)
  global.request_path_ids = global.request_path_ids or {}
  global.request_path_ids[request_path_id] = spidertron
  game.map_settings.path_finder.use_path_cache = false
  chatty_print("Spidertron requested a path to the new position")
  else
    local random_position = spidertron.surface.find_non_colliding_position(spidertron.name, random_position_in_radius(spidertron.position, 25), 25, 0.5)
    random_position = random_position or random_position_in_radius(spidertron.position, 25)
    spidertron.add_autopilot_destination(random_position)
  end
end

---@param event EventData.on_script_path_request_finished
local function on_script_path_request_finished(event)
  global.request_path_ids = global.request_path_ids or {}
  if not global.request_path_ids[event.id] then return end
  chatty_print("Spidertron path request finished")
  local path = event.path
  local spidertron = global.request_path_ids[event.id]
  if not spidertron and spidertron.valid then chatty_print("invalid spider") goto cleanup end
  if event.try_again_later then chatty_print("try again later") goto cleanup end
  if not path then chatty_print("no path") nudge_spidertron(spidertron) goto cleanup end
  if spidertron.speed > 0 then goto cleanup end
  spidertron.autopilot_destination = nil
  for _, waypoint in ipairs(path) do
    spidertron.add_autopilot_destination(waypoint.position)
  end
  chatty_print("Spidertron wander path memorized")
  ::cleanup::
  global.request_path_ids[event.id] = nil
end

-- on_nth_tick check if any spidertrons are bored and want to go off wandering
---@param event NthTickEventData
local function on_nth_tick(event)
  for destruction_id, spidertron in pairs(global.spidertrons) do
    if not spidertron.valid then
      global.spidertrons[destruction_id] = nil
      goto next_spidertron
    end
    if spidertron.speed ~= 0 then goto next_spidertron end
    if spidertron.autopilot_destinations[1] then nudge_spidertron(spidertron) goto next_spidertron end
    if math.random() > 5/10 then goto next_spidertron end
    chatty_print("Spidertron is bored and wants to go wandering")
    send_spider_wandering(spidertron)
    ::next_spidertron::
  end
end

---@param spidertron LuaEntity
local function add_spider(spidertron)
  global.ignored_spidertrons = global.ignored_spidertrons or {}
  if global.ignored_spidertrons[spidertron.name] then return end
  local destruction_id = script.register_on_entity_destroyed(spidertron)
  global.spidertrons = global.spidertrons or {} ---@type table<uint64, LuaEntity>
  global.spidertrons[destruction_id] = spidertron
end

---@param registration_number uint64
local function remove_spider(registration_number)
  global.spidertrons = global.spidertrons or {}
  global.spidertrons[registration_number] = nil
end

---@param name string
local function ignore_spider(name)
  global.ignored_spidertrons = global.ignored_spidertrons or {}
  global.ignored_spidertrons[name] = true
end

local function initialize_globals()
  global.spidertrons = {}
  for _, surface in pairs(game.surfaces) do
    for _, spidertron in pairs(surface.find_entities_filtered{type = "spider-vehicle"}) do
      if not spidertron and not spidertron.valid then goto next_spidertron end
      add_spider(spidertron)
      ::next_spidertron::
    end
  end
  global.ignored_spidertrons = {
    ["companion"] = true,
    ["constructron"] = true,
  }
end

---@param event EventData.on_built_entity | EventData.on_robot_built_entity
local function on_built_entity(event)
  if event.created_entity.type ~= "spider-vehicle" then return end
  local spidertron = event.created_entity
  add_spider(spidertron)
end

---@param event EventData.on_entity_destroyed
local function on_entity_destroyed(event)
  remove_spider(event.registration_number)
end

script.on_init(initialize_globals)
script.on_configuration_changed(initialize_globals)
script.on_nth_tick(300, on_nth_tick)
script.on_event(defines.events.on_built_entity, on_built_entity)
script.on_event(defines.events.on_robot_built_entity, on_built_entity)
script.on_event(defines.events.on_entity_destroyed, on_entity_destroyed)
script.on_event(defines.events.on_script_path_request_finished, on_script_path_request_finished)