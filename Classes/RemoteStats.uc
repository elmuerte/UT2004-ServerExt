/*******************************************************************************
	Remote stat logging. Sends the stat logs to a remote server			<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: RemoteStats.uc,v 1.2 2004/10/01 10:10:14 elmuerte Exp $ -->
*******************************************************************************/

class RemoteStats extends MasterServerGameStats;

/** The remote stats link class to use */
var class<RStatsLink> RStatsLinkClass;
/** the link to the remote stats */
var protected RStatsLink link;

function Logf(string LogString)
{
	Super.Logf(LogString);
	if (link != none) link.BufferLogf(LogString);
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
	super.PreBeginPlay();
	link = spawn(RStatsLinkClass);
}

defaultproperties
{
	RStatsLinkClass=class'RStatsLink'
}
