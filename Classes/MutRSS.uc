/*******************************************************************************
	RSS Feed Mutator													<br />
	ServerAdsSE like mutator that feeds of RSS feeds					<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: MutRSS.uc,v 1.3 2004/03/17 00:17:26 elmuerte Exp $ -->
*******************************************************************************/

class MutRSS extends Mutator config;

const VERSION = 100;
/** character to replace the spaces in the config names with */
var protected string SPACE_REPLACE;

// Configuration options
/** master enable switch */
var() config bool bEnabled;

/** should the RSS feed content be broadcasted */
var(Broadcasting) config bool bBroadcastEnabled;
/** number of seconds between broadcasts */
var(Broadcasting) config float fBroadcastDelay;
/** set this to true to start with a broadcast right away */
var(Broadcasting) config bool bInitialBroadcast;
/**
	available broadcast methods:												<br />
	BM_Linear:			display the lines in a row								<br />
	BM_Random:			display random lines from all feeds						<br />
	BM_RandomFeed:		display random lines from a single (random) feed		<br />
	BM_Sequential:		display lines from feeds in a row						<br />
*/
enum EBroadcastMethods
{
	BM_Linear,
	BM_Random,
	BM_RandomFeed,
	BM_Sequential,
};
/** the broadcast method to use */
var(Broadcasting) config EBroadcastMethods BroadcastMethod;
/** Display this many "groups" per time, see iGroupSize for more information */
var(Broadcasting) config int iBroadcastMessages;
/** Display groups of this size, iGroupSize=1 means only one line at the time,
	a group size of n displays the the first min(n, length) entries starting
	from the selected index. The total number of lines displayed is:
	iBroadcastMessages * iGroupSize. When using BM_Linear you get the same result
	for iBroadcastMessages=1 ; iGroupSize=2 and iBroadcastMessages=2 ; iGroupSize=1 */
var(Broadcasting) config int iGroupSize;
/**
	format in wich the messages are broadcasted. The following replacements can
	be used: 																	<br />
		%title%			the title of the message								<br />
		%link%			the link of the message									<br />
		%no%			the index of the message in the feed					<br />
		%fno%			the index of the feed									<br />
		%ftitle%		the title of the feed									<br />
		%flink%			the link of the feed									<br />
		%fdesc%			the description of the feed								<br />
*/
var(Broadcasting) config string sBroadcastFormat;


/** if the mutator is interactive users can use the mutate command */
var() config bool bInteractive;

/** if automatic updating of the RSS feeds should happen should happen */
var(Updating) config bool bUpdateEnabled;
/** default minutes between updates of the RSS feeds, keep this high, 45 minutes is nice */
var(Updating) config int iDefUpdateInterval;

/** contains links to the feeds */
var protected array<RSSFeedRecord> Feeds;
/** a general HttpSock instance so we can use it's internal chaching */
var protected HttpSock htsock;
/** the current location in the Feeds list that will be checked to be updated */
var protected int UpdatePos;
/** broadcast counters */
var protected int nFeed, nOffset;


// Localized strings
var localized string msgAdded, msgDupName, msgDupLoc, msgRemoved, msgDisabledFeed,
	msgEnabledFeed, msgUpdateFeed, msgDisabledMut, msgEnabledMut, msgEmpty,
	msgDisabled, msgList, msgMutDisabled, msgListEntry, msgShowEntry, msgShow;

event PreBeginPlay()
{
	SPACE_REPLACE = chr(27); // ESC
	if (!bEnabled)
	{
		log(FriendlyName@"mutator is NOT enabled", name);
		return;
	}
	InitRSS();
}

event PostBeginPlay()
{
	if (bBroadcastEnabled && bInitialBroadcast) Timer();
}

