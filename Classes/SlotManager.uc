/*******************************************************************************
	Actual slot manager close											<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: SlotManager.uc,v 1.1 2004/05/17 09:37:20 elmuerte Exp $ -->
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

/** slot record configuration record */
struct SlotRecord
{
	/** the value to match, can contain wilcards: * (zero or many) or ? (one char) */
	var string data;
	/** defines what the data file contains */
	var ESlotType type;
	/** slot only available for spectators */
	var bool specOnly;
};
/** slot configuration */
var globalconfig array<SlotRecord> Slots;
/** the maxplayers will never increase above this limit */
var globalconfig int AbsoluteMaxPlayers;
/** the maxspectator will never increase above this limit */
var globalconfig int AbsoluteMaxSpectators;

var localized string PIgroup, PIdesc[3], PIhelp[3];

function bool PreLogin(	string Options, string Address, string PlayerID,
						out string Error, out string FailCode, bool bSpectator)
{
	local int i;
	local string tmp;

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
			log("Found reserved slot (#"$i$") for"@tmp, name);
   			if (Level.Game.AtCapacity(bSpectator))
			{
				if (!AtMaxCapacity(bSpectator))IncreaseCapicity(bSpectator);
				else log("Maximum capicity reached", name);
			}
			return true;
		}
	}
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

static function FillPlayInfo(PlayInfo PlayInfo)
{
	super.FillPlayInfo(PlayInfo);
	PlayInfo.AddSetting(default.PIgroup, "AbsoluteMaxPlayers", 		default.PIdesc[0], 200, 0, "Text", "3;0:999",,True,True);
 	PlayInfo.AddSetting(default.PIgroup, "AbsoluteMaxSpectators", 	default.PIdesc[1], 200, 0, "Text", "3;0:999",,True,True);
 	PlayInfo.AddSetting(default.PIgroup, "Slots", 					default.PIdesc[2], 200, 0, "Custom",,,True,True);
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

defaultproperties
{
	PIgroup="Reserved slots"
	PIdesc[0]="Absolute Max Players"
	PIhelp[0]="The maximum value will never increase about this value"
	PIdesc[1]="Absolute Max Spectators"
	PIhelp[1]="The maximum value will never increase about this value"
	PIdesc[2]="Slots"
	PIhelp[2]="The reserved slots"
}
