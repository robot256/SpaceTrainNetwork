

local function InitStopGroup(name)
  global.StopGroups[name] = global.StopGroups[name] or {global_stops={}, proxy_stops={}, trains={}}
end


local function initGlobals()

  
  FindAllStops()

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


