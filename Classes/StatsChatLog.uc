/*******************************************************************************
	Stats Chat Logging addon.											<br />
	Adds chat logging to the stats logs.								<br />
	Two new log entries are added: V (normal chat), TV (team chat)		<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: StatsChatLog.uc,v 1.3 2004/04/19 06:27:55 elmuerte Exp $ -->
*******************************************************************************/

class StatsChatLog extends BroadcastHandler;

var protected GameStats statslog;

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
		log("	[Engine.GameStats]", name);
		log("	bLocalLog=true", name);
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
		if (ctype != "") statslog.TempLog.Logf(statslog.Header()$ctype$Chr(9)$SenderPRI.PlayerID$Chr(9)$Msg);
	}
	super.BroadcastText(SenderPRI, Receiver, Msg, Type);
}

