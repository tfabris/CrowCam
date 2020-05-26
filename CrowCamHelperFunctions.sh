#!/bin/bash

#------------------------------------------------------------------------------
# CrowCamHelperFunctions.sh - Common functions used in the CrowCam scripts.
#------------------------------------------------------------------------------
# Please see the accompanying file REAMDE.md for setup instructions. Web Link:
#        https://github.com/tfabris/CrowCam/blob/master/README.md
#
# The scripts in this project don't work "out of the box", they need some
# configuration. All details are found in README.md, so please look there
# and follow the instructions.
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Function blocks
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Function: Log message to console and, if this script is running on a
# Synology NAS, also log to the Synology system log.
# 
# Parameters: $1 - "info"  - Log to console stderr and Synology log as info.
#                  "err"   - Log to console stderr and Synology log as error.
#                  "dbg"   - Log to console stderr, do not log to Synology.
#
#             $2 - The string to log. Do not end with a period, we will add it.
#
# Global Variable used: $programname - Prefix all log messages with this.
#
# NOTE: I'm logging to the STDERR channel (>&2) as a work-around to a problem
# where there doesn't appear to be a Bash-compatible way to combine console
# logging *and* capturing STDOUT from a function call. Because if I log to
# STDOUT, then if I call LogMessage from within any of my functions which
# return values to the caller, then the log message output becomes the return
# data, and messes everything up. TO DO: Learn the correct way of doing both at
# the same time in Bash.
#------------------------------------------------------------------------------
LogMessage()
{
  # Log message to shell console. Echo to STDERR on purpose, and add a period
  # on purpose, to mimic the behavior of the Synology log entry, which adds
  # its own period.
  echo "$programname - $2." >&2

  # Only log to synology if the log level is not "dbg"
  if ! [ "$1" = dbg ]
  then
    # Only log to Synology system log if we are running on a Synology NAS
    # with the correct logging command available. Test for the command
    # by using "command" to locate the command, and "if -x" to determine
    # if the file is present and executable.
    if  [ -x "$(command -v synologset1)" ]
    then 
      # Special command on Synology to write to its main log file. This uses
      # an existing log entry in the Synology log message table which allows
      # us to insert any message we want. The message in the Synology table
      # has a period appended to it, so we don't add a period here.
      synologset1 sys $1 0x11800000 "$programname - $2"
    fi
  fi
}

#------------------------------------------------------------------------------
# Function: Check if a certain date string is older than X number of days.
#
# Parameters:  $1 - The date string you want to check, in ISO 8601 UTC
#                   format, like this: "2019-03-17T03:17:07.000Z"
#
#              $2 - The number of days back that you want to know if it's
#                   older than. For instance if you want to know if the date
#                   string is at least 3 days old, then pass in 3 for this.
#
# Returns:          true if older than, false if younger than or if bad input.
#------------------------------------------------------------------------------
IsOlderThan()
{
    oneVideoDateString="$1"
    dateDistanceDays="$2"

    # Fail out of function if there was bad input. This can happen on purpose,
    # for example if the function is part of a larger loop that gets fed a
    # blank time string, so fail gracefully.
    if [ -z "$oneVideoDateString" ]
    then
      returnValue=false
      echo $returnValue
      return -1
    fi
    if [ -z "$dateDistanceDays" ]
    then
      returnValue=false
      echo $returnValue
      return -1
    fi

    # Take the date string from the API results and make it a localized date
    # variable that we can do calculations upon.
    #
    # NOTE: MAC OS PROBLEM:
    #
    # At this point, the inputted date looks something like this, taken
    # straight from the output from the YouTube API:
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
    # keep in mind that a given date will be considered "old" at a different
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
      returnValue=false
      echo $returnValue
      return -1
    fi

    # Debugging - log the localized date that we got. Usually leave disabled.
    # LogMessage "dbg" "Localized video date: $videoDateTimeLocalized"

    # Obtain the current date the same way, localized, so that we're
    # comparing apples to apples when we do our date math. I think this
    # command, when it's just "date" like this, has more or less the same
    # output on Linux and Mac (I think).
    currentDate=$(date)

    # Create a date that is an arbitrary distance in the past (based on the
    # days inputted into this function). Of course the syntax has to be
    # different for Mac OS, because the "date" command is different...
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
        dateSubtractionString+="$dateDistanceDays"
        dateSubtractionString+="d"
        dateInThePast=$( date -j -v $dateSubtractionString )
    else
        # Linux version.
        dateInThePast=$(date -d "$currentDate-$dateDistanceDays days")
    fi

    # Debugging - log current and past dates. Usually leave disabled.
    # LogMessage "dbg" "Current date:    $currentDate"
    # LogMessage "dbg" "Date $dateDistanceDays days ago: $dateInThePast"

    # Validate that we got a string of any kind, for the date in the past.
    if [ -z "$dateInThePast" ]
    then
        LogMessage "err" "Problem processing date. Current date: $currentDate - Attempted date-in-the-past calculation: $dateInThePast"
        returnValue=false
        echo $returnValue
        return -1
    fi

    # Compare the arbitrary date in the past with the video's date. Only delete
    # videos which are X days old, where X is the number of days of our buffer.
    # For instance if dateDistanceDays is 5, then only delete videos older than
    # 5 days.
    #
    # Start by creating a variable to decide the behavior. Fail safe with a
    # "false" default value before moving on to the calculations.
    returnValue=false

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
            returnValue=true
        fi
    else
        # Linux version.
        if (( $(date -d "$videoDateTimeLocalized" +%s) < $(date -d "$dateInThePast" +%s) ))
        then
            returnValue=true
        fi
    fi

    # Return true or false result from the function
    echo $returnValue
}

