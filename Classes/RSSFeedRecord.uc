/*******************************************************************************
	RSS Feed Record														<br />
	Contains the data of an RSS File									<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />
	$Id: RSSFeedRecord.uc,v 1.2 2004/03/15 22:29:25 elmuerte Exp $
*******************************************************************************/

class RSSFeedRecord extends LibHTTP2.NewsFeed PerObjectConfig config(RSS);

/** name of this object */
var config string rssHost;
/** download location */
var config string rssLocation;
/** true if this feed is enabled */
var config bool rssEnabled;
/** minutes between updates, make this a nice value like 45 minutes */
var config int rssUpdateInterval;
/** the color to use when displaying the content of this feed */
var config color TextColor;

// RSS Entries
/** RSS Channel values */
var config string ChanTitle, ChanLink, ChanDesc;
/** UNIX timestamp of the last update */
var config int TimeStamp;
/** titles of the entries, maps 1 on 1 with Links */
var config array<string> Titles;
/** links of the entries, maps 1 on 1 with Titles */
var config array<string> Links;

struct HTMLSpecialCharItem
{
	var string from, to;
};
var array<HTMLSpecialCharItem> HTMLSpecialChars;

/** update the current feed, needs a HttpSock because we want to make use of the internal caching */
function Update(HttpSock sock)
{
	log("Updating RSS Feed"@rssHost, name);
	if (rssLocation != "") sock.HttpRequest(rssLocation);
	else Log("RSS Location is empty");
}

function ProcessData(HttpSock sock)
{
	local int i;

	if (ParseRDFData(sock.ReturnData) > 0)
	{
		ChanTitle = ChannelTitle;
		ChanLink = ChannelLink;
		ChanDesc = ChannelDescription;
		Titles.Length = Entries.Length;
		Links.Length = Entries.Length;
		for (i = 0; i < Entries.Length; i++)
		{
			Titles[i] = fixHTMLSpecialsChars(Entries[i].Title);
			Links[i] = fixHTMLSpecialsChars(Entries[i].Link);
		}

		TimeStamp = sock.now();
		SaveConfig();
		Log("Updated RSS Feed"@rssHost, name);
	}
	else {
		Log("RSS Feed was empty for "@rssHost, name);
	}
}

/** fill the line buffer */
protected function bool getLine()
{
	local string tmp;
	if (lineno >= data.length) return false;
	tmp = data[lineno];
	tmp = repl(tmp, Chr(9), " ");
	tmp = repl(tmp, "<", " <");
	tmp = repl(tmp, ">", "> ");
	split(tmp, " ", line);
	lineno++;
	wordno = 0;
	return true;
}

/** replaces HTML special chars */
protected function string fixHTMLSpecialsChars(coerce string in)
{
	local int i, j;
	local string tmp;
	// first &#<number>;
	i = InStr(in, "&#");
	while (i > -1)
	{
		tmp = Left(in, i);
		in = Mid(in, i);
		i = InStr(in, ";");
		j = int(Mid(in, 2, i-2));
		if (j < 32) j = 63; // == ?
		tmp $= Chr(j)$Mid(in, i+1);
		in = tmp;
		i = InStr(in, "&#");
	}
	// then lookup table
	for (i = 0; i < HTMLSpecialChars.length; i++)
	{
		in = repl(in, HTMLSpecialChars[i].from, HTMLSpecialChars[i].to);
	}
	return in;
}

defaultproperties
{
	rssEnabled=true
	rssUpdateInterval=45
	TextColor=(R=255,G=255,B=0)

	HTMLSpecialChars(0)=(from="&amp;",to="&")
	HTMLSpecialChars(1)=(from="&quote;",to="\"")
	HTMLSpecialChars(2)=(from="&squote;",to="'")
	HTMLSpecialChars(3)=(from="&nbsp;",to=" ")
	HTMLSpecialChars(4)=(from="&lt;",to="<")
	HTMLSpecialChars(5)=(from="&gt;",to=">")
	HTMLSpecialChars(6)=(from="&copy;",to="©")
	HTMLSpecialChars(7)=(from="&reg;",to="®")
}

