/*******************************************************************************
	Remote stat logging. Sends the stat logs to a remote server			<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: RemoteStats.uc,v 1.1 2004/09/28 08:12:37 elmuerte Exp $ -->
*******************************************************************************/

class RemoteStats extends MasterServerGameStats;

var class<RStatsLink> RStatsLinkClass;
var RStatsLink link;

function Logf(string LogString)
{
	if (link != none) link.BufferLogf(LogString);
	Super.Logf(LogString);
}

function Shutdown()
{
	super.Shutdown();
	if (link != none) link.FinalFlush();
}

function EndGame(string Reason)
{
	super.EndGame(Reason);
	if (link != none) link.FinalFlush();
}

function PreBeginPlay()
{
	link = spawn(RStatsLinkClass);
}

defaultproperties
{
	RStatsLinkClass=class'RStatsLink'
}
