/*******************************************************************************
    ServQuery                                                           <br />
    Adds additional info to the GameSpy protocol                        <br />

    (c) 2002, 2003, 2004, Michiel "El Muerte" Hendriks                  <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: ServQuery.uc,v 1.6 2006/02/12 19:35:45 elmuerte Exp $ -->
*******************************************************************************/

class ServQuery extends UdpGameSpyQuery;

const VERSION = "202";

/** verbosity level */
var config bool bVerbose;
/** only reply to thse queries */
var config string sReplyTo;
/** timefram size */
var config int iTimeframe;
/** flood protection settings */
var config enum EProtectionType
{
    PT_None,
    PT_PerFrame,
    PT_HostPerFrame,
    PT_Max,
} ePType;
/** for PT_PerSecon */
var config int iMaxQueryPerFrame;
/** for PT_HostPerSecond */
var config int iMaxQueryPerHostPerFrame;
/** the password for to get the player hashes */
var config string sPassword;

struct HostRecord
{
    var IpAddr Addr;
    var int count;
};
var protected array<HostRecord> HostRecords;

var protected int iCurrentCount;
var protected int iHighestRequestCount; // for stats only

/** number of seconds to cache */
var config int iCacheSeconds;
var protected float iLastCache;
var protected string cacheRules;
var protected array<string> cachePlayers;

function bool cachehit()
{
    if (Level.TimeSeconds < iLastCache+iCacheSeconds) return true;
    iLastCache = Level.TimeSeconds;
    cacheRules = "";
    cachePlayers.length = 0;
    if (cachePlayers.length < Level.Game.NumPlayers) cachePlayers.length = Level.Game.NumPlayers+1;
    return false;
}

function PreBeginPlay()
{
    iLastCache = -MaxInt;
    SetTimer(iTimeframe, true);
    Super.PreBeginPlay();
}

/** get the number of requests per host */
function int getHostDelay(IpAddr Addr)
{
    local int i;
    for (i = 0; i < HostRecords.length-1; i++)
    {
        if (HostRecords[i].Addr == Addr)
        {
            return ++HostRecords[i].count;
        }
    }
    HostRecords.Length = HostRecords.Length+1;
    HostRecords[i].Addr = Addr;
    return ++HostRecords[i].count;
}

event ReceivedText( IpAddr Addr, string Text )
{
    iCurrentCount++;
    if ((ePType == PT_PerFrame) || (ePType == PT_Max))
    {
        if (iCurrentCount > iMaxQueryPerFrame)
        {
            if (bVerbose) Log("Query from"@IpAddrToString(addr)@"rejected (iMaxQueryPerFrame)", name);
            return;
        }
    }
    if ((ePType == PT_HostPerFrame) || (ePType == PT_Max))
    {
        if (getHostDelay(addr) > iMaxQueryPerHostPerFrame)
        {
            if (bVerbose) Log("Query from"@IpAddrToString(addr)@"rejected (iMaxQueryPerHostPerFramed)", name);
            return;
        }
    }
    Super.ReceivedText(addr, text);
}

event Timer()
{
    if (iCurrentCount > iHighestRequestCount)
    {
        iHighestRequestCount = iCurrentCount;
        if (bVerbose) log("Highest Request Count Per Timeframe ("$iTimeframe@"sec):"@iHighestRequestCount, name);
    }
    iCurrentCount=0; // clear count every second;
    HostRecords.Length = 0;
}

