#!/bin/bash

#------------------------------------------------------------------------------
# CrowCam.sh - A Bash script to control and maintain our CrowCam.
#------------------------------------------------------------------------------
# IMPORTANT:
#
# Please see the accompanying file "REAMDE.md" for how use this script. It
# contains detailed instructions regarding how to set up and configure all of
# the scripts in this project. The scripts in this project don't work "out of
# the box", they need some configuration. All details are found in the file
# "README.md", so please look there and follow the instructions.
#------------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# Workaround to allow exiting a Bash script from inside a function call. See
# this EmpegBBS post for details of how this works and why it's needed:
# https://empegbbs.com/ubbthreads.php/topics/371554
# ----------------------------------------------------------------------------
# Set a trap to receive a TERM signal from a function, and execute the code
# block "exit 1", in the context of the top-level of this Bash script, as soon
# as it receives it the TERM signal.
trap "exit 1" TERM

# Create an exported environment variable named "TOP_PID" and populate it with
# the PID of this top-level Bash script. Use "$$" to identify the top level
# PID of this script. The function will use "$TOP_PID" to identify which PID to
# send the TERM signal to, once a program exit is desired.
export TOP_PID=$$

# ----------------------------------------------------------------------------
# Basic startup configuration variables 
# ----------------------------------------------------------------------------

# Configure debug mode for testing this script. Set this value to blank "" for
# running in the final functional mode on the Synology Task Scheduler.
debugMode=""         # True final runtime mode for Synology.
# debugMode="Synology" # Test on Synology SSH prompt, console or redirect output.
# debugMode="MacHome"  # Test on Mac at home, LAN connection to Synology.
# debugMode="MacAway"  # Test on Mac away from home, no connection to Synology.
# debugMode="WinAway"  # In the jungle, the mighty jungle.

# Program name used in log messages.
programname="CrowCam Controller"

# URL of the YouTube live stream that we are controlling. This must be the
# live stream's main parent URL, not the address of an individual video within
# the channel. (For instance, not an archived video.)
youTubeUrl="https://www.youtube.com/channel/UCqPZGFtBau8rm7wnScxdA3g/live"

# Get the directory of the current script so that we can find files in the
# same folder as this script, regardless of the current working directory. The
# technique was learned from the following post:
# https://stackoverflow.com/questions/59895/get-the-source-directory-of-a-bash-script-from-within-the-script-itself
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Create a variable for the youtube-dl executable.
executable="$DIR/youtube-dl"

# Create a variable for the API credentials file. The file itself must be
# created by you. The file should contain the user name and password that will
# be used for connecting to the Synology API. Make sure to create this file
# and place it in the same directory as this script. It should be one line of
# ASCII text: The username, a space, then the password.
apicreds="$DIR/api-creds"

# Set "location" to your actual location. Can be a zip code, a city name, or
# something else which might result in a Google search that returns the correct
# sunrise or sunset time. Must not have any spaces in the location string.
# It simply searches Google with a search string where the word "Sunrise" or
# "Sunset" precedes this location string. Examples: 
#   location="98125"        Google search will be "Sunrise 98125" etc.
#   location="Seattle,WA"   Google search will be "Sunrise Seattle,WA" etc.
#   location="Bangladesh"   Google search will be "Sunset Bangladesh" etc.
# Special bonus: If you leave the location blank (""), Google will just search
# on the word "Sunrise" or "Sunset" and automatically attempt to work out your
# location based on where the query is originating from. Maybe this will work
# for your particular situation, feel free to experiment with leaving it blank.
location=""

# Some sugar required for Wget to successfully retrieve a result from Google.
# Without this, Google gives you a "403 forbidden" message when you try to
# use Wget to perform a Google search.
userAgent="Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.103 Safari/537.36"

# Name of the Synology Surveillance Station service that we are checking, to
# see if it is up (if the service is not up, we will not do anything).
serviceName="pkgctl-SurveillanceStation"

# If testing on Mac, check this instead. Close or open Chrome to test.
if [[ $debugMode == *"Mac"* ]]
then
  serviceName="Google Chrome"
fi

# If testing on Windows, check this instead. Stop or start service to test.
if [[ $debugMode == *"Win"* ]]
then
  serviceName="Adobe Acrobat Update Service"
fi

