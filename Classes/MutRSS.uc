/*******************************************************************************
    RSS Feed Mutator                                                    <br />
    ServerAdsSE like mutator that feeds of RSS feeds                    <br />

    (c) 2004-2006, Michiel "El Muerte" Hendriks                         <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: MutRSS.uc,v 1.27 2006/01/14 15:45:02 elmuerte Exp $ -->
*******************************************************************************/

class MutRSS extends Mutator config;

#include classes/const.inc

const VERSION = 105;
/** character to replace the spaces in the config names with */
var string SPACE_REPLACE;

// Configuration options
/** master enable switch */
var(Config) globalconfig bool bEnabled;
/** announce to the masterserver and clients that we are running this mutator */
var(Config) globalconfig bool bAnnounce;
/** comma seperated list with feeds to use, leave blank to use all feeds */
var(Config) globalconfig string sExlusiveFeeds;
/** the client side GUI browser portal to spawn on: "mutate rss browser", after
    spawning the Create event is called */
var(Config) globalconfig string BrowserPortal, BrowserMenu;
/** The WebAdmin Query handler */
var(Config) globalconfig string WebQueryHandler;

/** should the RSS feed content be broadcasted */
var(Broadcasting) globalconfig bool bBroadcastEnabled;
/** number of seconds between broadcasts */
var(Broadcasting) globalconfig float fBroadcastDelay;
/** set this to true to start with a broadcast right away */
var(Broadcasting) globalconfig bool bInitialBroadcast;
/**
    available broadcast methods:                                                <br />
    BM_Linear:          display the lines in a row                              <br />
    BM_Random:          display random lines from all feeds                     <br />
    BM_RandomFeed:      display random lines from a single (random) feed        <br />
    BM_Sequential:      display lines from feeds in a row                       <br />
*/
enum EBroadcastMethods
{
    BM_Linear,
    BM_Random,
    BM_RandomFeed,
    BM_Sequential,
};
/** the broadcast method to use */
var(Broadcasting) globalconfig EBroadcastMethods BroadcastMethod;
/** Display this many "groups" per time, see iGroupSize for more information */
var(Broadcasting) globalconfig int iBroadcastMessages;
/** Display groups of this size, iGroupSize=1 means only one line at the time,
    a group size of n displays the the first min(n, length) entries starting
    from the selected index. The total number of lines displayed is:
    iBroadcastMessages * iGroupSize. When using BM_Linear you get the same result
    for iBroadcastMessages=1 ; iGroupSize=2 and iBroadcastMessages=2 ; iGroupSize=1 */
var(Broadcasting) globalconfig int iGroupSize;
/**
    format in wich the messages are broadcasted. The following replacements can
    be used:                                                                    <br />
        %title%         the title of the message                                <br />
        %link%          the link of the message                                 <br />
        %desc%          the content/description of the message                  <br />
        %no%            the index of the message in the feed                    <br />
        %fno%           the index of the feed                                   <br />
        %ftitle%        the title of the feed                                   <br />
        %flink%         the link of the feed                                    <br />
        %fdesc%         the description of the feed                             <br />
*/
var(Broadcasting) globalconfig string sBroadcastFormat;


/** if the mutator is interactive users can use the mutate command */
var(Interaction) globalconfig bool bInteractive;
/** if set to true the user can use 'rss browser' for a client side RSS browser */
var(Interaction) globalconfig bool bBrowserEnabled;

/** if automatic updating of the RSS feeds should happen should happen */
var(Updating) globalconfig bool bUpdateEnabled;
/** default minutes between updates of the RSS feeds, keep this high, 45 minutes is nice */
var(Updating) globalconfig int iDefUpdateInterval;

/**
    sets the Feed Record class name to use for feed records, you should change this
    when you know what your are doing
*/
var(AdvancedConfig) globalconfig string RSSFeedRecordClassName;
var class<RSSFeedRecord> RSSFeedRecordClass;

