
--[[ factorio mod sentient spiders control script created by asher_sky --]]

local ignored_entity_types = require("ignored_entity_types")

---@param message string
local function chatty_print(message)
    storage.chatty_print = true
    -- storage.chatty_print = true
    if not storage.chatty_print then return end
    game.print("[" .. game.tick .. "] " .. message)
end

---@param entity LuaEntity?
---@return string
local function get_chatty_name(entity)
    if not entity then return "" end
    local id = entity.entity_label or entity.backer_name or entity.unit_number or script.register_on_object_destroyed(entity)
    if entity.type == "character" and entity.player then
        id = entity.player.name
    end
    local name = entity.name .. " " .. id
    local color = entity.color
    if color then
        name = "[color=" .. color.r .. "," .. color.g .. "," .. color.b .. "]" .. name .. "[/color]"
    end
    return "[" .. name .. "]"
end

---@param entity LuaEntity|MapPosition|TilePosition
---@return string
local function get_chatty_position(entity)
    local position = serpent.line(entity.position or entity)
    -- if entity and entity.x and entity.y then
    --     position = string.format("[gps=%.1f,%.1f]", entity.x, entity.y)
    -- end
    if entity and entity.position then
        position = string.format("[gps=%.1f,%.1f,1,%s]", entity.position.x, entity.position.y, entity.surface and entity.surface.name or "")
    end
    return position
end

---@return Color
local function random_color()
    local clamp = 10
    return {
        r = math.random(clamp, 255 - clamp),
        g = math.random(clamp, 255 - clamp),
        b = math.random(clamp, 255 - clamp),
        -- a = math.random(clamp, 255 - clamp)
    }
end

---@param color Color
---@return Color
local function adjust_color(color)
    local min, max = -1, 1
    local r, g, b, a = color.r * 255, color.g * 255, color.b * 255, color.a and color.a * 255 or 255
    return {
        r = math.random() > 1 / 60 and r or math.min(math.max(r + math.random(min, max), 0), 255),
        g = math.random() > 1 / 60 and g or math.min(math.max(g + math.random(min, max), 0), 255),
        b = math.random() > 1 / 60 and b or math.min(math.max(b + math.random(min, max), 0), 255),
        a = a
        -- a = math.random() > 1 / 60 and a or math.min(math.max(a + math.random(min, max), 0), 255),
    }
end

