#!/bin/bash

#------------------------------------------------------------------------------
# CrowCamKeepAlive.sh - Ensures a YouTube stream's DVR functionality works.
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
programname="CrowCam Keep Alive"

# URL of the YouTube live stream that we want to keep alive. This must be
# the live stream's main parent URL, not the address of an individual
# video within the channel. (For instance, not an archived video.)
youTubeUrl="https://www.youtube.com/channel/UCqPZGFtBau8rm7wnScxdA3g/live"

# Get the directory of the current script so that we can find files in the
# same folder as this script, regardless of the current working directory. The
# technique was learned from the following post:
# https://stackoverflow.com/questions/59895/get-the-source-directory-of-a-bash-script-from-within-the-script-itself
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Create a variable for the youtube-dl executable.
executable="$DIR/youtube-dl"

# Slightly different file if testing on Windows PC.
if [[ $debugMode == *"Win"* ]]
then
    executable="$DIR/youtube-dl.exe"
fi

# Create a variable for the API credentials file. The file itself must be
# created by you. The file should contain the user name and password that will
# be used for connecting to the Synology API. Make sure to create this file
# and place it in the same directory as this script. It should be one line of
# ASCII text: The username, a space, then the password.
apicreds="$DIR/api-creds"

# Download only about X seconds of the stream, i.e., run the downloader for
# this long only, and terminate the downloader when this time expires. By the
# way, in the final reckoning, this number ended up being somewhat moot
# because, as it turns out, we didn't really need to download any video stream
# data to keep the channel alive. All that ends up getting downloaded is a
# text file, a metadata index of the stream chunks, rather than the video
# itself. That text file downloads in a split second, so this number (used as
# a timeout ceiling in the code) is rarely, if ever, actually reached. Note
# that this variable is a string because it includes the "s" at the end.
secondsToDownload="20s"

# Length of random time to pause before executing each download, in seconds.
# The pause will be a random number between 0 and this number. Note that this
# variable is an integer. 300 seconds equals five minutes. The random number
# is intended to vary this script's footprint on YouTube, in the hope that this
# will prevent YouTube's bot-detection algorithms from getting mad at this
# script.
pauseSecondsUpperBound=300

# Alternate amount of random time to pause, used for test runs.
if [ ! -z "$debugMode" ]
then
  pauseSecondsUpperBound=5
fi

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

# Temporary file to store the contents of the live stream that we are (for a 
# short time) downloading during this run. The file will get cleaned up at
# the end of the run.
tempFile="CrowCamTemp.mp4"

# Cookie file name that will save the login/auth cookie for the web API. This
# allows subsequent calls to the Synology API to succeed after the initial
# authentication has been successful. Subsequent calls simply use the cookie.
cookieFileName="wgetcookies.txt"


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


#------------------------------------------------------------------------------
# Main program code
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

# Randomly pause between 0 and X seconds. This is an attempt to prevent this
# program from running afoul of the YouTube bot detectors. Probably won't help.
pauseSeconds=$(( ( RANDOM % $pauseSecondsUpperBound )  + 1 ))
logMessage "dbg" "Pausing for a random amount of seconds (in this case $pauseSeconds seconds) before performing tasks"
sleep $pauseSeconds

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

