/*******************************************************************************
    General query handler for ServerExt packages                        <br />

    (c) 2004, Michiel "El Muerte" Hendriks                              <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: SExWebQueryHandler.uc,v 1.2 2004/10/20 14:03:03 elmuerte Exp $ -->
*******************************************************************************/
class SExWebQueryHandler extends xWebQueryHandler abstract;

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
