/*******************************************************************************
	client server portal to send feeds to the RSS Browser				<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: RSSBrowserPortalBase.uc,v 1.1 2004/03/19 21:40:39 elmuerte Exp $ -->
*******************************************************************************/

class RSSBrowserPortalBase extends Info abstract;

var string BrowserMenu;
var MutRSS RSSSource;

replication
{
	reliable if (Role == ROLE_Authority)
		OpenBrowser, AddFeed;

	reliable if (Role < ROLE_Authority)
		GetFeeds;
}

/** open de browser */
simulated function OpenBrowser(optional string Param1, optional string Param2)
{
	PlayerController(Owner).ClientOpenMenu(BrowserMenu, false, param1, param2);
}

simulated function AddFeed(int id, string ChannelName);

simulated function FeedDesc(int id, string desc);
simulated function FeedLink(int id, string link);

simulated function AddEntry(int id, string Title, string Link);
simulated function AddEntryDesc(int id, string desc);

function GetFeeds()
{
	local int i;
	local string tmp;
	for (i = 0; i < RSSSource.Feeds.Length; i++)
	{
		tmp = RSSSource.Feeds[i].ChannelTitle;
		if (tmp == "") tmp = RSSSource.Feeds[i].rssHost;
		AddFeed(i, tmp);
	}
}

function GetFeed(int id)
{
	local int i;
	if (id >= RSSSource.Feeds.Length) return;
	if (id < 0) return;
	FeedLink(id, RSSSource.Feeds[id].ChannelLink);
	FeedDesc(id, RSSSource.Feeds[id].ChannelDescription);
	for (i = 0; i < RSSSource.Feeds[id].Entries.length; i++)
	{
		AddEntry(i, RSSSource.Feeds[id].Entries[i].Title, RSSSource.Feeds[id].Entries[i].Link);
		if (RSSSource.Feeds[id].Entries[i].Desc != "") AddEntryDesc(i, RSSSource.Feeds[id].Entries[i].Desc);
	}
}

defaultproperties
{
	RemoteRole=ROLE_AutonomousProxy
}
