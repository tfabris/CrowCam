#!/bin/bash

#------------------------------------------------------------------------------
# CrowCam.sh - A Bash script to control and maintain our YouTube stream.
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
programname="CrowCam Controller"

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

# Number of times we will loop and retest for network problems. Use this,
# combined with the pause between tests, to determine the approximate length
# of time this script will run in normal conditions. For instance, you could
# program it to perform a test every 20 seconds with 3 tests, then set the
# Task Scheduler to run the script every minute. Each run of the script will
# perform a test at 0sec, 20sec and at 40sec during that minute, and then the
# next run of the script falling at 0sec of the next minute will start the
# cycle over again. If, during any of these tests, a problem with the network
# is detected, it will bounce the YouTube stream to make the stream start
# working again. Note: This test has no hysteresis - a network problem will
# always trigger a stream bounce. In my experience, all network blips will
# cause the stream to hang, unless I bounce it.
NumberOfTests=6

# Number of seconds to pause between network-up-check tests.
PauseBetweenTests=10

# Number of times we will loop and retest for stream problems if it detects
# that the stream is down. This is a secondary test which will only be run if
# the network is up. This attempts to connect to the stream and retrieve its
# URL. If an error is received, it will perform a small amount of hysteresis
# (repeated tests, controlled by these variables). This hysteresis is needed on
# the stream test, but not the network test, because the stream test has proven
# to be flaky, sometimes reporting a problem when there is actually no problem.
# If, after the hysteresis retries, there is still a problem reported in the
# stream, then we will bounce the stream, even if the network hasn't gone down.
NumberOfStreamTests=6

# Number of seconds to pause between stream-up-check tests.
PauseBetweenStreamTests=15

# When in test mode, pause for a shorter period between tests.
if [ ! -z "$debugMode" ]
then
  PauseBetweenTests=1
  PauseBetweenStreamTests=1
fi

# Number of retries that the script will perform, to wait for the network to
# come back up, after the network went down. Here's how it works: If the
# network went down, and we detected that it went down, then we want to bounce
# the YouTube stream. However, we don't want to bounce it instantly. We want to
# wait until the network is back up again, and then bounce the stream. If the
# network is taking an unexpectedly long time to come back up, then at some
# point we need to decide to just give up and bounce the stream anyway. That
# last part is what this variable controls. It controls how many loops the
# program waits for the network to come back. These loops will be performed at
# the same interval as the main network test (it uses the same PauseBetweenTests
# variable). For instance, if you set PauseBetweenTests to 20 seconds, and then
# set this value to 30, it will continue to retry and look for the network to
# come back up for about ten minutes before bouncing the network stream anyway.
MaxComebackRetries=40

# Set this global variable to a starting integer value. There is a possible
# condition in the code if we are in test mode, where we might test the value
# once before any value has been set for it. The issue is not harmful to the
# program, but this line will prevent an error message of "integer expression
# expected" appearing on the console at the wrong moment.
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


#------------------------------------------------------------------------------
# Function blocks
#------------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# Function: Test_Stream
# 
# Performs a check to see if the YouTube live stream is up, and sets
# the global variable $StreamIsUp to either "true" or "false".
#
# Recommend only calling this function shortly after having called
# Test_Network, since it's only useful if the network is up.
#
# Parameters:  None.
#              Uses some global configuration variables during its run.
#
# Returns:     Nothing.
#              Sets the global variable $StreamIsUp.
#
# This test contains an "inner loop" of hysteresis to prevent false alarms
# about the YouTube stream potentially being down. The process of checking the
# YouTube stream with youtube-dl has proven to be a little bit flaky. Sometimes
# it is unreliable and returns a false alarm. So this will retry a few times
# before officially flagging an issue.
# -----------------------------------------------------------------------------
Test_Stream()
{
  # Debugging message, leave commented out usually.
  # logMessage "info" "Begin Test_Stream"

  # Check the global variable $NetworkIsUp and see if it's true. This function
  # is only useful if the network is up. If the network is down, then return
  # false automatically.
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

  # BUGFIX: Attempt to fix GitHub issue #4. There was a time when the stream
  # got bounced unnecessarily even though everything was actually up and
  # working correctly. My suspicion is that attempting to download the YouTube
  # stream status with YouTube-DL is flaky, and that I need to add some
  # hysteresis here. Adding an inner "Stream testing" loop here, for testing
  # multiple retries to see if the live stream is up, and failing only if all
  # of the tests fail. Bail out of the loop on any success.
  for streamTestLoop in `seq 1 $NumberOfStreamTests`
  do
    # Start by assuming the stream is up, and set the value to true, then set it
    # to false below if any of our failure conditions are hit.
    StreamIsUp=true

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
    # This is the first test, where I am testing if the return code is zero.
    if [[ $errorStatus != 0 ]]
    then
      logMessage "dbg" "$executable finished with exit code $errorStatus, live stream is down"
      StreamIsUp=false
    fi

    # I doubt the URL will be empty, I figure it will either be a valid URL
    # or it will be the text of an error message. But if it happens to be
    # blank, that would also mean the stream is probably down. Return false.
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
      logMessage "dbg" "$executable returned an error message string, live stream is down"
      StreamIsUp=false
    fi

    # Debugging only, print the results of the $finalUrl variable:
    #   logMessage "dbg" "Variable finalUrl was: $finalUrl"

    # Attempted Issue #4 bugfixing - Controlling the pass/fail state of the
    # hysteresis loop here. If we reach this point and get "true", then that
    # is the "good" state and we can bail out. If we get "false" then we have
    # to try again.
    if "$StreamIsUp" = true
    then
      # Break out of the hysteresis loop if the stream is OK.
      break
    fi

    # If we have reached this point then we need to pause and try another
    # hysteresis loop. However, on the last loop, don't pause, just let it
    # drop through since it will bail out the bottom of the loop on the last
    # one.
    if [ "$streamTestLoop" -lt "$NumberOfStreamTests" ]
    then
      # Make this message "info" level so that I can get some data on how
      # often GitHub issue #4 occurs. 
      logMessage "info" "The network is up, but the YouTube stream is down. Pausing to give it a chance to come up. Inner stream test loop, retry attempt $streamTestLoop of $NumberOfStreamTests . Sleeping $PauseBetweenStreamTests seconds before trying again"

      # Sleep between stream tests.
      sleep $PauseBetweenStreamTests
    fi    
  done

  # If we haven't hit one of our failure modes, the stream is likely up.
  if "$StreamIsUp" = true
  then
    # This message is normally a debug message (i.e., doesn't go into the
    # Synology log), unless we have been encountering stream problems, and
    # have had to hit our hysteresis loop above. If we came out of that loop
    # with any number greater than one, then, I want a "stream up" message to
    # appear in the Synology Log that corresponds with the "stream down"
    # message from our hysteresis loop above.
    if [ "$streamTestLoop" -gt "1" ]
    then
      logMessage "info" "Live stream came back up"
    else
      logMessage "dbg" "Live stream is up"
    fi
  fi

  # Debugging message, leave commented out usually.
  # logMessage "info" "Done with Test_Stream" 
}


