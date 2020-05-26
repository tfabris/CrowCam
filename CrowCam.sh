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
#
# Note: Attempting to address issue #29 - Do not call the YouTube API as often.
# Try to prevent busting the quota by running this script every five minutes
# instead of every one minute. This requires 30 network tests spaced at 10
# seconds apart, instead of 6 tests at 10 seconds apart.
NumberOfTests=30

# Number of seconds to pause between network-up-check tests.
PauseBetweenTests=10

# Number of seconds after the top of the hour that we will consider this
# script to be "running at the top of the hour". This will be used for
# functions which do something special at an interval of once per hour. This
# variable is dependent on how frequently this script is launched from the
# Synology Task Scheduler. It should be set to the same number of seconds as
# the launch frequency in the Synology Task Scheduler. For example, if the
# Synology Task Scheduler is configured to launch this script once every 5
# minutes, then, set TopOfTheHourPeriod to 300 (5 minutes in seconds).
TopOfTheHourPeriod=300

# Number of times we will loop and retest for stream problems if it detects
# that the stream is down. This is a secondary test which will only be run if
# the network is up. This attempts to connect to the stream and retrieve its
# info. If an error is received, it will perform a small amount of hysteresis
# (repeated tests, controlled by these variables). This hysteresis is needed on
# the stream test, but not the network test, because the stream test has proven
# to be flaky, sometimes reporting a problem when there is actually no problem.
# If, after the hysteresis retries, there is still a problem reported in the
# stream, then we will bounce the stream, even if the network hasn't gone down.
#
# Note: Attempting to address issue #29 - Do not call the YouTube API as often.
# Try to prevent busting the quota by re-querying more slowly. You can view
# your quota usage here:
# https://console.developers.google.com/apis/api/youtube.googleapis.com/quotas?project=crowcam
NumberOfStreamTests=4

# Number of seconds to pause between stream-up-check tests.
PauseBetweenStreamTests=15

# When in test mode, pause for a shorter period between tests, and do fewer
# loops of the main network test loop.
if [ ! -z "$debugMode" ]
then
  PauseBetweenTests=1
  PauseBetweenStreamTests=1
  NumberOfTests=5
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

