CrowCam
==============================================================================
&copy; 2019 by Tony Fabris

https://github.com/tfabris/CrowCam

CrowCam is a set of Bash scripts which control and maintain a webcam in my
backyard. The scripts automate some important tasks which would otherwise be
manual and repetitive, and also work around some unfixed bugs in the streaming
software and in YouTube itself.

This project could be useful to anyone who uses any kind of unattended camera
(not necessarily for bird watching) who wants to stream it to YouTube, but
might have encountered the same problems with YouTube that I did. It's also
a good platform for demonstrating some useful programming techniques. Besides
learning a lot about Bash and shell scripts in general, I learned:

- How to properly fail out of a Bash script while down inside a sub-function,
  since in Bash, "exit 1" doesn't work as expected when inside a function.
- How to access and use the Synology API.
- How to use OAuth to access the YouTube API from a shell script.
- How to parse the output of the YouTube API to learn information about the
  videos uploaded to a YouTube channel.
- How to delete specific videos from a YouTube channel via a shell script.
- Many complex and subtle tricks required when writing scripts that are meant
  to run both in a Linux shell and a MacOS shell. Linux and MacOS have just
  enough in common to get you in trouble when you are moving between them.
- How to script based on Sunrise and Sunset.
- How to work around the Synology bug which prevents the YouTube live stream
  from properly resuming after a network outage.
- How to work around the YouTube bug which prevents users from being able to
  use the live stream's DVR functionality.

------------------------------------------------------------------------------


