










-- add_link: Registers two surfaces
local function add_link(origin, destination, link_schedule, link_cost)
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
        -- already in the same set. Add link stop if this link is empty
        if not origin_set.origins[origin.index][destination.index] then
          origin_set.origins[origin.index][destination.index] = link_entry
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
            [destination.index] = link_entry
          },
          [destination.index] = {
            [origin.name] = {}
          },
        },
        groups = {}
      }
      global.surface_sets[origin.index] = new_set
      global.surface_sets[destination.index] = new_set
    end
  end

end

local function update_link(link_stop, destination_surface)


end

local function remove_link(link_stop)

