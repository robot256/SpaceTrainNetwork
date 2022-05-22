
local surface_graph = {}

local stop_group = require("script/stop-group")

-- create_set: Make a new set with just one surface in it
function surface_graph.get_or_create_set(surface)
  local index = surface.index
  -- Make sure this surface is not already in a set
  if not global.surface_set_map[index] then
    -- make a new set for just this surface
    local new_set = {
      origins = {
        [index] = {[index] = {cost=0}},
      },
      groups = {}
    }
    table.insert(global.surface_set_list, new_set)
    global.surface_set_map[index] = new_set
    -- Find all the stops on the surface already
    surface_graph.add_all_stops(surface)
  end
  return global.surface_set_map[index]
end

-- add_waiting_train_stop: When a Global or Proxy Stop is created, find the appropriate surface group to put it in
function surface_graph.add_stop(entity)
  local name = entity.backer_name
  local surface = entity.surface
  local set = surface_graph.get_or_create_set(surface)
  
  -- Check if this surface set has a group with this name already
  if set.groups[name] then
    -- Add this stop to the group
    stop_group.add_stop(set.groups[name], entity)
  else
    -- Make a new group
    set.groups[name] = stop_group.create_group(name, set)
    stop_group.add_stop(set.groups[name], entity)
  end
end

-- Add all stops on the given surface (when linking a surface with existing stops)
function surface_graph.add_all_stops(surface)
  local stops = surface.get_train_stops{name={NAME_GLOBAL_STOP, NAME_PROXY_STOP}}
  for i=1,#stops do
    surface_graph.add_stop(stops[i])
  end
end

-- Remove a stop from whatever set group it is in
function surface_graph.remove_stop(entity)
  local name = entity.backer_name
  local surface = entity.surface
  local set = global.surface_set_map[surface.index]

  if not set then
    --log(">> Could not find surface_set for "..surface.name..", entity not removed.")
    return
  end
  
  if set.groups[name] then
    --log(">> Removing stop from group '"..name.."' on "..surface.name)
    stop_group.remove_stop(set.groups[name], entity)
    if stop_group.size(set.groups[name]) == 0 then
      set.groups[name] = nil
      --log(">> Group '"..name.."' is empty, removing from "..surface.name)
    end
  else
    --log(">> Could not find stop group for '"..name.."' on "..surface.name..", entity not removed.")
  end
end

-- Remove all stops on the given surface (prior to deleting or unlinking the surface)
function surface_graph.remove_all_stops(surface)
  local stops = surface.get_train_stops{name={NAME_GLOBAL_STOP, NAME_PROXY_STOP}}
  for i=1,#stops do
    surface_graph.remove_stop(stops[i])
  end
end

-- Rename a stop (move it to a different group)
function surface_graph.rename_stop(entity, old_name)
  local name = entity.backer_name
  local surface = entity.surface
  local set = surface_graph.get_or_create_set(surface)
  
  -- Remove this stop (by unit_number) from the old group
  if set.groups[old_name] then
    stop_group.remove_stop(set.groups[old_name], entity)
    if stop_group.size(set.groups[old_name]) == 0 then
      set.groups[old_name] = nil
    end
  end
  -- Make a new group if necessary
  -- Add this stop to the new group
  surface_graph.add_stop(entity)
end


-- Update the limits on a specific set of surfaces
local function update_set_limits(set)
  for name,group in pairs(set.groups) do
    stop_group.update_limits(group)
  end
end

-- Update all the limits in the game (performed every tick)
function surface_graph.update_all_limits()
  for i=1,#global.surface_set_list do
    update_set_limits(global.surface_set_list[i])
  end
end


-- Create the global tables if necessary
function surface_graph.init_globals()
  global.surface_set_list = global.surface_set_list or {}
  global.surface_set_map = global.surface_set_map or {}
end


