/*******************************************************************************
	WebAdmin Query Handler												<br />
	This will allow you to add/remove feeds from the webadmin			<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: RSSWebQueryHandler.uc,v 1.3 2004/05/10 22:10:39 elmuerte Exp $ -->
*******************************************************************************/

class RSSWebQueryHandler extends xWebQueryHandler;

var protected MutRSS MutRSS;

function bool Init()
{
	local int i;
	foreach AllObjects(class'MutRSS', MutRSS)
	{
		if (MutRSS != none) break;
	}
	if (MutRSS == none)
	{
		for (i = 0; i < QueryHandlerClasses.length; i++)
		{
			if (QueryHandlerClasses[i] ~= string(class))
			{
				QueryHandlerClasses.remove(i, 1);
				Outer.SaveConfig();
			}
		}
		return false;
	}
	return true;
}

function bool Query(WebRequest Request, WebResponse Response)
{
	switch (Mid(Request.URI, 1))
	{
		case DefaultPage:	QueryFeeds(Request, Response); return true;
	}
}

function QueryFeeds(WebRequest Request, WebResponse Response)
{
	local string tmp;
	local int i, feedid;
	local RSSFeedRecord fr;

	if (Request.GetVariable("submit", "") ~= "add")
	{
		fr = new(None, Request.GetVariable("rssHost", "")) MutRSS.RSSFeedRecordClass;
		fr.rssEnabled = Request.GetVariable("rssEnabled", "") ~= "true";
		fr.rssHost = Request.GetVariable("rssHost", "");
		fr.rssLocation = Request.GetVariable("rssLocation", "");
		fr.rssUpdateInterval = max(0, int(Request.GetVariable("rssUpdateInterval", string(MutRSS.iDefUpdateInterval))));
		fr.Saveconfig();
		MutRSS.Feeds[MutRSS.Feeds.length] = fr;
		feedid = MutRSS.Feeds.length-1;
	}
	else if (Request.GetVariable("submit", "") ~= "edit")
	{
		if (Request.GetVariable("feedid", "0") != "new")
		{
			feedid = int(Request.GetVariable("feedid", "0"));
			fr = MutRSS.Feeds[feedid];
		}
	}
	else if (Request.GetVariable("submit", "") ~= "update")
	{
		feedid = int(Request.GetVariable("feedid", "0"));
		fr = MutRSS.Feeds[feedid];
		fr.rssEnabled = Request.GetVariable("rssEnabled", "") ~= "true";
		fr.rssHost = Request.GetVariable("rssHost", "");
		fr.rssLocation = Request.GetVariable("rssLocation", "");
		fr.rssUpdateInterval = max(0, int(Request.GetVariable("rssUpdateInterval", string(MutRSS.iDefUpdateInterval))));
		fr.Saveconfig();
	}
	else if (Request.GetVariable("submit", "") ~= "delete")
	{
		if ((Request.GetVariable("feedid", "0") != "new") && (Request.GetVariable("deleteConfirm", "") ~= "true"))
		{
			feedid = int(Request.GetVariable("feedid", "0"));
			fr = MutRSS.Feeds[feedid];
			fr.ClearConfig();
			MutRSS.Feeds.Remove(feedid, 1);
			fr = none;
		}
	}

	if (fr != none)
	{
		Response.Subst("feedid", feedid);
		if (fr.rssEnabled) Response.Subst("rssEnabled", "checked=\"checked\"");
		Response.Subst("rssHost", fr.rssHost);
		Response.Subst("rssLocation", fr.rssLocation);
		Response.Subst("rssUpdateInterval", fr.rssUpdateInterval);
		Response.Subst("feed_action", "Update");
	}
	else {
		Response.Subst("rssUpdateInterval", MutRSS.iDefUpdateInterval);
		//Response.Subst("TextColor", class'RSSFeedRecord'.default.TextColor);
		Response.Subst("feed_action", "Add");
	}

	for (i = 0; i < MutRSS.Feeds.Length; i++)
	{
		tmp $= "<option value=\""$i$"\">"$MutRSS.Feeds[i].rssHost$"</option>";
	}
	Response.Subst("feed_select", tmp);
	Response.Subst("PostAction", DefaultPage);
	ShowPage(Response, DefaultPage);
}

defaultproperties
{
	DefaultPage="rssfeeds"
	Title="RSS Feeds"
	NeededPrivs=""
}
