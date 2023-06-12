
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
  -- global.chatty_print = true
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
  local color = spidertron.color or { r = 1, g = 1, b = 1 }
  color.a = 1
  rendering.draw_text{
    text = message,
    surface = spidertron.surface,
    target = spidertron,
    target_offset = { 0, -8 },
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
    bounding_box = { { -0.01, -0.01 }, { 0.01, 0.01 } },
    collision_mask = { "water-tile", "colliding-with-tiles-only", "consider-tile-transitions" },
    start = start_position,
    goal = goal_position,
    force = force,
    radius = radius,
    pathfind_flags = { low_priority = true, cache = true },
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
  local surface = spidertron.surface
  local position = spidertron.position
  local player_built_entities = {}
  for i = 1, 5 do
    if player_built_entities[1] then break end
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
    global.try_again_next_tick[unit_number] = nil
  end
  chatty_print("Spidertron found a player built entity to wander to")
  if ignored_entity_types[entity.type] then return end
  request_spider_path(spidertron, spidertron.position, entity.position, spidertron.force, 10, -4)
end

---@param spidertron LuaEntity
local function nudge_spidertron(spidertron)
  local autopilot_destinations = spidertron.autopilot_destinations
  local destination_count = #autopilot_destinations
  chatty_print("nudging spidertron")
  if destination_count >= 1 then
    local random_position = random_position_in_radius(spidertron.position, 50)
    local legs = spidertron.get_spider_legs()
    -- local non_colliding_position = spidertron.surface.find_non_colliding_position(legs[1].name, random_position, 50, 0.25)
    local non_colliding_position = spidertron.surface.find_tiles_filtered({
      position = spidertron.position,
      radius = 15,
      collision_mask = { "water-tile" },
      invert = true,
      limit = 1,
    })
    local new_position = non_colliding_position and non_colliding_position[1] and non_colliding_position[1].position or random_position
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
  local path_request_data = global.request_path_ids[event.id]
  local spidertron = path_request_data.spidertron
  local resolution = path_request_data.resolution
  local spider_was_stuck = path_request_data.spider_was_stuck
  if not spidertron and spidertron.valid then
    chatty_print("invalid spider")
    goto cleanup
  end
  if event.try_again_later then
    chatty_print("try again later")
    goto cleanup
  end
  if ((spidertron.speed > 0) and not spider_was_stuck) then goto cleanup end
  if not path then
    chatty_print("no path")
    if spidertron.speed == 0 then
      nudge_spidertron(spidertron)
    end
    goto cleanup
  end
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
  chatty_print("on_nth_tick")
  local ignored_spidertrons = global.ignored_spidertrons or {}
  for destruction_id, spidertron in pairs(global.spidertrons) do
    if not spidertron.valid then
      global.spidertrons[destruction_id] = nil
      goto next_spidertron
    end
    if ignored_spidertrons[spidertron.name] then
      chatty_print("ignored_spidertrons")
      goto next_spidertron
    end
    if spidertron.speed ~= 0 then
      chatty_print("speed ~= 0")
      goto next_spidertron
    end
    if spidertron.follow_target then
      chatty_print("follow_target")
      goto next_spidertron
    end
    if spider_has_active_bots(spidertron) then goto next_spidertron end
    if spidertron.autopilot_destinations[1] then
      nudge_spidertron(spidertron)
      chatty_print("destinations[1]")
      goto next_spidertron
    end
    local chance = math.random(100)
    if (chance < 99) then goto next_spidertron end
    local driver, passenger = spidertron.get_driver(), spidertron.get_passenger()
    if driver or passenger then chatty_print("driver or passenger")
      local knower = driver or passenger
      local player = knower and knower.type == "character" and knower.player or knower and knower.type == "player" and knower
      if player and player.afk_time and player.afk_time < 60 * 60 * 5 then goto next_spidertron end
    end
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
  elseif destinations == 10 then
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

---@param spidertron LuaEntity
local function remove_following_spider(spidertron)
  global.following_spiders = global.following_spiders or {}
  for player_index, following_spiders in pairs(global.following_spiders) do
    for unit_number, following_spider in pairs(following_spiders) do
      if unit_number == spidertron.unit_number then
        following_spiders[unit_number] = nil
      end
    end
  end
end

---@param player LuaPlayer
---@param spidertron LuaEntity
local function add_following_spider(player, spidertron)
  global.following_spiders = global.following_spiders or {}
  global.following_spiders[player.index] = global.following_spiders[player.index] or {}
  global.following_spiders[player.index][spidertron.unit_number] = spidertron
end

---@param player LuaPlayer
local function relink_following_spiders(player)
  global.following_spiders = global.following_spiders or {}
  global.following_spiders[player.index] = global.following_spiders[player.index] or {}
  for unit_number, spidertron in pairs(global.following_spiders[player.index]) do
    if spidertron and spidertron.valid then
      local follow_target = player.character or player.vehicle
      if follow_target then
        spidertron.follow_target = follow_target
      end
    else
      global.following_spiders[player.index][unit_number] = nil
    end
  end
end

---@param event EventData.on_player_driving_changed_state
local function update_player_followers(event)
  local player = game.get_player(event.player_index) --[[@as LuaPlayer]]
  global.ignored_spidertrons = global.ignored_spidertrons or {}
  global.following_spiders = global.following_spiders or {} --[[@type table<uint, table<uint, LuaEntity>>]]
  local spidertron = event.entity and event.entity.type == "spider-vehicle" and event.entity
  if spidertron then
    local driver = spidertron.get_driver()
    local passenger = spidertron.get_passenger()
    if not driver and not passenger and not global.ignored_spidertrons[spidertron.name] then
      add_following_spider(player, spidertron)
    end
  end
  relink_following_spiders(player)
end

---@param event EventData.on_player_driving_changed_state
local function on_player_driving_changed_state(event)
  update_player_followers(event)
end

---@param entity LuaEntity
---@return boolean, uint?
local function entity_is_character(entity)
  local bool = false
  local player_index = nil
  if entity and entity.type == "character" then
    bool = true
    if entity.player then
      player_index = entity.player.index
    end
  end
  return bool, player_index
end

---@param event EventData.on_player_used_spider_remote
local function on_player_used_spider_remote(event)
  if not event.success then return end
  if event.vehicle.follow_target then
    remove_following_spider(event.vehicle)
    local is_character, player_index = entity_is_character(event.vehicle.follow_target)
    if is_character and player_index then
      add_following_spider(game.get_player(player_index) --[[@as LuaPlayer]], event.vehicle)
    end
  end
  if event.vehicle.autopilot_destinations[1] then
    remove_following_spider(event.vehicle)
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

local function initialize_globals()
  global.spidertrons = {}
  for _, surface in pairs(game.surfaces) do
    for _, spidertron in pairs(surface.find_entities_filtered { type = "spider-vehicle" }) do
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

require("interface")
script.on_init(initialize_globals)
script.on_configuration_changed(initialize_globals)
script.on_nth_tick(60, on_nth_tick)
script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_built_entity, on_built_entity)
script.on_event(defines.events.on_robot_built_entity, on_built_entity)
script.on_event(defines.events.on_entity_destroyed, on_entity_destroyed)
script.on_event(defines.events.on_spider_command_completed, on_spider_command_completed)
script.on_event(defines.events.on_script_path_request_finished, on_script_path_request_finished)
script.on_event(defines.events.on_player_driving_changed_state, on_player_driving_changed_state)
script.on_event(defines.events.on_player_used_spider_remote, on_player_used_spider_remote)
