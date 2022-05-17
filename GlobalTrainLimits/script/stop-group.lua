
-- Create an empty stop group
local function create_group(name, set)
  return {
    name = name,
    global_stops = {},  -- index by unit_number
    proxy_stops = {},   -- index by unit_number
    trains_waiting = {},  -- index by train_id: Trains without a reservation at a global stop
    trains_pathing = {},  -- index by train_id: Trains traveling to a global stop
    trains_arriving = {}, -- index by train_id: Trains at a global stop, after the slot is opened but before they reserve it
    surface_set = set
  }
end


-- Merge group2 into group1 (modify group1 and destroy group2) (assume they have the same names)
local function merge_groups(group1, group2)
  for unit_number,global_stop_entry in pairs(group2.global_stops) do
    group1.global_stops[unit_number] = global_stop_entry
  end
  for unit_number,proxy_stop_entry in pairs(group2.proxy_stops) do
    group1.proxy_stops[unit_number] = proxy_stop_entry
  end
  if group2.trains_pathing then
    group1.trains_pathing = group1.trains_pathing or {}
    for train_id,train_entry in pairs(group2.trains_pathing) do
      group1.trains_pathing[train_id] = train_entry
    end
  end
  if group2.trains_arriving then
    group1.trains_arriving = group1.trains_arriving or {}
    for train_id,train_entry in pairs(group2.trains_arriving) do
      group1.trains_arriving[train_id] = train_entry
    end
  end
  return group1
end


-- Count the number of stops in this group
local function size(group)
  return table_size(group.global_stops) + table_size(group.proxy_stops)
end

-- Add the given proxy or global stop to the given group.
local function add_stop(group, entity)
  local unit_number = entity.unit_number
  if entity.name == NAME_GLOBAL_STOP then
    group.global_stops[unit_number] = {
      entity = entity,
      limit = nil,
      open = nil,
      trains_pathing = nil,
      trains_arriving = nil
    }
  elseif entity.name == NAME_PROXY_STOP then
    group.proxy_stops[unit_number] = {
      entity = entity
    }
    -- No wires allowed on Proxy stops
    entity.disconnect_neighbour(defines.wire_type.red)
    entity.disconnect_neighbour(defines.wire_type.green)
    -- Always set Proxy train limit 0, so that trains are held at their current stop until we modify their schedule
    entity.trains_limit = 0
  end
end

-- Remove the given proxy or global stop from the given group, based on the stop's unit_number.
local function remove_stop(group, entity)
  if entity.name == NAME_GLOBAL_STOP then
    local unit_number = entity.unit_number
    local stop = group.global_stops[unit_number]
    if stop then
      -- Forget trains currently pathing to this station
      if stop.trains_pathing then
        for id,train in pairs(stop.trains_pathing) do
          group.trains_pathing[id] = nil
        end
      end
      if stop.trains_arriving then
        for id,train in pairs(group.global_stops[unit_number].trains_arriving) do
          group.trains_arriving[id] = nil
        end
      end
      group.global_stops[unit_number] = nil
    end
  elseif entity.name == NAME_PROXY_STOP then
    group.proxy_stops[entity.unit_number] = nil
  end
end

-- Purge stop group of ones on inaccessible surfaces
local function purge_inaccessible_stops(group)
  local set = group.surface_set
  
  for stop_id,stop_entry in pairs(group.global_stops) do
    if not set.origins[stop_entry.entity.surface.index] then
      -- This stop is on a surface not in this set. Remove from set. Any trains going to it will be forgotten
      group.global_stops[stop_id] = nil
    end
  end
  
  for stop_id,proxy_stop in pairs(group.proxy_stops) do
    if not set.origins[proxy_stop.entity.surface.index] then
      -- This stop is on a surface not in this set. Remove from set.
      group.proxy_stops[stop_id] = nil
    end
  end
  
  for train_id,train_entry in pairs(group.trains_pathing) do
    if not group.global_stops[train_entry.stop_id] then
      -- Train is pathing to a stop that was removed from the group
      group.trains_pathing[train_id] = nil
    end
  end
  
  for train_id,train_entry in pairs(group.trains_arriving) do
    if not group.global_stops[train_entry.stop_id] then
      -- Train is arriving at a stop that was removed from the group
      group.trains_arriving[train_id] = nil
    end
  end
  
  for train_id,train in pairs(group.trains_waiting) do
    if not set.origins[train.carriages[1].surface.index] then
      -- Train is waiting on a surface not in this set.
      group.trains_waiting[train_id] = nil
    end
  end
  
