


-- Crude search for matching a planet/moon surface with its orbit.
function find_elevator_surfaces(surface)
  local results = {}
  
  local current_zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index=surface.index})
  local planet_zone
  local orbit_zone
  local radius
  
  if (current_zone.type == "planet" or current_zone.type == "moon") and current_zone.orbit_index then
    planet_zone = current_zone
    orbit_zone = remote.call("space-exploration", "get_zone_from_zone_index", {zone_index=current_zone.orbit_index})
  elseif current_zone.type == "orbit" then
    local parent_zone = remote.call("space-exploration", "get_zone_from_zone_index", {zone_index=current_zone.parent_index})
    if parent_zone.type == "planet" or parent_zone.type == "moon" then
      planet_zone = parent_zone
      orbit_zone = current_zone
    end
  end
  
  if planet_zone then
    results.planet = remote.call("space-exploration", "zone_get_surface", {zone_index = planet_zone.index})
    radius = planet_zone.radius
  end
  if orbit_zone then
    results.orbit = remote.call("space-exploration", "zone_get_surface", {zone_index = orbit_zone.index})
  end
  
  if current_zone == planet_zone then
    results.adjacent = results.orbit
    results.start_on_surface = true
    results.path_cost = radius * ELEVATOR_COST_MULTIPLIER
  elseif current_zone == orbit_zone then
    results.adjacent = results.planet
    results.start_on_surface = false
    results.path_cost = radius/5 * ELEVATOR_COST_MULTIPLIER
  end
  
  return results
end

return {find_elevator_surfaces = find_elevator_surfaces}
