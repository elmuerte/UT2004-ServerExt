/*******************************************************************************
	Mutator to provide voting for chat abuse                            <br />

	(c) 2004, Michiel "El Muerte" Hendriks                              <br />
	Released under the Open Unreal Mod License                          <br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense

	<!-- $Id: CFWarningMut.uc,v 1.3 2004/11/11 19:55:29 elmuerte Exp $ -->
*******************************************************************************/

class CFWarningMut extends Mutator cacheexempt;

/** pointer to the chatfilter class for "execution" */
var protected ChatFilter cf;

/** judgement record */
struct JudgeMent
{
    var array<PlayerController> Jury;
    var float total;
};
/** all current judgements */
var array<JudgeMent> JudgeMents;

event PreBeginPlay()
{
	foreach Level.AllActors( class'ChatFilter', cf )
	{
		break;
	}
	if (cf == none) Error("No ChatFilter actor found");
}

/** cast a judgement vote */
function judgeMentVote(PlayerController Sender, int offset)
{
	local int i;
	if (cf.ChatRecords.Length > offset)
	{
		if (cf.ChatRecords[offset].warnings > 0)
		{
			if (JudgeMents.Length <= offset)
			{
				JudgeMents.Length = offset+1;
				JudgeMents[offset].total = 0;
			}
			for (i = 0; i < JudgeMents[offset].Jury.Length; i++)
			{
				if (JudgeMents[offset].Jury[i] == Sender) return;
			}
			JudgeMents[offset].Jury.Length = i+1;
			JudgeMents[offset].Jury[i] = Sender;
			JudgeMents[offset].total += 1;
			if ((JudgeMents[offset].total/float(Level.Game.NumPlayers)) >= cf.fMinVote)
			{
				cf.ChatRecords[offset].bUserRequest = true;
				cf.judgeWarning(cf.ChatRecords[offset].Sender, offset);
				JudgeMents[offset].total = 0;
				JudgeMents[offset].Jury.Length = 0;
			}
		}
	}
}

function Mutate(string MutateString, PlayerController Sender)
{
	local array<string> parts;
	if (split(MutateString, " ", parts) > 2)
	{
		if (parts[0] ~= "cf")
		{
			if (parts[1] ~= "judge")
			{
				judgeMentVote(Sender, int(parts[2]));
			}
		}
	}
	Super.Mutate(MutateString, Sender);
}

defaultproperties
{
  FriendlyName="ChatFilter"
  Description="Clean up server chatting"
  GroupName="ChatFilter"
}
