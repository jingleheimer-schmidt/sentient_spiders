
require("util")

local ignored_entity_types = {
  ["straight-rail"] = true,
  ["curved-rail"] = true,
  ["electric-pole"] = true,
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
  ["unit"] = true,
  ["turret"] = true,
  ["unit-spawner"] = true,
}

---@param message string
local function chatty_print(message)
  global.chatty_print = false
  if not global.chatty_print then return end
  game.print("[" .. game.tick .. "]" .. message)
end

---@param spidertron LuaEntity
---@param message string
local function spider_speak(spidertron, message)
  local manual_override = true
  if manual_override then return end
  if math.random() > 0.5 then return end
  global.ignored_spidertrons = global.ignored_spidertrons or {}
  if global.ignored_spidertrons[spidertron.name] then return end
  local visible_to_players = {}
  for _, player in pairs(game.connected_players) do
    table.insert(visible_to_players, player.name)
  end
  local color = spidertron.color or {r = 1, g = 1, b = 1}
  color.a = 1
  rendering.draw_text{
    text = message,
    surface = spidertron.surface,
    target = spidertron,
    target_offset = {0, -8},
    alignment = "center",
    color = color,
    scale = 2.5,
    scale_with_zoom = true,
    players = visible_to_players,
    time_to_live = 60 * 5
  }
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

---@param position MapPosition
---@param inner_radius number
---@param outer_radius number
---@return MapPosition
local function random_position_within_range(position, inner_radius, outer_radius)
  local angle = math.random() * 2 * math.pi
  local distance = math.max(inner_radius, math.random() * outer_radius)
  return {
    x = position.x + math.cos(angle) * distance,
    y = position.y + math.sin(angle) * distance
  }
end

---@param spidertron LuaEntity
---@param start_position MapPosition
---@param goal_position MapPosition
---@param force ForceIdentification
---@param radius number
---@param path_resolution_modifier number
---@param entity_to_ignore LuaEntity?
---@param spider_was_stuck boolean?
local function request_spider_path(spidertron, start_position, goal_position, force, radius, path_resolution_modifier, entity_to_ignore, spider_was_stuck)
  local request_path_id = spidertron.surface.request_path{
    bounding_box = {{-0.01, -0.01}, {0.01, 0.01}},
    collision_mask = {"water-tile", "colliding-with-tiles-only", "consider-tile-transitions"},
    start = start_position,
    goal = goal_position,
    force = force,
    radius = radius,
    pathfind_flags = {low_priority = true, cache = true},
    path_resolution_modifier = path_resolution_modifier,
    entity_to_ignore = entity_to_ignore,
  }
  ---@class PathRequestData
  ---@field spidertron LuaEntity
  ---@field resolution number
  ---@field spider_was_stuck boolean?
  global.request_path_ids = global.request_path_ids or {} ---@type table<uint, PathRequestData>
  global.request_path_ids[request_path_id] = {
    spidertron = spidertron,
    resolution = -3,
    spider_was_stuck = spider_was_stuck,
  }
  chatty_print("Spidertron requested a path to the entity")
end

---@param spidertron LuaEntity
---@return boolean
local function spider_has_active_bots(spidertron)
  local cell = spidertron.logistic_cell
  if not cell then return false end
  local network = cell.logistic_network
  if not network then return false end
  if network.available_logistic_robots == network.all_logistic_robots then return false end
  if network.available_construction_robots == network.all_construction_robots then return false end
  return true
end

---@param spidertron LuaEntity
local function send_spider_wandering(spidertron)
  if spider_has_active_bots(spidertron) then return end
  local surface = spidertron.surface
  local position = spidertron.position
  local player_built_entities = {}
  for i = 1, 5 do
    if player_built_entities[1] then break end
    -- local wander_position = random_position_in_radius(position, 250)
    local wander_position = random_position_within_range(position, 100, 500)
    local find_entities_filter = { ---@type LuaSurface.find_entities_filtered_param
      force = spidertron.force,
      position = wander_position,
      radius = 5,
      -- to_be_deconstructed = false,
      limit = 1,
    }
    player_built_entities = surface.find_entities_filtered(find_entities_filter)
  end
  local entity = player_built_entities[1]
  local unit_number = spidertron.unit_number --[[@as uint]]
  global.try_again_next_tick = global.try_again_next_tick or {}
  if not entity then
    global.try_again_next_tick[unit_number] = spidertron
    return
  else
    global.try_again_next_tick [unit_number] = nil
  end
  chatty_print("Spidertron found a player built entity to wander to")
  if ignored_entity_types[entity.type] then return end
  -- game.print("attempting to wander to [" .. entity.type .. "]")
  -- local legs = spidertron.get_spider_legs()
  -- for _, leg in pairs(legs) do
  --   request_spider_path(spidertron, leg.position, entity.position, spidertron.force, 10, -3, leg)
  -- end
  request_spider_path(spidertron, spidertron.position, entity.position, spidertron.force, 10, -4)
end

