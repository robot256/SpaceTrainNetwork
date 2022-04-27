# SpaceTrainNetwork
Factorio mod in Lua to dispatch trains

This project is inspired by the famous Logistic Train Network by Optera. LTN has maintained a large number of features through many updates of the Factorio API. Some features are no longer needed, and some suggested but not practical to implement. The purpose of the Space Train Network project is to design an automatic train dispatching system from a clean sheet, utilizing the modern state of the Factorio API and incorporating exciting new compatibility features.

With the addition of Train Limits to vanilla Factorio, intelligent routing of trains on a single surface is trivial if you accept that having many waiting trains is UPS-optimal. Each provider station has a full train waiting at it, and each requester station sets its train limit to request a precise number of trains to deliver materials. There is little need to have a smaller pool of trains and have a mod dispatch them to many resources, which results in 50% more trips per train, and therefore more pathfinding computations.

The addition of train routes between surfaces by mods makes this vanilla train network impossible. There is no support for train limits or routing between surfaces, and simply setting train limits with circuits or mod logic risks conflicts and race conditions with the vanilla routing on the same surface. Furthermore, moving trains between surfaces can be expensive, both in game resources and in UPS, so maximizing the value of each transit is important. Therefore, an intelligent train dispatching system is needed that is aware of inter-surface routes and can optimize the transits taken to fulfill material requests.

Vanilla train limits let trains "reserve" stations like signal blocks, so that trains can wait for an available spot and avoid overcrowding. This does not work for trains that are teleported between surfaces, so a mod is needed to perform the same function when trains are en route from a different surface. It seems impractical to switch from mod-limit to vanilla-limit once the train has reached the same surface as the destination, so the mod must maintain control of all trains approaching a stop, even from the same surface.

To minimize inter-surface transits, once a train has changed surfaces and delivered materials, it should not automatically return entry. Instead, it should go to a depot on the new surface and wait for materials to load for the return trip. But if one surface is lacking empty trains in its depot, an empty train may need to transit to pickup materials or to wait in the other depot.

Actually performing the inter-surface transits typically requires adding special entries to the train's schedule. The dispatching mod must keep a database of the schedule entries needed to travel between each pair of surfaces. Different transits may have different in-game costs, and those should be accounted for when choosing the best source for each material. The player should also be able to assign priority values that override that cost, if particular routes are desired. 

Complications arise when connected surfaces include multiple disconnected rail networks. In the most generalized implementation, the mod would need to follow the rail paths and generate its own list of which stops are accessible from which transit points. There could be paths that start and end on the same surface, but must make multiple transits. Automatic network traversal will be important for use with the Train Tunnels mod, but is probably not needed with Space Exploration.



Routing features:
- Basic: stops can provide and/or request, or depot, or maintenance.
- Multiple networks with respective depots
- Assume all trains in a network are same length
- Detect when train in depot is low on fuel or has contamination (reach goal)
- No timeouts?
- No train length or rolling stock detection whatsoever
- Set limits on incoming trains for each stop (depot is always limit of1)
- Set priority on all stops including depots
- Priority can force intersurface transit even if a destination is available on this surface
- Should there be intrasurface priority as well. Seems logical. How to differentiate levels of priority? Perhaps each transit subtracts 100 from priority, so a priority of 200 that is 2 transits away would be treated the same as a stop on the same surface with priority 0. Or should transits be treated like distance?
- Allow stops with the same name?  This is complicated because coordinate-based temporary stops cannot be added until the train has completed its final transit.


Stop data storage:
- UID
- Name
- Surface
- Position
- Entity
- Network
- Priority
- Depot
- Train limit
- Requests
- Provisions
- Trains en route (IDs and cargo)

Dispatched train data storage:
- Train ID
- Destination stop UID