# ----------------------------------------------------------------------------
# Function: Test_Network
# 
# Performs a single check to see if the network is up and sets the global
# variable $NetworkIsUp to either "true" or "false".
#
# This test is hairtrigger sensitive, and contains no hysteresis algorithm.
# I have found that its method of pinging the DNS name of our reliable ping
# destination is a very good indicator of whether the network has any problems.
# And if the network had any problems at all, even slight ones, my experience
# tells me that the YouTube stream is at high risk of being hung. So we want
# this test to be very hairtrigger.
#
# Parameters:  None.
#              Uses global variables $mainLoop and $restoreLoop among others.
#
# Returns:     Nothing.
#              Sets the global variable $NetworkIsUp
# ----------------------------------------------------------------------------
Test_Network()
{
  # Debugging message, leave commented out usually.
  # logMessage "info" "Beginning Test_Network" 

  # Special code for test mode to induce a fake network problem.
  if [ "$mainLoop" -eq "$TestModeFailOnLoop" ]
  then
    # In test mode, set a nonexistent web site name to make it fail
    ThisTestSite="aslksdkhskh.com"

    # In test mode, make the real web site come back after a certain number
    # of retries so that it simulates the network coming back up again.
    if [ "$restoreLoop" -eq "$TestModeComeBackOnRetry" ]
    then
      ThisTestSite="$TestSite"
    fi
  else 
    # If we are not in test mode, use the real web site name all the time.
    ThisTestSite="$TestSite"
  fi

  # Message for local test runs.
  logMessage "dbg" "Testing $ThisTestSite - outer network test attempt $mainLoop of $NumberOfTests"

  # Preset the global variable $NetworkIsUp to assume "true" unless proven
  # otherwise by the tests below.
  NetworkIsUp=true

  # The ping command differs on Windows (but it's the same on Linux and Mac),
  # so we must have an alternate version if we are testing on Windows.
  if [[ $debugMode == *"Win"* ]]
  then
    # Special handling of windows command needed, in order to make it
    # compatible with multiple different flavors of Bash on Windows. For
    # example, Git Bash will take "PING" directly, but the Linux Subsystem
    # For Windows 10 needs it put into cmd.exe /c in order to work. Also, the
    # backticks are needed or else it doesn't always work properly.
    pingResult=`cmd.exe /c "PING -n 1 $ThisTestSite"`
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
    logMessage "dbg" "Network is up, outer network test attempt $mainLoop of $NumberOfTests"
  fi

  # Debugging message, leave commented out usually.
  # logMessage "info" "Done with Test_Network"
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
    # logMessage "info" "Beginning GetSunriseSunsetTimeFromGoogle" 

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

    # Debugging message, leave commented out usually.
    # logMessage "info" "Done with GetSunriseSunsetTimeFromGoogle"
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
    logMessage "dbg" "$2. But we're not in a position where we can control the stream up/down state"
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

  # Behavior when stream is set to up, at a time when it should be up.
  if [ "$currentStreamState" = true ] && [ $1 = "up" ]
  then
    # Message for local machine test runs.
    logMessage "dbg" "$2. $featureName is up. It should be $1 at this time. Nothing to do"
  fi

  # Behavior when stream is set to down, at a time when it should be up.
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
    logMessage "dbg" "Sleeping briefly, to allow for stream startup"
    sleep 30
  fi
  
  # Behavior when stream is set to up, at a time when it should be down.
  if [ "$currentStreamState" = true ] && [ $1 = "down" ]
  then
    logMessage "info" "$2. $featureName is up. It should be $1 at this time. Stopping stream"

    # Stop the stream. Stop it here by using the "Save" method to set
    # live_on=false. Response is expected to be {"success":true}.
    WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&live_on=false" >/dev/null
  fi
  
  # Behavior when stream is set to down, and it should be down.
  if [ "$currentStreamState" = false ] && [ $1 = "down" ]
  then
    # Message for local machine test runs.
    logMessage "dbg" "$2. $featureName is down. It should be $1 at this time. Nothing to do"
  fi
}