/** contains links to the feeds */
var array<RSSFeedRecord> Feeds;
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
/** Play Info descriptions */
var localized string piDesc[15],piHelp[15];
var localized string piOpt[2];
var localized string msgHelp[5], msgAdminHelp[7];

var ServerExtDummyPlayer DummyPC;

event PreBeginPlay()
{
    SPACE_REPLACE = chr(27); // ESC
    // unless RSSFeedRecordClassName is set load the default class
    RSSFeedRecordClass = class<RSSFeedRecord>(DynamicLoadObject(repl(RSSFeedRecordClassName, "%clientpackage%", ClientSidePackageRSS), class'Class'));
    if (RSSFeedRecordClass == none)
    {
        error(RSSFeedRecordClassName@"is not a valid RSSFeedRecord class");
        return;
    }
    if (!bEnabled)
    {
        log(FriendlyName@"mutator is NOT enabled", name);
        return;
    }
    InitRSS();
    if (bBrowserEnabled && (int(Level.EngineVersion) > 3195))
    {
        AddToPackageMap(ClientSidePackageRSS);
        AddToPackageMap(LibHTTPPackage);
    }
}

event PostBeginPlay()
{
    if (bBroadcastEnabled && bInitialBroadcast) Timer();
    LoadWebAdmin();
    if (Level.Game.BroadcastHandler.IsA('UT2VoteChatHandler'))
    {
        DummyPC = spawn(class'ServerExtDummyPlayer');
        Log("Spawning UT2Vote fix PlayerController for MutRSS", name);
    }
}

function LoadWebAdmin()
{
    local UTServerAdmin webadmin;
    local int i;
    local class<xWebQueryHandler> qh;

    foreach AllObjects(class'UTServerAdmin', webadmin) if (webadmin != none) break;
    if (webadmin == none)
    {
        for (i = 0; i < class'UTServerAdmin'.default.QueryHandlerClasses.Length; i++)
        {
            if (class'UTServerAdmin'.default.QueryHandlerClasses[i] == WebQueryHandler) break;
        }
        if (i >= class'UTServerAdmin'.default.QueryHandlerClasses.Length)
        {
            class'UTServerAdmin'.default.QueryHandlerClasses[class'UTServerAdmin'.default.QueryHandlerClasses.Length] = WebQueryHandler;
            class'UTServerAdmin'.static.StaticSaveConfig();
            log("Added query handler"@WebQueryHandler, name);
        }
        return;
    }
    for (i = 0; i < webadmin.QueryHandlerClasses.Length; i++)
    {
        if (webadmin.QueryHandlerClasses[i] == WebQueryHandler) break;
    }
    if (i >= webadmin.QueryHandlerClasses.Length)
    {
        webadmin.QueryHandlerClasses.Length = webadmin.QueryHandlerClasses.Length+1;
        webadmin.QueryHandlerClasses[webadmin.QueryHandlerClasses.Length-1] = WebQueryHandler;
        qh = class<xWebQueryHandler>(DynamicLoadObject(repl(WebQueryHandler, "%clientpackage%", ClientSidePackageRSS), class'Class'));
        if (qh != none)
        {
            webadmin.QueryHandlers.length = webadmin.QueryHandlers.length+1;
            webadmin.QueryHandlers[webadmin.QueryHandlers.Length-1] = new(webadmin) qh;
            log("Loaded"@WebQueryHandler, name);
        }
        else log("No valid QueryHandler"@WebQueryHandler, name);
        webadmin.SaveConfig();
    }
}

