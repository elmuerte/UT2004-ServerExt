/*******************************************************************************
	ServQuery Master Server Uplink										<br />
	Replaced the original Master Server Uplink							<br />

	(c) 2002, 2003, 2004, Michiel "El Muerte" Hendriks					<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: SQMSUplink.uc,v 1.1 2004/03/27 15:45:03 elmuerte Exp $ -->
*******************************************************************************/

class SQMSUplink extends MasterServerUplink config;

/** respond to GameSpy Queries */
var config bool bGameSpyQueries;
/** the GamespyQuery class to spawn */
var config string UdpGamespyQueryClass;

event BeginPlay()
{
	local class<UdpGamespyQuery> GSQ;

	if ( bGameSpyQueries )
	{
		GSQ = class<UdpGamespyQuery>(DynamicLoadObject(UdpGamespyQueryClass, class'Class', false));
		if (GSQ != none)
		{
			GamespyQueryLink = Spawn(GSQ);
		}
	}

	if( DoUplink )
	{
		// If we're sending stats,
		if( SendStats )
		{
			foreach AllActors(class'MasterServerGameStats', GameStats )
			{
				if( GameStats.Uplink == None )
					GameStats.Uplink = Self;
				else
					GameStats = None;
				break;
			}
			if( GameStats == None )	Log("MasterServerUplink: MasterServerGameStats not found - stats uploading disabled.");}
		}
		if(UplinkToGamespy){if (DoUplink||class'ServQuery'.static.GSQonline())

		Spawn(class'UdpGamespyUplink');
	}
	Reconnect();
}

defaultproperties
{
	bGameSpyQueries=true
	UdpGamespyQueryClass="ServerExt.ServQuery"
}
