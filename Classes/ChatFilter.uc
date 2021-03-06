/*******************************************************************************
    ChatFilter filters the chat for bad words                           <br />

    (c) 2004-2006, Michiel "El Muerte" Hendriks                         <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: ChatFilter.uc,v 1.13 2006/01/14 15:45:02 elmuerte Exp $ -->
*******************************************************************************/

class ChatFilter extends BroadcastHandler config;

#include classes/const.inc

/** if set to true it will not try to find the right broadcast handler */
var config bool bDisableBHFix;

/** used to disable it via the WebAdmin */
var(Config) config bool bEnabled;

/** available chat filter actions */
enum ChatFilterAction
{
    CFA_Nothing,
    CFA_Kick,
    CFA_Ban,
    CFA_SessionBan,
    CFA_Defrag,
    CFA_Warn,
    CFA_Mute
};
/** available bad nick actions */
enum BNA
{
    BNA_Kick,
    BNA_Request,
    BNA_Ban,
    BNA_SessionBan
};

// SPAM check
/** timeframe length, in seconds, after each timeframe the score is reset */
var(Config) config float fTimeFrame;
/** maximum messages per timeframe */
var(Config) config int iMaxPerTimeFrame;
/** maximum repeats per timeframe */
var(Config) config int iMaxRepeat;
/** the score to add for spam */
var(Config) config int iScoreSpam;

// Foul language check
/** bad words */
var(Config) config array<string> BadWords;
/** word to replace the bad words with */
var(Config) config string CencorWord;
/** score to add for using bad words */
var(Config) config int iScoreSwear;
/** bad words are a replacement table */
var(Config) config bool bUseReplacementTable; // BadWords=> replace;with

// Nickname check
/** check for bad nicknames */
var(Config) config bool bCheckNicknames;
/** action to use for bad nick names */
var(Config) config BNA BadnickAction;
/** unallowed nick names */
var(Config) config array<string> UnallowedNicks;
/** nicknames contain wildcards */
var(Config) config bool bWildCardNicks;
// Judgement actions
/** the score to reach before actions will be taken */
var(Config) config int iKillScore;
/** the action to take */
var(Config) config ChatFilterAction KillAction;

// CFA_Warn
/** printed on the abusers screen */
var(Config) config string sWarningNotification;
/** broadcasted to eveybody */
var(Config) config string sWarningBroadcast;
/** action to take (only CFA_Nothing, CFA_Kick, CFA_Ban, CFA_SessionBan, CFA_Defrag) */
var(Config) config ChatFilterAction WarningAction;
/** max warnings for a auto action */
var(Config) config int iMaxWarnings;
/** minimum percentage of votes needed for user action */
var(Config) config float fMinVote;
/** allow other players to vote to take action when somebody has been warned */
var(Config) config bool bWarnVoting;

// CFA_Mute
/** the message to show when muted */
var(Config) config string sMuteMessage;
/** show the muted hud */
var(Config) config bool bShowMuted;

// logging
/** perform chatloggin */
var(Config) config bool bLogChat;
/** the filename to use */
var(Config) config string sFileFormat;
/** the file log instance for the chat log */
var FileLog logfile;

/** Webadmin receives unfiltered chat messages */
var(Config) config bool bUnfilteredWebAdmin;
/** Logged-in admin receives unfiltered chat messages */
var(Config) config bool bUnfilteredAdmin;
/** WebAdmin received team messages */
var(Config) config bool bWebAdminReceiveTeam;

// message target filtering -- NOT IMPLEMENTED
const CD_P2P = 1; // player -> player
const CD_S2S = 2; // spectator -> spectator
const CD_P2S = 4; // player -> spectator
const CD_S2P = 8; // spectator -> player
const CD_A2A = 16; // admin -> all
var config byte ChatDirection;

/** bad word replacement table entry */
struct ReplacementEntry
{
    var string from,to;
};
/** replacement table */
var array<ReplacementEntry> ReplacementTable;

/** chatfilter record */
struct ChatRecord
{
    /** the owning user */
    var PlayerController Sender;
    /** the filtered message */
    var string FilteredMsg;
    /** */
    var float LastMsgTick;
    /** last message of this user */
    var string LastMsg;
    /** number of same messages within a timeframe */
    var int count;
    /** total number of messages */
    var int msgCount;
    /** current score */
    var int score;
    /** number of warnings received */
    var int warnings;
    /** removed by user request */
    var bool bUserRequest;
    /** user has been muted */
    var bool bMuted;
    /** the message dispacther for this user */
    var CFMsgDispatcher Dispatcher;
    /** last nick used */
    var string lastName;
};
/** records for the current players */
var array<ChatRecord> ChatRecords;

/** warning mutator to spawn when warn voting is enabled */
var string WarningMutClass;

/** message dispatcher class to spawn */
var class<CFMsgDispatcher> MessageDispatcherClass;

