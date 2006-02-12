/*******************************************************************************
    Team balancer mutator                                               <br />

    (c) 2004, Michiel "El Muerte" Hendriks                              <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: mutTeamBalance.uc,v 1.11 2006/02/12 19:35:45 elmuerte Exp $ -->
*******************************************************************************/
class mutTeamBalance extends Mutator;

/** to reduce typecasting */
var protected TeamGame TeamGame;
/** used to check for reserved slots */
var protected SlotManager SlotManager;

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
/**
    if the team balance isn't odd, but the sizes are not equal use bots to correct
    this issue;
*/
var(BotBalance) config bool bBotsFill;

/** if a player switches team and it unbalances the team switch the player back,
    if this is not set the default balacing will be applied */
var(PlayerBalance) config bool bSwitchPlayersBack;

/**
    Various balance methods:
    Balance players based on their join time (BM_Oldest, BM_Newest).
    Balance players based on their gaming performance, their performance is
    defined by their score/death ration (BM_Worst, BM_Best).
    Or just randomly. Key players are never balanced.
*/
enum EBalanceMethod
{
    BM_Worst,
    BM_Best,
    BM_Oldest,
    BM_Newest,
    BM_Random,
};
/** method to use when balancing players */
var(PlayerBalance) config EBalanceMethod BalanceMethod;

/** log debug messages */
var(DebugConfig) config bool bDebug;

/** player team history, used to check if a player changed teams */
struct TeamRecordEntry
{
    var PlayerController PC;
    var int team;
};
/** list with playercontrollers and their "old" team id */
var array<TeamRecordEntry> TeamRecords;

//!Localization
var localized string msgNotUnbalanced, msgAdminRequired, PIdesc[15], PIhelp[15],
    PIgroup;

function PreBeginPlay()
{
    local TeamBalanceRules TBR;
    super.PreBeginPlay();
    TeamGame = TeamGame(Level.Game);
    if (TeamGame == none)
    {
        Error("Current game is NOT a team game type");
        return;
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

/** check for unbalanced teams when a player quits */
function NotifyLogout(Controller Exiting)
{
    local int i;
    super.NotifyLogout(Exiting);

    if (PlayerController(Exiting) != none)
    {
        for (i = 0; i < TeamRecords.length; i++)
        {
            if (TeamRecords[i].PC == PlayerController(Exiting))
            {
                TeamRecords.remove(i, 1);
                return;
            }
        }
    }

    if (!bActive) return;
    if (bOnlyBalanceOnRequest) return;
    if (Level.Game.bGameEnded) return;
    if (PlayerController(Exiting) == none) return;

    if (Exiting.PlayerReplicationInfo.Team == none) i = 0;
    else if (Exiting.PlayerReplicationInfo.Team.TeamIndex == 0) i = -1;
    else i = 1;
    if (OddTeams(i))
    {
        if (fTeamBalanceDelay < 0.5) Balance();
        else SetTimer(fTeamBalanceDelay, false);
    }
    else if (bBotsFill) CorrectBots();
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
    if (!OddTeams())// check again
    {
        if (bBotsFill) CorrectBots();
        return;
    }
    Balance();
}

/**
    check if a PC switched teams and if the switch is allowed. Returns true
    when the player switched team again
*/
function bool PCTeamSwitch(PlayerController PC)
{
    local int i;
    if (!bActive) return false;
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
            if (bDebug) log("DEBUG: team change in an unbalanced game", name);
            if (!bSwitchPlayersBack)
            {
                if (fTeamBalanceDelay < 0.5) Balance();
                else SetTimer(fTeamBalanceDelay, false);
            }
            else {
                if (!IsSmallest(TeamRecords[i].PC.PlayerReplicationInfo.Team.TeamIndex))
                {
                    if (bDebug) log("DEBUG: force player to old team: "$PC.PlayerReplicationInfo.Team.TeamIndex$" -> "$TeamRecords[i].Team, name);
                    TeamRecords[i].PC.ServerChangeTeam(TeamRecords[i].Team);
                    return true;
                }
            }
        }
        else if (bBotsFill) CorrectBots();
        TeamRecords[i].Team = TeamRecords[i].PC.PlayerReplicationInfo.Team.TeamIndex;
    }
    return false;
}

