/*******************************************************************************
    Logs player joins                                                   <br />

    (c) 2004, Michiel "El Muerte" Hendriks                              <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: PlayerJoinLog.uc,v 1.2 2004/10/20 14:03:03 elmuerte Exp $ -->
*******************************************************************************/
class PlayerJoinLog extends info config;

/** external log file */
var FileLog extlog;

/** use an external log file instead of the server log */
var config bool bExternalLog;
/** the filename of the external log */
var config string sFileFormat;

const VERSION = "100";

/** player cache record */
struct PlayerCache
{
  var string name;
  var string ip;
  /** magic number to find parted players */
  var int magic;
  /** is spectator */
  var bool spec;
};
var array<PlayerCache> cache;

var int lastID;

function PostBeginPlay()
{
    log("Starting PlayerJoinLog version "$VERSION, name);
    if (bExternalLog)
    {
        extlog = spawn(class'FileLog');
        extlog.OpenLog(LogFilename());
    }
    Enable('Tick');
    lastID = -1;
}

function Tick(float DeltaTime)
{
    if (lastID < Level.Game.CurrentID) CheckPlayerList();
}

function CheckPlayerList()
{
    local int pLoc, magicint;
    local string ipstr, typemsg;
    local PlayerController PC;
    local Controller C;

    lastID = Level.Game.CurrentID;

    if (Level.Game.CurrentID > cache.length) cache.length = Level.Game.CurrentID+1; // make cache larger
    magicint = Rand(MaxInt);

    for( C = Level.ControllerList; C != None; C = C.NextController )
    {
        PC = PlayerController(C);
        if (PC == none) continue;

        pLoc = PC.PlayerReplicationInfo.PlayerID;
        ipstr = PC.GetPlayerNetworkAddress();
        if (ipstr != "")
        {
            if (PC.PlayerReplicationInfo.bOnlySpectator) typemsg = "SPECTATOR";
            else typemsg = "PLAYER";

            if (cache[pLoc].ip != ipstr)
            {
                cache[pLoc].spec = PC.PlayerReplicationInfo.bOnlySpectator;
                cache[pLoc].ip = ipstr;
                cache[pLoc].name = PC.PlayerReplicationInfo.PlayerName;
                LogLine("["$typemsg$"_JOIN]"@Timestamp()$chr(9)$PC.PlayerReplicationInfo.PlayerName$chr(9)$ipstr$chr(9)$PC.Player.CurrentNetSpeed$chr(9)$PC.GetPlayerIDHash());
            }
            else if (cache[pLoc].name != PC.PlayerReplicationInfo.PlayerName)
            {
                LogLine("["$typemsg$"_NAME_CHANGE]"@Timestamp()$chr(9)$cache[pLoc].name$chr(9)$PC.PlayerReplicationInfo.PlayerName);
                cache[pLoc].name = PC.PlayerReplicationInfo.PlayerName;
            }
            cache[pLoc].magic = magicint;
        }
    }

    // check parts
    for (pLoc = 0; pLoc < cache.length; pLoc++)
    {
        if ((cache[pLoc].magic != magicint) && (cache[pLoc].magic > -1) && (cache[pLoc].ip != ""))
        {
            cache[pLoc].magic = -1;
            if (cache[pLoc].spec) typemsg = "SPECTATOR";
            else typemsg = "PLAYER";
            LogLine("[PLAYER_PART]"@Timestamp()$chr(9)$cache[pLoc].name);
        }
    }
}

/** write to the server */
function LogLine(string logline)
{
    if (bExternalLog)
    {
        extlog.Logf(logline);
    }
    else log(logline, name);
}

function string GetServerPort()
{
    local string S;
    local int i;
    S = Level.GetAddressURL();
    i = InStr( S, ":" );
    return Mid(S,i+1);
}

function string GetServerIP()
{
    local string S;
    local int i;
    S = Level.GetAddressURL();
    i = InStr( S, ":" );
    return Left(S,i);
}

/** put out a time stamp */
function string Timestamp()
{
    return Level.Year$"/"$Level.Month$"/"$Level.Day$" "$Level.Hour$":"$Level.Minute$":"$Level.Second;
}

/** generate the filename to use */
function string LogFilename()
{
    local string result;
    result = sFileFormat;
    ReplaceText(result, "%P", GetServerPort());
    ReplaceText(result, "%N", Level.Game.GameReplicationInfo.ServerName);
    ReplaceText(result, "%Y", Right("0000"$string(Level.Year), 4));
    ReplaceText(result, "%M", Right("00"$string(Level.Month), 2));
    ReplaceText(result, "%D", Right("00"$string(Level.Day), 2));
    ReplaceText(result, "%H", Right("00"$string(Level.Hour), 2));
    ReplaceText(result, "%I", Right("00"$string(Level.Minute), 2));
    ReplaceText(result, "%W", Right("0"$string(Level.DayOfWeek), 1));
    ReplaceText(result, "%S", Right("00"$string(Level.Second), 2));
    return result;
}

defaultproperties
{
    bExternalLog=false
    sFileFormat="PlayerJoin_%P_%Y_%M_%D_%H_%I_%S"
}