var float LastMsgTick;

var localized string PICat, PIlabel[26], PIdesc[26];

/** last\current nick name to track changes */
var array<string> NameHistory;

/** last time the nicknames were checked */
var float LastNickCheck;

/** WebAdmin playercontroller */
var UTServerAdminSpectator WebAdminPC;
var bool HasWebAdmin;

/** Find a player record and create a new one when needed */
function int findChatRecord(Actor Sender, optional bool bCreate)
{
    local int i;
    if (PlayerController(Sender) == none) return -1;
    for (i = 0; i < ChatRecords.Length; i++)
    {
        if (ChatRecords[i].Sender == Sender) return i;
    }
    if (bCreate)
    {
        ChatRecords.Length = ChatRecords.Length+1;
        ChatRecords[ChatRecords.Length-1].Sender = PlayerController(Sender);
        if ((bCheckNicknames && (BadnickAction == BNA_Request)) || bShowMuted)
        {
            if (ChatRecords[ChatRecords.Length-1].Dispatcher == none)
                ChatRecords[ChatRecords.Length-1].Dispatcher = spawn(MessageDispatcherClass, Sender);
        }
        return ChatRecords.Length-1;
    }
    return -1;
}

/** Filter bad words out a string */
function string filterString(coerce string Msg, int cr)
{
    local int i,k;

    if (cr == -1) return Msg;
    if (bUseReplacementTable) return filterStringTable(Msg, cr);
    for (i=0; i<BadWords.Length; i++)
    {
        k = InStr(Caps(msg), Caps(BadWords[i]));
        while (k > -1)
        {
            msg = Left(msg, k)$chr(1)$Mid(msg, k+Len(BadWords[i]));
            ChatRecords[cr].score += iScoreSwear;
            k = InStr(Caps(msg), Caps(BadWords[i]));
        }
        msg = repl(msg, chr(1), CencorWord);
    }
    return Msg;
}

/** Filter bad words out a string, using replacement table */
function string filterStringTable(coerce string Msg, int cr)
{
    local int i,k;

    if (cr == -1) return Msg;
    for (i=0; i<ReplacementTable.Length; i++)
    {
        k = InStr(Caps(Msg), Caps(ReplacementTable[i].from));
        while (k > -1)
        {
            Msg = Left(Msg, k)$chr(1)$Mid(Msg, k+Len(ReplacementTable[i].from));
            ChatRecords[cr].score += iScoreSwear;
            k = InStr(Caps(Msg), Caps(ReplacementTable[i].from));
        }
        Msg = repl(msg, chr(1), ReplacementTable[i].to);
    }
    return Msg;
}

/** Write judgement to log */
function judgeLog(string msg)
{
    log(msg, name);
    if (logfile != none) logfile.Logf(Level.TimeSeconds$chr(9)$"JUDGE"$chr(9)$msg);
}

/** Initial judge */
function judge(PlayerController Sender, int cr)
{
    local int x;
    if ((Sender != none) && (MessagingSpectator(Sender) == none))
    {
        if (ChatRecords[cr].score > iKillScore)
        {
            x = ChatRecords[cr].score;
            ChatRecords[cr].score = 0;
            switch (KillAction)
            {
                case CFA_Nothing:       return;
                case CFA_Kick:          judgeLog("Kicking player"@Sender.PlayerReplicationInfo.PlayerName);
                                        Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[1];
                                        Level.Game.AccessControl.KickPlayer(Sender);
                                        Level.Game.AccessControl.DefaultKickReason = Level.Game.AccessControl.default.DefaultKickReason;
                                        return;
                case CFA_Ban:           judgeLog("Banning player"@Sender.PlayerReplicationInfo.PlayerName);
                                        Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[2];
                                        Level.Game.AccessControl.BanPlayer(Sender, false);
                                        Level.Game.AccessControl.DefaultKickReason = Level.Game.AccessControl.default.DefaultKickReason;
                                        return;
                case CFA_SessionBan:    judgeLog("Session banning player"@Sender.PlayerReplicationInfo.PlayerName);
                                        Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[3];
                                        Level.Game.AccessControl.BanPlayer(Sender, true);
                                        Level.Game.AccessControl.DefaultKickReason = Level.Game.AccessControl.default.DefaultKickReason;
                                        return;
                case CFA_Defrag:        judgeLog("Defragging player"@Sender.PlayerReplicationInfo.PlayerName);
                                        Sender.PlayerReplicationInfo.Score -= x;
                                        return;
                case CFA_Warn:          judgeLog("Warning player"@Sender.PlayerReplicationInfo.PlayerName);
                                        ChatRecords[cr].warnings++;
                                        judgeWarning(Sender, cr);
                                        return;
                case CFA_Mute:          judgeLog("Muting player"@Sender.PlayerReplicationInfo.PlayerName);
                                        Sender.ClearProgressMessages();
                                        Sender.SetProgressTime(6);
                                        Sender.SetProgressMessage(0, sMuteMessage, class'Canvas'.Static.MakeColor(255,0,0));
                                        ChatRecords[cr].bMuted = true;
                                        if (bShowMuted) ChatRecords[cr].Dispatcher.MutedHud(Sender);
                                        return;
            }
        }
    }
}

