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
  LogMessage "err" "------------- Script $programname is running in debug mode: $debugMode -------------"
fi

# Log current script location and working directory.
LogMessage "dbg" "Script exists in directory: $DIR"
LogMessage "dbg" "Current working directory:  $(pwd)"

# Verify that the necessary external files exist.
if [ ! -e "$apicreds" ]
then
  LogMessage "err" "Missing file $apicreds"
  exit 1
fi
if [ ! -e "$executable" ]
then
  LogMessage "err" "Missing file $executable"
  exit 1
fi

# Get API creds out of the external file, assert values are non-blank.
# TO DO: Learn the correct linux-supported method for storing and retrieving
# a username and password in an encrypted way.
read username password < "$apicreds"
if [ -z "$username" ] || [ -z "$password" ]
then
  LogMessage "err" "Problem obtaining API credentials from external file"
fi

# Randomly pause between 0 and X seconds. This is an attempt to prevent this
# program from running afoul of the YouTube bot detectors. Probably won't help.
pauseSeconds=$(( ( RANDOM % $pauseSecondsUpperBound )  + 1 ))
LogMessage "dbg" "Pausing for a random amount of seconds (in this case $pauseSeconds seconds) before performing tasks"
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
  LogMessage "dbg" "$serviceName is not running. Exiting program"
  exit 0
fi

# -----------------------------------------------------------------------------
# Check the status of the YouTube Streaming feature.
# -----------------------------------------------------------------------------
currentStreamState=$( IsStreamRunning )
if ! [ "$currentStreamState" = true ]
then
  # If the stream is not set to be "up" right now, then do nothing and exit the
  # program. We only need to be keep the stream alive if the stream is up.
  LogMessage "dbg" "Live stream is not currently turned on. Will not perform the Keep Alive operation on the stream"
  exit 0
fi

# -----------------------------------------------------------------------------
# Update the youtube-dl executable from the internet site.
# -----------------------------------------------------------------------------
executableUpdateUrl="https://yt-dl.org/downloads/latest/$executableFilenameOnly"

# Pre-clean the temporary download file.
rm -f "$executable.temp"

# Download the update file. It is simply the actual loose executable file.
LogMessage "dbg" "wget $executableUpdateUrl -q -O $executable.temp"
                  wget $executableUpdateUrl -q -O "$executable.temp"

# Check to make sure that some file was downloaded at all.
if [ ! -f "$executable.temp" ]
then
  LogMessage "dbg" "Error: Unable to download $executableFilenameOnly. File did not exist after download. Will not update the file"
else
  # Check to make sure the file is nonzero and it is not an HTML error.
  # File size if the file is successful will be either about 1758665 bytes on
  # Linux or 8045118 bytes on Windows, whereas, if the file is an HTML error
  # message then the file will be more like 85440 bytes of HTML text. So check
  # to see if the file is large enough.
  minimumsize=1000000
  actualsize=$(wc -c <"$executable.temp")
  LogMessage "dbg" "Downloaded file was $actualsize bytes"
  if [ $actualsize -ge $minimumsize ]; then
    # Log download success.
    LogMessage "dbg" "File $executableFilenameOnly was successfully downloaded, copying into place"
    
    # Copy the file into its final resting place. The "\" before "cp" unaliases the
    # command and forces it to work without prompting for an overwrite. More info
    # can be found in these locations:
    # https://www.rapidtables.com/code/linux/cp/cp-overwrite.html
    # https://stackoverflow.com/a/8488292/3621748
    \cp "$executable.temp" "$executable"

    # Set the file permissions on the copied file.
    LogMessage "dbg" "chmod 770 $executable"
                      chmod 770 "$executable"

    # Post-clean the temporary download file, but only in the success case.
    # In the failure case, leave the file behind for forensics.
    rm -f "$executable.temp"
  else
    LogMessage "dbg" "Error: Unable to download $executableFilenameOnly. File was not large enough after download. Will not update the file. Check for possible problems with website certificate for $executableUpdateUrl"
  fi
fi

# -----------------------------------------------------------------------------
# Log a non-debug error message if the youtube-dl file is out of date.
# -----------------------------------------------------------------------------

