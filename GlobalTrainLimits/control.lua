


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

NAME_GLOBAL_STOP = "global-train-stop"
NAME_PROXY_STOP = "proxy-train-stop"
NAME_ELEVATOR_STOP = "se-space-elevator-train-stop"
NAME_ELEVATOR_ENTITY = "se-space-elevator"




-- Crude search for matching a planet/moon surface with its orbit.
local function FindAdjacentSurface(surface)
  local results = {}
  
  local current_zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index=surface.index})
  local planet_zone
  local orbit_zone
  local other_zone
  local train_on_surface = false
  
  if (current_zone.type == "planet" or current_zone.type == "moon") and current_zone.orbit_index then
    planet_zone = current_zone
    orbit_zone = remote.call("space-exploration", "get_zone_from_zone_index", {zone_index=current_zone.orbit_index})
    train_on_surface = true
  elseif current_zone.type == "orbit" then
    local parent_zone = remote.call("space-exploration", "get_zone_from_zone_index", {zone_index=current_zone.parent_index})
    if parent_zone.type == "planet" or parent_zone.type == "moon" then
      planet_zone = parent_zone
      orbit_zone = current_zone
    end
  end
  
  if planet_zone then
    results.planet = remote.call("space-exploration", "zone_get_surface", {zone_index = planet_zone.index})
  end
  if orbit_zone then
    results.orbit = remote.call("space-exploration", "zone_get_surface", {zone_index = orbit_zone.index})
  end
  
  return results
end


local function InitStopGroup(name)
  global.StopGroups[name] = global.StopGroups[name] or {global_stops={}, proxy_stops={}, trains={}}
end


local function initGlobals()

  
  FindAllStops()

end





-- Register a Global or Proxy stop in the database
local function RegisterStop(entity)
  local name = entity.backer_name
  
  if entity.name == NAME_GLOBAL_STOP then
    if not global.GlobalStops[entity.unit_number] then
      game.print("Adding Global stop to list: "..name.." ("..entity.unit_number..") on "..entity.surface.name)
      global.GlobalStops[entity.unit_number] = {
        entity = entity,
        unit_number = entity.unit_number,
        group = name
      }
      InitStopGroup(name)
      global.StopGroups[name].global_stops[entity.unit_number] = {
        entity = entity,
        unit_number = entity.unit_number
      }
    end
  elseif entity.name == NAME_PROXY_STOP then
    if not global.ProxyStops[entity.unit_number] then
      game.print("Adding Proxy stop to list: "..name.." ("..entity.unit_number..") on "..entity.surface.name)
      global.ProxyStops[entity.unit_number] = {
        entity = entity,
        unit_number = entity.unit_number,
        group = name
      }
      InitStopGroup(name)
      global.StopGroups[name].proxy_stops[entity.unit_number] = {
        entity = entity,
        unit_number = entity.unit_number
      }
    end
  end
end

local function UnregisterStop(name, entity)
  if entity.name == NAME_GLOBAL_STOP then
    game.print("Removing Global stop from list: "..name.." ("..entity.unit_number..") on "..entity.surface.name)
    if global.StopGroups[name] then
      global.StopGroups[name].global_stops[entity.unit_number] = nil
    end
    global.GlobalStops[entity.unit_number] = nil
  elseif entity.name == NAME_PROXY_STOP then
    game.print("Removing Proxy stop from list: "..name.." ("..entity.unit_number..") on "..entity.surface.name)
    if global.StopGroups[name] then
      global.StopGroups[name].proxy_stops[entity.unit_number] = nil
    end
    global.ProxyStops[entity.unit_number] = nil
  end
end

function OnEntityCreated(event)
  local entity = event.created_entity or event.entity or event.destination
  RegisterStop(entity)
end

function OnEntityRemoved(event)
  local entity = event.entity
  UnregisterStop(entity.backer_name, entity)
end

-- remove stop references when deleting surfaces
function OnSurfaceRemoved(event)
  local surface = game.surfaces[event.surface_index]
  if surface then
    local train_stops = surface.get_train_stops{name = {NAME_GLOBAL_STOP, NAME_PROXY_STOP}}
    for _, entity in pairs(train_stops) do
      UnregisterStop(entity.backer_name, entity)
    end
  end
end

