#!/bin/bash

#------------------------------------------------------------------------------
# CrowCamCleanup.sh - A Bash script to clean out old YouTube stream archives.
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
# debugMode="WinAway"  # In the jungle, the mighty jungle.

# Program name used in log messages.
programname="CrowCam Cleanup"

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

# When in test mode, reduce the number of days of buffer so that we can see
# the code actually try to delete an old video. For example, the "real" code
# might be currently running and installed on the Synology, and now you're
# debugging changes to the code. In that case, the real code would likely have
# already completed its daily cleanup, so the test run of this script will
# have nothing to do. So we won't usually see a deletion occur during test
# mode, unless we shorten this number.)
if [ ! -z "$debugMode" ]
then
    # Double parentheses around the decrement command are required so that Bash
    # knows it is an arithmetic operation. Without the parens it doesn't work.
    ((dateBufferDays--)) 
    ((dateBufferDays--)) 
fi


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

# Get the channel information so that I can find the ID of the playlist.
curlUrl="https://www.googleapis.com/youtube/v3/channels?part=contentDetails,id&mine=true&access_token=$accessToken"
channelsOutput=""
channelsOutput=$( curl -s $curlUrl )

# Debugging output. Only needed if you run into a nasty bug here.
# Leave deactivated most of the time.
# LogMessage "dbg" "Channels output information: $channelsOutput"

