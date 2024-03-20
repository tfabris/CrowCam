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
# debugMode="MacAway"  # Test on Mac away from home, no connection to Synology.
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

# Get Synology NAS API creds out of the external file, assert values are non-blank.
# TO DO: Learn the correct linux-supported method for storing and retrieving a
# username and password in an encrypted way.
read username password < "$apicreds"
if [ -z "$username" ] || [ -z "$password" ]
then
  LogMessage "err" "Problem obtaining Synology API credentials from external file"
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
# Test: Create new stream using the new code that I added for issue #69.
# ----------------------------------------------------------------------------
CreateNewStream
exit 0



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


# ----------------------------------------------------------------------------
# Utility: Copy archive video links from my old channel to my new channel
# ----------------------------------------------------------------------------
# Existing set of archived videos, up until 2020, are all stored in the 
# "Vixy & Tony" YouTube channel. But in 2024, I'm moving things to the new
# "CrowCam" channel. I want to have that playlist of older archives all moved
# to the new location too. I could have downloaded and re-uploaded every
# video, but that would have been onerous. Instead I will leave those old
# videos over in the Vixy & Tony channel and just in a hidden "CrowCam
# Archives" playlist. And then link them in the CrowCam channel in the
# new "CrowCam Archives" playlist in that channel.
#
# I already happened to have the list of the videos in my crowcam-videodata
# file, so pull that list of videos in the crowcam-videodata file and poke
# those into the new playlist with the YouTube API.
#
# Old "CrowCam Archives" playlist in Vixy & Tony:     
# https://www.youtube.com/playlist?list=PLqi-Lr1hPBOUuBgMvsDMY2K3iUg6nBZAV
#
# New "CrowCam Archives" playlist in CrowCam:
# https://www.youtube.com/playlist?list=PL8Fzg-YTf-GbfOHNxAAZEW9dixstuSztl
#

# Put the new playlist ID into a varaible.
newPlaylistId="PL8Fzg-YTf-GbfOHNxAAZEW9dixstuSztl"

# Parse out all of the titles, video IDs, and start times from my
# crowcam-videodata file. Regex string looks like this:
#    "(title|videoId|actualStartTime)": "([^"])*"
# Which means:
#    "          Find a quote
#    (          Find one of these things in this group
#    title      Find the word title
#    |videoId   or the word videoId
#    |actual... or the word actualStartTime
#    )          Close up that group of things
#    ": "       Find a quote, a colon, a space, and a quote
#    (          Find the things in in this group
#    [^"]       Find anything that's NOT a quote
#    )          Close up that group of things
#    *          Find any number of instances of that group in a row (characters that aren't quotes)
#    "          Find a quote
#
# The returns three strings from each entry in that file that look like this, in
# this order:
#
#    "title": "7:28 am - Juvenile crow begs from parent quite intensely"
#    "videoId": "1Y9BFUyzpys"
#    "actualStartTime": "2020-09-01T13:50:13Z"
#
# I'm actually only needing the "videoId" from these, but, I wanted to see if
# each one was being retrieved correctly and in the right order, and to have
# something readable to display to the user.
#
# Special notes about this code which greps the contents of the crowcam-videodata file:
# - Grep commands: -o only matching text returned, -h hide filenames, -E extended regex
# - arrayName=( ):  Make sure to have the outer parentheses to make it a true array.
# - IFS_backup=$IFS; IFS=$'\n': IFS is the way it splits the resulting array. Normally it
#   splits on space/tab/linefeed, I'm changing it to just split on linefeed so that each
#   return value from the regex grep is its own array element.
IFS_backup=$IFS
IFS=$'\n'
videoDataArray=( $(grep -o -h -E '"(title|videoId|actualStartTime)": "([^"])*"' $videoData) )
IFS=$IFS_backup

