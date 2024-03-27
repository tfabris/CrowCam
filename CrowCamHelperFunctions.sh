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
#             $2 - The string to log. Synology will always add a period to it.
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
  # GitHub issue #85 - Correctly interpret multiline strings when logging. I had
  # a situation where there was an error in an API, and the error details were
  # embedded in the JSON response that was returned to the API. However the
  # JSON response was in "pretty" mode, and so it had nice linefeeds and
  # indents to go along with the curly braces. When I tried to log that JSON
  # response, since the bash function call to LogMessage interprets each line
  # as a separate parameter, only the first of the line of the message (in this
  # case, parameter $2) was printed to the log. Fix this by re-interpreting all
  # parameters from $2 on up as the message string. This uses a special bash
  # parameter expansion command to interpret all of the parameters from 2->n.
  # Excellent explanation here: https://stackoverflow.com/a/3816747/3621748
  logOutputString="${@:2}"

  # Convenience feature: Logging to the Synology log will always add a trailing
  # period to the end of the log message. The Synology message template
  # 0x11800000 that I'm using literally has a period built into it. So before
  # logging, strip out a trailing period (if any) from the text message, to
  # prevent double-periods in the log. For a long time, I was just trying to
  # remember not to add periods at the ends of my log messages, and I would
  # occasionally forget, and the double period would appear. So strip that
  # here, and add it back below if it's needed. The technique that I'm using
  # is to use the Parameter Expansion feature of Bash, and use the special
  # operator "%" which is meant for trimming characters from the end of an
  # expansion. In this case, "%." means "Strip the period from the end."
  logOutputString="${logOutputString%.}"

  # Log message to shell console. This command has the following features:
  # - Echo to STDERR on purpose (>&2) so that, if you are logging inside
  #   a Bash "function", the function doesn't accidentally return your
  #   log message as the return value for that function.
  # - Echo with the "-e" parameter, so that linefeeds are preserved when
  #   echoing to the shell console. This makes output more readable when
  #   you are debugging things like prettified JSON or XML at the console.
  # - Add a period at the end of the output on purpose, to mimic the
  #   appearance of the Synology log entry, which adds its own period.
  echo -e "$programname - $logOutputString." >&2

  # Only log to synology if the log level is not "dbg"
  if ! [ "$1" = dbg ]
  then
    # Only log to Synology system log if we are running on a Synology NAS
    # with the correct logging command available. Test for the command
    # by using "command" to locate the command, and "if -x" to determine
    # if the file is present and executable.
    if  [ -x "$(command -v synologset1)" ]
    then 
      # GitHub issue #85 - Ensure that all newlines have been removed from the
      # string before sending it to the Synology log, so that all of the
      # message is visible (Synology prints only the first line of multi-line
      # logs). Note that this command must use the "-e" feature to ensure that
      # the translate (tr) command will correctly get all of the string,
      # newlines and all, so that it can strip those newlines.
      synologyLogOutputString=$(echo -e "$logOutputString" | tr -d '\n')

      # Special command on Synology to write to its main log file. This uses
      # an existing log entry in the Synology log message table which allows
      # us to insert any message we want. The message in the Synology table
      # already has a period appended to it, so we don't add a period here.
      synologset1 sys $1 0x11800000 "$programname - $synologyLogOutputString"
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
        #
        # Update 2024-03-13 - The YouTube API changed at some point to have
        # either removed or added the milliseconds from their JSON output. So
        # this function needs to process both if possible.
        # Old version:
        #    videoDateTimeLocalized=$(date -j -f "%Y-%m-%dT%H:%M:%S.000Z" "$oneVideoDateString")
        # New version:

        # Check if the string that we're stuffing into the Date command already
        # ends with the milliseconds. This is the syntax in Bash for "endswith".
        # NOTE: The wildcard requires no quotes around either of the IF strings.
        if [[ $oneVideoDateString == *.000Z ]]
        then
          videoDateTimeLocalized=$(date -j -f "%Y-%m-%dT%H:%M:%S.000Z" "$oneVideoDateString")
        else
          videoDateTimeLocalized=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$oneVideoDateString")
        fi
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

# -----------------------------------------------------------------------------
# Function: GetFutureZulu
# 
# Creates a zulu date string that is a date that is in the future. Used for
# creating a timestring that is in the future, so that it can satisfy a
# specific requirement of the YouTube API which is creating an upcoming YouTube
# video live stream.
#
# It will return a string that looks similar to this:
#         2024-03-19T20:55:00Z
# 
# The Z at the end indicates it is a Zulu date which is a UTC date.
#
# The actual date and time will be some time in the future. Not too far off from
# today's time but also far enough that you've got time to create the stream.
#
# Parameters:  None.
#
# Returns:     Just that string.
# -----------------------------------------------------------------------------
GetFutureZulu()
{
    # Create a date that is an arbitrary distance in the future. Of course the
    # syntax has to be different for Mac OS, because the "date" command is
    # different on MacOS.
    if [[ $debugMode == *"Mac"* ]]
    then
        # Mac version.
        dateInTheFuture=$( date -u -j -v +5M +"%Y-%m-%dT%H:%M:%S" ) # The 5M must be capitalized for "Minutes"
    else
        # Linux version.
        dateInTheFuture=$(date -u -d "+5 minutes" +"%Y-%m-%dT%H:%M:%S")
    fi

    # Add the Z to the end of the string and output it to the calling routine.
    dateInTheFuture="$dateInTheFuture"
    dateInTheFuture+="Z"
    echo "$dateInTheFuture"
}