# QUERY FOR DEFAULT PLAYLISTS ("uploads"):
# channelsOutput contains JSON which includes the line that looks like this:
#    "uploads": "UUqPZGFtBau8rm7wnScxdA3g",
# Parse out the uploads playlist ID string from that line. Some systems that I
# developed this on didn't have "jq" installed in them, so I am using commands
# which are more cross-platform compatible.
uploadsId=""
uploadsId=$(echo $channelsOutput | sed 's/"uploads"/\'$'\n&/g' | grep -m 1 "uploads" | cut -d '"' -f4)

# Make sure the uploadsId is not empty. Whether we use it or not, it should be
# obtained, and it indicates a query or parse error if it's not obtained.
if test -z "$uploadsId" 
then
    LogMessage "err" "The variable uploadsId came up empty. Error accessing API. Exiting program"
    LogMessage "err" "The channelsOutput was $( echo $channelsOutput | tr '\n' ' ' )"
    exit 1
fi

# User may choose, in the config file, to clean out their default "uploads"
# playlist, or to clean out one of their user-created playlists.
# Interestingly, I have to use a completely different set of queries to find
# the list of user-created playlists. It's much more complex than finding the
# uploads playlist.
if [ "$playlistToClean" = "uploads" ]
then
    # Simple - we have the uploads ID and we'll just use it. Assign it to our
    # target ID and skip the query for custom playlists.
    playlistTargetId="$uploadsId"
else
  # QUERY FOR USER-CREATED PLAYLISTS:
  # This outputs some JSON data which includes the Channel ID which I need, in
  # order to retrieve ALL the playlists in the next query. The "channels" list,
  # above, specifically its "&mine=true" parameter, gets all the default
  # playlists like "uploads", but does not include user-created playlists like
  # "CrowCam Archives". So parse the channelId out of the results.
  channelId=""
  channelId=$(echo $channelsOutput | sed 's/"id"/\'$'\n&/g' | grep -m 1 "id" | cut -d '"' -f4)

  # Make sure the channelId is not empty.
  if test -z "$channelId" 
  then
      LogMessage "err" "The variable channelId came up empty. Error accessing API. Exiting program"
      LogMessage "err" "The channelsOutput was $( echo $channelsOutput | tr '\n' ' ' )"
      exit 1
  fi

  # Query for a list of all playlists in the channel. This will include more
  # than just the default playlists.
  curlUrl="https://www.googleapis.com/youtube/v3/playlists?part=contentDetails,snippet&channelId=$channelId&access_token=$accessToken"
  playlistsOutput=""
  playlistsOutput=$( curl -s $curlUrl )

  # Debugging output. Only needed if you run into a nasty bug here.
  # Leave deactivated most of the time.
  # LogMessage "dbg" "Playlists output information: $playlistsOutput"

  # This outputs some JSON data which includes sections that looks like this
  # (several of these):
  #
  # "id": "PLqi-Lr1hPBOUuBgMvsDMY2K3iUg6nBZAV",
  #  "snippet": {
  #   "publishedAt": "2019-11-19T20:23:06.000Z",
  #   "channelId": "UCqPZGFtBau8rm7wnScxdA3g",
  #   "title": "CrowCam Archives",
  #   "description": "",
  #
  # Parse each of the "id" and "title" into lists, and then find the one ID the
  # list that matches the playlist title that we want.
  playlistIds=()
  playlistTitles=()

  # Loop through all of the lines in the JSON output and add the matching lines
  # to the arrays as we find them. This special syntax uses <<< to redirect
  # input into this loop at the end of the "do" statement down below.
  while IFS= read -r line
  do
      lineResult=$( echo $line | grep '"id"' | cut -d '"' -f4)
      if ! [ -z "$lineResult" ]
      then
        playlistIds+=( "$lineResult" )
      fi

      lineResult=$( echo $line | grep '"title"' | cut -d '"' -f4 )
      if ! [ -z "$lineResult" ]
      then
        # Special trick: There are two "title" entries in the full output,
        # they're the same title. I can't have them both in the list, since this
        # list has to match the IDs list 1:1. So check to see if the last entry
        # in the list is the same as the current entry, and don't add it if so.
        # Also only do the check if we are more than zero items into the array,
        # to prevent a "bad array subscript" error message.
        if [ "${#playlistTitles[@]}" -gt "0" ]
        then
          if ! [ "$lineResult" =  "${playlistTitles[ ${#playlistTitles[@]} - 1 ]}" ]
          then
            playlistTitles+=( "$lineResult" )
          fi
        else
          # If we're on item number 0 in the list then we automatically add it
          # without checking it first.
          playlistTitles+=( "$lineResult" )
        fi
      fi
  done <<< "$playlistsOutput"

  # Error out of the program if the count is zero.
  if [ "${#playlistIds[@]}" = "0" ]
  then
     LogMessage "err" "Error - Playlist count is zero, either there are no playlists in the channel or a parsing error has occurred"
     exit 1
  else
     LogMessage "dbg" "Playlist count is nonzero, continuing to process"
  fi

  # Log playlist counts.
  LogMessage "dbg" "${#playlistIds[@]} playlistIds, ${#playlistTitles[@]} playlistTitles found"

  # Error out of the program if playlist ID and Title counts do not match exactly.
  if [ "${#playlistIds[@]}" = "${#playlistTitles[@]}" ]
  then
     LogMessage "dbg" "Playlist counts are equal, continuing to process"
  else
     LogMessage "err" "Error - Data counts for playlists did not match. A parsing error has occurred"
     exit 1
  fi

  # Loop through and find the one playlist we want.
  playlistTargetId=""
  for ((i = 0; i < ${#playlistIds[@]}; i++))
  do
      # Debugging - Print the playlists as we go.
      LogMessage "dbg" "Found playlist: ${playlistIds[$i]} ${playlistTitles[$i]}"

      # Compare our desired playlist title that we want to clean, with the
      # playlist title in this loop. If they match, it's our thing!
      if [ "${playlistTitles[$i]}" = "$playlistToClean" ]
      then
          # Assign the located ID (same index number as the tile) to playlist ID
          # variable which will be used for querying all the items in that
          # playlist.
          playlistTargetId="${playlistIds[$i]}"
      fi
  done
fi

# Make sure the playlistTargetId is not empty.
if test -z "$playlistTargetId" 
then
    LogMessage "err" "The variable playlistTargetId came up empty. Error accessing API. Exiting program"
    LogMessage "err" "The playlistsOutput was $( echo $playlistsOutput | tr '\n' ' ' )"
    exit 1
fi

# Log the playlist ID that we found.
LogMessage "dbg" "Using playlist ID: $playlistTargetId Title: $playlistToClean"

# Bugfix for GitHub issue #51 - Implement pagination in the query. Start by
# initializing the variable which will be keeping track of the pagination.
nextPageToken=""

# Set/clear the variable which will hold the combined results of all loops
# which query multiple pages of the youtube channel's "My Uploads" playlist.
uploadsOutput=""

# Paginate through all pages of the youtube channel's saved videos. Set an
# upper limit of the number of pages. Originally the number of pages was
# limited to 3 pages to prevent Google quota overruns. However this code is
# now using a better method to retrieve the video details, and it no longer
# needs the strict limit because it's getting the job done with much fewer
# queries. So now the limit is set to 100 pages, which, at 50 videos each, is
# 5000 "kept" videos.
for (( c=1; c<=100; c++ ))
do
    # Create the base url for the Curl command to query the API for the videos
    # in the "My Uploads" playlist. NOTE: Must use maxResults=50 parameter
    # because the default number of search results is only 5 items, and we
    # want to get as many items per page as possible. 50/page is the max
    # allowed. Update: Query for "snippet" instead of "contentDetails" so that
    # we can get all video details without any later re-queries.
    curlUrl="https://www.googleapis.com/youtube/v3/playlistItems?playlistId=$playlistTargetId&maxResults=50&part=snippet&mine=true&access_token=$accessToken"

    # If a prior loop resulted in a "next page" pagination token, use it on
    # this loop. If the token is nonblank, then assume we got a page token on
    # the prior run, and use it. The first time through the loop, we will be
    # retrieving the first page, so it will always be blank, so the first
    # query will never contain this parameter. Subsequent queries may or may
    # not contain the parameter depending on how many videos are in the
    # playlist.
    if [ ! -z "$nextPageToken" ]
    then
        # If the prior loop's response contained a next page token, then 
        # concatenate the next page token into the command for this loop run.
        curlUrl="$curlUrl&pageToken=$nextPageToken"
    fi
    
    # Print the curl command we are about to use, in debug mode only.
    # LogMessage "dbg" "curl -s $curlUrl"   # Do not log strings which contain credentials or access tokens, even in debug mode.
    
    # Perform the API query with curl.
    LogMessage "dbg" "Querying YouTube API. Pagination: page $c"
    uploadsOneLoopOutput=""
    uploadsOneLoopOutput=$( curl -s $curlUrl )

    # Zero out the next page token for this loop, and then try to re-retrieve
    # it from the curl results. If this results in a nonblank string, then,
    # the string will be the next page token for the next loop. 
    nextPageToken=""
    nextPageToken=$(echo $uploadsOneLoopOutput | sed 's/"nextPageToken"/\'$'\n&/g' | grep "nextPageToken" | cut -d '"' -f4)
    
    # Concatenate the current loop's output with all the prior loops' output.
    # This will be used later, to scan for all of the videos in the entire
    # set of all queries together.
    uploadsOutput="$uploadsOutput $uploadsOneLoopOutput"

    # If the next page token is blank, it means we have reached the last page
    # and can exit the loop.
    if [ -z "$nextPageToken" ]
    then
        # We have reached the last page, exit the paginiation loop.
        break
    fi

    # Also exit the loop if we are in debug mode - Only process the first page
    # when we're in debug mode, to speed it up.
    #
    # Actually, don't skip the loop in debug mode for the moment. I recently
    # found myself in a debug situation where I needed all the pages. Uncomment
    # this when you run into a situation where you need faster debugging.
    #        if [ ! -z "$debugMode" ]
    #        then
    #           # Exit the pagination loop when we are debugging.
    #            break
    #        fi
done

# Log the output results. Not usually needed. Leave deactivated usually.
# echo " "
# echo  "Output from the query of the Uploads playlist:"
# echo  $uploadsOutput | sed 's/"videoId"/\'$'\n&/g' | grep "videoId"
# echo " "

# Begin parsing the video data out of the JSON results. Log our intentions.
LogMessage "dbg" "Retrieving playlistItemIds, titles, and videoIds from the JSON results"

# Set up empty arrays to hold the video details. These arrays will build the
# video details list in order, so the arrays will have the same ordering.
playlistItemIds=()
titles=()
videoIds=()

# GitHub Issue #72 - Improve the speed of parsing the results by grepping the
# entire JSON dataset in one statement, rather than trying to iterate through
# the JSON line-by-line.
# 
# NEW METHOD:
# Parse out all of the titles, video IDs, and start times from the video data
# Regex string looks like this:
#    "(id|title|videoId)": "([^"])*"
# Which means:
#    "                                 Find a quote
#     (                                Find one of these things in this group
#      id                              Find the word id
#        |title                        or the word title
#              |videoId                or the word videoId
#                      )               Close up that group of things
#                       ": "           Find a quote, a colon, a space, and a quote
#                           (          Find the things in in this group
#                            [^"]      Find anything that's NOT a quote
#                                )     Close up that group of things
#                                 *    Find any number of instances of that group
#                                  "   Find a quote
#
# The returns three strings from each entry in the JSON that look like this, in
# this order:
#
#    "id": "UEw4RnpnLVlUZi1HYmZPSE54QUFaRVc5ZGl4c3R1U3p0bC41NkI0NEY2RDEwNTU3Q0M2"
#    "title": "7:28 am - Juvenile crow begs from parent quite intensely"
#    "videoId": "1Y9BFUyzpys"
#
# Special notes about this code which greps the data:
# - Grep commands: -o only matching text returned, -h hide filenames, -E extended regex
# - arrayName=( ):  Make sure to have the outer parentheses to make it a true array.
# - IFS_backup=$IFS; IFS=$'\n': IFS is the way it splits the resulting array. Normally it
#   splits on space/tab/linefeed, I'm changing it to just split on linefeed so that each
#   return value from the regex grep is its own array element.
IFS_backup=$IFS
IFS=$'\n'
videoDataArray=( $(echo $uploadsOutput | grep -o -h -E '"(id|title|videoId)": "([^"])*"') )
IFS=$IFS_backup

# Syntax note: the pound sign retrieves the count/size of the array.
videoDataArrayCount=${#videoDataArray[@]}  
LogMessage "dbg" "videoDataArrayCount: $videoDataArrayCount"

# Process all items
LogMessage "dbg" "Looping through videoDataArray to get three final arrays"
loopIndex=0
while [ $loopIndex -lt $videoDataArrayCount ]   
do
    # Freshen variables at the start of each loop
    currentId=""
    currentTitle=""
    currentvideoId=""

    # Record first item, the playlist item ID
    oneVideoDataItem=${videoDataArray[loopIndex]}
    currentId=$( echo $oneVideoDataItem | cut -d '"' -f4 )
    if ! [ -z "$currentId" ]
    then
      playlistItemIds+=( "$currentId" )
    fi

  ((loopIndex++))  

    # Record the second item, the title
    oneVideoDataItem=${videoDataArray[loopIndex]}
    currentTitle=$( echo $oneVideoDataItem | cut -d '"' -f4 )
    if ! [ -z "$currentTitle" ]
    then
      titles+=( "$currentTitle" )
    fi

  ((loopIndex++))

    # Record the third item, the video ID
    oneVideoDataItem=${videoDataArray[loopIndex]}
    currentvideoId=$( echo $oneVideoDataItem | cut -d '"' -f4 )
    if ! [ -z "$currentvideoId" ]
    then
      videoIds+=( "$currentvideoId" )
    fi

  ((loopIndex++))
done

# GitHub issue #87 - Only log debug mode here. Final log is after processing is
# fully done, and only in certain situations (no longer basing the log on the
# time hour any more.)
#     # Log the number of videos found. But only log this late at night. All the
#     # extra logs fill up the Synology log too much, too much noise. But I want to
#     # know if it's working in general, so I want a log sometimes. I compromise by
#     # printing it to the Synology log only during the midnight and 7pm hours.
#     currentHour=$( date +"%H" )
#     if [ "$currentHour" = "00" ] || [ "$currentHour" = "19" ]
#     then
#         LogMessage "info" "Total: ${#playlistItemIds[@]} playlistItemIds, ${#videoIds[@]} videoIds, ${#titles[@]} titles found. Processing"
#     else
#         LogMessage "dbg" "Total: ${#playlistItemIds[@]} playlistItemIds, ${#videoIds[@]} videoIds, ${#titles[@]} titles found. Processing"
#     fi
LogMessage "dbg" "Total: ${#playlistItemIds[@]} playlistItemIds, ${#videoIds[@]} videoIds, ${#titles[@]} titles found. Processing"

# Error out of the program if the count is zero.
if [ "${#videoIds[@]}" = "0" ]
then
   LogMessage "err" "Error - Video count is zero, either there are no videos in the channel or a parsing error has occurred"
   exit 1
else
   LogMessage "dbg" "Count is nonzero, continuing to process"
fi

# Error out of the program if all numbers do not match exactly.
if [ "${#videoIds[@]}" = "${#titles[@]}" ] && [ "${#titles[@]}" = "${#playlistItemIds[@]}" ];
then
   LogMessage "dbg" "All counts are equal, continuing to process"
else
   LogMessage "err" "Error - Data counts for video details did not match. A parsing error has occurred"
   exit 1
fi
# Debugging - Print the array. No need to do this unless you encounter
# some kind of nasty unexpected bug. Leave this commented out usually.
# for ((i = 0; i < ${#videoIds[@]}; i++))
# do
#     echo "${playlistItemIds[$i]} ${videoIds[$i]} ${titles[$i]}"
# done
# LogMessage "dbg" "${#playlistItemIds[@]} playlistItemIds, ${#videoIds[@]} videoIds, ${#titles[@]} titles found. Processing"

# GitHub issue #87 - Set a flag which indicates whether we should log some of
# our actions to the Synology ("info" level instead of "dbg" level). Start
# with the flag set to false, and set to true if a condition comes up which
# would be worth logging.
logToSynology=false

# Iterate through the array and delete any old videos which have not been renamed.
for ((i = 0; i < ${#videoIds[@]}; i++))
do
    # Set the current loop's data to easier-to-read variables.
    oneVideoTitle=${titles[$i]}
    oneVideoId=${videoIds[$i]}
    onePlaylistItemId=${playlistItemIds[$i]}

    # Throw an error if any of the values are blank.
    if test -z "$oneVideoTitle" 
    then
        LogMessage "err" "The variable oneVideoTitle came up empty. Error accessing API. Exiting program"
        exit 1
    fi
    if test -z "$oneVideoId" 
    then
        LogMessage "err" "The variable oneVideoId came up empty. Error accessing API. Exiting program"
        exit 1
    fi

    # Work-around for issue #59. If any video is found with the title
    # "Deleted video", it means that there was a deleted video that ended up
    # in the playlist somehow, without being removed from the playlist.
    # Remove it from the playlist now, and skip to the next item.
    if [ "$oneVideoTitle" = "Deleted video" ]
    then
      # Don't delete the playlist item if we are in debug mode.
      if [ -z "$debugMode" ]
      then
          # GitHub issue #87 - This is a situation I'd like to have the Synology log for this.
          logToSynology=true

          # Remove the item from the cache if it happens to be in there.
          DeleteRealTimes "$oneVideoId"

          # Delete the playlist item. Note that in this section of the code,
          # we will only see something titled "Deleted video" in a custom
          # playlist, since deleted videos automatically disappear from the
          # "uploads" playlist.
          deletePlaylistItemOutput=""
          curlFullPlaylistItemString="curl -s --request DELETE https://www.googleapis.com/youtube/v3/playlistItems?id=$onePlaylistItemId&access_token=$accessToken"
          LogMessage "err" "Playlist $playlistToClean contained a video, $oneVideoId named $oneVideoTitle. Deleting playlist item $onePlaylistItemId"
          deletePlaylistItemOutput=$( $curlFullPlaylistItemString )
          LogMessage "dbg" "Curl deletePlaylistItemOutput was: $deletePlaylistItemOutput"
          if [[ $deletePlaylistItemOutput == *"error"* ]]
          then
              LogMessage "err" "The attempt to delete playlist item $onePlaylistItemId failed with an error. Error accessing API. Exiting program"
              LogMessage "err" "The deletePlaylistItemOutput was $( echo $deletePlaylistItemOutput | tr '\n' ' ' )"
              exit 1
          fi

          # Continue to the next item in the loop. If the video is already
          # deleted, then no further processing is needed besides cleaning
          # the cache and removing the item from the playlist.
          continue         
      else
          LogMessage "dbg" "Debug mode - Playlist $playlistToClean contained a video, $oneVideoId named $oneVideoTitle. Playlist item: $onePlaylistItemId. Debug mode, so not deleting this playlist item"
          continue
      fi
    fi

    # Secondary query for the video actual recording start date/time and end
    # date/time. Needed because for God's sake, "publishedAt" sucks. Though
    # the data set we already retrieved at this point already has the
    # "publishedAt" value, and I was originally using that value, I found it
    # had a real accuracy problem. PublishedAt contains a weird tweaked value
    # which is rarely exact, and is sometimes flat out wrong, such as: It's
    # either several hours early, right on time, or several hours late. It's a
    # different value depending on whether you're viewing the video from the
    # "uploads" playlist or from a custom playlist. If you view it from a
    # custom playlist, then it is the date you added the video to a playlist.
    # So we have to bite the bullet and perform a secondary query to get some
    # better date values. This additional query eats 2 additional quota for
    # each video, but, to alleviate that, I'm now caching the results in a
    # file, so it won't end up eating a super ton of quota very much.
    timeResponseString=""
    timeResponseString=$( GetRealTimes "$oneVideoId" )
    LogMessage "dbg" "GetRealTimes response: $oneVideoId: $timeResponseString"

    # Place the cache responses into variables.
    read -r cacheMiss throwawayVideoId actualStartTime actualEndTime <<< "$timeResponseString"

    # GitHub issue #87 -If a new video was recently added to the list, I would
    # like to log the fact that we're uploading it, each time that happens.
    # However, this script doesn't know specifically when the videos it's
    # writing are new or not. It knows when one was deleted, so it can log
    # that, but the only indicator of a "new" video would be a cache miss from
    # the GetRealTimes function. Reading that as the first parameter return
    # from the GetRealTimes function now.
    if [ "$cacheMiss" = true ]
    then
      LogMessage "info" "Cache miss, new video $oneVideoId titled $oneVideoTitle"
      logToSynology=true
    fi

    # Debug output. Display the output of the variables (compare with string
    # response above, weird spacing is so it lines up).
    # LogMessage "dbg" "Values:   $throwawayVideoId              $actualStartTime $actualEndTime"

    # If the video is not an archived copy of a live streaming video, then the
    # actual start time will come out blank. If not blank, though, then write
    # that value into the video data string for later use by another project.
    # Note that the actualEndTime will sometimes be blank, in the case of 
    # uploaded videos which were not "live" videos. In that case, the
    # actualEndTime will be blank and the actualStartTime will be the
    # recordingDate with a midnight UTC value (00:00:00.000Z). It is OK to
    # write a blank actualEndTime value to my video data, so that the other
    # project which consumes the values will know the difference, because
    # actualEndTime will be blank/null/zero in that case. 
    if [ ! -z "$actualStartTime" ]
    then
      # Use a string replacement to write these values into the video data
      # string that I'm already scheduled to write to the disk, essentially
      # adding new JSON into the pattern that isn't originally there. I'm not
      # even writing it into the correct place in the JSON structure, I'm just
      # finding a spot near the videoId and stuffing it in there. This SED
      # command is doing the following (see https://ss64.com/osx/sed.html):
      #    (Overall structure is s/regex/replacement/flags)
      #   "   "              Surround sed command with doublequotes so that the variables work.
      #   \" \"              (several places) - escape the literal doublequotes in spots.
      #    s/someregex/      Substitute someregex with a replacement.    
      #   /\"$oneVideoId\"/  The regex to search for: find quote, the video id, and a quote.
      #   /replacement/      The replacement
      #   /& (replacement)/  Start the replacement string by filling in the contents of the found regex.
      #   g                  Flag to replace all occurrences (I only expect one, but it won't work without a flag).
      uploadsOutput=$( sed "s/\"$oneVideoId\"/&,\"actualStartTime\": \"$actualStartTime\", \"actualEndTime\": \"$actualEndTime\"/g" <<< $uploadsOutput )
    else
      # If we did not get an actual time, then skip to the next iteration of
      # the loop, because we don't want to touch any videos that we can't
      # positively identify the time of recording of the video at all.
      LogMessage "dbg" "Could not get actual video start time - Skipping cleanup of $oneVideoId - $oneVideoTitle"
      continue
    fi

    # Debugging - Output every video title and publication date before the date
    # calculations start to occur. This output can be quite large, so do not
    # activate this unless you really need it.
    #  LogMessage "dbg" "$oneVideoId - $actualStartTime - $oneVideoTitle"

    # Determine if the video is old enough to delete. Start by creating a
    # variable to decide the behavior. Fail safe with a "false" default value
    # before moving on to the test.
    videoNeedsDeleting=false

    # Call the helper function to test the date.
    videoNeedsDeleting=$( IsOlderThan "$actualStartTime" "$dateBufferDays" )

    # Make sure that we only delete videos matching our exact title.
    if [ "$oneVideoTitle" != "$titleToDelete" ]
    then
        videoNeedsDeleting=false
    fi

    # Debug output of the state of the variables we are comparing.
    LogMessage "dbg" "Checking: $videoNeedsDeleting $cacheMiss - $oneVideoId - $actualStartTime - $oneVideoTitle"

    # Delete the video if it deserves to be deleted.
    if [ "$videoNeedsDeleting" = true ]
    then
        # GitHub issue #87 - This is a situation I'd like to have the Synology log for this.
        logToSynology=true

        # Log to the Synology log that we are deleting a video.
        LogMessage "info" "Title: $oneVideoTitle Id: $oneVideoId Date: $actualStartTime - more than $dateBufferDays days old. Deleting $oneVideoTitle"

        # Prepare a full string of the entire curl command for usage below.
        # Note: The following attempts were poor and did not work, I think
        # because the "--data" command for Curl just doesn't work well for me.
        # I don't know why, because all the examples use the --data command.
        # However every time I use it, it fails. The only way I can get the
        # OAuth token working correctly is to put it directly into the URL.
        # 
        # Does not work:
        #     curlFullString="curl -s --request DELETE --data \"id=$oneVideoId&access_token=$accessToken\" https://www.googleapis.com/youtube/v3/videos"
        #     curlFullString="curl -s -H \"Authorization: OAuth $accessToken\" --request DELETE --data \"id=$oneVideoId&access_token=$accessToken\" https://www.googleapis.com/youtube/v3/videos"
        #
        # Works:
        curlFullString="curl -s --request DELETE https://www.googleapis.com/youtube/v3/videos?id=$oneVideoId&access_token=$accessToken"

        # Log the curl string before we use it.
        # LogMessage "dbg" "Curl command for deletion of video: $curlFullString"  # Do not log strings which contain credentials or access tokens, even in debug mode.

        # Prepare a variable to contain the output from the deletion command.
        deleteVideoOutput=""

        # Do the same for deleting the item from the playlist. The video
        # disappears from the "uploads" playlist automatically, but if the
        # playlist is a custom playlist, then it sits there as a "deleted
        # video" entry unless we do this.
        deletePlaylistItemOutput=""
        curlFullPlaylistItemString="curl -s --request DELETE https://www.googleapis.com/youtube/v3/playlistItems?id=$onePlaylistItemId&access_token=$accessToken"

        # Don't delete the video if we are in debug mode.
        if [ -z "$debugMode" ]
        then
            # Remove the item from the cache before we delete it.
            DeleteRealTimes "$oneVideoId"

            # Delete the playlist item. See if issue #59 can be alleviated by
            # deleting the playlist item before the actual file deletion.
            # However, don't bother to try to clean out the playlistItem if
            # the cleaning target is the "uploads" folder, because that one
            # automatically disappears from the list of uploads as soon as the
            # video is deleted. Whereas, with a custom playlist, then you need
            # to pull the item out of the playlist too.
            if [ "$playlistToClean" = "uploads" ]
            then
              LogMessage "dbg" "Playlist is $playlistToClean - not deleting playlist item"
            else
              LogMessage "dbg" "Playlist is $playlistToClean - Deleting playlist item $onePlaylistItemId"
              deletePlaylistItemOutput=$( $curlFullPlaylistItemString )
              LogMessage "dbg" "Curl deletePlaylistItemOutput was: $deletePlaylistItemOutput"
            fi

            # Perform the actual video deletion.
            deleteVideoOutput=$( $curlFullString )
            LogMessage "dbg" "Curl deleteVideoOutput was: $deleteVideoOutput"

        else
            LogMessage "dbg" "Debug mode - not actually doing a deletion"
        fi

        # If there was the word "error" in the deletion output, error out.
        # NOTE: Sometimes the response is blank when the deletion is
        # successful, I'm not sure why, so only test for the word "error".
        if [[ $deletePlaylistItemOutput == *"error"* ]]
        then
            LogMessage "err" "The attempt to delete playlist item $onePlaylistItemId failed with an error. Error accessing API. Exiting program"
            LogMessage "err" "The deletePlaylistItemOutput was $( echo $deletePlaylistItemOutput | tr '\n' ' ' )"
            exit 1
        fi

        # Do the same for the video deletion.
        if [[ $deleteVideoOutput == *"error"* ]]
        then
            LogMessage "err" "The attempt to delete video $oneVideoId failed with an error. Error accessing API. Exiting program"
            LogMessage "err" "The deleteVideoOutput was $( echo $deleteVideoOutput | tr '\n' ' ' )"
            exit 1
        fi
    fi
done

LogMessage "dbg" "Stripping redundant pagination sections to return the API results back to parseable JSON"
# Github Issue #83 - Make sure the string is parseable JSON before using it.
# At this point, the string $uploadsOutput is a collection of multiple pages'
# worth of JSON queries concatenated together, at 50 results per page. This
# produces invalid JSON output when treated as a single string. It looks like
# this right now:
#     {
#      "kind": "youtube#playlistItemListResponse", (...),
#      "items": [  (...),(...),(...) ],
#      "pageInfo": { (...) }
#     }
#     {
#      "kind": "youtube#playlistItemListResponse", (...),
#      "items": [  (...),(...),(...) ],
#      "pageInfo": { (...) }
#     }
#     {
#      "kind": "youtube#playlistItemListResponse", (...),
#      "items": [  (...),(...),(...) ],
#      "pageInfo": { (...) }
#     }
# What we want is to run all the items together into a single list of items. Do this by
# finding the section between each items-bracket-end and each items-bracket-beginning
# and replacing the whole thing with a single comma. It replaces all the intermediate
# redundant instances of "pageinfo" and "kind:playlistItemListResponse" and leaves only
# a nice clean-smelling list of "items":[(...),(...),(...)] in the middle which is now
# proper JSON again. It still contains one "kind:playlistItemListResponse" at the top and
# one "pageinfo" at the end, and those are OK and we want to keep them.
# 
# Explanation of the SED statement below:
#
#  sed '   '      Surround SED command with singles so that you can use unescaped doubles.
#  s_             Substitute the following pattern with another pattern.
#   _             Use underscores as the SED delimiters instead of the traditional slashes
#                 that SED normally uses, because all the forward and back slashes together
#                 was hurting my tiny monkey brain.
#  \]             Search for a single close square bracket (escaped), the end of "items:[]"
#  , "pageinfo":  Search for a comma, a space, "pageinfo", a colon, and a space, the section
#                 I want to remove after all but the final items:[] section.
#  [   ]*         SPECIAL TRICK: We want to get anything up until the opening of the next 
#                 "items:[]" section. But if we just searched for ".*" here, it fails
#                 because it would grab all of the middle "items:[]"" sections because it
#                 would greedily grab everything up until the FINAL occurrence of the
#                 opening bracket (i.e., the LAST "items:[]" section). And there's a side
#                 issue which is that the lazy match search "(.*?)" would work here if only
#                 SED would support it (it doesn't). So we have to do this trick...
#  [   ]*         Search for any number of characters within this character set...
#  [^\[]*         But you're searching for any characters which are NOT (^) an open square
#                 bracket (escaped) so that you non-greedily grab up until the FIRST
#                 occurrence of said bracket instead of the last one. We want to grab up to
#                 the opening bracket of the first occurrence of the next upcoming "items:[]"
#  \[             Search for a single open square bracket (escaped). This is to grab just that
#                 one bracket character that follows the the prior search.
#  _              End of the sed "search for" phrase, start of the sed "replace with" phrase
#  ,              Replace with a single comma character.
#  _g             Greedy, replace all possible occurrences instead of just the first.
#
# This should work to remove all the doubled-up sections between the end of every "items:[]"
# section (which always precedes a "pageinfo:" section) and then up until the opening bracket
# of the next "items:[]" section. This should also be safe even if the user types square
# brackets into the video description, because it's only searching for a lonely opening
# square bracket in the cruft area between the items, not inside each item.
uploadsOutput=$( echo $uploadsOutput | sed 's_\], "pageInfo":[^\[]*\[_,_g' )

# Output the entire set of concatenated JSON data retrievals into a file on
# the hard disk for later processing. Do this last, so that if any of the
# tests/checks/validations above have failed, then this file does not get
# written. This helps to ensure that the file is a good file which represents
# accurate data.
echo "$uploadsOutput" > "$DIR/$videoData"

# GitHub issue # 87 - log to the synology that we will be uploading our output
# to our secondary project.
if [ "$logToSynology" = true ]
then
  LogMessage "info" "Processed: ${#playlistItemIds[@]} items."
else
  LogMessage "dbg" "Processed: ${#playlistItemIds[@]} items."
fi

# Trigger secondary script to upload the video data to my secondary project,
# if the project exists on the hard disk parallel to this project.
uploadScript="$DIR/../UploadFiles/UploadFiles.sh"
if [ -z "$debugMode" ]
then
  if [ ! -e "$uploadScript" ]
  then
    LogMessage "dbg" "Missing file $uploadScript"
  else
    LogMessage "dbg" "Launching file $uploadScript"
    bash "$uploadScript" $logToSynology
  fi
else
  LogMessage "dbg" "Debug mode - Not trying to launch file $uploadScript"
fi

