# Q: What does it mean for a spider to wander?
- Every second, there is a 2% chance that an idle spidertron will wander off to a different part of the factory. A spidertron is considered idle if all of the following conditions are true:
  - the spidertron is not moving, not following a target, and has no active robots
  - the driver (if any) has been afk for more than 5 minutes
  - the spidertron has not been interacted with for more than 5 minutes
  - the spidertron has been waiting at a player-issued waypoint for more than 5 minutes

# Q: How does a spidertron decide where to wander?
- Spidertrons choose a random location between 100 and 500 tiles away from their current location. If there is a structure with the same force as the spidertron within 5 tiles of the location, they request a path to the structure. Otherwise they try again with up to 4 additional locations. If there are still no structures near any of the locations, they try again the following tick.

# Q: Will a spidertron wander into a lake?
- No. The pathfinding algorithm knows to avoid water. However, if a spidertron is stuck trying to reach a waypoint, it will attempt to modify its own path to find a way around the obstacle. This means that even if a player gives a spidertron a waypoint on the other side of a lake, the spidertron will automatically attempt to repath to the final destination if it gets stuck.

# Q: Will a spidertron wander through a biter nest?
- No? When searching for structures to path to, certain structures like rails and power poles are ignored to prevent spiders from wandering too far from the main factory area or too near any active combat zones. However, if a spidertron finds a structure to wander to and there are biters between its current position and the structure, it is possible that the spidertron will pathfind through the biters. See the [list of ignored_entity_types on github](https://github.com/jingleheimer-schmidt/sentient_spiders/blob/2fa9c3fff8bf30d968d349e0cc0503640161b04d/ignored_entity_types.lua).

# Q: How do the spidertrons follow the player?
- When a player exits a spidertron, the spidertron will attempt to add the player's character as its follow_target. When a player enters a vehicle, any spidertrons that were following the player character will update to follow the vehicle, and any spidertrons that were following the vehicle will update to follow the player character when they exit. Spidertrons that were following a player that changed surfaces will re-follow the player when they return to the surface. 

# Q: What happens if a player exits a spidertron while another player is still in it?
- The spidertron will only follow the last player to exit the spidertron, when there are no remaining drivers or passengers. 

# Q: How do I get a spidertron to stay still?
- Since a spidertron will not start wandering around if it has a target it is following, you can order the spidertron to follow a vehicle that is not moving to keep it still in one place. If you place a spidertron and don't want it to potentially wander off, you can enter and exit the spidertron to make it follow you. Two spidertrons may also be set as eachothers target to keep them both still.

# Q: Are there any spidertrons that are ignored by this mod?
- Yes. By default Constructrons from the Constructron-Continued mod, and Companions from the Companion Drones mod, are ignored. Mod authors can add their own spidertrons to the ignore list using the provided [remote interface](https://github.com/jingleheimer-schmidt/sentient_spiders/blob/2fa9c3fff8bf30d968d349e0cc0503640161b04d/interface.lua), or by making a post on the discussion page.

# Q: Will this mod impact game performance?
- This mod should have no noticeable impact on game performance FPS/UPS. The mod has been structured to be lightweight and performant, and all pathfinding is performed by the game at low priority. 