/** Secondary judge on a CFA_Warn */
function judgeWarning(PlayerController Sender, int cr)
{
    local string tmp;
    if ((Sender != none) && (MessagingSpectator(Sender) == none))
    {
        if ((ChatRecords[cr].warnings > iMaxWarnings) || ChatRecords[cr].bUserRequest)
        {
            switch (WarningAction)
            {
                case CFA_Nothing:       break;
                case CFA_Kick:          judgeLog("Kicking player"@Sender.PlayerReplicationInfo.PlayerName@"iMaxWarning exceeded:"@(ChatRecords[cr].warnings > iMaxWarnings)@"Requested:"@ChatRecords[cr].bUserRequest);
                                        if (ChatRecords[cr].bUserRequest) //ChatRecords[cr].Dispatcher.Dispatch(Sender, 4);
                                        Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[4];
                                        else //ChatRecords[cr].Dispatcher.Dispatch(Sender, 1);
                                        Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[1];
                                        Level.Game.AccessControl.KickPlayer(Sender);
                                        Level.Game.AccessControl.DefaultKickReason = Level.Game.AccessControl.default.DefaultKickReason;
                                        break;
                case CFA_Ban:           judgeLog("Banning player"@Sender.PlayerReplicationInfo.PlayerName@"iMaxWarning exceeded:"@(ChatRecords[cr].warnings > iMaxWarnings)@"Requested:"@ChatRecords[cr].bUserRequest);
                                        if (ChatRecords[cr].bUserRequest) //ChatRecords[cr].Dispatcher.Dispatch(Sender, 5);
                                        Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[5];
                                        else //ChatRecords[cr].Dispatcher.Dispatch(Sender, 2);
                                        Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[2];
                                        Level.Game.AccessControl.BanPlayer(Sender, false);
                                        Level.Game.AccessControl.DefaultKickReason = Level.Game.AccessControl.default.DefaultKickReason;
                                        break;
                case CFA_SessionBan:    judgeLog("Session banning player"@Sender.PlayerReplicationInfo.PlayerName@"iMaxWarning exceeded:"@(ChatRecords[cr].warnings > iMaxWarnings)@"Requested:"@ChatRecords[cr].bUserRequest);
                                        if (ChatRecords[cr].bUserRequest) //ChatRecords[cr].Dispatcher.Dispatch(Sender, 6);
                                        Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[6];
                                        else //ChatRecords[cr].Dispatcher.Dispatch(Sender, 3);
                                        Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[3];
                                        Level.Game.AccessControl.BanPlayer(Sender, true);
                                        Level.Game.AccessControl.DefaultKickReason = Level.Game.AccessControl.default.DefaultKickReason;
                                        break;
                case CFA_Defrag:        judgeLog("Defragging player"@Sender.PlayerReplicationInfo.PlayerName@"iMaxWarning exceeded:"@(ChatRecords[cr].warnings > iMaxWarnings)@"Requested:"@ChatRecords[cr].bUserRequest);
                                        Sender.PlayerReplicationInfo.Score -= ChatRecords[cr].warnings*iKillScore;
                                        break;
                case CFA_Mute:          judgeLog("Muting player"@Sender.PlayerReplicationInfo.PlayerName@"iMaxWarning exceeded:"@(ChatRecords[cr].warnings > iMaxWarnings)@"Requested:"@ChatRecords[cr].bUserRequest);
                                        Sender.ClearProgressMessages();
                                        Sender.SetProgressTime(6);
                                        Sender.SetProgressMessage(0, sMuteMessage, class'Canvas'.Static.MakeColor(255,0,0));
                                        ChatRecords[cr].bMuted = true;
                                        //if (bShowMuted) Dispatcher.MuteHud(Sender);
                                        break;
            }
            ChatRecords[cr].warnings = 0;
            ChatRecords[cr].bUserRequest = false;
            return;
        }
        else {
            if (sWarningNotification != "")
            {
                Sender.ClearProgressMessages();
                Sender.SetProgressTime(6);
                Sender.SetProgressMessage(0, sWarningNotification, class'Canvas'.Static.MakeColor(255,0,0));
            }
            if (sWarningBroadcast != "" && bWarnVoting)
            {
                tmp = sWarningBroadcast;
                ReplaceText(tmp, "%s", Sender.PlayerReplicationInfo.PlayerName);
                ReplaceText(tmp, "%i", string(cr));
                Level.Game.Broadcast(none, tmp, '');
            }
        }
    }
}