#------------------------------------------------------------------------------
# Function: Get the real start and stop times of a given video.
#
# This will pull the information from the cache file $videoRealTimestamps if
# present in the file, and if not, it will query the YouTube API and then write
# the data to the cache file if not present.
#
# Make sure you have successfully set the access token by calling the function
# YouTubeApiAuth before calling this function.
#
# Parameters: $1   The YouTube Video ID of the video you want.
# Returns:         One of the following sets of output:
#
#                  If there is a cache miss, and no timing values retrieved:
#                      - No return value
#
#                  If cache file or API contains actualStartTime/actualEndTime,
#                  returns a string containing the data in the following format:
#                      - The video ID
#                      - A space
#                      - The actual start time 
#                      - A space
#                      - The actual end time
#
#                  If cache file or API contains actualStartTime but no end time,
#                  returns a string containing the data in the following format:
#                      - The video ID
#                      - A space
#                      - The actual start time
#
#                  If cache file or API contains no actualStartTime/actualEndTime,
#                  but it does contain a recordingDate time, then it returns
#                  a string containing the data in the following format:
#                      - The video ID
#                      - A space
#                      - The recording date, with a timestamp of midnight UTC.
#
# Notes:  Times are in ISO 8601 (YYYY-MM-DDThh:mm:ss.sZ) format.
#
#         Variables do not contain quote characters or spaces, so you can just
#         do a "read" statement to process them like this:
#
#             timeResponseString=$( GetRealTimes $oneVideoId )
#             read -r oneVideoId actualStartTime actualEndTime <<< "$timeResponseString"
#
#         ActualStartTime and actualEndTime will exist on archives of "live"
#         videos. If video contains an actualStartTime and actualEndTime then
#         both of those time values will be returned from this function.
#
#         RecordingDate will exist on "uploaded" videos. If video contains
#         only a recordingDate value, then only one time value will be
#         returned from this function (i.e., the actualEndTime retrieved from
#         the "read" statement will be blank, and the retrieved
#         actualStartTime value will instead be the recordingDate value).
#
#         The recordingDate value will contain the date, but its timestamp
#         will always be midnight UTC, 0Zulu, in other words "00:00:00.000Z".
#
#         The recordingDate will only be useful if the video owner has entered
#         the correct recording date value into the video details by hand.
#
#         Live "in-progress" live streams will contain an actualStartTime but
#         no end time. The way to tell the difference between a live video and
#         an upload is the 0Zulu timestamp described above. This is not 100%
#         perfect because you can have a live video which happened to start at
#         exactly 0Zulu.
#
#------------------------------------------------------------------------------
GetRealTimes()
{
  # Make sure the first parameter is not empty. If it's not empty, the begin
  # processing the cache file and try to read a value from it based on the ID.
  if [ ! -z $1 ]
  then
    oneVideoId=$1
    cacheReturn=""

    # https://stackoverflow.com/a/2427987/3621748 - Sometimes the YouTube
    # strings begin with a dash, which Grep interprets as a parameter instead
    # of a string. A double dash (--) is used in bash built-in commands and
    # many other commands to signify the end of command options, after which
    # only positional parameters are accepted.
    cacheReturn=$( grep -w -- "$oneVideoId" "$DIR/$videoRealTimestamps" )

    # Address a secondary problem mentioned in issue #58 - refresh any cache
    # returns which might be a stale entry for a partially-broadcast
    # in-progress live stream, i.e., a video with a start time but no end time
    # that's not an "uploaded" video. The idea is to prevent the cache getting
    # "stuck" on a video which is start-time-only because it doesn't re-query
    # later when the video finally gets its end time.
    if [ ! -z "$cacheReturn" ]
    then
      # Get the cache return into variables.
      read -r throwawayVideoId actualStartTime actualEndTime <<< "$cacheReturn"

      # If there's an end time, it's a good cache entry that doesn't need to
      # be refreshed, so we don't need to do anything. Only refresh the data
      # if we don't have an end time.
      if [ -z "$actualEndTime" ]
      then
        # In situations where the start time contains a 0Zulu date, it is
        # likely to be an uploaded video and doesn't need to be refreshed.
        # However, there is a slim chance that it's a live video that by pure
        # chance happened to start at 0Zulu and needs a refresh. But most of
        # the time it's going to be an uploaded video if it's got a 0Zulu.
        if [[ $actualStartTime == *"T00:00:00.000Z"* ]]
        then
          # If the timestamp is less than 24hrs in the past, invalidate this
          # cache entry too. Otherwise do nothing and print a debug log entry.
          # This will prevent a situation where a video which happens to have
          # started at 0Zulu gets stuck without a refreshed end time.
          isVideoOld=$( IsOlderThan "$actualStartTime" 1 )
          if [ "$isVideoOld" = true ]
          then
            LogMessage "dbg" "Cache hit: $oneVideoId - 0Zulu - This is an uploaded video"
          else
            LogMessage "info" "Cache invalidate - Special rare case of young 0Zulu video - $oneVideoId - Start: $actualStartTime End: (none)"
            
            # Invalidate the cache entry by doing the following: Delete the
            # cache entry from the file, clear out the cacheReturn variable, and
            # let the code fall through to the next section with an empty
            # cacheReturn. This way the query code below can try again as if it
            # were a fresh cache entry.
            DeleteRealTimes "$oneVideoId"
            cacheReturn=""
          fi
        else
          # If the $actualStartTime is a valid timestamp (not 0Zulu), and
          # there is no end time, then this is definitely a live video which
          # hasn't finished playing yet. 
          LogMessage "dbg" "Cache invalidate: $oneVideoId - Start: $actualStartTime End: (none) - Likely a live video in progress"
          
          # Invalidate the cache entry by doing the following: Delete the
          # cache entry from the file, clear out the cacheReturn variable, and
          # let the code fall through to the next section with an empty
          # cacheReturn. This way the query code below can try again as if it
          # were a fresh cache entry.
          DeleteRealTimes "$oneVideoId"
          cacheReturn=""
        fi       
      fi
    fi
    
    # Check if something was returned from the cache.
    if [ -z "$cacheReturn" ]
    then
      # If nothing was returned from the cache, query the API for that data.
      LogMessage "dbg" "Cache miss: $oneVideoId"
      curlUrl="https://www.googleapis.com/youtube/v3/videos?part=liveStreamingDetails&id=$oneVideoId&access_token=$accessToken"
      liveStreamingDetailsOutput=""
      liveStreamingDetailsOutput=$( curl -s $curlUrl )
      
      # Debugging output. Only needed if you run into a nasty bug here.
      # Leave deactivated most of the time.
      # LogMessage "dbg" "Live streaming details output information: $liveStreamingDetailsOutput"      

      # Parse the actual start/stop times out of the details output.
      actualStartTime=""
      actualStartTime=$(echo $liveStreamingDetailsOutput | sed 's/"actualStartTime"/\'$'\n&/g' | grep -m 1 "actualStartTime" | cut -d '"' -f4)
      actualEndTime=""
      actualEndTime=$(echo $liveStreamingDetailsOutput | sed 's/"actualEndTime"/\'$'\n&/g' | grep -m 1 "actualEndTime" | cut -d '"' -f4)

      # If the video is not a live streaming video, or it is not found, then
      # the actual start and end times will come out blank. 
      if [ ! -z "$actualStartTime" ] || [ ! -z "$actualEndTime" ]
      then
        # If the start and end times are unblank, write them to the file and
        # also echo them to the standard output to return them back to the
        # caller of this function.
        echo "$oneVideoId $actualStartTime $actualEndTime" >> "$DIR/$videoRealTimestamps"
        echo "$oneVideoId $actualStartTime $actualEndTime"
      else
        # If the start and end times were blank, check to see if the video is
        # not found at all, which can happen if the video was deleted yet
        # still remains in the playlist. If the video is not found then the
        # response string will contain this exact string value within it:
        #     "totalResults": 0
        # If the video is found, then I expect it to find only one result:
        #     "totalResults": 1
        # To check this, cannot do my usual retrieval of a value like this, it
        # doesn't work due to totalResults integer not surrounded by quotes.
        #     totalResults=$(echo $liveStreamingDetailsOutput | sed 's/"totalResults"/\'$'\n&/g' | grep -m 1 "totalResults" | cut -d '"' -f4)
        # So just check for the whole string.
        if [[ "$liveStreamingDetailsOutput" == *"\"totalResults\": 1"* ]]
        then
          # If the start and end times were blank, but the the video did in
          # fact exist, then it is likely an "uploaded video" instead of a
          # live video. Perform a secondary API query to retrieve the
          # "recordingDate" value in lieu of the actualStartTime value.  
          LogMessage "dbg" "Did not find start or end times for video $oneVideoId - performing secondary query of API for recordingDate"
          curlUrl="https://www.googleapis.com/youtube/v3/videos?part=recordingDetails&id=$oneVideoId&access_token=$accessToken"
          recordingDetailsOutput=""
          recordingDetailsOutput=$( curl -s $curlUrl )

          # Debugging output. Only needed if you run into a nasty bug here.
          # Leave deactivated most of the time.
          # LogMessage "dbg" "Recording details output information: $recordingDetailsOutput"  

          # Extract the recording date value from the API query results. Note:
          # In order for this value to be useful, the owner of this video must
          # have correctly filled out, by hand, the recording date in the
          # YouTube settings for this video. If untouched, the recording date
          # will be inaccurate.
          recordingDate=""
          recordingDate=$(echo $recordingDetailsOutput | sed 's/"recordingDate"/\'$'\n&/g' | grep -m 1 "recordingDate" | cut -d '"' -f4)

          # Check if we successfully retrieved a recordingDate for this video.
          if [ ! -z "$recordingDate" ]
          then
            # If the recording date is unblank, write it to the file and also
            # echo it to the standard output to return it back to the caller
            # of this function. This forces, into the cache file, and into the
            # return from the cache file, the recordingDate value in place of
            # the actualStartTime value. Also, it leaves the actualEndTime
            # value blank. Note: recordingDate is the date only, and always
            # has a time-of-day stamp of midnight UTC (00:00:00.000Z).
            LogMessage "dbg" "Substituting into the cache: Using recordingDate from video $oneVideoId in place of actualStartTime. Value: $recordingDate"
            echo "$oneVideoId $recordingDate" >> "$DIR/$videoRealTimestamps"
            echo "$oneVideoId $recordingDate"
          else
            # If the video was found in the playlist, but it had neither a
            # recording date nor an actual start time, it might be an
            # "upcoming" video, for example it may be the channel's main live
            # video stream, either online or offline. I have already confirmed
            # that this state occurs for upcoming videos which are offline.
            # TODO: confirm if this state occurs for the channel's main online
            # live stream, for example, I wonder if an online live stream has
            # an actualStartTime but doesn't yet contain an actualEndTime, or
            # if they are both blank until the live stream finishes.
            LogMessage "dbg" "Did not find a recordingDate from video $oneVideoId - video may be an upcoming scheduled video"
          fi
        else
          LogMessage "dbg" "Video was not found in search: $oneVideoId - Video may have been deleted" 
        fi
      fi
    else
      # If there was a value found in the cache, return it.
      echo "$cacheReturn"
    fi
  fi
}

#------------------------------------------------------------------------------
# Function: Clean start and stop times from the cache file.
#
# Parameters: $1   The YouTube Video ID of the video you want to clear.
# Returns:         Nothing.
#
# This will erase the line from the cache file which contains the video ID.
# Remember to call this function any time you delete a file, so that cruft
# doesn't build up.
#------------------------------------------------------------------------------
DeleteRealTimes()
{
    oneVideoId=$1
    LogMessage "dbg" "Cleaning $1 out of the cache"

    # The SED technique at https://stackoverflow.com/a/5410784/3621748 didn't
    # work, so doing this instead https://stackoverflow.com/a/5413132/3621748.
    grep -v -w -- "$oneVideoId" "$DIR/$videoRealTimestamps" > "$DIR/$videoRealTimestamps.temp"
    mv "$DIR/$videoRealTimestamps.temp" "$DIR/$videoRealTimestamps"
}


#------------------------------------------------------------------------------
# Function: Check if Synology Surveillance Station service is up.
# 
# Parameters: None
# Returns: "true" if the Synology Surveillance Station is up, "false" if not.
#------------------------------------------------------------------------------
IsServiceUp()
{
  # Preset a variable to return so that all paths return some kind of value.
  # Value will be changed depending on the outcome of the tests below.
  ReturnCode=1

  # When running on Synology, check the actual service using a Syno command.
  if [ -z "$debugMode" ] || [[ $debugMode == *"Synology"* ]]
  then 
    # Note - you must redirect to /dev/null or else your output from this
    # command will become the return text rather than "true" or "false" below.
    # This command has no "quiet" mode, so do /dev/null instead.
    synoservicectl --status $serviceName > /dev/null
    ReturnCode=$?
  fi

  # Version of service check command for testing on Mac. The $serviceName
  # variable will be different when running in debug mode on Mac, so that it
  # is easier to test in that environment.
  if [[ $debugMode == *"Mac"* ]]
  then
    pgrep -xq -- "${serviceName}"
    ReturnCode=$?
  fi

  # Version of service check command for testing on Windows. The $serviceName
  # variable will be different when running in debug mode on Windows, so that
  # it is easier to test in that environment.
  if [[ $debugMode == *"Win"* ]]
  then
    # Special handling of windows command needed, in order to make it
    # compatible with multiple different flavors of Bash on Windows. For
    # example, Git Bash will take "net start" directly, but the Linux Subsystem
    # For Windows 10 needs it put into cmd.exe /c in order to work. Also, the
    # backticks are needed or else it doesn't always work properly. Fun times.
    winOutput=`cmd.exe /c "net start"`
    echo "$winOutput" | grep -q "$serviceName"
    ReturnCode=$?
  fi

  # Check return code and report running or down.
  if [ "$ReturnCode" = 0 ]
  then
    echo "true"
  else
    echo "false"
  fi
}


#------------------------------------------------------------------------------
# Function: Web API Call. Performs a Synology Web API call. Uses the global
#           variable $webApiRootUrl for the base URL, the part of the URL for
#           everything up to and including "/webapi/".
# 
# Params:   $1 = The string following "/webapi/" in the query you're making.
#
# Returns:  The string of the data returned from the Synology web API.
#
# Note:     Will log in to the web API automatically if needed.
#------------------------------------------------------------------------------
WebApiCall()
{
  # Workaround for exiting the entire Bash script from a sub-function of this
  # function. Create an intermediary step that allows an option to be able to
  # send a TERM signal to the top level script and then exit this function.
  trap "kill -s TERM $TOP_PID && exit 1" TERM

  # Use $BASHPID to obtain the Process ID of this function when it's running,
  # so that the child subroutine knows where to send its signal when needed.
  #
  # NOTE: Issue #6 - $BASHPID is not present on Mac OS X due to it having been
  # introduced in Bash v4 while Mac is still on Bash v3. Attempted workaround
  # here: https://stackoverflow.com/a/9121753 - did not work. Giving up, since
  # the issue only occurs in debug mode on Mac OS X - Perfect kill behavior is
  # not needed in debug mode.
  export WEBAPICALL_PID=$BASHPID

  # Set up some parameters that will be used for calling WGet.
  cookieParametersStandard="--load-cookies $cookieFileName --timeout=10"

  # If the cookie file is not present, perform the first authentication with
  # the web API which will save a new cookie file that we can use below.
  if ! [ -e $cookieFileName ]
  then
    LogMessage "dbg" "Cookie file not present - authenticating"
    WebApiAuth
  fi

  # Make the web API call.
  LogMessage "dbg" "Calling: wget -qO- $cookieParametersStandard \"$webApiRootUrl/$1\""
                webResult=$( wget -qO- $cookieParametersStandard "$webApiRootUrl/$1" )
  LogMessage "dbg" "Response: $webResult"

  # Check to make sure our call to the web API succeeded, if not, perform a
  # single re-auth and try again. This situation can occur if a cookie already
  # existed but it had expired and thus we needed to re-auth.
  if ! [[ $webResult == *"\"success\":true"* ]]
  then
    LogMessage "dbg" "The call to the Synology Web API failed. Attempting to re-authenticate"
    WebApiAuth
    LogMessage "dbg" "Re-Calling: wget -qO- $cookieParametersStandard \"$webApiRootUrl/$1\""
                     webResult=$( wget -qO- $cookieParametersStandard "$webApiRootUrl/$1" )
    LogMessage "dbg" "Response: $webResult"
  fi

  # Check to make sure our call to the web API succeeded, exit if not.
  if ! [[ $webResult == *"\"success\":true"* ]]
  then
    LogMessage "err" "The call to the Synology Web API failed. Exiting program"

    # Work-around to problem of being unable to exit the script from within
    # this function. Send kill signal to top level PID and then exit
    # the function to prevent additional commands from being executed.
    kill -s TERM $TOP_PID
    exit 1
  fi

  # Return the string of data that we got back from the Synology API.
  echo $webResult
}


#------------------------------------------------------------------------------
# Function: Web API Auth. Performs a Synology API login and saves the cookie.
# 
# Params:   None - uses global variables for the credentials.
# Returns:  Nothing. If it fails to authenticate, it will exit the script.
#------------------------------------------------------------------------------
WebApiAuth()
{
  # Set up strings
  cookieParametersAuth="--keep-session-cookies --save-cookies $cookieFileName --timeout=10"

  # Create string for authenticating with Synology Web API. Note: deliberately
  # using version=1 in this call because I ran into problems with version=3.
  authWebCall="auth.cgi?api=SYNO.API.Auth&version=1&method=login&account=$username&passwd=$password&session=SurveillanceStation&format=cookie"

  # Debugging output for local machine test runs. Do not use this under normal
  # circumstances - it prints the password in clear text.
  # LogMessage "dbg" "Logging into Web API: wget -qO- $cookieParametersAuth \"$webApiRootUrl/$authWebCall\""

  # Make the web API call. The expected response from this call will be
  # {"success":true}. Note: The response is more detailed in version=3 but I
  # had some problems with other calls in version=3 so I went back down to
  # version=1 on all calls.
  authResult=$( wget -qO- $cookieParametersAuth "$webApiRootUrl/$authWebCall" )

  # Output for local machine test runs.
  LogMessage "dbg" "Response: $authResult"

  # Check to make sure our call to the web API succeeded, exit if not.
  if ! [[ $authResult == *"\"success\":true"* ]]
  then
    LogMessage "err" "The call to authenticate with the Synology Web API failed. Exiting program. Response: $authResult"

    # Work-around to problem of being unable to exit the script from within
    # this function. Send kill signal to mid level PID and then exit
    # the function to prevent additional commands from being executed.
    kill -s TERM $WEBAPICALL_PID
    exit 1
  fi
}


#------------------------------------------------------------------------------
# Function: Check if the live video stream to YouTube is running.
# 
# Parameters: None
# Returns: "true" if the video stream to YouTube is running, "false" if not.
#
# Note: This does not check if the stream is "succeeding", only if the feature
# that's "trying" to do the streaming is turned on or not.
#------------------------------------------------------------------------------
IsStreamRunning()
{
    # Check the status only if we are running on the Synology.
    if [ -z "$debugMode" ] || [[ $debugMode == *"Synology"* ]]
    then
      # The response of this call will list all data for the YouTube live stream
      # upload as it is configured in Surveillance Station "Live Broadcast"
      # screen. The response will look something like this:
      # {"data":{"cam_id":1,"connect":false,"key":"xxxx-xxxx-xxxx-xxxx",
      # "live_on":false,"rtmp_path":"rtmp://a.rtmp.youtube.com/live2",
      # "stream_profile":0},"success":true}. We are looking specifically for
      # "live_on":false or "live_on":true here. 
      LogMessage "dbg" "Checking status of $featureName feature"
      streamStatus=$( WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&version=1&method=Load" )

      # Check the string for our test phrase and return the appropriate value.
      if [[ $streamStatus == *"\"live_on\":true"* ]]
      then
        LogMessage "dbg" "$featureName feature is running"
        echo "true"
      else
        LogMessage "dbg" "$featureName feature is stopped"
        echo "false"
      fi
    else
      # If we're debugging on a different system, just return true.
      LogMessage "dbg" "We are not in a position to check status of $featureName - returning true"
      echo "true"
    fi
}


#------------------------------------------------------------------------------
# Function: Start the live video stream to YouTube.
# 
# Parameters: None
# Returns: Nothing.
#------------------------------------------------------------------------------
StartStream()
{
  # Use the "Save" method to set live_on=true. Response is expected to be
  # {"success":true} but I'm not checking the return data from this API call.
  WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&live_on=true" >/dev/null
}


#------------------------------------------------------------------------------
# Function: Stop the live video stream to YouTube.
# 
# Parameters: None
# Returns: Nothing.
#------------------------------------------------------------------------------
StopStream()
{
  # Use the "Save" method to set live_on=false. Response is expected to be
  # {"success":true} but I'm not checking the return data from this API call.
  WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&live_on=false" >/dev/null
}


#------------------------------------------------------------------------------
# Function: Convert a number of seconds duration into HH:MM format.
# 
# Parameters: $1 = integer of the number of seconds since midnight
#
# Returns: Formatted time string in "HH:MM" format, or "D days HH:MM" format.
#
# Technique gleaned from: https://unix.stackexchange.com/a/27014
#------------------------------------------------------------------------------
SecondsToTime()
{
  # If the number of seconds is a negative number, then the event is in the
  # past, so flip the number to positive so that we can show the HH:MM time
  # without a bunch of ugly "-" signs in the output. If the number is 0 or
  # positive, then use the number as-is.
  if [ $1 -ge 0 ]
  then
    # Use the number as-is if it's 0 or positive.
    T=$1
  else
    # If the number is negative, flip it to positive by multiplying by -1.
    T=$((-1*$1))
  fi
  
  # Perform the calculations and formatting based on the code example.
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))
  
  # Return the resulting string to the code that called us.
  if [ $D -gt 0 ]
  then
    printf "%d days %02d:%02d\n" $D $H $M
  else
    printf "%02d:%02d\n" $H $M
  fi
}

#------------------------------------------------------------------------------
# Function: Convert a number of seconds duration into H:MM AM/PM format.
# 
# Parameters: $1 = integer of the number of seconds since midnight
#
# Returns: Formatted time string in "H:MM AM/PM" format, or "D days HH:MM AM/PM".
#
# Technique gleaned from: https://unix.stackexchange.com/a/27014
#------------------------------------------------------------------------------
SecondsToTimeAmPm()
{
  # If the number of seconds is a negative number, then the event is in the
  # past, so flip the number to positive so that we can show the HH:MM time
  # without a bunch of ugly "-" signs in the output. If the number is 0 or
  # positive, then use the number as-is.
  if [ $1 -ge 0 ]
  then
    # Use the number as-is if it's 0 or positive.
    T=$1
  else
    # If the number is negative, flip it to positive by multiplying by -1.
    T=$((-1*$1))
  fi
  
  # Perform the calculations and formatting based on the code example.
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))

  # Do the AM/PM fun stuff.
  amPmString="AM"
  if [ $H -gt 11 ]; then amPmString="PM"; fi
  if [ $H -eq 0 ]; then H=12; fi
  if [ $H -gt 12 ]; then H=$(( $H - 12 )); fi
  
  # Return the resulting string to the code that called us.
  if [ $D -gt 0 ]
  then
    printf "%d days %d:%02d %s\n" $D $H $M $amPmString
  else
    printf "%d:%02d %s\n" $H $M $amPmString
  fi
}

