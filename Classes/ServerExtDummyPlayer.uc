/*******************************************************************************
    Dummy PC to fool UT2Vote                                            <br />

    (c) 2006, Michiel "El Muerte" Hendriks                              <br />
    Released under the Open Unreal Mod License                          <br />
    http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

    <!-- $Id: ServerExtDummyPlayer.uc,v 1.1 2006/02/12 19:36:48 elmuerte Exp $ -->
*******************************************************************************/

class ServerExtDummyPlayer extends MessagingSpectator;

function InitPlayerReplicationInfo()
{
	Super.InitPlayerReplicationInfo();
	PlayerReplicationInfo.PlayerName="";
}