


local stop_group = require("script/stop-group")

-- create_set: Make a new set with just one surface in it
local function get_or_create_set(surface)
  local index = surface.index
  -- Make sure this surface is not already in a set
  if not global.surface_set_map[index] then
    -- make a new set for just this surface
    local new_set = {
      origins = {
        [index] = {[index] = {schedule = nil, cost = 0}},
      },
      groups = {}
    }
    table.insert(global.surface_set_list, new_set)
    global.surface_set_map[index] = new_set
  end
  return global.surface_set_map[index]
end

-- add_waiting_train_stop: When a Global or Proxy Stop is created, find the appropriate surface group to put it in
local function add_stop(entity)
  local name = entity.backer_name
  local surface = entity.surface
  local set = get_or_create_set(surface)
  
  -- Check if this surface set has a group with this name already
  if set.groups[name] then
    -- Add this stop to the group
    stop_group.add_stop(set.groups[name], entity)
  else
    -- Make a new group
    set.groups[name] = stop_group.create_group(set)
    stop_group.add_stop(set.groups[name], entity)
  end
end

-- Add all stops on the given surface (when linking a surface with existing stops)
local function add_all_stops(surface)
  local stops = surface.get_train_stops{name={NAME_GLOBAL_STOP, NAME_PROXY_STOP}}
  for i=1,#stops do
    add_stop(stops[i])
  end
end

-- Remove a stop from whatever set group it is in
local function remove_stop(entity)
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
local function remove_all_stops(surface)
  local stops = surface.get_train_stops{name={NAME_GLOBAL_STOP, NAME_PROXY_STOP}}
  for i=1,#stops do
    remove_stop(stops[i])
  end
end

-- Rename a stop (move it to a different group)
local function rename_stop(entity, old_name)
  local name = entity.backer_name
  local surface = entity.surface
  local set = get_or_create_set(surface)
  
  -- Remove this stop (by unit_number) from the old group
  if set.groups[old_name] then
    stop_group.remove_stop(set.groups[old_name], entity)
    if stop_group.size(set.groups[old_name]) == 0 then
      set.groups[old_name] = nil
    end
  end
  -- Make a new group if necessary
  -- Add this stop to the new group
  add_stop(entity)
end


-- Update the limits on a specific set of surfaces
local function update_set_limits(set)
  for name,group in pairs(set.groups) do
    stop_group.update_limits(group)
  end
end

-- Update all the limits in the game (performed every tick)
local function update_all_limits()
  for i=1,#global.surface_set_list do
    update_set_limits(global.surface_set_list[i])
  end
end


-- Create the global tables if necessary
local function init_globals()
  global.surface_set_list = global.surface_set_list or {}
  global.surface_set_map = global.surface_set_map or {}
end


-- add_link: Registers two surfaces
local function add_link(origin, destination, link_schedule, link_cost, link_position, update)
  local origin_set = global.surface_set_map[origin.index]
  local destination_set = global.surface_set_map[destination.index]
  local link_entry = {schedule = link_schedule, cost = link_cost, position = link_position}
  if origin_set then
    if destination_set then
      -- both are already in a set
      if origin_set ~= destination_set then
        -- Merge two non-overlapping sets
        -- merge link tables
        for added_origin_index,added_origin_table in pairs(destination_set.origins) do
          origin_set.origins[added_origin_index] = added_origin_table
          global.surface_set_map[added_origin_index] = origin_set
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
      else
        -- Already in the same set. Use this link stop if no link in this direction, or if this is cheaper
        if update or not origin_set.origins[origin.index][destination.index] then
          --if not origin_set.origins[origin.index][destination.index] or not link_cost or
          --      (origin_set.origins[origin.index][destination.index].cost and 
          --       link_cost <= origin_set.origins[origin.index][destination.index].cost) then
            origin_set.origins[origin.index][destination.index] = link_entry
          --end
        end
      end
    else
      -- add destination to origin's set, then add link
      origin_set.origins[destination.index] = {}
      origin_set.origins[origin.index][destination.index] = link_entry
      global.surface_set_map[destination.index] = origin_set
      add_all_stops(destination)
      update_set_limits(origin_set)
    end
  else
    if destination_set then
      -- add origin to destination's set with link
      destination_set.origins[origin.index][destination.index] = link_entry
      global.surface_set_map[origin.index] = destination_set
      add_all_stops(origin)
      update_set_limits(destination_set)
    else
      -- make new set with origin and destination
      local new_set = {
        origins = {
          [origin.index] = {
            [destination.index] = link_entry  -- There is a path from origin to destination
          },
          [destination.index] = {  -- Destination is in the set, but there are no paths from it yet
            [destination.index] = {cost=0}
          },
        },
        groups = {}
      }
      table.insert(global.surface_set_list, new_set)
      global.surface_set_map[origin.index] = new_set
      global.surface_set_map[destination.index] = new_set
      add_all_stops(origin)
      add_all_stops(destination)
      update_set_limits(new_set)
    end
  end

end

-- remove_link: Deregister a link and split surface set if needed
local function remove_link(origin, destination)
  local origin_set = global.surface_set_map[origin.index]
  if not origin_set[origin.index][destination.index] then
    return
  end
  
  -- Remove the link
  origin_set[origin.index][destination.index] = nil
  
  -- Now figure out if this surface pair is still connected
  if origin_set[destination.index][origin.index] then
    return
  end
  
  -- There is no link in either direction now. Figure out of there are disjointed sets now
  -- make a new set for the destination and its connections, to use if 
  local destination_set = {
    origins = {
      [destination.index] = {}
    },
    groups = {}
  }
  
  -- TODO: Figure out how to do an efficient graph search
  
  -- TODO: If they are disjoint, change the set assignment in global.surface_set_map for anything not connected to origin
  
end





-- Update trains in this set waiting for dispatch
local function update_set_trains(set)
  for name,group in pairs(set.groups) do
    stop_group.update_trains(group)
  end
end

-- Update all the trains waiting for dispatch (performed every several ticks)
local function update_all_trains()
  for i=1,#global.surface_set_list do
    update_set_trains(global.surface_set_list[i])
  end
end

-- When a train is created, update train ids in groups
local function train_created(event)
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
local function train_teleported(event)
  --game.print("Handling train_teleported event")
  local train = event.train
  local id = train.id
  local surface = train.carriages[1].surface
  local set = global.surface_set_map[surface.index]
  if set then
    -- Aftr teleporting, always update train IDs
    for name,group in pairs(set.groups) do
      stop_group.update_train_id(group, train, event.old_train_id_1)
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


-- When a train arrives at a station
local function train_state_changed(event)
  --game.print("Handling train_state_changed event")
  local train = event.train
  
  if train.state == defines.train_state.destination_full then
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
    
  elseif train.state == defines.train_state.wait_station then
    -- Train arrived at scheduled stop, either temporary or station.
    --game.print("Train "..tostring(train.id).." is now wait_station")
    local schedule = train.schedule
    local surface = train.carriages[1].surface
    local set = global.surface_set_map[surface.index]
    if set then
      -- Temporary stop that is not the end of the schedule
      if schedule.records[schedule.current].temporary and #schedule.records > schedule.current then
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


return {
  init_globals = init_globals,
  add_link = add_link, 
  remove_link = remove_link,
  add_stop = add_stop,
  add_all_stops = add_all_stops,
  remove_stop = remove_stop,
  remove_all_stops = remove_all_stops,
  rename_stop = rename_stop,
  update_all_limits = update_all_limits,
  update_all_trains = update_all_trains,
  train_created = train_created,
  train_teleported = train_teleported,
  train_state_changed = train_state_changed,
}
