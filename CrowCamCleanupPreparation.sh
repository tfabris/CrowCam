#!/bin/bash

#------------------------------------------------------------------------------
# CrowCamCleanupPreparation.sh - Prepare auth tokens for CrowCamCleanup.sh
#------------------------------------------------------------------------------
# Please see the accompanying file REAMDE.md for setup instructions. Web Link:
#        https://github.com/tfabris/CrowCam/blob/master/README.md
#
# The scripts in this project don't work "out of the box", they need some
# configuration. All details are found in README.md, so please look there
# and follow the instructions.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Note: This CrowCamCleanupPreparation.sh script only needs to be run once.
#------------------------------------------------------------------------------
# Once this script is successful, it should not need to be run a second time.
#
# YouTube API access requires an OAuth 2.0 access key and a refresh token. My
# research seems to indicate that the refresh token does not have an
# expiration date, though it can be revoked under the following circumstances:
#       - The user has revoked access.
#       - The token has not been used for six months.
#       - The user account has exceeded a certain number of token requests.
#         There is currently a 25-token limit per Google user account. If a
#         user account has 25 valid tokens, the next authentication request
#         succeeds, but quietly invalidates the oldest outstanding token
#         without any user-visible warning.
#
# If it becomes revoked, then the script may need to be re-run. Also, if you
# lose the refresh token, you might need to re-run this script to get another.
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Startup configuration variables 
#------------------------------------------------------------------------------

# Get the directory of the current script so that we can find files in the
# same folder as this script, regardless of the current working directory. The
# technique was learned from the following post:
# https://stackoverflow.com/questions/59895/get-the-source-directory-of-a-bash-script-from-within-the-script-itself
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Create a variable for the "client_id.json" file, we will read from this file.
clientIdJson="$DIR/client_id.json"

# Create a variable for the "crowcam-tokens" file, we will write to this file.
crowcamTokens="$DIR/crowcam-tokens"


#------------------------------------------------------------------------------
# Main Script Code Body
#------------------------------------------------------------------------------

# Log current script location and working directory.
echo "Script exists in directory: $DIR"
echo "Current working directory:  $(pwd)"

# Verify that the necessary external files exist.
if [ ! -e "$clientIdJson" ]
then
  echo ""
  echo "Missing file $clientIdJson"
  echo " - Follow the instructions in the README.md file accompanying this"
  echo "   script to obtain the client_id.json and put in in the same"
  echo "   directory."
  echo ""
  exit 1
fi


#------------------------------------------------------------------------------
# Read client ID and client secret from the client_id.json file
#------------------------------------------------------------------------------

# Place contents of file into a variable.
clientIdOutput=$(< "$clientIdJson")

# Parse the Client ID and Client Secret out of the results. The commands work
# like this:
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
  echo ""
  echo "The variable clientId came up empty. Error parsing json file. Exiting program"
  echo "The clientIdOutput was $( echo $clientIdOutput | tr '\n' ' ' )"
  echo ""
  exit 1
fi

# Make sure the clientSecret is not empty.
if test -z "$clientSecret" 
then
  echo ""
  echo "The variable clientSecret came up empty. Error parsing json file. Exiting program"
  echo "The clientIdOutput was $( echo $clientIdOutput | tr '\n' ' ' )"
  echo ""
  exit 1
fi

echo ""
echo "Client ID:     $clientId"
echo "Client Secret: $clientSecret"
echo ""


#------------------------------------------------------------------------------
# Authorize the account to make changes to your YouTube Channel
#------------------------------------------------------------------------------
#
# This authorization must be requested with the correct scope. I have found
# success with the "Installed application flow", the description is here:
#
#    https://developers.google.com/youtube/v3/live/guides/auth/installed-apps
#
# This uses the scope variable of "https://www.googleapis.com/auth/youtube".
# That scope variable is part of the URL defined below. Note: do not use the
# "device flow" or "devices" type or the "youtube.upload" scope; those won't
# allow the right scopes. My initial try didn't work due to the oauth scope
# being wrong. It resulted in error "Insufficient Permission: Request had
# insufficient authentication scopes." So make sure you use the "Installed
# application flow" scope, https://www.googleapis.com/auth/youtube.
#
authUrl="https://accounts.google.com/o/oauth2/auth?client_id=$clientId&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/youtube&response_type=code"
echo "Authorization URL: $authUrl"

echo ""
echo "----------------------------------------------------------------------"
echo "     About to open your default web browser for authorization."
echo "----------------------------------------------------------------------"
echo ""
echo "When the browser opens, remember to do the following:"
echo ""
echo " - Log into Google with your main user account if needed."
echo ""
echo " - If you are given an option to select the Brand Account for your"
echo "   YouTube channel, then choose that Brand Account."
echo ""
echo " - Grant the app the permission to manage your YouTube account."
echo ""
echo " - It will give you an authentication code. Important: copy that"
echo "   authentication code to the clipboard."
echo ""
echo " - Once the code is copied to the clipbard, close the browser and"
echo "   come back to this window."
echo ""
read -n 1 -s -r -p "Press any key when you are ready to perform these steps."
echo ""

