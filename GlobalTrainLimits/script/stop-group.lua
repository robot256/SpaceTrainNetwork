
-- Create an empty stop group
local function create_group()
  return {
    global_stops = {},
    proxy_stops = {},
    any_limited = false,
    all_limited = false,
    trains_pathing = {},
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
      for id,train in group.global_stops[unit_number].trains do
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
  group.any_limited = false
  group.all_limited = true
  local total_open_slots = 0
  -- Step 1: Get the user train limit signal from every flobal stop, and the inbound train
  --         And disable the "set train limit" control behavior
  for id,stop in pairs(group.global_stops) do
    if stop.entity.get_circuit_network(defines.wire_type.green) or 
       stop.entity.get_circuit_network(defines.wire_type.red) then
      -- Read the global limit signal (negative values treated as zero)
      stop.limit = math.max(stop.entity.get_merged_signal({type="virtual",name="signal-global-train-limit"}), 0)
      group.any_limited = true
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
      -- Calculate how many slots to give to proxy stops (counting both en route and reserved trains)
      total_open_slots = total_open_slots + math.max(stop.limit - real_trains_count - hidden_trains_count, 0)
    else
      -- Not connected to circuit network, no limit
      stop.limit = nil
      group.all_limited = false
      -- Clear the stop train limit
      stop.entity.trains_limit = nil
    end
  end
  
  -- Step 2: Ensure that Proxy Stops have control behavior flags cleared
  for id,stop in pairs(group.proxy_stops) do
    if stop.entity.get_circuit_network(defines.wire_type.green) or 
       stop.entity.get_circuit_network(defines.wire_type.red) then
      -- Disable setting train limit through vanilla circuit
      local cb = stop.entity.get_control_behavior()
      if cb then
        cb.set_trains_limit = false
        cb.enable_disable = false
      end
    end
    -- Set train limit if there are a finite slots in all the global stops
    if group.all_limited then
      stop.entity.trains_limit = total_open_slots
    else
      stop.entity.trains_limit = nil
    end
  end
  
end

local function update_trains(group)


end

local function dispatch_train(group, train)


end


return {
  create_group = create_group,
  size = size,
  add_stop = add_stop,
  remove_stop = remove_stop,
  update_limits = update_limits,
}
