/*******************************************************************************
	Actual slot manager close (base class)								<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: SlotManagerBase.uc,v 1.1 2004/05/17 09:37:20 elmuerte Exp $ -->
*******************************************************************************/
class SlotManagerBase extends Info abstract;

/** return true when this is the final judgement */
function bool PreLogin(	string Options, string Address, string PlayerID,
						out string Error, out string FailCode, bool bSpectator)
{
	return false;
}

function IncreaseCapicity(optional bool bSpectator)
{
	log("Increasing limit", name);
	if (bSpectator)
   	{
   		Level.Game.MaxSpectators++;
   	}
   	else {
   		Level.Game.MaxPlayers++;
   	}
}
