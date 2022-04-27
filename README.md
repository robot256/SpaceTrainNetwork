# SpaceTrainNetwork
Factorio mod in Lua to dispatch trains

Goal:
Route trains automatically through space elevator in a train system mostly governed by vanilla train limits

Problem:. When destinations on surface and orbit have same name, train will only go to ones on same surface.
Problem: elevator commands must be added manually to each schedule

Solution: Detect when train has no destinations available on this surface, and one is availabile on the other, and add elevator command

Problem: Reservation on orbit surface is not claimed until train exits elevator, so other train in orbit could claim it first.

This is the only reason why using LTN for space elevator is needed.

Solution: keep mod routing table of trains en route instead of, or in addition to, vanilla train limits.

Problem: Depots on nearest surface might be full.

Solution: use same algo as finding source material to find depot space. Reserve depot spots like pickup materials.


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
- Should there be intrasurface priority as well?
- Temporary stops? Probably not, since it makes elevators complicated


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
- 