/** return true when the teams are not even, incTeamX modifies the team difference
    with it's value. So, incTeamX should be 1 for Team 0 and -1 for Team 1 */
function bool OddTeams(optional int incTeamX)
{
    local int i;
    local float j;
    i = TeamGame.Teams[0].Size - TeamGame.Teams[1].Size + incTeamX;
    if (i == 0) return false;
    if (bDebug) log("DEBUG: difference = "$i@"team 0:"@TeamGame.Teams[0].Size@"team 1:"@TeamGame.Teams[1].Size@"incTeamX:"@incTeamX, name);
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

    if (bDebug) log("Balancing teams...", name);
    if (bDebug) log("STAGE 0", name);
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

    if (bDebug) log("STAGE 1 - diff = "$diff, name);
    if (bBotsBalance && (TeamGame.MinPlayers > 0 || TeamGame.NumBots > 0))
    {
        if (bAddBots)
        {
            if (bDebug) log("STAGE 1a - diff = "$diff, name);
            i = diff - TeamGame.NumBots;
            j = iMaxBots;
            if (bDebug) log("DEBUG: initial iMaxBots = "$j, name);
            switch (j)
            {
                case -1:    j = Level.IdealPlayerCountMax-TeamGame.NumPlayers;
                case -2:    j = Level.IdealPlayerCountMin-TeamGame.NumPlayers;
            }
            j -= TeamGame.NumBots;
            if (bDebug) log("DEBUG: iMaxBots = "$j, name);
            i = min(i, j);
            if (i > 0)
            {
                if (bDebug) log("DEBUG: adding"@i@"bots", name);
                TeamGame.AddBots(i);
                diff -= i;
            }
        }
        // rearrage bots
        if (bDebug) log("STAGE 1b - diff = "$diff, name);
        for (C = Level.ControllerList; C != none; C = C.nextController)
        {
            if (C.PlayerReplicationInfo.bBot && C.PlayerReplicationInfo.Team == source)
            {
                if (IsKeyPlayer(C)) continue; // prevent switch when carring

                if (bDebug) log("DEBUG: force team change for bot"@C.PlayerReplicationInfo.PlayerName, name);
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
    if (bDebug) log("STAGE 2a - diff = "$diff, name);
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
    if (bDebug) log("STAGE 2b - diff = "$diff, name);
    // sort the list
    for (i = 0; i < PCs.length-1; i++)
    {
        for (j = i+1; j < PCs.length; j++)
        {
            if (BalanceMethod == BM_Newest)
            {
                if (PCs[i].PlayerReplicationInfo.StartTime < PCs[j].PlayerReplicationInfo.StartTime)
                {
                    PC = PCs[i];
                    PCs[i] = PCs[j];
                    PCs[j] = PC;
                }
            }
            else if (BalanceMethod == BM_Oldest)
            {
                if (PCs[i].PlayerReplicationInfo.StartTime > PCs[j].PlayerReplicationInfo.StartTime)
                {
                    PC = PCs[i];
                    PCs[i] = PCs[j];
                    PCs[j] = PC;
                }
            }
            else if (BalanceMethod == BM_Worst)
            {
                if (PCs[i].PlayerReplicationInfo.Score*1000/(PCs[i].PlayerReplicationInfo.Deaths+1) >
                    PCs[j].PlayerReplicationInfo.Score*1000/(PCs[j].PlayerReplicationInfo.Deaths+1))
                {
                    PC = PCs[i];
                    PCs[i] = PCs[j];
                    PCs[j] = PC;
                }
            }
            else if (BalanceMethod == BM_Best)
            {
                if (PCs[i].PlayerReplicationInfo.Score*1000/(PCs[i].PlayerReplicationInfo.Deaths+1) <
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
        if (bDebug) log("DEBUG: force team change for player"@PCs[i].PlayerReplicationInfo.PlayerName, name);
        PCs[i].ServerChangeTeam(target.TeamIndex);
        diff--;
        if (diff <= 0) return;
    }
}

/** will add/remove bots so that both teams have the equal size */
function CorrectBots()
{
    local Controller C;
    local UnrealTeamInfo team;
    local int diff;
    local array<Controller> killlist;

    if (TeamGame.Teams[0].Size == TeamGame.Teams[1].Size) return;
    if (TeamGame.MinPlayers <= 0 && TeamGame.NumBots <= 0) return; // no bot game

    diff = abs(TeamGame.Teams[0].Size - TeamGame.Teams[1].Size);
    if (bDebug) log("DEBUG: num bots ="@TeamGame.NumBots@"num players ="@TeamGame.NumPlayers@" min players ="@TeamGame.MinPlayers, name);
    if (TeamGame.NumBots+TeamGame.NumPlayers > TeamGame.MinPlayers)
    {
        if (bDebug) log("DEBUG: CorrectBots - removing bots:"@diff, name);
        if (TeamGame.Teams[0].Size < TeamGame.Teams[1].Size) team = TeamGame.Teams[1];
        else team = TeamGame.Teams[0];
        for (C = Level.ControllerList; C != none; C = C.nextController)
        {
            if (C.PlayerReplicationInfo.Team == team)
            {
                if (IsKeyPlayer(C)) continue;
                killlist[killlist.length] = C;
                diff--;
            }
            if (diff <= 0) break;
        }
        if (bDebug) log("DEBUG: killing"@killlist.length@"bot controllers", name);
        for (diff = 0; diff < killlist.length; diff++)
        {
            TeamGame.KillBot(killlist[diff]);
        }
    }
    else if (TeamGame.NumBots+TeamGame.NumPlayers < TeamGame.MinPlayers) {
        if (bDebug) log("DEBUG: CorrectBots - adding bots:"@diff, name);
        TeamGame.AddBots(diff);
    }
}

/** returns true when the PC had a reserved slot */
function bool IsReservedSlot(PlayerController PC)
{
    if (SlotManager == none) return false;
    return SlotManager.IsReserved("%import%", PC.GetPlayerNetworkAddress(), PC.GetPlayerIDHash(), false);
}

/** return true when Controller is a key player in the current game */
function bool IsKeyPlayer(Controller C)
{
    return TeamGame.CriticalPlayer(C);
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

static function FillPlayInfo(PlayInfo PlayInfo)
{
    super.FillPlayInfo(PlayInfo);
    PlayInfo.AddSetting(default.PIgroup, "fLingerTime",             default.PIdesc[1], 100, 0, "Text", "5;0:999",, True);
    PlayInfo.AddSetting(default.PIgroup, "iSizeThreshold",          default.PIdesc[2],  75, 0, "Text", "3;0:999",, True);
    PlayInfo.AddSetting(default.PIgroup, "bIgnoreWinning",          default.PIdesc[3],  75, 0, "Check",,, True);
    PlayInfo.AddSetting(default.PIgroup, "fTeamScoreThreshold",     default.PIdesc[4],  75, 0, "Text", "5;-999:999",, True);
    PlayInfo.AddSetting(default.PIgroup, "bOnlyBalanceOnRequest",   default.PIdesc[5], 150, 0, "Check",,, True);
    PlayInfo.AddSetting(default.PIgroup, "fTeamBalanceDelay",       default.PIdesc[6],  75, 0, "Text", "5;0:999",, True);
    PlayInfo.AddSetting(default.PIgroup, "bOnlyAdminBalance",       default.PIdesc[7], 150, 0, "Check",,, True);

    PlayInfo.AddSetting(default.PIgroup, "bBotsBalance",            default.PIdesc[8],  75, 0, "Check",,, True);
    PlayInfo.AddSetting(default.PIgroup, "bAddBots",                default.PIdesc[9],  75, 0, "Check",,, True);
    PlayInfo.AddSetting(default.PIgroup, "iMaxBots",                default.PIdesc[10], 75, 0, "Text", "3;-2:999",, True);
    PlayInfo.AddSetting(default.PIgroup, "bBotsFill",               default.PIdesc[14], 75, 0, "Check",,, True);

    PlayInfo.AddSetting(default.PIgroup, "bSwitchPlayersBack",      default.PIdesc[11], 75, 0, "Check",,, True);
    PlayInfo.AddSetting(default.PIgroup, "BalanceMethod",           default.PIdesc[12], 75, 0, "Select",default.PIdesc[13],, True);
}

static event string GetDescriptionText(string PropName)
{
    switch (PropName)
    {
        case "fLingerTime":             return default.PIhelp[1];
        case "iSizeThreshold":          return default.PIhelp[2];
        case "bIgnoreWinning":          return default.PIhelp[3];
        case "fTeamScoreThreshold":     return default.PIhelp[4];
        case "bOnlyBalanceOnRequest":   return default.PIhelp[5];
        case "fTeamBalanceDelay":       return default.PIhelp[6];
        case "bOnlyAdminBalance":       return default.PIhelp[7];

        case "bBotsBalance":            return default.PIhelp[8];
        case "bAddBots":                return default.PIhelp[9];
        case "iMaxBots":                return default.PIhelp[10];
        case "bBotsFill":               return default.PIhelp[14];

        case "bSwitchPlayersBack":      return default.PIhelp[11];
        case "BalanceMethod":           return default.PIhelp[12];
    }
    return "";
}

defaultProperties
{
    GroupName="Team Balancer"
    FriendlyName="Team Balancer (ServerExt)"
    Description="Make sure the teams have equal size when the odds are off"

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
    bBotsFill=false

    bSwitchPlayersBack=true
    BalanceMethod=BM_Worst

    bDebug=false

    msgNotUnbalanced="The teams are NOT unbalanced"
    msgAdminRequired="Only administrators can request to balance the teams."

    PIgroup="Team Balancer"

    PIdesc[0]=""
    PIhelp[0]=""
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
    PIhelp[7]="If set to true, that entered bassed on a reserved slot (requires the Reserved Slots addon) will not be balanced. Only the reserved slots with IP, Hash or PlayerName can be checked. Reserved slots based on the password or any other part of the connect url can't be checked."
    PIdesc[8]="Bots balance"
    PIhelp[8]="Balance bots first. This only works if there are bots on the server, or MinPlayers has been set."
    PIdesc[9]="Add bots"
    PIhelp[9]="Add bots to balance the teams first."
    PIdesc[10]="Maximum bots"
    PIhelp[10]="The absolute maximum number of bots allowed. If set to -1 it will use the maximum recommended player count for the current map, if set to -2 it will use the minimum recommended player count (both corrected with the current player count)."
    PIdesc[11]="Switch players back"
    PIhelp[11]="If a user switches team when the teams are unbalanced switch the user back to his old team (when he tried to join the bigger team). If set to false it will use the standard balancing method."
    PIdesc[12]="Balance method"
    PIhelp[12]="Method to balance the players"
    // 13 is used for #12 PI info
    PIdesc[13]="BM_Newest;Newest players;BM_Oldest;Oldest players;BM_Worst;Worst score rating;BM_Best;Best score rating;BM_Random;Random"
    PIhelp[13]="none"
    PIdesc[14]="Bots file the gap"
    PIhelp[14]="When the game isn't unbalanced, but the team sizes are not equal bots will correct the team size"
}