---@param spidertron LuaEntity
---@param message string
local function spider_speak(spidertron, message)
    local manual_override = true
    if manual_override then return end
    if math.random() > 0.5 then return end
    storage.ignored_spidertrons = storage.ignored_spidertrons or {}
    if storage.ignored_spidertrons[spidertron.name] then return end
    local visible_to_players = {}
    for _, player in pairs(game.connected_players) do
        table.insert(visible_to_players, player.name)
    end
    local color = spidertron.color or { r = 1, g = 1, b = 1 }
    color.a = 1
    rendering.draw_text {
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
---@param force ForceID
---@param radius number
---@param path_resolution_modifier number
---@param entity_to_ignore LuaEntity?
---@param spider_was_stuck boolean?
---@param goal_entity LuaEntity?
local function request_spider_path(spidertron, start_position, goal_position, force, radius, path_resolution_modifier, entity_to_ignore, spider_was_stuck, goal_entity)
    local request_path_id = spidertron.surface.request_path {
        bounding_box = { { -0.01, -0.01 }, { 0.01, 0.01 } },
        collision_mask = { layers = { water_tile = true }, colliding_with_tiles_only = true, consider_tile_transitions = true },
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
    ---@type table<UnitNumber, PathRequestData>
    storage.request_path_ids = storage.request_path_ids or {}
    storage.request_path_ids[request_path_id] = {
        spidertron = spidertron,
        resolution = -3,
        spider_was_stuck = spider_was_stuck,
    }
    chatty_print(get_chatty_name(spidertron) .. " requested a path to " .. get_chatty_name(goal_entity) .. " " .. serpent.line(goal_position))
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
local function set_last_interacted_tick(spidertron)
    ---@type table<UnitNumber, uint>
    storage.last_interacted_tick = storage.last_interacted_tick or {}
    storage.last_interacted_tick[spidertron.unit_number] = game.tick
    chatty_print(get_chatty_name(spidertron) .. " last_interacted_tick set to [" .. game.tick .. "]")
end

---@param spidertron LuaEntity
---@return uint
local function get_last_interacted_tick(spidertron)
    storage.last_interacted_tick = storage.last_interacted_tick or {}
    return storage.last_interacted_tick[spidertron.unit_number] or 0
end

---@param spidertron LuaEntity
---@param value boolean
local function set_player_initiated_movement(spidertron, value)
    ---@type table<UnitNumber, boolean>
    storage.player_initiated_movement = storage.player_initiated_movement or {}
    storage.player_initiated_movement[spidertron.unit_number] = value
    chatty_print(get_chatty_name(spidertron) .. " player_initiated_movement set to [" .. serpent.line(value) .. "]")
end

---@param spidertron LuaEntity
---@return boolean
local function get_player_initiated_movement(spidertron)
    storage.player_initiated_movement = storage.player_initiated_movement or {}
    return storage.player_initiated_movement[spidertron.unit_number]
end

---@param spidertron LuaEntity
local function send_spider_wandering(spidertron)
    local surface = spidertron.surface
    local position = spidertron.position
    local chatty_name = get_chatty_name(spidertron)
    local player_built_entities = {}
    for i = 1, 5 do
        if player_built_entities[1] and not ignored_entity_types[player_built_entities[1].type] then break end
        local wander_position = random_position_within_range(position, 100, 500)
        ---@type EntitySearchFilters
        local find_entities_filter = {
            force = spidertron.force,
            position = wander_position,
            radius = 5,
            -- to_be_deconstructed = false,
            limit = 1,
        }
        player_built_entities = surface.find_entities_filtered(find_entities_filter)
    end
    local entity = player_built_entities[1]
    local unit_number = spidertron.unit_number
    if not unit_number then return end
    ---@type table<UnitNumber, LuaEntity>
    storage.try_again_next_tick = storage.try_again_next_tick or {}
    if not entity then
        storage.try_again_next_tick[unit_number] = spidertron
        chatty_print(chatty_name .. " did not find a wander target")
        return
    else
        storage.try_again_next_tick[unit_number] = nil
    end
    chatty_print(chatty_name .. " found a wander target: " .. get_chatty_name(entity))
    request_spider_path(spidertron, spidertron.position, entity.position, spidertron.force, 10, -4, nil, nil, entity)
end

---@param spidertron LuaEntity
local function nudge_spidertron(spidertron)
    local autopilot_destinations = spidertron.autopilot_destinations
    local destination_count = #autopilot_destinations
    local new_position = nil
    for i = 1, 5 do
        if new_position then break end
        local nearby_position = random_position_within_range(spidertron.position, 25, 50)
        local non_colliding_position = spidertron.surface.find_tiles_filtered {
            position = nearby_position,
            radius = 10,
            collision_mask = { "water_tile" },
            invert = true,
            limit = 1,
        }
        new_position = non_colliding_position and non_colliding_position[1] and non_colliding_position[1].position
    end
    -- local new_position = non_colliding_position and non_colliding_position[1] and non_colliding_position[1].position or nearby_position
    new_position = new_position or random_position_within_range(spidertron.position, 10, 30)
    chatty_print(get_chatty_name(spidertron) .. " is stuck. autopilot re-routed via " .. get_chatty_position(new_position))
    if destination_count >= 1 then
        if destination_count > 1 then
            autopilot_destinations[1] = new_position
        else
            table.insert(autopilot_destinations, 1, new_position)
        end
        request_spider_path(spidertron, new_position, autopilot_destinations[#autopilot_destinations], spidertron.force,
            10, -4, nil, true)
        spidertron.autopilot_destination = nil
        for _, destination in pairs(autopilot_destinations) do
            spidertron.add_autopilot_destination(destination)
        end
    else
        spidertron.add_autopilot_destination(new_position)
    end
end

---@param event EventData.on_script_path_request_finished
local function on_script_path_request_finished(event)
    storage.request_path_ids = storage.request_path_ids or {}
    if not storage.request_path_ids[event.id] then return end
    local path = event.path
    local path_request_data = storage.request_path_ids[event.id]
    local spidertron = path_request_data.spidertron
    local chatty_name = get_chatty_name(spidertron)
    -- local resolution = path_request_data.resolution
    local spider_was_stuck = path_request_data.spider_was_stuck
    if not spidertron and spidertron.valid then
        goto cleanup
    end
    if event.try_again_later then
        chatty_print(chatty_name .. " received [[color=yellow]try_again_later[/color]] signal from pathfinder")
        goto cleanup
    end
    if ((spidertron.speed > 0) and not spider_was_stuck) then goto cleanup end
    if not path then
        chatty_print(chatty_name .. " received [[color=red]no_path[/color]] signal from pathfinder")
        if spidertron.speed == 0 then
            nudge_spidertron(spidertron)
        end
        goto cleanup
    end
    spidertron.autopilot_destination = nil
    for _, waypoint in ipairs(path) do
        spidertron.add_autopilot_destination(waypoint.position)
    end
    chatty_print(chatty_name .. " received path data from request [" .. event.id .. "]")
    ::cleanup::
    storage.request_path_ids[event.id] = nil
end

---@param spidertron LuaEntity
---@return boolean
local function spidertron_is_idle(spidertron)
    local ignored_spidertrons = storage.ignored_spidertrons or {}
    if ignored_spidertrons[spidertron.name] then return false end
    if spidertron.speed ~= 0 then return false end
    if spidertron.follow_target then return false end
    if spider_has_active_bots(spidertron) then return false end
    return true
end

-- on_nth_tick check if any spidertrons are bored and want to go off wandering
---@param event NthTickEventData
local function on_nth_tick(event)
    for registration_number, spidertron in pairs(storage.spidertrons) do
        if not spidertron.valid then
            storage.spidertrons[registration_number] = nil
            goto next_spidertron
        end
        if not spidertron_is_idle(spidertron) then
            goto next_spidertron
        end
        if spidertron.autopilot_destinations[1] then
            nudge_spidertron(spidertron)
            goto next_spidertron
        end
        local rider = spidertron.get_driver() or spidertron.get_passenger()
        local player = rider and rider.type == "character" and rider.player or rider and rider.type == "player" and rider
        if player and player.afk_time and player.afk_time < 60 * 60 * 5 then
            goto next_spidertron
        end
        if get_last_interacted_tick(spidertron) + 60 * 60 * 5 > game.tick then
            goto next_spidertron
        end
        if (math.random(100) < 99) then
            goto next_spidertron
        end
        chatty_print(get_chatty_name(spidertron) .. " is bored and wants to go wandering")
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
        if get_player_initiated_movement(spidertron) then
            set_last_interacted_tick(spidertron)
            set_player_initiated_movement(spidertron, false)
        end
        ---@type EntitySearchFilters
        local find_entities_filter = {
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
    storage.try_again_next_tick = storage.try_again_next_tick or {}
    for id, spidertron in pairs(storage.try_again_next_tick) do
        if not spidertron.valid then
            storage.try_again_next_tick[id] = nil
            goto next_spidertron
        end
        send_spider_wandering(spidertron)
        ::next_spidertron::
    end
end

---@param spidertron LuaEntity
local function remove_following_spider(spidertron)
    storage.following_spiders = storage.following_spiders or {}
    for player_index, following_spiders in pairs(storage.following_spiders) do
        for unit_number, following_spider in pairs(following_spiders) do
            if unit_number == spidertron.unit_number then
                following_spiders[unit_number] = nil
            end
        end
    end
end

---@alias PlayerIndex integer
---@alias UnitNumber integer

---@param player LuaPlayer
---@param spidertron LuaEntity
local function add_following_spider(player, spidertron)
    ---@type table<PlayerIndex, table<UnitNumber, LuaEntity>>
    storage.following_spiders = storage.following_spiders or {}
    storage.following_spiders[player.index] = storage.following_spiders[player.index] or {}
    storage.following_spiders[player.index][spidertron.unit_number] = spidertron
end

---@param player LuaPlayer
local function relink_following_spiders(player)
    storage.following_spiders = storage.following_spiders or {}
    storage.following_spiders[player.index] = storage.following_spiders[player.index] or {}
    for unit_number, spidertron in pairs(storage.following_spiders[player.index]) do
        if spidertron and spidertron.valid then
            local follow_target = player.character or player.vehicle
            if follow_target then
                spidertron.follow_target = follow_target
            end
            set_last_interacted_tick(spidertron)
        else
            storage.following_spiders[player.index][unit_number] = nil
        end
    end
    chatty_print(get_chatty_name(player.character) .. " following spiders relinked")
end

---@param event EventData.on_player_driving_changed_state
local function on_player_driving_changed_state(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    storage.ignored_spidertrons = storage.ignored_spidertrons or {}
    storage.following_spiders = storage.following_spiders or {}
    local spidertron = event.entity and event.entity.type == "spider-vehicle" and event.entity
    if spidertron then
        set_last_interacted_tick(spidertron)
        local driver = spidertron.get_driver()
        local passenger = spidertron.get_passenger()
        if not driver and not passenger and not storage.ignored_spidertrons[spidertron.name] then
            add_following_spider(player, spidertron)
        end
    end
    relink_following_spiders(player)
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

---@param event EventData.on_player_used_spidertron_remote
local function on_player_used_spider_remote(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local spidertrons = player.spidertron_remote_selection or {}
    for _, spidertron in pairs(spidertrons) do
        if spidertron.follow_target then
            remove_following_spider(spidertron)
            local is_character, player_index = entity_is_character(spidertron.follow_target)
            if is_character and player_index then
                add_following_spider(player, spidertron)
            end
        end
        if spidertron.autopilot_destinations[1] then
            remove_following_spider(spidertron)
            set_player_initiated_movement(spidertron, true)
        end
        set_last_interacted_tick(spidertron)
    end
end

---@param event EventData.on_player_changed_surface
local function on_player_changed_surface(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    relink_following_spiders(player)
end

---@param spidertron LuaEntity
local function add_spider(spidertron)
    storage.ignored_spidertrons = storage.ignored_spidertrons or {}
    if storage.ignored_spidertrons[spidertron.name] then return end
    local registration_number = script.register_on_object_destroyed(spidertron)
    ---@type table<uint64, LuaEntity>
    storage.spidertrons = storage.spidertrons or {}
    storage.spidertrons[registration_number] = spidertron
end

---@param registration_number uint64
local function remove_spider(registration_number)
    storage.spidertrons = storage.spidertrons or {}
    storage.spidertrons[registration_number] = nil
end

local function initialize_globals()
    storage.spidertrons = {}
    for _, surface in pairs(game.surfaces) do
        for _, spidertron in pairs(surface.find_entities_filtered { type = "spider-vehicle" }) do
            if not spidertron and not spidertron.valid then goto next_spidertron end
            add_spider(spidertron)
            ::next_spidertron::
        end
    end
    ---@type table<string, boolean>
    storage.ignored_spidertrons = {
        ["companion"] = true,
        ["constructron"] = true,
    }
end

---@return string
local function random_backer_name()
    local backer_names = game.backer_names
    local index = math.random(#backer_names)
    return backer_names[index]
end

---@param event EventData.on_built_entity | EventData.on_robot_built_entity
local function on_built_entity(event)
    if event.entity.type ~= "spider-vehicle" then return end
    local spidertron = event.entity
    if not spidertron.entity_label then
        spidertron.entity_label = random_backer_name()
        chatty_print(get_chatty_name(spidertron) .. " given a backer_name")
    end
    add_spider(spidertron)
    set_last_interacted_tick(spidertron)
end

---@param event EventData.on_object_destroyed
local function on_object_destroyed(event)
    remove_spider(event.registration_number)
end

require("interface")
script.on_init(initialize_globals)
script.on_configuration_changed(initialize_globals)
script.on_nth_tick(60, on_nth_tick)
script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_built_entity, on_built_entity)
script.on_event(defines.events.on_robot_built_entity, on_built_entity)
script.on_event(defines.events.on_object_destroyed, on_object_destroyed)
script.on_event(defines.events.on_player_changed_surface, on_player_changed_surface)
script.on_event(defines.events.on_spider_command_completed, on_spider_command_completed)
script.on_event(defines.events.on_script_path_request_finished, on_script_path_request_finished)
script.on_event(defines.events.on_player_driving_changed_state, on_player_driving_changed_state)
script.on_event(defines.events.on_player_used_spidertron_remote, on_player_used_spider_remote)
