/*******************************************************************************
    Actual slot manager close (base class)                              <br />

    (c) 2004, Michiel "El Muerte" Hendriks                              <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: SlotManagerBase.uc,v 1.4 2004/10/20 14:03:03 elmuerte Exp $ -->
*******************************************************************************/
class SlotManagerBase extends Info abstract;

#include classes/const.inc

/** query handler to add to the webadmin */
var string WebQueryHandler;

event PreBeginPlay()
{
    super.PreBeginPlay();
    if (WebQueryHandler != "") LoadWebAdmin();
}

/** load the webadmin */
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
    for (i = 0; i < webadmin.QueryHandlerClasses.Length-1; i++)
    {
        if (webadmin.QueryHandlerClasses[i] == WebQueryHandler) break;
    }
    if (i >= webadmin.QueryHandlerClasses.Length)
    {
        webadmin.QueryHandlerClasses.Length = webadmin.QueryHandlerClasses.Length+1;
        webadmin.QueryHandlerClasses[webadmin.QueryHandlerClasses.Length-1] = WebQueryHandler;
        qh = class<xWebQueryHandler>(DynamicLoadObject(WebQueryHandler, class'Class'));
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

/** return true when this is the final judgement */
function bool PreLogin( string Options, string Address, string PlayerID,
                        out string Error, out string FailCode, bool bSpectator)
{
    return false;
}

/** modify login info */
function ModifyLogin(out string Portal, out string Options);

/** increase the capicity */
function IncreaseCapicity(optional bool bSpectator)
{
    if (bSpectator)
    {
        log("Increasing max spectator limit", name);
        Level.Game.MaxSpectators++;
    }
    else {
        log("Increasing max player limit", name);
        Level.Game.MaxPlayers++;
    }
}