-- Reassign group when station is renamed
function OnEntityRenamed(event)
  local entity = event.entity
  if entity.name == NAME_GLOBAL_STOP then
    local oldName = event.old_name
    local newName = entity.backer_name
    local unit_number = entity.unit_number
    if global.StopGroups[oldName] then
      global.StopGroups[oldName].global_stops[unit_number] = nil
      if not next(global.StopGroups[oldName].global_stops) and not next(global.StopGroups[oldName].proxy_stops) then
        global.StopGroups[oldName] = nil
      end
    end
    InitStopGroup(newName)
    global.StopGroups[newName].global_stops[unit_number] = {
      entity = entity,
      unit_number = unit_number
    }
    global.GlobalStops[unit_number].group = newName
  elseif entity.name == NAME_PROXY_STOP then
    local oldName = event.old_name
    local newName = entity.backer_name
    local unit_number = entity.unit_number
    if global.StopGroups[oldName] then
      global.StopGroups[oldName].proxy_stops[unit_number] = nil
      if not next(global.StopGroups[oldName].global_stops) and not next(global.StopGroups[oldName].proxy_stops) then
        global.StopGroups[oldName] = nil
      end
    end
    InitStopGroup(newName)
    global.StopGroups[newName].global_stops[unit_number] = {
      entity = entity,
      unit_number = unit_number
    }
    global.ProxyStops[unit_number].group = newName
  end
end