end




-- Update the train limits on all the stops in the group
-- Global Train Limit signal: 
--   Unconnected wire = infinite
--   Negative signal = zero limit
--   Zero signal or not set = zero limit
--   Positive signal = nonzero limit (send very large number if no limit is needed on a wired stop)
local function update_limits(group, verbose)
  -- Step 1: Get the user train limit signal from every flobal stop, and the inbound train
  --         And disable the "set train limit" control behavior
  for id,stop in pairs(group.global_stops) do
    if not group.name then
      group.name = stop.entity.backer_name
    end
    if (stop.entity.get_circuit_network(defines.wire_type.green) or 
        stop.entity.get_circuit_network(defines.wire_type.red) ) then
      local changed = false
      -- Read the global limit signal (negative values treated as zero)
      stop.limit = math.max(stop.entity.get_merged_signal({type="virtual",name=NAME_GLOBAL_LIMIT_SIGNAL}), 0)
      -- Disable setting train limit through vanilla circuit
      local cb = stop.entity.get_control_behavior()
      if cb then
        cb.set_trains_limit = false
        cb.enable_disable = false
      end
      -- Set the stop train limit, taking into account en route trains that haven't reserved it yet
      local pathing_trains_count = (stop.trains_pathing and table_size(stop.trains_pathing)) or 0     -- en route, no reservation
      local arriving_trains_count = (stop.trains_arriving and table_size(stop.trains_arriving)) or 0  -- just arrived, no reservation yet
      local real_trains_count = stop.entity.trains_count   -- have reservation
      local stopped_trains_count = (stop.entity.get_stopped_train() and 1) or 0  -- stopped at station
      local duplicate_trains_count = 0
      
      -- There is a trick where a train can appear in trains_arriving and the vanilla reservations at the same time.
      -- We need to not double-count them
      if real_trains_count > 0 then
        local stop_vanilla_trains = stop.entity.get_train_stop_trains()
        for i=1,#stop_vanilla_trains do
          local train = stop_vanilla_trains[i]
          if stop.trains_arriving and stop.trains_arriving[train.id] and train.path_end_stop == stop.entity then
            -- this is a duplicate arriving train
            duplicate_trains_count = duplicate_trains_count + 1
          end
        end
      end
      
      
      -- Vanilla-pathing trains don't need a slot. They already have a reservation and will arrive even if the limit is zero
      -- Stopped trains don't need a slot. They are already at the station
      -- Mod-pathing trains don't need a slot. They haven't tried to make a reservation yet
      -- Mod-arriving trains DO need a slot, so that they can make a reservation
      -- After excluding vanilla- and mod-reservations, extra slots can stay open for vanilla reservations
      local new_limit = math.max(stop.limit - pathing_trains_count - real_trains_count - stopped_trains_count, arriving_trains_count + real_trains_count - stopped_trains_count - duplicate_trains_count)
      if new_limit ~= stop.entity.trains_limit then
        --game.print(tostring(game.tick)..": Setting stop "..tostring(id).." limit to "..tostring(new_limit))
        stop.entity.trains_limit = math.max(new_limit, 0)  -- must not provide a negative number
        changed = true
      end
      -- Calculate whether a slot is available to dispatch another train.
      -- Vanilla-pathing, stopped, mod-pathing, and mod-arriving trains all count against the additional dispatch quota
      local open = math.max(stop.limit - real_trains_count - pathing_trains_count - arriving_trains_count, 0)
      if stop.open ~= open then
        changed = true
        stop.open = open
      end
      
      if verbose or changed then
        
        -- Figure out which vanilla trains are approaching this stop
        local vanilla_string = ""
        local vanilla_trains = stop.entity.get_train_stop_trains()
        for i=1,#vanilla_trains do
          local t = vanilla_trains[i]
          local schedule = t.schedule
          if schedule.records[schedule.current].station == stop.entity.backer_name then
            if t.state == defines.train_state.on_the_path or t.state == defines.train_state.arrive_signal or t.state == defines.train_state.wait_signal or
             t.state == defines.train_state.arrive_station or t.state == defines.train_state.wait_station or t.state == defines.train_state.destination_full or
             t.state == defines.train_state.no_path then
              
              vanilla_string = vanilla_string .. " " .. tostring(t.id)..":"..tostring(t.state)
            end
          end
        end
        
        local arriving_string = ""
        if stop.trains_arriving then
          for id,t in pairs(stop.trains_arriving) do
            arriving_string = arriving_string.." "..tostring(id)..":"..tostring(t.state)
          end
        end
        log_msg(string.format("Stop %d '%s' >> {signal=%d, vanilla=%d, stopped=%d, pathing=%d, arriving=%d, duplicate=%d, new_limit=%d, open=%d}  vanilla={%s} arriving={%s}",
                              id, stop.entity.backer_name, stop.limit, real_trains_count, stopped_trains_count, pathing_trains_count,
                              arriving_trains_count, duplicate_trains_count, new_limit, stop.open, vanilla_string, arriving_string),
                LOG_DEBUG)
      end
    else
      -- Not connected to circuit network, no limit
      stop.limit = nil
      stop.open = nil
      -- Clear the stop train limit
      stop.entity.trains_limit = nil
    end
  end
