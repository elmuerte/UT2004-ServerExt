/*******************************************************************************
	Team balancer mutator												<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: mutTeamBalance.uc,v 1.4 2004/05/25 20:17:21 elmuerte Exp $ -->
*******************************************************************************/
class mutTeamBalance extends Mutator;

/** to reduce typecasting */
var protected TeamGame TeamGame;
/** used to check for reserved slots */
var protected SlotManager SlotManager;

/** announce this mutator to the master server */
var(Config) config bool bAnnounce;

/**
	number seconds since the beginning of the game that the team balancer will
	remain inactive.
*/
var(Config) config float fLingerTime;
/** if true the team balancer is active */
var protected bool bActive;

/** minimum difference between team sizes before actions are taken */
var(Config) config int iSizeThreshold;
/** delay in seconds before automatic rebalancing takes effect */
var(Config) config float fTeamBalanceDelay;

/** don't balance team when the smalles team is winning */
var(Config) config bool bIgnoreWinning;
/**
	difference in teamscore before it's considered winning (used when checking
	if the smallest team is winning), should be 0 or less because with -1 the
	score difference has to be at least 2
*/
var(Config) config float fTeamScoreThreshold;
/** don't perform automatic balance fixing (onjoin/onleave/etc.) */
var(Config) config bool bOnlyBalanceOnRequest;
/** don't balance players in reserved slots, this requires the ReservedSlots
	addon of ServerExt */
var(Config) config bool bIgnoreReservedSlots;
/** if set only administrators can balance the teams via the mutate command */
var(Config) config bool bOnlyAdminBalance;

/** bots will balance the teams as much as possible */
var(BotBalance) config bool bBotsBalance;
/** add bots if there are not enough bots */
var(BotBalance) config bool bAddBots;
/**
	absolute maximum number of bots to add, -1 will use the map's max player
	count (corrented with the current player count), -2 will use the map's min
	player count
*/
var(BotBalance) config int iMaxBots;

/** if a player switches team and it unbalances the team switch the player back,
	if this is not set the default balacing will be applied */
var(PlayerBalance) config bool bSwitchPlayersBack;
/**
	Balance players based on their join time, the newest players are balanced
	first.
*/
var(PlayerBalance) config bool bBalanceNewest;
/**
	Balance players based on their gaming performance, their performance is
	defined by their score/death ration. if neither bBalanceWorst or bBalanceNewest
	is set random players will be balanced
*/
var(PlayerBalance) config bool bBalanceWorst;

/** player team history, used to check if a player changed teams */
struct TeamRecordEntry
{
	var PlayerController PC;
	var int team;
};
/** list with playercontrollers and their "old" team id */
var array<TeamRecordEntry> TeamRecords;

//!Localization
var localized string msgNotUnbalanced, msgAdminRequired, PIdesc[14], PIhelp[14],
	PIgroup;

function PreBeginPlay()
{
	local TeamBalanceRules TBR;
	super.PreBeginPlay();
	TeamGame = TeamGame(Level.Game);
	if (TeamGame == none)
	{
		Error("Current game is NOT a team game type");
	}
	if (bIgnoreReservedSlots)
	{
		foreach AllActors(class'SlotManager', SlotManager) break;
	}
	TBR = Spawn(class'TeamBalanceRules');
	TBR.mutTB = self;
	Level.Game.AddGameModifier(TBR);
	if (fLingerTime < 0.01) bActive = true;
	else {
		bActive = false;
		SetTimer(fLingerTime, false);
	}
}

function Mutate(string MutateString, PlayerController Sender)
{
	super.Mutate(MutateString, Sender);
	if (!bActive) return;
	if (Level.Game.bGameEnded) return;
	if (MutateString ~= "balance")
	{
		if (bOnlyAdminBalance && !Level.Game.AccessControl.IsAdmin(Sender))
		{
			Sender.TeamMessage(none, msgAdminRequired, 'None');
			return;
		}
		if (!OddTeams())
		{
			Sender.TeamMessage(none, msgNotUnbalanced, 'None');
			return;
		}
		Balance();
	}

	/*
	else if (Left(MutateString, 3) ~= "bot")
	{
		AddBotToTeam(TeamGame.Teams[int(Mid(MutateString, 3))]);
	}
	*/
}