local function ProcessTrainSchedule(train, cargo)

  -- Find which zone is planet and which is orbit, and which one we start on
  local planet_zone = nil
  local orbit_zone = nil
  local train_on_surface = nil
  
  local current_zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index=train.front_stock.surface.index})
  
  if (current_zone.type == "planet" or current_zone.type == "moon") and current_zone.orbit_index then
    planet_zone = current_zone
    orbit_zone = remote.call("space-exploration", "get_zone_from_zone_index", {zone_index=current_zone.orbit_index})
    train_on_surface = true
  elseif current_zone.type == "orbit" then
    local parent_zone = remote.call("space-exploration", "get_zone_from_zone_index", {zone_index=current_zone.parent_index})
    if parent_zone.type == "planet" or parent_zone.type == "moon" then
      planet_zone = parent_zone
      orbit_zone = current_zone
      train_on_surface = false
    end
  end
  
  local starts_on_surface = train_on_surface
  
  -- If we're in asteroids, there is no elevator
  if planet_zone == nil then
    --game.print("Can't find matching planet/moon. Currently in "..current_zone.name.." which is a "..current_zone.type)
    return
  end
  
  if orbit_zone == nil then
    --game.print("Can't find matching orbit. Currently in "..current_zone.name.." which is a "..current_zone.type)
    return
  end
  
  local upward_elevator = "[img=entity/se-space-elevator]  " .. planet_zone.name .. " ↑"
  local downward_elevator = "[img=entity/se-space-elevator]  " .. planet_zone.name .. " ↓"
  local planet_surface = remote.call("space-exploration", "zone_get_surface", {zone_index = planet_zone.index})
  local orbit_surface = remote.call("space-exploration", "zone_get_surface", {zone_index = orbit_zone.index})
  local up_record = {station = upward_elevator, wait_conditions = {{compare_type = "and",ticks = 0,type = "time"}} }
  local down_record = {station = downward_elevator, wait_conditions = {{compare_type = "and",ticks = 0,type = "time"}} }
  
  -- Scan schedule for proxy stops.
  -- If any of them are on a different surface than the train is now, try to add elevator stops to schedule
  local schedule = train.schedule
  if schedule and schedule.records and #schedule.records>0 then
    
    -- If there are already elevator commands, don't touch this train
    local proxies = {}
    for idx, record in pairs(schedule.records) do
      if record.station and (record.station == upward_elevator or record.station == downward_elevator) then
        --game.print("already added proxies in "..train.id)
        return
      end
      if record.station and global.ProxyStops[record.station] then
        table.insert(proxies, {idx,global.ProxyStops[record.station].entity} )
      end
    end
    
    -- Exit if there are no proxy stations in schedule
    if #proxies == 0 then 
      --game.print("found no proxies in "..train.id)
      return 
    end
    --game.print("found "..#proxies.." proxies in "..train.id..": "..tostring(proxies))
    
    -- For each proxy in the schedule, see if we need to change surfaces
    local idxs = 0
    local changed = false
    for _,prec in pairs(proxies) do
      local pidx = prec[1] + idxs
      local proxy = prec[2]
      
      -- New rail-target 
      local stop_on_surface = (proxy.surface == planet_surface)
      local stop_in_orbit = (proxy.surface == orbit_surface)
      
      --log("Adding proxy for station "..proxy.backer_name..","..tostring(train_on_surface)..","..
      --          tostring(stop_on_surface)..","..tostring(stop_in_orbit))
      
      if train_on_surface and stop_in_orbit then
        --log("trying to get DOWN from #"..tostring(pidx)..", which is now "..tostring(prec[1]+idxs))
        -- add a DOWN after this stop
        table.insert(schedule.records, pidx+1, util.table.deepcopy(down_record))
        idxs = idxs + 1
        changed = true
        -- get the train UP somehow
        if pidx>1 and schedule.records[pidx-1].rail then
          if pidx>2 and schedule.records[pidx-2].station and schedule.records[pidx-2].station == downward_elevator then
            -- remove the temporary stop and the previous DOWN command
            --log("trying to remove DOWN and TEMP prior to #"..tostring(pidx))
            table.remove(schedule.records, pidx-2)
            table.remove(schedule.records, pidx-2)
            idxs = -2
          else
            -- Change the temporary stop to UP
            schedule.records[pidx-1] = util.table.deepcopy(up_record)
            --log("trying to get UP for #"..tostring(pidx)..". changed temporary to UP stop")
          end
        end
        --log("\n"..serpent.block(schedule))
        
      elseif not train_on_surface and stop_on_surface then
        --log("trying to get UP from #"..tostring(pidx)..", which is now "..tostring(prec[1]+idxs))
        -- add a UP after this stop
        table.insert(schedule.records, pidx+1, util.table.deepcopy(up_record))
        idxs = idxs + 1
        changed = true
        -- get the train DOWN somehow
        if pidx>1 and schedule.records[pidx-1].rail then
          if pidx>2 and schedule.records[pidx-2].station and schedule.records[pidx-2].station == upward_elevator then
            -- remove the temporary stop and the previous UP command
            --log("trying to remove UP and TEMP prior to #"..tostring(pidx))
            table.remove(schedule.records, pidx-2)
            table.remove(schedule.records, pidx-2)
            idxs = -2
          else
            -- Change the temporary stop to DOWN
            schedule.records[pidx-1] = util.table.deepcopy(down_record)
            --log("trying to get UP for #"..tostring(pidx)..". changed temporary to DOWN stop")
          end
        end
        --log("\n"..serpent.block(schedule))
      end
    end
    
    if changed then
      --log("\nNEW SCHEDULE:\n"..serpent.block(schedule))
      if cargo then
        local t,name = cargo:match("([^,]+),([^,]+)")
        game.print("[LTN-MSS] Routing delivery of ["..t.."="..name.."] through "..current_zone.name.." space elevator.")
      else
        game.print({"","[LTN-MSS] Routing delivery through "..current_zone.name.." space elevator."})
      end
      train.schedule = schedule
    end
  end
end


--[[
function OnScheduleChanged(event)
  -- don't mess with manual schedule changes
  if event.player ~= nil then
    return
  end
  if not (event.train and event.train.valid) then
    return
  end
  ProcessTrainSchedule(event.train)
end
--]]



-- Adjust train schedules so they go through the elevator!
function OnTrainChangedState(event)
  local train = event.train
  
  if train.state == defines.train_state.wait_station and train.station ~= nil and train.station.name == 'ltn-proxy-train-stop' then
    -- Find corresponding actual LTN stop (This needs to be cached)
    local virtual_stop = nil
    for _,surface in pairs(game.surfaces) do
      local stops = surface.find_entities_filtered{name="logistic-train-stop"}
      for _,stop in pairs(stops) do
        if stop.backer_name == train.station.backer_name then
          virtual_stop = stop
          break
        end
      end
      if virtual_stop then
        break
      end
    end
    if virtual_stop then
      game.print("LTN-MSS telling LTN that train "..train.id.." arrived at "..virtual_stop.backer_name)
      remote.call("logistic-train-network", "train_arrives", train, virtual_stop)
    end
  end
end



-- Re-register proxy stations on all surfaces
function FindAllStops()
  for _,surface in pairs(game.surfaces) do
    local global_stops = surface.get_train_stops{name={NAME_GLOBAL_STOP, NAME_PROXY_STOP}}
    for _,stop in pairs(global_stops) do
      RegisterStop(stop)
    end
  end
end




-- register events
local function registerEvents()
 
  -- always track built/removed train stops for duplicate name list
  entity_filters = {
    {type="name", name=NAME_GLOBAL_STOP},
    {type="name", name=NAME_PROXY_STOP}
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
  