end

-- Add a train that is waiting for a stop in this group (in Destination Full state)
local function add_waiting_train(group, train)
  group.trains_waiting[train.id] = train
  log_msg("Adding train "..tostring(train.id).." waiting for space at "..tostring(group.name), LOG_INFO)
end


local function set_train_teleporting(group, train)
  local id = train.id
  if group.trains_pathing[id] then
    log_msg("Started Teleporting train "..tostring(train.id).." pathing to "..tostring(group.name), LOG_INFO)
    group.trains_pathing[id].teleporting = true
  elseif group.trains_arriving[id] then
    group.trains_arriving[id].teleporting = true
  end
end

local function clear_train_teleporting(group, train)
  local id = train.id
  if group.trains_pathing[id] then
    log_msg("Finished Teleporting train "..tostring(train.id), LOG_INFO)
    group.trains_pathing[id].teleporting = nil
  elseif group.trains_arriving[id] then
    group.trains_arriving[id].teleporting = nil
  end
end


-- Remove this train from the record wherever it might be
local function remove_train(group, train_id)
  for id,stop_entry in pairs(group.global_stops) do
    stop_entry.trains_arriving[id] = nil
    stop_entry.trains_pathing[id] = nil
  end
  group.trains_pathing[id] = nil
  group.trains_waiting[id] = nil
  group.trains_arriving[id] = nil
end


-- The train has fully arrived at the global stop
local function complete_trip(group, train)
  local stop_id = group.trains_arriving[train.id].stop_id
  local stop = group.global_stops[stop_id]
  -- Remove train from arriving
  stop.trains_arriving[train.id] = nil
  group.trains_arriving[train.id] = nil
  -- Update limits now that this train has a real reservation
  --game.print("complete updating limits")
  update_limits(group)
  log_msg("Train "..tostring(train.id).." finished arriving at "..tostring(stop_id).." "..train.station.backer_name, LOG_INFO)
end


-- Send this train to the correct stop with a temporary stop
local function schedule_temp_stop(group, train)
  local entity = group.global_stops[group.trains_pathing[train.id].stop_id].entity
  local rail = entity.connected_rail
  local direction = entity.connected_rail_direction
  
  if not rail then
    log_msg("ERROR: No rail connected to station "..tostring(entity.unit_number).." "..entity.backer_name..", so Train "..tostring(train.id).." cannot path to it.", LOG_INFO)
    return
  end
  
  if rail.surface ~= train.carriages[1].surface then
    log_msg("ERROR: Train "..tostring(train.id).." is not on the same surface as stop "..tostring(group.trains_pathing[train.id].stop_id).." "..entity.backer_name.." yet.")
    return
  end
  
  local record = {rail=rail, rail_direction=direction, temporary=true, wait_conditions={{type="time", ticks=0, compare_type="and"}}}
  
  local schedule = train.schedule
  table.insert(schedule.records, schedule.current, record)
  
  log_msg("Adding temp stop to train "..tostring(train.id).." approaching stop "..tostring(entity.unit_number).." "..entity.backer_name)
  train.schedule = schedule
