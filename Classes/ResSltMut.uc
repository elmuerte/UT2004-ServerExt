/*******************************************************************************
	hidden mutator to check player limits								<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: ResSltMut.uc,v 1.1 2004/05/17 21:19:04 elmuerte Exp $ -->
*******************************************************************************/
class ResSltMut extends Mutator cacheexempt;

/** check every tick to decrease the player limit */
function NotifyLogout(Controller Exiting)
{
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
	super.NotifyLogout(Exiting);
}

/** call modify login on the slot managers */
function ModifyLogin(out string Portal, out string Options)
{
	if (ReservedSlots(Level.Game.AccessControl) != none) ReservedSlots(Level.Game.AccessControl).ModifyLogin(Portal, Options);
	else if (ReservedSlotsIni(Level.Game.AccessControl) != none) ReservedSlotsIni(Level.Game.AccessControl).ModifyLogin(Portal, Options);
	super.ModifyLogin(Portal, Options);
}

/** reset the default player limits */
function ServerTraveling(string URL, bool bItems)
{
	super.ServerTraveling(URL, bItems);
	Level.Game.MaxPlayers = Level.Game.default.MaxPlayers;
	Level.Game.MaxSpectators = Level.Game.default.MaxSpectators;
}

/** make sure this mutator doesn't show up */
function GetServerDetails( out GameInfo.ServerResponseLine ServerState );