---@param spidertron LuaEntity
local function nudge_spidertron(spidertron)
  local autopilot_destinations = spidertron.autopilot_destinations
  local destination_count = #autopilot_destinations
  if destination_count >= 1 then
    -- local random_position = random_position_in_radius(autopilot_destinations[destination_count], 15)
    -- local legs = spidertron.get_spider_legs()
    -- local non_colliding_position = spidertron.surface.find_non_colliding_position(legs[1].name, random_position, 50, 0.25)
    -- local new_position = non_colliding_position or random_position
    -- remote.call("SpidertronEnhancementsInternal-pf", "use-remote", spidertron, new_position)
    local random_position = random_position_in_radius(spidertron.position, 50)
    local legs = spidertron.get_spider_legs()
    local non_colliding_position = spidertron.surface.find_non_colliding_position(legs[1].name, random_position, 50, 0.25)
    local new_position = non_colliding_position or random_position
    if destination_count > 1 then
      autopilot_destinations[1] = new_position
    else
      table.insert(autopilot_destinations, 1, new_position)
    end
    request_spider_path(spidertron, new_position, autopilot_destinations[#autopilot_destinations], spidertron.force, 10, -3, nil, true)
    spidertron.autopilot_destination = nil
    for _, destination in pairs(autopilot_destinations) do
      spidertron.add_autopilot_destination(destination)
    end
    chatty_print("Spidertron re-requested a path to the destination")
  else
    local random_position = random_position_in_radius(spidertron.position, 15)
    spidertron.add_autopilot_destination(random_position)
    -- remote.call("SpidertronEnhancementsInternal-pf", "use-remote", spidertron, random_position)
    chatty_print("Spidertron requested a path to a nearby random position")
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
    if spidertron.follow_target then goto next_spidertron end
    -- if spidertron. -- goto next_spidertron end if spider construction bots are active or logistic bots are on the way
    if spidertron.autopilot_destinations[1] then nudge_spidertron(spidertron) goto next_spidertron end
    local chance = math.random(100)
    if (chance < 95) then goto next_spidertron end
    chatty_print("Spidertron is bored and wants to go wandering")
    send_spider_wandering(spidertron)
    ::next_spidertron::
  end
end

local idle_spider_speak_messages = {
  "I'm bored.",
  "I'm bored. I'm bored. I'm bored.",
  "I wonder what's over there?",
}

local on_the_move_spider_speak_messages = {
  "I'm going on an adventure!",
  "Almost there!",
  "I'm on my way!",
}

local specific_entity_spider_speak_messages = {
  ["accumulator"] = {
    "Power looks good on you.",
    "Accumulator is a funny word.",
  },
  ["transport-belt"] = {
    "Look at all those belts!",
  }
}

local generic_spider_speak_messages = {
  "I'm a spider!",
  "I'm a spider! I'm a spider! I'm a spider!",
  "Ooooh pretty!",
  "Please send help",
  "Oh no... ",
}

---@param event EventData.on_spider_command_completed
local function on_spider_command_completed(event)
  local spidertron = event.vehicle
  local destinations = #spidertron.autopilot_destinations
  if destinations == 0 then
    local find_entities_filter = { ---@type LuaSurface.find_entities_filtered_param
      force = spidertron.force,
      position = spidertron.position,
      radius = 5,
      to_be_deconstructed = false,
      limit = 1,
    }
    local player_built_entities = spidertron.surface.find_entities_filtered(find_entities_filter)
    if player_built_entities[1] then
      local entity = player_built_entities[1]
      local type_specific_messages = specific_entity_spider_speak_messages[entity.type]
      if type_specific_messages then
        spider_speak(spidertron, type_specific_messages[math.random(#type_specific_messages)])
      else
        spider_speak(spidertron, generic_spider_speak_messages[math.random(#generic_spider_speak_messages)])
      end
    end
  elseif destinations == 5 then
    spider_speak(spidertron, on_the_move_spider_speak_messages[math.random(#on_the_move_spider_speak_messages)])
  end
end

---@param event EventData.on_tick
local function on_tick(event)
  global.try_again_next_tick = global.try_again_next_tick or {}
  for id, spidertron in pairs(global.try_again_next_tick) do
    if not spidertron.valid then
      global.try_again_next_tick[id] = nil
      goto next_spidertron
    end
    send_spider_wandering(spidertron)
    ::next_spidertron::
  end
end

---@param event EventData.on_player_driving_changed_state
local function on_player_driving_changed_state(event)
  local spider = event.entity
  if not spider then return end
  global.ignored_spidertrons = global.ignored_spidertrons or {}
  if global.ignored_spidertrons[spider.name] then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if not (spider.type == "spider-vehicle") then return end
  if player.vehicle then return end
  if spider.get_driver() then return end
  if spider.get_passenger() then return end
  local character = player.character
  if not character then return end
  spider.follow_target = character
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

local interface_functions = {
  ignore_spider = ignore_spider,
}
remote.add_interface("wandering-spiders", interface_functions)
-- usage: remote.call("wandering-spiders", "ignore_spider", "name of spider to ignore")

script.on_init(initialize_globals)
script.on_configuration_changed(initialize_globals)
script.on_nth_tick(60, on_nth_tick)
script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_built_entity, on_built_entity)
script.on_event(defines.events.on_robot_built_entity, on_built_entity)
script.on_event(defines.events.on_entity_destroyed, on_entity_destroyed)
script.on_event(defines.events.on_spider_command_completed, on_spider_command_completed)
script.on_event(defines.events.on_script_path_request_finished, on_script_path_request_finished)
