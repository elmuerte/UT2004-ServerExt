/*******************************************************************************
    Stats Chat Logging addon.                                           <br />
    Adds chat logging to the stats logs.                                <br />
    Two new log entries are added: V (normal chat), TV (team chat)      <br />

    (c) 2004, Michiel "El Muerte" Hendriks                              <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: StatsChatLog.uc,v 1.7 2006/01/06 20:32:06 elmuerte Exp $ -->
*******************************************************************************/
class StatsChatLog extends BroadcastHandler;

/** if set to true it will not try to find the right broadcast handler */
var config bool bDisableBHFix;

var protected GameStats statslog;

const SPECPRE = "spec_";

function PreBeginPlay()
{
    local BroadcastHandler BH;

    log("Loading StatsChatLog...", name);
    statslog = Level.Game.GameStats;
    if (statslog == none)
    {
        log("Stats logging is NOT enabled", name);
        log("Add \"?gamestats=true\" to your launch URL on the commandline", name);
    }
    else if (statslog.TempLog == none)
    {
        log("Local stats logging is NOT enabled", name);
        log("Add the following to your server configuration", name);
        log("   [Engine.GameStats]", name);
        log("   bLocalLog=true", name);
    }
    if (!bDisableBHFix && (Level.Game.BroadcastHandler.class != Level.Game.default.BroadcastClass) /*Level.Game.BroadcastHandler.IsA('UT2VoteChatHandler')*/)
    {
        log("WARNING: Unexpected broadcast handler `"$Level.Game.BroadcastHandler.class$"`. Will try to use the original.", name);
        foreach AllActors(class'BroadcastHandler', BH)
        {
            if (BH.class == Level.Game.default.BroadcastClass)
            {
                log("Found the original broadcast handler "$BH.class, name);
                BH.RegisterBroadcastHandler(Self);
                break;
            }
        }
        if (BH == none)
        {
            log("Unable to find the original broadcast handler. Will fallback to the current handler and hope it works out.");
            Level.Game.BroadcastHandler.RegisterBroadcastHandler(Self);
        }
    }
    else {
        Level.Game.BroadcastHandler.RegisterBroadcastHandler(Self);
    }
}

function BroadcastText( PlayerReplicationInfo SenderPRI, PlayerController Receiver, coerce string Msg, optional name Type )
{
    local string ctype;
    if ((statslog != none) && (statslog.TempLog != none) && (Receiver.PlayerReplicationInfo == SenderPRI))
    {
        if (Type == 'say') ctype = "V";
        else if (Type == 'teamsay') ctype = "TV";
        if (ctype != "")
        {
            if (SenderPRI.bIsSpectator) statslog.TempLog.Logf(statslog.Header()$ctype$Chr(9)$SPECPRE$SenderPRI.PlayerName$Chr(9)$Msg);
            else statslog.TempLog.Logf(statslog.Header()$ctype$Chr(9)$SenderPRI.PlayerID$Chr(9)$Msg);
        }
    }
    super.BroadcastText(SenderPRI, Receiver, Msg, Type);
}

defaultproperties
{
    bDisableBHFix=false
}