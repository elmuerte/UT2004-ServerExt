/** allows you to add more than one slot manager */
var config array<string> SlotManagerClasses;
/** configured slot managers */
var array<SlotManagerBase> SlotManagers;
/** used to call FillPlayInfo */
var protected array< class<SlotManagerBase> > SMClasses;

/** initialize */
event PreBeginPlay()
{
	local int i;
	local class<SlotManagerBase> SM;

	super.PreBeginPlay();
	Level.Game.AddMutator("ServerExt.ResSltMut");
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

/** modify login info */
function ModifyLogin(out string Portal, out string Options)
{
	local int i;
	for (i = 0; i < SlotManagers.length; i++)
	{
		SlotManagers[i].ModifyLogin(Portal, Options);
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