# Check the status of the Synology Surveillance Station "Live Broadcast"
# feature. But only if we are running on the Synology or at least at
# home where we can access the API on the local LAN.
if [ -z "$debugMode" ] || [[ $debugMode == *"Home"* ]] || [[ $debugMode == *"Synology"* ]]
then
  # The response of this call will list all data for the YouTube live stream
  # upload as it is configured in Surveillance Station "Live Broadcast"
  # screen. The response will look something like this:
  # {"data":{"cam_id":1,"connect":false,"key":"xxxx-xxxx-xxxx-xxxx",
  # "live_on":false,"rtmp_path":"rtmp://a.rtmp.youtube.com/live2",
  # "stream_profile":0},"success":true}. We are looking specifically for
  # "live_on":false or "live_on":true here. 
  logMessage "dbg" "Checking status of $featureName feature"
  streamStatus=$( WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&version=1&method=Load" )

  # If the stream is not set to be "up" right now, then do nothing and exit the
  # program. We only need to be downloading the stream if the stream is up. To
  # check if the stream is up, look for "live_on"=true in the response string.
  if ! [[ $streamStatus == *"\"live_on\":true"* ]]
  then
    logMessage "dbg" "Live stream is not currently turned on. Will not perform the Keep Alive operation on the stream"
    exit 0
  fi
fi

# Pre-clean the temporary downloaded file, including a partial copy if any.
rm -f $tempFile
rm -f $tempFile.part

# Log that we will be doing our task.
logMessage "dbg" "Downloading $youTubeUrl"

# Download the video from YouTube for a few seconds.
#
#  Notes on the parameters to the linux "timeout" commands used below:
#
#    "-s 2" is the type of termination signal that we will send to $executable
#    when the timeout is hit. "2" is a simple "SIGINT" command which interrupts
#    the running program while leaving any child processes it may have spawned
#    to finish their jobs. For youtube-dl, it allows any video conversion (such
#    as an ffmpeg conversion) to finish successfully after quitting.
#
#    "-k $secondsToDownload" is how many seconds after we send the termination
#    signal that we will force-kill the process if it didn't actually exit. I'm
#    using the same value for this that I use for the normal amount of seconds.
#
#    The next parameter "$secondsToDownload" (without a preceding letter) is
#    the number of seconds we allow the program to run before sending the -s 2
#    signal to it. This is how many seconds to download the stream under normal
#    circumstances.
#

# WORK AROUND - The below statements should have worked but they have a problem
# on the Synology NAS because...
#
# - Somehow it tries to use ffmpeg to perform its downloading.
#
# - On the Synology NAS, ffmpeg is already preinstalled.
#
# - However on the Synology NAS. ffmpeg is compiled differently than what this
#   program expects it to be.
#
# - So on the Synology NAS when it tries to download it gets this annoying error:
#
#        "https protocol not found, recompile FFmpeg with openssl, gnutls, or
#        securetransport enabled."
#
# - There are command line parameters to youtube-dl which might theoretically
#   help - two of them in fact, --hls-prefer-native and --external-downloader,
#   but neither of them work to fix the issue.
#
# Old commands:
#
#    logMessage "dbg" "timeout -s 2 -k $secondsToDownload $secondsToDownload \"$executable\"" --hls-prefer-native --external-downloader wget $youTubeUrl -o $tempFile"
#                      timeout -s 2 -k $secondsToDownload $secondsToDownload "$executable" --hls-prefer-native --external-downloader wget $youTubeUrl -o $tempFile 
# 
# New work-around:
#
#   Use this parameter to youtube-dl to "get" just the final URL to download:
#
#                  -g, --get-url Simulate, quiet but print URL
#
logMessage "dbg" "\"$executable\" $youTubeUrl -g"
        finalUrl=$("$executable" $youTubeUrl -g )

# Debugging - You can retrieve and log error messages from the output by
# adding 2>&1 to the command. Don't use this for normal runs though, since
# having error text in the URL (instead of a URL) causes bad behavior farther
# down the line.
#   finalUrl=$("$executable" $youTubeUrl -g  2>&1 )

# If the stream is down, youtube-dl responds with "ERROR: This video is
# unavailable." and will return a nonzero exit code. Also, no URL will
# be returned back to the caller.
errorStatus=$?
if [[ $errorStatus != 0 ]]
then
  logMessage "err" "$executable finished with exit code $errorStatus"
fi

# Bail out of program with an error if finalUrl is blank.
if [ -z "$finalUrl" ]
then
  logMessage "err" "No final URL was obtained from $executable. Exiting program"
  exit 1
fi

# Now perform the actual work-around download with wget. Interesting note: for
# live streams, this does not actually download any video, it seems to
# download an ASCII file that indexes segments of the video. I think that for
# saved videos, it will download the actual video, but our program is
# concerned only with a live stream, so we'll get that ASCII index file. In
# any case, my experiments seem to indicate that downloading the index file is
# actually enough to keep the stream alive, so it's perfect for our purposes.
if [[ $debugMode == *"Mac"* ]]
then
  # MacOs version of running the download (no "timeout" command exists on Mac).
  logMessage "dbg" "wget $finalUrl -q -O $tempFile --timeout=10"
                     wget $finalUrl -q -O $tempFile --timeout=10
else
  # Standard way of running the download, using timeout to limit its length.
  logMessage "dbg" "timeout -s 2 -k $secondsToDownload $secondsToDownload wget $finalUrl -q -O $tempFile --timeout=10"
                    timeout -s 2 -k $secondsToDownload $secondsToDownload wget $finalUrl -q -O $tempFile --timeout=10
fi

# Post-clean the temporary downloaded file, including a partial copy, if any.
# When testing the script, leave the files behind for post-mortem
# examination.
if [ -z "$debugMode" ]
then
  rm -f $tempFile
  rm -f $tempFile.part
else
  logMessage "dbg" "Debug mode - downloaded file (if any) is left in $tempFile"
fi

# Log completion of task.
logMessage "dbg" "Complete"

