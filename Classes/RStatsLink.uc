/*******************************************************************************
	Remote stat logging. Sends the stat logs to a remote server. Contains the
	actual logic because the stats actor will be killed at the end of the game
	before we can submit the last piece of data.						<br />

	(c) 2004, Michiel "El Muerte" Hendriks								<br />
	Released under the Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/OpenUnrealModLicense				<br />

	<!-- $Id: RStatsLink.uc,v 1.2 2004/10/01 10:10:14 elmuerte Exp $ -->
*******************************************************************************/

class RStatsLink extends Info;

/**
	Destination url to post to.
*/
var config string PostURL;
/**
	This name/value combination will be added to the request. You can use this
	to pass along a password with the request.
*/
var config string SecretName, SecretValue;

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
var protected string gameDateTime;

/** spawn our post socket */
function PreBeginPlay()
{
	seq = 0;
	lastSeq = 0;
	if (PostURL != "")
	{
		sock = spawn(class'HttpSock');
		gameDateTime = class'HttpUtil'.static.timestampToString(sock.now(),,"2822");
		gameDateTime = repl(gameDateTime, " +0000", "");
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
	local int i, j;
	if (sock == none) return;
	sock.TransferMode = TM_Fast; // switch to fast transfer mode
	if (BufferCache.length == 0) BufferCache.length = 1;
	// merging buffers
	for (i = 1; i < BufferCache.length; i++)
	{
		for (j = 0; j < BufferCache[i].buffer.Length; j++)
		{
			BufferCache[0].buffer[BufferCache[0].buffer.length] = BufferCache[i].buffer[j];
		}
	}
	if (BufferCache.length > 1) BufferCache.length = 1;
	for (i = 0; i < Buffer.Length; i++)
	{
		BufferCache[0].buffer[BufferCache[0].buffer.length] = Buffer[i];
	}
	Buffer.length = 0;
	if (BufferCache[0].buffer.length == 0) return;
	SendBuffer(0);
}

/** post the buffer data */
function FlushBuffer()
{
	local int i;
	if (sock == none) return;
	if (buffer.length == 0) return;

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
	sock.setFormData("serverPort", level.game.GetServerPort());
	sock.setFormData("gameDateTime", gameDateTime);
	sock.setFormData("sequence", BufferCache[i].seq);
	sock.setFormData(SecretName, SecretValue); // add the secret
	sock.setFormDataEx("stats", BufferCache[i].buffer);
	sock.post(PostURL);
}

/** post was complete */
function PostComplete(HttpSock sender)
{
	if (sock.LastStatus == 200)
	{
		lastSeq++;
		BufferCache.Remove(0, 1);
		// more to send
		if (BufferCache.length > 0) SendBuffer(0);
	}
	else {
		log("No valid response from the post url:"@sock.LastStatus@class'HttpUtil'.static.HTTPResponseCode(sock.LastStatus), name);
	}
}

function PostTimeout(HttpSock sender)
{
	log("Timeout while trying to post data, will retry in"@fRetryDelay@"seconds", name);
	SetTimer(fRetryDelay, false);
}

function PostConnectError(HttpSock sender)
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
	BufferSize=2048
	fRetryDelay=30
	SecretName="secret"
	SecretValue=""
}