#------------------------------------------------------------------------------
# Function: Convert a timestamp from HH:MM format into seconds since midnight.
# 
# Parameters: $1 = input time in HH:MM format. Can be 12- or 24-hour format.
#             $2 = optional - "AM" or "PM" if 12-hour format is being used.
#
# Returns: integer of the number of seconds since midnight.
#
# If your 12-hour time is a string, such as "7:35 PM" then it is already
# set up to pass into this function as two parameters. Pass it into this
# function like this, with no quotes around the string when passing it in:
#
#     sunsetString="7:35 PM"
#     sunsetSeconds=$(TimeToSeconds $sunsetString)
#
# The same method of parameter passing works for 24-hour times:
#
#     sunsetString="19:35"
#     sunsetSeconds=$(TimeToSeconds $sunsetString)
#
# NOTE: Important trick! Must add the expression "10#" in the calculations
# below, because in Bash, numbers with leading zeroes make Bash assume that the
# calculation is in Octal, so any value 08 or above would cause it to get an
# error because it thinks that we mean 08 octal instead of 8 decimal. This
# causes some gnarly hard-to-diagnose errors unless we add that "10#" to force
# it to base 10.
#
# Technique obtained (but is incorrect due to that octal thing) from:
# https://stackoverflow.com/a/2181749/3621748
#------------------------------------------------------------------------------
TimeToSeconds()
{
    # Set the time string to calculate based on the input parameter.
    inputTime=$1

    # Perform the calculation based on the example code from Stack Overflow.
    SavedIFS="$IFS"
    IFS=":."
    Time=($inputTime)
    calculatedSeconds=$((10#${Time[0]}*3600 + 10#${Time[1]}*60))

    # If "PM" was passed in the second parameter, then add 12 hours to it.
    if [[ $2 == *"PM"* ]]
    then
        # Parenthesis required for arithmetic expression
        ((calculatedSeconds += 43200))
    fi

    # Set things back and return our results.
    IFS="$SavedIFS"
    echo $calculatedSeconds
}

#------------------------------------------------------------------------------
# Function: Output Time Difference.
# 
# Parameters: $1 = Integer seconds difference such as $sunriseDifferenceSeconds
#             $2 = String in HH:MM format of that, obtained from SecondsToTime
#             $3 = Name of the difference such as "Sunrise"
#
# Returns: A sentence describing the difference.
#------------------------------------------------------------------------------
OutputTimeDifference()
{
  # Output the time difference based on whether the number was positive or
  # negative. If the number is negative, the event was in the past for today.
  # If the number is positive, the event is coming up later today.
  if [ $1 -ge 0 ]
  then
      echo "$3 is coming up in about $2"
  else
      echo "$3 was about $2 ago"
  fi
}

#------------------------------------------------------------------------------
# Function: Write the time to a file each time we start the YouTube stream.
# 
# Write the current wall clock time, in seconds, to a certain file, intended
# to track the most recent time that we started the stream for any reason.
# 
# Make sure to call this function each time we start the YouTube stream for any
# reason.
# 
# Parameters: None.
# Returns: Nothing.
#------------------------------------------------------------------------------
WriteStreamStartTime()
{
  # Get the current time string into a variable, but use only hours and
  # minutes. This code is deliberately not accurate down to the second.
  currentStreamStartTime="`date +%H:%M`"

  # Convert our current time into seconds-since-midnight.
  currentStreamStartTimeSeconds=$(TimeToSeconds $currentStreamStartTime)

  # Log
  LogMessage "dbg" "Writing $currentStreamStartTimeSeconds to $crowcamCamstart"

  # Write the current time, in seconds, into the specified file.
  # Use "-n" to ensure there is no trailing newline character.
  echo -n "$currentStreamStartTimeSeconds" > "$crowcamCamstart"
}


# -----------------------------------------------------------------------------
# Function: Fix Locale.
#
# This is part of the bugfix to issue #81. If the system locale is not set, then
# force the system locale to be our desired value so that grepping for the
# unicode characters works as expected.
#
# In the function GetSunriseSunsetTimeFromGoogle, it became necessary to grep
# for a unicode narrow nonbreaking space (0x202f), which will succeed if the
# system locale is set to any UTF8 variant. Running under the Synology Task
# Scheduler, for some weird reason, has no locale set at all. The $LC_ALL
# variable is blank in that situation, and so grepping for unicode characters
# might fail. Since $LC_ALL is set correctly when running at the Synology
# shell, this is hard to debug at a runtime shell.
# -----------------------------------------------------------------------------
FixLocale()
{
  # Only perform actions if the existing locale is blank/null.
  if [ -z "$LC_ALL" ]
  then
    LogMessage "dbg" "System LC_ALL variable was null, attempting to fix"

    # Loop through all possible locale values by listing them all using
    # the "locale -a" command.
    forceLocale=""
    for onePossibleLocale in `locale -a`
    do
      # Look to see if the string matches our needs. It needs to be some upper
      # lower or mixed case variation of "en_US.utf8", with or without a hyphen
      # in "utf-8". This uses the "tr" string translator to change upper case
      # to lower case, so we get a case insensitive check for this IF
      # statement.
      if [[ "$(echo $onePossibleLocale | tr '[:upper:]' '[:lower:]')" = *'en_us'* ]] && [[ "$(echo $onePossibleLocale | tr '[:upper:]' '[:lower:]')" = *'utf'* ]]
      then
        # LogMessage "dbg" "FOUND desired locale value:       $onePossibleLocale"
        forceLocale="$onePossibleLocale"
        break
        # else
        # LogMessage "dbg" "Searching possible locale values: $onePossibleLocale"
      fi
    done
  
    # Only force the locale if we got a valid value out of the search.
    if [ -z "$forceLocale" ]
    then
      LogMessage "err" "Unable to find a valid locale value to set, locale fixing not performed"
    else
      # Fix the LC_ALL variable for use in the remainder of this script run.
      LogMessage "dbg" "Forcing locale to: $forceLocale"
      export LC_ALL=$forceLocale
      LogMessage "dbg" "Current Locale:    $LC_ALL"
    fi
  else
    LogMessage "dbg" "System LC_ALL variable was already set to $LC_ALL - No locale fix needed"
  fi
}


# -----------------------------------------------------------------------------
# Function: Get sunrise or sunset time from Google.
#
# Performs a simple Google search such as "Sunrise 98133" and finds the 
# "answer box" on Google containing the answer. The "answer box" is the little
# box that google puts at the top of your search results when it thinks that
# you were searching for a particular piece of data, such as the results of a
# math calculation, or, as in this case, the astronomical data for a particular
# location.
# 
# Parameters:       $1         Should be either "Sunrise" or "Sunset".
# Global Variables: $location  Global variable containing your location, such
#                              as "98125" or "Seattle,WA"
#                   $userAgent Global variable containing user-agent for the
#                              web query (see above for details).
# Returns:                     String of the time that Google responded with,
#                              such as "7:25 AM"
# -----------------------------------------------------------------------------
GetSunriseSunsetTimeFromGoogle()
{
    # Debugging message, leave commented out usually.
    # LogMessage "info" "Beginning GetSunriseSunsetTimeFromGoogle" 

    # Fix the locale bug from issue #81
    FixLocale

    # Create the query URL that we will use for Google.
    googleQueryUrl="http://www.google.com/search?q=$1%20$location"

    # Debugging output
    # LogMessage "dbg" "Google Sunrise/Sunset Query URL: $googleQueryUrl"

    # Perform the query on the URL, and place the HTML results into a variable.
    googleQueryResult=$( wget -L -qO- --user-agent="$userAgent" "$googleQueryUrl" )
    
    # Debugging output
    # LogMessage "dbg" "Google Sunrise/Sunset Query Result: $googleQueryResult"

    # Alternate version that uses Curl instead of Wget, if needed.
    # googleQueryResult=$( curl -L -A "$userAgent" -s "$googleQueryUrl" )

    # Debug test cases: Uncomment some or all of these to test time-parsing.
    # googleQueryResult="<test>
    # <div>123:456 am</div>
    # <div>123:456 a.m.</div>
    # <div>123:456</div>
    # <div>12:32 foo AM</div>
    # <div>12:32</div>
    # <div>12:81 am</div>
    # <div>12:3 am</div>
    # <div>1:3 am</div>
    # <div>09:30 azmz</div>
    # <div>6:59 a.m.</div>
    # <div>6:59 AM</div>
    # <div>09:30 a.m.</div>
    # <div>09:30 A.M.</div>
    # <div>09:30 am</div>
    # <div>9:31 am</div>
    # <div>9:32 AM</div>
    # <div>09:32 AM</div>
    # </test>"
    
    # Parse the HTML for our answer, and echo the result back to the caller.
    # Update 2024-03-16 - Google is no longer using the "w-answer-desktop" CSS
    # class in their output, instead the classname seems to be random
    # characters which might be dynamically generated. Also they changed the
    # whitespace between the time and the AM/PM indicator so that it's no
    # longer just a space, it's a <0x202f> which is a unicode "narrow nobreak
    # space". Let's see if we can locate the time in the output result by
    # grepping on just the time characters, any dealing with that funky space.
    #
    # Parsing statement detailed explanation. Note: On MacOS the "-P" parameter
    # does not work, so you can't use the \d+ command on MacOS.
    #    -o               Output only the matched text from each line.
    #    -m 1             Output only the first match found on each line.
    #    [0-9]{1,2}       Look for 1 or 2 integer digits of 0-9.
    #    :                Look for a colon.
    #    [0-5][0-9]       Look for exactly two integer digits, the first being 0-5.
    #    .                Fix issue #81 - Look for any one char (such as space 0x202f)
    #    (AM|p\.m\. etc)  Fix issue #84 - Look for the acceptable combinations of AM/PM.
    #                     Escape the periods to ensure it's JUST periods it's looking for.
    #    | head -n 1      Return only the first result, just in case the input string
    #                     is multiline and grep returns more than one possible result.
    # This should get everything like "7:25 AM" or "10:00 p.m." etc. with a space or
    # any weird unicode character in place of the space.
    timeWithWeirdSpaceInTheMiddle=$(echo $googleQueryResult | grep -o -E -m 1 '[0-9]{1,2}:[0-5][0-9].(AM|PM|am|pm|A\.M\.|P\.M\.|a\.m\.|p\.m\.)' | head -n 1 )

    # OK, but now the time has that weird space in the middle, and without that
    # actual space, it crashes all the other functions that try to do
    # calculations on it. Blech. So let's strip it down to that space using
    # similar techniques.
    #    LogMessage "dbg" "Post-Processing this time string: $timeWithWeirdSpaceInTheMiddle"
    firstTimeSection=$(echo $timeWithWeirdSpaceInTheMiddle | grep -o -E -m 1 '[0-9]{1,2}:[0-5][0-9]' )
    secondTimeSection=$(echo $timeWithWeirdSpaceInTheMiddle | grep -o -E '(AM|PM|am|pm|A\.M\.|P\.M\.|a\.m\.|p\.m\.)' )

    # While we're here, I want the final output to be "AM" or "PM" uppercase
    # without periods, to ensure that later parsing steps can handle it.
    # Translate the string to uppercase using "tr" and then use substitution in
    # parameter expansion to replace periods with nothings (twice).
    secondTimeSection=$(echo $secondTimeSection | tr '[:lower:]' '[:upper:]')
    secondTimeSection=${secondTimeSection/.}
    secondTimeSection=${secondTimeSection/.}

    # Finally, let's return this thing out of this function as a proper time
    # with a REGULAR space in the middle.
    #
    # BUGFIX - If we didn't get any data from Google, then we want to return a
    # null string. But saying "echo "$firstTimeSection $secondTimeSection"" at
    # the end of the function does NOT return a null string. Even if Google
    # gets nothing, it still returns a string with a single space. This is a
    # problem if there is an error extracting data from Google. So we must
    # check it and only return the "spaced" string if Google returned us
    # something good.
    if [ -z "$firstTimeSection" ] || [ -z "$secondTimeSection" ]
    then
      # Debugging output for the console if the parsing code failed somehow.
      LogMessage "dbg" "Google surise/sunset time retrieval failed"
      LogMessage "dbg" "Google output was: $googleQueryResult"
      LogMessage "dbg" "timeWithWeirdSpaceInTheMiddle: $timeWithWeirdSpaceInTheMiddle"
      LogMessage "dbg" "firstTimeSection:              $firstTimeSection"
      LogMessage "dbg" "secondTimeSection:             $secondTimeSection"

      # Echo an empty string out of the function.
      echo ""
    else
      # Echo the correct result out of the function.
      echo "$firstTimeSection $secondTimeSection"
    fi

    # Debugging message, leave commented out usually.
    # LogMessage "info" "Done with GetSunriseSunsetTimeFromGoogle"
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
        #
        # Update 2024-03-13 - The YouTube API changed at some point to have
        # either removed or added the milliseconds from their JSON output. So
        # this function needs to process both if possible. So now also checking
        # for just a "Z" at the end as well as a ".000Z" at the end.
        if [[ $actualStartTime == *"T00:00:00.000Z"* ]] || [[ $actualStartTime == *"T00:00:00Z"* ]]
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
            LogMessage "dbg" "Cache invalidate - Special rare case of young 0Zulu video - $oneVideoId - Start: $actualStartTime End: (none)"
            
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
    # Check the status only if we are running on the Synology, or at least at
    # home where we can access its API on the local LAN. 
    if [ -z "$debugMode" ] || [[ $debugMode == *"Home"* ]] || [[ $debugMode == *"Synology"* ]]
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


# -----------------------------------------------------------------------------
# Function: CreateNewStream
# 
# Creates a new livebroadcast, its corresponding livestream, and begins
# streaming to it. This is in response to GitHub issue #69. Details of the
# required steps are here:
# 
#    https://developers.google.com/youtube/v3/live/life-of-a-broadcast
#
# Parameters:  None.
#              Uses some global configuration variables during its run.
#
# Returns:     Nothing.
# -----------------------------------------------------------------------------
CreateNewStream()
{
  # Make sure you are recently authenticated with the YouTube API before starting
  # this function, so that the calls to the API are correct and expected.
  YouTubeApiAuth

  # Stop the stream if one is already running.
  LogMessage "dbg" "Stopping existing stream (if any) prior to creating a new live broadcast"
  StopStream

  # First step - Create a new live broadcast at an upcoming near-future date.
  LogMessage "info" "Creating new YouTube Live Broadcast"

  # Get a time string that's in the future, because creating a livestream
  # requires an upcoming start time in the near future. 
  futureZuluTime=$(GetFutureZulu)

  # Create a new liveBroadcast on YouTube. Below is the minimum set of fields
  # which are needed to create a new liveBroadcast. This is on purpose, because
  # the fields and settings of the broadcast mostly default to the stuff from
  # the last broadcast, so you don't need to fill out a bunch of stuff.
  #
  # Well, one exception to the minimum. I have added enableAutoStart/Stop
  # because that saves a step when starting the stream below. The stream should
  # go live as soon as the stream starts and then stop about a minute after the
  # stream stops. 
  curlData=""
  curlData+="{"
    curlData+="\"snippet\": "
      curlData+="{"
        curlData+="\"title\": \"$titleToDelete\","
        curlData+="\"scheduledStartTime\": \"$futureZuluTime\""
      curlData+="},"
    curlData+="\"status\": "
      curlData+="{"
        curlData+="\"privacyStatus\": \"$desiredStreamVisibility\""
      curlData+="},"
    curlData+="\"contentDetails\": "
      curlData+="{"
        curlData+="\"enableAutoStart\": true,"   # No quotes around true/false
        curlData+="\"enableAutoStop\": true"     # No quotes around true/false
      curlData+="}"
  curlData+="}"
  curlUrl="https://www.googleapis.com/youtube/v3/liveBroadcasts?part=snippet,id,status,contentDetails&mine=true&access_token=$accessToken"
  createNewLiveBroadcastOutput=$( curl -s -m 20 -X POST -H "Content-Type: application/json" -d "$curlData" $curlUrl )

  # Retrieve the first "id" field of the response, this is the broadcast that we
  # must bind the new liveStream (below) to.
  thisBroadcastId=""
  thisBroadcastId=$(echo $createNewLiveBroadcastOutput | sed 's/"id"/\'$'\n&/g' | grep -m 1 "id" | cut -d '"' -f4)
  if [ -z "$thisBroadcastId" ] || [[ $createNewLiveBroadcastOutput == *"\"error\":"* ]]
  then
    LogMessage "err" "Error getting variable thisBroadcastId. Output was $createNewLiveBroadcastOutput"
  else
    # Note: I was unable to get the re-using of the liveStream to succeed. It
    # worked the first time I tried it, on a liveStream that I had created but
    # never used. This seemed promising. But on subsequent attempts, the
    # liveBroadcast became a spinny death icon when trying to re-use that same
    # stream. So this isn't do-able.
    #
    #     LogMessage "dbg" "Searching for an existing reusable live stream to bind to the broadcast"
    # 
    #     # See if the first livestream in my list is reusable and try to reuse it.
    #     # NOTE: using the variable "createNewLiveStreamOutput" twice, once here if
    #     # this reusable stream works, and once again below if we must create a new
    #     # live stream. Whichever of these methods is successful, one of them will
    #     # get parsed for the ID of the stream that we want. Note: the "contentDetails"
    #     # section is the part that contains the field "isReusable".
    #     curlUrl="https://www.googleapis.com/youtube/v3/liveStreams?part=id,cdn,status,contentDetails&mine=true&access_token=$accessToken"
    #     createNewLiveStreamOutput=""
    #     createNewLiveStreamOutput=$( curl -s -m 20 $curlUrl )
    #
    #     # Find the first occurrence of the parameter "isReusable" and see if it's
    #     # the acceptable value. Special way to parse out a value that's true/false
    #     # out of the JSON since true/false don't have quotes around them and might
    #     # be followed with a comma.
    #     isReusable=""
    #     isReusable=$(echo $createNewLiveStreamOutput | sed 's/"isReusable"/\'$'\n&/g' | grep -m 1 "isReusable" | cut -d '"' -f3 | cut -d ' ' -f2 | cut -d ',' -f1)

    LogMessage "dbg" "Creating new YouTube Live Stream to bind to the Broadcast"

    # Create a new liveStream resource to bind to the liveBroadcast we created
    # above. Like the liveBroadcast, this is the minimum set of fields for this.
    curlData=""
    curlData+="{"
      curlData+="\"snippet\": "
        curlData+="{"
          curlData+="\"title\": \"$titleToDelete\""
        curlData+="},"
      curlData+="\"cdn\": "
        curlData+="{"
          curlData+="\"frameRate\": \"variable\","
          curlData+="\"ingestionType\": \"rtmp\","
          curlData+="\"resolution\": \"variable\","
          curlData+="\"frameRate\": \"variable\"" # The docs say you must also set frameRate if you set rez.
        curlData+="}"
    curlData+="}"
    curlUrl="https://www.googleapis.com/youtube/v3/liveStreams?part=snippet,cdn,status&mine=true&access_token=$accessToken"
    createNewLiveStreamOutput=$( curl -s -m 20 -X POST -H "Content-Type: application/json" -d "$curlData" $curlUrl )

    # Retrieve the first "id" field of the response, this is the liveStream that we
    # must bind to the broadcast (above).
    thisStreamId=""
    thisStreamId=$(echo $createNewLiveStreamOutput | sed 's/"id"/\'$'\n&/g' | grep -m 1 "id" | cut -d '"' -f4)

    # Retrieve the field "streamName" from the response as well. This is the
    # liveStream's "secret Name/Key" that we must plug into the Synology "Live
    # broadcast" feature in order for the stream to work.
    streamName=""
    streamName=$(echo $createNewLiveStreamOutput | sed 's/"streamName"/\'$'\n&/g' | grep -m 1 "streamName" | cut -d '"' -f4)

    # Also find the parameters "streamStatus" and the "status" value inside
    # the "healthStatus" and tell us what they were. I don't know if these will
    # be a factor in whether or not the stream is successfully reusable. The JSON
    # here looks like this:
    #    "status":
    #    {
    #      "streamStatus": "inactive",
    #      "healthStatus":
    #      {
    #       "status": "noData"
    #      }
    #    },
    # Due to the weird JSON, to get the healthStatus, we must locate TWO
    # sections named "status" (-m 2) and parse the second one (tail -1).
    healthStatus=""
    healthStatus=$(echo $createNewLiveStreamOutput | sed 's/"status"/\'$'\n&/g' | grep -m 2 "status" | tail -1 | cut -d '"' -f4 )
    streamStatus=""
    streamStatus=$(echo $createNewLiveStreamOutput | sed 's/"streamStatus"/\'$'\n&/g' | grep -m 1 "streamStatus" | cut -d '"' -f4)

    # Ensure there were no major errors getting the liveStream details, then display what we got.
    if [ -z "$thisStreamId" ] || [ -z "$streamName" ] || [[ $createNewLiveStreamOutput == *"\"error\":"* ]]
    then
      LogMessage "err" "Error getting variable thisStreamId. Output was $createNewLiveStreamOutput"
    else
      LogMessage "dbg" "Live Stream Key (aka streamName): $streamName Id: $thisStreamId Stream Status: $streamStatus Health Status: $healthStatus"
      LogMessage "dbg" "Binding stream to the Broadcast Id: $thisBroadcastId"

      # Bind the live stream to the broadcast.
      curlUrl="https://www.googleapis.com/youtube/v3/liveBroadcasts/bind?part=status&id=$thisBroadcastId&streamId=$thisStreamId&access_token=$accessToken"

      bindToBroadcastOutput=""
      bindToBroadcastOutput=$( curl -s -m 20 -X POST -H "Content-Type: application/json" $curlUrl )

      # Bind should return a status response which looks something like this:
      # {
      #   "kind": "youtube#liveBroadcast",
      #   "etag": "asdfasdfasdfasdfasdfasdfasdfasdf",
      #   "id": "asdfasdfasdf",
      #   "status": {
      #     "lifeCycleStatus": "ready",
      #     "privacyStatus": "public",
      #     "recordingStatus": "notRecording",
      #     "madeForKids": false,
      #     "selfDeclaredMadeForKids": false
      #   }
      # }
      # Get the lifeCycleStatus back from the response.
      lifeCycleStatusAfterBind=""
      lifeCycleStatusAfterBind=$(echo $bindToBroadcastOutput | sed 's/"lifeCycleStatus"/\'$'\n&/g' | grep -m 1 "lifeCycleStatus" | cut -d '"' -f4)

      # Ensure there were no errors and check for the "lifeCycleStatus": "ready" part.
      if [ "$lifeCycleStatusAfterBind" != "ready" ] || [[ $bindToBroadcastOutput == *"\"error\":"* ]]
      then 
        LogMessage "err" "Error binding to broadcast. Output was $bindToBroadcastOutput"
      else
        LogMessage "dbg" "Bound to broadcast. Updating Synology with key $streamName"

        # Update the stream name/key on the Synology Live Broadcast feature.
        if [ -z "$debugMode" ] || [[ $debugMode == *"Home"* ]] || [[ $debugMode == *"Synology"* ]]
        then
          WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&key=$streamName" >/dev/null
        fi

        # Start the stream.
        WriteStreamStartTime  
        if [ -z "$debugMode" ] || [[ $debugMode == *"Home"* ]] || [[ $debugMode == *"Synology"* ]]
        then
          StartStream
          LogMessage "dbg" "Stream started, pausing to give it time to start working"
        fi

        # Wait a few seconds for the stream to engage, so that it sets the
        # livestream status to "active".
        sleep 10

        LogMessage "dbg" "Querying liveStreams for the status of the stream after starting it"

        # Query the liveStreams to get the status and confirm that it is Active.
        # According to the lifecycle instructions, it should be Active now
        # after we started streaming data to it. 
        curlUrl="https://www.googleapis.com/youtube/v3/liveStreams?part=status&id=$thisStreamId&access_token=$accessToken"
        liveStreamsOutput=""
        liveStreamsOutput=$( curl -s -m 20 $curlUrl )

        # Retrieve the streamStatus field of the response
        thisStreamStatus=""
        thisStreamStatus=$(echo $liveStreamsOutput | sed 's/"streamStatus"/\'$'\n&/g' | grep -m 1 "streamStatus" | cut -d '"' -f4)

        # Ensure no errors.
        if [ -z "$thisStreamStatus" ] || [[ $liveStreamsOutput == *"\"error\":"* ]]
        then
          LogMessage "err" "Error getting variable thisStreamStatus. Output was $liveStreamsOutput"
        else
          if [ "$thisStreamStatus" != "active" ]
          then
            LogMessage "err" "The streamStatus is not active. Value retrieved was: $thisStreamStatus"
          else
            # This is the main log message indicating the newly-created stream
            # is now live. Targeting this as "info" level for the Synology log.
            LogMessage "info" "New video is live. Video ID: $thisBroadcastId Status: $thisStreamStatus Key: $streamName"
          fi
        fi

        # GitHub issue #75 - Fix categoryID after stream is created. Though the
        # creation of a new video automatically re-uses a bunch of stuff from
        # your prior livestreams (things such as Description and Tags are
        # already filled out), there is a bug: One field keeps getting
        # clobbered each time: The "categoryId" of the video keeps getting
        # reset to "24 (Entertainment)" each time you create a new video. This
        # fix below puts the desired categoryId into video after it is created.
        # Make sure to configure your desired default categoryId in
        # crowcam-config.
        # 
        # The problem is that fixing the categoryId overwrites the entire
        # "snippet" field, which ALSO clobbers things like the description, the
        # tags, and the thumbnail. Gah. So now we also must have a default
        # Description, Tags, and Thumbnail configured in the crowcam-config file
        # to push into every new video.
        LogMessage "dbg" "Setting the categoryId of video $thisBroadcastId to $categoryId"
        curlData=""
        curlData+="{"
          curlData+="\"id\": \"$thisBroadcastId\","
          curlData+="\"snippet\": "
            curlData+="{"
              curlData+="\"title\": \"$titleToDelete\","
              curlData+="\"description\": \"$defaultDescription\","
              curlData+="\"tags\": $defaultTags,"
              curlData+="\"categoryId\": \"$categoryId\""
            curlData+="}"
        curlData+="}"
        curlUrl="https://youtube.googleapis.com/youtube/v3/videos?part=snippet&access_token=$accessToken"
        fixCategoryOutput=$( curl -s -m 20 -X PUT -H "Content-Type: application/json" -d "$curlData" $curlUrl )

        # It should respond with a Videos resource with a Snippet section, and
        # that section should contain the updated categoryId field. Retrieve
        # that field of the response and check it.
        respondedCategoryId=""
        respondedCategoryId=$(echo $fixCategoryOutput | sed 's/"categoryId"/\'$'\n&/g' | grep -m 1 "categoryId" | cut -d '"' -f4)

        # Ensure there were no errors.
        if [ "$respondedCategoryId" != "$categoryId" ] || [[ $fixCategoryOutput == *"\"error\":"* ]]
        then
          LogMessage "err" "Error setting categoryId to $categoryId. Output was $fixCategoryOutput"
        else
          # Upload a default thumbnail file (file pointed to by
          # $defaultThumbnail should exist in the same folder as this script).
          LogMessage "dbg" "Uploading thumbnail file $defaultThumbnail"
          curlUrl="https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=$thisBroadcastId&access_token=$accessToken"
          uploadThumbnailOutput=$( curl -s -F "image=@$defaultThumbnail" $curlUrl )

          # Parse out the "kind" field from the thumbnail response, it's supposed
          # to contain "kind": "youtube#thumbnailSetResponse" in the JSON response.
          thumbnailKind=""
          thumbnailKind=$(echo $uploadThumbnailOutput | sed 's/"kind"/\'$'\n&/g' | grep -m 1 "kind" | cut -d '"' -f4)

          # Ensure there were no errors.
          if [ "$thumbnailKind" != "youtube#thumbnailSetResponse" ] || [[ $uploadThumbnailOutput == *"\"error\":"* ]] || [[ $uploadThumbnailOutput == *"\"errors\":"* ]]
          then
            LogMessage "err" "Error uploading thumbnail to video $thisBroadcastId. Output was $uploadThumbnailOutput"
          else
            # GitHub issue #75 - Add the new video stream to the top of our
            # desired playlist.
            if [ "$playlistToClean" = "uploads" ]
            then
              LogMessage "dbg" "Video does not need to be added to playlist $playlistToClean because new video streams will always be added there."
            else
              LogMessage "dbg" "Adding video $thisBroadcastId to the top of playlist $playlistToClean"
              
              # Get the playlist that we want to work on. This code is similar to
              # what's in CrowCamCleanup.sh, so look there for an explanation of
              # all this needlessly-complicated stuff.
              curlUrl="https://www.googleapis.com/youtube/v3/channels?part=contentDetails,id&mine=true&access_token=$accessToken"
              channelsOutput=""
              channelsOutput=$( curl -s $curlUrl )
              channelId=""
              channelId=$(echo $channelsOutput | sed 's/"id"/\'$'\n&/g' | grep -m 1 "id" | cut -d '"' -f4)
              if test -z "$channelId" 
              then
                LogMessage "err" "The variable channelId came up empty. Error accessing API. Output was $channelsOutput"
              else
                curlUrl="https://www.googleapis.com/youtube/v3/playlists?part=contentDetails,snippet&channelId=$channelId&access_token=$accessToken"
                playlistsOutput=""
                playlistsOutput=$( curl -s $curlUrl )              
                playlistIds=()
                playlistTitles=()
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
                      if [ "${#playlistTitles[@]}" -gt "0" ]
                      then
                        if ! [ "$lineResult" =  "${playlistTitles[ ${#playlistTitles[@]} - 1 ]}" ]
                        then
                          playlistTitles+=( "$lineResult" )
                        fi
                      else
                        playlistTitles+=( "$lineResult" )
                      fi
                    fi
                done <<< "$playlistsOutput"
                if [ "${#playlistIds[@]}" = "0" ]
                then
                  LogMessage "err" "Error - Playlist count is zero, Output was: $playlistsOutput"
                else
                  if [ "${#playlistIds[@]}" != "${#playlistTitles[@]}" ]
                  then
                     LogMessage "err" "Error - Playlist counts unequal, Output was: $playlistsOutput"
                  else
                    playlistTargetId=""
                    for ((i = 0; i < ${#playlistIds[@]}; i++))
                    do
                      if [ "${playlistTitles[$i]}" = "$playlistToClean" ]
                      then
                          playlistTargetId="${playlistIds[$i]}"
                      fi
                    done
                    if test -z "$playlistTargetId" 
                    then
                      LogMessage "err" "The variable playlistTargetId came up empty, Output was: $playlistsOutput"
                    else
                      LogMessage "dbg" "Adding video $thisBroadcastId to playlist ID: $playlistTargetId Title: $playlistToClean"
                      
                      # Finally, we can add it! Note that if you do not supply the
                      # "position": 0 entry in this JSON, it will default to adding
                      # the item at the END of the playlist instead of the beginning.
                      # So we do "position": 0 to keep the playlist in the correct
                      # order which also fixes GitHub issue #78.
                      curlData=""
                      curlData+="{"
                       curlData+="\"snippet\": "
                       curlData+="{"
                         curlData+="\"playlistId\": \"$playlistTargetId\","
                         curlData+="\"position\": 0,"
                         curlData+="\"resourceId\": "
                         curlData+="{"
                           curlData+="\"kind\": \"youtube#video\","
                           curlData+="\"videoId\": \"$thisBroadcastId\""
                         curlData+="}"
                       curlData+="}"
                      curlData+="}"
                      curlUrl="https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&access_token=$accessToken"
                      insertIntoPlaylistsOutput=$( curl -s -m 20 -X POST -H "Content-Type: application/json" -d "$curlData" $curlUrl )
                   
                      # Ensure there were no errors.
                      if [[ $insertIntoPlaylistsOutput == *"\"error\":"* ]] || [[ $insertIntoPlaylistsOutput == *"\"errors\":"* ]]
                      then
                        LogMessage "err" "Error adding video $thisBroadcastId to playlist id $playlistTargetId titled $playlistToClean - Output was $insertIntoPlaylistsOutput"
                      else
                        LogMessage "dbg" "Video added to playlist"
                      fi
                    fi
                  fi
                fi
              fi
            fi
          fi
        fi
      fi  
    fi
  fi
}

