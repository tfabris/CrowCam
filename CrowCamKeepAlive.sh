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
programname="CrowCam Keep Alive"

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
  logMessage "err" "Problem obtaining API credentials from external file"
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
#    ssh admin@your.nas.address
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
# When testing the script, leave the files behind for post-mortem examination.
if [ -z "$debugMode" ]
then
  rm -f $tempFile
  rm -f $tempFile.part
else
  logMessage "dbg" "Debug mode - downloaded file (if any) is left in $tempFile"
fi

# Log completion of task.
logMessage "dbg" "Complete"

