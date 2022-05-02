


local stop_group = require("script/stop-group")



-- add_train_stop: When a Global or Proxy Stop is created, find the appropriate surface group to put it in
local function add_stop(entity)
  local name = entity.backer_name
  local surface = entity.surface
  local set = global.surface_set_map[surface.index]
  
  -- Check if this surface is in a group
  if not set then
    return
  end
  
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
    return
  end
  
  if set.groups[name] then
    stop_group.remove_stop(set.groups[name], entity)
  end
end

-- Remove all stops on the given surface (prior to deleting or unlinking the surface)
local function remove_all_stops(surface)
  local stops = surface.get_train_stops{name={NAME_GLOBAL_STOP, NAME_PROXY_STOP}}
  for i=1,#stops do
    remove_stop(stops[i])
  end
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
local function add_link(origin, destination, link_schedule, link_cost, update)
  local origin_set = global.surface_set_map[origin.index]
  local destination_set = global.surface_set_map[destination.index]
  local link_entry = {schedule = link_schedule, cost = link_cost}
  if origin_set then
    if destination_set then
      -- both are already in a set
      if origin_set ~= destination_set then
        -- merge two non-overlapping sets
        -- merge link tables
        for origin_index,origin_table in destination_set.origins do
          origin_set.origins[origin_index] = origin_table
          global.surface_set_map[origin_index] = origin_set
        end
        -- add new link
        origin_set.origins[origin.index][destination.index] = link_entry
        -- TODO: merge stop groups from destination into origin
        
        update_set_limits(origin_set)
      else
        -- already in the same set. Add link stop if this link is empty or if this is an update to an existing link and is cheaper
        if update or not origin_set.origins[origin.index][destination.index] then
          if not origin_set.origins[origin.index][destination.index] or not link_cost or
                (origin_set.origins[origin.index][destination.index].cost and link_cost <= origin_set.origins[origin.index][destination.index].cost) then
            origin_set.origins[origin.index][destination.index] = link_entry
          end
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
          [destination.index] = {},  -- Destination is in the set, but there are no paths from it yet
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
  -- TODO: Delete sets if there is only one surface in it.

end


return {
  init_globals = init_globals,
  add_link = add_link, 
  remove_link = remove_link,
  add_stop = add_stop,
  add_all_stops = add_all_stops,
  remove_stop = remove_stop,
  remove_all_stops = remove_all_stops,
  update_all_limits = update_all_limits,
}
