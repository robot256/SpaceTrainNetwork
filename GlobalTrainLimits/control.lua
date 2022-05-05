


-- Goal:
--   When a Proxy stop has the same name as a Logistic stop on a different surface,
--     And a train routes to the Logistic stop,
--     Replace the temporary stop to the unreachable Logistic stop with the combination of a space elevator destination
---       and a new temporary stop at the corresponding stop in orbit.
--   Intentional limitations:
--     This will only work for Logistic and Proxy stops that share an otherwise unique name.
--     This will only work for Logistic and Proxy stops on surfaces linked by a space elevator.
--     This will only work if it is guaranteed that, after going up an arbitrary space elevator, the Proxy stop is in fact reachable.



-- Maintain a list of ltn-proxy-train-stop entities, and their corresponding logistic-train-stop entities, if any

NAME_GLOBAL_STOP = "global-train-stop"
NAME_PROXY_STOP = "proxy-train-stop"
NAME_ELEVATOR_STOP = "se-space-elevator-train-stop"
NAME_ELEVATOR_ENTITY = "se-space-elevator"
NAME_GLOBAL_LIMIT_SIGNAL = "signal-global-train-limit"


util = require("util")
zone_util = require("script/zone-util")
surface_graph = require("script/surface-graph")


-- Reassign group when station is renamed
local function OnEntityRenamed(event)
  local entity = event.entity
  local surface = entity.surface
  if entity.name == NAME_GLOBAL_STOP or entity.name == NAME_PROXY_STOP then
    -- Reassign stop groups
    surface_graph.rename_stop(entity, event.old_name)
  elseif entity.name == NAME_ELEVATOR_STOP then
    -- Elevator stops get renamed when they are created or when the user renames the elevator entity
    local elevator_surfaces = zone_util.find_elevator_surfaces(surface)
    if elevator_surfaces.adjacent then
      local schedule = { {station = entity.backer_name, temporary = true} }
      surface_graph.add_link(surface, elevator_surfaces.adjacent, schedule, elevator_surfaces.path_cost, true)  -- Only most recently built/renamed elevator will be sed
    end
  end
end

-- Add global and proxy stops to a surface set if there is one
local function OnEntityCreated(event)
  local entity = event.created_entity or event.entity or event.destination
  
  if entity.name == NAME_GLOBAL_STOP or entity.name == NAME_PROXY_STOP then
    surface_graph.add_stop(entity)
  end
end

-- Remove global and proxy stops from a surface set if there is one
local function OnEntityRemoved(event)
  local entity = event.entity
  if entity.name == NAME_GLOBAL_STOP or entity.name == NAME_PROXY_STOP then
    --log("> Removing stop "..tostring(entity.unit_number).." '"..entity.backer_name.."' on "..entity.surface.name)
    surface_graph.remove_stop(entity)
  end
end


-- Tick handler to update the train limits and dispatch waiting trains
local function OnTick(event)
  surface_graph.update_all_limits()
  surface_graph.update_all_trains()
end


-- Watch for when trains are stuck waiting for a destination
local function OnTrainChangedState(event)
  --game.print(tostring(game.tick)..": Received on_train_changed_state event. train="..tostring(event.train)..", state="..tostring(event.train.state))
  local train = event.train
  if train.state == defines.train_state.destination_full then
    surface_graph.add_waiting_train(train)
  elseif train.state == defines.train_state.wait_station then
    -- if a train that was in transit is now waiting at a station, then we should remove it from the in-transit list
    surface_graph.train_state_changed(event)
  end
end

-- Watch for when train id changes as carriages are added
local function OnTrainCreated(event)
  surface_graph.train_created(event)
end

-- Watch for when trains are first teleported to another surface
local function OnTrainTeleported(event)
  -- Check if this train in is transit to a global stop
  surface_graph.train_teleported(event)
end

local function init_globals()
  surface_graph.init_globals()
end

-- register events
local function register_events()
 
  -- Track Global Stops and Proxy Stops
  entity_filters = {
    {filter="name", name=NAME_GLOBAL_STOP},
    {filter="name", name=NAME_PROXY_STOP},
  }
  script.on_event( defines.events.on_built_entity, OnEntityCreated, entity_filters )
  script.on_event( defines.events.on_robot_built_entity, OnEntityCreated, entity_filters )
  script.on_event( defines.events.on_entity_cloned, OnEntityCreated, entity_filters )
  script.on_event( defines.events.script_raised_built, OnEntityCreated, entity_filters )
  script.on_event( defines.events.script_raised_revive, OnEntityCreated, entity_filters )

  script.on_event( defines.events.on_pre_player_mined_item, OnEntityRemoved, entity_filters )
  script.on_event( defines.events.on_robot_pre_mined, OnEntityRemoved, entity_filters )
  script.on_event( defines.events.on_entity_died, OnEntityRemoved, entity_filters )
  script.on_event( defines.events.script_raised_destroy, OnEntityRemoved, entity_filters )
  
  script.on_event(defines.events.on_entity_renamed, OnEntityRenamed )
  
  -- Track valid surfaces
  script.on_event( {defines.events.on_pre_surface_deleted, defines.events.on_pre_surface_cleared }, OnSurfaceRemoved )
  
  -- Track train states
  script.on_event( defines.events.on_train_changed_state, OnTrainChangedState )
  script.on_event( defines.events.on_train_created, OnTrainCreated )
  script.on_event( remote.call("space-exploration", "get_on_space_elevator_teleported_train_event"), OnTrainTeleported )
  
  script.on_event( defines.events.on_tick, OnTick )
  
end


script.on_load(function()
  register_events()
end)


script.on_init(function()
  init_globals()
  register_events()
end)

script.on_configuration_changed(function()
  init_globals()
  register_events()
end)


if script.active_mods["gvv"] then require("__gvv__.gvv")() end
