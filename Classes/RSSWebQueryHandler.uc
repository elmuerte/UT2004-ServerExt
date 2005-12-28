/*******************************************************************************
    WebAdmin Query Handler                                              <br />
    This will allow you to add/remove feeds from the webadmin           <br />

    (c) 2004, Michiel "El Muerte" Hendriks                              <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: RSSWebQueryHandler.uc,v 1.8 2005/12/28 14:46:09 elmuerte Exp $ -->
*******************************************************************************/

class RSSWebQueryHandler extends SExWebQueryHandler;

var protected MutRSS MutRSS;

function bool Init()
{
    foreach AllObjects(class'MutRSS', MutRSS)
    {
        if (MutRSS != none) break;
    }
    return ValidateRequirements(MutRSS != none);
}

function bool Query(WebRequest Request, WebResponse Response)
{
    if (super.Query(Request, Response)) return true;
    switch (Mid(Request.URI, 1))
    {
        case DefaultPage:   QueryFeeds(Request, Response); return true;
    }
    return false;
}

function QueryFeeds(WebRequest Request, WebResponse Response)
{
    local string tmp;
    local int i, feedid;
    local RSSFeedRecord fr;

    if (Request.GetVariable("submit", "") ~= "add")
    {
        tmp = repl(Request.GetVariable("rssHost", ""), " ", MutRSS.SPACE_REPLACE);
        if (tmp != "")
        {
            fr = new(None, tmp) MutRSS.RSSFeedRecordClass;
            fr.rssEnabled = Request.GetVariable("rssEnabled", "") ~= "true";
            fr.rssHost = Request.GetVariable("rssHost", "");
            fr.rssLocation = Request.GetVariable("rssLocation", "");
            fr.rssUpdateInterval = max(0, int(Request.GetVariable("rssUpdateInterval", string(MutRSS.iDefUpdateInterval))));
            fr.Save();
            MutRSS.Feeds[MutRSS.Feeds.length] = fr;
            feedid = MutRSS.Feeds.length-1;
        }
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
        fr.Save();
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
    else if (Request.GetVariable("submit", "") ~= "edit-entry")
    {
        feedid = int(Request.GetVariable("feedid", "0"));
        fr = MutRSS.Feeds[feedid];
        tmp = Request.GetVariable("action" , "");
        i = int(Request.GetVariable("entry_id", "0"));
        if (tmp ~= "update")
        {
            if (i >= fr.Entries.length) fr.Entries.length = i+1;
            fr.Entries[i].Title = Request.GetVariable("entry_title" , "");
            fr.Entries[i].Link = Request.GetVariable("entry_link" , "");
            fr.Entries[i].Desc = Request.GetVariable("entry_description" , "");
        }
        else if (tmp ~= "delete")
        {
            if (i < fr.Entries.length) fr.Entries.Remove(i, 1);
        }
        else if (tmp ~= "up")
        {
            if ((i > 0) && (i < fr.Entries.length))
            {
                fr.Entries.Insert(i-1, 1);
                fr.Entries[i-1] = fr.Entries[i+1];
                fr.Entries.Remove(i+1, 1);
            }
        }
        else if (tmp ~= "down")
        {
            if (i < fr.Entries.length)
            {
                fr.Entries.Insert(i+2, 1);
                fr.Entries[i+2] = fr.Entries[i];
                fr.Entries.Remove(i, 1);
            }
        }
        fr.Save();
    }

    if (fr != none)
    {
        Response.Subst("feedid", feedid);
        if (fr.rssEnabled) Response.Subst("rssEnabled", "checked=\"checked\"");
        Response.Subst("rssHost", fr.rssHost);
        Response.Subst("rssLocation", fr.rssLocation);
        Response.Subst("rssUpdateInterval", fr.rssUpdateInterval);
        Response.Subst("feed_action", "Update");
        tmp = "";
        for (i = 0; i < fr.Entries.length; i++)
        {
            if (i % 2 == 0) Response.Subst("altbg", "n");
            else Response.Subst("altbg", "nabg");
            Response.Subst("entry_id", i);
            Response.Subst("entry_title", HtmlEncode(UnescapeQuotes(fr.Entries[i].Title)));
            Response.Subst("entry_link", HtmlEncode(fr.Entries[i].Link));
            Response.Subst("entry_description", HtmlEncode(UnescapeQuotes(fr.Entries[i].Desc)));
            tmp $= Response.LoadParsedUHTM(Path $ SkinPath $ "/" $ "rssfeeds_lineentry.inc");
        }
        if (i % 2 == 0) Response.Subst("altbg", "n");
        else Response.Subst("altbg", "nabg");
        Response.Subst("entry_id", i);
        Response.Subst("entry_title", "");
        Response.Subst("entry_link", "");
        Response.Subst("entry_description", "");
        tmp $= Response.LoadParsedUHTM(Path $ SkinPath $ "/" $ "rssfeeds_lineentry.inc");
        Response.Subst("feed_entries", tmp);
    }
    else {
        Response.Subst("rssUpdateInterval", MutRSS.iDefUpdateInterval);
        //Response.Subst("TextColor", class'RSSFeedRecord'.default.TextColor);
        Response.Subst("feed_action", "Add");
        Response.Subst("feed_entries", "");
    }

    tmp = "";
    for (i = 0; i < MutRSS.Feeds.Length; i++)
    {
        tmp $= "<option value=\""$i$"\">"$MutRSS.Feeds[i].rssHost$"</option>";
    }
    Response.Subst("feed_select", tmp);
    ShowPage(Response, DefaultPage);
}

/** fix a bug for escaped double qoutes in dynamic struct arrays */
static function string UnescapeQuotes(string in)
{
    return repl(in, "\\\"", "\"");
}

defaultproperties
{
    DefaultPage="rssfeeds"
    Title="RSS Feeds"
    NeededPrivs=""
}