-- add_link: Registers two surfaces as connected
function surface_graph.add_link(origin, destination, link_schedule, link_cost, link_position, update)
  -- Make sure each surface is in a set, probably by itself, with all its stops catalogued
  local origin_set = surface_graph.get_or_create_set(origin)
  local destination_set = surface_graph.get_or_create_set(destination)
  local link_entry = {schedule = link_schedule, cost = link_cost, position = link_position}
  
  if origin_set == destination_set then
    -- Already in the same set. Add the new link, or overwrite the old one if update=true
    if update or not origin_set.origins[origin.index][destination.index] then
      origin_set.origins[origin.index][destination.index] = link_entry
    end
  else
    -- Merge two non-overlapping sets
    -- merge link tables (since no surfaces are shared, all origins in destination_set are new to origin_set)
    for added_origin_index,added_origin_table in pairs(destination_set.origins) do
      origin_set.origins[added_origin_index] = added_origin_table
      global.surface_set_map[added_origin_index] = origin_set
    end
    -- remove destination_set from global list
    for i=1,#global.surface_set_list do
      if global.surface_set_list[i] == destination_set then
        table.remove(global.surface_set_list, i)
        break
      end
    end
    -- add new link
    origin_set.origins[origin.index][destination.index] = link_entry
    -- merge stop groups
    for name,group in pairs(destination_set.groups) do
      if origin_set.groups[name] then
        -- merge into existing group
        stop_group.merge_groups(origin_set.groups[name], group)
      else
        -- name not present in origin set, add it directly
        origin_set.groups[name] = group
      end
    end
    update_set_limits(origin_set)
  end
end


-- Recursively look for new destinations attached to this one
local function recursive_tree_search(set, start_index, found_list)
  for new_id,link in pairs(set.origins[start_index]) do
    -- Loop through all the links leaving from surface start_index
    if not found_list[new_id] then
      -- This endpoint not in the connected list yet
      found_list[new_id] = true
      -- Now add all the surfaces accessible from here too.
      recursive_tree_search(set, new_id, found_list)
    end
  end
end


