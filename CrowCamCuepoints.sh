#!/bin/bash

#------------------------------------------------------------------------------
# CrowCamCuepoints.sh - A Bash script to add motion cuepoints to a live stream.
#------------------------------------------------------------------------------
# Please see the accompanying file REAMDE.md for setup instructions. Web Link:
#        https://github.com/tfabris/CrowCam/blob/master/README.md
#
# The scripts in this project don't work "out of the box", they need some
# configuration. All details are found in README.md, so please look there
# and follow the instructions.
#------------------------------------------------------------------------------


# ----------------------------------------------------------------------------
# Workaround to allow exiting a Bash script from inside a function call. See
# this EmpegBBS post for details of how this works and why it's needed:
# https://empegbbs.com/ubbthreads.php/topics/371554
# Note: the functions which call these traps are in CrowCamHelperFunctions.sh
# ----------------------------------------------------------------------------
# Set a trap to receive a TERM signal from a function, and execute the code
# block "exit 1", in the context of the top-level of this Bash script, as soon
# as it receives the TERM signal.
trap "exit 1" TERM

# Create an exported environment variable named "TOP_PID" and populate it with
# the PID of this top-level Bash script. Use "$$" to identify the top level
# PID of this script. The function will use "$TOP_PID" to identify which PID to
# send the TERM signal to, once a program exit is desired.
export TOP_PID=$$


#------------------------------------------------------------------------------
# Startup configuration variables 
#------------------------------------------------------------------------------

# Configure debug mode for testing this script. Set this value to blank "" for
# running in the final functional mode on the Synology Task Scheduler.
debugMode=""         # True final runtime mode for Synology.
# debugMode="Synology" # Test on Synology SSH prompt, console or redirect output.
debugMode="MacHome"  # Test on Mac at home, LAN connection to Synology.
# debugMode="MacAway"  # Test on Mac away from home, no connection to Synology.
# debugMode="WinAway"  # In the jungle, the mighty jungle.

# Program name used in log messages.
programname="CrowCam Cuepoints"

# Get the directory of the current script so that we can find files in the
# same folder as this script, regardless of the current working directory. The
# technique was learned here: https://stackoverflow.com/a/246128/3621748
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Load the configuration file "crowcam-config", which contains variables that
# are user-specific.
source "$DIR/crowcam-config"

# Load the include file "CrowCamHelperFunctions.sh", which contains shared
# functions that are used in multiple scripts.
source "$DIR/CrowCamHelperFunctions.sh"

#------------------------------------------------------------------------------
# Main Script Code Body
#------------------------------------------------------------------------------

# Log the current test mode state, if activated.
if [ ! -z "$debugMode" ]
then
  LogMessage "err" "------------- Script $programname is running in debug mode: $debugMode -------------"
fi

# Log current script location and working directory.
LogMessage "dbg" "Script exists in directory: $DIR"
LogMessage "dbg" "Current working directory:  $(pwd)"

# Verify that the necessary external files exist.
if [ ! -e "$clientIdJson" ]
then
  LogMessage "err" "Missing file $clientIdJson"
  exit 1
fi
if [ ! -e "$crowcamTokens" ]
then
  LogMessage "err" "Missing file $crowcamTokens"
  exit 1
fi
if [ ! -e "$apicreds" ]
then
  LogMessage "err" "Missing file $apicreds"
  exit 1
fi

# Get API creds out of the external file, assert values are non-blank.
# TO DO: Learn the correct linux-supported method for storing and retrieving a
# username and password in an encrypted way.
read username password < "$apicreds"
if [ -z "$username" ] || [ -z "$password" ]
then
  LogMessage "err" "Problem obtaining API credentials from external file"
fi



#------------------------------------------------------------------------------
# Retrieve recent event information from Synology API.
#------------------------------------------------------------------------------

# Work in progress. Attempt to retrieve the recent history of motion detection
# events from Synology. This is the first experiment to see if I can query
# this at all? This does not work yet. Link to docs:
# https://global.download.synology.com/download/Document/Software/DeveloperGuide/Package/SurveillanceStation/All/enu/Surveillance_Station_Web_API.pdf
# Example from docs:
# "2.3.21.8 ListHistory method"
# GET /webapi/entry.cgi?start=0&api="SYNO.SurveillanceStation.ActionRule"&limit=100&version="1"&method="ListHistory"
# This produces no results, so, not using this.

