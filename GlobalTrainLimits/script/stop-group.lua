
-- Create an empty stop group
local function create_group(set)
  return {
    global_stops = {},  -- index by unit_number
    proxy_stops = {},   -- index by unit_number
    any_limited = false,
    all_limited = false,
    trains_pathing = {}, -- index by train_id, link to reserved global stop unit_number
    trains_waiting = {},  -- index by train_id
    surface_set = set,
  }
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
      trains = {}
    }
  elseif entity.name == NAME_PROXY_STOP then
    group.proxy_stops[unit_number] = {
      entity = entity
    }
  end
end

-- Remove the given proxy or global stop from the given group, based on the stop's unit_number.
local function remove_stop(group, entity)
  local unit_number = entity.unit_number
  if entity.name == NAME_GLOBAL_STOP then
    if group.global_stops[unit_number] then
      -- Forget trains currently pathing to this station
      for id,train in pairs(group.global_stops[unit_number].trains) do
        group.trains[id] = nil
      end
      group.global_stops[unit_number] = nil
    end
  elseif entity.name == NAME_PROXY_STOP then
    group.proxy_stops[unit_number] = nil
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
      local hidden_trains_count = table_size(stop.trains)  -- en route, no reservation
      local real_trains_count = stop.entity.trains_count   -- have reservation
      -- Always give slots for existing reservations.
      -- Only give extra if they are not needed by en route trains
      local new_limit = math.max(stop.limit - hidden_trains_count, real_trains_count)
      stop.entity.trains_limit = math.max(new_limit, 0)  -- must not provide a negative number
      -- Calculate how many slots to give to proxy stops (counting both en route and reserved trains) --> Not needed. Proxy stop train limit is held at 0
      local open_slots_this_stop = math.max(stop.limit - real_trains_count - hidden_trains_count, 0)
      stop.open = open_slots_this_stop
      --total_open_slots = total_open_slots + open_slots_this_stop
      --open_slots_per_surface[stop.entity.surface.index] = (open_slots_per_surface[stop.entity.surface.index] or 0) + open_slots_this_stop
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
local function add_train(group, train)
  group.trains_waiting[train.id] = train
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
      
      -- Send the train over the link a stop was found
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
        group.global_stops[best_stop_index].trains[id] = train
        update_limits(group)
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
  elseif group.trains_pathing[old_train_id] then
    game.print("Updating pathing train id "..tostring(old_train_id).." to "..tostring(train.id))
    local stop_index = group.trains_pathing[old_train_id].stop_id
    group.trains_pathing[train.id] = {train=train, stop_id=stop_index}
    group.global_stops[stop_index].trains[train.id] = train
    group.global_stops[stop_index].trains[old_train_id] = nil
    group.trains_pathing[old_train_id] = nil
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
local function complete_trip(group, train)
  local stop_id = group.trains_pathing[train.id].stop_id
  local schedule = train.schedule
  local station = schedule.records[schedule.current+1].station
  -- Remove this train from the pathing_trains lists
  group.global_stops[stop_id].trains[train.id] = nil
  group.trains_pathing[train.id] = nil
  update_limits(group)
  game.print("Opened slot for Train "..tostring(train.id).." about to go to station "..station)
end


return {
  create_group = create_group,
  size = size,
  add_stop = add_stop,
  remove_stop = remove_stop,
  update_limits = update_limits,
  add_train = add_train,
  update_trains = update_trains,
  update_train_id = update_train_id,
  schedule_temp_stop = schedule_temp_stop,
  complete_trip = complete_trip,
  clear_train = clear_train,
}