-- remove_link: Deregister a link and split surface set if needed
function surface_graph.remove_link(origin, destination)
  local origin_set = surface_graph.get_or_create_set(origin)
  
  -- If there is not already a link from origin to destination, do nothing
  if not origin_set.origins[origin.index][destination.index] then
    return
  end
  
  -- Remove the link from origin to destination
  origin_set.origins[origin.index][destination.index] = nil
  
  -- If there is still a link from destination to origin, do nothing
  if origin_set.origins[destination.index][origin.index] then
    return
  end
  
  game.print(">>>>> SEPARATING SURFACES "..origin.name.." and "..destination.name.." <<<<<")
  
  -- There is no link in either direction now. Figure out of there are disjointed sets now
  local connected_to_origin = {[origin.index]=true}
  recursive_tree_search(origin_set, origin.index, connected_to_origin)
  
  -- Now we have a dictionary of all the surfaces accessible from the origin.
  -- (If there are one-way paths ending at the origin, we won't see them.)  TODO: Figure out if this matters
  
  -- Make a list of anything not connected
  local not_connected = {}
  for new_id,_ in pairs(origin_set.origins) do
    if not connected_to_origin[new_id] then
      not_connected[new_id] = true
    end
  end
  
  -- Removing one link can create at most one new set
  if next(not_connected) then
    -- Make a new set for the disjointed surfaces
    local new_set = {
      origins = {},
      groups = {}
    }
    table.insert(global.surface_set_list, new_set)
    
    -- Move the disconnected surfaces to the new set
    for new_id,_ in pairs(not_connected) do
      -- Connections in the surfaces are still valid, move link tables
      new_set.origins[new_id] = origin_set.origins[destination.index]
      origin_set.origins[destination.index] = nil
      -- Update link in global map for this surface
      global.surface_set_map[new_id] = new_set
    end
    
    -- Copy the stop groups, then purge each side of stops on the wrong surfaces
    new_set.groups = table.deepcopy(origin_set.groups)
    for name,group in pairs(origin_set.groups) do
      game.print("running purge on origin group "..name)
      stop_group.purge_inaccessible_stops(group)
    end
    for name,group in pairs(new_set.groups) do
      game.print("running purge on new group "..name)
      group.surface_set = new_set
      stop_group.purge_inaccessible_stops(group)
    end
  end
end



-- Update trains in this set waiting for dispatch
local function update_set_trains(set)
  for name,group in pairs(set.groups) do
    stop_group.update_trains(group)
  end
end

-- Update all the trains waiting for dispatch (performed every several ticks)
function surface_graph.update_all_trains()
  for i=1,#global.surface_set_list do
    update_set_trains(global.surface_set_list[i])
  end
end

-- When a train is created, update train ids in groups
function surface_graph.train_created(event)
  --game.print("Handling train_created event")
  local train = event.train
  local surface = train.carriages[1].surface
  local set = global.surface_set_map[surface.index]
  if set then
    if event.old_train_id_1 then
      for name,group in pairs(set.groups) do
        stop_group.update_train_id(group, train, event.old_train_id_1)
      end
    end
    if event.old_train_id_2 then
      for name,group in pairs(set.groups) do
        stop_group.update_train_id(group, train, event.old_train_id_2)
      end
    end
  end
end

-- When a train is teleported, and is now bound for a global stop, update the schedule
function surface_graph.train_teleported(event)
  local train = event.train
  local id = train.id
  local surface = train.carriages[1].surface
  local set = global.surface_set_map[surface.index]
  log_msg("Handling train_teleport_started event: Train "..tostring(id).." on "..surface.name.." used to be train "..tostring(event.old_train_id_1).." on "..game.surfaces[event.old_surface_index].name, LOG_DEBUG)
  if set then
    -- Aftr teleporting, always update train IDs
    for name,group in pairs(set.groups) do
      stop_group.update_train_id(group, train, event.old_train_id_1)
      stop_group.set_train_teleporting(group, train)
    end
    -- Then check if this is the last transit in the trip, and schedule waypoint to destination stop
    local schedule = train.schedule
    local station = schedule.records[schedule.current].station
    local group = set.groups[station]
    if group and group.trains_pathing[train.id] then
      stop_group.schedule_temp_stop(group, train)
    end
  end
end

function surface_graph.train_teleport_finished(event)
  local train = event.train
  local id = train.id
  local surface = train.carriages[1].surface
  local set = global.surface_set_map[surface.index]
  log_msg("Handling train_teleport_finished event: Train "..tostring(id).." on "..surface.name.." is complete.", LOG_DEBUG)
  if set then
    -- Aftr teleporting, always update train IDs
    for name,group in pairs(set.groups) do
      stop_group.clear_train_teleporting(group, train)
    end
  end
end


-- When a train arrives at a station
function surface_graph.train_state_changed(event)
  --game.print("Handling train_state_changed event")
  local train = event.train
  
  if train.state == defines.train_state.destination_full then
    if (train.front_rail and (train.front_rail.name == NAME_ELEVATOR_RAIL or train.front_rail.name == NAME_ELEVATOR_CURVE)) or 
       (train.back_rail and (train.back_rail.name == NAME_ELEVATOR_RAIL or train.back_rail.name == NAME_ELEVATOR_CURVE)) then
      -- Waiting inside the space elevator.  The train should stay in the Pathing list.
      local surface = train.carriages[1].surface
      local set = global.surface_set_map[surface.index]
      if set then
        for name,group in pairs(set.groups) do
          stop_group.set_train_teleporting(group, train)
        end
      end
    else
      -- Train says all destinations are full. Check if it's waiting for a spot at a Global Stop Group and add to list.
      local surface = train.carriages[1].surface
      local set = global.surface_set_map[surface.index]
      if set then
        local schedule = train.schedule
        local station = schedule.records[schedule.current].station
        local group = set.groups[station]
        if group then
          stop_group.add_waiting_train(group, train)
        end
      end
    end
    
  elseif train.state == defines.train_state.wait_station then
    -- Train arrived at scheduled stop, either temporary or station.
    --game.print("Train "..tostring(train.id).." is now wait_station")
    local schedule = train.schedule
    local surface = train.carriages[1].surface
    local set = global.surface_set_map[surface.index]
    if set then
      -- Temporary stop that is not the end of the schedule
      if schedule.records[schedule.current].temporary and schedule.records[schedule.current].rail and #schedule.records > schedule.current then
        --game.print("Just stopped at a temporary stop")
        local station = schedule.records[schedule.current+1].station
        local group = set.groups[station]
        if group and group.trains_pathing[train.id] then
          -- Next stop is a global stop, need to reserve it so the train will arrive at it next tick
          stop_group.reserve_stop(group, train)
        end
      
      -- Arriving at a real stop
      elseif schedule.records[schedule.current].station then
        --game.print("Just stopped at a station")
        local group = set.groups[schedule.records[schedule.current].station]
        if group and group.trains_arriving[train.id] then
          -- Arrived at a global stop. Remove train from watch lists
          stop_group.complete_trip(group, train)
        end
      end
    end
  
  elseif train.state == defines.train_state.on_the_path then
  --       (event.previous_state == defines.train_state.wait_station or
  --        event.previous_state == defines.train_state.destination_full or
  --        event.previous_state == defines.train_state.no_path or
  --        event.previuos_state == defines.train_state.manual) then
  
    -- Train just started pathing to a destination. Check if it took a reservation at a Global Stop
    local dest = train.path_end_stop
    if dest and dest.name == NAME_GLOBAL_STOP then
      -- Train is currently pathing directly to a global stop. Make sure it is on the list
      local set = global.surface_set_map[dest.surface.index]
      if set and set.groups[dest.backer_name] then
        stop_group.add_pathing_train(set.groups[dest.backer_name], train)
      end
    end
  end
end


return surface_graph