/** Write chat log */
function WriteLog(PlayerController Sender, coerce string msg, coerce string tag)
{
    if (Sender != none)
    {
        if (logfile != none)
        {
            logfile.Logf(Level.TimeSeconds$chr(9)$tag$chr(9)$Sender.PlayerReplicationInfo.PlayerName$chr(9)$msg);
        }
    }
}

/** Check for foul nickname */
function CheckNickname(PlayerController PC)
{
    local bool foulName, badName;
    local int i;

    foulName = false;
    badName = false;
    if (bUseReplacementTable)
    {
        for (i=0; i<ReplacementTable.Length; i++)
        {
            if (InStr(Caps(PC.PlayerReplicationInfo.PlayerName), Caps(ReplacementTable[i].from)) > -1)
            {
                foulName = true;
                break;
            }
        }
    }
    else {
        for (i=0; i<BadWords.Length; i++)
        {
            if (InStr(Caps(PC.PlayerReplicationInfo.PlayerName), Caps(BadWords[i])) > -1)
            {
                foulName = true;
                break;
            }
        }
    }
    if (!foulName)
    {
        for (i=0; i<UnallowedNicks.Length; i++)
        {
            if (bWildCardNicks && (InStr(UnallowedNicks[i], "*") > -1 || InStr(UnallowedNicks[i], "?") > -1))
            {
                if (class'wString'.static.MaskedCompare(PC.PlayerReplicationInfo.PlayerName, UnallowedNicks[i]))
                {
                    badName = true;
                    break;
                }
            }
            else {
                if (Caps(PC.PlayerReplicationInfo.PlayerName) == Caps(UnallowedNicks[i]))
                {
                    badName = true;
                    break;
                }
            }
        }
    }
    i = findChatRecord(PC, true);
    if (foulName || badName)
    {
        if (i > -1)
        {
            if (ChatRecords[i].LastName == Caps(PC.PlayerReplicationInfo.PlayerName)) return;
            judgeLog("Bad nickname"@PC.PlayerReplicationInfo.PlayerName);
            if (BadnickAction == BNA_Kick)
            {
                if (foulName) //ChatRecords[i].Dispatcher.Dispatch(PC, 0);
                Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[0];
                else if (badName) //ChatRecords[i].Dispatcher.Dispatch(PC, 7);
                Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[7];
                Level.Game.AccessControl.KickPlayer(PC);
                Level.Game.AccessControl.DefaultKickReason = Level.Game.AccessControl.default.DefaultKickReason;
            }
            else if (BadnickAction == BNA_Request)
            {
                if (foulName) ChatRecords[i].Dispatcher.ChangeNamerequest(PC, 0);
                else if (badName) ChatRecords[i].Dispatcher.ChangeNamerequest(PC, 7);
            }
            else if ((BadnickAction == BNA_Ban) || (BadnickAction == BNA_SessionBan))
            {
                if (foulName) //ChatRecords[i].Dispatcher.ChangeNamerequest(PC, 0);
                Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[0];
                else if (badName) //ChatRecords[i].Dispatcher.ChangeNamerequest(PC, 7);
                Level.Game.AccessControl.DefaultKickReason = class'ChatFilterMsg'.default.messages[7];
                Level.Game.AccessControl.BanPlayer(PC, (BadnickAction == BNA_SessionBan));
                Level.Game.AccessControl.DefaultKickReason = Level.Game.AccessControl.default.DefaultKickReason;
            }
        }
    }
    if (i > -1) ChatRecords[i].LastName = Caps(PC.PlayerReplicationInfo.PlayerName);
}

/** check the chat direction */
function bool mayChat(PlayerController Sender, PlayerController Receiver)
{
    /*
    if (ChatDirection == CD_All) return true;
    if (Sender.PlayerReplicationInfo.bAdmin && bAdminChatOverride) return true;
    if (Sender.PlayerReplicationInfo.bIsSpectator)
    {
        if (ChatDirection == CD_PrivateSpecator) return Receiver.PlayerReplicationInfo.bIsSpectator;
    }
    if (ChatDirection == CD_PrivatePlayer) return Receiver.PlayerReplicationInfo.bIsSpectator;
    */
    return true;
}

/** game information for the chat log */
function GameInformation()
{
    local string line, tmp;
    local Mutator M;
    line = "===";
    line = line$chr(9)$Level.Game.Class; // gametype
    line = line$chr(9)$Left(string(Level), InStr(string(Level), ".")); // map
    for (M = Level.Game.BaseMutator.NextMutator; M != None; M = M.NextMutator)
    {
        if (tmp != "") tmp = tmp$",";
        tmp = tmp$(M.GetHumanReadableName());
    }
    line = line$chr(9)$tmp; // mutators

    logfile.Logf(line);
}

