/*******************************************************************************
	RSS Feed Mutator													<br />
	ServerAdsSE like mutator that feeds of RSS feeds					<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />
	$Id: MutRSS.uc,v 1.2 2004/03/15 22:29:25 elmuerte Exp $
*******************************************************************************/

class MutRSS extends Mutator config;

const VERSION = 100;
/** character to replace the spaces in the config names with */
var protected string SPACE_REPLACE;

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
/** default minutes between updates of the RSS feeds, keep this high, 45 minutes is nice */
var() config int iDefUpdateInterval;

/** contains links to the feeds */
var protected array<RSSFeedRecord> Feeds;
/** a general HttpSock instance so we can use it's internal chaching */
var protected HttpSock htsock;
/** the current location in the Feeds list that will be checked to be updated */
var protected int UpdatePos;


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

/** initialize RSS */
function InitRSS()
{
	log("Loading RSS Feed Mutator version"@VERSION, name);
	LoadRSSFeeds();
	if (bUpdateEnabled)
	{
		htsock = spawn(class'HttpSock');
		htsock.iVerbose = 255;
		htsock.OnComplete = ProcessRSSUpdate;
		htsock.OnResolveFailed = RSSResolveFailed;
		htsock.OnConnectionTimeout = RSSConnectionTimeout;
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

/** translates a color to a string code */
function string ColorCode(color in)
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
	fBroadcastDelay=300
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