#------------------------------------------------------------------------------
# Function: Bounce the YouTube stream.
# 
# Brings the YouTube stream down, waits a bit, and then brings it up again, by
# using the Synology API to turn the Synology Surveillance Station's "Live
# Broadcast" feature off then on again.
#
# This usually fixes most problems where the YouTube stream has stopped working
# for whatever reason. The most common reason for the stream failing would be
# a blip in the internet service at the site which is hosting the webcam.
#
# It would also be possible to fix stream issues by restarting the Synology
# Surveillance Station service itself, with a command similar to this:
#
#                synoservicectl --restart $serviceName
#
# However that method is not desirable because it would stop all security
# camera recordings, if more than one camera were installed in the system.
# Bouncing the "Live Broadcast" feature is the more desirable method because
# it allows the Surveillance Station Service to keep running, in case we are
# using other security cameras on it. This method allows all cameras to
# continue working and recording to the NAS, while bouncing the YouTube Stream
# portion of the system.
#
# Parameters: None.
# Returns: Nothing.
#------------------------------------------------------------------------------
BounceTheStream()
{
  # Stop the YouTube stream feature here by using the "Save" method to set
  # live_on=false. Response is expected to be {"success":true}.
  WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&live_on=false" >/dev/null
  
  # Wait a while to make sure it is really turned off. I had some troubles
  # in testing, where, if I set this number too small, that I would not get
  # a successful stream reset. Now using a nice long chunk of time here to
  # make absolutely sure. This seems to work long-term.
  logMessage "info" "Pausing, after bringing down the stream, before bringing it up again"
  sleep 95
  
  # Bring the stream back up. Start it here by using the "Save" method to
  # set live_on=true. Response is expected to be {"success":true}.
  WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&live_on=true" >/dev/null

  # Log that we're done.
  logMessage "info" "Done bouncing YouTube stream"

  # If we had to bounce the stream, wait a little while before allowing the
  # program to continue to its exit point. This allows the stream to get
  # spooling up and started, before there is an opportunity for the next
  # Task-scheduled run of this script to get launched. If we don't pause
  # here, we run the risk of possibly having the next run of this script
  # start too soon, before the bounced stream is up and running again, and
  # then detecting a false error at that time.
  #
  # UPDATE: Post-bounce pause should not be needed, for the following reasons:
  # - In the new code flow, the program exits after bouncing the stream.
  # - The next run of the program will occur in the Synology Task Scheduler.
  # - In the new code flow, the program starts out by checking the network
  #   all by itself, without checking the stream, for approximately a minute
  #   or so, before checking the stream status. So the "pause" I would normally
  #   be trying to do here, is actually built in to the next run of the program.
  # - There is also hysteresis built-in to the stream check, so that even after
  #   the "natural pause" described above, there is still some hysteresis for
  #   allowing the stream to come back up and register upness before it panics.
  #
  # UP-UPDATE: Experimentation indicates that we still need a pause. See
  # GitHub Issue #17.
  logMessage "dbg" "Pausing, after bringing the stream back up again, to give the stream a chance to spin up and work"
  sleep 40
}


#------------------------------------------------------------------------------
# Main program code body.
#------------------------------------------------------------------------------

# Log the current test mode state, if activated.
if [ ! -z "$debugMode" ]
then
  logMessage "err" "------------- Script $programname is running in debug mode: $debugMode -------------"
fi

# Debugging message for logging script start/stop times. Leave commented out.
# logMessage "info" "-------------------------- Starting script: $programname -------------------------"

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
# TO DO: Learn the correct linux-supported method for storing and retrieving a
# username and password in an encrypted way.
read username password < "$apicreds"
if [ -z "$username" ] || [ -z "$password" ]
then
  logMessage "err" "Problem obtaining API credentials from external file"
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


# ----------------------------------------------------------------------------
# YouTube Stream uptime control section.
#
# First, determine if the YouTube Stream should be up or down at this time of
# day, and set it accordingly.
# ----------------------------------------------------------------------------

# Get the current time string into a variable, but use only hours and minutes.
# This code is deliberately not accurate down to the second.
currentTime="`date +%H:%M`"

# Convert our current time into seconds-since-midnight.
currentTimeSeconds=$(TimeToSeconds $currentTime)

# Read our fallback values of the sunrise and sunset files from the hard disk.
sunrise=$(< "$crowcamSunrise")
sunset=$(< "$crowcamSunset")

# Address GitHub issue #18 - Reduce the frequency of error messages from the
# Google sunrise/sunset time queries. Here's the concept of how/when the Google
# search query will be done:
#
# - We want to query the sunrise/sunset from Google and write the new values to
#   our fallback files. But we don't want to do this every single time we run
#   the program. We only want to do this approximately once per day.
# 
# - I could just program it to happen every 24 hours, in a whole separate
#   script, run under the Task Scheduler. But I didn't want to write a whole
#   other script. Instead, I'll do a scheme where the repeated nature of *this*
#   script allows for a sort of built-in retry feature, allowing this to work
#   even if the internet connection was down during its normal query window.
# 
# - We'll do this by checking the timestamps of the fallback files that we've
#   written. If the files are clearly from yesterday or older, then, query
#   Google for some new values and write the values to the files.
#
# - But don't simply check for "look if the file is >24hrs old", because then
#   you would get a slow drift each day, where the file gets written a few
#   seconds later each day until finally it wraps around and hits our 3:30am
#   router health-reboot window.
# 
# - Scheme: Only perform the query this if we're post-2pm - This ensures a nice
#   middle-of-the-afternoon check which works for most timezones and latitudes
#   most of the time. This will also ensure we're looking at the upcoming
#   sunrise time (tomorrow AM) as opposed to the sunrise from earlier today.
#
# - If the file is older than, say, 18 hours, (when the check is made, i.e.,
#   during the post-2pm window), then we know it's yesterday's file but not a
#   drifted version of a file from the same day.
#
# - Also, always perform the query when we are in debug mode, so that we can
#   see if the query works.