# Syntax note: the pound sign retrieves the count/size of the array.
videoDataArrayCount=${#videoDataArray[@]}  

# Flag to indicate whether it's OK to process the video or not in the loop.
# There is a special case where I might not want to process the entire contents
# of the loop, this would be when I busted an API quota and only got about 2/3
# of the way through the list. This flag will be updated later inside the loop.
okToProcessVideo=false

# Process all items
loopIndex=0
videosProcessed=0
while [ $loopIndex -lt $videoDataArrayCount ]   
do
    # Freshen variables at the start of each loop
    currentTitle=""
    currentvideoId=""
    currentActualStartTime=""

    # Record the first of the three items, the title
    oneVideoDataItem=${videoDataArray[loopIndex]}
    currentTitle=$( echo $oneVideoDataItem | cut -d '"' -f4 )

  ((loopIndex++))

    # Record the second item, is the video ID
    oneVideoDataItem=${videoDataArray[loopIndex]}
    currentvideoId=$( echo $oneVideoDataItem | cut -d '"' -f4 )

  ((loopIndex++))

    # Record third item, the start time
    oneVideoDataItem=${videoDataArray[loopIndex]}
    currentActualStartTime=$( echo $oneVideoDataItem | cut -d '"' -f4 )

  ((loopIndex++))  # Update this value after logging, so the number is still correct.

    # Check to see if we are supposed to hold off on processing a video
    # until we reach a certain point. For example, I busted my API quota
    # the first time I was able to run this script full successfully.
    # 2024-03-14 - I hit my API quota at the video here in the list:
    # Successfully processed:
    #     nPz8DggbVOE 2019-06-06T20:13:08.000Z 1:54 pm Crow caws on platform, crowfuffle. 1:57 pm closeup crowfuffle.
    # Failed to process (and everything after that):
    #     rm8DWNGR5Wc 2019-06-06T12:00:17.000Z 11:06 am Crow intimidates badass squirrel. 11:23 am Crows scold raccoon..

    if [ "$currentvideoId" == "rm8DWNGR5Wc" ]
    then
      okToProcessVideo=true  # Set to True for the remainder of the l
    fi 

    # Check to see if it is OK to process the video before doing the actual processing.
    if $okToProcessVideo
    then
      # Now fully process the results. Begin by logging the data we're working on.
      LogMessage "dbg" "Processing: $loopIndex $currentvideoId $currentActualStartTime $currentTitle"

      # Build the data blob that we are sending to the YouTube API. It must
      # contain certain very specific things in order to be processed correctly.
      # Details here: https://stackoverflow.com/a/20652371/3621748
      curlUrl="https://www.googleapis.com/youtube/v3/playlistItems?part=id,snippet,status&mine=true&access_token=$accessToken"
      curlData=""
      curlData+="{"
       curlData+="\"snippet\": "
       curlData+="{"
         curlData+="\"playlistId\": \"$newPlaylistId\","
         curlData+="\"resourceId\": "
         curlData+="{"
           curlData+="\"kind\": \"youtube#video\","
           curlData+="\"videoId\": \"$currentvideoId\""
         curlData+="}"
       curlData+="}"
      curlData+="}"

      # Dev output 
      # LogMessage "dbg" "Curl URL: $curlUrl"
      # LogMessage "dbg" "Curl data: $curlData"

      # Don't actually do it if this script is in debug mode.
      if [ ! -z "$debugMode" ]
      then
        LogMessage "err" "Debug mode: Not actually adding a video to the playlist"
      else
        # Use the YouTube API to insert that video into the playlist. NOTE: Must be
        # POST instead of PUT in this case, because the documentation says that PUT
        # is an "update" command for YouTube, and POST is an "insert" command for
        # YouTube. According to the docs, adding and item to a playlist is
        # an "insert".
        insertVideoResults=$( curl -s -m 20 -X POST -H "Content-Type: application/json" -d "$curlData" $curlUrl )

        # Check the response for errors.
        if [ -z "$insertVideoResults" ] || [[ $insertVideoResults == *"\"error\":"* ]] 
        then
         LogMessage "err" "The API returned an error when trying to insert a video: $insertVideoResults"
         exit 1
        fi
      fi
      ((videosProcessed++))
    else
      LogMessage "dbg" "SKIPPING:   $loopIndex $currentvideoId $currentActualStartTime $currentTitle"
    fi

done
LogMessage "dbg" "Processed $videosProcessed videos from $videoDataArrayCount data items"

exit 0