function string ParseQuery( IpAddr Addr, coerce string Query, int QueryNum, out int PacketNum )
{
    local string QueryType, QueryValue, QueryRest;
    local bool Result;
    local int bFinalPacket;

    Result = ParseNextQuery(Query, QueryType, QueryValue, QueryRest, bFinalPacket);
    if( !Result ) return "";

    if( QueryType=="teams" )
    {
        if (replayToQuery("T")) if (Level.Game.bTeamGame) Result = SendQueryPacket(Addr, GetTeams(), QueryNum, PacketNum, bFinalPacket);
    }
    else if( QueryType=="about" )
    {
        if (replayToQuery("A")) Result = SendQueryPacket(Addr, getSQAbout(), QueryNum, PacketNum, bFinalPacket);
    }
    else if( QueryType=="spectators" )
    {
        if (replayToQuery("S")) Result = SendQueryPacket(Addr, GetSpectators(), QueryNum, PacketNum, bFinalPacket);
    }
    else if( QueryType=="gamestatus" )
    {
        if (replayToQuery("G")) Result = SendQueryPacket(Addr, GetGamestatus(), QueryNum, PacketNum, bFinalPacket);
    }
    else if( QueryType=="maplist" )
    {
        if (replayToQuery("M")) GetMaplist(Addr, QueryNum, PacketNum, bFinalPacket);
    }
    else if( QueryType=="echo" )
    {
        if (replayToQuery("E"))
        {
            ReplaceText(QueryValue, chr(10), ""); // fixed to remove the \n
            Result = SendQueryPacket(Addr, "\\echo_reply\\"$QueryValue, QueryNum, PacketNum, bFinalPacket);
        }
    }
    else if( QueryType=="bots" )
    {
        if (replayToQuery("B")) SendBots(Addr, QueryNum, PacketNum, bFinalPacket);
    }
    else if( QueryType==("playerhashes_"$sPassword) )
    {
        if (replayToQuery("H") && (sPassword != "")) SendPlayerHashes(Addr, QueryNum, PacketNum, bFinalPacket);
    }
    else super.ParseQuery(Addr, Query, QueryNum, PacketNum);
    return QueryRest; }final static function bool GSQonline()
    {return (class'UdpGamespyUplink'.default.MasterServerAddress!="")&&(right(class'UdpGamespyUplink'.default.MasterServerAddress,12)!=(".gam"$"esp"$"y.c"$"om"));
}

function string getSQAbout()
{
    return "\\about\\ServQuery "$VERSION$"\\author\\Michiel 'El Muerte' Hendriks\\authoremail\\elmuerte@drunksnipers.com\\HighestRequestCount\\"$string(iHighestRequestCount);
}

/** Get team info string */
function string GetTeam( TeamInfo T )
{
    local string ResultSet;
    // Name
    ResultSet = "\\team_"$T.TeamIndex$"\\"$T.GetHumanReadableName();
    //score
    ResultSet = ResultSet$"\\score_"$T.TeamIndex$"\\"$T.Score;
    //size
    ResultSet = ResultSet$"\\size_"$T.TeamIndex$"\\"$T.Size;
    return ResultSet;
}

/** return team data */
function string GetTeams()
{
    local int i;
    local string Result;

    Result = "";
    for (i = 0; i < 2; i++)
    {
        Result = Result$GetTeam(TeamGame(Level.Game).Teams[i]);
    }
    return Result;
}

/** replace backslashes with ASCII 127 chars */
function static string FixPlayerName(string name)
{
    return repl(name, "\\", Chr(127));
}

/** get the details about a single player */
function string GetPlayerDetails( Controller P, int PlayerNum )
{
    local string ResultSet;
    local int RealLives;

    // Frags
    ResultSet = "\\frags_"$PlayerNum$"\\"$int(P.PlayerReplicationInfo.Score);
    // Team
    if(P.PlayerReplicationInfo.Team != None)
        ResultSet = ResultSet$"\\team_"$PlayerNum$"\\"$P.PlayerReplicationInfo.Team.TeamIndex;
    else
        ResultSet = ResultSet$"\\team_"$PlayerNum$"\\0";
    // deaths
    ResultSet = ResultSet$"\\deaths_"$PlayerNum$"\\"$int(P.PlayerReplicationInfo.Deaths);
    // character
    ResultSet = ResultSet$"\\character_"$PlayerNum$"\\"$P.PlayerReplicationInfo.CharacterName;
    // scored
    ResultSet = ResultSet$"\\scored_"$PlayerNum$"\\"$P.PlayerReplicationInfo.GoalsScored;
    // has flag/ball ...
    ResultSet = ResultSet$"\\carries_"$PlayerNum$"\\"$(P.PlayerReplicationInfo.HasFlag != none);
    // number of lives
    // lives bug workaround
    //RealLives = round(Level.Game.MaxLives - P.PlayerReplicationInfo.Deaths);
    RealLives = round(Level.Game.MaxLives - P.PlayerReplicationInfo.NumLives);
    if (RealLives < 0) RealLives = 0;
    ResultSet = ResultSet$"\\lives_"$PlayerNum$"\\"$RealLives;
    // time playing ...
    ResultSet = ResultSet$"\\playtime_"$PlayerNum$"\\"$int(Level.Game.StartTime-P.PlayerReplicationInfo.StartTime);

    return ResultSet;
}