if [ $currentTimeSeconds -gt 50400 ] || [ ! -z "$debugMode" ]  # 50400 sec is 14hr since midnight aka 2pm.
then
  # Set the file age limit in minutes. If a sunrise/sunset file is older than
  # this many minutes, will be considered eligible for a refresh query. I'm using
  # minutes for the value instead of seconds because the "find" command accepts
  # a parameter of minutes for this particular kind of file search.
  ageLimit=1080 # 1080 minutes is 18 hours of age.

  # Check the file date/time stamps on the sunrise/sunset files. If they are
  # recent enough, don't bother to check with Google. To look up the file age,
  # use the Bash "find" statement with the "-mmin" parameter (search based on
  # the file age in minutes). The "+" symbol before the ageLimit indicates
  # that the statement should return "true" if the file is *older* than the
  # indicated age. This was obtained from this StackOverflow answer:
  # https://stackoverflow.com/a/552750/3621748
  #
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
  # I don't know why the double-nested double-quotes works there, but they do.
  #
  # Also, the test can no longer be a straight true/false, it must now be a
  # test for a null string comparison in order to work correctly:
  #        [ "$( find "$filename" params )" != "" ]
  #
  # Thanks to Shonky from the EmpegBBS for understanding and explaining this
  # tricky issue: https://empegbbs.com/ubbthreads.php/topics/371885
  #
  # Finally: Also perform the Google Search if the files do not exist. This
  # ensures that the program's first-run will write the necessary files if they
  # have not been created yet.
  if [ ! -f "$crowcamSunrise" ] || [ ! -f "$crowcamSunset" ] || [ "$( find "$crowcamSunrise" -mmin +$ageLimit )" != "" ] || [ "$( find "$crowcamSunset" -mmin +$ageLimit )" != "" ]
  then
    # Get more accurate sunrise/sunset results from Google if available.
    logMessage "info" "Retrieving sunrise/sunset times from Google"
    googleSunriseString=$(GetSunriseSunsetTimeFromGoogle "Sunrise")
    googleSunsetString=$(GetSunriseSunsetTimeFromGoogle "Sunset")

    # Make sure the Google responses were non-null and non-empty.
    if [ -z "$googleSunriseString" ] || [ -z "$googleSunsetString" ]
    then
      # Failure condition, did not retrieve values.
      logMessage "err" "Problem obtaining sunrise/sunset from Google. Falling back to previously saved values: $sunrise/$sunset"
    else
      # Success condition. If the Google responses were non-empty, use them
      # in place of the fallback values and write them to the fallback files.
      sunrise=$googleSunriseString
      sunset=$googleSunsetString
      logMessage "info" "Retrieved sunrise/sunset times from Google: $sunrise/$sunset"
      
      # If the Google responses were not empty, then write them into our fallback
      # files. Use "-n" to ensure they do not write a trailing newline character.
      echo -n "$sunrise" > "$crowcamSunrise"
      echo -n "$sunset" > "$crowcamSunset"
    fi
  fi
fi

# Check to make sure that the sunrise and sunset values are not empty. This
# can occur in certain situations, for instance if there is a problem with
# Google during the very first run of the program. In that case, the fallback
# files won't yet exist, the Google search will fail, and there will be no
# sunrise or sunset times in these variables.
if [ -z "$sunrise" ] || [ -z "$sunset" ]
then
  logMessage "err" "Problem obtaining sunrise/sunset values. Unable to obtain values from Google, and also unable to use fallback values"
  exit 1
fi

# Convert our sunrise/sunset times into seconds-since-midnight.
sunriseSeconds=$(TimeToSeconds $sunrise)
sunsetSeconds=$(TimeToSeconds $sunset)

# Perform math calculations on the times.
sunriseDifferenceSeconds=$( expr $sunriseSeconds - $currentTimeSeconds)
sunsetDifferenceSeconds=$( expr $sunsetSeconds - $currentTimeSeconds)

# Calculate which times of day we should stop and start the stream.
# The offsets are given in minutes, which need to be converted to
# seconds, by multiplying them by 60 seconds each.
startServiceSeconds=$(($sunriseSeconds + $startServiceOffset*60 ))
stopServiceSeconds=$(($sunsetSeconds + $stopServiceOffset*60 ))