# Base URL of the API of the Synology NAS we are accessing, from the point of
# view of the script running on the NAS itself (i.e., loopback/localhost)
webApiRootUrl="http://localhost:5000/webapi"

# Alternate version of the URL if we are accessing it from a shell prompt on
# a test computer located on the same LAN as the Synology NAS, in test mode.
if [[ $debugMode == *"Home"* ]]
then
  webApiRootUrl="http://192.168.0.88:5000/webapi"
fi

# Name of the "YouTube Live Broadcast" feature that we are turning on and off.
# This string is only used in log messages.
featureName="YouTube Live Broadcast"

# Cookie file name that will save the login/auth cookie for the web API. This
# allows subsequent calls to the Synology API to succeed after the initial
# authentication has been successful. Subsequent calls simply use the cookie.
cookieFileName="wgetcookies.txt"

# DNS name that we will ping to see if the network is up. Sorry Google, but
# you're the most reliable. I'll try not to hammer you too hard.
TestSite="google.com"

# Number of times we will loop and retest for network problems. Use this,
# combined with the pause between tests, to determine the length of time this
# script will run in normal conditions. For instance, you could program it to
# perform a test every 20 seconds with 3 tests, then set the Task Scheduler to
# run the script every minute. Each run of the script will perform a test at
# 0sec, 20sec and at 40sec during that minute, and then the next run of the
# script falling at 0sec of the next minute will start the cycle over again.
NumberOfTests=3

# Number of seconds to pause between network-up-check tests.
PauseBetweenTests=20

# When in test mode, pause for a shorter period between network checks.
if [ ! -z "$debugMode" ]
then
  PauseBetweenTests=1
fi

# Number of retries that the script will perform, to wait for the network to
# come back up, before giving up and bouncing the stream anyway. These retries
# will be performed at the same interval as the main network test (it uses the
# same pause between tests). For instance, if you set the PauseBetweenTests to
# 20 seconds, and then set this value to 30, it will continue to retry and look
# for the network to come back up for about ten minutes before giving up and
# bouncing the network stream anyway.
MaxComebackRetries=30

# Set this global variable to a starting integer value. There is a possible
# condition in the code if we are in test mode where we might test the value
# once before any value has been set for it. The issue is not harmful to the
# program, but this line will prevent an error message of "integer expression
# expected" at the wrong moment.
restoreLoop=0

# This is the normal default value for this variable.
TestModeFailOnLoop=0

# Debugging mode - Test/debug runs only - To induce the network failure
# behavior, uncomment this line and set this value to fall somewhere between
# 1 and the NumberOfTests.
# TestModeFailOnLoop=2

# This variable is used during test runs only - To cause the test to come back
# again after a certain number of retries, set this to the number of retries
# where you want the network to come back during your test run. It does not
# affect the program unless you are in test mode.
TestModeComeBackOnRetry=1

# Difference, in minutes, that you want to perform the startup and shutdown of
# the video stream during any given day. Negative numbers are preceding the
# event, and positive numbers are after the event. For instance,
# startServiceOffset=-30 means that the stream will start 30 minutes before
# the (approximate) sunrise. stopServiceOffset=60 means that the stream will
# stop 60 minutes after the (approximate) sunset.
startServiceOffset=0
stopServiceOffset=15

# The arrays of approximate sunrise/sunset data to use if the script is unable
# to connect to Google to obtain accurate data. These values are the
# "fallback" values which are less accurate than the Google results. Please
# note: These values are:
#   - Very very approximate.
#   - Do not change every day, they only change once a month.
#   - They are based on the 15th of each month.
#   - They follow the DST change, for example jumping an hour in
#     March and November. 
#   - Will be even more approximate near the DST change date.
#   - Are for location: Seattle, WA. Look up your own location's
#     data at: https://www.timeanddate.com/sun/country/yourcityname
#     and fill in the tables yourself.
sunriseArray[1]="07:52"
sunriseArray[2]="07:15"
sunriseArray[3]="07:22"
sunriseArray[4]="06:20"
sunriseArray[5]="05:32"
sunriseArray[6]="05:11"
sunriseArray[7]="05:27"
sunriseArray[8]="06:05"
sunriseArray[9]="06:46"
sunriseArray[10]="07:28"
sunriseArray[11]="07:14"
sunriseArray[12]="07:50"