event PreBeginPlay()
{
    local int i,j;
    local BroadcastHandler BH;

    if (!bEnabled)
    {
        Self.Destroy();
        return;
    }
    log("Loading Chat Filter", name);
    if (bLogChat)
    {
        logfile = spawn(class 'FileLog', Level);
        logfile.OpenLog(LogFilename());
        logfile.Logf("--- Log started on "$Level.Year$"/"$Level.Month$"/"$Level.Day@Level.Hour$":"$Level.Minute$":"$Level.Second);
        GameInformation();
    }
    if (!bDisableBHFix && (Level.Game.BroadcastHandler.class != Level.Game.default.BroadcastClass) /*Level.Game.BroadcastHandler.IsA('UT2VoteChatHandler')*/)
    {
        log("WARNING: Unexpected broadcast handler `"$Level.Game.BroadcastHandler.class$"`. Will try to use the original.", name);
        foreach AllActors(class'BroadcastHandler', BH)
        {
            if (BH.class == Level.Game.default.BroadcastClass)
            {
                log("Found the original broadcast handler "$BH.class, name);
                BH.RegisterBroadcastHandler(Self);
                break;
            }
        }
        if (BH == none)
        {
            log("Unable to find the original broadcast handler. Will fallback to the current handler and hope it works out.");
            Level.Game.BroadcastHandler.RegisterBroadcastHandler(Self);
        }
    }
    else {
        Level.Game.BroadcastHandler.RegisterBroadcastHandler(Self);
    }
    if (KillAction == CFA_Warn && bWarnVoting)
    {
        log("Launching warning mutator", name);
        Level.Game.AddMutator(repl(WarningMutClass, "%clientpackage%", ClientSidePackageChatFilter), true);
    }
    if (bUseReplacementTable)
    {
        log("Converting BadWords to ReplacementTable", name);
        ReplacementTable.Length = BadWords.Length;
        for (i = 0; i < BadWords.Length; i++)
        {
            j = InStr(BadWords[i], ";");
            if (j < 0) j = Len(BadWords[i]);
            ReplacementTable[i].from = Left(BadWords[i], j);
            ReplacementTable[i].to = Mid(BadWords[i], j+1);
            if (ReplacementTable[i].to == "") ReplacementTable[i].to = CencorWord;
            log("[~]"@ReplacementTable[i].from@"=>"@ReplacementTable[i].to);
        }
    }
    if ((bCheckNicknames && (BadnickAction == BNA_Request)) || bShowMuted)
    {
        if (int(Level.EngineVersion) > 3195) AddToPackageMap(ClientSidePackageChatFilter);
        MessageDispatcherClass = class<CFMsgDispatcher>(DynamicLoadObject(ClientSidePackageChatFilter$".CFMsgDispatcher", class'Class'));
    }
    SetTimer(fTimeFrame, true);
    enable('Tick');
}

event Timer()
{
    local int i;
    for (i = 0; i < ChatRecords.Length; i++)
    {
        ChatRecords[i].msgCount = 0;
        ChatRecords[i].count = 0;
    }
}

event Tick(float delta)
{
    local Controller C;
    LastMsgTick = Level.TimeSeconds;
    if ((Level.NextURL != "") && (logfile != none))
    {
        logfile.Logf("--- Log closed on "$Level.Year$"/"$Level.Month$"/"$Level.Day@Level.Hour$":"$Level.Minute$":"$Level.Second);
        logfile.Destroy();
        logfile = none;
    }
    // check nickname
    if (bCheckNicknames)
    {
        LastNickCheck += delta;
        if (LastNickCheck < 1) return;
        LastNickCheck = 0;
        for( C = Level.ControllerList; C != None; C = C.NextController )
        {
            if (C.PlayerReplicationInfo == none) continue;
            if (C.PlayerReplicationInfo.bBot || (MessagingSpectator(C) != none)) continue; // fast escape
            if (NameHistory.length <= C.PlayerReplicationInfo.PlayerID) NameHistory.length = C.PlayerReplicationInfo.PlayerID+1;
            if (C.PlayerReplicationInfo.PlayerName != NameHistory[C.PlayerReplicationInfo.PlayerID])
            {
                if (bLogChat && (NameHistory[C.PlayerReplicationInfo.PlayerID] != ""))
                    WriteLog(PlayerController(C), "old name: "$NameHistory[C.PlayerReplicationInfo.PlayerID], "NAMECHANGE");
                NameHistory[C.PlayerReplicationInfo.PlayerID] = C.PlayerReplicationInfo.PlayerName;
                CheckNickname(PlayerController(C));
            }
        }
    }
}

