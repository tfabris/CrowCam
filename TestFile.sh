#!/bin/bash

#------------------------------------------------------------------------------
# TestFile.sh - A script for experimenting with CrowCam features and API calls.
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


# ----------------------------------------------------------------------------
# Startup configuration variables 
# ----------------------------------------------------------------------------

# Configure debug mode for testing this script. Set this value to blank "" for
# running in the final functional mode on the Synology Task Scheduler.
debugMode=""         # True final runtime mode for Synology.
# debugMode="Synology" # Test on Synology SSH prompt, console or redirect output.
# debugMode="MacHome"  # Test on Mac at home, LAN connection to Synology.
debugMode="MacAway"  # Test on Mac away from home, no connection to Synology.
# debugMode="WinAway"  # In the jungle, the mighty jungle.

# Program name used in log messages.
programname="CrowCam Test File"

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

# Filenames for data files this program reads or writes.
videoData="crowcam-videodata"
videoRealTimestamps="crowcam-realtimestamps"



# ----------------------------------------------------------------------------
# Main Script Code Body
# ----------------------------------------------------------------------------

# Log the current test mode state, if activated.
if [ ! -z "$debugMode" ]
then
  LogMessage "err" "------------- Script $programname is running in debug mode: $debugMode -------------"
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


# ----------------------------------------------------------------------------
# Test: Validate new time comparison function.
# ----------------------------------------------------------------------------

videoIds=(
          "IDmfSWhAST0" # Live in progress video at the time I ran the test.
          "waE1oHY2S-8" # Yesterday's afternoon video at the time I ran the test.
          "mscSq9g5uKQ" # Yesterday's morning video at the time I ran the test.
          "vyFp5-eQChY" # Day before yesterday, afternoon, at the time I ran the test.
          "GshDu58Y7aE" # Day before yesterday, morning, at the time I ran the test.
          "1C9UhZiPaQk" # uploaded video - "slug on camera...".
          "-k9E41Xtv5s" # Video ID with hyphen - "Three squirrels..."
          "feA8mkTI1-s" # Deleted video
          "HzcqJp0AqDU" # Regular video - "Much drama..."
          "fN8Xj7PkUHY" # Regular video - "Crow family..."
          "ptOU01miz7s" # Regular video - "Infrared squirrel..."
          "_LrYCdxnE7A" # Regular video - "Squirrel lays a hand on..."
          "tGEHJvDEX-8" # Uploaded video - "Raccoon climbs up..."
          )