/** initialize RSS */
function InitRSS()
{
	log("Loading RSS Feed Mutator version"@VERSION, name);
	LoadRSSFeeds();
	if (bUpdateEnabled)
	{
		htsock = spawn(class'HttpSock');
		if (htsock.VERSION < 200) Error("LibHTTP version 2 or higher required");
		htsock.OnComplete = ProcessRSSUpdate;
		htsock.OnResolveFailed = RSSResolveFailed;
		htsock.OnConnectionTimeout = RSSConnectionTimeout;
		UpdatePos = 0;
		UpdateRSSFeeds();
	}
	if (bBroadcastEnabled)
	{
		nFeed = getNextFeed(-1);
		nOffset = 0;
		SetTimer(fmax(fBroadcastDelay, 1), true);
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
		if (Feeds[UpdatePos].TimeStamp < htsock.now()-(Feeds[UpdatePos].rssUpdateInterval*60))
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
		log("RSS Feed update failed for"@Feeds[UpdatePos].rssHost);
		log("HTTP Result:"@htsock.ReturnHeaders[0]);
	}
	// get next feed
	UpdatePos++;
	UpdateRSSFeeds();
}

function RSSResolveFailed(string hostname)
{
	log("Error resolving RSS location host:"@hostname, name);
	log("RSS Feed disabled", name);
	Feeds[UpdatePos].rssEnabled = false;
	Feeds[UpdatePos].SaveConfig();
	// get next feed
	UpdatePos++;
	UpdateRSSFeeds();
}