/** check if a player requested a team in an unbalanced state */
function ModifyLogin(out string Portal, out string Options)
{
	local int rteam, i;
	super.ModifyLogin(Portal, Options);
	if (!bActive) return;
	if (bOnlyBalanceOnRequest) return;
	if (Level.Game.bGameEnded) return;

	rteam = TeamGame.GetIntOption(Options, "team", 255);
	if (rteam == 255) return; // no team requested, let the system handle it
	if (rteam == 0) i = 1;
	else i = -1;
	if (OddTeams(i))
	{
		Options = repl(Options, "team="$rteam, "team=255"); // system will even the odds
	}
}

/** check for unbalanced teams whena player quits */
function NotifyLogout(Controller Exiting)
{
	local int i;
	super.NotifyLogout(Exiting);
	if (!bActive) return;
	if (bOnlyBalanceOnRequest) return;
	if (Level.Game.bGameEnded) return;
	if (PlayerController(Exiting) == none) return;

	if (Exiting.PlayerReplicationInfo.Team.TeamIndex == 0) i = -1;
	else i = 1;
	if (OddTeams(i))
	{
		if (fTeamBalanceDelay < 0.5) Balance();
		else SetTimer(fTeamBalanceDelay, false);
	}
}

/** for the delayed balance call */
event Timer()
{
	if (!bActive)
	{
		bActive = true;
		return;
	}
	if (Level.Game.bGameEnded) return;
	if (!OddTeams()) return; // check again
	Balance();
}

/** check if a PC switched teams and if the switch is allowed */
function PCTeamSwitch(PlayerController PC)
{
	local int i;
	if (!bActive) return;
	for (i = 0; i < TeamRecords.length; i++)
	{
		if (TeamRecords[i].PC == PC) break;
	}
	if (i == TeamRecords.length)
	{
		TeamRecords.length = i+1;
		TeamRecords[i].PC = PC;
		//TeamRecords[i].Team = TeamRecords[i].PC.PlayerReplicationInfo.Team.TeamIndex;
		TeamRecords[i].Team = -1;
	}
	if (TeamRecords[i].Team != TeamRecords[i].PC.PlayerReplicationInfo.Team.TeamIndex)
	{
		if (OddTeams())
		{
			log("DEBUG: team change in an unbalanced game", name);
			if (!bSwitchPlayersBack)
			{
				if (fTeamBalanceDelay < 0.5) Balance();
				else SetTimer(fTeamBalanceDelay, false);
			}
			else {
				if (!IsSmallest(TeamRecords[i].PC.PlayerReplicationInfo.Team.TeamIndex))
				{
					log("DEBUG: force player to old team", name);
					TeamRecords[i].PC.ServerChangeTeam(TeamRecords[i].Team);
					return;
				}
			}
		}
		TeamRecords[i].Team = TeamRecords[i].PC.PlayerReplicationInfo.Team.TeamIndex;
	}
}

/** return true when the teams are not even, incTeamX modifies the team difference
	with it's value. So, incTeamX should be 1 for Team 0 and -1 for Team 1 */
function bool OddTeams(optional int incTeamX)
{
	local int i;
	local float j;
	i = TeamGame.Teams[0].Size - TeamGame.Teams[1].Size + incTeamX;
	if (i == 0) return false;
	log("DEBUG: difference = "$i@"team 0:"@TeamGame.Teams[0].Size@"team 1:"@TeamGame.Teams[1].Size@"incTeamX:"@incTeamX, name);
	if (!bIgnoreWinning)
	{
		j = TeamGame.Teams[0].Score - TeamGame.Teams[1].Score;
		if (i < 0 && j+fTeamScoreThreshold > 0) return false;
		if (i > 0 && j-fTeamScoreThreshold < 0) return false;
	}
	return (Abs(i) >= iSizeThreshold);
}

/** return true of the TeamIndex is the smallest team */
function bool IsSmallest(int TeamIndex)
{
	return TeamGame.Teams[TeamIndex].Size <= TeamGame.Teams[(TeamIndex + 1) % 2].Size;
}

