/*******************************************************************************
	Remote stat logging. Sends the stat logs to a remote server. Contains the
	actual logic because the stats actor will be killed at the end of the game
	before we can submit the last piece of data.						<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: RStatsLink.uc,v 1.1 2004/09/28 08:12:37 elmuerte Exp $ -->
*******************************************************************************/

class RStatsLink extends MasterServerGameStats;

/**
	Destination url to post to.
*/
var config string PostURL;

/**
	Maximum buffer size allowed, data won't be posted until the buffer exceeds
	this size. Don't set this too high because it might cause issue and the
	end of a game.
*/
var config int BufferSize;

/** delay to retry sending data */
var config float fRetryDelay;

/** local buffer for the remote stats */
var array<string> Buffer;

struct BufferCacheEntry
{
	var int seq;
	var array<string> buffer;
};
/** cache of the buffers send, in case an error occures */
var protected array<BufferCacheEntry> BufferCache;

/** socket to use to post the data */
var protected HttpSock sock;

/** sequence number */
var protected int seq;
/** sequence number of the last completed sequence */
var protected int lastSeq;

/** local copy of the server host */
var protected string serverHost;
/** time of the match start */
var protected string gameTimestamp;

/** spawn our post socket */
function PreBeginPlay()
{
	seq = 0;
	lastSeq = 0;
	if (PostURL != "")
	{
		sock = spawn(class'HttpSock');
		gameTimestamp = string(sock.now());
		sock.OnComplete = PostComplete;
		sock.OnConnectionTimeout = PostTimeout;
		sock.OnConnectError = PostConnectError;
		sock.iVerbose = 255;
	}
	else {
		Log("ERROR: PostURL is empty", name);
	}
}

/** find the serverhost */
function BeginPlay()
{
	local InternetLink il;
	local InternetLink.IpAddr addr;
	foreach AllActors(class'InternetLink', il);
	if (il == none)
	{
		il = spawn(class'InternetLink');
	}
	il.GetLocalIP(addr);
	serverHost = il.IpAddrToString(addr);
	serverHost = Left(serverHost, InStr(serverHost, ":"));
	log("ServerHost ="@serverHost);
}

/** add this line to the buffer */
function BufferLogf(string LogString)
{
	Buffer[Buffer.length] = LogString;
	if (CalcBufferSize() > BufferSize) FlushBuffer();
}

/** calculate the buffer size */
function int CalcBufferSize()
{
	local int i, res;
	res = 0;
	for (i = 0; i < Buffer.length; i++)
	{
		res += Len(Buffer[i]);
	}
	return res;
}

/** flush the last piece of stats */
function FinalFlush()
{
	if (sock == none) return;
	sock.TransferMode = TM_Fast; // switch to fast transfer mode
	FlushBuffer();
}

/** post the buffer data */
function FlushBuffer()
{
	local int i;
	if (sock == none) return;

	i = BufferCache.length;
	BufferCache.length = i+1;
	BufferCache[i].seq = seq+1;
	BufferCache[i].buffer = buffer;
	buffer.length = 0;
	if (seq == lastSeq) SendBuffer(i);
	else {
		log("Postponing stats sendig", name);
	}
	seq++;
}

/** send a buffered record */
function SendBuffer(int i)
{
	sock.clearFormData();
	sock.setFormData("serverHost", serverHost);
	sock.setFormData("serverName", level.game.StripColor(level.Game.GameReplicationInfo.ServerName));
	sock.setFormData("serverPort", string(level.game.GetServerPort()));
	sock.setFormData("gameTimestamp", gameTimestamp);
	sock.setFormData("sequence", string(BufferCache[i].seq));
	sock.setFormDataEx("stats", BufferCache[i].buffer);
	sock.post(PostURL);
}

/** post was complete */
function PostComplete()
{
	if (sock.LastStatus == 200)
	{
		lastSeq++;
		BufferCache.Remove(0, 1);
		// more to send
		if (BufferCache.length > 0) SendBuffer(0);
	}
	else {
		log("No valid response from the post url: "@sock.LastStatus@class'HttpUtil'.static.HTTPResponseCode(sock.LastStatus), name);
	}
}

function PostTimeout()
{
	log("Timeout while trying to post data, will retry in"@fRetryDelay@"seconds", name);
	SetTimer(fRetryDelay, false);
}

function PostConnectError()
{
	log("Error connecting to the server, will retry in"@fRetryDelay@"seconds", name);
	SetTimer(fRetryDelay, false);
}

/** retry to send data */
function Timer()
{
	if (BufferCache.length > 0) SendBuffer(0);
}

defaultproperties
{
	BufferSize=512
	fRetryDelay=30
}
