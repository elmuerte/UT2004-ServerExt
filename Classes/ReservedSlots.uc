/*******************************************************************************
	Managers reserved slots												<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: ReservedSlots.uc,v 1.1 2004/05/17 09:37:20 elmuerte Exp $ -->
*******************************************************************************/
class ReservedSlots extends AccessControl config;

/** allows you to add more than one slot manager */
var config array<string> SlotManagerClasses;
/** configured slot managers */
var array<SlotManagerBase> SlotManagers;

var protected array< class<SlotManagerBase> > SMClasses;

/** initialize */
event PreBeginPlay()
{
	local int i;
	local class<SlotManagerBase> SM;

	super.PreBeginPlay();
	enable('Tick');
	default.SMClasses.length = 0;
	for (i = 0; i < SlotManagerClasses.length; i++)
	{
		sm = class<SlotManagerBase>(DynamicLoadObject(SlotManagerClasses[i], class'Class'));
		if (sm != none)
		{
			default.SMClasses[default.SMClasses.length] = sm;
			SlotManagers[SlotManagers.length] = spawn(sm);
		}
	}
}

/** check for a valid reserved slot */
event PreLogin(string Options, string Address, string PlayerID, out string Error, out string FailCode, bool bSpectator)
{
	local int i;
	for (i = 0; i < SlotManagers.length; i++)
	{
		if (SlotManagers[i].PreLogin(Options, Address, PlayerID, Error, FailCode, bSpectator))
		{
			return;
		}
	}
	if ((Error != "") || (FailCode != "")) return;
	super.PreLogin(Options, Address, PlayerID, Error, FailCode, bSpectator);
}

/** check every tick to decrease the player limit */
event Tick(float bDelta)
{
	super.Tick(bDelta);
	// check normal players
	if (Level.Game.MaxPlayers > Level.Game.default.MaxPlayers)
	{
		if (Level.Game.NumPlayers < Level.Game.MaxPlayers)
		{
			Level.Game.MaxPlayers = Level.Game.NumPlayers;
		}
	}
	// check spectators
	if (Level.Game.MaxSpectators > Level.Game.default.MaxSpectators)
	{
		if (Level.Game.NumSpectators < Level.Game.MaxSpectators)
		{
			Level.Game.MaxSpectators = Level.Game.NumSpectators;
		}
	}
}

static function FillPlayInfo(PlayInfo PlayInfo)
{
	local int i;
	super.FillPlayInfo(PlayInfo);
	for (i = 0; i < default.SMClasses.length; i++)
	{
		default.SMClasses[i].static.FillPlayInfo(PlayInfo);
	}
}

defaultproperties
{
	SlotManagerClasses[0]="ServerExt.SlotManager"
}
