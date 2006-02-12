/*******************************************************************************
    Team balancer game rules to check for additional unbalanced teams
    issues                                                              <br />

    (c) 2004-2006 Michiel "El Muerte" Hendriks                          <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: TeamBalanceRules.uc,v 1.4 2006/02/12 19:35:45 elmuerte Exp $ -->
*******************************************************************************/
class TeamBalanceRules extends GameRules;

/** pointer to our parent */
var mutTeamBalance mutTB;

/** lock to check if we're doing a subrequest on the player start */
var protected bool bSubReq;

/** will be called when a player changes teams, check if the team change is allowed */
function NavigationPoint FindPlayerStart( Controller Player, optional byte InTeam, optional string incomingName )
{
    local NavigationPoint res;
    local int teamid;
    if (bSubReq) // subrequest
    {
        if (mutTB.bDebug) log("DEBUG: FindPlayerStart in subrequest", name);
        bSubReq = false;
        return super.FindPlayerStart(Player, InTeam, incomingName);
    }
    if (Player == none || PlayerController(Player) == none) return super.FindPlayerStart(Player, InTeam, incomingName);
    if (mutTB.PCTeamSwitch(PlayerController(Player)))
    {
        bSubReq = true;
        if (Player.PlayerReplicationInfo.Team == none) teamid = (InTeam+1) % 2;
        else teamid = Player.PlayerReplicationInfo.Team.TeamIndex;
        res = Level.Game.FindPlayerStart(Player, teamid, incomingName);
        bSubReq = false;
        return res;
    }
    else return super.FindPlayerStart(Player, InTeam, incomingName);
}

