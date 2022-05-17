


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
NAME_ELEVATOR_RAIL = "se-space-elevator-straight-rail"
NAME_ELEVATOR_CURVE = "se-space-elevator-curved-rail"
NAME_GLOBAL_LIMIT_SIGNAL = "signal-global-train-limit"

ELEVATOR_COST_MULTIPLIER = 10  -- Nauvis orbit is 5000*10 = 50,000 tile cost

DEBUG = false


util = require("util")
zone_util = require("script/zone-util")
surface_graph = require("script/surface-graph")


LOG_INFO = 1
LOG_DEBUG = 2
function log_msg(msg, level)
  if not level or level < 2 or DEBUG == true then
    game.print(tostring(game.tick)..": "..msg)
    log(msg)
  end
end


local function elevator_added(entity)
  local surface = entity.surface
  local elevator_surfaces = zone_util.find_elevator_surfaces(surface)
  if elevator_surfaces.adjacent then
    local schedule = { {station = entity.backer_name, temporary = true} }
    surface_graph.add_link(surface, elevator_surfaces.adjacent, schedule, elevator_surfaces.path_cost, entity.position, true)  -- Only most recently built/renamed elevator will be used
  end
end


-- Reassign group when station is renamed
local function OnEntityRenamed(event)
  local entity = event.entity
  if entity.name == NAME_GLOBAL_STOP or entity.name == NAME_PROXY_STOP then
    -- Reassign stop groups
    surface_graph.rename_stop(entity, event.old_name)
    
  elseif entity.name == NAME_ELEVATOR_STOP then
    -- Elevator stops get renamed when they are created or when the user renames the elevator entity
    elevator_added(entity)
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
  
  elseif entity.name == NAME_ELEVATOR_ENTITY then
    -- Elevator was destroyed/removed
    local surface = entity.surface
    local elevator_surfaces = zone_util.find_elevator_surfaces(surface)
      
    -- Check if there are other elevators still linking these surfaces?
    local elevators = surface.find_entities_filtered{name=NAME_ELEVATOR_ENTITY}
    local link_restored = false
    for _,elevator in pairs(elevators) do
      if elevator ~= entity and elevator.valid then
        game.print("Elevator was removed, but there is still one left at "..util.positiontostr(elevator.position))
        -- At least one remaining elevator entity, find its stop
        local stop_one = surface.find_entities_filtered{name=NAME_ELEVATOR_STOP, position=elevator.position, radius=elevator.get_radius(), limit=1}[1]
        game.print("Adding elevator ".. stop_one.backer_name.." on "..surface.name)
        elevator_added(stop_one)  -- Only last one will be used...
        local stop_two = elevator_surfaces.adjacent.find_entities_filtered{name=NAME_ELEVATOR_STOP, position=elevator.position, radius=elevator.get_radius(), limit=1}[1]
        game.print("Adding elevator ".. stop_two.backer_name.." on "..elevator_surfaces.adjacent.name)
        elevator_added(stop_two)  -- Only last one will be used...
        link_restored = true
      end
    end
    
    if not link_restored then
      -- No remaining elevator entities
      surface_graph.remove_link(surface, elevator_surfaces.adjacent)
      surface_graph.remove_link(elevator_surfaces.adjacent, surface)
    end

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
  surface_graph.train_state_changed(event)
end

-- Watch for when train id changes as carriages are added
local function OnTrainCreated(event)
  --log("Train "..tostring(event.train.id).." created"..(event.old_train_id_1 and (" from "..tostring(event.old_train_id_1)..(event.old_train_id_2 and (" and "..tostring(event.old_train_id_2)) or "")) or ""))
  surface_graph.train_created(event)
end

-- Watch for when trains are first teleported to another surface
local function OnTrainTeleported(event)
  -- Check if this train in is transit to a global stop
  --log("Train "..tostring(event.train.id).." started teleport: "..serpent.line(event))
  surface_graph.train_teleported(event)
end

local function OnTrainTeleportFinished(event)
  --log("Train "..tostring(event.train.id).." finished teleport: "..serpent.line(event).." "..serpent.line(event.train.get_contents()))
  surface_graph.train_teleport_finished(event)
end

local function OnTrainScheduleChanged(event)
  local train = event.train
  log_msg("Train "..tostring(train.id).." on "..train.carriages[1].surface.name.." schedule changed to "..serpent.line(train.schedule))
end



local function scan_for_elevators()
  for id,surface in pairs(game.surfaces) do
    local elevator_stops = surface.find_entities_filtered{name=NAME_ELEVATOR_STOP}
    for i=1,#elevator_stops do
      elevator_added(elevator_stops[i])  -- Only last one will be used...
    end
  end
end

local function init_globals()
  surface_graph.init_globals()
  scan_for_elevators()
end


-- register events
local function register_events()
 
  -- Track Global Stops and Proxy Stops
  local entity_filters = {
    {filter="name", name=NAME_GLOBAL_STOP},
    {filter="name", name=NAME_PROXY_STOP},
    {filter="name", name=NAME_ELEVATOR_ENTITY},
  }
  script.on_event( defines.events.on_built_entity, OnEntityCreated, entity_filters )
  script.on_event( defines.events.on_robot_built_entity, OnEntityCreated, entity_filters )
  script.on_event( defines.events.on_entity_cloned, OnEntityCreated, entity_filters )
  script.on_event( defines.events.script_raised_built, OnEntityCreated, entity_filters )
  script.on_event( defines.events.script_raised_revive, OnEntityCreated, entity_filters )

  script.on_event( defines.events.on_pre_player_mined_item, OnEntityRemoved, entity_filters )
  script.on_event( defines.events.on_player_mined_entity, OnEntityRemoved, entity_filters )
  script.on_event( defines.events.on_robot_pre_mined, OnEntityRemoved, entity_filters )
  script.on_event( defines.events.on_entity_died, OnEntityRemoved, entity_filters )
  script.on_event( defines.events.script_raised_destroy, OnEntityRemoved, entity_filters )
  
  script.on_event(defines.events.on_entity_renamed, OnEntityRenamed )
  
  -- Track valid surfaces
  script.on_event( {defines.events.on_pre_surface_deleted, defines.events.on_pre_surface_cleared }, OnSurfaceRemoved )
  
  -- Track train states
  script.on_event( defines.events.on_train_changed_state, OnTrainChangedState )
  script.on_event( defines.events.on_train_created, OnTrainCreated )
  script.on_event( remote.call("space-exploration", "get_on_train_teleport_started_event"), OnTrainTeleported )
  script.on_event( remote.call("space-exploration", "get_on_train_teleport_finished_event"), OnTrainTeleportFinished )
  
  script.on_event( defines.events.on_train_schedule_changed, OnTrainScheduleChanged )
  
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
