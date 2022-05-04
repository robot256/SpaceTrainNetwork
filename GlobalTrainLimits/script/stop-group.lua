
-- Create an empty stop group
local function create_group(set)
  return {
    global_stops = {},  -- index by unit_number
    proxy_stops = {},   -- index by unit_number
    any_limited = false,
    all_limited = false,
    trains_waiting = {},  -- index by train_id: Trains without a reservation at a global stop
    trains_pathing = {},  -- index by train_id: Trains traveling to a global stop
    trains_arriving = {}, -- index by train_id: Trains at a global stop, after the slot is opened but before they reserve it
    surface_set = set,
  }
end


-- Merge group2 into group1 (modify group1 and destroy group2)
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


-- Update the train limits on all the stops in the group
-- Global Train Limit signal: 
--   Unconnected wire = infinite
--   Negative signal = zero limit
--   Zero signal or not set = zero limit
--   Positive signal = nonzero limit (send very large number if no limit is needed on a wired stop)
local function update_limits(group)
  --group.any_limited = false
  --group.all_limited = true
  --local total_open_slots = 0
  --local open_slots_per_surface = {}
  -- Step 1: Get the user train limit signal from every flobal stop, and the inbound train
  --         And disable the "set train limit" control behavior
  for id,stop in pairs(group.global_stops) do
    if (stop.entity.get_circuit_network(defines.wire_type.green) or 
        stop.entity.get_circuit_network(defines.wire_type.red) ) then
      -- Read the global limit signal (negative values treated as zero)
      stop.limit = math.max(stop.entity.get_merged_signal({type="virtual",name=NAME_GLOBAL_LIMIT_SIGNAL}), 0)
      --group.any_limited = true
      -- Disable setting train limit through vanilla circuit
      local cb = stop.entity.get_control_behavior()
      if cb then
        cb.set_trains_limit = false
        cb.enable_disable = false
      end
      -- Set the stop train limit, taking into account en route trains that haven't reserved it yet
      local pathing_trains_count = (stop.trains_pathing and table_size(stop.trains_pathing) or 0)  -- en route, no reservation
      local arriving_trains_count = (stop.trains_arriving and table_size(stop.trains_arriving) or 0)  -- just arrived, no reservation yet
      local real_trains_count = stop.entity.trains_count   -- have reservation
      local stopped_trains_count = (stop.entity.get_stopped_train() and 1) or 0
      -- Subtract slots for trains pathing that don't need a reservation yet. Minimum is real trains pathing, but don't count trains that are already here
      local new_limit = math.max(stop.limit - pathing_trains_count, real_trains_count - stopped_trains_count)
      new_limit = math.max(new_limit, 0)
      if new_limit ~= stop.entity.trains_limit then
        game.print(tostring(game.tick)..": Setting stop "..tostring(id).." limit to "..tostring(math.max(new_limit, 0)))
        stop.entity.trains_limit = new_limit  -- must not provide a negative number
      end
      -- Calculate whether a slot is available to dispatch another train.
      stop.open = math.max(stop.limit - real_trains_count - pathing_trains_count - arriving_trains_count, 0)
    else
      -- Not connected to circuit network, no limit
      stop.limit = nil
      stop.open = nil
      --group.all_limited = false
      -- Clear the stop train limit
      stop.entity.trains_limit = nil
    end
  end
  
  -- Step 2: Ensure that Proxy Stops have control behavior flags cleared
  for id,stop in pairs(group.proxy_stops) do
    if (stop.entity.get_circuit_network(defines.wire_type.green) or 
        stop.entity.get_circuit_network(defines.wire_type.red) ) then
      -- Disable setting train limit through vanilla circuit (there really shouldn't be any circuits attached to proxy stops, but still)
      local cb = stop.entity.get_control_behavior()
      if cb then
        cb.set_trains_limit = false
        cb.enable_disable = false
      end
    end
    -- Always set Proxy train limit 0, so that trains are held at their current stop until we modify their schedule
    -- TODO: When Proxy stops are automatically created and invisible, set the trains_limit=0 at creation and don't change it again
    stop.entity.trains_limit = 0
  end
  
end

-- Add a train that is waiting for a stop in this group (in Destination Full state)
local function add_waiting_train(group, train)
  group.trains_waiting[train.id] = train
end


-- The train has fully arrived at the global stop
local function complete_trip(group, train)
  local stop_id = group.trains_arriving[train.id].stop_id
  local stop = group.global_stops[stop_id]
  -- Remove train from arriving
  stop.trains_arriving[train.id] = nil
  if table_size(stop.trains_arriving) == 0 then
    stop.trains_arriving = nil
  end
  group.trains_arriving[train.id] = nil
  -- Update limits now that this train has a real reservation
  game.print("complete updating limits")
  update_limits(group)
  game.print("Train "..tostring(train.id).." finished arriving at "..train.station.name)
end

-- Loop through waiting trains and see if we can dispatch them
local function update_trains(group)
  -- Update waiting trains
  for id,train in pairs(group.trains_waiting) do
    if train.state ~= defines.train_state.destination_full then
      -- Train already dispatched itself somewhere else
      group.trains_waiting[id] = nil
    else
      -- Check if there is somewhere we can send this train
      local surface = train.carriages[1].surface
      local best_cost = 1e15
      local best_link = nil
      local best_stop = nil
      local best_stop_index = nil
      for unit_number,stop in pairs(group.global_stops) do
        -- Check if this stop has slots available
        if not stop.open or stop.open > 0 then
          -- Check that this stop is accessible from the train's current surface
          local link =  group.surface_set.origins[surface.index][stop.entity.surface.index]
          if link and link.cost < best_cost then
            best_link = link
            best_cost = link.cost
            best_stop = stop
            best_stop_index = unit_number
            game.print("Found best link from surface "..surface.name.." to surface "..stop.entity.surface.name)
          end
        end
      end
      
      -- Send the train over the link if a stop was found
      if best_stop then
        -- Add link to schedule
        local schedule = train.schedule
        for k,record in pairs(best_link.schedule) do
          table.insert(schedule.records, schedule.current+k-1, record)
        end
        -- Set train schedule. Current stop index stays the same, but now it is the temporary elevator stop
        game.print("Setting train "..tostring(train.id).." schedule to "..serpent.line(schedule))
        train.schedule = schedule
        group.trains_waiting[id] = nil
        group.trains_pathing[id] = {train=train, stop_id=best_stop_index}
        best_stop.trains_pathing = best_stop.trains_pathing or {}
        best_stop.trains_pathing[id] = train
        update_limits(group)
      end
    end
  end
  
  -- Update arriving trains
  for id, train_entry in pairs(group.trains_arriving) do
    if train_entry.train.state == defines.train_state.wait_station then
      if train_entry.train.station == group.global_stops[train_entry.stop_id].entity then
        -- Train has reserved the other stop
        game.print("Update_train completed trip for train "..tostring(id))
        complete_trip(group, train_entry.train)
      end
    end
  end
end


-- Update train id links if this train is here
local function update_train_id(group, train, old_train_id)
  if group.trains_waiting[old_train_id] then
    game.print("Updating waiting train id "..tostring(old_train_id).." to "..tostring(train.id))
    group.trains_waiting[old_train_id] = nil
    group.trains_waiting[train.id] = train
  end
  if group.trains_pathing and group.trains_pathing[old_train_id] then
    game.print("Updating pathing train id "..tostring(old_train_id).." to "..tostring(train.id))
    local stop_index = group.trains_pathing[old_train_id].stop_id
    local stop = group.global_stops[stop_index]
    stop.trains_pathing[train.id] = train
    group.trains_pathing[train.id] = {train=train, stop_id=stop_index}
    stop.trains_pathing[old_train_id] = nil
    group.trains_pathing[old_train_id] = nil
  end
  if group.trains_arriving and group.trains_arriving[old_train_id] then
    game.print("Updating arriving train id "..tostring(old_train_id).." to "..tostring(train.id))
    local stop_index = group.trains_arriving[old_train_id].stop_id
    local stop = group.global_stops[stop_index]
    stop.trains_arriving[train.id] = train
    group.trains_arriving[train.id] = {train=train, stop_id=stop_index}
    stop.trains_arriving[old_train_id] = nil
    group.trains_arriving[old_train_id] = nil
  end
end

-- Send this train to the correct stop with a temporary stop
local function schedule_temp_stop(group, train)
  local entity = group.global_stops[group.trains_pathing[train.id].stop_id].entity
  local rail = entity.connected_rail
  local direction = entity.connected_rail_direction
  
  local record = {rail=rail, rail_direction=direction, temporary=true, wait_conditions={{type="time", ticks=0, compare_type="and"}}}
  
  local schedule = train.schedule
  table.insert(schedule.records, schedule.current, record)
  
  game.print("Setting train "..tostring(train.id).." schedule to "..serpent.line(schedule))
  train.schedule = schedule
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
  group.trains_arriving[train.id] = {train=train, stop_id=stop_id}
  stop.trains_pathing[train.id] = nil
  if table_size(stop.trains_pathing) == 0 then
    stop.trains_pathing = nil
  end
  group.trains_pathing[train.id] = nil
  -- Update the limit so we have a slot but don't send anything there
  game.print("reserve updating limits")
  update_limits(group)
  -- Command the train to go there before the temporary stop times out
  game.print("reserve setting train schedule")
  table.remove(schedule.records, schedule.current)
  train.schedule = schedule
  train.go_to_station(schedule.current)
  game.print("Opened slot for Train "..tostring(train.id).." and commanded it to station "..station)
  if train.station then
    game.print("reserve is completing trip")
    complete_trip(group, train)
  end
end



return {
  create_group = create_group,
  merge_groups = merge_groups,
  size = size,
  add_stop = add_stop,
  remove_stop = remove_stop,
  update_limits = update_limits,
  add_waiting_train = add_waiting_train,
  update_trains = update_trains,
  update_train_id = update_train_id,
  schedule_temp_stop = schedule_temp_stop,
  reserve_stop = reserve_stop,
  complete_trip = complete_trip,
  clear_train = clear_train,
}
