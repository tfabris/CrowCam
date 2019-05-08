


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
# Work in progress code for making sure the Stream Key is current/updated.
#------------------------------------------------------------------------------
# Get the current live broadcast information details as a prelude to obtaining
# the live stream's current/active "Secret Key" for the default live broadcast
# video on my YouTube channel.
# Some help here: https://stackoverflow.com/a/35329439/3621748
# Best help was here: https://stackoverflow.com/a/40422459/3621748
# Requesting the "part=contentDetails" gets us some variables including
# "boundStreamId". The boundStreamId is needed for obtaining the stream's
# secret key. Note that you could also request things like "part=snippet"
# instead of the "part=contendDetails" to get more info, such as the video
# description text, if you wanted. You can request a bunch of pieces of text
# simultaneously by requesting them all together separated by commas, like
# this: part=id,snippet,contentDetails,status
curlUrl="https://www.googleapis.com/youtube/v3/liveBroadcasts?part=contentDetails&broadcastType=persistent&mine=true&access_token=$accessToken"
liveBroadcastOutput=""
liveBroadcastOutput=$( curl -s $curlUrl )

# Debugging output. Only needed if you run into a nasty bug here.
# Leave deactivated most of the time.
# logMessage "dbg" "Live Broadcast output information: $liveBroadcastOutput"

# Extract the boundStreamId which is needed in order to find the secret key.
boundStreamId=""
boundStreamId=$(echo $liveBroadcastOutput | sed 's/"boundStreamId"/\'$'\n&/g' | grep -m 1 "boundStreamId" | cut -d '"' -f4)
logMessage "dbg" "boundStreamId: $boundStreamId"

# Extract the timestamp to help in determining if the stream has hung up.
# Note: This does not actually help because it describes when the stream's
# details changed, such as the text description, not when the video stream
# itself last got valid data.
boundStreamLastUpdateTimeMs=""
boundStreamLastUpdateTimeMs=$(echo $liveBroadcastOutput | sed 's/"boundStreamLastUpdateTimeMs"/\'$'\n&/g' | grep -m 1 "boundStreamLastUpdateTimeMs" | cut -d '"' -f4)
logMessage "dbg" "boundStreamLastUpdateTimeMs: $boundStreamLastUpdateTimeMs"

# Calculate difference between system current date and the date that was
# given by the API query of the last update time. Warning: I expect these lines
# to fail on MacOS due to Mac having a different "date" command.

# I think these convert to local time automatically. For instance if I put in
# 2019-05-08T15:26:11.276Z (which is 3:26pm UTC) then I get 8:26am output.
# For debugging the various output options for the time stamp, change this
# variable here and force it to the time stamp you want to test:
#     boundStreamLastUpdateTimeMs="2019-05-03T21:24:11.276Z"
lastUpdatePrettyString=$( date -d "$boundStreamLastUpdateTimeMs" )
lastUpdateDateTimeSeconds=$( date -d "$boundStreamLastUpdateTimeMs" +%s )

# So, use local time for your local side of the calculations.
currentDateTimePrettyString=$( date )
currentDateTimeSeconds=$( date +%s )

# Get the difference between the two times.
differenceDateTimeSeconds=$(( $currentDateTimeSeconds - $lastUpdateDateTimeSeconds ))
differencePrettyString=$( SecondsToTime $differenceDateTimeSeconds )

logMessage "dbg" "Date/Time of last YouTube Stream update:  $lastUpdateDateTimeSeconds seconds, $lastUpdatePrettyString"
logMessage "dbg" "Date/Time of current system:              $currentDateTimeSeconds seconds, $currentDateTimePrettyString"
logMessage "dbg" "Stream was last edited:                   $differenceDateTimeSeconds seconds ago, aka $differencePrettyString ago"

# Obtain the stream key from the live stream details, now that we have the 
# variable "boundStreamId" which is the thing that's required to get the key.
# We can query for part=id,snippet,cdn,contentDetails,status, but "cdn" is the
# one we really want, which contains the special key that we're looking for.
# Note: if querying for a specific stream id, you have to remove "mine=true",
# you can only query for "id=xxxxx" or query for "mine=true", not both.
curlUrl="https://www.googleapis.com/youtube/v3/liveStreams?part=cdn&id=$boundStreamId&access_token=$accessToken"
liveStreamsOutput=""
liveStreamsOutput=$( curl -s $curlUrl )

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
logMessage "dbg" "Secret stream key for this broadcast (aka streamName): $streamName"

exit 0