end


-- Add a train that is pathing to a global stop, which we might not have dispatched ourselves
local function add_pathing_train(group, train)
  -- Check if the train is already in the pathing list
  local train_id = train.id
  if train.path_end_stop then
    local stop_id = train.path_end_stop.unit_number
    if group.trains_pathing and group.trains_pathing[train_id] then
      if group.trains_pathing[train_id].stop_id ~= stop_id then
        -- Need to change registered stop for this pathing train
        log_msg("Changing registration of train "..tostring(train.id).." from stop "..tostring(group.trains_pathing[train_id].stop_id).." to stop "..tostring(stop_id).." "..train.path_end_stop.backer_name)
        local old_stop = group.global_stops[group.trains_pathing[train_id].stop_id]
        old_stop.trains_pathing[train_id] = nil
        
        group.trains_pathing[train_id] = {train=train, stop_id=stop_id, tick=game.tick}
        local new_stop = group.global_stops[stop_id]
        new_stop.trains_pathing = new_stop.trains_pathing or {}
        new_stop.trains_pathing[train_id] = train
        update_limits(group)
      else
        -- Already registered as pathing to the correct stop, do nothing
      end
    else
      -- Train has a destination stop but it is not registered with the group
      log_msg("Registering train "..tostring(train.id).." as pathing to stop "..tostring(stop_id).." "..train.path_end_stop.backer_name)
      local new_stop = group.global_stops[stop_id]
      new_stop.trains_pathing = new_stop.trains_pathing or {}
      new_stop.trains_pathing[train_id] = train
      group.trains_pathing[train_id] = {train=train, stop_id=stop_id, tick=game.tick}
      -- Schedule temp stops so the stop limit can be reset
      schedule_temp_stop(group, train)
      update_limits(group)
    end
  else
    -- Train is not pathing to a station, do nothing
  end
end