sunsetArray[1]="16:45"
sunsetArray[2]="17:32"
sunsetArray[3]="19:14"
sunsetArray[4]="19:58"
sunsetArray[5]="20:40"
sunsetArray[6]="21:08"
sunsetArray[7]="21:03"
sunsetArray[8]="20:21"
sunsetArray[9]="19:21"
sunsetArray[10]="18:21"
sunsetArray[11]="16:32"
sunsetArray[12]="16:18"


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
# NOTE: I'm logging to the STDERR channel (>&2) as a work-around to a
# problem where there doesn't appear to be a Bash-compatible way to combine
# console logging and capturing STDOUT from a function call. The only way I
# can figure out how to return a string from a function call and yet also be
# able to ECHO any logging from within that function call because if I log
# to STDOUT then the log becomes the return call from the function and
# messes everything up.
#------------------------------------------------------------------------------
logMessage()
{
  # Log message to shell console under the appropriate circumstances.
  if [ ! -z "$debugMode" ]
  then
    echo "$programname - $2." >&2
  fi

  # Only log to synology if the log level is not "dbg"
  if ! [ "$1" = dbg ]
  then
    # Only log to Synology system log if we are running on Synology.
    if [ -z "$debugMode" ] || [[ $debugMode == *"Synology"* ]]
    then 
      # Special command on Synology to write to its main log file.
      synologset1 sys $1 0x11800000 "$programname - $2"
    fi
  fi
}

# ----------------------------------------------------------------------------
# Function: Test_Stream
# 
# Performs a single check to see if the YouTube live stream is up, and sets
# the global variable $StreamIsUp to either "true" or "false".
#
# Recommend only calling this function shortly after having called
# Test_Network, since it's only useful if the network is up.
# ----------------------------------------------------------------------------
Test_Stream()
{
  # Start by assuming the stream is up, and set the value to true, then set it
  # to false below if any of our failure conditions are hit.
  StreamIsUp=true

  # Check the global variable $NetworkIsUp and see if it's true. This function
  # is only useful if the network is up. 
  if "$NetworkIsUp" = true
  then
    logMessage "dbg" "Network is up, checking if live stream is up"
  else
    # If the network is down, assume the stream must be down too, and stop
    # trying to do anything else here, just return back to the caller.
    StreamIsUp=false
    logMessage "dbg" "Network is down, assuming live stream must also be down"
    return
  fi

  # Use youtube-dl to perform the first step of attempting to download the
  # live stream, just enough to either get an error message or not. This is
  # the minimum work needed to find out if the stream is alive or not. It
  # uses this parameter to youtube-dl to "get" the final URL of the stream.
  #         -g, --get-url Simulate, quiet but print URL
  # This will either retrieve a valid URL for the stream, or fail with an
  # error message.
  #      logMessage "dbg" "\"$executable\" $youTubeUrl -g"
                 finalUrl=$("$executable" $youTubeUrl -g  2>&1 )
                 errorStatus=$?

  # Because the command above used the "2>&1" construct, then the resulting
  # variable will contain either the valid URL, or the error message. Also
  # the return code from youtube-dl will most likely be nonzero if an error
  # was hit. If either of those things are the case, report a downed stream.
  if [[ $errorStatus != 0 ]]
  then
    logMessage "dbg" "$executable finished with exit code $errorStatus, live stream is down"
    StreamIsUp=false
  fi

  # I doubt the URL will be empty, I figure it will either be a valid URL
  # or it will be the text of an error message. But if it happens to be
  # blank, that would also mean the stream is probably down.
  if [ -z "$finalUrl" ]
  then
    logMessage "dbg" "No URL was obtained from $executable, live stream is down"
    StreamIsUp=false
  fi

  # If the URL variable contains the word "error" anywhere in it, then an
  # error message was returned into the variable instead of a URL, stream is
  # probably down. The most likely error message would be "ERROR: This video
  # is unavailable." but there could be others. 
  if [[ $finalUrl == *"ERROR"* ]] || [[ $finalUrl == *"error"* ]] || [[ $finalUrl == *"Error"* ]]
  then
    logMessage "dbg" "$executable returned an error, live stream is down"
    StreamIsUp=false
  fi

  # Debugging only, print the results of the $finalUrl variable:
  #   logMessage "dbg" "Variable finalUrl was: $finalUrl"

  # If we haven't hit one of our failure modes, the stream is likely up.
  if "$StreamIsUp" = true
  then
    logMessage "dbg" "Live stream is up"
  fi
}