function BroadcastText( PlayerReplicationInfo SenderPRI, PlayerController Receiver, coerce string Msg, optional name Type )
{
    local string lmsg;
    // elmuerte: this is sort of a bug in the parent code, acceptbroadcast is called
    //   for every player and every boradcasthandler. It should actually only be called
    //   once for every player since AcceptBroadcastText already checks with the other
    //   handlers.

	//if ( !AcceptBroadcastText(Receiver, SenderPRI, Msg, Type) )
	//	return;

	if (bWebAdminReceiveTeam && (SenderPRI == Receiver.PlayerReplicationInfo) && HasWebAdmin && (Type == 'TeamSay'))
	{
        if (WebAdminPC == none)
            foreach AllActors(class'UTServerAdminSpectator', WebAdminPC) break;
        if (WebAdminPC == none) HasWebAdmin = false;
        else {
            lmsg = msg;
            if (AcceptBroadcastText(WebAdminPC, SenderPRI, lmsg, type))
            {
                lmsg = "[Team:"$SenderPRI.Team.GetHumanReadableName()$"] "$lmsg;
                WebAdminPC.TeamMessage(SenderPRI, lmsg, type);
            }
        }
	}

	if ( NextBroadcastHandler != None )
		NextBroadcastHandler.BroadcastText( SenderPRI, Receiver, Msg, Type );
	else Receiver.TeamMessage( SenderPRI, Msg, Type );
}

function bool AcceptBroadcastText( PlayerController Receiver, PlayerReplicationInfo SenderPRI, out string Msg, optional name Type )
{
    local int cr;
    local string logpre;

    cr = -1;
    if (SenderPRI != none) cr = findChatRecord(SenderPRI.Owner, true);
    if ((cr > -1 ) && (ChatRecords[cr].LastMsgTick == LastMsgTick))
    {
        if (!(bUnfilteredWebAdmin && Receiver.IsA('UTServerAdminSpectator'))
            &&
            !(bUnfilteredAdmin && Receiver.PlayerReplicationInfo.bAdmin)
            )
            msg = ChatRecords[cr].FilteredMsg;
        return super.AcceptBroadcastText(Receiver, SenderPRI, Msg, Type);
    }
    if ((cr > -1) && ((Type == 'Say') || (Type == 'TeamSay')))
    {
        ChatRecords[cr].LastMsgTick = LastMsgTick;
        if (Type == 'TeamSay') logpre = "TEAM";
        else logpre = "";

        ChatRecords[cr].msgCount++;
        if (ChatRecords[cr].bMuted)
        {
            if (bLogChat) WriteLog(PlayerController(SenderPRI.Owner), msg, "MUTE");
            return false;
        }
        if (ChatRecords[cr].msgCount > iMaxPerTimeFrame)
        {
            if (bLogChat) WriteLog(PlayerController(SenderPRI.Owner), msg, logpre$"SPAM");
            ChatRecords[cr].score += iScoreSpam;
            judge(PlayerController(SenderPRI.Owner), cr);
            return false; // max exceeded
        }
        if (ChatRecords[cr].LastMsg == Msg)
        {
            ChatRecords[cr].count++;
            if (ChatRecords[cr].count > iMaxRepeat)
            {
                if (bLogChat) WriteLog(PlayerController(SenderPRI.Owner), msg, logpre$"SPAM");
                ChatRecords[cr].score += iScoreSpam;
                judge(PlayerController(SenderPRI.Owner), cr);
                return false; // max exceeded
            }
        }
        else {
            ChatRecords[cr].LastMsg = Msg;
            ChatRecords[cr].count = 0;
        }
    }
    if (bLogChat && ((Type == 'Say') || (Type == 'TeamSay')) && (SenderPRI != none))
    {
        //log(SenderPRI.PlayerName@msg);
        WriteLog(PlayerController(SenderPRI.Owner), msg, logpre$"CHAT");
    }
    if (cr > -1)
    {
        ChatRecords[cr].FilteredMsg = filterString(Msg, cr);

        if (!(bUnfilteredWebAdmin && Receiver.IsA('UTServerAdminSpectator'))
            &&
            !(bUnfilteredAdmin && Receiver.PlayerReplicationInfo.bAdmin)
            )
            msg = ChatRecords[cr].FilteredMsg;

        judge(PlayerController(SenderPRI.Owner), cr);
    }
    return super.AcceptBroadcastText(Receiver, SenderPRI, Msg, Type);
}