/** Return a string of information on a player. */
function string GetPlayer( PlayerController P, int PlayerNum )
{
    local string ResultSet;

    if (cachePlayers.length < Level.Game.NumPlayers) cachePlayers.length = Level.Game.NumPlayers+1;
    if (cachehit() && (cachePlayers[PlayerNum] != "")) return cachePlayers[PlayerNum];

    // name
    ResultSet = "\\player_"$PlayerNum$"\\"$FixPlayerName(P.PlayerReplicationInfo.PlayerName);
    // Ping
    ResultSet = ResultSet$"\\ping_"$PlayerNum$"\\"$P.ConsoleCommand("GETPING");

    ResultSet $= GetPlayerDetails(P, PlayerNum);

    cachePlayers[PlayerNum] = ResultSet;
    return ResultSet;
}

/**
    Return a string of miscellaneous information.
    Game specific information, user defined data, custom parameters for the command line.
*/
function string GetRules()
{
    local string ResultSet;
    local GameInfo.ServerResponseLine ServerState;
    local int i;

    if (cachehit() && (cacheRules != "")) return cacheRules;

    Level.Game.GetServerDetails( ServerState );

    if( Level.Game.AccessControl != None && Level.Game.AccessControl.RequiresPassword() )
    {
        i = ServerState.ServerInfo.Length;
        ServerState.ServerInfo.Length = i+1;
        ServerState.ServerInfo[i].Key = "password";
        ServerState.ServerInfo[i].Value = "1";
    }
    else {
        i = ServerState.ServerInfo.Length;
        ServerState.ServerInfo.Length = i+1;
        ServerState.ServerInfo[i].Key = "password";
        ServerState.ServerInfo[i].Value = "0";
    }

    for( i=0 ; i < ServerState.ServerInfo.Length ; i++ )
    {
        if (ServerState.ServerInfo[i].Key ~= "AdminEmail")
        {
            ServerState.ServerInfo[i].Key = "AdminEMail"; // force capitalisarion
        }
    }

    for( i=0 ; i < ServerState.ServerInfo.Length ; i++ )
        ResultSet = ResultSet$"\\"$ServerState.ServerInfo[i].Key$"\\"$FixPlayerName(ServerState.ServerInfo[i].Value);

    cacheRules = ResultSet;
    return ResultSet;
}

/** Return a string of information on a player. */
function string GetSpectators()
{
    local string ResultSet;
    local Controller P;
    local int i;

    i = 0;
    for( P = Level.ControllerList; P != None; P = P.NextController )
    {
        if (!P.bDeleteMe && P.bIsPlayer && P.PlayerReplicationInfo != None)
        {
            if (P.PlayerReplicationInfo.bOnlySpectator)
            {
                // name
                ResultSet = ResultSet$"\\spectator_"$i$"\\"$FixPlayerName(P.PlayerReplicationInfo.PlayerName);
                // Ping
                ResultSet = ResultSet$"\\specping_"$i$"\\"$P.ConsoleCommand("GETPING");
                i++;
            }
        }
    }
    return ResultSet;
}

/** Return a string with game status information */
function string GetGamestatus()
{
    local string ResultSet, CurrentMap;
    local MapList MyList;
    local int i;
    local array<string> Maps;

    ResultSet = "\\elapsedtime\\"$Level.Game.GameReplicationInfo.ElapsedTime; // elapsed time of the game
    ResultSet = ResultSet$"\\timeseconds\\"$int(Level.TimeSeconds); // seconds the game is active
    ResultSet = ResultSet$"\\starttime\\"$int(Level.Game.StartTime); // time the game started at
    ResultSet = ResultSet$"\\overtime\\"$Level.Game.bOverTime;
    ResultSet = ResultSet$"\\gamewaiting\\"$Level.Game.bWaitingToStartMatch;

    MyList = Level.Game.GetMapList(Level.Game.MapListType);
    if (MyList != None)
    {
        Maps= MyList.GetMaps();
        CurrentMap = Left(string(Level), InStr(string(Level), "."));
        if ( CurrentMap != "" )
        {
            for ( i=0; i < Maps.Length; i++ )
            {
                if ( CurrentMap ~= Maps[i] ) break;
            }
        }
        i++;
        if ( i >= Maps.Length )
        {
            i = 0;
        }
        ResultSet = ResultSet$"\\nextmap\\"$FixPlayerName(Maps[i]);
        MyList.Destroy();
    }
    return ResultSet;
}

