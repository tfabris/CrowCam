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
  # Log message to shell console, only when we are in debug mode.
  if [ ! -z "$debugMode" ]
  then
    # Echo to STDERR on purpose, and add the period on purpose, to mimic the 
    # behavior of the Synology log entry, below.
    echo "$programname - $2." >&2
  fi

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
      LogMessage "dbg" "Access Token retrieved."
  fi
}