static function FillPlayInfo(PlayInfo PI)
{
    Super.FillPlayInfo(PI);

    PI.AddSetting(default.PICat, "fTimeFrame", default.PIlabel[1], 10, 1, "Text", "5");
    PI.AddSetting(default.PICat, "iMaxPerTimeFrame", default.PIlabel[2], 10, 2, "Text", "5");
    PI.AddSetting(default.PICat, "iMaxRepeat", default.PIlabel[3], 10, 3, "Text", "5");
    PI.AddSetting(default.PICat, "iScoreSpam", default.PIlabel[4], 10, 4, "Text", "5");

    PI.AddSetting(default.PICat, "CencorWord", default.PIlabel[5], 10, 5, "Text", "20");
    PI.AddSetting(default.PICat, "iScoreSwear", default.PIlabel[6], 10, 6, "Text", "5");
    //PI.AddSetting(default.PICat, "BadWords", default.PIlabel[7], 10, 7, "Textarea", "");

    PI.AddSetting(default.PICat, "bUnfilteredWebAdmin", default.PIlabel[23], 10, 7, "Check");
    PI.AddSetting(default.PICat, "bUnfilteredAdmin", default.PIlabel[24], 10, 7, "Check");
    PI.AddSetting(default.PICat, "bWebAdminReceiveTeam", default.PIlabel[25], 10, 7, "Check");

    PI.AddSetting(default.PICat, "iKillScore", default.PIlabel[8], 10, 8, "Text", "5");
    PI.AddSetting(default.PICat, "KillAction", default.PIlabel[9], 10, 9, "Select", "CFA_Nothing;Nothing;CFA_Warn;Warn player;CFA_Kick;Kick player;CFA_Ban;Ban player;CFA_SessionBan;Ban player this session;CFA_Defrag;Remove one point;CFA_Mute;Mute player for this game");

    PI.AddSetting(default.PICat, "bCheckNicknames", default.PIlabel[10], 10, 10, "check", "");
    PI.AddSetting(default.PICat, "BadnickAction", default.PIlabel[11], 10, 10, "Select", "BNA_Kick;Kick the player;BNA_Request;Request a new nickname;BNA_Ban;Ban the player;BNA_SessionBan;Ban this player for this session only");
    PI.AddSetting(default.PICat, "bWildCardNicks", default.PIlabel[12], 10, 10, "check", "");

    PI.AddSetting(default.PICat, "sWarningNotification", default.PIlabel[13], 10, 11, "Text", "999");
    PI.AddSetting(default.PICat, "sWarningBroadcast", default.PIlabel[14], 10, 12, "Text", "999");
    PI.AddSetting(default.PICat, "WarningAction", default.PIlabel[15], 10, 13, "Select", "CFA_Nothing;Nothing;CFA_Kick;Kick player;CFA_Ban;Ban player;CFA_SessionBan;Ban player this session;CFA_Defrag;Remove one point;CFA_Mute;Mute player for this game");
    PI.AddSetting(default.PICat, "iMaxWarnings", default.PIlabel[16], 10, 14, "Text", "5");
    PI.AddSetting(default.PICat, "bWarnVoting", default.PIlabel[22], 10, 15, "Check");
    PI.AddSetting(default.PICat, "fMinVote", default.PIlabel[17], 10, 16, "Text", "5;0:1");

    PI.AddSetting(default.PICat, "sMuteMessage", default.PIlabel[18], 10, 16, "Text", "999");
    PI.AddSetting(default.PICat, "bShowMuted", default.PIlabel[19], 10, 17, "Check");

    //CD_All;Public;CD_PrivateSpecator;Spectators are private;CD_PrivatePlayer;Specators and Players are private;

    PI.AddSetting(default.PICat, "bLogChat", default.PIlabel[20], 10, 17, "check");
    PI.AddSetting(default.PICat, "sFileFormat", default.PIlabel[21], 10, 18, "Text", "40");
}

static event string GetDescriptionText(string PropName)
{
    switch (PropName)
    {
        case "fTimeFrame": return default.PIdesc[1];
        case "iMaxPerTimeFrame": return default.PIdesc[2];
        case "iMaxRepeat": return default.PIdesc[3];
        case "iScoreSpam": return default.PIdesc[4];
        case "CencorWord": return default.PIdesc[5];
        case "iScoreSwear": return default.PIdesc[6];
        case "BadWords": return default.PIdesc[7];
        case "iKillScore": return default.PIdesc[8];
        case "KillAction": return default.PIdesc[9];
        case "bCheckNicknames": return default.PIdesc[10];
        case "BadnickAction": return default.PIdesc[11];
        case "bWildCardNicks": return default.PIdesc[12];
        case "sWarningNotification": return default.PIdesc[13];
        case "sWarningBroadcast": return default.PIdesc[14];
        case "WarningAction": return default.PIdesc[15];
        case "iMaxWarnings": return default.PIdesc[16];
        case "fMinVote": return default.PIdesc[17];
        case "sMuteMessage": return default.PIdesc[18];
        case "bShowMuted": return default.PIdesc[19];
        case "bLogChat": return default.PIdesc[20];
        case "sFileFormat": return default.PIdesc[21];
        case "bWarnVoting": return default.PIdesc[22];
        case "bUnfilteredWebAdmin": return default.PIdesc[23];
        case "bUnfilteredAdmin": return default.PIdesc[24];
        case "bWebAdminReceiveTeam": return default.PIdesc[25];
    }
    return super.GetDescriptionText(PropName);
}

