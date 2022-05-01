


local function ProcessTrainSchedule(train, cargo)

  -- Find which zone is planet and which is orbit, and which one we start on
  local planet_zone = nil
  local orbit_zone = nil
  local train_on_surface = nil
  
  local current_zone = remote.call("space-exploration", "get_zone_from_surface_index", {surface_index=train.front_stock.surface.index})
  
  if (current_zone.type == "planet" or current_zone.type == "moon") and current_zone.orbit_index then
    planet_zone = current_zone
    orbit_zone = remote.call("space-exploration", "get_zone_from_zone_index", {zone_index=current_zone.orbit_index})
    train_on_surface = true
  elseif current_zone.type == "orbit" then
    local parent_zone = remote.call("space-exploration", "get_zone_from_zone_index", {zone_index=current_zone.parent_index})
    if parent_zone.type == "planet" or parent_zone.type == "moon" then
      planet_zone = parent_zone
      orbit_zone = current_zone
      train_on_surface = false
    end
  end
  
  local starts_on_surface = train_on_surface
  
  -- If we're in asteroids, there is no elevator
  if planet_zone == nil then
    --game.print("Can't find matching planet/moon. Currently in "..current_zone.name.." which is a "..current_zone.type)
    return
  end
  
  if orbit_zone == nil then
    --game.print("Can't find matching orbit. Currently in "..current_zone.name.." which is a "..current_zone.type)
    return
  end
  
  local upward_elevator = "[img=entity/se-space-elevator]  " .. planet_zone.name .. " ↑"
  local downward_elevator = "[img=entity/se-space-elevator]  " .. planet_zone.name .. " ↓"
  local planet_surface = remote.call("space-exploration", "zone_get_surface", {zone_index = planet_zone.index})
  local orbit_surface = remote.call("space-exploration", "zone_get_surface", {zone_index = orbit_zone.index})
  local up_record = {station = upward_elevator, wait_conditions = {{compare_type = "and",ticks = 0,type = "time"}} }
  local down_record = {station = downward_elevator, wait_conditions = {{compare_type = "and",ticks = 0,type = "time"}} }
  
  -- Scan schedule for proxy stops.
  -- If any of them are on a different surface than the train is now, try to add elevator stops to schedule
  local schedule = train.schedule
  if schedule and schedule.records and #schedule.records>0 then
    
    -- If there are already elevator commands, don't touch this train
    local proxies = {}
    for idx, record in pairs(schedule.records) do
      if record.station and (record.station == upward_elevator or record.station == downward_elevator) then
        --game.print("already added proxies in "..train.id)
        return
      end
      if record.station and global.ProxyStops[record.station] then
        table.insert(proxies, {idx,global.ProxyStops[record.station].entity} )
      end
    end
    
    -- Exit if there are no proxy stations in schedule
    if #proxies == 0 then 
      --game.print("found no proxies in "..train.id)
      return 
    end
    --game.print("found "..#proxies.." proxies in "..train.id..": "..tostring(proxies))
    
    -- For each proxy in the schedule, see if we need to change surfaces
    local idxs = 0
    local changed = false
    for _,prec in pairs(proxies) do
      local pidx = prec[1] + idxs
      local proxy = prec[2]
      
      -- New rail-target 
      local stop_on_surface = (proxy.surface == planet_surface)
      local stop_in_orbit = (proxy.surface == orbit_surface)
      
      --log("Adding proxy for station "..proxy.backer_name..","..tostring(train_on_surface)..","..
      --          tostring(stop_on_surface)..","..tostring(stop_in_orbit))
      
      if train_on_surface and stop_in_orbit then
        --log("trying to get DOWN from #"..tostring(pidx)..", which is now "..tostring(prec[1]+idxs))
        -- add a DOWN after this stop
        table.insert(schedule.records, pidx+1, util.table.deepcopy(down_record))
        idxs = idxs + 1
        changed = true
        -- get the train UP somehow
        if pidx>1 and schedule.records[pidx-1].rail then
          if pidx>2 and schedule.records[pidx-2].station and schedule.records[pidx-2].station == downward_elevator then
            -- remove the temporary stop and the previous DOWN command
            --log("trying to remove DOWN and TEMP prior to #"..tostring(pidx))
            table.remove(schedule.records, pidx-2)
            table.remove(schedule.records, pidx-2)
            idxs = -2
          else
            -- Change the temporary stop to UP
            schedule.records[pidx-1] = util.table.deepcopy(up_record)
            --log("trying to get UP for #"..tostring(pidx)..". changed temporary to UP stop")
          end
        end
        --log("\n"..serpent.block(schedule))
        
      elseif not train_on_surface and stop_on_surface then
        --log("trying to get UP from #"..tostring(pidx)..", which is now "..tostring(prec[1]+idxs))
        -- add a UP after this stop
        table.insert(schedule.records, pidx+1, util.table.deepcopy(up_record))
        idxs = idxs + 1
        changed = true
        -- get the train DOWN somehow
        if pidx>1 and schedule.records[pidx-1].rail then
          if pidx>2 and schedule.records[pidx-2].station and schedule.records[pidx-2].station == upward_elevator then
            -- remove the temporary stop and the previous UP command
            --log("trying to remove UP and TEMP prior to #"..tostring(pidx))
            table.remove(schedule.records, pidx-2)
            table.remove(schedule.records, pidx-2)
            idxs = -2
          else
            -- Change the temporary stop to DOWN
            schedule.records[pidx-1] = util.table.deepcopy(down_record)
            --log("trying to get UP for #"..tostring(pidx)..". changed temporary to DOWN stop")
          end
        end
        --log("\n"..serpent.block(schedule))
      end
    end
    
    if changed then
      --log("\nNEW SCHEDULE:\n"..serpent.block(schedule))
      if cargo then
        local t,name = cargo:match("([^,]+),([^,]+)")
        game.print("[LTN-MSS] Routing delivery of ["..t.."="..name.."] through "..current_zone.name.." space elevator.")
      else
        game.print({"","[LTN-MSS] Routing delivery through "..current_zone.name.." space elevator."})
      end
      train.schedule = schedule
    end
  end
end