# Example from docs:
# "2.3.11.6 CountByCategory method"
# GET /webapi/entry.cgi?locked=0&version="4"&blIncludeSnapshot=true&cameraIds=""&evtSrcType=2&reason=""&api="SYNO.SurveillanceStation.Recording"&evtSrcId=-1&toTime=0&limit=0&fromTime=0&method="CountByCategory"&timezoneOffset=480&includeAllCam=true
#
# Note: Not that many parameters are needed. The code below, using fewer
# parameters than the example, produces the total count of events that
# occurred on each date, with the breakdown of how many occurred in the AM and
# the PM of each date, as well as the total for the queried time range.
#
# {
#   "data":{
#     "date":{
#       "-1":53,
#                (... other entries omitted here ...)
#       "2020/05/03":{
#         "-1":8,
#         "am":4,
#         "pm":4
#       }
#     },
#     "evt_cam":{
#       "0":{
#         "-1":53,
#         "2-CrowCam":53
#       },
#       "-1":53
#     },
#     "recCntTmstmp":47375347270,
#     "total":53
#   },
#   "success":true
# }

# Create a query to see how many events occurred in the last X time period.
# Set a time range that is X seconds ago (300 = 5 minutes ago for example).
howLongAgoInSeconds=9600
toTime=$( date +%s )
fromTime=$(( $toTime -  $howLongAgoInSeconds))

# Get current system's timezone offset from Zulu based on current system
# timezone config. Lower case "%z" returns a value that looks like "-0700"
# (for PDT, which is my example).
timzoneZuluOffset=$( date +%z )

# Convert that into minutes of timezone offset from UTC, because the Synology
# API expects the "timezoneOffset" variable to be in minutes. First step is to
# get this into decimal hours using this great technique:
# https://unix.stackexchange.com/a/434133
timezoneOffsetHours=$( date +%z | sed -E 's/^([+-])(..)(..)/scale=2;0\1(\2 + \3\/60)/' | bc )
timezoneOffset=$( echo "$timezoneOffsetHours * 60" | bc )
LogMessage "dbg" "Current system timezone offset: ZuluCode: $timzoneZuluOffset  - Hours: $timezoneOffsetHours  - Minutes: $timezoneOffset"