/** perform the balancing */
function Balance()
{
	local UnrealTeamInfo target, source;
	local int diff, i, j;
	local Controller C;
	local PlayerController PC;
	local array<PlayerController> PCs;

	log("Balancing teams...", name);
	log("STAGE 0", name);
	if (TeamGame.Teams[0].Size < TeamGame.Teams[1].Size)
	{
		target = TeamGame.Teams[0];
		source = TeamGame.Teams[1];
	}
	else {
		target = TeamGame.Teams[1];
		source = TeamGame.Teams[0];
	}
	diff = (source.size - target.size) / 2;
	if (diff == 0) return;

	log("STAGE 1 - diff = "$diff, name);
	if (bBotsBalance && (TeamGame.MinPlayers > 0 || TeamGame.NumBots > 0))
	{
		if (bAddBots)
		{
			log("STAGE 1a - diff = "$diff, name);
			i = diff - TeamGame.NumBots;
			j = iMaxBots;
			switch (j)
			{
				case -1:	j = Level.IdealPlayerCountMax-TeamGame.NumPlayers;
				case -2:	j = Level.IdealPlayerCountMin-TeamGame.NumPlayers;
			}
			j -= TeamGame.NumBots;
			log("DEBUG: iMaxBots = "$j, name);
			i = min(i, j);
			if (i > 0)
			{
				log("DEBUG: adding"@i@"bots", name);
				TeamGame.AddBots(i);
				diff -= i;
			}
		}
		// rearrage bots
		log("STAGE 1b - diff = "$diff, name);
		for (C = Level.ControllerList; C != none; C = C.nextController)
		{
			if (C.PlayerReplicationInfo.bBot && C.PlayerReplicationInfo.Team == source)
			{
				if (IsKeyPlayer(C)) continue; // prevent switch when carring

				log("DEBUG: force team change for bot"@C.PlayerReplicationInfo.PlayerName, name);
				if (TeamGame.ChangeTeam(C, target.TeamIndex, true))
				{
					if (C.Pawn != none) C.Pawn.PlayerChangedTeam();
					diff--;
				}
			}
			if (diff <= 0) return;
		}
	}
	// rearange humans
	log("STAGE 2a - diff = "$diff, name);
	for (C = Level.ControllerList; C != none; C = C.nextController)
	{
		if (C.bIsPlayer && !C.PlayerReplicationInfo.bBot && C.PlayerReplicationInfo.Team == source)
		{
			if (IsKeyPlayer(C)) continue; // prevent switch when carring
			if (bIgnoreReservedSlots)
			{
				if (IsReservedSlot(PlayerController(C))) continue;
			}
			PCs[PCs.length] = PlayerController(C);
		}
	}
	log("STAGE 2b - diff = "$diff, name);
	// sort the list
	for (i = 0; i < PCs.length-1; i++)
	{
		for (j = i+1; j < PCs.length; j++)
		{
			if (bBalanceNewest)
			{
				if (PCs[i].PlayerReplicationInfo.StartTime < PCs[j].PlayerReplicationInfo.StartTime)
				{
					PC = PCs[i];
					PCs[i] = PCs[j];
					PCs[j] = PC;
				}
			}
			else if (bBalanceWorst)
			{
				if (PCs[i].PlayerReplicationInfo.Score*1000/(PCs[i].PlayerReplicationInfo.Deaths+1) >
					PCs[j].PlayerReplicationInfo.Score*1000/(PCs[j].PlayerReplicationInfo.Deaths+1))
				{
					PC = PCs[i];
					PCs[i] = PCs[j];
					PCs[j] = PC;
				}
			}
			else if (frand() > 0.5)
			{
				PC = PCs[i];
				PCs[i] = PCs[j];
				PCs[j] = PC;
			}
		}
	}
	for (i = 0; i < PCs.length; i++)
	{
		log("DEBUG: force team change for player"@PCs[i].PlayerReplicationInfo.PlayerName, name);
		PCs[i].ServerChangeTeam(target.TeamIndex);
		diff--;
		if (diff <= 0) return;
	}
}

