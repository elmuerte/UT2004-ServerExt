/*******************************************************************************
    Actual slot manager close                                           <br />

    (c) 2004-2005, Michiel "El Muerte" Hendriks                              <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: SlotManager.uc,v 1.11 2005/12/05 10:06:08 elmuerte Exp $ -->
*******************************************************************************/
class SlotManager extends SlotManagerBase config parseconfig;

/**
    slot record type. ST_IP = IP address; ST_Hash = CDKey hash;
    ST_Nick = player nickname; ST_Password = password; ST_Options = check
    connect options
*/
enum ESlotType
{
    ST_IP,
    ST_Hash,
    ST_Nick,
    ST_Password,
    ST_Options,
};

/**
    method to use to open slots. Expand will increase the player limit, kick
    will kick a person
*/
enum ESlotOpenMethod
{
    SOM_Expand,
    SOM_KickRandom,
    SOM_KickWorst,
    SOM_KickBest,
    SOM_KickOldest,
    SOM_KickNewest,
    SOM_KickBestSPM,
    SOM_KickWorstSPM,
};

/** slot record configuration record */
struct SlotRecord
{
    /** the value to match, can contain wilcards: * (zero or many) or ? (one char) */
    var string data;
    /** defines what the data file contains */
    var ESlotType type;
    /** slot only available for spectators */
    var bool specOnly;
    /** open method, SOM_Expand by default */
    var ESlotOpenMethod method;
    /** maximum number of users that can use this slot, 0 means no limit */
    var int maxSize;
    /** current size */
    var int curSize;
    /** a comment, can be anything, not used for anything */
    var string comment;
};
/** slot configuration */
var globalconfig array<SlotRecord> Slots;
/** the maxplayers will never increase above this limit */
var globalconfig int AbsoluteMaxPlayers;
/** the maxspectator will never increase above this limit */
var globalconfig int AbsoluteMaxSpectators;

/** if set logged in admins will never be booted to make room */
var globalconfig bool bProtectAdmin;

/** user join options cache record */
struct UserOptionsRecord
{
    var string Hash;
    var string Options;
};
/** cache for user options */
var array<UserOptionsRecord> UserOptionsCache;

//!Localization
var localized string PIgroup, PIdesc[4], PIhelp[4], KickMsg;

function PreBeginPlay()
{
    local int i;
    super.PreBeginPlay();
    log("Loaded slot manager:"@slots.length@"slots configured", name);
    for (i = 0; i < slots.length; i++)
    {
        slots[i].curSize = 0;
    }
}

/** check free slots */
function bool PreLogin( string Options, string Address, string PlayerID,
                        out string Error, out string FailCode, bool bSpectator)
{
    local int idx;
    local string match;

    if (IsReserved(Options, Address, PlayerId, bSpectator, idx, match))
    {
        AddUserOptionCache(PlayerId, Options);
        if (Level.Game.AtCapacity(bSpectator))
        {
            log("Found reserved slot (#"$idx$") for"@match, name);
            if (Slots[idx].method == SOM_Expand)
            {
                if (!AtMaxCapacity(bSpectator)) IncreaseCapicity(bSpectator);
                else {
                    log("Absolute maximum capicity reached", name);
                    return false;
                }
            }
            else return KickFreeRoom(Slots[idx].method, bSpectator, Level.Game.ParseOption(Options, "name"));
        }
        return true;
    }
    else {
        if (Level.Game.AtCapacity(bSpectator))
        {
            log("No reserved slot found, rejecting new player", name);
        }
    }
}

/**  */
function NotifyLogout(Controller Exiting)
{
}

/** return true when the player has a reserved slot */
function bool IsReserved(string Options, string Address, string PlayerID, optional bool bSpectator,
    optional out int i, optional out string tmp)
{
    local int n;
    local string tmpOptions;
    if (InStr(Locs(Options), "%import%") > -1)
    {
       for (n = 0; n < UserOptionsCache.length; n++)
       {
            if (UserOptionsCache[i].Hash ~= PlayerID)
            {
                tmpOptions = UserOptionsCache[i].Options;
                break;
            }
       }
       Options = Repl(Options, "%import%", tmpOptions);
    }

    for (i = 0; i < Slots.Length; i++)
    {
        if ((Slots[i].maxSize > 0) && (Slots[i].maxSize >= Slots[i].curSize)) continue; // slot full
        switch (Slots[i].type)
        {
            case ST_IP:         tmp = Address;
                                if (InStr(tmp, ":") > -1) tmp = Left(tmp, InStr(tmp, ":")); // strip port
                                break;
            case ST_Hash:       tmp = PlayerID; break;
            case ST_Nick:       tmp = Level.Game.ParseOption(Options, "name"); break;
            case ST_Password:   tmp = Level.Game.ParseOption(Options, "password"); break;
            case ST_Options:    tmp = Options; break;
        }
        if (class'wString'.static.MaskedCompare(tmp, Slots[i].data))
        {
            if (Slots[i].specOnly && !bSpectator) continue;
            return true;
        }
    }
    return false;
}

/** check of the maximum capicity has been reached */
function bool AtMaxCapacity(optional bool bSpectator)
{
    if (bSpectator)
    {
        if (AbsoluteMaxSpectators <= 0) return false;
        return Level.Game.MaxSpectators >= AbsoluteMaxSpectators;
    }
    else {
        if (AbsoluteMaxPlayers <= 0) return false;
        return Level.Game.MaxPlayers >= AbsoluteMaxPlayers;
    }
}

