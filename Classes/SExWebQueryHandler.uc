/*******************************************************************************
	General query handler for ServerExt packages						<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: SExWebQueryHandler.uc,v 1.1 2004/05/17 21:19:04 elmuerte Exp $ -->
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
