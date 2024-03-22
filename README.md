CrowCam
==============================================================================
&copy; 2020 by Tony Fabris

https://github.com/tfabris/CrowCam

CrowCam is a set of Bash scripts which control and maintain a webcam in my
backyard. The scripts automate some important tasks which would otherwise be
manual and repetitive, and also work around some unfixed bugs in the streaming
software and in YouTube itself. Including:
- Camera on/off times based on local sunrise/sunset.
- Work around bugs in Synology streaming software which sometimes cause the
  stream to stop working unexpectedly.
- Automatically clean up old YouTube stream archives.

This project could be useful to anyone who uses a Synology NAS, running the
Synology Surveillance Station app, to stream a camera to YouTube, but who might
have encountered the same problems with it that I did. It's also a good
platform for demonstrating some useful programming techniques. These scripts
include well-documented methods for the following things:

- How to script based on sunrise and sunset.
- How to work around the Synology bug which prevents the YouTube live stream
  from properly resuming after a network outage.
- How to work around the Synology bug which causes the YouTube live stream to
  hang with a "spinny death icon".
- How to work around the YouTube bug which randomly resets your live stream's
  secret name/key with no warning.
- How to work around the YouTube bug which randomly resets your live stream's
  public/private/unlisted status with no warning.
- How to work around the YouTube bug which limits the length of your video
  live stream to 12 hours maximum.
- How to clean out old YouTube stream archives automatically via a script.
- How to properly fail out of a Bash script while down inside a sub-function,
  since in Bash, "exit 1" doesn't work as expected when inside a function.
- How to access and use the Synology API.
- How to use OAuth to access the YouTube API from a shell script.
- How to parse the output of the YouTube API to learn information about the
  videos uploaded to a YouTube channel.
- How to delete specific videos from a YouTube channel via a shell script.
- How to write Bash scripts cross-platform, so they can run in a Linux shell,
  a MacOS shell, and Windows Subsystem shell, and which work around the
  inherent differences in the platforms.
- Some techniques for quickly parsing known variables out of HTML or JSON data,
  which work on multiple Bash shell implementations cross-platform, including
  ones which do not have "jq" or other parsers installed.

------------------------------------------------------------------------------