# Perform the API query to look for events in that time range with that time offset.
eventCount=$( WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.Recording&version=4&method=CountByCategory&limit=100&locked=0&timezoneOffset=$timezoneOffset&fromTime=$fromTime&toTime=$toTime" )

# Parse the count of "total": out of that output:
totalRecentEvents=""
totalRecentEvents=$(echo $eventCount | sed 's/"total"/\'$'\n&/g' | grep -m 1 "total" | cut -d ':' -f2 | cut -d '}' -f1)
LogMessage "dbg" "totalRecentEvents: $totalRecentEvents"

# Currently the above experimental code does not produce the results that I
# want. The query works, and if I make the time range large enough, it
# produces a nonzero count of events. However querying recent motion events
# (in the last few minutes) produces a "0" result even if something happened
# within the last couple of minutes. This is both with, and without, the
# timezoneOffset parameter being included. To do: get to the bottom of this.

# Debugging - Quit early while I am doing experiments with the APIs.
exit 0




#------------------------------------------------------------------------------
# Write a cuepoint marker to the live/current/active YouTube video stream.
#------------------------------------------------------------------------------

# Authenticate with the YouTube API and receive the Access Token which allows
# us to make YouTube API calls. Retrieves the $accessToken variable.
YouTubeApiAuth

# If the access Token is empty, crash out of the program. An error message
# will have already been printed if this is the case, so we can just bail
# out without saying anything to the console here.
if test -z "$accessToken" 
then
    exit 1
fi

# Get the current live broadcast information details which are needed in order
# to update it. Details of the items in the response are found here:
# https://developers.google.com/youtube/v3/live/docs/liveBroadcasts#resource
curlUrl="https://www.googleapis.com/youtube/v3/liveBroadcasts?part=snippet,contentDetails&broadcastType=persistent&mine=true&access_token=$accessToken"
liveBroadcastOutput=""
liveBroadcastOutput=$( curl -s -m 20 $curlUrl )

# Debugging output. Only needed if you run into a nasty bug here.
# Leave deactivated most of the time.
# LogMessage "dbg" "liveBroadcastOutput information: $liveBroadcastOutput"

# Extract the boundStreamId which may be needed in order to find other
# information later. 
boundStreamId=""
boundStreamId=$(echo $liveBroadcastOutput | sed 's/"boundStreamId"/\'$'\n&/g' | grep -m 1 "boundStreamId" | cut -d '"' -f4)
LogMessage "dbg" "boundStreamId: $boundStreamId"

# Make sure the boundStreamId is not empty.
if test -z "$boundStreamId"
then
    LogMessage "err" "The variable boundStreamId came up empty. Error accessing YouTube API"
    LogMessage "err" "The liveBroadcastOutput was $( echo $liveBroadcastOutput | tr '\n' ' ' )"

    exit 1
fi

# Extract the broadcastId (in this case I think it's the video ID, in other
# words, the URL of the individual YouTube video) which is needed in the Json
# structure of the cuepoint resource, so it knows which video in which to
# insert the new cuepoint.
broadcastId=""
broadcastId=$(echo $liveBroadcastOutput | sed 's/"id"/\'$'\n&/g' | grep -m 1 "id" | cut -d '"' -f4)
LogMessage "dbg" "broadcastId: $broadcastId"

# Make sure the broadcastId is not empty.
if test -z "$broadcastId"
then
    LogMessage "err" "The variable broadcastId came up empty. Error accessing YouTube API"
    LogMessage "err" "The liveBroadcastOutput was $( echo $liveBroadcastOutput | tr '\n' ' ' )"

    exit 1
fi

# Extract the channelId which is needed in the JSON structure as well.
channelId=""
channelId=$(echo $liveBroadcastOutput | sed 's/"channelId"/\'$'\n&/g' | grep -m 1 "channelId" | cut -d '"' -f4)
LogMessage "dbg" "channelId: $channelId"

# Make sure the channelId is not empty.
if test -z "$channelId"
then
    LogMessage "err" "The variable channelId came up empty. Error accessing YouTube API"
    LogMessage "err" "The liveBroadcastOutput was $( echo $liveBroadcastOutput | tr '\n' ' ' )"

    exit 1
fi


# WORK IN PROGRESS - TODO: Find out how to trigger this from the Synology API.
# An example might be to have this script get auto-run every time that Synology
# detects a motion event, and then give it some hysteresis (if that is even
# possible in the Synology system). Or regularly query the Synology API for
# recent motion events.


# Generate the date/time for the wall clock time for the cuepoint.
# WORK IN PROGRESS - THIS CURRENTLY INSERTS THE CURRENT CLOCK TIME.
# This might need to be different later.
cuePointWallTime=$(date -u +"%FT%T.000Z")
LogMessage "dbg" "cuePointWallTime: $cuePointWallTime"

# Build strings for writing the cuepoint to the video ID. A full JSON for a
# cuepoint will look like this, but only some of these fields are used in this
# implementation. 
# More details at https://developers.google.com/youtube/v3/live/docs/liveCuepoints
# and at https://developers.google.com/youtube/v3/live/docs/liveCuepoints/insert
#     {
#       "id": string,   
#       "kind": "youtubePartner#liveCuepoint",
#       "broadcastId": string,
#       "settings":
#       {
#         "offsetTimeMs": long,
#         "walltime": datetime,
#         "cueType": string,
#         "durationSecs": unsigned integer
#       }
#    }

curlUrl="https://www.googleapis.com/youtube/partner/v1/liveCuepoints?part=id,status&broadcastType=persistent&mine=true&access_token=$accessToken"
curlData=""
curlData+="{"
curlData+="\"broadcastId\": \"$broadcastId\","
curlData+="\"settings\": "
  curlData+="{"
    curlData+="\"cueType\": \"ad\""
    curlData+="\"walltime\": \"$cuePointWallTime\""
  curlData+="}"
curlData+="}"

# Do not log strings which contain credentials or access tokens, even in debug mode.
# LogMessage "dbg" "curlUrl: $curlUrl"
# LogMessage "dbg" "curlData: $curlData"


# Perform the API call to add the cuePoint.
# cuePointInsertionOutput=$( curl -s -m 20 -X POST -H "Content-Type: application/json" -d "$curlData" $curlUrl )
cuePointInsertionOutput=$( curl -s -m 20 -H "Content-Type: application/json" -d "$curlData" $curlUrl )
LogMessage "dbg" "Response from attempting to add the cuepoint: $cuePointInsertionOutput"

# WORK IN PROGRESS - The code above results in the error message:
# "Insufficient Permission: Request had insufficient authentication scopes."
#
# https://developers.google.com/youtube/v3/live/docs/liveCuepoints says that
# "The API command for controlling cuepoints is actually part of the YouTube
# Content ID API and has different authorization requirements than requests
# to manage liveBroadcast and liveStream resources.".
#
# The code in CrowCamCleanupPreparation.sh authorizes us for
# scope=https://www.googleapis.com/auth/youtube&response_type=code" and I
# need to investigate if the cuepoints will require a separate OAuth key or if
# there is a way to add it to the existing key.

exit 0