/** returns true when the PC had a reserved slot */
function bool IsReservedSlot(PlayerController PC)
{
	if (SlotManager == none) return false;
	return SlotManager.IsReserved("?name="$PC.PlayerReplicationInfo.PlayerName, PC.GetPlayerNetworkAddress(), PC.GetPlayerIDHash(), false);
}

/** return true when Controller is a key player in the current game */
function bool IsKeyPlayer(Controller C)
{
	return C.PlayerReplicationInfo.HasFlag != none;
}

/*
/** debug function */
function AddBotToTeam(UnrealTeamInfo Team, optional string botname)
{
	local bot newbot;
	newbot = TeamGame.SpawnBot(botname);
	if (newbot == none) return;
	if (newbot.PlayerReplicationInfo.Team != Team)
	{
		if (newbot.PlayerReplicationInfo.Team != none) newbot.PlayerReplicationInfo.Team.RemoveFromTeam(newbot);
		Team.AddToTeam(newbot);
		Team.SetBotOrders(newbot, Team.GetNamedBot(newbot.PlayerReplicationInfo.PlayerName));
	}

	// copy from DeatchMatch.AddBot
	TeamGame.BroadcastLocalizedMessage(TeamGame.GameMessageClass, 1, NewBot.PlayerReplicationInfo);

	NewBot.PlayerReplicationInfo.PlayerID = TeamGame.CurrentID++;
	TeamGame.NumBots++;
	if ( Level.NetMode == NM_Standalone )
		TeamGame.RestartPlayer(NewBot);
	else
		NewBot.GotoState('Dead','MPStart');
}
*/

/** add information to the server details listing */
function GetServerDetails( out GameInfo.ServerResponseLine ServerState )
{
	if (bAnnounce) super.GetServerDetails(ServerState);
}

static function FillPlayInfo(PlayInfo PlayInfo)
{
	super.FillPlayInfo(PlayInfo);
	PlayInfo.AddSetting(default.PIgroup, "bAnnounce",				default.PIdesc[0], 175, 0, "Check",,, True);

	PlayInfo.AddSetting(default.PIgroup, "fLingerTime",				default.PIdesc[1], 100, 0, "Text", "5;0:999",, True);
	PlayInfo.AddSetting(default.PIgroup, "iSizeThreshold",			default.PIdesc[2],  75, 0, "Text", "3;0:999",, True);
	PlayInfo.AddSetting(default.PIgroup, "bIgnoreWinning",			default.PIdesc[3],  75, 0, "Check",,, True);
	PlayInfo.AddSetting(default.PIgroup, "fTeamScoreThreshold",		default.PIdesc[4],  75, 0, "Text", "5;-999:999",, True);
	PlayInfo.AddSetting(default.PIgroup, "bOnlyBalanceOnRequest",	default.PIdesc[5], 150, 0, "Check",,, True);
	PlayInfo.AddSetting(default.PIgroup, "fTeamBalanceDelay",		default.PIdesc[6],  75, 0, "Text", "5;0:999",, True);
	PlayInfo.AddSetting(default.PIgroup, "bOnlyAdminBalance",		default.PIdesc[7], 150, 0, "Check",,, True);

	PlayInfo.AddSetting(default.PIgroup, "bBotsBalance",			default.PIdesc[8],  75, 0, "Check",,, True);
	PlayInfo.AddSetting(default.PIgroup, "bAddBots",				default.PIdesc[9],  75, 0, "Check",,, True);
	PlayInfo.AddSetting(default.PIgroup, "iMaxBots",				default.PIdesc[10], 75, 0, "Text", "3;-2:999",, True);

	PlayInfo.AddSetting(default.PIgroup, "bSwitchPlayersBack",		default.PIdesc[11], 75, 0, "Check",,, True);
	PlayInfo.AddSetting(default.PIgroup, "bBalanceNewest",			default.PIdesc[12], 75, 0, "Check",,, True);
	PlayInfo.AddSetting(default.PIgroup, "bBalanceWorst",			default.PIdesc[13], 75, 0, "Check",,, True);
}