#------------------------------------------------------------------------------
# Function: Authenticate with the YouTube API.
# 
# Parameters: None - uses global variables for its inputs.
#
# Returns: None - sets the global variable $accessToken
#
# Note: Requires detailed setup steps before this function will work. Must
# follow the instructions in README.md and execute the file
# "CrowCamCleanupPreparation.sh" as instructed there (after setting up the
# account correctly first).
#------------------------------------------------------------------------------
YouTubeApiAuth()
{
  # First, read client ID and client secret from the client_id.json file

  # Place contents of file into a variable.
  clientIdOutput=$(< "$clientIdJson")

  # Parse the Client ID and Client Secret out of the results. Some systems that I
  # developed this on didn't have "jq" installed in them, so I am using commands
  # which are more cross-platform compatible. The commands work like this:
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
      LogMessage "err" "The variable clientId came up empty. Error parsing json file. Exiting program"
      LogMessage "dbg" "The clientIdOutput was $( echo $clientIdOutput | tr '\n' ' ' )"

      # Work-around to problem of being unable to exit the script from within
      # this function. Send kill signal to top level PID and then exit
      # the function to prevent additional commands from being executed.
      kill -s TERM $TOP_PID
      exit 1
  fi

  # Make sure the clientSecret is not empty.
  if test -z "$clientSecret" 
  then
      LogMessage "err" "The variable clientSecret came up empty. Error parsing json file. Exiting program"
      LogMessage "dbg" "The clientIdOutput was $( echo $clientIdOutput | tr '\n' ' ' )"

      # Work-around to problem of being unable to exit the script from within
      # this function. Send kill signal to top level PID and then exit
      # the function to prevent additional commands from being executed.
      kill -s TERM $TOP_PID
      exit 1
  fi

  # Next, read refresh token from the crowcam-tokens file. Place contents of
  # file into a variable. Note that the refresh token file is expected to have
  # no newline or carriage return characters within it, not even at the end of
  # the file.
  refreshToken=$(< "$crowcamTokens")

  # Make sure the refreshToken is not empty.
  if test -z "$refreshToken" 
  then
      LogMessage "err" "The variable refreshToken came up empty. Error parsing tokens file. Exiting program"

      # Work-around to problem of being unable to exit the script from within
      # this function. Send kill signal to top level PID and then exit
      # the function to prevent additional commands from being executed.
      kill -s TERM $TOP_PID
      exit 1
  fi

  # Use the refresh token to get a new access token each time we run the script.
  # The refresh token has a long life, but the access token expires quickly,
  # probably in an hour or so, so we'll get a new one each time we run the
  # script.
  accessTokenOutput=""
  accessTokenOutput=$( curl -s --request POST --data "client_id=$clientId&client_secret=$clientSecret&refresh_token=$refreshToken&grant_type=refresh_token" https://accounts.google.com/o/oauth2/token )

  # Parse the Access Token out of the results. Some systems that I developed this
  # on didn't have "jq" installed in them, so I am using commands which are more
  # cross-platform compatible. The commands work like this:
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
      LogMessage "err" "The variable accessToken came up empty. Error accessing YouTube API"
      # LogMessage "dbg" "The accessTokenOutput was $( echo $accessTokenOutput | tr '\n' ' ' )"     # Do not log strings which contain credentials or access tokens, even in debug mode.
  
      # Fix GitHub issue #28 - Do not crash out of the program if we can't
      # retrieve the access token. Just print an error and let the calling
      # program decide whether or not to fail if the access token is empty. 
        # kill -s TERM $TOP_PID
        # exit 1
  else
      # Log the access token to the output.
      # LogMessage "dbg" "Access Token: $accessToken" # Do not log strings which contain credentials or access tokens, even in debug mode.
      LogMessage "dbg" "Access Token retrieved"
  fi
}