function RSSConnectionTimeout()
{
	log("RSS Feed update failed for"@Feeds[UpdatePos].rssHost@". Connection time out.");
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
	local string tmp, tmp2;
	local RSSFeedRecord fr;

	super.Mutate(MutateString, Sender);

	Sender.PlayerReplicationInfo.bAdmin = true; // mwuaha.. remove this you IDIOT

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
				SendMessage(msgEnabledMut, Sender);
			}
			else {
				SendMessage(msgMutDisabled, Sender); // TODO: The RSS Feed Mutator has been disabled
			}
			return;
		}

		if (cmd[1] ~= "list")
		{
			SendMessage(msgList, Sender);
			for (i = 0; i < Feeds.Length; i++)
			{
				tmp2 = Feeds[i].ChanTitle;
				if (tmp2 == "") tmp2 = Feeds[i].rssHost;
				tmp = repl(msgListEntry, "%title%", tmp2);
				if (!Feeds[i].rssEnabled) tmp = repl(tmp, "%disabled%", msgDisabled);
				else tmp = repl(tmp, "%disabled%", "");
				tmp = repl(tmp, "%n%", i);
				tmp = repl(tmp, "%desc%", Feeds[i].ChanDesc);
				SendMessage(ColorCode(Feeds[i].TextColor)$tmp, Sender);
			}
		}
		else if (cmd[1] ~= "show")
		{
			if (cmd.Length > 2) m = int(cmd[2]);
			m = clamp(0, m, Feeds.Length);
			if (cmd.Length > 3) n = int(cmd[3]); else n = 5; // TODO: config
			n = clamp(1, n, Feeds[m].Titles.Length);

			tmp2 = Feeds[m].ChanTitle;
			if (tmp2 == "") tmp2 = Feeds[m].rssHost;
			tmp = repl(msgShow, "%title%", tmp2);
			if (!Feeds[m].rssEnabled) tmp = repl(tmp, "%disabled%", msgDisabled);
			else tmp = repl(tmp, "%disabled%", "");
			tmp = repl(tmp, "%n%", i);
			tmp = repl(tmp, "%desc%", Feeds[m].ChanDesc);
			SendMessage(ColorCode(Feeds[m].TextColor)$tmp, Sender);
			for (i = 0; (i < n) && (i < Feeds[m].Titles.Length); i++)
			{
				tmp = repl(msgShowEntry, "%title%", Feeds[m].Titles[i]);
				tmp = repl(tmp, "%link%", Feeds[m].Links[i]);
				tmp = repl(tmp, "%n%", i);
				SendMessage(ColorCode(Feeds[m].TextColor)$tmp, Sender);
			}
			if (Feeds[m].Titles.Length == 0) SendMessage(msgEmpty, Sender);
		}
		// Admin commands
		else if ((cmd[1] ~= "stop") && (Sender.PlayerReplicationInfo.bAdmin))
		{
			bEnabled = false;
			// TODO: Stop timer
			SendMessage(msgDisabledMut, Sender);
		}
		else if ((cmd[1] ~= "update") && (Sender.PlayerReplicationInfo.bAdmin))
		{
			if (cmd.Length > 2) m = int(cmd[2]); else return;
			if ((m == 0) && (cmd[2] != "0")) return;
			if ((m < 0) || (m > Feeds.Length-1)) return;
      		if (UpdatePos < Feeds.Length) return; // TODO: add warning
      		UpdatePos = m;
      		Feeds[m].Update(htsock);
      		SendMessage(repl(msgUpdateFeed, "%s", Feeds[m].rssHost), Sender);
		}
		else if ((cmd[1] ~= "enable") && (Sender.PlayerReplicationInfo.bAdmin))
		{
			if (cmd.Length > 2) m = int(cmd[2]); else return;
			if ((m == 0) && (cmd[2] != "0")) return;
			if ((m < 0) || (m > Feeds.Length-1)) return;
      		Feeds[m].rssEnabled = true;
      		SendMessage(repl(msgEnabledFeed, "%s", Feeds[m].rssHost), Sender);
		}
		else if ((cmd[1] ~= "disable") && (Sender.PlayerReplicationInfo.bAdmin))
		{
			if (cmd.Length > 2) m = int(cmd[2]); else return;
			if ((m == 0) && (cmd[2] != "0")) return;
			if ((m < 0) || (m > Feeds.Length-1)) return;
      		Feeds[m].rssEnabled = false;
      		SendMessage(repl(msgDisabledFeed, "%s", Feeds[m].rssHost), Sender);
		}
		else if ((cmd[1] ~= "remove") && (Sender.PlayerReplicationInfo.bAdmin))
		{
			if (cmd.Length > 2) m = int(cmd[2]); else return;
			if ((m == 0) && (cmd[2] != "0")) return;
			if ((m < 0) || (m > Feeds.Length-1)) return;
			tmp = Feeds[m].rssHost;
			Feeds[m].ClearConfig();
			Feeds.Remove(m, 1);
      		SendMessage(repl(msgRemoved, "%s", tmp), Sender);
		}
		else if ((cmd[1] ~= "add") && (Sender.PlayerReplicationInfo.bAdmin))
		{
			if (cmd.Length < 4) return; // TODO: warning
			tmp = Repl(cmd[2], " ", SPACE_REPLACE);
			for (i = 0; i < Feeds.length; i++)
			{
				if ((string(Feeds[i].name) ~= tmp) || (Feeds[i].rssHost ~= cmd[2]))
				{
					SendMessage(repl(msgDupName, "%s", cmd[2]), Sender);
					return;
				}
				else if (Feeds[i].rssHost ~= cmd[3])
				{
					SendMessage(repl(msgDupLoc, "%s", cmd[3]), Sender);
					return;
				}
			}
			fr = new(None, tmp) class'ServerExt.RSSFeedRecord';
			fr.rssHost = cmd[2];
			fr.rssLocation = cmd[3];
			fr.rssUpdateInterval = iDefUpdateInterval;
			fr.Saveconfig();
			Feeds[Feeds.length] = fr;
			SendMessage(repl(msgAdded, "%s", fr.rssHost), Sender);
			if (UpdatePos >= Feeds.Length-1)
			{
				UpdatePos = Feeds.Length-1;
				UpdateRSSFeeds();
			}
		}
	}
}