# Bounce duration, in seconds. These are the number of seconds that the stream
# will bounce "down" during bounces. It is the amount of time that the script
# will wait after bringing the stream down, before bringing it back up again.
# There are two values here: shortBounceDuration, used when certain issues
# can be repaired with a fast bounce, and longBounceDuration, used when we are
# trying to seriously split the stream into separate sections.
shortBounceDuration=4
longBounceDuration=135

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
# YouTube stream is a little bit flaky. Sometimes it is unreliable and returns
# a false alarm. So this will retry a few times before officially flagging an
# issue. Also, this function will also leave StreamIsUp set to true if the
# YouTube API is completely down and returns no information about the status of
# the stream.
# -----------------------------------------------------------------------------
Test_Stream()
{
  # Debugging message, leave commented out usually.
  # LogMessage "info" "Begin Test_Stream"
  
  # When starting this function, assume the stream is up. It will be set to
  # false if the hysteresis loop below exits with definitive information that
  # the stream has gone bad. If the results of the test are inconclusive, then
  # the stream will be considered still good, so that we don't over-bounce in
  # situations where the YouTube API isn't responding to queries. This is to
  # help one of the issues I found in bug #37.
  StreamIsUp=true
  
  # Check the global variable $NetworkIsUp and see if it's true. This function
  # is only useful if the network is up. If the network is down, then return
  # false automatically.
  if [ "$NetworkIsUp" = true ]
  then
    LogMessage "dbg" "Network is up, checking if live stream is up"
  else
    # If the network is down, assume the stream must be down too, and stop
    # trying to do anything else here, just return back to the caller.
    StreamIsUp=false
    LogMessage "dbg" "Network is down, assuming live stream must also be down"
    return
  fi

  # BUGFIX: Attempt to fix GitHub issue #4. There was a time when the stream
  # got bounced unnecessarily even though everything was actually up and
  # working correctly. My suspicion is that testing the stream status is flaky,
  # and that I need to add some hysteresis here. Adding an inner "Stream
  # testing" loop here, for testing multiple retries to see if the live stream
  # is up, and failing only if all of the tests fail. Bail out of the loop on
  # any success.
  for streamTestLoop in `seq 1 $NumberOfStreamTests`
  do
    # Attempting to address issues #23 and #26: Test if the live stream is up
    # by querying the YouTube API for the stream status.

    # Bugfix for issue #37 - Keep track of whether the stream upness detection
    # succeeded inside this hysteresis loop. Start by assuming upness is good,
    # and set the variable to false below if any of our failure conditions are
    # hit. This must be a separate variable from StreamIsUp in order to combine
    # its results with the GoodApiDataRetrieved variable, below.
    GoodStreamInsideLoop=true
    
    # Bugfix for issue #37 - Start by assuming that we will retrieve good API
    # data, and if we do not, then it will be set to false below if there are
    # any data retrieval problems encountered. This will be used to determine
    # if the StreamIsUp variable should be altered or not, in any given loop.
    GoodApiDataRetrieved=true
  
    # Authenticate with the YouTube API and receive the Access Token which allows
    # us to make YouTube API calls. Retrieves the $accessToken variable.
    #
    # Note: at this point in the code we have already called YouTubeApiAuth
    # once, when we checked the Stream Key. However, we should do it again
    # here, because we are inside our hysteresis loop. There is a chance that
    # a brief blip in the availability of the YouTube API would cause too many
    # false-positives and make us bounce our stream. We want to truly perform
    # a genuine re-try to check the stream status, and to do that, we must
    # also re-try the authentication process, because that's one of the things
    # that the hysteresis is protecting against.
    YouTubeApiAuth

    # Make sure the Access Token is not empty. Part of the fix for issue #28, do
    # not exit the program if the access token fails, just keep rolling.
    if test -z "$accessToken" 
    then
      # Bugfix to issue #37 - Do not bounce the stream if there is no valid
      # data to analyze, instead, flag that we did not get good API data.
      # An error message will have already been printed about the access token
      # at this point, so we only need to flag the issue for later processing.
      GoodApiDataRetrieved=false
    else
      # Get the current live broadcast information details as a prelude to obtaining
      # the live stream details. Details of the items in the response are found here:
      # https://developers.google.com/youtube/v3/live/docs/liveBroadcasts#resource
      curlUrl="https://www.googleapis.com/youtube/v3/liveBroadcasts?part=contentDetails&broadcastType=persistent&mine=true&access_token=$accessToken"
      liveBroadcastOutput=""
      liveBroadcastOutput=$( curl -s -m 20 $curlUrl )
    
      # Extract the boundStreamId which is needed in order to find other information.
      boundStreamId=""
      boundStreamId=$(echo $liveBroadcastOutput | sed 's/"boundStreamId"/\'$'\n&/g' | grep -m 1 "boundStreamId" | cut -d '"' -f4)
      LogMessage "dbg" "boundStreamId: $boundStreamId"
    
      # Make sure the boundStreamId is not empty.
      if test -z "$boundStreamId"
      then
        LogMessage "err" "The variable boundStreamId came up empty, inside Test_Stream. Error accessing YouTube API"
        LogMessage "err" "The liveBroadcastOutput, inside Test_Stream, was $( echo $liveBroadcastOutput | tr '\n' ' ' )"
        
        # Bugfix to issue #37 - Do not bounce the stream if there is no valid
        # data to analyze, instead, flag that we did not get good API data.
        GoodApiDataRetrieved=false
      else
        # Obtain the liveStreams status details and look at the resource results in
        # the response. Details of the various items in the response are found here:
        # https://developers.google.com/youtube/v3/live/docs/liveStreams#resource
        curlUrl="https://www.googleapis.com/youtube/v3/liveStreams?part=status&id=$boundStreamId&access_token=$accessToken"
        liveStreamsOutput=""
        liveStreamsOutput=$( curl -s -m 20 $curlUrl )
  
        # Debugging output. Leave disabled most of the time.
        #   LogMessage "dbg" "Live Streams output response:"
        #   LogMessage "dbg" "---------------------------------------------------------- $liveStreamsOutput"
        #   LogMessage "dbg" "----------------------------------------------------------"
  
        # Get "streamStatus" from the results. Looking for the field "active" in
        # these results:
        #           "status": {
        #            "streamStatus": "active",
        #            "healthStatus": {
        #             "status": "ok",
        # Possible expected values should be:
        #     active – The stream is in active state which means the user is receiving data via the stream.
        #     created – The stream has been created but does not have valid CDN settings.
        #     error – An error condition exists on the stream.
        #     inactive – The stream is in inactive state which means the user is not receiving data via the stream.
        #     ready – The stream has valid CDN settings.
        streamStatus=""
        streamStatus=$(echo $liveStreamsOutput | sed 's/"streamStatus"/\'$'\n&/g' | grep -m 1 "streamStatus" | cut -d '"' -f4)
        LogMessage "dbg" "streamStatus: $streamStatus"

        # Make sure the streamStatus is not empty.
        if test -z "$streamStatus"
        then
          LogMessage "err" "The variable streamStatus came up empty. Error accessing YouTube API"
          LogMessage "err" "The liveStreamsOutput was $( echo $liveStreamsOutput | tr '\n' ' ' )"
          
          # Bugfix to issue #37 - Do not bounce the stream if there is no valid
          # data to analyze, instead, flag that we did not get good API data.
          GoodApiDataRetrieved=false
        else
          # Stream status should be "active" if the stream is up and working. Any
          # other value means the stream is down at the current time.
          if [ "$streamStatus" != "active" ]
          then
              LogMessage "err" "The streamStatus is not active. Value retrieved was: $streamStatus"
              GoodStreamInsideLoop=false
          fi
        fi
  
        # Extract the "status" field of the  "healthStatus" object, but that means
        # we're parsing for the second occurrence of the variable "status" in the
        # results. So the grep statement must be -m 2 instead of -m 1, so that it
        # returns two results, and then we have to "tail -1" to get only the last of
        # the two results. This works to tease out the "ok" from this text:
        #           "status": {
        #            "streamStatus": "active",
        #            "healthStatus": {
        #             "status": "ok",
        # Possible expected values should be:
        #    good – There are no configuration issues for which the severity is warning or worse.
        #    ok – There are no configuration issues for which the severity is error.
        #    bad – The stream has some issues for which the severity is error.
        #    noData – YouTube's live streaming backend servers do not have any information about the stream's health status.
        healthStatus=""
        healthStatus=$(echo $liveStreamsOutput | sed 's/"status"/\'$'\n&/g' | grep -m 2 "status" | tail -1 | cut -d '"' -f4 )
        LogMessage "dbg" "healthStatus: $healthStatus"
    
        # Make sure the healthStatus is not empty.
        if test -z "$healthStatus" 
        then
          LogMessage "err" "The variable healthStatus came up empty. Error accessing YouTube API"
          LogMessage "err" "The liveStreamsOutput was $( echo $liveStreamsOutput | tr '\n' ' ' )"
          
          # Bugfix to issue #37 - Do not bounce the stream if there is no valid
          # data to analyze, instead, flag that we did not get good API data.
          GoodApiDataRetrieved=false
        else
          # Health status should be "good" or "ok" if the stream is up and
          # working. I have discovered that the stream can also be reported as
          # "bad" if there is low bandwidth, even though the stream is working
          # fine, so we actually must consider "bad" to be good, even though
          # it's the exact opposite of what you might expect. Receiving "noData"
          # or other values mean the stream is down at the current time, and
          # that's the thing we're truly looking for here: A genuinely dead
          # stream, not just a low-bandwidth stream.
          if [ "$healthStatus" != "good" ] && [ "$healthStatus" != "ok" ] && [ "$healthStatus" != "bad" ]
          then
              LogMessage "err" "The healthStatus is not good. Value retrieved was: $healthStatus"
              GoodStreamInsideLoop=false
          fi    
        fi
  
        # Attempt to catch issue #23 and correct it. Look for any occurrence
        # of this particular error in the status output and bounce the stream
        # if it's there:
        #    "configurationIssues": [
        #     {
        #      "type": "videoIngestionFasterThanRealtime",
        #      "severity": "error",
        #      "reason": "Check video settings",
        #      "description": "Your encoder is sending data faster than realtime (multipleseconds of video each second). You must rate limit your livevideo upload to approximately 1 second of video each second."
        #     },
        #
        if [[ $liveStreamsOutput == *"videoIngestionFasterThanRealtime"* ]]
        then
              LogMessage "err" "The configurationIssues contains a bad value. Value retrieved was: videoIngestionFasterThanRealtime"
              GoodStreamInsideLoop=false
        fi
  
        # Also check for this error type and see how often it comes up.
        if [[ $liveStreamsOutput == *"videoIngestionStarved"* ]]
        then
          # Update 2019-05-27 - Do not bounce the stream due to the error
          # "videoIngestionStarved" because it cries wolf too frequently.
          # Only log the situation and allow the program to continue.
          LogMessage "dbg" "The configurationIssues contains a bad value. Value retrieved was: videoIngestionStarved. Will not act on this error due to this particular error message proving to be flaky sometimes"
        fi
      fi    
    fi
    
    # Attempted bugfix related to issue #37 - Don't make assumptions about
    # whether the stream is really good or not if this loop had any API data
    # retrieval problems. 
    if [ "$GoodApiDataRetrieved" = true ]
    then
      # Attempted Issue #4 bugfixing - Controlling the pass/fail state of the
      # hysteresis loop here. If we reach this point and get "true", then that
      # is the "good" state and we can bail out. If we get "false" then we have
      # to try again.
      if [ "$GoodStreamInsideLoop" = true ]
      then
        # Break out of the hysteresis loop if the stream and the API are OK.
        # Also set the global variable StreamIsUp to True because we know that
        # we got good data indicating that it was indeed up.
        StreamIsUp=true
        break
      else
        # The current inner hysteresis loop run returned an actual failure.
        # Set our global StreamIsUp variable to false and allow it to go
        # through the loop again.
        StreamIsUp=false
      fi
    fi

    # If we have reached this point then we need to pause and try another
    # hysteresis loop. However, on the last loop, don't pause, just let it
    # drop through since it will bail out the bottom of the loop on the last
    # one.
    if [ "$streamTestLoop" -lt "$NumberOfStreamTests" ]
    then
      # Related to issue #37: Change messaging if the API is being goofy today.
      if [ "$GoodApiDataRetrieved" = true ]
      then
        LogMessage "dbg" "The network is up, but the YouTube stream is down. Pausing to give it a chance to come up. Inner stream test loop, retry attempt $streamTestLoop of $NumberOfStreamTests . Sleeping $PauseBetweenStreamTests seconds before trying again"
      else
        LogMessage "dbg" "The network is up, but the YouTube stream test results are inconclusive. Inner stream test loop, retry attempt $streamTestLoop of $NumberOfStreamTests . Sleeping $PauseBetweenStreamTests seconds before trying again"
      fi
      
      # Sleep between stream tests.
      sleep $PauseBetweenStreamTests
    fi    
  done

  # If we haven't hit one of our failure modes, the stream is likely up.
  if [ "$StreamIsUp" = true ]
  then
    # This message is normally a debug message (i.e., doesn't go into the
    # Synology log), unless we have been encountering stream problems, and
    # have had to hit our hysteresis loop above. If we came out of that loop
    # with any number greater than one, then, I want a "stream up" message to
    # appear in the Synology Log that corresponds with the "stream down"
    # message from our hysteresis loop above.
    if [ "$streamTestLoop" -gt "1" ]
    then
      # Related to issue #37: Change messaging if the API is being goofy today.
      if [ "$GoodApiDataRetrieved" = true ]
      then
        LogMessage "info" "Live stream came back up"
      else
        LogMessage "info" "Live stream test results are inconclusive"
      fi
    else
      LogMessage "dbg" "Live stream is up"
    fi
  fi

  # Debugging message, leave commented out usually.
  # LogMessage "info" "Done with Test_Stream" 
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
  # LogMessage "info" "Beginning Test_Network" 

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
  LogMessage "dbg" "Testing $ThisTestSite - outer network test attempt $mainLoop of $NumberOfTests"

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
  if [ "$NetworkIsUp" = true ]
  then
    # Note that there is a more serious message which appears in the log,
    # triggered elsewhere in the code, when the network is down, so a log
    # message for network failure is not needed here, only for success.
    LogMessage "dbg" "Network is up, outer network test attempt $mainLoop of $NumberOfTests"
  fi

  # Debugging message, leave commented out usually.
  # LogMessage "info" "Done with Test_Network"
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
    # LogMessage "info" "Done with GetSunriseSunsetTimeFromGoogle"
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
    LogMessage "dbg" "Checking status of $featureName feature"
  else
    LogMessage "dbg" "$2. But we're not in a position where we can control the stream up/down state"
    return
  fi

  # Check if the video stream to YouTube is currently turned on or not, and
  # place that value into a variable for using multiple times below.
  currentStreamState=$( IsStreamRunning )

  # Behavior when stream is set to up, at a time when it should be up.
  if [ "$currentStreamState" = true ] && [ $1 = "up" ]
  then
    # Message for local machine test runs.
    LogMessage "dbg" "$2. $featureName is up. It should be $1 at this time. Nothing to do"
  fi

  # Behavior when stream is set to down, at a time when it should be up.
  if [ "$currentStreamState" = false ] && [ $1 = "up" ]
  then
    # Bring the stream back up.
    LogMessage "info" "$2. $featureName is down. It should be $1 at this time. Starting stream"
    WriteStreamStartTime
    StartStream

    # Insert a deliberate pause after starting the stream, to make sure that
    # YouTube has a chance to get its head together and actually stream some
    # video (it sometimes takes a bit). If we don't do this pause here, we run
    # the risk of starting up the stream but then immediately checking if the
    # stream is up (in the network test section), and discovering the wheels
    # weren't quite turning yet, and then raising a false alarm.
    LogMessage "dbg" "Sleeping briefly, to allow for stream startup"
    sleep 50
  fi
  
  # Behavior when stream is set to up, at a time when it should be down.
  if [ "$currentStreamState" = true ] && [ $1 = "down" ]
  then
    # Stop the stream.
    LogMessage "info" "$2. $featureName is up. It should be $1 at this time. Stopping stream"
    StopStream
  fi
  
  # Behavior when stream is set to down, and it should be down.
  if [ "$currentStreamState" = false ] && [ $1 = "down" ]
  then
    # Message for local machine test runs.
    LogMessage "dbg" "$2. $featureName is down. It should be $1 at this time. Nothing to do"
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
# Parameters: $1 - Integer - length of bounce (down time) in seconds.
# Returns: Nothing.
#------------------------------------------------------------------------------
BounceTheStream()
{
  # Only bounce the stream if we are running on the Synology, or at least at
  # home where we can access its API on the local LAN. 
  if [ -z "$debugMode" ] || [[ $debugMode == *"Home"* ]] || [[ $debugMode == *"Synology"* ]]
  then
    # Stop the YouTube stream feature
    LogMessage "dbg" "Bouncing stream for $1 seconds"
    StopStream
  else
    # In test mode, log something anyway.
    LogMessage "dbg" "Bouncing stream for $1 seconds - Except we're not in a position where we can control the stream up/down state, so no stream bounce performed"
  fi
  
  # Wait a while to make sure it is really turned off. The number passed in
  # as parameter $1 will determine how long to wait. Short values will quickly
  # restart the stream, keeping the stream to be part of the same video on
  # YouTube, and long values (not sure how long, but 100+ seconds seems to
  # work in my experiments) will end the current stream and split it into a
  # different stream archive video segment on YouTube.
  LogMessage "dbg" "Pausing for $1 seconds, after bringing down the stream, before bringing it up again"
  sleep $1

  # Write the bounceup time to our configuration file which tracks the startup
  # time of each stream segment. Do this only for long bounces such as those
  # which are intended to split the stream. Shorter ones are not expected to
  # split the stream, so don't write a new start time for the shorter ones.
  if [ $1 -ge $longBounceDuration ]
  then
    WriteStreamStartTime
  fi

  # Bring the stream back up.
  if [ -z "$debugMode" ] || [[ $debugMode == *"Home"* ]] || [[ $debugMode == *"Synology"* ]]
  then
    LogMessage "dbg" "Starting stream"
    StartStream
  fi

  # If we had to bounce the stream, wait a little while before allowing the
  # program to continue. This allows the stream to get spooling up and
  # started, before there is an opportunity for the next part of the program
  # (or the next Task-scheduled run of this script) to check the stream state.
  # If we don't pause here, we run the risk of possibly having the next
  # section start too soon, before the bounced stream is up and running again,
  # and then detecting a false error at that time.
  postBounceSleepTime=50
  LogMessage "dbg" "Pausing $postBounceSleepTime seconds, after bringing the stream back up again, to give the stream a chance to spin up and work"
  sleep $postBounceSleepTime
  LogMessage "dbg" "Done bouncing the stream"
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


#------------------------------------------------------------------------------
# Main program code body.
#------------------------------------------------------------------------------

# Log the current test mode state, if activated.
if [ ! -z "$debugMode" ]
then
  LogMessage "err" "------------- Script $programname is running in debug mode: $debugMode -------------"
fi

# Debugging message for logging script start/stop times. Leave commented out.
# LogMessage "info" "-------------------------- Starting script: $programname -------------------------"

# Log current script location and working directory.
LogMessage "dbg" "Script exists in directory: $DIR"
LogMessage "dbg" "Current working directory:  $(pwd)"


# Verify that the necessary external files exist.
if [ ! -e "$clientIdJson" ]
then
  LogMessage "err" "Missing file $clientIdJson"
  exit 1
fi
if [ ! -e "$crowcamTokens" ]
then
  LogMessage "err" "Missing file $crowcamTokens"
  exit 1
fi
if [ ! -e "$apicreds" ]
then
  LogMessage "err" "Missing file $apicreds"
  exit 1
fi


# Get API creds out of the external file, assert values are non-blank.
# TO DO: Learn the correct linux-supported method for storing and retrieving a
# username and password in an encrypted way.
read username password < "$apicreds"
if [ -z "$username" ] || [ -z "$password" ]
then
  LogMessage "err" "Problem obtaining API credentials from external file"
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
  LogMessage "dbg" "$serviceName is not running. Exiting program"
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
    LogMessage "dbg" "Retrieving sunrise/sunset times from Google"
    googleSunriseString=$(GetSunriseSunsetTimeFromGoogle "Sunrise")
    googleSunsetString=$(GetSunriseSunsetTimeFromGoogle "Sunset")

    # Make sure the Google responses were non-null and non-empty.
    if [ -z "$googleSunriseString" ] || [ -z "$googleSunsetString" ]
    then
      # Failure condition, did not retrieve values.
      LogMessage "err" "Problem obtaining sunrise/sunset from Google. Falling back to previously saved values: $sunrise/$sunset"
    else
      # Success condition. If the Google responses were non-empty, use them
      # in place of the fallback values and write them to the fallback files.
      sunrise=$googleSunriseString
      sunset=$googleSunsetString
      LogMessage "info" "Retrieved sunrise/sunset times from Google: $sunrise/$sunset"
      
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
  LogMessage "err" "Problem obtaining sunrise/sunset values. Unable to obtain values from Google, and also unable to use fallback values"
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

# GitHub issue #55 - Calculate midday (again). Get the total length of all
# stream uptime (the elapsed time between the approximate sunrise/camera-on
# time and the approximate sunset/camera-off time), and calculate the halfway
# point between those two points. That halfway point will be our approximate
# midday mark, which gets used in bounce/split calculations. 
totalStreamSeconds=$(($stopServiceSeconds - $startServiceSeconds))
if [ $totalStreamSeconds -lt 1 ]  
then  
  LogMessage "err" "Problem calculating sunrise/sunset values. Total stream length is $totalStreamSeconds seconds"  
  exit 1  
fi
halfTimeSeconds=$(( ($totalStreamSeconds / 2) ))
middaySeconds=$(( $startServiceSeconds + $halfTimeSeconds ))
middayDifferenceSeconds=$(( $middaySeconds - $currentTimeSeconds ))
midday=$(SecondsToTimeAmPm $middaySeconds)

# GitHub issue #55 - If the midday point is shorter than the maximum allowed
# video length, then use that value in place of it. This means that the daily
# split point will be either midday, or, the max video length, whichever is
# the shorter one.
if [ $halfTimeSeconds -lt $maxVideoLengthSeconds ]  
then  
  LogMessage "dbg" "Using midday bounce length $(SecondsToTime $halfTimeSeconds) in place of maximum video length $(SecondsToTime $maxVideoLengthSeconds) to determine split points"  
  maxVideoLengthSeconds=$halfTimeSeconds
fi  


# Output - print the results of our calculations to the screen.
LogMessage "dbg" "Current time:    $currentTime    ($currentTimeSeconds seconds)"
LogMessage "dbg" "Approx Sunrise:  $sunrise  ($sunriseSeconds seconds, difference is $sunriseDifferenceSeconds)"
LogMessage "dbg" "Approx Midday:   $midday  ($middaySeconds seconds, difference is $middayDifferenceSeconds)"
LogMessage "dbg" "Approx Sunset:   $sunset  ($sunsetSeconds seconds, difference is $sunsetDifferenceSeconds)"
LogMessage "dbg" ""
LogMessage "dbg" "$( OutputTimeDifference $sunriseDifferenceSeconds $(SecondsToTime $sunriseDifferenceSeconds) Sunrise )"
LogMessage "dbg" "$( OutputTimeDifference $sunsetDifferenceSeconds $(SecondsToTime $sunsetDifferenceSeconds) Sunset )"
LogMessage "dbg" ""
LogMessage "dbg" "Will start the stream at about   $startServiceSeconds $(SecondsToTime $startServiceSeconds)"
LogMessage "dbg" "Will stop it for the night at    $stopServiceSeconds $(SecondsToTime $stopServiceSeconds)"
LogMessage "dbg" "Total stream length (if unsplit) $totalStreamSeconds $(SecondsToTime $totalStreamSeconds)"
LogMessage "dbg" ""

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
currentStreamState=$( IsStreamRunning )
if ! [ "$currentStreamState" = true ]
then
  # If the stream is not set to be "up" right now, then do nothing and exit the
  # program. We only need to be keep the stream alive if the stream is up.
  LogMessage "dbg" "Live stream is not currently turned on. Network checking is not needed"
  exit 0
fi


#------------------------------------------------------------------------------
# Issue #34: Workaround for YouTube limiting videos to about 12 hours long.
# Issue #44: Make sure the video is split into manageable segments every day.
#
# Check to see if the total video length exceeds maximum length, and if so,
# bounce the stream, to force the video to split the archive.
#------------------------------------------------------------------------------

# Read the value from the file which stores the last time-of-day our camera was
# started (in seconds). This value might be blank or null if running on a fresh
# system due to the file not being present. In theory, value might be later in
# the day than current time, because it might be a value from yesterday. These
# weird situations will likely only occur in debug/test runs, not in normal run
# states. In normal run states, we will only read this value if the stream is
# already started and the value has already been written, because this section
# of code is only executed if the stream is up and running. Worst cases of bad
# values: If this value is blank/null, then the midday bounce will occur at the
# midpoint time of the day even if maybe it wasn't strictly needed. If this
# value is in the future (for example if it was yesterday's value) then the
# bounce will not occur and at worst the debug output will display some
# negative numbers.
if [ -f "$crowcamCamstart" ]
then
  camstartSeconds=$(< "$crowcamCamstart")
fi

# Avoid errors in the math calculations if no camstart value was retrieved.
if test -z "$camstartSeconds" 
then
  camstartSeconds=0
fi

# Calculate how long it's been since our last camstart based on
# $currentTimeSeconds. Although we are farther along in the code than we were
# when $currentTimeSeconds was first retrieved, we shouldn't be very far from
# that actual time. At worst, the wall clock might be several seconds past
# $currentTimeSeconds but that's close enough for our calculations.
secondsSinceCamstart=$(($currentTimeSeconds - $camstartSeconds))

# Part of the fix to issue #47: Calculate the "graced" end of the broadcast
# day, i.e., the expected stream stop time, minus the grace period. This will
# be used when deciding whether to split the stream if the end of the day
# is approaching.
gracedEndOfDay=$(($stopServiceSeconds - $maxVideoLengthGracePeriod))

# Display all values we will be using to base our stream split decision upon.
LogMessage "dbg" ""
LogMessage "dbg" "Camera was last started at                     $camstartSeconds $(SecondsToTime $camstartSeconds) on the clock"
LogMessage "dbg" "Elapsed time since camera was started          $secondsSinceCamstart $(SecondsToTime $secondsSinceCamstart) ago"
LogMessage "dbg" "Max stream length allowed                      $maxVideoLengthSeconds $(SecondsToTime $maxVideoLengthSeconds) long"
LogMessage "dbg" "Grace period length                            $maxVideoLengthGracePeriod $(SecondsToTime $maxVideoLengthGracePeriod) long"
LogMessage "dbg" "Current time (approximate)                     $currentTimeSeconds $(SecondsToTime $currentTimeSeconds) on the clock"
LogMessage "dbg" "End of broadcast day                           $stopServiceSeconds $(SecondsToTime $stopServiceSeconds) on the clock"
LogMessage "dbg" "End of broadcast with grace period subtracted  $gracedEndOfDay $(SecondsToTime $gracedEndOfDay) on the clock"

# Decide if a stream bounce is needed, based on the length of the currently
# recording video stream. Check if the total uptime of the current segment is
# longer than the configured maximum archive length. If so, we're due to
# split the video.
if [ $secondsSinceCamstart -gt $maxVideoLengthSeconds ]
then
  # Fix issue #47: Check if the end of the broadcast day is coming up soon
  # anyway, and if the day's endpoint is within the grace period, then don't
  # bother to bounce the stream.
  if [ $currentTimeSeconds -ge $gracedEndOfDay ]
  then
    # We are within the grace period, don't bounce the stream.
    LogMessage "dbg" "Within grace period, end of day is at $(SecondsToTime $stopServiceSeconds). Current video length $(SecondsToTime $secondsSinceCamstart) exceeds maximum, but not bouncing the stream"
  else
    # The end of the day is not close enough. Bounce the stream.
    LogMessage "info" "Current video length $(SecondsToTime $secondsSinceCamstart) exceeds maximum of $(SecondsToTime $maxVideoLengthSeconds), bouncing the stream for $longBounceDuration seconds"

    # Perform the bounce, but only if we are not in debug mode.
    # Use the long bounce duration here, because we are deliberately trying
    # to split the stream into multiple sections with this bounce.
    if [ -z "$debugMode" ]
    then
      BounceTheStream $longBounceDuration
    else
      LogMessage "dbg" "(Skipping the actual bounce when in debug mode)"
    fi
  fi
fi

# Log a blank line in the debug console output to separate the midday bounce
# reports from the remainder of the output.
LogMessage "dbg" ""


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
  # this point. So here, we only need to set the flag indicating that it is not
  # safe to try to work on the key.
  safeToFixStreamKey=false
else
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
  curlUrl="https://www.googleapis.com/youtube/v3/liveBroadcasts?part=snippet,contentDetails,status&broadcastType=persistent&mine=true&access_token=$accessToken"
  liveBroadcastOutput=""
  liveBroadcastOutput=$( curl -s -m 20 $curlUrl )

  # Debugging output. Only needed if you run into a nasty bug here.
  # Leave deactivated most of the time.
  # LogMessage "dbg" "Live Broadcast output information: $liveBroadcastOutput"

  # Extract the boundStreamId which is needed in order to find the secret key.
  boundStreamId=""
  boundStreamId=$(echo $liveBroadcastOutput | sed 's/"boundStreamId"/\'$'\n&/g' | grep -m 1 "boundStreamId" | cut -d '"' -f4)
  LogMessage "dbg" "boundStreamId: $boundStreamId"
fi

# Make sure the boundStreamId is not empty.
if test -z "$boundStreamId" 
then
  LogMessage "err" "The variable boundStreamId came up empty, during the YouTube Stream Key update. Error accessing YouTube API"
  LogMessage "err" "The liveBroadcastOutput, during the YouTube Stream Key update, was $( echo $liveBroadcastOutput | tr '\n' ' ' )"
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
  # LogMessage "dbg" "Live Streams output information: $liveStreamsOutput"

  # Obtain the secret stream key that is currently being used by my broadcast.
  # Note: This variable is named a bit confusingly. It is called "streamName" in
  # the YouTube API, and identified as "Stream Name/Key" on the YouTube stream
  # management web page. But it's not really a "name" per se, it's really a
  # secret key. We need this key, but we're using the same name as the YouTube
  # API variable name to identify it.
  streamName=""
  streamName=$(echo $liveStreamsOutput | sed 's/"streamName"/\'$'\n&/g' | grep -m 1 "streamName" | cut -d '"' -f4)
  LogMessage "dbg" "Secret YouTube stream name/key for this broadcast (aka streamName): $streamName"

  # Make sure the streamName is not empty.
  if test -z "$streamName" 
  then
    LogMessage "err" "The variable streamName came up empty. Error accessing YouTube API"
    LogMessage "err" "The liveStreamsOutput was $( echo $liveStreamsOutput | tr '\n' ' ' )"
    safeToFixStreamKey=false
  fi
fi

# Fix GitHub issue #27 - extract the stream title which we will use to make
# sure that we're working on the correct stream.
boundStreamTitle=""
boundStreamTitle=$(echo $liveBroadcastOutput | sed 's/"title"/\'$'\n&/g' | grep -m 1 "title" | cut -d '"' -f4)
LogMessage "dbg" "boundStreamTitle: $boundStreamTitle"

# Make sure the stream title is not empty.
if test -z "$boundStreamTitle" 
then
  LogMessage "err" "The variable boundStreamTitle came up empty. Error accessing YouTube API"
  safeToFixStreamKey=false
else
  # If the stream title is not empty, then make sure the title of the stream
  # is the one that we expect it to be. This fixes GitHub issue #27.
  if [[ "$titleToDelete" == "$boundStreamTitle" ]]
  then
    LogMessage "dbg" "Expected stream title $titleToDelete matches YouTube stream title $boundStreamTitle"
  else
    # Log a set of error messages if they do not match.
    LogMessage "err" "Expected stream title does not match YouTube stream title"
    LogMessage "err" "Expected name: $titleToDelete"
    LogMessage "err" "YouTube name:  $boundStreamTitle"
    safeToFixStreamKey=false
  fi
fi

# Fix for issue #37 - Check to make sure that the stream visibility/privacy is
# set to the correct desired setting ("private", "public", or "unlisted").
# Sometimes YouTube glitches, and clobbers this value, causing the stream to
# disappear. The goal is to have it automatically fix this and get the stream
# to go back to a visible/working state again without human intervention.
privacyStatus=""
privacyStatus=$(echo $liveBroadcastOutput | sed 's/"privacyStatus"/\'$'\n&/g' | grep -m 1 "privacyStatus" | cut -d '"' -f4)
LogMessage "dbg" "privacyStatus: $privacyStatus"
if test -z "$privacyStatus"; then safeToFixStreamKey=false; fi

# Make sure the privacyStatus is not empty.
if test -z "$privacyStatus" 
then
  LogMessage "err" "The variable privacyStatus came up empty. Error accessing YouTube API"
  safeToFixStreamKey=false
else
  # If privacyStatus is not empty, check to see if it is the desired value.
  if [[ "$desiredStreamVisibility" == "$privacyStatus" ]]
  then
    LogMessage "dbg" "Expected stream visibility $desiredStreamVisibility matches YouTube stream visibility $privacyStatus"
  else
    # Log an error message if they do not match.
    LogMessage "err" "Expected stream visibility does not match YouTube stream visibility. Expected visibility: $desiredStreamVisibility YouTube visibility: $privacyStatus"
    
    # Retrieve the "id" field, so that the API command can identify which
    # video stream to update.
    thisStreamId=""
    thisStreamId=$(echo $liveBroadcastOutput | sed 's/"id"/\'$'\n&/g' | grep -m 1 "id" | cut -d '"' -f4)
    LogMessage "dbg" "thisStreamId: $thisStreamId"
    if test -z "$thisStreamId"; then safeToFixStreamKey=false; fi

    # In addition to retrieving privacyStatus and id, also retrieve all of
    # these other values. According to the documentation, the API call which
    # performs the fix must include all of these values embedded in the API
    # call itself. My experimentation has found that many of these values
    # might not actually be needed if we're merely updating the privacyStatus
    # field. But since there's not a major cost associated with retrieving all
    # of these values, retrieve them here (the API call was already made, so
    # the API quota is already spent, we merely need to parse them into some
    # variables). Also, I will bad-flag our "safeToFixStreamKey" flag if any
    # of them come out blank, because these values should definitely get
    # retrieved, and if they're not, then something worse is going on with the
    # API, so I shouldn't be making any changes if any of these fields are
    # bad.

    # Note: Parsing "etag" is special because in the output from the server,
    # etag has these extra \" things in the actual field. Like escape codes
    # embedded inside the string. It doesn't seem to require those things in
    # the etag when I send it up to the server, but if I want to parse it when
    # coming down, I need to parse them out. So there is an extra CUT at the
    # end of this parse statement, and it starts on field f5 instead of f4.
    # Not clear? Here's clearer:
    # Instead of parsing this like a sane person:
    #   "etag": "Bdx4f4ps3xCOOo1WZ91nTLkRZ_c/QD47KDPSQZK5sRit4gFAPblFBb8",
    # I'm having to parse this like a crazy person:
    #   "etag": "\"Bdx4f4ps3xCOOo1WZ91nTLkRZ_c/QD47KDPSQZK5sRit4gFAPblFBb8\"",
    etag=""
    etag=$(echo $liveBroadcastOutput | sed 's/"etag"/\'$'\n&/g' | grep -m 1 "etag" | cut -d '"' -f5 | cut -d '\' -f1)
    LogMessage "dbg" "etag: $etag"
    if test -z "$etag"; then safeToFixStreamKey=false; fi

    channelId=""
    channelId=$(echo $liveBroadcastOutput | sed 's/"channelId"/\'$'\n&/g' | grep -m 1 "channelId" | cut -d '"' -f4)
    LogMessage "dbg" "channelId: $channelId"
    if test -z "$channelId"; then safeToFixStreamKey=false; fi
    
    scheduledStartTime=""
    scheduledStartTime=$(echo $liveBroadcastOutput | sed 's/"scheduledStartTime"/\'$'\n&/g' | grep -m 1 "scheduledStartTime" | cut -d '"' -f4)
    LogMessage "dbg" "scheduledStartTime: $scheduledStartTime"
    if test -z "$scheduledStartTime"; then safeToFixStreamKey=false; fi
    
    actualStartTime=""
    actualStartTime=$(echo $liveBroadcastOutput | sed 's/"actualStartTime"/\'$'\n&/g' | grep -m 1 "actualStartTime" | cut -d '"' -f4)
    LogMessage "dbg" "actualStartTime: $actualStartTime"
    if test -z "$actualStartTime"; then safeToFixStreamKey=false; fi
    
    isDefaultBroadcast=""
    isDefaultBroadcast=$(echo $liveBroadcastOutput | sed 's/"isDefaultBroadcast"/\'$'\n&/g' | grep -m 1 "isDefaultBroadcast" | cut -d '"' -f3 | cut -d ' ' -f2 | cut -d ',' -f1)
    LogMessage "dbg" "isDefaultBroadcast: $isDefaultBroadcast"
    if test -z "$isDefaultBroadcast"; then safeToFixStreamKey=false; fi

    liveChatId=""
    liveChatId=$(echo $liveBroadcastOutput | sed 's/"liveChatId"/\'$'\n&/g' | grep -m 1 "liveChatId" | cut -d '"' -f4)
    LogMessage "dbg" "liveChatId: $liveChatId"
    if test -z "$liveChatId"; then safeToFixStreamKey=false; fi
    
    boundStreamId=""
    boundStreamId=$(echo $liveBroadcastOutput | sed 's/"boundStreamId"/\'$'\n&/g' | grep -m 1 "boundStreamId" | cut -d '"' -f4)
    LogMessage "dbg" "boundStreamId: $boundStreamId"
    if test -z "$boundStreamId"; then safeToFixStreamKey=false; fi

    enableMonitorStream=""
    enableMonitorStream=$(echo $liveBroadcastOutput | sed 's/"enableMonitorStream"/\'$'\n&/g' | grep -m 1 "enableMonitorStream" | cut -d '"' -f3 | cut -d ' ' -f2 | cut -d ',' -f1)
    LogMessage "dbg" "enableMonitorStream: $enableMonitorStream"
    if test -z "$enableMonitorStream"; then safeToFixStreamKey=false; fi

    broadcastStreamDelayMs=""
    broadcastStreamDelayMs=$(echo $liveBroadcastOutput | sed 's/"broadcastStreamDelayMs"/\'$'\n&/g' | grep -m 1 "broadcastStreamDelayMs" | cut -d '"' -f3 | cut -d ' ' -f2 | cut -d ',' -f1)
    LogMessage "dbg" "broadcastStreamDelayMs: $broadcastStreamDelayMs"
    if test -z "$broadcastStreamDelayMs"; then safeToFixStreamKey=false; fi

    enableDvr=""
    enableDvr=$(echo $liveBroadcastOutput | sed 's/"enableDvr"/\'$'\n&/g' | grep -m 1 "enableDvr" | cut -d '"' -f3 | cut -d ' ' -f2 | cut -d ',' -f1)
    LogMessage "dbg" "enableDvr: $enableDvr"
    if test -z "$enableDvr"; then safeToFixStreamKey=false; fi

    enableContentEncryption=""
    enableContentEncryption=$(echo $liveBroadcastOutput | sed 's/"enableContentEncryption"/\'$'\n&/g' | grep -m 1 "enableContentEncryption" | cut -d '"' -f3 | cut -d ' ' -f2 | cut -d ',' -f1)
    LogMessage "dbg" "enableContentEncryption: $enableContentEncryption"
    if test -z "$enableContentEncryption"; then safeToFixStreamKey=false; fi

    enableEmbed=""
    enableEmbed=$(echo $liveBroadcastOutput | sed 's/"enableEmbed"/\'$'\n&/g' | grep -m 1 "enableEmbed" | cut -d '"' -f3 | cut -d ' ' -f2 | cut -d ',' -f1)
    LogMessage "dbg" "enableEmbed: $enableEmbed"
    if test -z "$enableEmbed"; then safeToFixStreamKey=false; fi

    recordFromStart=""
    recordFromStart=$(echo $liveBroadcastOutput | sed 's/"recordFromStart"/\'$'\n&/g' | grep -m 1 "recordFromStart" | cut -d '"' -f3 | cut -d ' ' -f2 | cut -d ',' -f1)
    LogMessage "dbg" "recordFromStart: $recordFromStart"
    if test -z "$recordFromStart"; then safeToFixStreamKey=false; fi

    startWithSlate=""
    startWithSlate=$(echo $liveBroadcastOutput | sed 's/"startWithSlate"/\'$'\n&/g' | grep -m 1 "startWithSlate" | cut -d '"' -f3 | cut -d ' ' -f2 | cut -d ',' -f1)
    LogMessage "dbg" "startWithSlate: $startWithSlate"
    if test -z "$startWithSlate"; then safeToFixStreamKey=false; fi

    # Double check that it's safe to fix, before trying to fix. This variable
    # would have been set to "false" if there was a problem with any of the
    # earlier API calls to retrieve the necessary data to perform the fix.
    if [ "$safeToFixStreamKey" = true ]
    then
      # Perform the fix, following the API documentation located here:
      # https://developers.google.com/youtube/v3/live/docs/liveBroadcasts/update
      # The chunk (partially) looks like this in the liveBroadcasts response,
      # and the docs say we must update many of these mutable details (though
      # experimentation shows that I so not have to update all the ones that
      # the docs say I must update):
      #        (...)
      #          "scheduledStartTime": "1970-01-01T00:00:00.000Z",
      #          "actualStartTime": "2019-06-14T20:17:04.000Z",
      #          "isDefaultBroadcast": true,
      #          "liveChatId": "EiEKGFVDcVBaR0Z0QmF1OHJtN3dudgsdgaZEEzZxIFL2xpdmU"
      #         },
      #         "status": {
      #          "lifeCycleStatus": "live",
      #          "privacyStatus": "public",
      #          "recordingStatus": "recording"
      #         },
      #         "contentDetails": {
      #          "boundStreamId": "qPZGFtBau8dfsfasdfScxdA3g1557329171185998",
      #          "boundStreamLastUpdateTimeMs": "2019-05-08T15:26:11.276Z",
      #          "monitorStream": {
      #           "enableMonitorStream": true,
      #           "broadcastStreamDelayMs": 0,
      #        (...)
      # According to the documentation, I must populate the following values
      # since they are are all updated at once. So I retrieved them all, above.
      # (Though it turns out that I don't really need to update all of these.)
      # 
      #    My variable:              API actual variable:
      #
      #    thisStreamId              id
      #    boundStreamTitle          snippet.title
      #    scheduledStartTime        snippet.scheduledStartTime
      #    desiredStreamVisibility   status.privacyStatus
      #    privacyStatus             status.privacyStatus
      #    enableMonitorStream       contentDetails.monitorStream.enableMonitorStream
      #    broadcastStreamDelayMs    contentDetails.monitorStream.broadcastStreamDelayMs
      #    enableDvr                 contentDetails.enableDvr
      #    enableContentEncryption   contentDetails.enableContentEncryption
      #    enableEmbed               contentDetails.enableEmbed
      #    recordFromStart           contentDetails.recordFromStart
      #    startWithSlate            contentDetails.startWithSlate
      #
      # Other values that I have been experimenting with...
      #
      #    "youtube#liveBroadcast"   kind
      #    etag                      etag
      #    actualStartTime           snippet.actualStartTime
      #                              snippet.description
      #    channelId                 snippet.channelId
      #    isDefaultBroadcast        snippet.isDefaultBroadcast
      #    liveChatId                snippet.liveChatId
      #    boundStreamId             contentDetails.boundStreamId
      
      # Populate the scheduledStartTime value (might not be needed). The
      # scheduledStartTime cannot use the existing retrieved variable of
      # "1970-01-01T00:00:00.000Z" because that is the epoch start and the API
      # will throw an error saying "scheduled start time required". You cannot
      # use a predefined start time because it will give a different error
      # saying "Scheduled start time must be in the future and close enough
      # to the current date that a broadcast could be reliably scheduled at
      # that time." We may need to calculate the correct scheduled start time.
      # For instance by taking the current date and adding a few days to it.
      # After more experimentation, the scheduledStartTime seemed to become
      # less important: I stopped getting an error message about how the field
      # needed to specify a specific date in the near future. Perhaps this
      # doesn't need to be updated? Not sure.
      #    scheduledStartTime="2019-06-22T00:00:00.000Z" # Experimental values
      scheduledStartTime="$actualStartTime"
      
      # Build strings for fixing privacyStatus.
      # 
      # Documentation note here: Only supplying the relevant sections, for
      # example, only supplying "id" and "status" but omitting "snippet" and
      # omitting contentDetails, seems to work. Even though the docs say that
      # you also must supply snippet and contentDetails, in my experiments,
      # these sections were not needed for the code to succeed.
      # 
      # Make sure that the sections listed in the "part=" section of the URL
      # are also included in the curlData for the PUT command. In other words,
      # if the URL contains "part=status", then you must also have
      # "status:<some data>" in the JSON data being posted to the API.
      curlUrl="https://www.googleapis.com/youtube/v3/liveBroadcasts?part=id,status&broadcastType=persistent&mine=true&access_token=$accessToken"
      curlData=""
      curlData+="{"
        curlData+="\"id\": \"$thisStreamId\","
        curlData+="\"status\": "
          curlData+="{"
            curlData+="\"privacyStatus\": \"$desiredStreamVisibility\""
          curlData+="}"
      curlData+="}"

      # In the code below, I have commented out the values which are not
      # needed for updating just the privacyStatus, both the ones stated by
      # the docs, as well as my experimental values.
      #
      # Note: If commenting/uncommenting which sections and values get
      # included/excluded, make sure to get the positions of commas correct.
      # For instance, the difference between these statements means the
      # difference between a success and a "parse error", depending on
      # whether there is more data in that section after that line.
      #       curlData+="},"
      #       curlData+="}"
      #
      # curlData+="\"kind\": \"youtube#liveBroadcast\","
      # curlData+="\"etag\": \"$etag\","
      # curlData+="\"snippet\": "
      #   curlData+="{"
      #     #curlData+="\"isDefaultBroadcast\": $isDefaultBroadcast,"                 # no quotes around true/false values
      #     curlData+="\"channelId\": \"$channelId\","
      #     curlData+="\"description\": \"Test Stream\n\\\"Test Description\\\"\","   # experimentation (syntax is correct here for embedded quotes).
      #     curlData+="\"scheduledStartTime\": \"$scheduledStartTime\","
      #     curlData+="\"liveChatId\": \"$liveChatId\","
      #     curlData+="\"title\": \"$boundStreamTitle\""                  
      #   curlData+="},"
      # curlData+="\"contentDetails\": "
      #   curlData+="{"
      #     curlData+="\"monitorStream\": "
      #     curlData+="{"
      #       curlData+="\"enableMonitorStream\": $enableMonitorStream,"              # no quotes around true/false values
      #       curlData+="\"broadcastStreamDelayMs\": $broadcastStreamDelayMs"         # no quotes around numeric values
      #     curlData+="},"
      #     curlData+="\"enableDvr\": $enableDvr,"                                    # no quotes around true/false values
      #     curlData+="\"enableContentEncryption\": $enableContentEncryption,"        # no quotes around true/false values
      #     curlData+="\"enableEmbed\": $enableEmbed,"                                # no quotes around true/false values
      #     curlData+="\"recordFromStart\": $recordFromStart,"                        # no quotes around true/false values
      #     curlData+="\"startWithSlate\": $startWithSlate"                           # no quotes around true/false values
      #   curlData+="}"

      # Perform the fix.
      LogMessage "info" "Fixing privacyStatus to be $desiredStreamVisibility"
      LogMessage "dbg" "curlData: $curlData"
      # LogMessage "dbg" "curlUrl: $curlUrl" # Do not log strings which contain credentials or access tokens.
      streamVisibilityFixOutput=""

      # Important syntax note: In order to be able to update the stream
      # instead of creating a new stream, you must use the PUT feature of Curl
      # rather than the POST feature of Curl. The documentation says that PUT
      # is an "update" command for YouTube, and POST is an "insert" command
      # for YouTube. The trick is, you can't just say "PUT" and then use -d
      # for the data. If you do that, the -d will default to a POST instead of
      # a PUT and that will cause it to do a YouTube API "insert" command
      # (creating a new stream) instead of a YouTube API "update" command.
      # Instead you must use the "-X" aka "--request" command in Curl with the
      # PUT command immediately following the -X. Despite Curl's own
      # documentation stating that the "-X" command shouldn't be needed, it
      # seems to actually be needed, as described in places such as these:
      # https://stackoverflow.com/a/13782211
      # https://www.mkyong.com/web/curl-put-request-examples/
      # ...and even YouTube API's own example code for the Update
      # command.
      streamVisibilityFixOutput=$( curl -s -m 20 -X PUT -H "Content-Type: application/json" -d "$curlData" $curlUrl )
      LogMessage "dbg" "Response from fix attempt streamVisibilityFixOutput: $streamVisibilityFixOutput"

      # Check the response for errors and log the error if there is one.
      # Here is an example of what an error response looks like:
      #         {
      #          "error": {
      #           "errors": [
      #            {
      #             "domain": "global",
      #             "reason": "parseError",
      #             "message": "Parse Error"
      #            }
      #           ],
      #           "code": 400,
      #           "message": "Parse Error"
      #          }
      #         }
      # Note: A "good" response (a response that isn't an error), if that
      # response happens to contain the "snippet" details, might also contain
      # the "description" field of the snipped details. That field might some
      # freeform descriptive text, and I can't control the contents of that
      # text, so there is a chance that it might contain the word "error"
      # somewhere in that text. So try to make this check as specific as
      # possible,  so that if the user has a video description that merely
      # contains the word "error" somewhere in it, it won't false-alarm. 
      if [ -z "$streamVisibilityFixOutput" ] || [[ $streamVisibilityFixOutput == *"\"error\":"* ]] 
      then
        LogMessage "err" "The API returned an error when trying to fix the privacyStatus. The streamVisibilityFixOutput was: $streamVisibilityFixOutput"
      fi
    else
      LogMessage "err" "Unsafe to fix stream visibility due to API issues"
    fi
  fi
fi


# Fix for issue #28 - Check to make sure it is safe to work on the stream key.
# If any of the YouTube API retrievals above failed, then none of this section
# below should get executed. Skip it rather than exiting the program.
if [ "$safeToFixStreamKey" = true ]
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
    LogMessage "dbg" "Local Synology stream key (needs to match YouTube stream name/key): $streamKey"

    # Make sure the streamKey is not empty.
    if test -z "$streamKey" 
    then
        LogMessage "err" "The variable streamKey came up empty. Error accessing Synology API. Exiting program"
        LogMessage "err" "The streamKeyQuery was $( echo $streamKeyQuery | tr '\n' ' ' )"
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
      LogMessage "dbg" "Local Synology stream key matches YouTube stream name/key"
    else
      # Log a set of error messages if they do not match.
      LogMessage "err" "Local Synology stream key does not match YouTube stream name/key"
      LogMessage "err" "Local Key:   $streamKey"
      LogMessage "err" "YouTube Key: $streamName"

      # Write the new key to the Synology configuration automatically. Use the
      # Synology API's "Save" method to set "key=(the new key)". Response is
      # expected to be {"success":true} and will error out of the script if it
      # fails.
      LogMessage "info" "Updating local Synology stream name/key to be $streamName"
      WebApiCall "entry.cgi?api=SYNO.SurveillanceStation.YoutubeLive&method=Save&version=1&key=$streamName" >/dev/null
    fi
  else
    LogMessage "dbg" "Not in a position to obtain the Stream Key of $featureName feature - Will not attempt the Stream Key fix procedure"
  fi
else
  LogMessage "err" "Unable to obtain all of the YouTube API stream data for $titleToDelete live stream - Will not attempt the Stream Key fix procedure"
fi


# ----------------------------------------------------------------------------
# Hourly quick bounce.
#
# If the clock falls within the brief period at the top of the hour, then
# bounce the stream really quick, once. This is intended to work around the
# audio desynchronization issue described in GitHub issue #14. By bouncing the
# stream regularly, it will hopefully keep the audio in synch, at the cost of
# a very short skip in the video stream once per hour. This skip should be
# quick enough so that it doesn't cause a "split" in the YouTube stream.
# ----------------------------------------------------------------------------
if [ "$hourlyQuickBounce" = true ] 
then
  # Integer divide to extract the hours from the script's start time. For
  # example, if it were during the hour of 11:00am, then the number of seconds
  # since midnight would be slightly higher than 39600, and then the formula
  # (( $currentTimeSeconds / 3600 )) would result in "11" because it is a pure
  # integer division with no decimal and no remainder. Then multiplying 11 by
  # 3600 gets the result to exactly 39600.
  hoursSinceMidnightInSeconds=$(( $currentTimeSeconds / 3600 * 3600 ))

  # Integer subtract the hours since midnight to get the remainder, which will
  # be the number of seconds elapsed since the top of the hour.
  secondsSinceTopOfHour=$(( $currentTimeSeconds - $hoursSinceMidnightInSeconds ))
  LogMessage "dbg" "Hours since midnight, in seconds: $hoursSinceMidnightInSeconds. Seconds elapsed since the top of the hour: $secondsSinceTopOfHour"

  # If we are within the short number of seconds since the top of the hour,
  # then perform the hourly bounce.
  if [ "$secondsSinceTopOfHour" -lt "$TopOfTheHourPeriod" ]
  then
    LogMessage "dbg" "Performing quick stream bounce at the top of the hour"
    BounceTheStream 0
  else
    LogMessage "dbg" "Outside of hourly quick stream bounce range, no bounce to perform"
  fi
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
      LogMessage "dbg" "Outer network test loop $mainLoop of $NumberOfTests - Sleeping $PauseBetweenTests seconds"

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
      LogMessage "err" "Status - Network up: $NetworkIsUp - Network problem during outer network test loop $mainLoop of $NumberOfTests - Pausing $PauseBetweenTests seconds to wait for network to come back up. Inner restore attempt loop $restoreLoop of $MaxComebackRetries"

      # Pause before every network test when waiting for it to come back. 
      sleep $PauseBetweenTests

      # Test the network and stream again.
      LogMessage "dbg" "Testing network again"
      Test_Network
      LogMessage "dbg" "Status - Network up: $NetworkIsUp"

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
      LogMessage "info" "Bouncing the YouTube stream since the network came back up, bouncing for $shortBounceDuration seconds"
    else
      # Inform the user that we gave up trying.
      LogMessage "err" "The network is not back up yet. Bouncing YouTube stream anyway, bouncing for $shortBounceDuration seconds"
    fi
    
    # Actually bounce the stream. Using the short bounce duration because maybe
    # it was just a brief blip which only needs a slight correction.
    BounceTheStream $shortBounceDuration
    
    # Exit the program because we should only need to bounce the stream once
    # per run of the program. After bouncing the stream, we can exit this
    # program and let its next timed run (controlled in the Synology Task
    # Scheduler) handle any remaining tests.
    exit 0

    # Because we have bounced the YouTube stream, we no longer need to loop
    # around. Break out of the network test loop. NOTE: With the new code flow,
    # This line should not be hit because the program should have exited by
    # now. Adding an error message at this point to validate that assumption.
    LogMessage "err" "Unexpected program behavior. This program was expected to have exited before this line was reached"
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
    LogMessage "err" "Unexpected program behavior. Reached a point in the code where the NetworkIsUp variable was expected to be true, but it was false"
    exit 1
fi

# Test the stream. Note that the Test_Stream function contains its own inner
# hysteresis loop because the test method might intermittently cry wolf.
Test_Stream

# Log the status of network and stream.
LogMessage "dbg" "Status - Network up: $NetworkIsUp - Stream up: $StreamIsUp"

# If the stream is down, then bounce the stream.
if [ "$StreamIsUp" = false ] 
then
  # Inform the user that we're bouncing the stream.
  LogMessage "err" "Bouncing the YouTube stream for $shortBounceDuration seconds, because the stream was unexpectedly down"
  
  # Bounce the stream. Use the short bounce duration because we are
  # experimenting with the idea that the "VideoIngestionFasterThanRealtime"
  # issue might need only the slightest correction in order to be fixed, so
  # this might result in a quick-fix that doesn't even split the stream.
  BounceTheStream $shortBounceDuration
  
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
# LogMessage "info" "-------------------------- Ending script: $programname -------------------------"

