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
