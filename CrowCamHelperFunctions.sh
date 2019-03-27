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
# Function: Log message to console and Synology log both.
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
# STDOUT, then if I call logMessage from within any of my functions which
# return values to the caller, then the log message output becomes the return
# data, and messes everything up. TO DO: Learn the correct way of doing both at
# the same time in Bash.
#------------------------------------------------------------------------------
logMessage()
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
    # Only log to Synology system log if we are running on Synology.
    if [ -z "$debugMode" ] || [[ $debugMode == *"Synology"* ]]
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
    logMessage "dbg" "Cookie file not present - authenticating"
    WebApiAuth
  fi

  # Make the web API call.
  logMessage "dbg" "Calling: wget -qO- $cookieParametersStandard \"$webApiRootUrl/$1\""
                webResult=$( wget -qO- $cookieParametersStandard "$webApiRootUrl/$1" )
  logMessage "dbg" "Response: $webResult"

  # Check to make sure our call to the web API succeeded, if not, perform a
  # single re-auth and try again. This situation can occur if a cookie already
  # existed but it had expired and thus we needed to re-auth.
  if ! [[ $webResult == *"\"success\":true"* ]]
  then
    logMessage "dbg" "The call to the Synology Web API failed. Attempting to re-authenticate"
    WebApiAuth
    logMessage "dbg" "Re-Calling: wget -qO- $cookieParametersStandard \"$webApiRootUrl/$1\""
                     webResult=$( wget -qO- $cookieParametersStandard "$webApiRootUrl/$1" )
    logMessage "dbg" "Response: $webResult"
  fi

  # Check to make sure our call to the web API succeeded, exit if not.
  if ! [[ $webResult == *"\"success\":true"* ]]
  then
    logMessage "err" "The call to the Synology Web API failed. Exiting program"

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
  # logMessage "dbg" "Logging into Web API: wget -qO- $cookieParametersAuth \"$webApiRootUrl/$authWebCall\""

  # Make the web API call. The expected response from this call will be
  # {"success":true}. Note: The response is more detailed in version=3 but I
  # had some problems with other calls in version=3 so I went back down to
  # version=1 on all calls.
  authResult=$( wget -qO- $cookieParametersAuth "$webApiRootUrl/$authWebCall" )

  # Output for local machine test runs.
  logMessage "dbg" "Response: $authResult"

  # Check to make sure our call to the web API succeeded, exit if not.
  if ! [[ $authResult == *"\"success\":true"* ]]
  then
    logMessage "err" "The call to authenticate with the Synology Web API failed. Exiting program. Response: $authResult"

    # Work-around to problem of being unable to exit the script from within
    # this function. Send kill signal to mid level PID and then exit
    # the function to prevent additional commands from being executed.
    kill -s TERM $WEBAPICALL_PID
    exit 1
  fi
}






