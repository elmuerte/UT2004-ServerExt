# UT2004 ServerExt

ServerExt is a package containing extentions for UT2004 servers. It consist out of a couple of independed components:

   - Chat Filter
   - Player join log
   - Remote stats
   - Reserved slots
   - RSS Feed Mutator
   - ServQuery
   - Stats chat log
   - Team Balance mutator

# Revision history
## Changed since v109

   - 0000025: [! Other] ServerExt.ServQuery.ReceivedText is a very 'expensive' function
   - 0000026: [! Other] Admin email property reported by ServQuery with changed capitalisation
   - 0000023: [Reserved Slots] Updating existing entry to spec only does not work
   - 0000029: [Team Balancer] ServerExt.TeamBalanceRules.FindPlayerStart breaks other GameRules

## Changes since v108

   - Fixed a performance issue in the ChatFilter bad name checking [BT#11]
   - Changed critical player check to use the GameInfo's CriticalPlayer function [BT#10]
   - Made the broadcast handler check more foolproof. This can be disabled for ChatFilter and StatsChatLog by setting bDisableBHFix=false
   - Fixed the player join log [BT#12]
   - (Web)admin can be shown unfiltered text (bUnfilteredWebAdmin and bUnfilteredAdmin) [BT#16]
   - Fixed lives reporting for ServQuery [BT#21 & BT#20]
   - Added option to allow WebAdmin to see team chat (bWebAdminReceiveTeam) [BT#17]
   - Fixed a minor bug in the webadmin module loading
   - Changed the code to load the modules when UT2Vote replaces the default WebAdmin

Note: [BT#..] entries refer to BugTracker issues.

## Changes since v107

   - Fixed non scrolling webadmin pages
   - RSS: Fixed crach on long descriptions, there are now capped at 512 chars
   - Upgraded to LibHTTP 4
   - ReservedSlots: added SOM_KickBestSPM and SOM_KickWorstSPM slot open methods (SPM = score per minute)
   - ReservedSlots: added bSilentAdmin option to hide admin logins
   - ReservedSlots: added bProtectAdmins option to protect admins from being kicked
   - RSS: Added ability to edit the feed content through the webadmin
   - ChatFilter+Stats chat log: Added workaround for UT2Vote's broken broadcast handler

## Changes since v106

   - ReservedSlots: reserved slots users won't be kicked to make room
   - Fixed ChatFilter's warning mutator not loading
   - Fixed crash when you add too many reserved slots
   - Removed log verbosity for remote stats

## Changes since v105b

   - Fixed BM_Sequential mode for mutRSS
   - Client packages split up into two: one for ChatFilter and one for mutRSS
   - mutRSS now uses LibHTTP3
   - Fixed recursion issue in ChatFilter (e.g. replace xxx -> x doesn't crash the server anymore)
   - Fixed an issue with spaces in bad words
   - Fixed warning mutator for ChatFilter
   - Added a new option: bWarnVoting, only when this is set the voting mutator will be used and allow people to vote on a judgement of a player.
   - Fixed the Team Balancer where the wrong spawn points where used.
   - Added a new module: Remote stats, this will POST the stats to a website

## Changes since v105a

   - ReservedSlots, ReservedSlotsIni and SlotManager are now compiled with `parseconfig`. This means you change the config file to use on the commandline: -ReservedSlots=myini.ini, -ReservedSlotsIni=myini.ini, -SlotManager=myini.ini. The settings in the system config are loaded before the specified config file.

## Changes since v105

   - Fixed a couple of issues with text fields in the webadmin
   - Fixed reserved slots using name or password as check

## Changes since v104

   - Removed bFriendlymessage from ChatFilter, friendly messages are now always used and doesn't require the client side package
   - Added reserved slot feature
   - Added team balancer mutator
   - Fixed chat logging for spectators, requires an updated version of utstatsdb before it work (any version newer than 2.21)
   - Fixed gamepassword not being passed by ServQuery

## Changes since v103

   - Removed debug log spam
   - Fixed a couple of accessed nones in chatfilter

## Changes since v102

   - The RSS Feed configuration can now also be saved in an other config file than the RSS.ini. This has been added for GISPs, if you do not host multiple servers from the same location with different admins, then you should not use this feature.
   - Fixed "sequential" feed order with only one available feed
   - Fixed the client side browser
   - Added a new config option to MutRSS: bAnnounce
   - This will controll announcing this mutator to the master server
   - Fixed incorrect chatlogging in chatfilter
   - Fixed a couple of accessed nones in chatfilter

## Changes since v101

   - Included the webadmin pages for MutRSS
   - Fixed MutRSS webadmin removing admin\users tab

## Changes since v100

   - Fixed duplicate chat log entries
   - Ported the ChatFilter from UT2003

# General Installation

Copy the following files to the System directory of your UT2004 servers:

```
    LibHTTP4.u
    ServerExt.int
    ServerExt.u
    ServerExt.ucl
    ServerExtClientA.u
    ServerExtClientA.int
    ServerExtClientB_2.u
    ServerExtClientB_2.int
    wUtils.u
```

Remove the old ServerExtClient.u, ServerExtClient10*.u files from you system and configuration.

Copy the following files to the Web\ServerAdmin directory of your UT2004 servers:

```
    rssfeeds.htm
    sexframe.htm
    slotmanager.htm
    slotmanager-entry.inc
```

Note: do not add any of the packages to the ServerPackages list. When a package needs to be added to that list ServerExt will do that automatically. 

# Documentation

Documentation for ServerExt can be found on the [UnrealAdminWiki](http://wiki.unrealadmin.org/ServerExt).
