/*******************************************************************************
	Team balancer game rules to check for additional unbalanced teams
	issues																<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: TeamBalanceRules.uc,v 1.1 2004/05/23 15:36:00 elmuerte Exp $ -->
*******************************************************************************/
class TeamBalanceRules extends GameRules;

var mutTeamBalance mutTB;

/** will be called when a player changes teams, check if the team change is allowed */
function NavigationPoint FindPlayerStart( Controller Player, optional byte InTeam, optional string incomingName )
{
	if (Player == none || PlayerController(Player) == none) return super.FindPlayerStart(Player, InTeam, incomingName);
	mutTB.PCTeamSwitch(PlayerController(Player));
	return none;
}

