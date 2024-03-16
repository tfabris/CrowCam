#!/bin/bash

#------------------------------------------------------------------------------
# CrowCamCleanupPreparation.sh - Prepare auth tokens for CrowCamCleanup.sh.
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
# This script obtains a refresh token for the Google API for controlling your
# YouTube live stream video channel. Once this script is successful, it should
# not need to be run a second time, because the refresh token should stay good.
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
# technique was learned here: https://stackoverflow.com/a/246128/3621748
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Load the configuration file "crowcam-config", which contains variables that
# are user-specific.
source "$DIR/crowcam-config"

# Load the include file "CrowCamHelperFunctions.sh", which contains shared
# functions that are used in multiple scripts.
source "$DIR/CrowCamHelperFunctions.sh"

#------------------------------------------------------------------------------
# Main Script Code Body
#------------------------------------------------------------------------------

# Log current script location and working directory.
echo "Script exists in directory: $DIR"
echo "Current working directory:  $(pwd)"

# Verify that the necessary external files exist.
if [ ! -e "$clientIdJson" ]
then
  # Instruct the user to look at the instructions which tell you how to get
  # this file at the start of the installation process.
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
  echo ""
  echo "The variable clientId came up empty. Error parsing json file. Exiting program."
  echo "The clientIdOutput was $( echo $clientIdOutput | tr '\n' ' ' )"
  echo ""
  exit 1
fi

# Make sure the clientSecret is not empty.
if test -z "$clientSecret" 
then
  echo ""
  echo "The variable clientSecret came up empty. Error parsing json file. Exiting program."
  echo "The clientIdOutput was $( echo $clientIdOutput | tr '\n' ' ' )"
  echo ""
  exit 1
fi

# Log what we retrieved.
echo ""
echo "Client ID:     $clientId"
echo "Client Secret: $clientSecret"
echo ""


#------------------------------------------------------------------------------
# Authorize the account to make changes to your YouTube Channel
#------------------------------------------------------------------------------
#
# This authorization must be requested with the correct scope. I have found
# success with the "Installed application flow", also known as "Desktop app".
# The description is here:
#
#    https://developers.google.com/youtube/v3/live/guides/auth/installed-apps
#
# This uses the scope variable of "https://www.googleapis.com/auth/youtube".
# That scope variable is part of the URL defined below. Note: do not use the
# "device flow" or "devices" type or the "youtube.upload" scope; those won't
# allow the right scopes. My initial try didn't work due to the oauth scope
# being wrong. It resulted in error "Insufficient Permission: Request had
# insufficient authentication scopes." So make sure you use the "Installed
# application flow" or "desktop app" scope.
#
# GitHub issue #69 - Fix Google's deprecation of the the "OOB" flow. This
# is Google's choice to remove the option that showed the user a dialog box
# where they could copy and paste the authorization key. Details of the
# deprecation are here:
#
# https://developers.google.com/identity/protocols/oauth2/resources/oob-migration
#
# Originally this was done by a redirect URL in the authorization request which
# looks like this: "redirect_uri=urn:ietf:wg:oauth:2.0:oob" - which is a
# special code to tell Google to put up the dialog box which displays the auth
# code. That has now been removed from Google and we can't use it any more.
#
# The fix for this is somewhat onerous, because it requires you to sift out the
# code yourself.
#
# Here's how it works. The script code below sets the redirect URL to your own
# localhost web address, "redirect_uri=http://localhost/requestheaders.html".
# When Google calls this, it will make a query to your "application" (i.e.,
# whatever this script put into the parameter "redirect_uri=").
#
# Then after you complete the auth steps in your web browser, then Google
# will cause your web browser to redirect and open up the following page:
# 
#   http://localhost/requestheaders.html?code=4/0ASDF1234...etc...&scope=https://www.googleapis.com/auth/youtube
#
# The important part of the request in this case is the "code=" part. I
# personally have created the web page file "requestheaders.html" on my
# localhost site which uses the PHP command "$_SERVER['QUERY_STRING'];" to echo
# back the code. You, however, don't need to go to that much trouble. Just wait
# until it tries to open your localhost web site. If you have a localhost web
# site running, it will open that localhost site, and if you don't, it will say
# something similar to "This site can't be reached". Either way, whether it's
# successful or not, the code will be there in the URL bar, as part of the URL.
# the URL will look like the one above. Copy the URL (make sure it has "?code="
# and "&scope=" in it) and paste it when prompted by the script below.
#
# Old code with the deprecated "oob" redirect:
#      authUrl="https://accounts.google.com/o/oauth2/auth?client_id=$clientId&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/youtube&response_type=code"
# New code with the localhost requestheaders.html in the redirect:
authUrl="https://accounts.google.com/o/oauth2/auth?client_id=$clientId&redirect_uri=http://localhost/requestheaders.html&scope=https://www.googleapis.com/auth/youtube&response_type=code"
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
echo " - Google may display a prompt that it hasn't verified this app,"
echo "   so it may be unsafe. Press the ADVANCED link and then press"
echo "   GO TO AppName (unsafe). This is OK to do because it is referring"
echo "   to the OAuth credentials that you created yourself."
echo ""
echo " - Grant the app the permission to manage your YouTube account."
echo "   This is done by pressing the CONTINUE button."
echo ""
echo " - The web browser will try to open the web page at http://localhost."
echo ""
echo " - Your http://localhost page may open if you have one, or if not,"
echo "   your browser may display the message THIS SITE CAN'T BE REACHED"
echo "   (or something similar). either way, look in the URL bar and find"
echo "   the code. It will be between the words ?code= and &scope="
echo ""
echo "   Example:"
echo "           localhost/requestheaders.html?code=(THE CODE)&scope=..."
echo ""
echo " - Copy the URL to the clipboard, then close the browser and come"
echo "   back to this window."
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

      # "Start" is the windows version, and in the Windows version, we have to
      # escape URL ampersands by adding a caret before each one, or else
      # Windows will interpret the ampersands as line splitters. Here I am
      # telling SED to replace all ampersands (\& - escaped becuase ampersand
      # is a special command character for SED) with a caret and ampersand
      # (^\&), and to replace them all (/g).
      authUrl="$( echo "$authUrl" | sed "s/\&/^\&/g" )"
      
      # Debugging, in case you still have problems with the URL:
      # echo "Auth URL updated: $authUrl"

      # Special handling of windows command needed, in order to make it
      # compatible with multiple different flavors of Bash on Windows. For
      # example, Git Bash will take "start" directly, but the Linux Subsystem
      # For Windows 10 needs it put into cmd.exe /c in order to work. Also, the
      # backticks are needed or else it doesn't always work properly.
      `cmd.exe /c "start $authUrl"`
      if [[ $? != 0 ]]
      then
        # If none of the various attempts to launch the browser, above,
        # succeeded, then I give up, I don't know what to do. Throw an error.
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
echo "-------------------------------------------------------------------"
echo "PASTE the URL (or just the code), here now:"