/** initialize RSS */
function InitRSS()
{
    log("Loading RSS Feed Mutator version"@VERSION, name);
    LoadRSSFeeds();
    if (bUpdateEnabled)
    {
        htsock = spawn(class'LibHTTP4.HttpSock');
        if (htsock.VERSION < 350) Error("LibHTTP version 3.5 or higher required");
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
    local array<string> items, exclFeeds;
    local int i, j;
    local RSSFeedRecord item;

    log("Loading RSS feeds from "$RSSFeedRecordClass.default.ConfigFile$".ini", name);
    items = GetPerObjectNames(RSSFeedRecordClass.default.ConfigFile, string(RSSFeedRecordClass.Name));
    if (sExlusiveFeeds != "") split(sExlusiveFeeds, ",", exclFeeds);
    if (exclFeeds.length > 0)
    {
        for (i = items.length-1; i >= 0; i--)
        {
            for (j = 0; j < exclFeeds.Length; j++)
            {
                if (exclFeeds[j] ~= items[i])
                {
                    log(exclFeeds[j]);
                    break;
                }
            }
            if (j < exclFeeds.Length) continue; // in the list
            items.remove(i, 1);
        }
    }
    for (i = 0; i < items.Length; i++)
    {
        if (items[i] == "") continue;

        item = new(None, Repl(items[i], " ", SPACE_REPLACE)) RSSFeedRecordClass;
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
        if (Feeds[UpdatePos].rssUpdateInterval <= 0) continue;
        if (Feeds[UpdatePos].LastUpdate < htsock.now()-(Feeds[UpdatePos].rssUpdateInterval*60))
        {
            Feeds[UpdatePos].Update(htsock);
            return;
        }
    }
}

/** process the updated RSS feed */
function ProcessRSSUpdate(HttpSock sender)
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

function RSSResolveFailed(HttpSock sender, string hostname)
{
    log("Error resolving RSS location host:"@hostname, name);
    log("RSS Feed disabled", name);
    Feeds[UpdatePos].rssEnabled = false;
    Feeds[UpdatePos].Save();
    // get next feed
    UpdatePos++;
    UpdateRSSFeeds();
}

function RSSConnectionTimeout(HttpSock sender)
{
    log("RSS Feed update failed for"@Feeds[UpdatePos].rssHost@". Connection time out.");
    // get next feed
    UpdatePos++;
    UpdateRSSFeeds();
}

function SendMessage(coerce string Message, optional PlayerController Receiver)
{
    if (Receiver != none) Receiver.TeamMessage(none, Message, 'None');
    else level.Game.BroadcastHandler.Broadcast(DummyPC, Message);
}

/**
    Handle out mutate command, all start with "rss"                             <br />
    Commands:                                                                   <br />
        help                    show available commands                         <br />
        list                    list available feeds                            <br />
        show #                  show content of feed #                          <br />
        ...

    Admin only commands:                                                        <br />
        start                   enable the mutator                              <br />
        stop                    disable the mutator                             <br />
        update #                update feed #                                   <br />
        enable #                enable feed #                                   <br />
        disable #               disable feed #                                  <br />
        remove #                remove feed #                                   <br />
        add name location       add a new feed                                  <br />
*/
function Mutate(string MutateString, PlayerController Sender)
{
    local array<string> cmd;
    local int i, m, n;
    local string tmp, tmp2;
    local RSSFeedRecord fr;

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
                tmp2 = Feeds[i].ChannelTitle;
                if (tmp2 == "") tmp2 = Feeds[i].rssHost;
                tmp = repl(msgListEntry, "%title%", tmp2);
                if (!Feeds[i].rssEnabled) tmp = repl(tmp, "%disabled%", msgDisabled);
                else tmp = repl(tmp, "%disabled%", "");
                tmp = repl(tmp, "%n%", i);
                tmp = repl(tmp, "%desc%", Feeds[i].ChannelLink);
                SendMessage(ColorCode(Feeds[i].TextColor)$tmp, Sender);
            }
        }
        else if (cmd[1] ~= "show")
        {
            if (cmd.Length > 2) m = int(cmd[2]);
            m = clamp(0, m, Feeds.Length);
            if (cmd.Length > 3) n = int(cmd[3]); else n = 5; // TODO: config
            n = clamp(1, n, Feeds[m].Entries.Length);

            tmp2 = Feeds[m].ChannelTitle;
            if (tmp2 == "") tmp2 = Feeds[m].rssHost;
            tmp = repl(msgShow, "%title%", tmp2);
            if (!Feeds[m].rssEnabled) tmp = repl(tmp, "%disabled%", msgDisabled);
            else tmp = repl(tmp, "%disabled%", "");
            tmp = repl(tmp, "%n%", i);
            tmp = repl(tmp, "%desc%", Feeds[m].ChannelDescription);
            SendMessage(ColorCode(Feeds[m].TextColor)$tmp, Sender);
            for (i = 0; (i < n) && (i < Feeds[m].Entries.Length); i++)
            {
                tmp = repl(msgShowEntry, "%title%", UnescapeQuotes(Feeds[m].Entries[i].Title));
                tmp = repl(tmp, "%link%", Feeds[m].Entries[i].Link);
                tmp = repl(tmp, "%n%", i);
                SendMessage(ColorCode(Feeds[m].TextColor)$tmp, Sender);
            }
            if (Feeds[m].Entries.Length == 0) SendMessage(msgEmpty, Sender);
        }
        else if (cmd[1] ~= "browser")
        {
            if (bBrowserEnabled) SummonPortal(Sender);
        }
        else if (cmd[1] ~= "help")
        {
            for (i = 0; i < 5; i++)
            {
                SendMessage(msgHelp[i], Sender);
            }
            if (isAdmin(Sender))
            {
                for (i = 0; i < 8; i++)
                {
                    SendMessage(msgAdminHelp[i], Sender);
                }
            }
        }
        // Admin commands
        else if ((cmd[1] ~= "stop") && isAdmin(Sender))
        {
            bEnabled = false;
            SendMessage(msgDisabledMut, Sender);
        }
        else if ((cmd[1] ~= "update") && isAdmin(Sender))
        {
            if (cmd.Length > 2) m = int(cmd[2]); else return;
            if ((m == 0) && (cmd[2] != "0")) return;
            if ((m < 0) || (m > Feeds.Length-1)) return;
            if (UpdatePos < Feeds.Length) return; // TODO: add warning
            UpdatePos = m;
            Feeds[m].Update(htsock);
            SendMessage(repl(msgUpdateFeed, "%s", Feeds[m].rssHost), Sender);
        }
        else if ((cmd[1] ~= "enable") && isAdmin(Sender))
        {
            if (cmd.Length > 2) m = int(cmd[2]); else return;
            if ((m == 0) && (cmd[2] != "0")) return;
            if ((m < 0) || (m > Feeds.Length-1)) return;
            Feeds[m].rssEnabled = true;
            SendMessage(repl(msgEnabledFeed, "%s", Feeds[m].rssHost), Sender);
        }
        else if ((cmd[1] ~= "disable") && isAdmin(Sender))
        {
            if (cmd.Length > 2) m = int(cmd[2]); else return;
            if ((m == 0) && (cmd[2] != "0")) return;
            if ((m < 0) || (m > Feeds.Length-1)) return;
            Feeds[m].rssEnabled = false;
            SendMessage(repl(msgDisabledFeed, "%s", Feeds[m].rssHost), Sender);
        }
        else if ((cmd[1] ~= "remove") && isAdmin(Sender))
        {
            if (cmd.Length > 2) m = int(cmd[2]); else return;
            if ((m == 0) && (cmd[2] != "0")) return;
            if ((m < 0) || (m > Feeds.Length-1)) return;
            tmp = Feeds[m].rssHost;
            Feeds[m].ClearConfig();
            Feeds.Remove(m, 1);
            SendMessage(repl(msgRemoved, "%s", tmp), Sender);
        }
        else if ((cmd[1] ~= "add") && isAdmin(Sender))
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
            fr = new(None, tmp) RSSFeedRecordClass;
            fr.rssHost = cmd[2];
            fr.rssLocation = cmd[3];
            fr.rssUpdateInterval = iDefUpdateInterval;
            fr.Save();
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