# ----------------------------------------------------------------------------
# Function: Test_Network
# 
# Performs a single check to see if the network is up and sets the global
# variable $NetworkIsUp to either "true" or "false".
# ----------------------------------------------------------------------------
Test_Network()
{
  # Special code for test mode to induce a fake network problem.
  if [ "$mainLoop" -eq "$TestModeFailOnLoop" ]
  then
    # In test mode, set a nonexistent web site name to make it fail
    ThisTestSite="aslksdkhskh.com"
    if [ "$restoreLoop" -eq "$TestModeComeBackOnRetry" ]
    then
      # In test mode, make the real web site come back after a certain number
      # of retries so that it simulates the network coming back up again.
      ThisTestSite="$TestSite"
    fi
  else 
    # If we are not in test mode, use the real web site name all the time.
    ThisTestSite="$TestSite"
  fi

  # Message for local test runs.
  logMessage "dbg" "Testing $ThisTestSite on loop number $mainLoop"

  # Preset the global variable $NetworkIsUp to assume "true" unless proven
  # otherwise by the tests below.
  NetworkIsUp=true

  # The ping command differs on Windows (but it's the same on Linux and Mac),
  # so we must have an alternate version if we are testing on Windows.
  if [[ $debugMode == *"Win"* ]]
  then
    # Windows version of ping test.
    pingResult=$( PING -n 1 $ThisTestSite)
    if [[ $pingResult == *'TTL='* ]]
    then
      NetworkIsUp=true
    else
      NetworkIsUp=false
    fi
  else
    # This version of the Ping command works on both Linux and Mac.
    if ping -q -c 1 -W 15 $ThisTestSite >/dev/null
    then
      NetworkIsUp=true      
    else
      NetworkIsUp=false
    fi
  fi

  # Message for local test runs.
  if "$NetworkIsUp" = true
  then
    # Note that there is a more serious message which appears in the log,
    # triggered elsewhere in the code, when the network is down, so a log
    # message for network failure is not needed here, only for success.
    logMessage "dbg" "Network is up on loop number $mainLoop"
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

  # Version of service check command for testing on Mac.
  if [[ $debugMode == *"Mac"* ]]
  then
    pgrep -xq -- "${serviceName}"
    ReturnCode=$?
  fi

  # Version of service check command for testing on Windows
  if [[ $debugMode == *"Win"* ]]
  then
    net start | grep -q "$serviceName"
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

  # Log to console for local machine test runs.
  logMessage "dbg" "Calling: wget -qO- $cookieParametersStandard \"$webApiRootUrl/$1\""

  # Make the web API call.
  webResult=$( wget -qO- $cookieParametersStandard "$webApiRootUrl/$1" )

  # Log to console for local machine test runs.
  logMessage "dbg" "Response: $webResult"

  # Check to make sure our call to the web API succeeded, if not, perform a
  # single auth and try again.
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

  # Create string for authenticating with Synology Web API.
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
    # Create the query URL that we will use for Google.
    googleQueryUrl="http://www.google.com/search?q=$1%20$location"

    # Perform the query on the URL, and place the HTML results into a variable.
    googleQueryResult=$( wget -L -qO- --user-agent="$userAgent" "$googleQueryUrl" )

    # Alternate version that uses Curl instead of Wget, if needed.
    # googleQueryResult=$( curl -L -A "$userAgent" -s "$googleQueryUrl" )
    
    # Parse the HTML for our answer, and echo the result back to the caller.
    #
    # Parsing statement detailed explanation:
    #
    # Split the HTML output and insert a newline everywhere the string
    # "w-answer-desktop" appears ("w-answer-desktop" is the "answer box"
    # section of the resulting google HTML).
    #         Linux version:
    #           sed 's/w-answer-desktop/\n&/g'
    #         MacOS version:
    #           sed 's/w-answer-desktop/\'$'\n&/g'
    #         (On MacOS "\n" is not interpreted as newline. The weird syntax
    #         causes an actual newline to be directly inserted into sed.)
    #
    # Return only lines which contain "w-answer-desktop" and return only the
    # first result of those lines if there is more than one.
    #         grep -m 1 w-answer-desktop
    #
    # In the resulting line, use a regex to parse out the exact time string
    # which appeared in the google search result.
    #         Linux version:
    #           grep -o -P '\d+:\d+ [AP]M'
    #         MacOS version:
    #           grep -o '[0-9][0-9]*:[0-9][0-9] [AP]M'
    #         (On MacOS the "-P" parameter does not work, so you can't use
    #         the \d+ command on MacOS)
    # 
    # Breaking down that last grep statement further, the parameters are:
    #         -o            Output the matched regex section rather than the
    #                       whole line.
    #         -P            Use perl-style regex. Required for \d+ to work.
    #         \d+           Look for a group of integer digits (Linux).
    #         [0-9][0-9]*   Look for 1 or more integer digits (MacOS).
    #         :             Look for a colon.
    #         \d+           Look for a second group of integer digits (Linux).
    #         [0-9][0-9]    Look for exactly two integer digits (MacOS).
    #                       Look for a space.
    #         [AP]          Look for a capital letter A or a capital letter P.
    #         M             Look for the capital letter M.
    # This should get everything like "7:25 AM" or "10:00 PM" etc.
    #
    # Note: Uncomment only one of the two statements below.

    # Linux Version:
    # echo $googleQueryResult | sed 's/w-answer-desktop/\n&/g' | grep -m 1 w-answer-desktop | grep -o -P '\d+:\d+ [AP]M'

    # MacOs Version - Also works on Linux:
    echo $googleQueryResult | sed 's/w-answer-desktop/\'$'\n&/g' | grep -m 1 w-answer-desktop | grep -o '[0-9][0-9]*:[0-9][0-9] [AP]M'
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
# https://stackoverflow.com/questions/2181712/simple-way-to-convert-hhmmss-hoursminutesseconds-split-seconds-to-seconds
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
# Function: Convert a number of seconds duration into HH:MM format.
# 
# Parameters: $1 = integer of the number of seconds since midnight
#
# Returns: Formatted time string in HH:MM format.
#
# Technique gleaned from:
# https://unix.stackexchange.com/questions/27013/displaying-seconds-as-days-hours-mins-seconds
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
  printf "%02d:%02d\n" $H $M
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
# Function: Change YouTube Stream to down or up depending on its current state.
# 
# Parameters: $1 - "down" if it should be down, "up" if it should be up.
#             $2 - Additional string message describing the expected state such
#                  as "We are before our sunrise start time" or some such. Do
#                  not include a period at the end of the sentence.
#
# Returns: nothing. Will log some string output to the console sometimes.
#------------------------------------------------------------------------------
ChangeStreamState()
{
  # Check (and if necessary, change) the status of the Synology Surveillance
  # Station "Live Broadcast" feature. But only if we are running on the
  # Synology or at least at home where we can access the API on the local
  # LAN. If not, then simply return from this function without doing anything.
  if [ -z "$debugMode" ] || [[ $debugMode == *"Home"* ]] || [[ $debugMode == *"Synology"* ]]
  then
    logMessage "dbg" "Checking status of $featureName feature"
  else
    logMessage "dbg" "$2. But we're in test mode, and not in a position to check or change the stream state"
    return
  fi

  # The response of this call will list all data for the YouTube live
  # stream upload as it is configured in Surveillance Station "Live Broadcast"
  # screen. The response will look something like this:
  # {"data":{"cam_id":1,"connect":false,"key":"xxxx-xxxx-xxxx-xxxx",
  # "live_on":false,"rtmp_path":"rtmp://a.rtmp.youtube.com/live2",
  # "stream_profile":0},"success":true}. We are looking specifically for
  # "live_on":false or "live_on":true here. 
  streamStatus=$( WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&version=1&method=Load" )

  # Set the variable that tracks the current stream up/down state based on the
  # response to the API call above. To check if the stream is up, look for
  # "live_on"=true in the response string.
  if [[ $streamStatus == *"\"live_on\":true"* ]]
  then
    currentStreamState="true"
  else
    currentStreamState="false"
  fi

  if [ "$currentStreamState" = true ] && [ $1 = "up" ]
  then
    # Message for local machine test runs.
    logMessage "dbg" "$2. $featureName is up. It should be $1 at this time. Nothing to do"
  fi

  if [ "$currentStreamState" = false ] && [ $1 = "up" ]
  then
    logMessage "info" "$2. $featureName is down. It should be $1 at this time. Starting stream"

    # Bring the stream back up. Start it here by using the "Save" method to
    # set live_on=true. Response is expected to be {"success":true}.    
    WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&live_on=true" >/dev/null

    # Insert a deliberate pause after starting the stream, to make sure that
    # YouTube has a chance to get its head together and actually stream some
    # video (it sometimes takes a bit). If we don't do this pause here, we run
    # the risk of starting up the stream but then immediately checking if the
    # stream is up (in the network test section), and discovering the wheels
    # weren't quite turning yet, and then raising a false alarm.
    logMessage "dbg" "Sleeping 20 seconds, to allow for stream startup"
    sleep 20
  fi
  
  if [ "$currentStreamState" = true ] && [ $1 = "down" ]
  then
    logMessage "info" "$2. $featureName is up. It should be $1 at this time. Stopping stream"

    # Stop the stream. Stop it here by using the "Save" method to set
    # live_on=false. Response is expected to be {"success":true}.
    WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&live_on=false" >/dev/null
  fi
  
  if [ "$currentStreamState" = false ] && [ $1 = "down" ]
  then
    # Message for local machine test runs.
    logMessage "dbg" "$2. $featureName is down. It should be $1 at this time. Nothing to do"
  fi
}


#------------------------------------------------------------------------------
# Main program code body.
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

# Get API creds out of the external file, assert values are non-blank.
read username password < "$apicreds"
if [ -z "$username" ] || [ -z "$password" ]
then
  logMessage "err" "problem obtaining API credentials from external file"
fi


# ----------------------------------------------------------------------------
# Check to see if Surveillance Station is even running at all. If not, we are
# likely to be in a place where it is deliberately shut down, so simply exit
# this script entirely. This script should only do its business if
# Surveillance Station is supposed to be up.
#
# Note: To test this, you can issue the following commands to make an
# SSH login into the NAS and stop or start the service at will, like this:
#
#    ssh admin@192.168.0.88
# 
#    (the below stuff needs SUDO only if you do it at the
#     SSH prompt, but SUDO is not needed in Task Scheduler)
#
#    sudo synoservicectl --status pkgctl-SurveillanceStation
#
#    sudo synoservicectl --stop pkgctl-SurveillanceStation
#    
#    sudo synoservicectl --start pkgctl-SurveillanceStation
# ----------------------------------------------------------------------------
currentServiceState=$( IsServiceUp )
if [ "$currentServiceState" = false ]
then
  # Output for local machine test runs.
  logMessage "dbg" "$serviceName is not running. Exiting program"
  exit 0
fi


# ----------------------------------------------------------------------------
# YouTube Stream uptime control section.
#
# First, determine if the YouTube Stream should be up or down at this time of
# day, and set it accordingly.
# ----------------------------------------------------------------------------

# Get the current time string into a variable, but use only hours and minutes.
# This code is deliberately not accurate down to the second.
currentTime="`date +%H:%M`"

# Get the current month so that we can use it to look up our data in the array.
# IMPORTANT TRICK: The dash before the "m" means "do not pad with zeros". This
# is necessary for the index lookup to work and to retrieve the value correctly
# since items preceded with a 0 will be interpreted by Bash as being Octal and
# so values of 08 and 09 will cause an error if we don't put the dash there.
currentMonth="`date +%-m`"

# Obtain the (very approximate) fallback astronomical times from the tables.
sunrise=${sunriseArray[$currentMonth]}
sunset=${sunsetArray[$currentMonth]}

# Get more accurate sunrise/sunset results from Google if available.
googleSunriseString=$(GetSunriseSunsetTimeFromGoogle "Sunrise")
googleSunsetString=$(GetSunriseSunsetTimeFromGoogle "Sunset")

# Make sure the Google responses were non-null and non-empty.
if [ -z "$googleSunriseString" ] || [ -z "$googleSunsetString" ]
then
  logMessage "dbg" "problem obtaining sunrise/sunset from Google. Falling back to hard-coded table"
else
  # If the Google responses were non-empty, use them in place of the fallbacks.
  logMessage "dbg" "using Google-obtained times for sunrise/sunset"
  logMessage "dbg" "Sunrise (table):  $sunrise"
  logMessage "dbg" "Sunrise (Google): $googleSunriseString"
  logMessage "dbg" "Sunset  (table):  $sunset"
  logMessage "dbg" "Sunset  (Google): $googleSunsetString"
  sunrise=$googleSunriseString
  sunset=$googleSunsetString
fi

# Convert our times into seconds.
currentTimeSeconds=$(TimeToSeconds $currentTime)
sunriseSeconds=$(TimeToSeconds $sunrise)
sunsetSeconds=$(TimeToSeconds $sunset)

# Perform math calculations on the times.
sunriseDifferenceSeconds=$( expr $sunriseSeconds - $currentTimeSeconds)
sunsetDifferenceSeconds=$( expr $sunsetSeconds - $currentTimeSeconds)

# Calculate which times of day we should stop and start the stream
startServiceSeconds=$(($sunriseSeconds + $startServiceOffset*60 ))
stopServiceSeconds=$(($sunsetSeconds + $stopServiceOffset*60 ))

# Output - print the results of our calculations to the screen.
logMessage "dbg" "Current time:    $currentTime  ($currentTimeSeconds seconds) in month number $currentMonth"
logMessage "dbg" "Approx Sunrise:  $sunrise  ($sunriseSeconds seconds, difference is $sunriseDifferenceSeconds)"
logMessage "dbg" "Approx Sunset:   $sunset  ($sunsetSeconds seconds, difference is $sunsetDifferenceSeconds)"
logMessage "dbg" ""
logMessage "dbg" "$( OutputTimeDifference $sunriseDifferenceSeconds $(SecondsToTime $sunriseDifferenceSeconds) Sunrise )"
logMessage "dbg" "$( OutputTimeDifference $sunsetDifferenceSeconds $(SecondsToTime $sunsetDifferenceSeconds) Sunset )"
logMessage "dbg" ""
logMessage "dbg" "Will start the stream at about   $startServiceSeconds $(SecondsToTime $startServiceSeconds)"
logMessage "dbg" "Will stop it for the night at    $stopServiceSeconds $(SecondsToTime $stopServiceSeconds)"
logMessage "dbg" ""

# Decide the behavior if we need to stop the stream before sunrise.
if [ $currentTimeSeconds -lt $startServiceSeconds ]
then
  ChangeStreamState "down" "We are before our sunrise/start time"
fi

# Decide the behavior if we need to start the stream after sunrise.
if [ $currentTimeSeconds -ge $startServiceSeconds ] && [ $currentTimeSeconds -lt $stopServiceSeconds ]
then
  ChangeStreamState "up" "We are after our sunrise/start time"
fi

# Decide the behavior if we need to stop the stream after sunset.
if [ $currentTimeSeconds -ge $stopServiceSeconds ]
then
  ChangeStreamState "down" "We are after our sunset/stop time"
fi


# ----------------------------------------------------------------------------
# Bail out if Live Broadcast isn't turned on at this point.
# 
# The "Network Test" section of the code, which is the part following this
# section, should only trigger if the Surveillance Station's Live Broadcast
# feature is already turned on. If it's not on, then we don't care because the
# stream wasn't supposed to be up in the first place.
# ----------------------------------------------------------------------------
# In order to check the status of the Synology Surveillance Station "Live
# Broadcast" feature, we must either not be in debug mode, or if we are,
# we must at least be running either on the Synology or at home where we
# can access the API on the local LAN.
if [ -z "$debugMode" ] || [[ $debugMode == *"Home"* ]] || [[ $debugMode == *"Synology"* ]]
then
  logMessage "dbg" "Checking status of $featureName feature"
else
  logMessage "dbg" "We're in test mode, and not in a position to check or change the stream state, so no network testing will be performed"

  # If we can't check the stream state, then exit the program, the
  # same as if the stream was already supposed to be down anyway.
  exit 0
fi
streamStatus=$( WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&version=1&method=Load" )
if ! [[ $streamStatus == *"\"live_on\":true"* ]]
then
  logMessage "dbg" "Live stream is not currently turned on. Network checking is not needed"
  exit 0
fi


# ----------------------------------------------------------------------------
# Network Test section.
# 
# Checks the network and stream a specified number of times at intervals. If
# either is down, log this fact and then wait for the network to come back up.
# Once it comes back up, bounce the YouTube stream if it didn't also come
# back up itself.
# ----------------------------------------------------------------------------
for mainLoop in `seq 1 $NumberOfTests`
do
  # Test if the Internet is up and if our YouTube live stream is up.
  Test_Network
  Test_Stream

  # Check our initial results
  if [ "$NetworkIsUp" = true ] && [ "$StreamIsUp" = true ]
  then
    # The network and stream are working in this case. Pause before doing the
    # next check.

    # However, do not pause between test runs on the last test of the group.
    # Only pause if we are beneath the "maximum number of tests" ceiling. If
    # we equal or exceed that ceiling, do not pause between tests. (We should
    # never exceed it but it's good programming practice to use this pattern.)
    if [ "$mainLoop" -lt "$NumberOfTests" ]
    then
      # Message for local machine test runs.
      logMessage "dbg" "Sleeping $PauseBetweenTests seconds"

      # Sleep between network tests.
      sleep $PauseBetweenTests
    fi
  else
    # Network or stream is down in this case. Begin waiting, in a loop, for
    # the network to come back up so that we can restart the YouTube stream.
    for restoreLoop in `seq 1 $MaxComebackRetries`
    do
      # Pause before trying to check if the network is back up. In this case,
      # we pause every time because the pause is before the network check.
      logMessage "err" "Network or stream problem. Pausing to give them a chance to come up. Retry number $restoreLoop. Sleeping $PauseBetweenTests seconds before trying again"

      # Pause before every network test when waiting for it to come back. 
      sleep $PauseBetweenTests

      # Test the network and stream again.
      Test_Network
      Test_Stream
      logMessage "info" "Status - Network up: $NetworkIsUp  Stream up: $StreamIsUp"

      # Check if the network has come back up (or maybe it was already up and
      # the stream was the thing that was down) and break out of the retry
      # loop if the network is now up.
      if "$NetworkIsUp" = true
      then
        # Since the network is up, we can break out of our loop of retrying if
        # the network is up. Note that, at this point in the code, we already
        # confirmed something went wrong in either the network or the stream
        # earlier, so at this point we want to fall down into the next section
        # where we might bounce the stream even if the network is now up.
        # Heck, even the stream might have come back up too, but we'll check
        # that below.
        break
      fi
    done

    # If the stream was up after the network came up, then don't bother bouncing it.
    if "$StreamIsUp" = true
    then
      logMessage "info" "YouTube stream appears to be up, no further action needed"
      break
    fi

    # If we have reached this line without hitting a "break" above, it means
    # either the stream or network are still down, thus we are now at the
    # point where we are ready to bounce the stream. It is possible that we
    # either got a success result if the network really did come back up, or,
    # we waited as long as we could and then decided to give up. We need to
    # deliver a different log message depending on whether the network is up,
    # or we just gave up on waiting for it to come back up.
    if "$NetworkIsUp" = true
    then
      # Inform the user that we're bouncing the stream because the network is up.
      logMessage "info" "Bouncing the YouTube stream since the network is up"
    else
      # Inform the user that we gave up trying.
      logMessage "err" "The network is not back up yet. Bouncing YouTube stream anyway"
    fi

    # Two possible ways to fix the YouTube stream if the network has gone
    # down: Either bring the stream down and back up again (with a pause in
    # the middle), or restart the Surveillance Station service.

    # Method 1: Bring the YouTube stream down and back up again. This is the
    # more desirable method because it allows the Surveillance Station service
    # to keep running, in case we are using actual security cameras on it.

    # Bounce the stream. Stop it here by using the "Save" method to set
    # live_on=false. Response is expected to be {"success":true}.
    WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&live_on=false" >/dev/null
    
    # Wait a while to make sure it is really turned off. I had some troubles
    # in testing, where, if I set this number too small, that I would not get
    # a successful stream reset. Now using a nice long chunk of time here to
    # make absolutely sure. This seems to work long-term.
    sleep 95
    
    # Bring the stream back up. Start it here by using the "Save" method to
    # set live_on=true. Response is expected to be {"success":true}.
    WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&live_on=true" >/dev/null

    # Method 2: Restart the Surveillance Station service. This is the less
    # desirable method, because it stops all security camera recording as
    # well. We are not using this method. Keeping it here for posterity so
    # that we remember the syntax.
    #      synoservicectl --restart $serviceName

    # Log that we're done.
    logMessage "info" "Done bouncing YouTube stream"

    # Because we have bounced the YouTube stream, we no longer need to loop
    # around. Break out of the loop, which will finish the last part of the
    # program.
    break
  fi
done

