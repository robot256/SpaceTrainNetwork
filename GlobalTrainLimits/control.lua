


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

util = require("util")
zone_util = require("zone-util.lua")
surface_graph = require("surface-graph.lua")

NAME_GLOBAL_STOP = "global-train-stop"
NAME_PROXY_STOP = "proxy-train-stop"
NAME_ELEVATOR_STOP = "se-space-elevator-train-stop"
NAME_ELEVATOR_ENTITY = "se-space-elevator"



-- Reassign group when station is renamed
function OnEntityRenamed(event)
  local entity = event.entity
  local surface = entity.surface
  
  if entity.name == NAME_ELEVATOR_STOP then
    -- Elevator stops get renamed when they are created or when the user renames the elevator entity
    local elevator_surfaces = zone_util.find_elevator_surfaces(surface)
    if elevator_surfaces.adjacent then
      local schedule = { {station = entity.backer_name, temporary = true} }
      surface_graph.add_link(surface, elevator_surfaces.adjacent, schedule, elevator_surfaces.path_cost, true)  -- Only most recently built/renamed elevator will be sed
    end
  end
end



-- register events
local function registerEvents()
 
  -- always track built/removed train stops for duplicate name list
  entity_filters = {
    {type="name", name=NAME_GLOBAL_STOP},
    {type="name", name=NAME_PROXY_STOP},
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
  script.on_event( {defines.events.on_pre_surface_deleted, defines.events.on_pre_surface_cleared }, OnSurfaceRemoved )
  
  
  --script.on_event( defines.events.on_train_schedule_changed, OnScheduleChanged )
  script.on_event( defines.events.on_train_changed_state, OnTrainChangedState )
  
end


script.on_load(function()
  registerEvents()
end)


script.on_init(function()
  initGlobals()
  registerEvents()
end)

script.on_configuration_changed(function()
  initGlobals()
  registerEvents()
end)


if script.active_mods["gvv"] then require("__gvv__.gvv")() end
