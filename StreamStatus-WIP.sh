#!/bin/bash

# ----------------------------------------------------------------------------
# WORK IN PROGRESS CODE - DO NOT USE
# ----------------------------------------------------------------------------


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


# ----------------------------------------------------------------------------
# Startup configuration variables 
# ----------------------------------------------------------------------------

# Configure debug mode for testing this script. Set this value to blank "" for
# running in the final functional mode on the Synology Task Scheduler.
debugMode=""         # True final runtime mode for Synology.
# debugMode="Synology" # Test on Synology SSH prompt, console or redirect output.
# debugMode="MacHome"  # Test on Mac at home, LAN connection to Synology.
# debugMode="MacAway"  # Test on Mac away from home, no connection to Synology.
debugMode="WinAway"  # In the jungle, the mighty jungle.

# Program name used in log messages.
programname="WIP - DO NOT USE"

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
# Main program code body.
#------------------------------------------------------------------------------

# Log the current test mode state, if activated.
if [ ! -z "$debugMode" ]
then
  logMessage "err" "------------- Script $programname is running in debug mode: $debugMode -------------"
fi

# Debugging message for logging script start/stop times. Leave commented out.
# logMessage "info" "-------------------------- Starting script: $programname -------------------------"

# Log current script location and working directory.
logMessage "dbg" "Script exists in directory: $DIR"
logMessage "dbg" "Current working directory:  $(pwd)"


# Verify that the necessary external files exist.
if [ ! -e "$clientIdJson" ]
then
  logMessage "err" "Missing file $clientIdJson"
  exit 1
fi
if [ ! -e "$crowcamTokens" ]
then
  logMessage "err" "Missing file $crowcamTokens"
  exit 1
fi
if [ ! -e "$apicreds" ]
then
  logMessage "err" "Missing file $apicreds"
  exit 1
fi
if [ ! -e "$executable" ]
then
  logMessage "err" "Missing file $executable"
  exit 1
fi



#------------------------------------------------------------------------------
# Experimental code to see if we can get useful stream status information.
# Attempting to work on issues #23 and #26.
#------------------------------------------------------------------------------

# Global variable for keeping track of whether the stream is working correctly.
streamIsWorkingCorrectly=true

# Authenticate with the YouTube API and receive the Access Token which allows
# us to make YouTube API calls. Retrieves the $accessToken variable.
YouTubeApiAuth

# Make sure the Access Token is not empty. Part of the fix for issue #28, do
# not exit the program if the access token fails, just keep rolling.
if test -z "$accessToken" 
then
  # An error message will have already been printed about the access token at
  # this point, no need to do anything other than flag the issue for later.
  streamIsWorkingCorrectly=false
fi

# Get the current live broadcast information details as a prelude to obtaining
# the live stream details. Details of the items in the response are found here:
# https://developers.google.com/youtube/v3/live/docs/liveBroadcasts#resource
curlUrl="https://www.googleapis.com/youtube/v3/liveBroadcasts?part=contentDetails&broadcastType=persistent&mine=true&access_token=$accessToken"
liveBroadcastOutput=""
liveBroadcastOutput=$( curl -s -m 20 $curlUrl )

# Extract the boundStreamId which is needed in order to find other information.
boundStreamId=""
boundStreamId=$(echo $liveBroadcastOutput | sed 's/"boundStreamId"/\'$'\n&/g' | grep -m 1 "boundStreamId" | cut -d '"' -f4)
logMessage "dbg" "boundStreamId: $boundStreamId"

# Make sure the boundStreamId is not empty.
if test -z "$boundStreamId" 
then
  logMessage "err" "The variable boundStreamId came up empty. Error accessing YouTube API"
  logMessage "err" "The liveBroadcastOutput was $( echo $liveBroadcastOutput | tr '\n' ' ' )"
  streamIsWorkingCorrectly=false
else
  # Obtain the liveStreams status details and look at the resource results in
  # the response. Details of the various items in the response are found here:
  # https://developers.google.com/youtube/v3/live/docs/liveStreams#resource
  curlUrl="https://www.googleapis.com/youtube/v3/liveStreams?part=status&id=$boundStreamId&access_token=$accessToken"
  liveStreamsOutput=""
  liveStreamsOutput=$( curl -s -m 20 $curlUrl )

  # Debugging output.
  logMessage "dbg" "Live Streams output response:"
  logMessage "dbg" "---------------------------------------------------------- $liveStreamsOutput"
  logMessage "dbg" "----------------------------------------------------------"

  # Get "streamStatus" from the results. Looking for the field "active" in
  # these results:
  #           "status": {
  #            "streamStatus": "active",
  #            "healthStatus": {
  #             "status": "ok",
  # Possible expected values should be:
  #     active – The stream is in active state which means the user is receiving data via the stream.
  #     created – The stream has been created but does not have valid CDN settings.
  #     error – An error condition exists on the stream.
  #     inactive – The stream is in inactive state which means the user is not receiving data via the stream.
  #     ready – The stream has valid CDN settings.
  streamStatus=""
  streamStatus=$(echo $liveStreamsOutput | sed 's/"streamStatus"/\'$'\n&/g' | grep -m 1 "streamStatus" | cut -d '"' -f4)
  logMessage "dbg" "streamStatus: $streamStatus"
  
  # Make sure the streamStatus is not empty.
  if test -z "$streamStatus" 
  then
    logMessage "err" "The variable streamStatus came up empty. Error accessing YouTube API"
    streamIsWorkingCorrectly=false
  else
    # Stream status should be "active" if the stream is up and working. Any
    # other value means the stream is down at the current time.
    if [ "$streamStatus" != "active" ] 
    then
        logMessage "err" "The streamStatus is not active. Value retrieved was: $streamStatus"
        streamIsWorkingCorrectly=false
    fi
  fi

  # Extract the "status" field of the  "healthStatus" object, but that means
  # we're parsing for the second occurrence of the variable "status" in the
  # results. So the grep statement must be -m 2 instead of -m 1, so that it
  # returns two results, and then we have to "tail -1" to get only the last of
  # the two results. This works to tease out the "ok" from this text:
  #           "status": {
  #            "streamStatus": "active",
  #            "healthStatus": {
  #             "status": "ok",
  # Possible expected values should be:
  #    good – There are no configuration issues for which the severity is warning or worse.
  #    ok – There are no configuration issues for which the severity is error.
  #    bad – The stream has some issues for which the severity is error.
  #    noData – YouTube's live streaming backend servers do not have any information about the stream's health status.
  healthStatus=""
  healthStatus=$(echo $liveStreamsOutput | sed 's/"status"/\'$'\n&/g' | grep -m 2 "status" | tail -1 | cut -d '"' -f4 )
  logMessage "dbg" "healthStatus: $healthStatus"
  
  # Make sure the healthStatus is not empty.
  if test -z "$healthStatus" 
  then
    logMessage "err" "The variable healthStatus came up empty. Error accessing YouTube API"
    streamIsWorkingCorrectly=false
  else
    # Stream status should be "active" if the stream is up and working. Any
    # other value means the stream is down at the current time.
    if [ "$healthStatus" == "bad" ] || [ "$healthStatus" == "noData" ]
    then
        logMessage "err" "The healthStatus is not good. Value retrieved was: $healthStatus"
        streamIsWorkingCorrectly=false
    fi    
  fi
fi

# Example of the final test to see if the stream is really up or not.
if "$streamIsWorkingCorrectly" = true
then
    logMessage "dbg" "The stream is working correctly"
else
    logMessage "err" "ERROR: The stream is DOWN"
fi


exit 0

