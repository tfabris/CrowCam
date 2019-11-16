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

# Get the channel information so that I can find the ID of the playlist of
# "My Uploads".
curlUrl="https://www.googleapis.com/youtube/v3/channels?part=contentDetails&mine=true&access_token=$accessToken"
channelsOutput=""
channelsOutput=$( curl -s $curlUrl )

# Debugging output. Only needed if you run into a nasty bug here.
# Leave deactivated most of the time.
# LogMessage "dbg" "Channels output information: $channelsOutput"

# This outputs some JSON data which includes the line that looks like this:
#    "uploads": "UUqPZGFtBau8rm7wnScxdA3g",
# Parse out the uploads playlist ID string from that line. Some systems that I
# developed this on didn't have "jq" installed in them, so I am using commands
# which are more cross-platform compatible.
uploadsId=""
uploadsId=$(echo $channelsOutput | sed 's/"uploads"/\'$'\n&/g' | grep -m 1 "uploads" | cut -d '"' -f4)

# Make sure the uploadsId is not empty.
if test -z "$uploadsId" 
then
    LogMessage "err" "The variable uploadsId came up empty. Error accessing API. Exiting program"
    LogMessage "err" "The channelsOutput was $( echo $channelsOutput | tr '\n' ' ' )"
    exit 1
fi

# Log the uploads playlist ID to the output.
LogMessage "dbg" "My Uploads playlist ID: $uploadsId"

# Get a list of videos in the "My Uploads" playlist, which includes both
# public videos as well as unlisted videos (all my archived CrowCam videos are
# unlisted, but this should work either way).

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
    curlUrl="https://www.googleapis.com/youtube/v3/playlistItems?playlistId=$uploadsId&maxResults=50&part=snippet&mine=true&access_token=$accessToken"

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
    LogMessage "dbg" "Querying API page $c"
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
done

# Output the entire set of concatenated JSON data retrievals into a file on
# the hard disk for later processing.
echo "$uploadsOutput" > "$DIR/crowcam-videodata"

# Log the output results. Not usually needed. Leave deactivated usually.
# echo " "
# echo  "Output from the query of the Uploads playlist:"
# echo  $uploadsOutput | sed 's/"videoId"/\'$'\n&/g' | grep "videoId"
# echo " "

# OLD METHOD:
# Convert the contents of the output into an array that we can use. The sub-
# sections of the statements below work as follows:
#
# Place the results of the parsing into an array named videoIds (Note: uses
# process substitution which does not work in SH only in BASH, also, readarray
# is not present on MacOS X... Wow this is tougher than it should be):
#                 readarray -t videoIds < <(
# Insert a newline into the output before each occurrence of "videoId".
# (Special version of command with \'$' allows it to work on Mac OS.)
#                 sed 's/"videoId"/\'$'\n&/g'
# Use only the lines containing "videoId" (for example, not the first line).
#                 grep "videoId"
# The remainder of the line is the parsing of the output. All of these could
# work and produce more or less the same array. I've chosen sed-grep-cut. Some
# systems that I developed this on didn't have "jq" installed in them, so I am
# using commands which are more cross-platform compatible.
#
# Example: Use awk to locate the fourth field using a field delimiter of quote.
#      readarray -t videoIds < <(echo $uploadsOutput | sed 's/"videoId"/\'$'\n&/g' | grep "videoId" | awk -F\" 'NF>=3 {print $4}' )
# Example: Use sed to perform a complex parse of the quotes and such.
#      readarray -t videoIds < <(echo $uploadsOutput | sed 's/"videoId"/\'$'\n&/g' | grep "videoId" | sed -n '/{/,/}/{s/[^:]*:[^"]*"\([^"]*\).*/\1/p;}')
# Example: Use "cut" on the quotes and take the fourth field.
#      readarray -t videoIds < <(echo $uploadsOutput | sed 's/"videoId"/\'$'\n&/g' | grep "videoId" | cut -d '"' -f4)
#
# BUGFIX - Issue with the part of the above statements which look like this:
#      readarray -t videoIds < <(
# That syntax gets an error message when running under Task Scheduler in
# Synology when you launch the process with the command "sh script.sh"
#      /volume1/homes/admin/CrowCamCleanup.sh: line 344: syntax error near unexpected token `<'
# This is caused because of two combining problems. (1) The syntax used a
# technique called "process substitution" which works only in BASH not in SH.
# (2) I had been unwittingly launching these in Task Scheduler using the
# command "sh scriptname.sh" which forces it to use SH rather than BASH
# despite having the BASH "shebang" at the top of the file. details explained
# here: https://empegbbs.com/ubbthreads.php/topics/371758
#
# Initially bufgixed by using one of the other ways to read into an array:
#    https://stackoverflow.com/a/9294015/3621748
# But then that alternate array-read method broke when testing on Windows
# platform, so now I have to do the read differently depending on platform:
#
# TO DO: After ensuring the new details retrieval method works on all
# platforms, convert the retrieval of Video IDs to the new method.
if [[ $debugMode == *"Win"* ]]
then
    # This version works on Windows, but not on Mac - no "readarray" on Mac.
    readarray -t videoIds < <(echo $uploadsOutput | sed 's/"videoId"/\'$'\n&/g' | grep "videoId" | cut -d '"' -f4)
else
    # This version works on MacOS, Synology, and in SH, but not on Windows.
    textListOfVideoIds=$(echo $uploadsOutput | sed 's/"videoId"/\'$'\n&/g' | grep "videoId" | cut -d '"' -f4)
    read -a videoIds <<< $textListOfVideoIds
fi

# NEW METHOD:
# Set up empty arrays to hold the video details. These three arrays will build
# the video details list in order, so all three arrays will have the same
# ordering.
titles=()
publishedAts=()

# TO DO: After ensuring the new details retrieval method works on all
# platforms, convert the retrieval of Video IDs to the new method.
# videoIds=()

# New method for retrieving video details by looping through all of the lines
# in the JSON output and adding the matching lines to the arrays as we find
# them. This special syntax uses <<< to redirect input into this loop at the
# end "do" statement down below.
LogMessage "dbg" "Processing JSON results from the API queries, this may take a moment"
while IFS= read -r line
do
    lineResult=$( echo $line | sed 's/"title"/\'$'\n&/g' | grep "title" | cut -d '"' -f4 )
    if ! [ -z "$lineResult" ]
    then
      titles+=( "$lineResult" )
    fi

    lineResult=$( echo $line | sed 's/"publishedAt"/\'$'\n&/g' | grep "publishedAt" | cut -d '"' -f4)
    if ! [ -z "$lineResult" ]
    then
      publishedAts+=( "$lineResult" )
    fi

    # TO DO: After ensuring the new details retrieval method works on all
    # platforms, convert the retrieval of Video IDs to the new method.
    # lineResult=$( echo $line | sed 's/"videoId"/\'$'\n&/g' | grep "videoId" | cut -d '"' -f4)
    # if ! [ -z "$lineResult" ]
    # then
    #   videoIds+=( "$lineResult" )
    # fi
done <<< "$uploadsOutput"

# Log the number of videos found:
LogMessage "info" "${#videoIds[@]} videoIds, ${#titles[@]} titles, ${#publishedAts[@]} publishedAts found. Processing"

# Error out of the program if the count is zero.
if [ "${#videoIds[@]}" = "0" ]
then
   LogMessage "err" "Error - Video count is zero, either there are no videos in the channel or a parsing error has occurred"
   exit 1
else
   LogMessage "dbg" "Count is nonzero, continuing to process"
fi

# Error out of the program if all three numbers do not match exactly.
if [ "${#videoIds[@]}" = "${#titles[@]}" ] && [ "${#titles[@]}" = "${#publishedAts[@]}" ];
then
   LogMessage "dbg" "All three counts are equal, continuing to process"
else
   LogMessage "err" "Error - Data counts for video details did not match. A parsing error has occurred"
   exit 1
fi

# Debugging - Print the array. No need to do this unless you encounter
# some kind of nasty unexpected bug. Leave this commented out usually.
# for ((i = 0; i < ${#videoIds[@]}; i++))
# do
#     echo "${videoIds[$i]} ${publishedAts[$i]} ${titles[$i]}"
# done
# LogMessage "dbg" "${#videoIds[@]} videoIds, ${#titles[@]} titles, ${#publishedAts[@]} publishedAts found. Processing"

# Iterate through the array and delete any old videos which have not been renamed.
for ((i = 0; i < ${#videoIds[@]}; i++))
do    
    oneVideoDateString=${publishedAts[$i]}
    oneVideoTitle=${titles[$i]}
    oneVideoId=${videoIds[$i]}

    # Throw an error if any of the values are blank.
    if test -z "$oneVideoDateString" 
    then
        LogMessage "err" "The variable oneVideoDateString came up empty. Error accessing API. Exiting program"
        exit 1
    fi
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

    # Debugging - Output every video title and publication date before the date
    # calculations start to occur. This output can be quite large, so do not
    # activate this unless you really need it.
    #  LogMessage "dbg" "$oneVideoId - $oneVideoDateString - $oneVideoTitle"

    # Take the date string from the API results and make it a localized date
    # variable that we can do calculations upon.
    #
    # NOTE: MAC OS PROBLEM:
    #
    # At this point, $oneVideoDateString looks something like this, taken
    # straight from the output from the web site:
    #    "2019-03-17T03:17:07.000Z"
    #
    # The above is an ISO 8601 Greenwich date, and we need to convert it to a
    # local time date so that it looks more like this:
    #    "Sat Mar 16 20:17:07 PDT 2019"
    #
    # The problem is that I also want to be able to run/test this code on Mac,
    # and the Mac's date command doesn't work the same way as the date command
    # on Linux. In addition to the parameters being totally different (the -d
    # parameter means something completely different on Mac than on Linux),
    # the input string is illegal on Mac OS. Even specifying an input
    # format on Mac also has a little problem with it:
    #       -j    Don't try to set the system clock with this date. Required
    #             on Mac OS, so you don't mess up the system.
    #       -f    Specify the input format.
    #
    #                 -j -f "%Y-%m-%dT%H:%M:%S"
    # 
    # That allows the input to work, but is ignoring the milliseconds, and 
    # ignoring the Z at the end (which indicates it's a GMT date). With that
    # input format, it responds with:
    #    "Ignoring 5 extraneous characters in date string (.000Z)"
    #
    # That means it's entirely interpreting it as a local date, but I need it
    # interpreted as a Greenwich date.
    #
    # I've Googled around, and I can't find a documented way to get Mac to
    # interpret that input string as a GMT date instead of a local date. I
    # could install Gnu versions of linux commands, then use GDATE, but I
    # don't want to force people to do that, I want this to work with as
    # little system modification as possible. Besides, this is only so that I
    # can use my Mac as a debugging platform, it's not critical for the final
    # runtime mode on the Synolgy.
    #
    # So what I'm going to do here, for now, is to just accept the fact that
    # the date is going to be several hours off when debugging on Mac. This
    # allows for software code flow testing and debugging, though one must
    # keep in mind that the files will be flagged for deletion at a different
    # cutoff time than in the actual runtime mode.
    if [[ $debugMode == *"Mac"* ]]
    then
        # Mac version - Inaccurate due to failure to interpret GMT zone. Also
        # add ".000Z" to the format string to avoid the extra error message:
        # "Warning: Ignoring 5 extraneous characters in date string (.000Z)"
        videoDateTimeLocalized=$(date -j -f "%Y-%m-%dT%H:%M:%S.000Z" "$oneVideoDateString")
    else
        # Linux version - Accurate, but only works on Linux.
        videoDateTimeLocalized=$(date -d "$oneVideoDateString")
    fi

    # Validate that we got a localized time by checking for a blank string.
    if [ -z "$videoDateTimeLocalized" ]
    then
        LogMessage "err" "Problem retrieving date of video. GMT Date string from web: $oneVideoDateString - Interpreted localized time: $videoDateTimeLocalized"
        exit 1
    fi

    # Debugging - log the localized date that we got. Usually leave disabled.
    # LogMessage "dbg" "Localized video date: $videoDateTimeLocalized"

    # Obtain the current date the same way, localized, so that we're
    # comparing apples to apples when we do our date math. I think this
    # command, when it's just "date" like this, has more or less the same
    # output on Linux and Mac (I think).
    currentDate=$(date)

    # Create a date that is an arbitrary distance in the past (our buffer days
    # amount is defined up at the top of the code). Of course the syntax has
    # to be different for Mac OS, because the "date" command is different...
    if [[ $debugMode == *"Mac"* ]]
    then
        # Mac version.
        # Have to build a separate string for this parameter because it has
        # some characters (the - and the d) slammed right up against my
        # variable, so it makes the process of concatenating the strings
        # trickier than I want it to be. This was the first way I tried
        # doing this which worked, I tried several other methods all of
        # which failed. I'm trying to build a string that says "-5d" where
        # the "5" is the contents of my variable.
        dateSubtractionString="-"
        dateSubtractionString+="$dateBufferDays"
        dateSubtractionString+="d"
        dateInThePast=$( date -j -v $dateSubtractionString )
    else
        # Linux version.
        dateInThePast=$(date -d "$currentDate-$dateBufferDays days")
    fi

    # Debugging - log current and past dates. Usually leave disabled.
    # LogMessage "dbg" "Current date:    $currentDate"
    # LogMessage "dbg" "Date $dateBufferDays days ago: $dateInThePast"

    # Validate that we got a string of any kind, for the date in the past.
    if [ -z "$dateInThePast" ]
    then
        LogMessage "err" "Problem processing date. Current date: $currentDate - Attempted date-in-the-past calculation: $dateInThePast"
        exit 1
    fi

    # Compare the arbitrary date in the past with the video's date. Only delete
    # videos which are X days old, where X is the number of days of our buffer.
    # For instance if dateBufferDays is 5, then only delete videos older than
    # 5 days.
    #
    # Start by creating a variable to decide the behavior. Fail safe with a
    # "false" default value before moving on to the calculations.
    videoNeedsDeleting=false

    # The date calculations have different syntax depending on whether you're
    # running on Mac or Linux.
    if [[ $debugMode == *"Mac"* ]]
    then
        # Mac version - A full command line parameter reference is found if
        # you type "man date" in a Mac OS shell, but I'm having trouble with
        # finding a command to input/interpret the date from a string
        # without ALSO specifying the detailed formatting of that string. So
        # I'm specifying the input string format here and praying that the Mac
        # formats it the same on every system. Of course I know it's not, so
        # this isn't going to work everywhere. Luckily it's for debugging
        # only, so any issues that happen can get worked out in time.
        if (( $(date -j -f "%a %b %d %H:%M:%S %Z %Y" "$videoDateTimeLocalized" +%s) < $(date -j -f "%a %b %d %H:%M:%S %Z %Y" "$dateInThePast" +%s) ))
        then
            videoNeedsDeleting=true
        fi
    else
        # Linux version.
        if (( $(date -d "$videoDateTimeLocalized" +%s) < $(date -d "$dateInThePast" +%s) ))
        then
            videoNeedsDeleting=true
        fi
    fi

    # Make sure that we only delete videos matching our exact title.
    if [ "$oneVideoTitle" != "$titleToDelete" ]
    then
        videoNeedsDeleting=false
    fi

    # Debug output of the state of the variables we are comparing
    LogMessage "dbg" "Checking: $videoNeedsDeleting - $oneVideoId - $videoDateTimeLocalized - $dateInThePast - $oneVideoTitle"

    # Delete the video if it deserves to be deleted.
    if [ "$videoNeedsDeleting" = true ]
    then
        # Log to the Synology log that we are deleting a video.
        LogMessage "info" "Title: $oneVideoTitle Id: $oneVideoId Date: $videoDateTimeLocalized - more than $dateBufferDays days old. Deleting $oneVideoTitle"

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

        # Don't delete the video if we are in debug mode.
        if [ -z "$debugMode" ]
        then
            # Perform the actual deletion.
            deleteVideoOutput=$( $curlFullString )

            # Log the output from Curl
            LogMessage "dbg" "Curl deleteVideoOutput was: $deleteVideoOutput"
        else
            LogMessage "dbg" "Debug mode - not actually doing a deletion"
        fi

        # If there was the word "error" in the deletion output, error out.
        # NOTE: Sometimes the response is blank when the deletion is
        # successful, I'm not sure why, so only test for the word "error".
        if [[ $deleteVideoOutput == *"error"* ]]
        then
            LogMessage "err" "The attempt to delete video $oneVideoId failed with an error. Error accessing API. Exiting program"
            LogMessage "err" "The deleteVideoOutput was $( echo $deleteVideoOutput | tr '\n' ' ' )"
            exit 1
        fi
    fi
done