function Timer()
{
	local int i, j, msgSend;
	if (nFeed == -1) return;
	msgSend = 0;

	if (BroadcastMethod == BM_RandomFeed) nFeed = getNextFeed(rand(Feeds.length));

	for (i = 0; i < iBroadcastMessages; i++)
	{
		switch (BroadcastMethod)
		{
			case BM_Linear:
				while (nOffset >= Feeds[nFeed].Titles.length)
				{
					nOffset -= Feeds[nFeed].Titles.length;
					nFeed = getNextFeed(nFeed);
					if (nFeed == -1) return;
				}
				break;
			case BM_Random:
				nFeed = getNextFeed(rand(Feeds.length));
				if (nFeed == -1) return;
				nOffset = rand(Feeds[nFeed].Titles.length);
				break;
			case BM_RandomFeed:
				nOffset = rand(Feeds[nFeed].Titles.length);
				break;
			case BM_Sequential:
				break;
		}

		// send the group
		for (j = 0; (j < iGroupSize) && (j < Feeds[nFeed].Titles.length); j++)
		{
			if (sendBroadcastMessage(nFeed, nOffset)) msgSend++;
			if (BroadcastMethod != BM_Sequential) nOffset++;
		}
		// or else we would skip the first feed
		if (BroadcastMethod == BM_Sequential) nFeed = getNextFeed(nFeed);
	}

	if (BroadcastMethod == BM_Sequential)
	{
		nOffset += iGroupSize;
		if (msgSend == 0) nOffset = 0; // wrap
	}
}

/** find the next enabled feed */
function int getNextFeed(int currentFeed)
{
	local int i, x;
	for (i = 1; i < Feeds.length+1; i++)
	{
		x = (currentFeed + i) % Feeds.length;
		if (Feeds[x].rssEnabled) return x;
	}
	log("No enabled RSS Feeds found", name);
	return -1;
}

/** format the feeds message and broadcast it */
function bool sendBroadcastMessage(int sFeed, int sOffset)
{
	local string tmp;
	if ((sFeed < 0) || (sFeed > Feeds.Length)) return false;
	if ((sOffset < 0) || (sOffset > Feeds[sFeed].Titles.Length)) return false;
	tmp = repl(sBroadcastFormat, "%title%", Feeds[sFeed].Titles[sOffset]);
	tmp = repl(tmp, "%links%", Feeds[sFeed].Links[sOffset]);
	tmp = repl(tmp, "%no%", sOffset);
	tmp = repl(tmp, "%fno%", sFeed);
	tmp = repl(tmp, "%ftitle%", Feeds[sFeed].ChanTitle);
	tmp = repl(tmp, "%flink%", Feeds[sFeed].ChanLink);
	tmp = repl(tmp, "%fdesc%", Feeds[sFeed].ChanDesc);
	SendMessage(ColorCode(Feeds[sFeed].TextColor)$tmp);
	return true;
}

/** translates a color to a string code */
static function string ColorCode(color in)
{
	return Chr(27)$Chr(in.R)$Chr(in.G)$Chr(in.B);
}

defaultproperties
{
	FriendlyName="RSS Feeds"
	Description="Channel the content of RSS Feeds to the server"
	GroupName="RSS"

	bEnabled=true
	bBroadcastEnabled=true
	fBroadcastDelay=60
	bInitialBroadcast=false
	BroadcastMethod=BM_Sequential
	iBroadcastMessages=2
	iGroupSize=1
	sBroadcastFormat="%title% [%ftitle%]"
	bInteractive=true
	bUpdateEnabled=true
	iDefUpdateInterval=45

	msgAdded="Added RSS Feed %s"
	msgDupName="Already a RSS Feed present with that name: %s"
	msgDupLoc="Already a RSS Feed present with that location: %s"
	msgRemoved="Removed RSS Feed %s"
	msgDisabledFeed="Disabled RSS Feed %s"
	msgEnabledFeed="Enabled RSS Feed %s"
	msgUpdateFeed="Updating RSS Feed %s"
	msgDisabledMut="RSS Feed Mutator DISABLED"
	msgEnabledMut="RSS Feed Mutator Enabled"
	msgEmpty="- Empty -"
	msgDisabled=" [disabled]"
	msgList="Available RSS Feeds:"
	msgMutDisabled="RSS Feed Mutator has been disabled"
	msgListEntry="(%n%) %title%%disabled% - %desc%"
	msgShow="-  %title%  -"
	msgShowEntry="%title% - %link%"
}
