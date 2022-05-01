










-- add_link: Registers two surfaces
local function add_link(origin, destination, link_schedule, link_cost, update)
  local origin_set = global.surface_sets[origin.index]
  local destination_set = global.surface_sets[destination.index]
  local link_entry = {schedule = link_schedule, cost = link_cost}
  if origin_set then
    if destination_set then
      -- both are already in a set
      if origin_set ~= destination_set then
        -- merge two non-overlapping sets
        -- merge link tables
        for origin_index,origin_table in destination_set.origins do
          origin_set.origins[origin_index] = origin_table
          global.surface_sets[origin_index] = origin_set
        end
        -- TODO: merge stop groups
        -- add new link
        origin_set.origins[origin.index][destination.index] = link_entry
      else
        -- already in the same set. Add link stop if this link is empty or if this is an update to an existing link and is cheaper
        if update or not origin_set.origins[origin.index][destination.index] then
          if not link_cost or
                (origin_set.origins[origin.index][destination.index].cost and link_cost < origin_set.origins[origin.index][destination.index].cost) then
            origin_set.origins[origin.index][destination.index] = link_entry
          end
        end
      end
    else
      -- add destination to origin's set, then add link
      origin_set.origins[destination.index] = {}
      origin_set.origins[origin.index][destination.index] = link_entry
      global.surface_sets[destination.index] = origin_set
    end
  else
    if destination_set then
      -- add origin to destination's set with link
      destination_set.origins[origin.index][destination.index] = link_entry
      global.surface_sets[origin.index] = destination_set
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
      global.surface_sets[origin.index] = new_set
      global.surface_sets[destination.index] = new_set
    end
  end

end

-- remove_link: Deregister a link and split surface set if needed
local function remove_link(origin, destination)
  local origin_set = global.surface_sets[origin.index]
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
  
  -- TODO: If they are disjoint, change the set assignment in global.surface_sets for anything not connected to origin
  -- TODO: Delete sets if there is only one surface in it.

end


return {add_link = add_link, remove_link = remove_link}