/** return true if a player is an admin */
function bool isAdmin(PlayerController sender)
{
    if (Level.NetMode == NM_Standalone) return true;
    return sender.PlayerReplicationInfo.bAdmin;
}

/** open de client side RSS browser */
function SummonPortal(PlayerController sender)
{
    local class<RSSBrowserPortal> portalclass;
    local RSSBrowserPortal portal;
    portalclass = class<RSSBrowserPortal>(DynamicLoadObject(repl(BrowserPortal, "%clientpackage%", ClientSidePackageRSS), class'Class', false));
    if (portalclass == none) return;
    portal = spawn(portalclass, Sender);
    portal.BrowserMenu = repl(BrowserMenu, "%clientpackage%", ClientSidePackageRSS);
    portal.Created();
}

function Timer()
{
    local int i, j, msgSend;
    if (!bEnabled || !bBroadcastEnabled) return;
    if (nFeed == -1) return;
    msgSend = 0;

    if (BroadcastMethod == BM_RandomFeed) nFeed = getNextFeed(rand(Feeds.length));

    for (i = 0; i < iBroadcastMessages; i++)
    {
        switch (BroadcastMethod)
        {
            case BM_Linear:
                while (nOffset >= Feeds[nFeed].Entries.length)
                {
                    nOffset -= Feeds[nFeed].Entries.length;
                    nFeed = getNextFeed(nFeed);
                    if (nFeed == -1) return;
                }
                break;
            case BM_Random:
                nFeed = getNextFeed(rand(Feeds.length));
                if (nFeed == -1) return;
                nOffset = rand(Feeds[nFeed].Entries.length);
                break;
            case BM_RandomFeed:
                nOffset = rand(Feeds[nFeed].Entries.length);
                break;
            case BM_Sequential:
                break;
        }

        // send the group
        for (j = 0; (j < iGroupSize) && (nOffset < Feeds[nFeed].Entries.length); j++)
        {
            if (sendBroadcastMessage(nFeed, nOffset)) msgSend++;
            if (BroadcastMethod != BM_Sequential) nOffset++;
        }
        // or else we would skip the first feed
        if (BroadcastMethod == BM_Sequential)
        {
            j = getNextFeed(nFeed);
            if (nFeed == j) nOffset += iGroupSize;
            else nFeed = j;
        }
    }

    if (BroadcastMethod == BM_Sequential)
    {
        //nOffset += iGroupSize;
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
    if ((sOffset < 0) || (sOffset > Feeds[sFeed].Entries.Length)) return false;
    tmp = repl(sBroadcastFormat, "%title%", UnescapeQuotes(Feeds[sFeed].Entries[sOffset].Title));
    tmp = repl(tmp, "%links%", Feeds[sFeed].Entries[sOffset].Link);
    tmp = repl(tmp, "%desc%", UnescapeQuotes(Feeds[sFeed].Entries[sOffset].Desc));
    tmp = repl(tmp, "%no%", sOffset);
    tmp = repl(tmp, "%fno%", sFeed);
    tmp = repl(tmp, "%ftitle%", Feeds[sFeed].ChannelTitle);
    tmp = repl(tmp, "%flink%", Feeds[sFeed].ChannelLink);
    tmp = repl(tmp, "%fdesc%", Feeds[sFeed].ChannelDescription);
    SendMessage(ColorCode(Feeds[sFeed].TextColor)$tmp);
    return true;
}

/** translates a color to a string code */
static function string ColorCode(color in)
{
    return Chr(27)$Chr(max(in.R,1))$Chr(max(in.G,1))$Chr(max(in.B,1));
}

/** fix a bug for escaped double qoutes in dynamic struct arrays */
static function string UnescapeQuotes(string in)
{
    return repl(in, "\\\"", "\"");
}

static function FillPlayInfo(PlayInfo PlayInfo)
{
    Super.FillPlayInfo(PlayInfo);
    PlayInfo.AddSetting(default.FriendlyName, "bEnabled",           default.piDesc[0],  128, 1, "CHECK");
    PlayInfo.AddSetting(default.FriendlyName, "bAnnounce",          default.piDesc[14], 128, 1, "CHECK");
    PlayInfo.AddSetting(default.FriendlyName, "sExlusiveFeeds",     default.piDesc[11], 128, 1, "TEXT", "50;");

    PlayInfo.AddSetting(default.FriendlyName, "bBroadcastEnabled",  default.piDesc[1],  107, 10, "CHECK");
    PlayInfo.AddSetting(default.FriendlyName, "fBroadcastDelay",    default.piDesc[2],  107, 11, "TEXT", "10;1:9999");
    PlayInfo.AddSetting(default.FriendlyName, "bInitialBroadcast",  default.piDesc[3],  107, 12, "CHECK");
    PlayInfo.AddSetting(default.FriendlyName, "BroadcastMethod",    default.piDesc[4],  106, 13, "SELECT", default.piOpt[0]);
    PlayInfo.AddSetting(default.FriendlyName, "iBroadcastMessages", default.piDesc[5],  105, 14, "TEXT", "2;1:99");
    PlayInfo.AddSetting(default.FriendlyName, "iGroupSize",         default.piDesc[6],  105, 15, "TEXT", "2;1:99");
    PlayInfo.AddSetting(default.FriendlyName, "sBroadcastFormat",   default.piDesc[7],  104, 16, "TEXT", "50;");

    PlayInfo.AddSetting(default.FriendlyName, "bInteractive",       default.piDesc[8],   97, 20, "CHECK");
    PlayInfo.AddSetting(default.FriendlyName, "bBrowserEnabled",    default.piDesc[12],  97, 20, "CHECK");

    PlayInfo.AddSetting(default.FriendlyName, "bUpdateEnabled",     default.piDesc[9],  128, 20, "CHECK");
    PlayInfo.AddSetting(default.FriendlyName, "iDefUpdateInterval", default.piDesc[10], 128, 20, "TEXT", "5;1:99999");

    PlayInfo.AddSetting(default.FriendlyName, "RSSFeedRecordClassName", default.piDesc[13], 255, 255, "TEXT", "256");
}

static event string GetDescriptionText(string PropName)
{
    if (PropName ~= "bEnabled") return default.piHelp[0];
    if (PropName ~= "bAnnounce") return default.piHelp[14];
    if (PropName ~= "sExlusiveFeeds") return default.piHelp[11];
    if (PropName ~= "bBroadcastEnabled") return default.piHelp[1];
    if (PropName ~= "fBroadcastDelay") return default.piHelp[2];
    if (PropName ~= "bInitialBroadcast") return default.piHelp[3];
    if (PropName ~= "BroadcastMethod") return default.piHelp[4];
    if (PropName ~= "iBroadcastMessages") return default.piHelp[5];
    if (PropName ~= "iGroupSize") return default.piHelp[6];
    if (PropName ~= "sBroadcastFormat") return default.piHelp[7];
    if (PropName ~= "bInteractive") return default.piHelp[8];
    if (PropName ~= "bBrowserEnabled") return default.piHelp[12];
    if (PropName ~= "bUpdateEnabled") return default.piHelp[9];
    if (PropName ~= "iDefUpdateInterval") return default.piHelp[10];
    if (PropName ~= "RSSFeedRecordClassName") return default.piHelp[13];
    return Super.GetDescriptionText(PropName);
}

function GetServerDetails( out GameInfo.ServerResponseLine ServerState )
{
    local int i;
    local string tmp;
    if (bAnnounce) super.GetServerDetails(ServerState);
    ServerState.ServerInfo.Length = ServerState.ServerInfo.Length+1;
    ServerState.ServerInfo[ServerState.ServerInfo.Length-1].Key = "RSS Feeds";
    for (i = 0; i < Feeds.Length; i++)
    {
        if (tmp != "") tmp $= ", ";
        tmp $= Feeds[i].ChannelTitle;
    }
    ServerState.ServerInfo[ServerState.ServerInfo.Length-1].Value = tmp;
}


defaultproperties
{
    FriendlyName="RSS Feeds"
    Description="Channel the content of RSS Feeds to the server"
    GroupName="RSS"

    bEnabled=true
    bAnnounce=True;
    bBroadcastEnabled=true
    fBroadcastDelay=60
    bInitialBroadcast=false
    BroadcastMethod=BM_Sequential
    iBroadcastMessages=2
    iGroupSize=1
    sBroadcastFormat="%title% [%ftitle%]"
    bInteractive=true
    bBrowserEnabled=true
    bUpdateEnabled=true
    iDefUpdateInterval=45
    BrowserPortal="%clientpackage%.RSSBrowserPortal"
    BrowserMenu="%clientpackage%.MutRSSBrowser"
    WebQueryHandler="ServerExt.RSSWebQueryHandler"
    RSSFeedRecordClassName="%clientpackage%.RSSFeedRecord"

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

    piOpt[0]="BM_Linear;Linear;BM_Random;Random;BM_RandomFeed;Random Feed;BM_Sequential;Sequential"
    piDesc[0]="Global enable switch"
    piHelp[0]="This is the master switch, when set to false the mutator doesn't do anything"
    piDesc[1]="Broadcast enabled"
    piHelp[1]="Broadcast the feed content at a set interval. Turn this off when you don't want this spam"
    piDesc[2]="Broadcast delay"
    piHelp[2]="Seconds between broadcasts"
    piDesc[3]="Initial broadcast"
    piHelp[3]="Usualy the first broadcast is done after the initial delay has passed. When this is set to true the first broadcast will be done right after the mutator started"
    piDesc[4]="Broadcast method"
    piHelp[4]="The broadcast method to use. This will control in what order the messages are selected."
    piDesc[5]="Number of messages"
    piHelp[5]="Number of message groups to send per broadcast"
    piDesc[6]="Message group size"
    piHelp[6]="The size of a message group"
    piDesc[7]="Broadcast format"
    piHelp[7]="The way the message is constructed"
    piDesc[8]="Interactive"
    piHelp[8]="Is the mutator interactive, e.g. can people use the 'mutate rss' command"
    piDesc[9]="Updating enabled"
    piHelp[9]="Enable updating of the feeds. If you only have offline feeds set this to false to reduce some overhead."
    piDesc[10]="Default update time"
    piHelp[10]="Default update time for new feeds"
    piDesc[11]="Exlcusive feeds"
    piHelp[11]="Only use these feeds from all available feeds. This will override the enabled setting of each feed (when enabled). This is a comma delimited line of feed names."
    piDesc[12]="Client side browser"
    piHelp[12]="Enable the client side feed browser. Warning: this will increase the server bandwidth, all feed data is send to the client on request."
    piDesc[13]="RSS Feed Storage Record"
    piHelp[13]="The feed storage class, this is an advanced setting to use a different feed class it should only be changed if you know what you are doing."
    piDesc[14]="Announce"
    piHelp[14]="Announce to the masterserver and clients that we are running this mutator"

    msgHelp[0]="RSS Feed Mutator Help:"
    msgHelp[1]="mutate rss browser            show client side browser"
    msgHelp[2]="mutate rss help               show this message"
    msgHelp[3]="mutate rss list               show feed list"
    msgHelp[4]="mutate rss show n [m]         show m items from feed #n, m is 5 by default"

    msgAdminHelp[0]="mutate rss start              start the mutator, when it's disabled"
    msgAdminHelp[1]="mutate rss stop               stop the mutator"
    msgAdminHelp[2]="mutate rss update n           force an update on RSS feed #n"
    msgAdminHelp[3]="mutate rss enable n           enable RSS feed #n"
    msgAdminHelp[4]="mutate rss disable n          disable RSS feed #n"
    msgAdminHelp[5]="mutate rss remove n           remove RSS feed #n"
    msgAdminHelp[6]="mutate rss add name location  add a new RSS feed with name and download location"
}