function string GetServerPort()
{
    local string S;
    local int i;
    // Figure out the server's port.
    S = Level.GetAddressURL();
    i = InStr( S, ":" );
    assert(i>=0);
    return Mid(S,i+1);
}

function string LogFilename()
{
    local string result;
    result = sFileFormat;
    ReplaceText(result, "%P", GetServerPort());
    ReplaceText(result, "%N", Level.Game.GameReplicationInfo.ServerName);
    ReplaceText(result, "%Y", Right("0000"$string(Level.Year), 4));
    ReplaceText(result, "%M", Right("00"$string(Level.Month), 2));
    ReplaceText(result, "%D", Right("00"$string(Level.Day), 2));
    ReplaceText(result, "%H", Right("00"$string(Level.Hour), 2));
    ReplaceText(result, "%I", Right("00"$string(Level.Minute), 2));
    ReplaceText(result, "%W", Right("0"$string(Level.DayOfWeek), 1));
    ReplaceText(result, "%S", Right("00"$string(Level.Second), 2));
    return result;
}

defaultproperties
{
    bDisableBHFix=false

    bEnabled=true
    fTimeFrame=1.0000
    iMaxPerTimeFrame=2
    iMaxRepeat=1
    CencorWord="*****"
    iScoreSpam=1
    bUseReplacementTable=false
    iScoreSwear=1
    iKillScore=10
    KillAction=CFA_Nothing
    bCheckNicknames=false
    BadnickAction=BNA_Kick
    bWildCardNicks=true
    sWarningNotification="ChatFilter: Please clean up your act"
    sWarningBroadcast="%s is chatting abusive, type 'mutate cf judge %i` to judge the player"
    WarningAction=CFA_Kick
    bWarnVoting=false
    iMaxWarnings=2
    fMinVote=0.5000
    sMuteMessage="ChatFilter: You are muted the rest of the game"
    bShowMuted=false
    ChatDirection=255
    bLogChat=false
    sFileFormat="ChatFilter_%P_%Y_%M_%D_%H_%I_%S"
    bUnfilteredWebAdmin=false
    bUnfilteredAdmin=false
    bWebAdminReceiveTeam=false
    HasWebAdmin=true

    WarningMutClass="ServerExt.CFWarningMut"

    PICat="Chat Filter"
    PIlabel[0]=""
    PIdesc[0]=""
    PIlabel[1]="Time frame"
    PIdesc[1]="Time frame size in which some filters apply"
    PIlabel[2]="Max per time frame"
    PIdesc[2]="Maximum message per time frame"
    PIlabel[3]="Max repeats"
    PIdesc[3]="Maximum number of repeating lines allowed"
    PIlabel[4]="Spam score"
    PIdesc[4]="Score to add when spamming"
    PIlabel[5]="Censor replacement"
    PIdesc[5]="Replacement word for the bad words"
    PIlabel[6]="Swear score"
    PIdesc[6]="Score to add for using bad words"
    PIlabel[7]="Bad words"
    PIdesc[7]="the so called bad words that will be filtered"
    PIlabel[8]="Kill score"
    PIdesc[8]="Score to get before action is taken"
    PIlabel[9]="Kill action"
    PIdesc[9]="the action to take when the user hits the kill score"
    PIlabel[10]="Check nicknames"
    PIdesc[10]="Check the user's nick name"
    PIlabel[11]="Bad nick action"
    PIdesc[11]="Action to take on a bad nick name"
    PIlabel[12]="Bad nicks contain wildcards"
    PIdesc[12]="Accept wildcards in the bad nick name list"
    PIlabel[13]="Warning notification"
    PIdesc[13]="Notify message to show on the warned user"
    PIlabel[14]="Warning broadcast"
    PIdesc[14]="Notify other users when somebody get's warned"
    PIlabel[15]="Warning action"
    PIdesc[15]="Action to take when a user receives a warning"
    PIlabel[16]="Max warnings"
    PIdesc[16]="Maximum warnings to get before taking action"
    PIlabel[17]="Min vote percentage"
    PIdesc[17]="Minimal vote percentage required before an action is taken"
    PIlabel[18]="Mute message"
    PIdesc[18]="Message to show when the user is muted"
    PIlabel[19]="Show muted"
    PIdesc[19]="show on screen when the user has been muted"
    PIlabel[20]="Log chat"
    PIdesc[20]="Log the chats to the log file"
    PIlabel[21]="Filename format"
    PIdesc[21]="Filename to use for chat logging"
    PIlabel[22]="Warning voting"
    PIdesc[22]="Allow other players to vote on a judgement after a warning"
    PIlabel[23]="Unfiltered WebAdmin"
    PIdesc[23]="The webadmin receives the unfiltered text"
    PIlabel[24]="Unfiltered Admin"
    PIdesc[24]="A logged-in admin receives the unfiltered text"
    PIlabel[25]="WebAdmin TeamChat"
    PIdesc[25]="The WebAdmin can see team chat"
}
