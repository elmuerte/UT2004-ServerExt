/*******************************************************************************
	Actual slot manager close											<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: SlotManager.uc,v 1.4 2004/05/23 15:36:00 elmuerte Exp $ -->
*******************************************************************************/
class SlotManager extends SlotManagerBase config;

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
	/** a comment, can be anything, not used for anything */
	var string comment;
};
/** slot configuration */
var globalconfig array<SlotRecord> Slots;
/** the maxplayers will never increase above this limit */
var globalconfig int AbsoluteMaxPlayers;
/** the maxspectator will never increase above this limit */
var globalconfig int AbsoluteMaxSpectators;

//!Localization
var localized string PIgroup, PIdesc[3], PIhelp[3], KickMsg;

/** check free slots */
function bool PreLogin(	string Options, string Address, string PlayerID,
						out string Error, out string FailCode, bool bSpectator)
{
	local int idx;
	local string match;

	if (IsReserved(Options, Address, PlayerId, bSpectator, idx, match))
	{
		if (Level.Game.AtCapacity(bSpectator))
		{
			log("Found reserved slot (#"$idx$") for"@match, name);
			if (Slots[idx].method == SOM_Expand)
			{
				if (!AtMaxCapacity(bSpectator)) IncreaseCapicity(bSpectator);
				else {
					log("Maximum capicity reached", name);
					return false;
				}
			}
			else return KickFreeRoom(Slots[idx].method, bSpectator, Level.Game.ParseOption(Options, "name"));
		}
		return true;
	}
}

/** return true when the player has a reserved slot */
function bool IsReserved(string Options, string Address, string PlayerID, optional bool bSpectator,
	optional out int i, optional out string tmp)
{
	//local int i;
	//local string tmp;

	for (i = 0; i < Slots.Length; i++)
	{
		switch (Slots[i].type)
		{
			case ST_IP:			tmp = Address; break;
			case ST_Hash:		tmp = PlayerID;	break;
			case ST_Nick:		tmp = Level.Game.ParseOption(Options, "name");
			case ST_Password:	tmp = Level.Game.ParseOption(Options, "password");
			case ST_Options:	tmp = Options;
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
		return Level.Game.MaxSpectators < AbsoluteMaxSpectators;
	}
	else {
		if (AbsoluteMaxPlayers <= 0) return false;
		return Level.Game.MaxPlayers < AbsoluteMaxPlayers;
	}
}

/** make room by kicking a player */
function bool KickFreeRoom(ESlotOpenMethod method, optional bool bSpectator, optional string newname)
{
	local Controller C, best;
	local int i;

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
		switch (Method)
		{
			case SOM_KickWorst:		i = MaxInt; break;
			case SOM_KickBest:		i = -1*MaxInt; break;
			case SOM_KickOldest:	i = MaxInt; break;
			case SOM_KickNewest:	i = 0; break;
		}
		for (C = Level.ControllerList; C != none; C = C.nextController)
		{
			if (PlayerController(C) == none) continue;
			if (C.PlayerReplicationInfo.bOnlySpectator) continue;

			switch (Method)
			{
				case SOM_KickWorst:		if (C.PlayerReplicationInfo.Score*1000/(C.PlayerReplicationInfo.Deaths+1) < i)
										{
											i = C.PlayerReplicationInfo.Score*1000/(C.PlayerReplicationInfo.Deaths+1);
											Best = C;
										}
										break;
				case SOM_KickBest:		if (C.PlayerReplicationInfo.Score*1000/(C.PlayerReplicationInfo.Deaths+1) > i)
										{
											i = C.PlayerReplicationInfo.Score*1000/(C.PlayerReplicationInfo.Deaths+1);
											Best = C;
										}
										break;
				case SOM_KickOldest:	if (C.PlayerReplicationInfo.StartTime < i)
										{
											i = C.PlayerReplicationInfo.StartTime;
											Best = C;
										}
										break;
				case SOM_KickNewest:	if (C.PlayerReplicationInfo.StartTime > i)
										{
											i = C.PlayerReplicationInfo.StartTime;
											Best = C;
										}
										break;
			}
		}
	}


	if (best != none)
	{
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

static function FillPlayInfo(PlayInfo PlayInfo)
{
	super.FillPlayInfo(PlayInfo);
	PlayInfo.AddSetting(default.PIgroup, "AbsoluteMaxPlayers", 		default.PIdesc[0], 200, 0, "Text", "3;0:999",,		True,True);
 	PlayInfo.AddSetting(default.PIgroup, "AbsoluteMaxSpectators", 	default.PIdesc[1], 200, 0, "Text", "3;0:999",		,True,True);
 	PlayInfo.AddSetting(default.PIgroup, "Slots", 					default.PIdesc[2], 200, 0, "Custom",		,"Xi"	,True,True);
}

static event string GetDescriptionText(string PropName)
{
	switch (PropName)
	{
		case "AbsoluteMaxPlayers":		return default.PIhelp[0];
		case "AbsoluteMaxSpectators":	return default.PIhelp[1];
		case "Slots":					return default.PIhelp[2];
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

	PIgroup="Reserved slots"
	PIdesc[0]="Absolute Max Players"
	PIhelp[0]="The maximum value will never increase about this value"
	PIdesc[1]="Absolute Max Spectators"
	PIhelp[1]="The maximum value will never increase about this value"
	PIdesc[2]="Slots"
	PIhelp[2]="The reserved slots"

	KickMsg="You have been kicked to make room for %s"
}