for ((i = 0; i < ${#videoIds[@]}; i++))
do
    oneVideoId=${videoIds[$i]}

    # Test reading an item from the cache. The GetRealTimes function will read
    # the data from the YouTube API if there is a cache miss.
    timeResponseString=""
    timeResponseString=$( GetRealTimes "$oneVideoId" )

    # Place the cache responses into variables, test making sure this works.
    read -r oneVideoId actualStartTime actualEndTime <<< "$timeResponseString"

    # Get return value from the tested function.
    isItOld=$( IsOlderThan $actualStartTime 1 )

    # Display the output of the variable.
    LogMessage "dbg" "isItOld:  $isItOld  $actualStartTime  $oneVideoId"
done

exit 0


# ----------------------------------------------------------------------------
# Test: Validate the caching code for actualStartTime/actualEndTime.
# ----------------------------------------------------------------------------

videoIds=(
          "1C9UhZiPaQk" # uploaded video - "slug on camera...".
          "-k9E41Xtv5s" # Video ID with hyphen - "Three squirrels..."
          "feA8mkTI1-s" # Deleted video
          "HzcqJp0AqDU" # Regular video - "Much drama..."
          "fN8Xj7PkUHY" # Regular video - "Crow family..."
          "ptOU01miz7s" # Regular video - "Infrared squirrel..."
          "_LrYCdxnE7A" # Regular video - "Squirrel lays a hand on..."
          "tGEHJvDEX-8" # Uploaded video - "Raccoon climbs up..."
          )
for ((i = 0; i < ${#videoIds[@]}; i++))
do
    oneVideoId=${videoIds[$i]}

    # Test reading an item from the cache. The GetRealTimes function will read
    # the data from the YouTube API if there is a cache miss.
    timeResponseString=""
    timeResponseString=$( GetRealTimes "$oneVideoId" )
    LogMessage "dbg" "Response: $oneVideoId: $timeResponseString"

    # Place the cache responses into variables, test making sure this works.
    read -r oneVideoId actualStartTime actualEndTime <<< "$timeResponseString"

    # Display the output of the variables (compare with string response above).
    LogMessage "dbg" "Values:   $oneVideoId              $actualStartTime $actualEndTime"
done

exit 0


# ----------------------------------------------------------------------------
# Test: Validate the cache cleaning code for actualStartTime/actualEndTime.
# ----------------------------------------------------------------------------

videoIds=(
          "1C9UhZiPaQk" # uploaded video - "slug on camera...".
          "feA8mkTI1-s" # Deleted video
          )

# Pause the program before testing the cache cleaning features.
read -n1 -r -p "Press space to clean the cache..." key

# Loop through each item in the test list and clean the cache.
for ((i = 0; i < ${#videoIds[@]}; i++))
do
    # Break out of the loop early to make sure it's partially deleting,
    # as expected. Comment out this section to prune all entries in the test.
    if [ "$i" -gt "3" ]
    then
        break
    fi
    
    # Perform the cache item deletion.
    oneVideoId=${videoIds[$i]}
    DeleteRealTimes "$oneVideoId"
done

exit 0


# ----------------------------------------------------------------------------
# Test: Query recordingDate as well as actualStartTime
# ----------------------------------------------------------------------------

videoIds=(
          "1C9UhZiPaQk" # uploaded video - "slug on camera...".
          "-k9E41Xtv5s" # Video ID with hyphen - "Three squirrels..."
          )
for ((i = 0; i < ${#videoIds[@]}; i++))
do
    LogMessage "dbg" "--------------------------------------------------"
    oneVideoId=${videoIds[$i]}

    curlUrl="https://www.googleapis.com/youtube/v3/videos?part=liveStreamingDetails,recordingDetails&id=$oneVideoId&access_token=$accessToken"
    liveStreamingDetailsOutput=""
    liveStreamingDetailsOutput=$( curl -s $curlUrl )
    
    # Debugging output.
    LogMessage "dbg" "Live streaming details output information: $liveStreamingDetailsOutput"      

    # Parse the actual times out of the details output.
    actualStartTime=""
    actualStartTime=$(echo $liveStreamingDetailsOutput | sed 's/"actualStartTime"/\'$'\n&/g' | grep -m 1 "actualStartTime" | cut -d '"' -f4)
    actualEndTime=""
    actualEndTime=$(echo $liveStreamingDetailsOutput | sed 's/"actualEndTime"/\'$'\n&/g' | grep -m 1 "actualEndTime" | cut -d '"' -f4)
    recordingDate=""
    recordingDate=$(echo $liveStreamingDetailsOutput | sed 's/"recordingDate"/\'$'\n&/g' | grep -m 1 "recordingDate" | cut -d '"' -f4)

    # Display the output of the variables .
    LogMessage "dbg" "Values: oneVideoId: $oneVideoId - actualStartTime: $actualStartTime - actualEndTime: $actualEndTime - recordingDate: $recordingDate"
    LogMessage "dbg" "--------------------------------------------------"
done

exit 0


# ----------------------------------------------------------------------------
# Test: Attempt to write recordingDate value with a detailed timestamp,
# instead of just the date and 00:00.000z for time (which is what you get
# if you update the recordingDate in the GUI). Answer: Doesn't work! This code
# succeeds and writes the value, however, only the date gets updated, the time
# remains stuck at 00:00.000z after the update. Also note: the values
# actualStartTime and actualEndTime are not available to be written to, so
# that is also out of the question.
# ----------------------------------------------------------------------------

videoIds=( "1C9UhZiPaQk" )
for ((i = 0; i < ${#videoIds[@]}; i++))
do
    LogMessage "dbg" "--------------------------------------------------"
    oneVideoId=${videoIds[$i]}
    valueToWrite="2019-07-10T14:22:34.000Z"
    
      curlData=""
      curlData+="{"
        curlData+="\"id\": \"$oneVideoId\","
        curlData+="\"recordingDetails\": "
          curlData+="{"
            curlData+="\"recordingDate\": \"$valueToWrite\""
          curlData+="}"
      curlData+="}"
    
    curlUrl="https://www.googleapis.com/youtube/v3/videos?part=liveStreamingDetails,recordingDetails&id=$oneVideoId&access_token=$accessToken"
    liveStreamingDetailsOutput=""
    liveStreamingDetailsOutput=$( curl -s -m 20 -X PUT -H "Content-Type: application/json" -d "$curlData" $curlUrl )
    
    # Debugging output.
    LogMessage "dbg" "Live streaming details output information: $liveStreamingDetailsOutput"      

    # Parse the actual times out of the details output.
    actualStartTime=""
    actualStartTime=$(echo $liveStreamingDetailsOutput | sed 's/"actualStartTime"/\'$'\n&/g' | grep -m 1 "actualStartTime" | cut -d '"' -f4)
    actualEndTime=""
    actualEndTime=$(echo $liveStreamingDetailsOutput | sed 's/"actualEndTime"/\'$'\n&/g' | grep -m 1 "actualEndTime" | cut -d '"' -f4)
    recordingDate=""
    recordingDate=$(echo $liveStreamingDetailsOutput | sed 's/"recordingDate"/\'$'\n&/g' | grep -m 1 "recordingDate" | cut -d '"' -f4)

    # Display the output of the variables .
    LogMessage "dbg" "Values: oneVideoId: $oneVideoId - actualStartTime: $actualStartTime - actualEndTime: $actualEndTime - recordingDate: $recordingDate"
    LogMessage "dbg" "--------------------------------------------------"
done

exit 0


# ----------------------------------------------------------------------------
# Test: Deletion of playlist items.
# ----------------------------------------------------------------------------

playlistItemIds=( "UExxaS1McjFoUEJPVXVCZ012c0RNWTJLM2lVZzZuQlpBVi4zMDg5MkQ5MEVDMEM1NTg2" "UExxaS1McjFoUEJPVXVCZ012c0RNWTJLM2lVZzZuQlpBVi41Mzk2QTAxMTkzNDk4MDhF" "UExxaS1McjFoUEJPVXVCZ012c0RNWTJLM2lVZzZuQlpBVi5EQUE1NTFDRjcwMDg0NEMz" "UExxaS1McjFoUEJPVXVCZ012c0RNWTJLM2lVZzZuQlpBVi4yMUQyQTQzMjRDNzMyQTMy" )
for ((i = 0; i < ${#playlistItemIds[@]}; i++))
do
    onePlaylistItemsId=${playlistItemIds[$i]}

    deletePlaylistItemOutput=""
    curlFullPlaylistItemString="curl -s --request DELETE https://www.googleapis.com/youtube/v3/playlistItems?id=$onePlaylistItemsId&access_token=$accessToken"

    LogMessage "dbg" "curlFullPlaylistItemString will be: $curlFullPlaylistItemString"

    deletePlaylistItemOutput=$( $curlFullPlaylistItemString )
    LogMessage "dbg" "Curl deletePlaylistItemOutput was: $deletePlaylistItemOutput"
done

exit 0