# Output - print the results of our calculations to the screen.
logMessage "dbg" "Current time:    $currentTime    ($currentTimeSeconds seconds)"
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
#
# Note: Only perform this test after the sunrise/sunset decision has been made.
# ----------------------------------------------------------------------------
# In order to check the status of the Synology Surveillance Station "Live
# Broadcast" feature, we must either not be in debug mode, or if we are,
# we must at least be running either on the Synology or at home where we
# can access the API on the local LAN.
if [ -z "$debugMode" ] || [[ $debugMode == *"Home"* ]] || [[ $debugMode == *"Synology"* ]]
then
  logMessage "dbg" "Checking status of $featureName feature"

  # in this mode it should be safe to perform the web api call.
  streamStatus=$( WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&version=1&method=Load" )
  if ! [[ $streamStatus == *"\"live_on\":true"* ]]
  then
    logMessage "dbg" "Live stream is not currently turned on. Network checking is not needed"
    exit 0
  fi
  
else
  logMessage "dbg" "Performing network tests in debug mode, since we cannot check the status of $featureName feature"
fi


#------------------------------------------------------------------------------
# Make sure the YouTube Stream Key is updated. Workaround for GitHub issue #24.
#
# YouTube bug: Sometimes YouTube changes my Stream Key out from under me. This
# makes the stream simply stop working unexpectedly, with no warnings.
#
# Workaround their bug: Periodically check to see if the Stream Key (also
# known as the "Stream Name/Key" even though it's not a "name" per se),
# matches the value we have plugged into the Synology NAS for the "Live
# Broadcast" feature.
#
# Choosing to do this in "CrowCam.sh" even though there is a chance for a
# slight race condition with "CrowCamCleanup.sh" regarding the YouTube API
# access token. I'm not certain if only one access token can be alive at once
# or not. If more than one can be alive at a time, then no problem, both
# scripts will work simultaneously. If not, then one of the scripts might die
# if they both run at exactly the same time. I've tested running them both at
# the same time and I haven't seen an error, so we might be OK.
#------------------------------------------------------------------------------

# Fix for issue #28 - preset a global flag variable that I will be using below.
# This variable will hold true or false. If there is a problem with retrieving
# the API responses, then it will be set to false and the code will fall
# through to the network/uptime tests below, only logging the results rather
# than performing any actions. If all API responses are retrieved and look
# good, then it will remain set to true, and the code will perform the check
# for the stream key and do the needful, before falling through to the network
# tests.
safeToFixStreamKey=true

# Authenticate with the YouTube API and receive the Access Token which allows
# us to make YouTube API calls. Retrieves the $accessToken variable.
YouTubeApiAuth

# Make sure the Access Token is not empty. Part of the fix for issue #28, do
# not exit the program if the access token fails, just keep rolling.
if test -z "$accessToken" 
then
  # An error message will have already been printed about the access token at
  # this point, no need to do anything other than flag the issue for later.
  safeToFixStreamKey=false
fi

# Get the current live broadcast information details as a prelude to obtaining
# the live stream's current/active "Secret Key" for the default live broadcast
# video on my YouTube channel.
#     Some help here:     https://stackoverflow.com/a/35329439/3621748
#     Best help was here: https://stackoverflow.com/a/40422459/3621748
# Note: We are querying "liveBroadcasts" in the URL here, not "liveStreams",
# they are two different things (and I'm not clear on the exact difference).
# For more details of the items found in the response, look here:
# https://developers.google.com/youtube/v3/live/docs/liveBroadcasts#resource
# Also, we must request "broadcastType=persistent&mine=true" in order to get
# the correct details of our live stream's default/main live broadcast stream.
# Requesting the "part=contentDetails" gets us some variables including
# "boundStreamId". The boundStreamId is needed for obtaining the stream's
# secret key. We also need to request "part=snippet" in addition to
# "part=contendDetails" to get more info, because we need to obtain the "title"
# field as well, for verification that we're working on the right video. You
# can request a bunch of "parts" of data simultaneously by requesting them all
# together separated by commas, like part=id,snippet,contentDetails,status etc.
curlUrl="https://www.googleapis.com/youtube/v3/liveBroadcasts?part=snippet,contentDetails&broadcastType=persistent&mine=true&access_token=$accessToken"
liveBroadcastOutput=""
liveBroadcastOutput=$( curl -s -m 20 $curlUrl )

# Debugging output. Only needed if you run into a nasty bug here.
# Leave deactivated most of the time.
# logMessage "dbg" "Live Broadcast output information: $liveBroadcastOutput"

# Extract the boundStreamId which is needed in order to find the secret key.
boundStreamId=""
boundStreamId=$(echo $liveBroadcastOutput | sed 's/"boundStreamId"/\'$'\n&/g' | grep -m 1 "boundStreamId" | cut -d '"' -f4)
logMessage "dbg" "boundStreamId: $boundStreamId"

# Make sure the boundStreamId is not empty.
if test -z "$boundStreamId" 
then
  logMessage "err" "The variable boundStreamId came up empty. Error accessing YouTube API"
  logMessage "err" "The liveBroadcastOutput was $( echo $liveBroadcastOutput | tr '\n' ' ' )"
  safeToFixStreamKey=false
else
  # Obtain the stream key from the live stream details, now that we have the 
  # variable "boundStreamId" which is the thing that's required to get the key.
  # Note: We are querying "liveStreams" in the URL here, not "liveBroadcasts",
  # they are two different things (and I'm not clear on the exact difference).
  # More details of the various items in the response are found here:
  # https://developers.google.com/youtube/v3/live/docs/liveStreams#resource
  # We can query for part=id,snippet,cdn,contentDetails,status, but "cdn" is the
  # one we really want, which contains the special key that we're looking for.
  # Note: if querying for a specific stream id, you have to remove "mine=true",
  # you can only query for "id=xxxxx" or query for "mine=true", not both.
  curlUrl="https://www.googleapis.com/youtube/v3/liveStreams?part=cdn&id=$boundStreamId&access_token=$accessToken"
  liveStreamsOutput=""
  liveStreamsOutput=$( curl -s -m 20 $curlUrl )

  # Debugging output. Only needed if you run into a nasty bug here.
  # Leave deactivated most of the time.
  # logMessage "dbg" "Live Streams output information: $liveStreamsOutput"

  # Obtain the secret stream key that is currently being used by my broadcast.
  # Note: This variable is named a bit confusingly. It is called "streamName" in
  # the YouTube API, and identified as "Stream Name/Key" on the YouTube stream
  # management web page. But it's not really a "name" per se, it's really a
  # secret key. We need this key, but we're using the same name as the YouTube
  # API variable name to identify it.
  streamName=""
  streamName=$(echo $liveStreamsOutput | sed 's/"streamName"/\'$'\n&/g' | grep -m 1 "streamName" | cut -d '"' -f4)
  logMessage "dbg" "Secret YouTube stream name/key for this broadcast (aka streamName): $streamName"

  # Make sure the streamName is not empty.
  if test -z "$streamName" 
  then
    logMessage "err" "The variable streamName came up empty. Error accessing YouTube API"
    logMessage "err" "The liveStreamsOutput was $( echo $liveStreamsOutput | tr '\n' ' ' )"
    safeToFixStreamKey=false
  fi
fi

# Fix GitHub issue #27 - extract the stream title which we will use to make
# sure that we're working on the correct stream.
boundStreamTitle=""
boundStreamTitle=$(echo $liveBroadcastOutput | sed 's/"title"/\'$'\n&/g' | grep -m 1 "title" | cut -d '"' -f4)
logMessage "dbg" "boundStreamTitle: $boundStreamTitle"

# Make sure the stream title is not empty.
if test -z "$boundStreamTitle" 
then
  logMessage "err" "The variable boundStreamTitle came up empty. Error accessing YouTube API"
  safeToFixStreamKey=false
else
  # If the stream title is not empty, then make sure the title of the stream
  # is the one that we expect it to be. This fixes GitHub issue #27.
  if [[ "$titleToDelete" == "$boundStreamTitle" ]]
  then
    logMessage "dbg" "Expected stream title $titleToDelete matches YouTube stream title $boundStreamTitle"
  else
    # Log a set of error messages if they do not match.
    logMessage "err" "Expected stream title does not match YouTube stream title"
    logMessage "err" "Expected name: $titleToDelete"
    logMessage "err" "YouTube name:  $boundStreamTitle"
    safeToFixStreamKey=false
  fi
fi

# While we're here, extract the UTC timestamp of the last change in the
# stream. Note: Originally intended to help detect hung streams, this does not
# actually help because it only describes when the stream's details changed,
# such as the text description, not when the video stream itself last got
# valid data. Still, this will be useful for the logs to (hopefully) figure
# out exactly when YouTube yanked my stream key from me. I am hoping that if
# YouTube wipes my stream key, they'll at least have the courtesy to mark it
# as a "change" to the stream configuration, and I'll see the timestamp in the
# log.
boundStreamLastUpdateTimeMs=""
boundStreamLastUpdateTimeMs=$(echo $liveBroadcastOutput | sed 's/"boundStreamLastUpdateTimeMs"/\'$'\n&/g' | grep -m 1 "boundStreamLastUpdateTimeMs" | cut -d '"' -f4)
logMessage "dbg" "boundStreamLastUpdateTimeMs: $boundStreamLastUpdateTimeMs"

# Make sure the boundStreamLastUpdateTimeMs is not empty.
if test -z "$boundStreamLastUpdateTimeMs" 
then
  logMessage "err" "The variable boundStreamLastUpdateTimeMs came up empty. Error accessing YouTube API"
  safeToFixStreamKey=false
else
  # Calculate difference between system current date and the date that was given
  # by the API query of the last update time. The date commands below will
  # convert the UTC string that the YouTube API returns, into local time
  # automatically, when running on Linux. Alas, not with Mac. For instance if
  # YouTube responds with boundStreamLastUpdateTimeMs="2019-05-08T15:26:11.276Z"
  # (which is 3:26pm UTC) then I get 8:26am output on Linux, but I get 3:26pm on
  # Mac. Fortunately, the final target run destination for this script will by
  # Linux on Synology, and Mac is only used for test/debug/development, so it's
  # OK if it's inaccurate during debug runs. For debugging purposes, we will
  # obtain the last update time two different ways, depending on if you're on
  # Mac or Linux.
  if [[ $debugMode == *"Mac"* ]]
  then
      # Mac version - Note: Mac version is inaccurate due to failure to
      # interpret GMT zone. Also Note: This line will also print the warming
      # message "Warning: Ignoring 5 extraneous characters in date string
      # (.xxxZ)" due to Mac not supporting the milliseconds (%f) formatting
      # parameter. Basically, Mac's date commands suck compared to Linux.
      lastUpdatePrettyString=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$boundStreamLastUpdateTimeMs")
      lastUpdateDateTimeSeconds=$( date -j -f "%Y-%m-%dT%H:%M:%S" "$boundStreamLastUpdateTimeMs" +%s )
  else
      # Linux version - Accurate, but only works on Linux.
      lastUpdatePrettyString=$( date -d "$boundStreamLastUpdateTimeMs" )
      lastUpdateDateTimeSeconds=$( date -d "$boundStreamLastUpdateTimeMs" +%s )
  fi

  # Use local time for your local side of the calculations. At least "date +%s"
  # works the same on Mac as on Linux.
  currentDateTimePrettyString=$( date )
  currentDateTimeSeconds=$( date +%s )

  # Get the difference between the two times.
  differenceDateTimeSeconds=$(( $currentDateTimeSeconds - $lastUpdateDateTimeSeconds ))
  differencePrettyString=$( SecondsToTime $differenceDateTimeSeconds )

  logMessage "dbg" "Date/Time of last YouTube Stream update:  $lastUpdateDateTimeSeconds seconds, $lastUpdatePrettyString"
  logMessage "dbg" "Date/Time of current system:              $currentDateTimeSeconds seconds, $currentDateTimePrettyString"
  logMessage "dbg" "Stream was last edited:                   $differenceDateTimeSeconds seconds ago, aka $differencePrettyString ago"
fi

# Fix for issue #28 - Check to make sure it is safe to work on the stream key.
# If any of the YouTube API retreivals above failed, then none of this section
# below should get executed. Skip it rather than exiting the program.
if "$safeToFixStreamKey" = true
then
  # Obtain the local Synology stream key that is currently plugged into the
  # "Live Broadcast" feature of Surveillance Station.

  # In order to check the Stream Key of the Synology Surveillance Station "Live
  # Broadcast" feature, we must either not be in debug mode, or if we are, we
  # must at least be running either on the Synology or at home where we can
  # access the API on the local LAN.
  if [ -z "$debugMode" ] || [[ $debugMode == *"Home"* ]] || [[ $debugMode == *"Synology"* ]]
  then
    # Query the Synology API for the YouTube Live Broadcast details.
    streamKeyQuery=$( WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&version=1&method=Load" )
    
    # Extract the "key" from the Synology response which is needed in order to find the secret key.
    streamKey=""
    streamKey=$(echo $streamKeyQuery | sed 's/"key"/\'$'\n&/g' | grep -m 1 "key" | cut -d '"' -f4)
    logMessage "dbg" "Local Synology stream key (needs to match YouTube stream name/key): $streamKey"

    # Make sure the streamKey is not empty.
    if test -z "$streamKey" 
    then
        logMessage "err" "The variable streamKey came up empty. Error accessing Synology API. Exiting program"
        logMessage "err" "The streamKeyQuery was $( echo $streamKeyQuery | tr '\n' ' ' )"
        exit 1
    fi

    # Compare the YouTube stream name/key to our local Synology stream key.
    # Note: This is a case-sensitive comparison, but I think we can get away
    # with that here. Reasons: When setting up the stream, odds are that the
    # user used copy and paste to put the key into the box in the Live Broadcast
    # dialog box. So they should be the same case. Also, if the case was
    # different, then this step would immediately fix it anyway.
    if [[ "$streamKey" == "$streamName" ]]
    then
      logMessage "dbg" "Local Synology stream key matches YouTube stream name/key"
    else
      # Log a set of error messages if they do not match.
      logMessage "err" "Local Synology stream key does not match YouTube stream name/key"
      logMessage "err" "Local Key:   $streamKey"
      logMessage "err" "YouTube Key: $streamName"
      logMessage "err" "Stream was last edited $differencePrettyString ago, at $lastUpdatePrettyString local time"

      # Write the new key to the Synology configuration automatically. Use the
      # Synology API's "Save" method to set "key=(the new key)". Response is
      # expected to be {"success":true} and will error out of the script if it
      # fails.
      logMessage "info" "Updating local Synology stream name/key to be $streamName"
      WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&key=$streamName" >/dev/null
    fi
  else
    logMessage "dbg" "Not in a position to obtain the Stream Key of $featureName feature - Will not attempt the Stream Key fix procedure"
  fi
else
  logMessage "err" "Unable to obtain all of the YouTube API stream data for $titleToDelete live stream - Will not attempt the Stream Key fix procedure"
fi


# ----------------------------------------------------------------------------
# Network Test section.
# 
# Checks the network a specified number of times at intervals. If it is down,
# log this fact and then wait for the network to come back up. Once it comes
# back up, bounce the YouTube stream.
# ----------------------------------------------------------------------------

# Main "outer loop" of network tests. 
for mainLoop in `seq 1 $NumberOfTests`
do
  # Test if the Internet is up.  
  Test_Network

  # Check our initial results from the network test and behave accordingly.
  if [ "$NetworkIsUp" = true ] 
  then
    # The network is working in this case. Pause before doing the
    # next check.

    # However, do not pause between test runs on the last test of the group.
    # Only pause if we are beneath the "maximum number of tests" ceiling. If
    # we equal or exceed that ceiling, do not pause between tests. (We should
    # never exceed it but it's good programming practice to use this pattern.)
    if [ "$mainLoop" -lt "$NumberOfTests" ]
    then
      # Message for local machine test runs.
      logMessage "dbg" "Outer network test loop $mainLoop of $NumberOfTests - Sleeping $PauseBetweenTests seconds"

      # Sleep between network tests.
      sleep $PauseBetweenTests
    fi
  else
    # Network or stream is down in this case. Begin waiting, in a loop, for
    # the network to come back up so that we can restart the YouTube stream.
    for restoreLoop in `seq 1 $MaxComebackRetries`
    do
      # Pause before trying to check if the network is back up. In this case,
      # we pause every time, because the pause is before the network check.
      logMessage "err" "Status - Network up: $NetworkIsUp - Network problem during outer network test loop $mainLoop of $NumberOfTests - Pausing $PauseBetweenTests seconds to wait for network to come back up. Inner restore attempt loop $restoreLoop of $MaxComebackRetries"

      # Pause before every network test when waiting for it to come back. 
      sleep $PauseBetweenTests

      # Test the network and stream again.
      logMessage "info" "Testing network again"
      Test_Network
      logMessage "info" "Status - Network up: $NetworkIsUp"

      # Check if the network has come back up and break out of the retry loop
      # if the network is now up.
      if [ "$NetworkIsUp" = true ]
      then
        # Since the network is up, we can break out of our loop of retrying if
        # the network is up. Note that, at this point in the code, we already
        # confirmed something went wrong in either the network or the stream
        # earlier, so at this point we want to fall down into the next section
        # where we will bounce the stream.
        break
      fi
    done

    # ----------------------------------------------------------------------------
    # Bounce the stream
    # ----------------------------------------------------------------------------
    # If we have reached this line without hitting a "break" above, it means
    # we have satisfied all criteria for needing a stream bounce, and we are
    # now intending to actually bounce the stream.

    # Log our intention to bounce the stream. It is possible that the network
    # really did come back up, or, we waited as long as we could and then
    # decided to give up and bounce the stream anyway. We need to deliver a
    # different log message depending on whether the network is up, or we just
    # gave up on waiting for it to come back up.
    if [ "$NetworkIsUp" = true ]
    then
      # Inform the user that we're bouncing the stream because the network is up.
      logMessage "info" "Bouncing the YouTube stream since the network is up"
    else
      # Inform the user that we gave up trying.
      logMessage "err" "The network is not back up yet. Bouncing YouTube stream anyway"
    fi
    
    # Actually bounce the stream.
    BounceTheStream
    
    # Exit the program because we should only need to bounce the stream once
    # per run of the program. After bouncing the stream, we can exit this
    # program and let its next timed run (controlled in the Synology Task
    # Scheduler) handle any remaining tests.
    exit 0

    # Because we have bounced the YouTube stream, we no longer need to loop
    # around. Break out of the network test loop. NOTE: With the new code flow,
    # This line should not be hit because the program should have exited by
    # now. Adding an error message at this point to validate that assumption.
    logMessage "err" "Unexpected program behavior. This program was expected to have exited before this line was reached"
    exit 1
    break
  fi
done

# ----------------------------------------------------------------------------
# Stream Test section.
# 
# Checks the YouTube stream, and bounces it if the stream isn't up.
#
# Intended to fix issues where the network tests above weren't sufficient to
# detect a problem with the stream. Imagine a situation where the network blips
# very briefly, for example, and the tests above do not catch that blip. In
# that case, the stream would still go bad (based on my experience) and it
# still needs to be fixed by a stream bounce. In most of these cases, it will
# be detectable because an attempt to download the stream will result in an
# error.
#
# Note: Originally the code tested the stream repeatedly alongside each network
# test. During the investigation of GitHub Issue #9, after some experiments, I
# discovered that the stream tests sometimes took up to 20 seconds to return.
# This slowed down the overall network testing loop, causing the frequency of
# the test loop to be less frequent than I intended.
#
# Now, instead, the YouTube stream will only be checked once per run of this
# program, only once at the end of the run, and only if the network tests were
# good to begin with.
# ----------------------------------------------------------------------------

# Validate the state of $NetworkIsUp at this point in the program. I expect
# the variable $NetworkIsUp to be "true" at this moment, because if it were
# "false" at any point above, then the program should have bounced the stream
# and exited.
#
# Additionally, I expect the results of Test_Network to be a fresh result at
# this point in time. Any place where there would have been a "pause" in the
# code after a network test, we shouldn't have reached this line after the
# pause. Cases where there could have been a pause are:
# - We've bounced the network and paused during or after the bounce. This can't
#   be the case at this point in the code because we exit the program after
#   bouncing and we would never have reached this line.
# - The network tests were all good and there were pauses after each test. This
#   can't be the case here, because if all the tests were good, then it would
#   have completed its testing loop, and the pause is deliberately disabled
#   during the final loop after the final test, so it would have fallen through
#   to this line immediately after the last good test.
# - The network tests were bad and there were pauses as it waited for the
#   network to come back up. This can't be the case because all failed network
#   tests cause a stream bounce, which also exits the program.
if [ "$NetworkIsUp" = false ] 
then
    logMessage "err" "Unexpected program behavior. Reached a point in the code where the NetworkIsUp variable was expected to be true, but it was false"
    exit 1
fi

# Test the stream. Note that the Test_Stream function contains its own inner
# hysteresis loop because the test method might intermittently cry wolf.
Test_Stream

# Log the status of network and stream.
logMessage "dbg" "Status - Network up: $NetworkIsUp - Stream up: $StreamIsUp"

# If the stream is down, then bounce the stream.
if [ "$StreamIsUp" = false ] 
then
  # Inform the user that we're bouncing the stream.
  logMessage "err" "Bouncing the YouTube stream, because it was unexpectedly down"
  
  # Bounce the stream.
  BounceTheStream
  
  # Exit the program because we should only need to bounce the stream once
  # per run of the program. After bouncing the stream, we can exit this
  # program and let its next timed run (controlled in the Synology Task
  # Scheduler) handle any remaining tests.
  #
  # (At the time this was written, there wasn't anything else in the code after
  # this line, so it would have exited anyway, but I'm putting this in here so
  # that, if I add other tests below, the code still works as intended.)
  exit 0
fi
    
# Debugging message for logging script start/stop times. Leave commented out.
# logMessage "info" "-------------------------- Ending script: $programname -------------------------"







