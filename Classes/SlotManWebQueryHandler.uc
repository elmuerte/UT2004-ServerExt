/*******************************************************************************
	Slot Manager webadmin												<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: SlotManWebQueryHandler.uc,v 1.2 2004/05/21 20:56:54 elmuerte Exp $ -->
*******************************************************************************/
class SlotManWebQueryHandler extends SExWebQueryHandler;

var protected SlotManager SlotManager;

var localized string SlotType[5], MethodType[6], PageHelp;

function bool Init()
{
	foreach AllObjects(class'SlotManager', SlotManager)
	{
		if (SlotManager != none) break;
	}
	return ValidateRequirements(SlotManager != none);
}

function bool Query(WebRequest Request, WebResponse Response)
{
	switch (Mid(Request.URI, 1))
	{
		case DefaultPage:	QuerySlots(Request, Response); return true;
	}
}

function QuerySlots(WebRequest Request, WebResponse Response)
{
	local int i,j;
	local string slots, tmp;

	if ((Request.GetVariable("submit", "") == "new") && (Request.GetVariable("data", "") != ""))
	{
		SlotManager.Slots.Length = SlotManager.Slots.Length+1;
		SlotManager.Slots[SlotManager.Slots.Length-1].data = Request.GetVariable("data", "");
		SlotManager.Slots[SlotManager.Slots.Length-1].type = SlotManager.GetSlotType(Request.GetVariable("type", "0"));
		SlotManager.Slots[SlotManager.Slots.Length-1].specOnly = Request.GetVariable("speconly", "") == "true";
		SlotManager.Slots[SlotManager.Slots.Length-1].method = SlotManager.GetSlotOpenMethod(Request.GetVariable("method", "0"));
		SlotManager.Slots[SlotManager.Slots.Length-1].comment = Request.GetVariable("comment", "");
		SlotManager.SaveConfig();
	}
	else if (Request.GetVariable("submit", "") == "delete")
	{
		i = int(Request.GetVariable("sid", "-1"));
		if ((i >= 0) || (i < SlotManager.Slots.Length))
		{
			SlotManager.Slots.Remove(i, 1);
			SlotManager.SaveConfig();
		}
	}
	else if (Request.GetVariable("submit", "") == "update")
	{
		i = int(Request.GetVariable("sid", "-1"));
		if ((i >= 0) || (i < SlotManager.Slots.Length))
		{
			SlotManager.Slots[i].data = Request.GetVariable("data", "");
			SlotManager.Slots[i].type = SlotManager.GetSlotType(Request.GetVariable("type", "0"));
			SlotManager.Slots[i].specOnly = Request.GetVariable("speconly", "") == "true";
			SlotManager.Slots[i].method = SlotManager.GetSlotOpenMethod(Request.GetVariable("method", "0"));
			SlotManager.Slots[i].comment = Request.GetVariable("comment", "");
			SlotManager.SaveConfig();
		}
	}

	for (i = 0; i < SlotManager.Slots.Length; i++)
	{
		Response.Subst("sid", i);
		Response.Subst("data", SlotManager.Slots[i].data);
		if (SlotManager.Slots[i].specOnly) Response.Subst("speconly", "checked");
			else Response.Subst("speconly", "");
		tmp = "";
		for (j = 0; j < SlotManager.ESlotType.EnumCount; j++)
		{
			tmp $= "<option value=\""$j$"\"";
			if (SlotManager.Slots[i].type == j) tmp @= "selected";
			tmp $= ">"$SlotType[j];
		}
		Response.Subst("type", tmp);
		tmp = "";
		for (j = 0; j < SlotManager.ESlotOpenMethod.EnumCount; j++)
		{
			tmp $= "<option value=\""$j$"\"";
			if (SlotManager.Slots[i].method == j) tmp @= "selected";
			tmp $= ">"$MethodType[j];
		}
		Response.Subst("method", tmp);
		Response.Subst("comment", SlotManager.Slots[i].comment);
		slots = slots $ WebInclude(DefaultPage $ "-entry");
	}
	Response.Subst("slots", slots);
	Response.Subst("PageHelp", PageHelp);
	ShowPage(Response, DefaultPage);
}

defaultproperties
{
	DefaultPage="slotmanager"
	Title="Reserved Slots"
	NeededPrivs="Xi"

	SlotType[0]="IP"
	SlotType[1]="CDKey Hash"
	SlotType[2]="Nickname"
	SlotType[3]="Password"
	SlotType[4]="Connect url"

	MethodType[0]="Expand limit"
	MethodType[1]="Kick random player"
	MethodType[2]="Kick worst player"
	MethodType[3]="Kick best player"
	MethodType[4]="Kick oldest player"
	MethodType[5]="Kick newest player"

	PageHelp="On this page you can change the reserved slots. each slot can have different behaviour settings. Consult the readme file if the information isn't clear enough."
}
