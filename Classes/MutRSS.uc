/*******************************************************************************
	RSS Feed Mutator													<br />
	ServerAdsSE like mutator that feeds of RSS feeds					<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />
	$Id: MutRSS.uc,v 1.1 2004/03/15 13:04:36 elmuerte Exp $
*******************************************************************************/

class MutRSS extends Mutator config;

const VERSION = 100;
/** character to replace the spaces in the config names with */
const SPACE_REPLACE = "_";

// Configuration options
/** master enable switch */
var() config bool bEnabled;

/** should the RSS feed content be broadcasted */
var() config bool bBroadcastEnabled;
/** number of seconds between broadcasts */
var() config int fBroadcastDelay;

/** if the mutator is interactive users can use the mutate command */
var() config bool bInteractive;

/** if automatic updating of the RSS feeds should happen should happen */
var() config bool bUpdateEnabled;
/** minutes between updates of the RSS feeds, keep this high 45 minutes is nice */
var() config int iUpdateInterval;

/** contains links to the feeds */
var protected array<RSSFeedRecord> Feeds;
/** a general HttpSock instance so we can use it's internal chaching */
var protected HttpSock htsock;
/** the current location in the Feeds list that will be checked to be updated */
var protected int UpdatePos;

event PreBeginPlay()
{
	if (!bEnabled)
	{
		log(FriendlyName@"mutator is NOT enabled", name);
		return;
	}
	InitRSS();
}

/** initialize RSS */
function InitRSS()
{
	LoadRSSFeeds();
	if (bUpdateEnabled)
	{
		htsock = spawn(class'HttpSock');
		htsock.OnComplete = ProcessRSSUpdate;
		//htsock.OnError = RSSUpdateError;
		UpdatePos = 0;
		UpdateRSSFeeds();
	}
}

/** Load the RSS Feeds */
function LoadRSSFeeds()
{
	local array<string> items;
	local int i;
	local RSSFeedRecord item;

	log("Loading RSS feeds from RSS.ini", name);
	items = GetPerObjectNames("RSS", "RSSFeedRecord");
	for (i = 0; i < items.Length; i++)
	{
		if (items[i] == "") continue;

		item = new(None, Repl(items[i], " ", SPACE_REPLACE)) class'ServerExt.RSSFeedRecord';
		if (item != none)
		{
			Log("Loaded RSS Feed"@item.rssHost@"-"@item.rssLocation , name);
			Feeds[Feeds.length] = item;
		}
	}
}

/** update all RSS Feeds (only those that are enabled) */
function UpdateRSSFeeds()
{
	if (htsock == none) return;
	for (UpdatePos = UpdatePos; UpdatePos < Feeds.Length; UpdatePos++)
	{
		if (!Feeds[UpdatePos].rssEnabled) continue;
		if (Feeds[UpdatePos].TimeStamp < htsock.now()-(iUpdateInterval*60))
		{
			Feeds[UpdatePos].Update(htsock);
			return;
		}
	}
}

/** process the updated RSS feed */
function ProcessRSSUpdate()
{
	if (htsock.LastStatus == 200)
	{
		Feeds[UpdatePos].ProcessData(htsock);
	}
	else {
		log("RSS Feed update faile for"@Feeds[UpdatePos].rssHost);
		log("HTTP Result:"@htsock.ReturnHeaders[0]);
	}
	// get next feed
	UpdatePos++;
	UpdateRSSFeeds();
}


function SendMessage(coerce string Message, optional PlayerController Receiver)
{
	if (Receiver != none) Receiver.TeamMessage(none, Message, 'None');
	else level.Game.BroadcastHandler.Broadcast(none, Message);
}

/**
	Handle out mutate command, all start with "rss" 							<br />
	Commands:																	<br />
		help					show available commands							<br />
		list					list available feeds							<br />
		show #					show content of feed #							<br />
		...

	Admin only commands:														<br />
		start					enable the mutator								<br />
		stop					disable the mutator								<br />
		update #				update feed #									<br />
		enable #				enable feed #									<br />
		disable #				disable feed #									<br />
		remove #				remove feed #									<br />
		add name location		add a new feed									<br />
*/
function Mutate(string MutateString, PlayerController Sender)
{
	local array<string> cmd;
	local int i, m, n;

	super.Mutate(MutateString, Sender);
	if (bInteractive)
	{
		if (split(MutateString, " ", cmd) < 2) return;
		if (cmd[0] != "rss") return;
		if (!bEnabled)
		{
			if ((cmd[1] ~= "start") && (Sender.PlayerReplicationInfo.bAdmin))
			{
				bEnabled = true;
				if (Feeds.Length == 0) InitRSS();
				SendMessage("RSS Feed Mutator Enabled", Sender); // TODO: Localize
			}
			else {
				SendMessage("RSS Feed Mutator Enabled", Sender); // TODO: The RSS Feed Mutator has been disabled
			}
			return;
		}

		if (cmd[1] ~= "list")
		{
			SendMessage("Available RSS Feeds:", Sender); // TODO: Localize
			for (i = 0; i < Feeds.Length; i++)
			{
				SendMessage("("$i$")"@Feeds[i].ChanTitle@"-"@Feeds[i].ChanDesc, Sender);
			}
		}
		else if (cmd[1] ~= "show")
		{
			if (cmd.Length > 2) m = int(cmd[2]);
			m = clamp(0, m, Feeds.Length);
			if (cmd.Length > 3) n = int(cmd[3]); else n = 5; // TODO: config
			n = clamp(1, n, Feeds[m].Titles.Length);
			SendMessage("-"@Feeds[m].ChanTitle@"-", Sender);
			for (i = 0; (i < n) && (i < Feeds[m].Titles.Length); i++)
			{
				SendMessage(Feeds[m].Titles[i]@"-"@Feeds[m].Links[i], Sender);
			}
		}
		// Admin commands
		else if ((cmd[1] ~= "stop") && (Sender.PlayerReplicationInfo.bAdmin))
		{
			bEnabled = false;
			// TODO: Stop time
			SendMessage("RSS Feed Mutator DISABLED", Sender); // TODO: Localize
		}
	}
}

defaultproperties
{
	FriendlyName="RSS Feeds"
	Description="Channel the content of RSS Feeds to the server"
	GroupName="RSS"

	bEnabled=true
	bBroadcastEnabled=true
	fBroadcastDelay=300
	bInteractive=true
	bUpdateEnabled=true
	iUpdateInterval=45
}