-- Loop through waiting trains and see if we can dispatch them
local function update_trains(group)
  
  -- Update arriving trains (no event is triggered when they switch from "wait at temp stop" to "wait at real stop" on the same tile)
  for id,train_entry in pairs(group.trains_arriving) do
    if train_entry.train and train_entry.train.valid then
      if train_entry.train.state == defines.train_state.wait_station then
        local station = train_entry.train.station
        if station == group.global_stops[train_entry.stop_id].entity then
          -- Train has reserved the other stop
          --game.print(tostring(game.tick)..": Tick update completing trip for arriving train "..tostring(id))
          complete_trip(group, train_entry.train)
        elseif station and station.name ~= NAME_ELEVATOR_STOP then
          -- We are stopped at the wrong station!
          log_msg("Purging train "..tostring(id).." from arriving at "..tostring(group.name).." because it is stopped at "..tostring(station.unit_number).." "..station.backer_name)
          group.global_stops[train_entry.stop_id].trains_arriving[id] = nil
          group.trains_arriving[id] = nil
        end
      else
        --game.print(tostring(game.tick)..": Tick update still waiting for arriving train "..tostring(id).." at stop "..tostring(train_entry.stop_id).." "..group.global_stops[train_entry.stop_id].entity.backer_name)
      end
    else
      log_msg("Purging invalid train "..tostring(id).." from arriving at "..tostring(group.name))
      group.global_stops[train_entry.stop_id].trains_arriving[id] = nil
      group.trains_arriving[id] = nil
    end
  end
  
  -- Make sure pathing trains are still pathing
  for id,train_entry in pairs(group.trains_pathing) do
    if train_entry.train and train_entry.train.valid then
      local state = train_entry.train.state
      if train_entry.teleporting or 
         state == defines.train_state.on_the_path or
         state == defines.train_state.arrive_signal or
         state == defines.train_state.wait_signal or
         state == defines.train_state.arrive_station or
         (state == defines.train_state.wait_station and train_entry.train.station.name == NAME_ELEVATOR_STOP)
         then
        -- Train is correctly transiting to a place
        -- TODO: Make sure it's going to *this* stop still
        
      else
        -- Train is not pathing anymore
        log_msg("Removing train "..tostring(id).." on surface "..train_entry.train.carriages[1].surface.name.." in state "..tostring(state).." which is no longer pathing to "..tostring(group.name))
        group.global_stops[train_entry.stop_id].trains_pathing[id] = nil
        group.trains_pathing[id] = nil
      end
    else
      log_msg("Purging invalid train "..tostring(id).." from pathing to "..tostring(group.name))
      group.global_stops[train_entry.stop_id].trains_pathing[id] = nil
      group.trains_pathing[id] = nil
    end
  end
  
  -- Make sure waiting trains are still waiting
  for id,train in pairs(group.trains_waiting) do
    if train and train.valid then
      if train.state ~= defines.train_state.destination_full then
        -- Train already dispatched itself somewhere else
        log_msg("Train "..tostring(id).." is no longer waiting for "..tostring(group.name))
        group.trains_waiting[id] = nil
      end
    else
      log_msg("Purging invalid train "..tostring(id).." from waiting for "..tostring(group.name))
      group.trains_waiting[id] = nil
    end
  end
  
  
  -- As long as any trains are waiting, look for open stations.
  -- Pick trains greedily based on lowest cost of travel
  while next(group.trains_waiting) do
    local best_cost = 1e15
    local best_stop = nil
    local best_stop_id = nil
    local best_train = nil
    local best_train_id = nil
    local best_link = nil
    
    for stop_id,stop in pairs(group.global_stops) do
      -- Make sure it is unlimited or has space, and is connected to a valid rail segment.
      if (not stop.open or stop.open > 0) and stop.entity.connected_rail then
        -- This stop needs a train. Find the best one
        local stop_surface = stop.entity.surface
        local stop_position = stop.entity.position
        
        -- Find the closest train to this stop, and save if it's the shortest trip overall
        for train_id,train in pairs(group.trains_waiting) do
          -- Check if there is somewhere we can send this train
          local train_surface = train.carriages[1].surface
          local train_position = train.carriages[1].position
          -- Check that this stop is accessible from the train's current surface
          local link = group.surface_set.origins[train_surface.index][stop_surface.index]
          if link then
            -- Surface is accessible. Use link cost
            local path_cost = link.cost or 0
            if link.position then
              -- Add distance to and from the link
              path_cost = path_cost + util.distance(train_position, link.position) + util.distance(link.position, stop_position)
            else
              -- No link needed, add simple distance
              path_cost = path_cost + util.distance(train_position, stop_position)
            end
            -- Save the lowest cost path
            if path_cost < best_cost then
              best_link = link
              best_cost = path_cost
              best_stop = stop
              best_stop_id = stop_id
              best_train = train
              best_train_id = train_id
              log_msg("Found better trip from surface "..train_surface.name.." to surface "..stop_surface.name.." with cost "..tostring(best_cost), LOG_DEBUG)
            end
          end
        end
      end
    end
  
    -- Dispatch the shortest stop-train pair, then look for another one
    if best_stop then
      -- Update globals and indicate that the train has a reservation
      group.trains_waiting[best_train_id] = nil
      group.trains_pathing[best_train_id] = {train=best_train, stop_id=best_stop_id, tick=game.tick}
      best_stop.trains_pathing = best_stop.trains_pathing or {}
      best_stop.trains_pathing[best_train_id] = best_train
      update_limits(group)
      
      log_msg("Dispatchng train "..tostring(best_train_id).." on "..best_train.carriages[1].surface.name.." to stop "..tostring(best_stop_id).." on "..best_stop.entity.surface.name)
      if best_link.schedule then
        -- Add link to schedule
        local schedule = best_train.schedule
        for k,record in pairs(best_link.schedule) do
          table.insert(schedule.records, schedule.current+k-1, record)
        end
        -- Set train schedule. Current stop index stays the same, but now it is the temporary elevator stop
        log_msg("Adding Elevator transit to train "..tostring(best_train_id).." to "..best_stop.entity.surface.name)
        best_train.schedule = schedule
      else
        -- Already on same surface, add temporary stop to avoid distractions
        schedule_temp_stop(group, best_train)
      end
    else
      -- No stops available for the waiting trains, try again next tick
      break
    end
  end
  