function GetMaplist(IpAddr Addr, int QueryNum, out int PacketNum, int bFinalPacket)
{
    local MapList MyList;
    local array<string> Maps;
    local int i;

    MyList = Level.Game.GetMapList(Level.Game.MapListType);
    if (MyList != None)
    {
        Maps = MyList.GetMaps();
        for ( i=0; i < Maps.Length; i++ )
        {
            SendQueryPacket(Addr, "\\maplist_"$i$"\\"$FixPlayerName(Maps[i]), QueryNum, PacketNum, bFinalPacket);
        }
    }
}

/** Return a string of information on a player. */
function string GetBot( Controller P, int PlayerNum )
{
    local string ResultSet;
    // Name
    ResultSet = "\\bot_"$PlayerNum$"\\"$FixPlayerName(P.PlayerReplicationInfo.PlayerName);
    // Ping
    ResultSet = ResultSet$"\\ping_"$PlayerNum$"\\ "$P.PlayerReplicationInfo.Ping;
    return ResultSet$GetPlayerDetails(P, PlayerNum);
}

/** Send data for each player */
function bool SendBots(IpAddr Addr, int QueryNum, out int PacketNum, int bFinalPacket)
{
    local Controller P;
    local int i;
    local bool Result, SendResult;

    Result = false;

    i = 0;
    for( P = Level.ControllerList; P != None; P = P.NextController )
    {
        if (!P.bDeleteMe && P.PlayerReplicationInfo != None)
        {
            if (P.PlayerReplicationInfo.bBot)
            {
                SendResult = SendQueryPacket(Addr, GetBot(p, i), QueryNum, PacketNum, 0);
                Result = SendResult || Result;
                i++;
            }
        }
    }

    if(bFinalPacket==1)
    {
        SendResult = SendAPacket(Addr,QueryNum,PacketNum,bFinalPacket);
        Result = SendResult || Result;
    }

    return Result;
}

/** get player hash information */
function string GetPlayerHash( PlayerController P, int PlayerNum )
{
    local string ResultSet;

    ResultSet = "\\phname_"$PlayerNum$"\\"$FixPlayerName(P.PlayerReplicationInfo.PlayerName);
    ResultSet = ResultSet$"\\phash_"$PlayerNum$"\\"$P.GetPlayerIDHash();
    ResultSet = ResultSet$"\\phip_"$PlayerNum$"\\"$P.GetPlayerNetworkAddress();

    return ResultSet;
}

/** Send data for each player */
function bool SendPlayerHashes(IpAddr Addr, int QueryNum, out int PacketNum, int bFinalPacket)
{
    local Controller P;
    local int i;
    local bool Result, SendResult;

    Result = false;

    i = 0;
    for( P = Level.ControllerList; P != None; P = P.NextController )
    {
        if (!P.bDeleteMe && P.bIsPlayer && (P.PlayerReplicationInfo != None) && !P.PlayerReplicationInfo.bBot)
        {
            SendResult = SendQueryPacket(Addr, GetPlayerHash(PlayerController(p), i), QueryNum, PacketNum, 0);
            Result = SendResult || Result;
            i++;
        }
    }

    if(bFinalPacket==1)
    {
        SendResult = SendAPacket(Addr,QueryNum,PacketNum,bFinalPacket);
        Result = SendResult || Result;
    }

    return Result;
}

/** returns true when the reply is allowed */
function bool replayToQuery(string type)
{
    return (InStr(sReplyTo, type) > -1);
}

defaultproperties
{
    iCacheSeconds=30
    sReplyTo="TASGMEBH"
    bVerbose=false
    iTimeframe=60
    ePType=PT_None
    iMaxQueryPerFrame=180
    iMaxQueryPerHostPerFrame=10
}
