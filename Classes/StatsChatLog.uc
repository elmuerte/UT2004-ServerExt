/*******************************************************************************
    Stats Chat Logging addon.                                           <br />
    Adds chat logging to the stats logs.                                <br />
    Two new log entries are added: V (normal chat), TV (team chat)      <br />

    (c) 2004, Michiel "El Muerte" Hendriks                              <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: StatsChatLog.uc,v 1.5 2004/10/20 14:03:03 elmuerte Exp $ -->
*******************************************************************************/
class StatsChatLog extends BroadcastHandler;

var protected GameStats statslog;

const SPECPRE = "spec_";

function PreBeginPlay()
{
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
    if (Level.Game.BroadcastHandler != none) Level.Game.BroadcastHandler.RegisterBroadcastHandler(self);
    else Log("Error registering broadcast handler", name);
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