Table of Contents
==============================================================================
- [Project Information                                                             ](#project-information)
- [Requirements                                                                    ](#requirements)
- [Installation                                                                    ](#installation)
- [Usage and Troubleshooting                                                       ](#usage-and-troubleshooting)
- [What Each Script Does                                                           ](#what-each-script-does)
- [Resources                                                                       ](#resources)
- [Acknowledgments                                                                 ](#acknowledgments)


Project Information
------------------------------------------------------------------------------
The CrowCam is a webcam we use to watch the local crows that we feed in our
backyard. We like to feed them because they are friendly, intelligent, playful,
entertaining, and they [recognize faces](https://youtu.be/0fiAoqwsc9g).
We've even written [songs](https://vixy.dreamwidth.org/794522.html) about them.

It is an IP security camera connected to our Synology NAS, which uses
the Synology Surveillance Station app to record a live feed of the camera. We
then use the "Live Broadcast" feature of Surveillance Station to push the video
stream to our YouTube channel, where anyone can watch.

This project is a suite of related Bash script files:
- [CrowCam.sh - CrowCam Controller                                                 ](#crowcam-sh)
  - Starts and stops the YouTube stream at Sunrise/Sunset, and works
    around a bug in the Synology NAS which is caused by network outages.
- [CrowCamCleanup.sh - CrowCam Cleanup tool                                        ](#crowcamcleanup-sh)
  - Cleans out old YouTube stream archives after a certain number of days.
- [CrowCamKeepAlive.sh - CrowCam Keep Alive tool                                   ](#crowcamkeepalive-sh)
  - Ensures that a YouTube stream's DVR functionality works at all times
    for all users. It works around an unfixed YouTube bug related to DVR
    functionality.
  
These script files will be installed to the Synology NAS, where they will be
launched repeatedly, at timed intervals, using the Synology "Task Scheduler"
feature.


Requirements
------------------------------------------------------------------------------
- A Synology NAS, running its included security camera app, "Synology
  Surveillance Station".
- An IP security camera which is compatible with Synology Surveillance Station.
- A working YouTube live stream, using the "Live Broadcast" feature of
  Surveillance Station to feed the camera's output to the live stream. 
- A free Google Developer account, required to create the OAuth tokens needed
  to access the YouTube account. These tokens are used by CrowCamCleanup to
  delete old stream archives. If you don't already have one, create one at
  https://developers.google.com/
- A Bash shell prompt on your local computer, to execute the preparation
  script, and if desired, to test and debug all of the scripts. This can be on
  a Linux computer, a MacOS computer, or even a Windows computer if you install
  the [Subsystem](https://docs.microsoft.com/en-us/windows/wsl/install-win10).

Setup of your YouTube live stream is not documented here. See the YouTube and
Synology documentation to set this up. Make sure that the camera, NAS, Synology
Surveillance Station, and "Live Broadcast" features are all working correctly,
and that you can see the stream on your YouTube channel.


Installation
------------------------------------------------------------------------------
####  Create API credentials file:
Create an API credentials file named "api-creds" (no file extension),
containing a single line of text: A username, a space, and then a password.
These will be used for connecting to the API of your Synology NAS. Choose an
account on the Synology NAS which has a level of access high enough to connect
to the API, and to turn the Synology surveillance Station "Live Broadcast"
feature on and off. The built-in account "admin" naturally has this level of
access, but you may choose to create a different user for security reasons.
Create the "api-creds" file and place it in the same directory as these
scripts.

####  Get YouTube-dl:
YouTube-dl is a third party program which downloads video streams and other
information from YouTube. We use it for checking and connecting to the YouTube
live stream in an automated fashion. It is used for checking whether the stream
is up, and for making sure that the stream's DVR cache stays functional at all
times. Obtain the latest version of youtube-dl for Linux, and place it in the
same folder as these scripts. Youtube-dl is obtained either by grabbing it from
https://ytdl-org.github.io/youtube-dl/download.html, or by issuing this command
at the Bash shell prompt:

     wget https://yt-dl.org/downloads/latest/youtube-dl -O ./youtube-dl

####  Obtain OAuth credentials:
OAuth credentials are used for giving the CrowCamCleanup script permission to
access the YouTube account, so that it can delete old video stream archives
from the YouTube account's "uploads" directory. Unless something goes wrong,
you should only need create these credentials once.
- Navigate to your Google developer account dashboard at
  https://console.developers.google.com/apis/dashboard
- Create a new project to hold the auth creds. For instance, I have created a
  project called "CrowCam" in my account.
- Once the project is created, select "Credentials" from its left sidebar.
- Select "Create Credentials" and choose "OAuth Client ID".
- It may tell you that you must "Configure consent screen" before you can
  create credentials. If it does this, then configure the consent screen as
  follows:
  - Application Name: CrowCam
  - Press "Save", you don't need to fill anything else out here unless you
    want to.
- Now select "Create Credentials" again and choose "OAuth Client ID".
- Application type: Other.
- Name: CrowCam
- Press "Create".
- A screen will show the client ID and client secret. You do not need to copy
  them to the clipboard, they will be in the file you're about to download.
  Press OK.
- The Credentials screen should now show your credentials. Locate the
  "download" icon on the right side of the screen (a small downard-pointing
  arrow). Press that icon. It should download a client secret file.
- Rename the file that you downloaded to "client_id.json"
- Place the file in the same directory as these script files.

####  Run preparation script, to authorize your YouTube account with OAuth:
Run the CrowCamCleanupPreparation script. You should only need to run this
script once, or, perhaps later if the tokens get invalidated or if there is
an unexpected error. Open a Bash shell on your local PC, in the same folder as
these scripts, set the file permissions, and launch the preparation script:

     chmod 770 CrowCam*.sh
     chmod 770 crowcam-config
     chmod 660 client_id.json
     ./CrowCamCleanupPreparation.sh

- Note: Do not run the preparation script on the Synology itself. Run it on
  your local PC. The script will launch a web browser for authenticating your
  credentials, but launching a web browser does not work on the Synology. The
  script should be relatively good about cross platform compatibility on common
  desktop/laptop computers with a Bash shell available, suchs as a Linux
  computer, a MacOS computer, or even a Windows computer if you install the
  [Subsystem](https://docs.microsoft.com/en-us/windows/wsl/install-win10).

The preparation script will display some messages. Follow its prompts on the
screen, and make sure to follow all instructions and answer all promtps
correctly. If done correctly, a file should now be created in the same
directory as these scripts, named "crowcam-tokens" (no file extension).

Copy the following files to the Synology NAS into /volume1/homes/admin/
(which, if you're connecting to the Synology's SMB share across the network,
is just the volume "home" if you've connected to the fileshare using the
account "admin"):

     CrowCam.sh
     CrowCamCleanup.sh
     CrowCamKeepAlive.sh
     CrowCamHelperFunctions.sh
     crowcam-config
     youtube-dl
     api-creds
     crowcam-tokens
     client_id.json

Once all these files are copied to the NAS, then SSH into the NAS:

     ssh admin@192.168.0.222       (update the address to be your NAS address)

Set the access permissions on all of the files, using the SSH prompt:

     chmod 770 CrowCam*.sh
     chmod 770 crowcam-config
     chmod 770 youtube-dl
     chmod 660 api-creds
     chmod 660 crowcam-tokens
     chmod 660 client_id.json

In the Synology Control Panel, open the Task Scheduler, and create three tasks:
- Type of tasks: "Scheduled Task", "User-defined script"
- General, General Settings: Run all three tasks under User: "root"
- General, General Settings: Name each of the three tasks as follows:
```
     Task:   CrowCam Controller
     Task:   CrowCam Cleanup
     Task:   CrowCam Keep Alive
```
- Schedule: Set all three tasks to run "Daily"
- Schedule: First run time: Set all three tasks to "00:00"
- Schedule: Frequency: 
    - CrowCam Controller: Frequency: "Every Minute"
    - CrowCam Cleanup:    Frequency: "Every Day" 
    - CrowCam Keep Alive: Frequency: "Every 20 Minutes"
- Schedule: Last run time: Set it to the highest number it will let you select
  in the list, which will be different for each one of the tasks. For example,
  for a task that runs every minute, the last run time available will be
  "23:59", a task that runs every 20 minutes will be "23:40", etc.
- Task Settings, Run Command, User-defined script: create a command in each
  task to run each of the the corresponding scripts, for example:
```
     CrowCam Controller:        bash "/volume1/homes/admin/CrowCam.sh"
     CrowCam Cleanup:           bash "/volume1/homes/admin/CrowCamCleanup.sh"
     CrowCam Keep Alive:        bash "/volume1/homes/admin/CrowCamKeepAlive.sh"
```


Usage and Troubleshooting
------------------------------------------------------------------------------
All three scripts should now be running via the Synology Task Manager.

You can look at the Synology Log Center to see if the scripts are running OK.
The scripts will not put much information into the Log Center unless something
goes wrong. When working correctly, they will not be very chatty there, though
expect to see messages in the following situations:
- The Synology log should show a message near sunrise or sunset, when the
  stream is being turned on and off.
- If your local internet connection goes down, you should see Synology log
  entries which indicate that the script is bouncing the "Live Broadcast"
  feature to restart the failed stream.
- When the midnight cleanup is being performed, you should see a Synology log
  which lists how many files are being analyzed, and a message for any deleted
  files.
- If the scripts encounter any major error, the errors should be reported in
  the Synology log.

To troubleshoot a script, or to see more details about how a script is working,
edit the script, locate its debugMode variable, and set it to:

     debugMode="Synology"

You can then do one or both of the following:
- SSH into the Synology NAS and launch the script at the SSH prompt.
  Note: some of the commands in some scripts might require sudo. Example:
```
     sudo ./CrowCam.sh
```
- Edit the "Run Command" for the script in the Synology Task Scheduler, and set
  its stdout/stderr output to a file which you can download and analyze later:
```
     bash "/volume1/homes/admin/(scriptname).sh" >> "/volume1/homes/admin/(scriptname).log" 2>&1
```
Note: Don't leave the debugMode flag set for a long time. The scripts don't
work fully if the debugMode flag is set. For example, the Cleanup script will
only log its intentions in debug mode, but won't actually clean up any files.


What Each Script Does
------------------------------------------------------------------------------
####  CrowCam.sh
CrowCam.sh has two purposes:
- Fixes Synology Bug:
  - There is a very specific bug in Synology Surveillance Station: the "Live
    Broadcast" feature does not automatically restart its YouTube live stream
    after a network interruption. So if you are using Surveillance Station as
    the tool to create an unattended live webcam, then you will lose your
    stream if your network has a brief glitch. This script will bounce the
    Live Broadcast feature if the network blips, automatically restoring the
    stream to functionality, and working around Synology's bug.
- Sunrise/Sunset Scheduling:
  - Turns the YouTube live stream on and off based on the approximate sunrise
    and sunset for the camera's location and timezone. Because crows are
    diurnal, it is not useful to leave the YouTube stream running all of the
    time. For example, there is no point in consuming upstream bandwidth to
    display a YouTube stream which does not have any chance of crow activity.
    Though we could set a simple time-on-the-clock schedule, either via the
    Synology features or the camera features, it's much more useful to base it
    around local sunrise/sunset times, which is closer to the schedule that the
    crows follow. Since sunrise/sunset isn't built-in to Surveillance Station,
    we must code this ourselves. Additionally, this leaves Surveillance Station
    (and all attached cameras) still running 24/7, so that it can still be used
    for its intended security-camera features; the scheduling feature only
    stops and starts the YouTube "Live Broadcast", without touching the rest
    of the security camera features.

####  CrowCamCleanup.sh
Purpose of CrowCamCleanup.sh: 
- Each day, a new CrowCam video is created on our YouTube channel. We don't
  want the channel archives filling up with a bunch of old videos that we're
  not doing anything with.

Solution:
- This script will delete old CrowCam videos from the channel, provided that:
  - The video name is exactly "CrowCam", i.e., the video has not been renamed.
  - The video is old enough, for example, more than 5 days old.
- This allows us to save a favorite video by simply renaming it, and it gives
  us a buffer of a few days to look at recent videos.

####  CrowCamKeepAlive.sh
Purpose of CrowCamKeepAlive.sh:
- To work around a bug in YouTube which prevents users from seeing the history
  of a live video stream. 
  - YouTube has a bug where, if there is nobody watching the live stream, then
    the next person who joins the stream will not be able to scroll backwards in
    the timeline. YouTube calls this feature "DVR functionality", and it should
    theoretically work all the time, allowing any user to scroll up to four
    hours backwards into the live stream. But it does not always work, and the
    reason it doesn't work is not documented by YouTube. I did some experiments,
    and I discovered that as long as somebody is watching the stream, the DVR
    functionality works as expected for that user, and for all subsequent users,
    starting at the moment that the user began watching the stream. But once
    everyone drops off the stream, then about half an hour later, the DVR
    functionality stops working, so later joiners will not be able to scroll
    backwards. Based on these experiments, it looks like YouTube doesn't bother
    to fill their DVR cache unless someone is using it, with a hysteresis
    algorithm that's configured for about 30 minutes or so.

Solution:
- This program works around the bug by making it so that "someone" (i.e., the
  CrowCamKeepAlive script) is always watching the stream intermittently.


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
Many thanks to the multiple people on StackOverflow who were invaluable in
answering many questions, and giving me syntax help with Linux Bash scripts.
Many thanks to the members of the empegBBS who helped with everything else that
I couldn't find on StackOverflow. Thanks Mlord, Peter, Roger, Andy and everyone
else who chimed in. In particular, empegBBS user canuckInOR was the one who
suggested using the YouTube-dl tool, which turned out to be particularly useful
for doing the stream checking and keep-alive features.

Thanks, all!