Table of Contents
==============================================================================
- [Project Information                                                             ](#project-information)
- [Requirements                                                                    ](#requirements)
- [What Each Script Does                                                           ](#what-each-script-does)
- [Configuration                                                                   ](#configuration)
- [Usage and Troubleshooting                                                       ](#usage-and-troubleshooting)
- [Resources                                                                       ](#resources)
- [Acknowledgments                                                                 ](#acknowledgments)


Project Information
------------------------------------------------------------------------------
The CrowCam is a webcam we use to watch the local crows that we feed in our
backyard. We like to feed them because they are friendly, intelligent, playful,
entertaining, and they [recognize faces](https://youtu.be/0fiAoqwsc9g).
We've even written [songs](https://vixy.dreamwidth.org/794522.html) about them.

It is an IP security camera connected to our Synology NAS, which uses the
Synology Surveillance Station app to record a live feed of the camera. We then
use the "Live Broadcast" feature of Surveillance Station to push the video
stream to our YouTube channel, where anyone can watch.

This project is a set of related Bash script files, primarily these:
- [CrowCam.sh - CrowCam Controller                                                 ](#crowcamsh)
  - Starts and stops the YouTube stream at Sunrise/Sunset, and detects network
    outages, restarting the stream after an outage if needed.
- [CrowCamCleanup.sh - CrowCam Cleanup tool                                        ](#crowcamcleanupsh)
  - Cleans out old YouTube stream archives after a certain number of days.
  
These script files will be installed to the Synology NAS, where they will be
launched repeatedly, at timed intervals, using the Synology "Task Scheduler"
feature.


Requirements
------------------------------------------------------------------------------
- A Synology NAS. I have developed and tested this on my Synology model
  "DS214play", so your mileage may vary, depending on which NAS model you own
  and which version of the Synology operating system it's running.
- The Synology NAS should be running its included security camera app,
  "Synology Surveillance Station".
- An IP security camera which is compatible with Synology Surveillance Station.
- A working YouTube live stream, using the "Live Broadcast" feature of
  Surveillance Station to feed the camera's output to the live stream. 
- A free Google Developer account, required to create the OAuth tokens needed
  to access the YouTube account. The account is used to access the API to
  delete old stream archives, and to query the stream status. If you don't
  already have an account, create one at https://developers.google.com/
- A Bash shell prompt on your local computer, to execute the preparation
  script, and if desired, to test and debug all of the scripts. This can be on
  a Linux computer, a MacOS computer, or even a Windows computer if you install
  the [Subsystem](https://docs.microsoft.com/en-us/windows/wsl/install-win10).
- These scripts must be set up correctly. See: [Configuration](#configuration).

Setup of your YouTube live stream is not documented here. See the YouTube and
Synology documentation to set this up. First make sure that the camera, NAS,
Synology Surveillance Station, and "Live Broadcast" features are all working
correctly, and that you can see the stream on your YouTube channel. Then you
can begin setting up these scripts.


What Each Script Does
------------------------------------------------------------------------------
There are three main scripts in this archive, which are configured to run on
an automatic timer on the Synology NAS. The three scripts are:

####  CrowCam.sh
This script has multiple purposes:
- Fixes Synology Bugs:
  - There is a very specific bug in Synology Surveillance Station: the "Live
    Broadcast" feature does not automatically restart its YouTube live stream
    after a network interruption. So if you are using Surveillance Station as
    the tool to create an unattended live webcam, then you will lose your
    stream if your network has a brief glitch. This script will bounce the
    Live Broadcast feature if the network blips, automatically restoring the
    stream, and working around Synology's bug.
  - Sometimes YouTube displays a hung stream, showing a "spinning icon of
    death" instead of displaying new video content. This script tries to detect
    when the stream is in this state, and will restart the stream
    automatically, working around this bug.
- Fixes YouTube Bugs:
  - There is a bug in YouTube where it randomly clobbers your live stream's
    secret name/key variable, which causes your YouTube stream to unexpectedly
    stop working, because the variable no longer matches the one that you
    plugged into the Synology Surveillance Station "Live Broadcast" dialog box.
    This script will query the YouTube API, obtain the new key, and make sure
    that the one plugged into the Synology NAS matches the one on YouTube. If
    not, it logs an error message, and then automatically updates the key,
    keeping your stream alive and working around YouTube's bug.
  - There is a bug in YouTube where it randomly clobbers your live stream's
    public/private/unlisted status. For example, if your live stream is set to
    "public", YouTube sometimes randomly changes it to be "unlisted". That
    causes your YouTube stream to unexpectedly go down for anyone watching.
    This script will query the YouTube API, check if this has occurred, and
    fix the setting automatically, bringing the live stream back up and working
    around YouTube's bug.
  - There is a bug in YouTube where it arbitrarily decides that your video's
    archive length must be limited to slightly less than 12 hours maximum. This
    prevents you from recording a long summer day's worth of livestream. If
    your video exceeds that length, YouTube truncates that day's video archive
    file shortly before the 12 hour mark, potentially making you lose the
    archived video of events in the evening. This script works around that bug,
    by making sure the livestream's video segments are limited in length.
- Sunrise/Sunset Scheduling:
  - Turns the YouTube live stream on and off based on the approximate sunrise
    and sunset for the camera's location and timezone. Because crows are
    diurnal, it is not useful to leave the YouTube stream running all of the
    time. For example, there is no point in consuming upstream bandwidth to
    display a YouTube stream during the night when no crows are around. Though
    we could set a simple time-on-the-clock schedule, either via the Synology
    features or the camera features, it's much more useful to base it around
    local sunrise/sunset times, which is closer to the schedule that the crows
    follow. Since sunrise/sunset isn't built-in to Surveillance Station, we
    must code this ourselves. Additionally, this leaves Surveillance Station
    (and all attached cameras) still running 24/7, so that it can still be used
    for its intended security camera features; the scheduling feature only
    stops and starts the YouTube "Live Broadcast", without touching the rest
    of the security camera features.

####  CrowCamCleanup.sh
This script cleans up old archives: 
- Each day, a new set of CrowCam videos is created on the YouTube channel.
  Every video has a default title, in our case, that default title is always
  "CrowCam".
- We don't want the channel archives filling up with a bunch of old videos
  named "CrowCam" that we're not using.
- This script will delete old videos from the channel, provided that:
  - The video name is exactly "CrowCam" (or whatever name is configured), and
    the video has not been renamed.
  - The video is old enough, for example, more than 5 days old. This is also
    configurable.
- This allows us to save interesting videos by simply renaming them from the
  default name, and it gives us a buffer of a few days to look at recent videos
  before they get deleted.


Configuration
------------------------------------------------------------------------------
####  Obtain and unzip the latest files:
- Download the latest project file and unzip it to your hard disk:
  https://github.com/tfabris/CrowCam/archive/master.zip
- (Alternative) Use Git or GitHub Desktop to clone this repository:
  https://github.com/tfabris/CrowCam

####  Edit configuration file:
Edit the file named "crowcam-config" (no file extension), and update the first
several variables in the file. These are values which are unique to your
installation. They are clearly documented in the file.

- _**Optional**_: Instead of editing "crowcam-config", you could also create a
  file in the same folder, named "crowcam-override-config", add a shebang to the
  top of the file (`#!/bin/bash`) and enter any variables that you want to be
  different from crowcam-config. This is useful if, for example, you want to
  subscribe to the GitHub repository and keep the code updated, if you want a
  simpler file to update, or if you want an external program to write small
  configuration changes to the override file.

####  Edit thumbnail file:
Edit the file named "crowcam-thumbnail.jpg" to be your default thumbnail that is
used when a new video stream is created. This must be a JPG that adheres to the
YouTube standards for thumbnail files. Make sure to change it to something that
is appropriate for **your** YouTube channel! The file I've included in the
source code is the one for my YouTube channel, and I'm sure you don't want that.

####  Create API credentials file:
Create an API credentials file named "api-creds" (no file extension),
containing a single line of ASCII text: A username, a space, and then a
password. These will be used for connecting to the API of your Synology NAS.
Choose an account on the Synology NAS which has a level of access high enough
to connect to the Synology API, and which has permission to turn the Synology
Surveillance Station "Live Broadcast" feature on and off. The built-in account
"admin" naturally has this level of access, but you may choose to create a
different user for security reasons. Create the "api-creds" file and place it
in the same directory as these scripts.

####  Obtain OAuth credentials:
OAuth credentials are used for giving these scripts permission to access the
YouTube account, so that it can do things such as clean up old video stream
archives and check on the status of the stream. You should only need create
these credentials once, unless something goes wrong or you revoke the
credentials.
- If you don't have a Google developer account yet, create one at
  https://developers.google.com/
- Navigate to your Google developer account dashboard at
  https://console.developers.google.com/apis/dashboard
- At the top of the screen should be a pull down list that allows you to
  select a project or create a new project.
- Create a new project to hold the auth creds. For instance, I have created a
  project called "CrowCam" in my account.
- Navigate back to the APIs and Services screen and, select "Credentials" from
  its left sidebar: https://console.developers.google.com/apis/credentials
- Select "+ CREATE CREDENTIALS" at the top of the screen and choose "OAuth
  Client ID".
- It may tell you that you must "Configure consent screen" before you can
  create credentials. If it does this, then configure the consent screen as
  follows:
  - User Type (if prompted for it): External
  - Application Name: (whatever application name you want, mine is "CrowCam")
  - Press "Save", you don't need to fill anything else out here unless you
    want to.
- If you had to configure the consent screen, then navigate back to the APIs
   and Services screen, select "Credentials" from the sidebar, select
   "+ CREATE CREDENTIALS" again and choose "OAuth Client ID".
- Application type: "Desktop App".
- Name: (whatever name you want, mine is "CrowCam")
- Press "Create".
- A screen will show the client ID and client secret. You do not need to copy
  them to the clipboard, they will be in the JSON file you're about to
  download. Press OK.
- You may be given a prompt to download a JSON file, if so, download it.
- The Credentials screen should now show your credentials. You can also
  download the JSON file from this screen by pressing the "download" icon on
  the right side of the screen (a small downward-pointing arrow).
- Rename the JSON file that you downloaded to "client_id.json"
- Place the JSON file in the same directory as these script files.

####  Run preparation script, to authorize your YouTube account:
Run the CrowCamCleanupPreparation script. This script will authorize the Google
developer OAuth credentials (created above) to make changes to the YouTube
stream, and then will obtain an all-important refresh token which will allow it
to continue doing it over time, without needing to keep re-authorizing.
You should only need to run this script once, unless the tokens get invalidated
or there is an unexpected error. Open a Bash shell on your local PC, in the
same folder as these scripts. Then set the file permissions and launch the
preparation script using these commands:

     chmod 770 CrowCam*.sh
     chmod 770 crowcam-config
     chmod 660 client_id.json
     ./CrowCamCleanupPreparation.sh

- Note: Do not run the preparation script on the Synology itself. Run it on
  your local PC. The script will launch a web browser for authenticating your
  credentials, but launching a web browser does not work on the Synology. The
  script should be relatively good about cross platform compatibility on common
  desktop/laptop computers with a Bash shell available, such as a Linux
  computer, a MacOS computer, or even a Windows computer if you install the
  [Subsystem](https://docs.microsoft.com/en-us/windows/wsl/install-win10).

The preparation script will display some messages. Follow its prompts on the
screen, and make sure to follow all instructions and answer all promtps
correctly. If done correctly, a file should now be created in the same
directory as these scripts, named "crowcam-tokens" (no file extension).

####  Copy script and configuration files to the NAS
Once the preparation script has run successfully, then create a folder named
"CrowCam" on your the Synology NAS, in the folder /volume1/homes/admin/ by
doing the following:

- Make sure SMB network sharing is turned on for your Synology on your local
  network.
- Connect to the SMB network share of your Synology NAS of the volume "home",
  for example, on MacOS, select the Finder and select Go, Connect to Server,
  and connect to ```smb://192.168.0.222/home``` (or whatever your NAS address
  is). On Windows, you would press Windows+R and enter ```\\192.168.0.222\home```
- When prompted, enter the admin credentials for the NAS.
- This should place you in the "home" folder for the "admin" user. The full
  path of this folder on the NAS is actually ```/volume1/homes/admin/```.
- Create a new folder in this location called "CrowCam".

Copy the following files from your local PC into the folder on the NAS:

     CrowCam.sh
     CrowCamCleanup.sh
     CrowCamHelperFunctions.sh
     crowcam-config
     crowcam-override-config    (if you created one)
     api-creds
     crowcam-tokens
     crowcam-thumbnail.jpg
     client_id.json

Once all these files are copied to the NAS, then SSH into the NAS:

     ssh admin@192.168.0.222      # (update the address to be your NAS address)

Set the access permissions on the folder and its files, using the SSH prompt:

     chmod 770 CrowCam
     cd CrowCam
     chmod 770 CrowCam*.sh
     chmod 770 crowcam-config
     chmod 770 crowcam-override-config
     chmod 660 api-creds
     chmod 660 crowcam-tokens
     chmod 660 crowcam-sunrise
     chmod 660 crowcam-sunset
     chmod 660 crowcam-thumbnail.jpg
     chmod 660 client_id.json

####  Create automated tasks in the Synology Task Scheduler
In the Synology Control Panel, open the Task Scheduler, and create the following
tasks, each task should have the following settings:
- Type of tasks: "Scheduled Task", "User-defined script"
- General, General Settings: Run all three tasks under User: "root"
- General, General Settings: Name each of the tasks as follows:
```
     Task:   CrowCam Controller
     Task:   CrowCam Cleanup
```
- Schedule: Set all tasks to run "Daily"
- Schedule: First run time: "00:00"
- Schedule: Frequency: 
    - CrowCam Controller: Frequency: "Every 5 Minutes"
    - CrowCam Cleanup:    Frequency: "Every 30 Minutes" 
- Schedule: Last run time: Set it to the highest number it will let you select
  in the list, which will be different for each one of the tasks. For example,
  for a task that runs every 5 minutes, the highest run time available will be
  "23:55", a task that runs every 20 minutes will be "23:40", etc.
- Task Settings, Run Command, User-defined script: create a command in each
  task to run each of the the corresponding scripts, for example:
```
     CrowCam Controller:        bash "/volume1/homes/admin/CrowCam/CrowCam.sh"
     CrowCam Cleanup:           bash "/volume1/homes/admin/CrowCam/CrowCamCleanup.sh"
```


Usage and Troubleshooting
------------------------------------------------------------------------------
All three scripts should now be running via the Synology Task Manager.

You can monitor the Synology Log Center, over a long period of time, to see if
the scripts are running OK. The scripts will not put much information into the
Log Center unless something goes wrong. When working correctly, they will not
be very chatty there, though expect to see messages in the following
situations:
- The Synology log should show a message near sunrise or sunset, when the
  stream is being turned on and off.
- The Synology log should show a message each afternoon when the script Googles
  for the sunrise and sunset times for that day.
- If your local Internet connection has a temporary outage, you should see
  Synology log entries which indicate that the script is bouncing the "Live
  Broadcast" feature to restart the failed stream.
- If a new LiveStream gets created, you should see a log entry for that.
- Late at night, you should see a Synology log entry which lists how many
  files are in the playlist on your YouTube channel, being analyzed. You will
  occasionally see a message for any old archived livestream files which are
  being deleted.
- If the scripts encounter any major error, the errors should be reported in
  the Synology log.

To troubleshoot a script, or to see more details about how a script is working,
SSH into the Synology and run it from the shell. From there, you can see all
the "dbg" level messages which aren't shown in the Synology log.

Optionally, you can edit the script, locate the script's debugMode variable at
the top of the script, and temporarily set it to:

     debugMode="Synology"

Changing the debugMode variable is optional. Debug mode will shorten some loops
and will, in some cases, not follow through with writing or deleting certain
pieces of data. You can also run it without debugMode enabled; either way you
will always see "dbg" level messages at the shell prompt if you run it from
there.

If you changed the debugMode of the script, copy the changed version to the
Synology. You can then do one or both of the following:
- SSH into the Synology NAS and launch the script at the SSH prompt. ***Make
  sure to disable the script in the Synology Task Scheduler, and make sure its
  prior iteration is done running, before running the script from the SSH
  prompt.*** To check to see if the script is done running in the Task
  Scheduler, open up Control Panel, Task Scheduler, select the script, and
  press Action, View Result. Look at Current Status and make sure it doesn't
  say "running". Finally, these scripts requires elevation, so when testing on
  the Synology, launch the script with `sudo`. Examples:
```
     sudo ./CrowCam.sh

     or

     sudo -s
     ./CrowCam.sh
```
- Optionally, you can edit the "Run Command" for the script in the Synology Task
  Scheduler, and set its stdout/stderr output to a file which you can download
  and analyze later. This is much more cumbersome though:  
```
     bash "/volume1/homes/admin/CrowCam/(scriptname).sh" >> "/volume1/homes/admin/CrowCam/(scriptname).log" 2>&1
```

- Note that when the script is running from the Synology Task Scheduler, it will
  run under the account "root", which is different from the account that it will
  run under when you are logged in with an SSH prompt. So some differences may
  occur. For example, the script may write a temporary file called
  "wgetcookies.txt" to store cookies when accessing the Synology API, and the
  file might end up in different locations. If running the script directly at
  the SSH prompt, the file will end up in that directory, but if running under
  Synology Task Scheduler, the file will end up in the "/root" folder.

You can also configure the script to one of the other debugMode settings, to
test it on a local Windows or Mac computer, and run the script there. The
debug mode has some limitations when running under Windows or Mac, and will
skip certain commands and features if debugged in those states.

Note: Don't leave the debugMode flag set for a long time. The scripts don't
work fully if the debugMode flag is set. For example, the Cleanup script will
only log its intentions in debug mode, but won't actually clean up any files.
Remember to set the debugMode flag back to normal when you are done.


Resources
------------------------------------------------------------------------------
Initial OAuth script example:
- https://gist.github.com/LindaLawton/cff75182aac5fa42930a09f58b63a309

Refresh token expiration date information:
- https://stackoverflow.com/questions/8953983/do-google-refresh-tokens-expire

YouTube API samples:
- https://developers.google.com/youtube/v3/sample_requests
- https://developers.google.com/youtube/v3/code_samples/apps-script#retrieve_my_uploads

YouTube Video API references, specific details:
- https://developers.google.com/youtube/v3/docs/
- https://developers.google.com/youtube/v3/docs/channels/list
- https://developers.google.com/youtube/v3/docs/playlistItems/list
- https://developers.google.com/youtube/v3/docs/videos/list
- https://developers.google.com/youtube/v3/docs/videos/delete

YouTube's "Scope" for its OAuth authentication, docs:
- https://developers.google.com/youtube/v3/live/authentication
- https://developers.google.com/youtube/v3/live/guides/auth/installed-apps

Google Developer Console:
- https://console.developers.google.com/apis/dashboard

Ideas for how to parse the Json results from the Curl calls:
- https://stackoverflow.com/questions/723157/how-to-insert-a-newline-in-front-of-a-pattern
- https://stackoverflow.com/questions/38364261/parse-json-to-array-in-a-shell-script
- https://stackoverflow.com/questions/2489856/piping-a-bash-variable-into-awk-and-storing-the-output


Acknowledgments
------------------------------------------------------------------------------
Many thanks to the multiple people on StackOverflow, whose posts were
invaluable in answering many questions, and giving me syntax help with Linux
Bash scripts. Many thanks to the members of the empegBBS who helped with
everything else that I couldn't find on StackOverflow. Thanks Mlord, Peter,
Roger, Andy and everyone else who chimed in. 

Thanks, all!

