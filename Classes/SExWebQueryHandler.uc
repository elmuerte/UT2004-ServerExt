/*******************************************************************************
    General query handler for ServerExt packages                        <br />

    (c) 2004, Michiel "El Muerte" Hendriks                              <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: SExWebQueryHandler.uc,v 1.3 2005/11/27 12:11:09 elmuerte Exp $ -->
*******************************************************************************/
class SExWebQueryHandler extends xWebQueryHandler abstract;

var string singleFrame;

/** if bValid is false, remove itself from the query handler list */
function bool ValidateRequirements(bool bValid)
{
    local int i;
    if (!bValid)
    {
        for (i = 0; i < QueryHandlerClasses.length; i++)
        {
            if (QueryHandlerClasses[i] ~= string(class))
            {
                QueryHandlerClasses.remove(i, 1);
                Outer.SaveConfig();
            }
        }
        return false;
    }
    return true;
}

function bool Query(WebRequest Request, WebResponse Response)
{
    switch (Mid(Request.URI, 1))
    {
        case DefaultPage:
            if (Request.GetVariable("subpage", "0") == "1")
            {
                Response.Subst("PostAction", DefaultPage$"?subpage=1");
                return false;
            }
            QueryFrame(Request, Response);
            return true;
    }
}

function QueryFrame(WebRequest Request, WebResponse Response)
{
    Response.Subst("Title", Title);
    Response.Subst("MainURI", DefaultPage$"?subpage=1");
    ShowPage(Response, singleFrame);
}

defaultproperties
{
    singleFrame="sexframe"
}