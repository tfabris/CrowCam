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
# debugMode="MacHome"  # Test on Mac at home, LAN connection to Synology.
# debugMode="MacAway"  # Test on Mac away from home, no connection to Synology.
debugMode="WinAway"  # In the jungle, the mighty jungle.

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