/** make room by kicking a player */
function bool KickFreeRoom(ESlotOpenMethod method, optional bool bSpectator, optional string newname)
{
    local Controller C, best;
    local float bestRating, curRating;

    if (bSpectator)
    {
        for (C = Level.ControllerList; C != none; C = C.nextController)
        {
            if (PlayerController(C) == none) continue;
            if (C.PlayerReplicationInfo.bOnlySpectator)
            {
                best = C;
                break;
            }
        }
    }
    else {
        if (Method == SOM_KickRandom) Method = ESlotOpenMethod(rand(ESlotOpenMethod.EnumCount-2)+2);
        bestRating = -1*MaxInt;
        for (C = Level.ControllerList; C != none; C = C.nextController)
        {
            if (PlayerController(C) == none) continue;
            if (C.PlayerReplicationInfo.bOnlySpectator) continue;
            if (bProtectAdmin && C.PlayerReplicationInfo.bAdmin) continue;
            if (IsReserved("%import%", PlayerController(C).GetPlayerNetworkAddress(), PlayerController(C).GetPlayerIDHash(), false)) continue;

            switch (Method)
            {
                case SOM_KickWorst:
                    curRating = -1*C.PlayerReplicationInfo.Score*1000/(C.PlayerReplicationInfo.Deaths+1);
                    break;
                case SOM_KickBest:
                    curRating = C.PlayerReplicationInfo.Score*1000/(C.PlayerReplicationInfo.Deaths+1);
                    break;
                case SOM_KickOldest:
                    curRating = -1*C.PlayerReplicationInfo.StartTime;
                    break;
                case SOM_KickNewest:
                    curRating = C.PlayerReplicationInfo.StartTime;
                    break;
                case SOM_KickBestSPM:
                    curRating = C.PlayerReplicationInfo.Score / (Level.TimeSeconds-C.PlayerReplicationInfo.StartTime+0.1);
                    break;
                case SOM_KickWorstSPM:
                    curRating = -1*C.PlayerReplicationInfo.Score / (Level.TimeSeconds-C.PlayerReplicationInfo.StartTime+0.1);
                    break;
            }
            if (curRating > bestRating)
            {
                curRating = bestRating;
                Best = C;
            }
        }
    }


    if (best != none)
    {
        log("Kicking player"@best.PlayerReplicationInfo@"to make room for"@newname, name);
        Level.Game.AccessControl.DefaultKickReason = GetKickReason(newname);
        Level.Game.AccessControl.KickPlayer(PlayerController(best));
        Level.Game.AccessControl.DefaultKickReason = Level.Game.AccessControl.default.DefaultKickReason;
        return true;
    }
    return false;
}

/** get the formatted kick message string */
function string GetKickReason(optional string newname)
{
    return repl(KickMsg, "%s", newname);
}

function AddUserOptionCache(string Hash, string Options)
{
    local int i;
    for (i = 0; i < UserOptionsCache.Length; i++)
    {
        if (UserOptionsCache[i].Hash ~= Hash)
        {
            UserOptionsCache[i].Options = Options;
            return;
        }
    }
    UserOptionsCache.length = i+1;
    UserOptionsCache[i].Hash = Hash;
    UserOptionsCache[i].Options = Options;
}

static function FillPlayInfo(PlayInfo PlayInfo)
{
    super.FillPlayInfo(PlayInfo);
    PlayInfo.AddSetting(default.PIgroup, "AbsoluteMaxPlayers",      default.PIdesc[0], 200, 100, "Text", "3;0:999",,      True,True);
    PlayInfo.AddSetting(default.PIgroup, "AbsoluteMaxSpectators",   default.PIdesc[1], 200, 100, "Text", "3;0:999",       ,True,True);
    //PlayInfo.AddSetting(default.PIgroup, "Slots",                   default.PIdesc[2], 200, 0, "Custom",        ,"Xi"   ,True,True);
    PlayInfo.AddSetting(default.PIgroup, "bProtectAdmin",           default.PIdesc[3], 200, 99, "Check", "",       ,True,True);
}

static event string GetDescriptionText(string PropName)
{
    switch (PropName)
    {
        case "AbsoluteMaxPlayers":      return default.PIhelp[0];
        case "AbsoluteMaxSpectators":   return default.PIhelp[1];
        case "Slots":                   return default.PIhelp[2];
        case "bProtectAdmin":           return default.PIhelp[3];
    }
    return "";
}

/** get the enum value of the ESlotType index */
static function ESlotType GetSlotType(coerce int i)
{
    return ESlotType(i);
}

/** get the enum value of the ESlotOpenMethod index */
static function ESlotOpenMethod GetSlotOpenMethod(coerce int i)
{
    return ESlotOpenMethod(i);
}

defaultproperties
{
    WebQueryHandler="ServerExt.SlotManWebQueryHandler"
    bProtectAdmin=true

    PIgroup="Reserved slots"
    PIdesc[0]="Absolute Max Players"
    PIhelp[0]="The maximum value will never increase about this value"
    PIdesc[1]="Absolute Max Spectators"
    PIhelp[1]="The maximum value will never increase about this value"
    PIdesc[2]="Slots"
    PIhelp[2]="The reserved slots"
    PIdesc[3]="Protect Admins"
    PIhelp[3]="Never kick logged in admins to make room"

    KickMsg="You have been kicked to make room for %s"
}
