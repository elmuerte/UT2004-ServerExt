/** allows you to add more than one slot manager */
var config array<string> SlotManagerClasses;
/** configured slot managers */
var array<SlotManagerBase> SlotManagers;
/** used to call FillPlayInfo */
var protected array< class<SlotManagerBase> > SMClasses;
/** if set to true admin logins won't be announced */
var config bool bSilentAdmin;

var localized string PIgroup, PIdesc[2], PIhelp[2];

/** initialize */
event PreBeginPlay()
{
    local int i;
    local class<SlotManagerBase> SM;

    super.PreBeginPlay();
    Log("Loading ReservedSlots ...", name);
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

/** player logged out */
function NotifyLogout(Controller Exiting)
{
    local int i;
    for (i = 0; i < SlotManagers.length; i++)
    {
        SlotManagers[i].NotifyLogout(Exiting);
    }
}

static function FillPlayInfo(PlayInfo PlayInfo)
{
    local int i;
    super.FillPlayInfo(PlayInfo);
    PlayInfo.AddSetting(default.PIgroup, "bSilentAdmin", default.PIdesc[0], 200, 1, "Check");
    for (i = 0; i < default.SMClasses.length; i++)
    {
        default.SMClasses[i].static.FillPlayInfo(PlayInfo);
    }
}

static event string GetDescriptionText(string PropName)
{
    switch (PropName)
    {
        case "bSilentAdmin":    return default.PIhelp[0];
    }
    return "";
}

function AdminEntered( PlayerController P, string Username)
{
    if (bSilentAdmin) return;
    super.AdminEntered(P, Username);
}

function AdminExited( PlayerController P )
{
    if (bSilentAdmin) return;
    super.AdminExited(P);
}

defaultproperties
{
    PIgroup="Reserved slots"
    PIdesc[0]="Silent Admin Login"
    PIhelp[0]="If set an admin login won't be broadcasted"

    bSilentAdmin=false
    SlotManagerClasses[0]="ServerExt.SlotManager"
}
