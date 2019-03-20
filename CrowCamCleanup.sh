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
  logMessage "err" "---------------------- Script is running in debug mode: $debugMode ----------------------"
fi

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

#------------------------------------------------------------------------------
# Read client ID and client secret from the client_id.json file
#------------------------------------------------------------------------------

# Place contents of file into a variable.
clientIdOutput=$(< "$clientIdJson")

# Parse the Client ID and Client Secret out of the results. The commands work
# like this:
#
# Insert a newline into the output before each occurrence of "client_id".
# (Special version of command with \'$' allows it to work on Mac OS.)
#                 sed 's/"client_id"/\'$'\n&/g'
# Use only lines containing "client_id" and return only the first result.
#                 grep -m 1 "client_id"
# Cut on quotes and return the fourth field only.
#                 cut -d '"' -f4

clientId=$(echo $clientIdOutput | sed 's/"client_id"/\'$'\n&/g' | grep -m 1 "client_id" | cut -d '"' -f4)
clientSecret=$(echo $clientIdOutput | sed 's/"client_secret"/\'$'\n&/g' | grep -m 1 "client_secret" | cut -d '"' -f4)

# Make sure the clientId is not empty.
if test -z "$clientId" 
then
    logMessage "err" "The variable clientId came up empty. Error parsing json file. Exiting program"
    logMessage "dbg" "The clientIdOutput was $( echo $clientIdOutput | tr '\n' ' ' )"
    exit 1
fi

# Make sure the clientSecret is not empty.
if test -z "$clientSecret" 
then
    logMessage "err" "The variable clientSecret came up empty. Error parsing json file. Exiting program"
    logMessage "dbg" "The clientIdOutput was $( echo $clientIdOutput | tr '\n' ' ' )"
    exit 1
fi

#------------------------------------------------------------------------------
# Read refresh token from the crowcam-tokens file
#------------------------------------------------------------------------------

# Place contents of file into a variable. Note that the refresh token file is
# expected to have no newline or carriage return characters within it, not even
# at the end of the file.
refreshToken=$(< "$crowcamTokens")

# Make sure the refreshToken is not empty.
if test -z "$refreshToken" 
then
    logMessage "err" "The variable refreshToken came up empty. Error parsing tokens file. Exiting program"
    exit 1
fi

# Use the refresh token to get a new access token each time we run the script.
# The refresh token has a long life, but the access token expires quickly,
# probably in an hour or so, so we'll get a new one each time we run the
# script.
accessTokenOutput=""
accessTokenOutput=$( curl -s --request POST --data "client_id=$clientId&client_secret=$clientSecret&refresh_token=$refreshToken&grant_type=refresh_token" https://accounts.google.com/o/oauth2/token )

# Parse the Access Token out of the results. The commands work like this:
#
# Insert a newline into the output before each occurrence of "access_token".
# (Special version of command with \'$' allows it to work on Mac OS.)
#                 sed 's/"access_token"/\'$'\n&/g'
# Use only lines containing "access_token" and return only the first result.
#                 grep -m 1 "access_token"
# Cut on quotes and return the fourth field only.
#                 cut -d '"' -f4
accessToken=""
accessToken=$(echo $accessTokenOutput | sed 's/"access_token"/\'$'\n&/g' | grep -m 1 "access_token" | cut -d '"' -f4)

# Make sure the Access Token is not empty.
if test -z "$accessToken" 
then
    logMessage "err" "The variable accessToken came up empty. Error accessing API. Exiting program"
    logMessage "dbg" "The accessTokenOutput was $( echo $accessTokenOutput | tr '\n' ' ' )"
    exit 1
fi

# Log the access token to the output.
logMessage "dbg" "Access Token: $accessToken"

# Get the channel information so that I can find the ID of the playlist of
# "My Uploads".
curlUrl="https://www.googleapis.com/youtube/v3/channels?part=contentDetails&mine=true&access_token=$accessToken"
channelsOutput=""
channelsOutput=$( curl -s $curlUrl )

# Debugging output. Only needed if you run into a nasty bug here.
# Leave deactivated most of the time.
# logMessage "dbg" "Channels output information: $channelsOutput"

# This outputs some JSON data which includes the line that looks like this:
#    "uploads": "UUqPZGFtBau8rm7wnScxdA3g",
# Parse out the uploads playlist ID string from that line.
uploadsId=""
uploadsId=$(echo $channelsOutput | sed 's/"uploads"/\'$'\n&/g' | grep -m 1 "uploads" | cut -d '"' -f4)

# Make sure the uploadsId is not empty.
if test -z "$uploadsId" 
then
    logMessage "err" "The variable uploadsId came up empty. Error accessing API. Exiting program"
    logMessage "err" "The channelsOutput was $( echo $channelsOutput | tr '\n' ' ' )"
    exit 1
fi

# Log the uploads playlist ID to the output.
logMessage "dbg" "My Uploads playlist ID: $uploadsId"

# Get a list of videos in the "My Uploads" playlist, which includes unlisted
# videos such as all the old CrowCam videos. NOTE: Must use maxResults=50
# parameter because the default number of search results is only 5 items. The
# playlist is always longer than 5 items so we'll always want to process 50.
curlUrl="https://www.googleapis.com/youtube/v3/playlistItems?playlistId=$uploadsId&maxResults=50&part=contentDetails&mine=true&access_token=$accessToken"
uploadsOutput=""
uploadsOutput=$( curl -s $curlUrl )

# Log the output results. Not usually needed. Leave deactivated usually.
# echo " "
# echo  "Output from the query of the Uploads playlist:"
# echo  $uploadsOutput | sed 's/"videoId"/\'$'\n&/g' | grep "videoId"
# echo " "

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
# work and produce more or less the same array. I've chosen sed-grep-cut.
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
if [[ $debugMode == *"Win"* ]]
then
    # This version works on Windows, but not on Mac - no "readarray" on Mac.
    readarray -t videoIds < <(echo $uploadsOutput | sed 's/"videoId"/\'$'\n&/g' | grep "videoId" | cut -d '"' -f4)
else
    # This version works on MacOS, Synology, and in SH, but not on Windows.
    textListOfVideoIds=$(echo $uploadsOutput | sed 's/"videoId"/\'$'\n&/g' | grep "videoId" | cut -d '"' -f4)
    read -a videoIds <<< $textListOfVideoIds
fi

# Debugging - Print the array. No need to do this unless you encounter
# some kind of nasty unexpected bug. Leave this commented out usually.
# echo "Video IDs in the uploads directory in the channel:"
# printf "%s\n" "${videoIds[@]}"
# echo ""

#Display number of videos found:
logMessage "info" "${#videoIds[@]} videos found. Processing"

# Iterate through the array.
for oneVideoId in "${videoIds[@]}"
do
    curlUrl="https://www.googleapis.com/youtube/v3/videos?part=snippet&id=$oneVideoId&access_token=$accessToken"
    oneVideoOutput=""
    oneVideoOutput=$( curl -s $curlUrl )
    
    # Debugging - Output the results we got from the query about this video.
    # This output can be large on the screen, so only activate this line if
    # you need it.
    #  logMessage "dbg" "$oneVideoOutput"
    
    # Parse out the video publication date. NOTE: The "publishedAt" date does
    # not necessarily seem to always be exactly the date it was streamed to
    # the server. Initial investigation seems to indicate that it might be the
    # date that the video title was recently edited. For example if I changed
    # the video's title, then the "publishedAt" date will become the date I
    # changed the title. I *think*, not sure. In any case, I don't have any
    # other date value that I can use. The "snippet" output which contains the
    # title has only one datecode in the output, and that's "publishedAt", so
    # that's what we're stuck with. This should be OK since I only intend to
    # delete files whose titles have not been edited yet. Also the buffer
    # period will only be a few days, so if I edit the title and then edit it
    # back, the file will still eventually get deleted.
    oneVideoDateString=""
    oneVideoDateString=$(echo $oneVideoOutput | sed 's/"publishedAt"/\'$'\n&/g' | grep -m 1 "publishedAt" | cut -d '"' -f4)
    
    # Parse out the video title.
    #
    # NOTE - The title's listed twice, once under "snippet", once under
    # "localized". So we MUST use the -m 1 parameter to grep in this case, so
    # that only the first match is returned. Elsewhere in the code, the -m 1
    # parameter doesn't do much, because there's only ever one result returned
    # of the thing I'm grepping for. But in this case it's critical because
    # more than one will always be returned.
    oneVideoTitle=""
    oneVideoTitle=$(echo $oneVideoOutput | sed 's/"title"/\'$'\n&/g' | grep -m 1 "title" | cut -d '"' -f4)

    # Throw an error if either the title or the date are blank.
    if test -z "$oneVideoDateString" 
    then
        logMessage "err" "The variable oneVideoDateString came up empty. Error accessing API. Exiting program"
        logMessage "err" "The oneVideoOutput was $( echo $oneVideoOutput | tr '\n' ' ' )"
        exit 1
    fi
    if test -z "$oneVideoTitle" 
    then
        logMessage "err" "The variable oneVideoTitle came up empty. Error accessing API. Exiting program"
        logMessage "err" "The oneVideoOutput was $( echo $oneVideoOutput | tr '\n' ' ' )"
        exit 1
    fi

    # Debugging - Output every video title and publication date before the date
    # calculations start to occur. This output can be quite large, so do not
    # activate this unless you really need it.
    #  logMessage "dbg" "$oneVideoId - $oneVideoDateString - $oneVideoTitle"

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
    # The input string is illegal on Mac OS. Even specifying an input
    # format on Mac also has a little illegalness in it:
    #    -j -f "%Y-%m-%dT%H:%M:%S"
    # 
    # By the way:
    #       -j    (I think) don't try to set the system clock with this date
    #             (required on Mac so you don't mess it up)
    #       -f    Specify the input format. 
    #
    # That allows the input to work, but is ignoring the milliseconds, and 
    # ignoring the Z at the end (which indicates it's a GMT date). It says:
    #    "Ignoring 5 extraneous characters in date string (.000Z)"
    #
    # That means it's entirely interpreting it as a local date, but I need it
    # interpreted as a Greenwich date.
    #
    # I've Googled around and I can't find a documented way to get Mac to
    # interpret that input string as a GMT date instead of a local date.
    # (I could install Gnu versions of linux commands, then use GDATE but
    # I don't want to do that just to use my Mac as a debugging platform.)
    #
    # So what I'm going to do here, for now, is to just accept the fact that
    # the date is going to be several hours off when debugging on Mac. This
    # allows for software code flow testing without necessarily cutting off
    # the files at the wrong time.
    if [[ $debugMode == *"Mac"* ]]
    then
        # Mac version - Inaccurate due to failure to interpret GMT zone.
        # Also add ".000Z" to avoid the extra error message on Mac:
        # "Warning: Ignoring 5 extraneous characters in date string (.000Z)"
        videoDateTimeLocalized=$(date -j -f "%Y-%m-%dT%H:%M:%S.000Z" "$oneVideoDateString")
    else
        # Linux version - Accurate but only works on Linux
        videoDateTimeLocalized=$(date -d "$oneVideoDateString")
    fi

    # Validate that we got a localized time.
    if [ -z "$videoDateTimeLocalized" ]
    then
        logMessage "err" "Problem retrieving date of video. GMT Date string from web: $oneVideoDateString - Interpreted localized time: $videoDateTimeLocalized"
        exit 1
    fi

    # Debugging - log the localized date that we got. Usually leave disabled.
    # logMessage "dbg" "Localized video date: $videoDateTimeLocalized"

    # Obtain the current date the same way, localized, so that we're
    # comparing apples to apples when we do our date math. I think this
    # command, when it's just "date" like this, has more or less the same
    # output on Linux and Mac (I think).
    currentDate=$(date)

    # Create a date that is an arbitrary distance in the past (our buffer days
    # amount is defined up at the top of the code). Of course the syntax has
    # to be different for Mac OS...
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
    # logMessage "dbg" "Current date:    $currentDate"
    # logMessage "dbg" "Date $dateBufferDays days ago: $dateInThePast"

    # Validate that we got a string of any kind, for the date in the past.
    if [ -z "$dateInThePast" ]
    then
        logMessage "err" "Problem processing date. Current date: $currentDate - Attempted date-in-the-past calculation: $dateInThePast"
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
        # Mac version - I can't find a full command line parameter reference,
        # so I cant find a command to input/interpret the date from a string
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
    logMessage "dbg" "Checking: $videoNeedsDeleting - $oneVideoId - $videoDateTimeLocalized - $dateInThePast - $oneVideoTitle"

    # Delete the video if it deserves to be deleted.
    if [ "$videoNeedsDeleting" = true ]
    then
        # Log to the Synology log that we are deleting a video.
        logMessage "info" "Title: $oneVideoTitle Id: $oneVideoId Date: $videoDateTimeLocalized - more than $dateBufferDays days old. Deleting $oneVideoTitle"

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
        logMessage "dbg" "Curl command for deletion of video: $curlFullString"

        # Prepare a variable to contain the output from the deletion command.
        deleteVideoOutput=""

        # Don't delete the video if we are in debug mode.
        if [ -z "$debugMode" ]
        then
            # Perform the actual deletion.
            deleteVideoOutput=$( $curlFullString )

            # Log the output from Curl
            logMessage "dbg" "Curl deleteVideoOutput was: $deleteVideoOutput"
        else
            logMessage "dbg" "Debug mode - not actually doing a deletion"
        fi

        # If there was the word "error" in the deletion output, error out.
        # NOTE: Sometimes the response is blank when the deletion is
        # successful, I'm not sure why, so only test for the word "error".
        if [[ $deleteVideoOutput == *"error"* ]]
        then
            logMessage "err" "The attempt to delete video $oneVideoId failed with an error. Error accessing API. Exiting program"
            logMessage "err" "The deleteVideoOutput was $( echo $deleteVideoOutput | tr '\n' ' ' )"
            exit 1
        fi
    fi
done