# Read input from user, and time out if they don't enter it within 360 seconds.
read -r -t 360 authenticationCode

# Strip leading and trailing whitespace from the variable in case it was pasted
# clumsily. This is done with one of those "cheap tricks" in Bash. I hope this
# trick is portable. Trick was obtained from a non-green-checkmark answer here:
# https://stackoverflow.com/a/12973694/3621748
authenticationCode=$( echo "$authenticationCode" | xargs )

# If the user happened to paste in the entire URL that would work too. We will
# strip out the code by finding everything in between "?code=" and "&scope="
# and use only that part.
if [[ "$authenticationCode" == *"?code="* ]]
then
  # If this is a correct URL, the code will begin after the first equals sign.
  echo "Trimming after ?code="
  authenticationCode=$( echo "$authenticationCode" | cut -d '=' -f2 )
fi
if [[ "$authenticationCode" == *"&scope"* ]]   # The equals after scope= was already removed, don't search for it.
then
  # If this is a correct URL, the code will end before the first ampersand.
  echo "Trimming up to &scope" 
  authenticationCode=$( echo "$authenticationCode" | cut -d '&' -f1 )
fi

# Give the user a chance to view if the authentication code looks correct.
# It should appear as if in a box on the screen without any extra spaces or
# carriage returns on either side of it.
echo ""
echo "Authentication code:"
echo "--------------------------------------------------------------------------"
echo "---------$authenticationCode--------"
echo "--------------------------------------------------------------------------"
echo ""

# Make sure the authenticationCode is not empty.
if test -z "$authenticationCode" 
then
  echo ""
  echo "The variable authenticationCode came up empty. Error obtaining code. Exiting program."
  echo ""
  exit 1
fi


#------------------------------------------------------------------------------
# Obtain the Refresh token
#------------------------------------------------------------------------------
# This exchanges the authentication code (obtained above) for a Refresh token.
# This can only be done once, and subsequent times it will get an error.

refreshTokenOutput=""

# GitHub issue #69 - Fix Google's deprecation of the the "OOB" flow.
# Old code with the deprecated "oob" redirect:
# refreshTokenOutput=$( curl -s --request POST --data "code=$authenticationCode&client_id=$clientId&client_secret=$clientSecret&redirect_uri=urn:ietf:wg:oauth:2.0:oob&grant_type=authorization_code" https://accounts.google.com/o/oauth2/token )

refreshTokenOutput=$( curl -s --request POST --data "code=$authenticationCode&client_id=$clientId&client_secret=$clientSecret&redirect_uri=http://localhost/requestheaders.html&grant_type=authorization_code" https://accounts.google.com/o/oauth2/token )

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
  echo "The variable refreshToken came up empty. Unknown error. Exiting program."
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
  echo "The variable accessToken came up empty. Error accessing API. Exiting program."
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