# Improve log messages related to GitHub issue #66. When the site which hosts
# the latest copy of YouTube-DL is having problems, then the log gets filled
# up with too many error messages. Reduce the number of log messages during
# the initial hours of the problems (change the messages above to all
# debug-only), and hope that, whatever problem they're having (an expired cert
# in the issue #66 case), it's fixed within the time range defined below. If
# they haven't fixed it by that time, THEN start writing non-debug errors to
# the log.
#
# To look up the file age, use the Bash "find" statement with the "-mmin"
# parameter (search based on the file age in minutes). The "+" symbol before
# the ageLimit indicates that the statement should return "true" if the file
# is *older* than the indicated age. This was obtained from this StackOverflow
# answer: https://stackoverflow.com/a/552750/3621748
# However, that StackOverflow answer contains a fatal flaw which is not
# discussed there. There is a problem where the listed answer will not work
# if the path of the file contains a space. Instead, we must deviate from the
# StackOverflow answer a little bit. Here's why: When it fails to find a file
# of the appropriate age, it will return a null string, i.e., "false", and
# when it finds a file of the appropriate age, it will return a string of the
# file name including the path. This is usually OK for a true/false test,
# since a nonblank string is considered "true" by the "if" statement, EXCEPT
# if the path contains a space. In that case, it returns two unquoted strings
# separated by a space, which would cause a "Unary Operator Expected" error
# message if you don't put quotes in the right places. In this case, the
# quotes have to be around the call to the "find" command, because what we
# are quoting is the RETURN VALUE that the find command returns, as well as
# quoting the filename we're passing into it, like this:
#        "$( find "$filename" params )"
# I don't know why the double-nested double-quotes work there, but they do.
# Also, the test can no longer be a straight true/false, it must now be a
# test for a null string comparison in order to work correctly:
#        [ "$( find "$filename" params )" != "" ]
# Thanks to Shonky from the EmpegBBS for understanding and explaining this
# tricky issue: https://empegbbs.com/ubbthreads.php/topics/371885
executableAgeLimit=4320 # 4320 minutes is 72 hours (3 days) of age.
if [ ! -f "$executable" ] || [ "$( find "$executable" -mmin +$executableAgeLimit )" != "" ]
then
  # If the problem exists, only log the problem late at night. If we logged
  # this issue every time there was a failure, it would be too much noise in
  # the Synology logs. But it's important to know if there is a failure, so I
  # still want a failure log sometimes. The compromise is to log it to the
  # Synology system log only during the midnight hour.
  currentHour=$( date +"%H" )
  if [ "$currentHour" = "00" ]
  then
    LogMessage "err" "Error: Unable to download $executableFilenameOnly recently. Check for possible problems with the website or the certificate for $executableUpdateUrl"
  fi
fi

# -----------------------------------------------------------------------------
# Perform the keep-alive operation.
# -----------------------------------------------------------------------------

# Pre-clean the temporary downloaded file, including a partial copy if any.
rm -f $tempFile
rm -f $tempFile.part

# Log that we will be doing our task.
LogMessage "dbg" "Downloading $youTubeUrl"

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
#    LogMessage "dbg" "timeout -s 2 -k $secondsToDownload $secondsToDownload \"$executable\"" --hls-prefer-native --external-downloader wget $youTubeUrl -o $tempFile"
#                      timeout -s 2 -k $secondsToDownload $secondsToDownload "$executable" --hls-prefer-native --external-downloader wget $youTubeUrl -o $tempFile 
# 
# New work-around:
#
#   Use this parameter to youtube-dl to "get" just the final URL to download:
#
#                  -g, --get-url Simulate, quiet but print URL
#
LogMessage "dbg" "\"$executable\" $youTubeUrl -g"
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
  LogMessage "err" "$executable finished with exit code $errorStatus"
fi

# Bail out of program with an error if finalUrl is blank.
if [ -z "$finalUrl" ]
then
  LogMessage "err" "No final URL was obtained from $executable. Exiting program"
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
  LogMessage "dbg" "wget $finalUrl -q -O $tempFile --timeout=10"
                    wget $finalUrl -q -O $tempFile --timeout=10
else
  # Standard way of running the download, using timeout to limit its length.
  LogMessage "dbg" "timeout -s 2 -k $secondsToDownload $secondsToDownload wget $finalUrl -q -O $tempFile --timeout=10"
                    timeout -s 2 -k $secondsToDownload $secondsToDownload wget $finalUrl -q -O $tempFile --timeout=10
fi

# Post-clean the temporary downloaded file, including a partial copy, if any.
# When testing the script, leave the files behind for post-mortem examination.
if [ -z "$debugMode" ]
then
  rm -f $tempFile
  rm -f $tempFile.part
else
  LogMessage "dbg" "Debug mode - downloaded file (if any) is left in $tempFile"
fi

# Log completion of task.
LogMessage "dbg" "Complete"