end


-- Update train id links if this train is here
local function update_train_id(group, train, old_train_id)
  if group.trains_waiting[old_train_id] then
    log_msg("Updating waiting train id "..tostring(old_train_id).." to "..tostring(train.id), LOG_DEBUG)
    local tick
    if type(group.trains_waiting[old_train_id]) == "list" then
      tick = group.trains_waiting[old_train_id].tick
    end
    group.trains_waiting[old_train_id] = nil
    group.trains_waiting[train.id] = {train=train, tick=tick}
  end
  if group.trains_pathing and group.trains_pathing[old_train_id] then
    log_msg("Updating pathing train id "..tostring(old_train_id).." to "..tostring(train.id), LOG_DEBUG)
    local stop_id = group.trains_pathing[old_train_id].stop_id
    local tick = group.trains_pathing[old_train_id].tick
    local stop = group.global_stops[stop_id]
    stop.trains_pathing[train.id] = train
    group.trains_pathing[train.id] = {train=train, stop_id=stop_id, tick=tick}
    stop.trains_pathing[old_train_id] = nil
    group.trains_pathing[old_train_id] = nil
  end
  if group.trains_arriving and group.trains_arriving[old_train_id] then
    log_msg("Updating arriving train id "..tostring(old_train_id).." to "..tostring(train.id), LOG_DEBUG)
    local stop_id = group.trains_arriving[old_train_id].stop_id
    local tick = group.trains_arriving[old_train_id].tick
    local stop = group.global_stops[stop_id]
    stop.trains_arriving[train.id] = train
    group.trains_arriving[train.id] = {train=train, stop_id=stop_id, tick=tick}
    stop.trains_arriving[old_train_id] = nil
    group.trains_arriving[old_train_id] = nil
  end
end


-- The train has arrived at the temporary stop
local function reserve_stop(group, train)
  local stop_id = group.trains_pathing[train.id].stop_id
  local stop = group.global_stops[stop_id]
  local schedule = train.schedule
  local station = schedule.records[schedule.current+1].station
  -- Move this train from pathing to arriving
  stop.trains_arriving = stop.trains_arriving or {}
  stop.trains_arriving[train.id] = train
  group.trains_arriving[train.id] = {train=train, stop_id=stop_id, tick=game.tick}
  stop.trains_pathing[train.id] = nil
  group.trains_pathing[train.id] = nil
  -- Update the limit so we have a slot but don't send anything there
  --game.print("reserve updating limits")
  update_limits(group, true)
  -- Command the train to go there before the temporary stop times out
  --game.print("reserve setting train schedule")
  table.remove(schedule.records, schedule.current)
  train.schedule = schedule
  train.go_to_station(schedule.current)
  log_msg("Opened slot for Train "..tostring(train.id).." and commanded it to station "..tostring(stop_id).." "..station)
end



return {
  create_group = create_group,
  merge_groups = merge_groups,
  size = size,
  add_stop = add_stop,
  remove_stop = remove_stop,
  purge_inaccessible_stops = purge_inaccessible_stops,
  update_limits = update_limits,
  add_waiting_train = add_waiting_train,
  add_pathing_train = add_pathing_train,
  update_trains = update_trains,
  update_train_id = update_train_id,
  schedule_temp_stop = schedule_temp_stop,
  reserve_stop = reserve_stop,
  complete_trip = complete_trip,
  remove_train = remove_train,
  set_train_teleporting = set_train_teleporting,
  clear_train_teleporting = clear_train_teleporting
}