static event string GetDescriptionText(string PropName)
{
	switch (PropName)
	{
		case "bAnnounce":				return default.PIhelp[0];

		case "fLingerTime":				return default.PIhelp[1];
		case "iSizeThreshold":			return default.PIhelp[2];
		case "bIgnoreWinning":			return default.PIhelp[3];
		case "fTeamScoreThreshold":		return default.PIhelp[4];
		case "bOnlyBalanceOnRequest":	return default.PIhelp[5];
		case "fTeamBalanceDelay":		return default.PIhelp[6];
		case "bOnlyAdminBalance":		return default.PIhelp[7];

		case "bBotsBalance":			return default.PIhelp[8];
		case "bAddBots":				return default.PIhelp[9];
		case "iMaxBots":				return default.PIhelp[10];

		case "bSwitchPlayersBack":		return default.PIhelp[11];
		case "bBalanceNewest":			return default.PIhelp[12];
		case "bBalanceWorst":			return default.PIhelp[13];
	}
	return "";
}

defaultProperties
{
	GroupName="Team Balancer"
	FriendlyName="Team Balancer"
	Description="Make sure the teams have equal size when the odds are off"

	bAnnounce=true

	fLingerTime=0
	iSizeThreshold=2
	bIgnoreWinning=false
	fTeamScoreThreshold=-1
	bOnlyBalanceOnRequest=false
	fTeamBalanceDelay=5
	bIgnoreReservedSlots=false
	bOnlyAdminBalance=false

	bBotsBalance=true
	bAddBots=true
	iMaxBots=-1

	bSwitchPlayersBack=true
	bBalanceNewest=true
	bBalanceWorst=false

	msgNotUnbalanced="The teams are NOT unbalanced"
	msgAdminRequired="Only administrators can request to balance the teams."

	PIgroup="Team Balancer"

	PIdesc[0]="Announce to MS"
	PIhelp[0]="Announce this mutator to the master server and server details"
	PIdesc[1]="Initial in active time"
	PIhelp[1]="Number seconds since the beginning of the game that the team balancer will remain inactive."
	PIdesc[2]="Size threshold"
	PIhelp[2]="The size difference between teams before it's considered uneven, 2 is really the minimum."
	PIdesc[3]="Ignore winning team"
	PIhelp[3]="If set to true, don't take into account if the smaller team is winning"
	PIdesc[4]="Score threshold"
	PIhelp[4]="Difference in teamscore before it's considered winning (used when checking if the smallest team is winning), should be 0 or less because with -1 the score difference has to be at least 2"
	PIdesc[5]="Only balance on request"
	PIhelp[5]="Only balance the teams when it's requested via: mutate balance"
	PIdesc[6]="Team balance delay"
	PIhelp[6]="Number of seconds to wait befor balancing the team automatically"
	PIdesc[7]="Ignore reserved slots"
	PIhelp[7]="If set to true, that entered bassed on a reserved slot (requires the Reserved Slots addon) will not be balanced. Only the reserved slots	with IP, Hash or PlayerName can be checked. Reserved slots based on the password or any other part of the connect url can't be checked."
	PIdesc[8]="Bots balance"
	PIhelp[8]="Balance bots first. This only works if there are bots on the server, or MinPlayers has been set."
	PIdesc[9]="Add bots"
	PIhelp[9]="Add bots to balance the teams first."
	PIdesc[10]="Maximum bots"
	PIhelp[10]="The absolute maximum number of bots allowed. If set to -1 it will use the maximum recommended player count for the current map, if set to -2 it will use the minimum recommended player count (both corrected with the current player count)."
	PIdesc[11]="Switch players back"
	PIhelp[11]="If a user switches team when the teams are unbalanced switch the user back to his old team (when he tried to join the bigger team). If set to false it will use the standard balancing method."
	PIdesc[12]="Balance newest players"
	PIhelp[12]="Balance the players based on their join time"
	PIdesc[13]="Balance worst players"
	PIhelp[13]="Balance the players based on their score/death ration. The worst are balanced first. if neither bBalanceNewest or bBalanceWorst are set players are randomly balanced."
}