# Attempt to open in whatever browser works on whatever OS the user is running
# upon. If the command fails then move on to the next possibility, and so on.
# These are all variations of the "start" or "open" command on various flavors
# of Linux, MacOS and Windows. One of them will hopefully work.
echo "Attempting to launch web browser with xdg-open..."
xdg-open "$authUrl"
if [[ $? != 0 ]]
then
  echo "Attempting to launch web browser with open..."
  open "$authUrl"
  if [[ $? != 0 ]]
  then
    echo "Attempting to launch web browser with python -mwebbrowser..."
    python -mwebbrowser "$authUrl"
    if [[ $? != 0 ]]
    then
      echo "Attempting to launch web browser with start..."

      # Special handling of windows command needed, in order to make it
      # compatible with multiple different flavors of Bash on Windows. For
      # example, Git Bash will take "start" directly, but the Linux Subsystem
      # For Windows 10 needs it put into cmd.exe /c in order to work. Also, the
      # backticks are needed or else it doesn't always work properly.
      #
      # Also, we have to escape URL ampersands by adding a caret before each
      # one, or else windows will interpret them as line splitters. Here I am
      # telling SED to replace all ampersands (\& - escaped becuase ampersand
      # is a special command character for SED) with a caret and ampersand
      # (^\&), and to replace them all (/g).
      authUrl="$( echo "$authUrl" | sed "s/\&/^\&/g" )"
      echo "Auth URL updated: $authUrl"
      `cmd.exe /c "start $authUrl"`
      if [[ $? != 0 ]]
      then
        echo ""
        echo "Unable to launch web browser. There has been an unknown error."
        echo "You many be running this on a system which cannot use any of the"
        echo "common commands for starting a browser from a script."
        echo "Exiting program."
        echo ""
        exit 1
      fi
    fi
  fi
fi

echo ""
echo "---------------------------------------"
echo "PASTE the authentication code here now:"

# Read input from user, and time out if they don't enter it within 360 seconds.
read -r -t 360 authenticationCode
echo ""
echo "Authentication code: $authenticationCode"
echo ""

# Make sure the authenticationCode is not empty.
if test -z "$authenticationCode" 
then
  echo ""
  echo "The variable authenticationCode came up empty. Error obtaining code. Exiting program"
  echo ""
  exit 1
fi

#------------------------------------------------------------------------------
# Obtain the Refresh token
#------------------------------------------------------------------------------
# This exchanges the authentication code (obtained above) for a Refresh token.
# This can only be done once, and subsequent times it will get an error.

refreshTokenOutput=""
refreshTokenOutput=$( curl -s --request POST --data "code=$authenticationCode&client_id=$clientId&client_secret=$clientSecret&redirect_uri=urn:ietf:wg:oauth:2.0:oob&grant_type=authorization_code" https://accounts.google.com/o/oauth2/token )
echo ""
echo "Refresh Token Output:"
echo "$refreshTokenOutput"
echo ""
refreshToken=""
refreshToken=$(echo $refreshTokenOutput | sed 's/"refresh_token"/\'$'\n&/g' | grep -m 1 "refresh_token" | cut -d '"' -f4)
echo ""
echo "The refresh token is:"
echo "$refreshToken"

# Make sure the refreshToken is not empty.
if test -z "$refreshToken" 
then
  echo ""
  echo "The variable refreshToken came up empty. Unknown error. Exiting program"
  echo "The refreshTokenOutput was $( echo $refreshTokenOutput | tr '\n' ' ' )"
  echo ""
  exit 1
fi

#------------------------------------------------------------------------------
# Test the Refresh token
#------------------------------------------------------------------------------

# The refresh token we now have in the $refreshToken variable is the "gold"
# item. It is the thing that allows us to repeatedly access the YouTube API
# with the correct credentials. It is the "long lasting" part, which, when
# combined with the client ID and client secret, will give us the ability
# to retrieve multiple temporary access tokens later on.
#
# However, before saving it to a file...
#
# Test the refresh token to make sure it is correct. Do this by obtaining a
# temporary access token based on the refresh token. The CrowCamCleanup.sh
# script will be doing this step every time that it starts up, so this test is
# insurance that it will work when it gets run. Also, if this test fails, we
# won't write the token to the file, so that we don't accidentally overwrite
# an earlier, potentially-good file.

accessTokenOutput=""
accessTokenOutput=$( curl -s --request POST --data "client_id=$clientId&client_secret=$clientSecret&refresh_token=$refreshToken&grant_type=refresh_token" https://accounts.google.com/o/oauth2/token )

# Parse the Access Token out of the results, using the same techniques as
# described elsewhere in this file.
accessToken=""
accessToken=$(echo $accessTokenOutput | sed 's/"access_token"/\'$'\n&/g' | grep -m 1 "access_token" | cut -d '"' -f4)

# Make sure the Access Token is not empty.
if test -z "$accessToken" 
then
  echo ""
  echo "The variable accessToken came up empty. Error accessing API. Exiting program"
  echo "The accessTokenOutput was $( echo $accessTokenOutput | tr '\n' ' ' )"
  echo ""
  exit 1
fi

# Log the access token to the output.
echo ""
echo "Temporary Test Access Token: $accessToken"
echo ""

# Final step: Write the refresh token to our crowcam-tokens file.
# use "-n" to ensure it does not write a trailing newline character.
echo -n "$refreshToken" > "$crowcamTokens"

echo "File Written: $crowcamTokens"
echo "Complete."

