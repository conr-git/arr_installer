#!/bin/bash



scriptversion="3.0.9a"
scriptdate="2023-07-14"

set -euo pipefail

echo "Running \*Arr Install Script - Version [$scriptversion] as of [$scriptdate]"

# Am I root?, need root!

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit
fi

echo "Select the application to install: "

select app in lidarr prowlarr radarr readarr whisparr quit; do

    case $app in
    lidarr)
        app_port="8686"                                          # Default App Port; Modify config.xml after install if needed
        app_prereq="curl sqlite3 libchromaprint-tools mediainfo" # Required packages
        app_umask="0002"                                         # UMask the Service will run as
        branch="master"                                          # {Update me if needed} branch to install
        break
        ;;
    prowlarr)
        app_port="9696"           # Default App Port; Modify config.xml after install if needed
        app_prereq="curl sqlite3" # Required packages
        app_umask="0002"          # UMask the Service will run as
        branch="master"          # {Update me if needed} branch to install
        break
        ;;
    radarr)
        app_port="7878"           # Default App Port; Modify config.xml after install if needed
        app_prereq="curl sqlite3" # Required packages
        app_umask="0002"          # UMask the Service will run as
        branch="master"           # {Update me if needed} branch to install
        break
        ;;
    readarr)
        app_port="8787"           # Default App Port; Modify config.xml after install if needed
        app_prereq="curl sqlite3" # Required packages
        app_umask="0002"          # UMask the Service will run as
        branch="develop"          # {Update me if needed} branch to install
        break
        ;;
    whisparr)
        app_port="6969"           # Default App Port; Modify config.xml after install if needed
        app_prereq="curl sqlite3" # Required packages
        app_umask="0002"          # UMask the Service will run as
        branch="nightly"          # {Update me if needed} branch to install
        break
        ;;
    quit)
        exit 0
        ;;
    *)
        echo "Invalid option $REPLY"
        ;;
    esac
done

# Constants
### Update these variables as required for your specific instance
installdir="/opt"              # {Update me if needed} Install Location
bindir="${installdir}/${app^}" # Full Path to Install Location
datadir="/var/lib/$app/"       # {Update me if needed} AppData directory to use
app_bin=${app^}                # Binary Name of the app

if [[ $app != 'prowlarr' ]]; then
    echo "It is critical that the user and group you select to run ${app^} as will have READ and WRITE access to your Media Library and Download Client Completed Folders"
fi

# Prompt User
read -r -p "What user should ${app^} run as? (Default: $app): " app_uid
app_uid=$(echo "$app_uid" | tr -d ' ')
app_uid=${app_uid:-$app}
# Prompt Group
read -r -p "What group should ${app^} run as? (Default: media): " app_guid
app_guid=$(echo "$app_guid" | tr -d ' ')
app_guid=${app_guid:-media}

echo "${app^} selected"
echo "This will install [${app^}] to [$bindir] and use [$datadir] for the AppData Directory"
if [[ $app == 'prowlarr' ]]; then
    echo "${app^} will run as the user [$app_uid] and group [$app_guid]."
else
    echo "${app^} will run as the user [$app_uid] and group [$app_guid]. By continuing, you've confirmed that that user and group will have READ and WRITE access to your Media Library and Download Client Completed Download directories"
fi
echo "Continue with the installation [Yes/No]?"
select yn in "Yes" "No"; do
    case $yn in
    Yes) break ;;
    No) exit 0 ;;
    esac
done

# Create User / Group as needed
if [ "$app_guid" != "$app_uid" ]; then
    if ! getent group "$app_guid" >/dev/null; then
        groupadd "$app_guid"
    fi
fi
if ! getent passwd "$app_uid" >/dev/null; then
    adduser --system --no-create-home --ingroup "$app_guid" "$app_uid"
    echo "Created and added User [$app_uid] to Group [$app_guid]"
fi
if ! getent group "$app_guid" | grep -qw "$app_uid"; then
    echo "User [$app_uid] did not exist in Group [$app_guid]"
    usermod -a -G "$app_guid" "$app_uid"
    echo "Added User [$app_uid] to Group [$app_guid]"
fi

# Stop the App if running
if service --status-all | grep -Fq "$app"; then
    systemctl stop "$app"
    systemctl disable "$app".service
    echo "Stopped existing $app"
fi

# Create Appdata Directory

# AppData
mkdir -p "$datadir"
chown -R "$app_uid":"$app_guid" "$datadir"
chmod 775 "$datadir"
echo "Directories created"
# Download and install the App

# prerequisite packages
echo ""
echo "Installing pre-requisite Packages"
# shellcheck disable=SC2086
apt update && apt install $app_prereq
echo ""
ARCH=$(dpkg --print-architecture)
# get arch
dlbase="https://$app.servarr.com/v1/update/$branch/updatefile?os=linux&runtime=netcore"
case "$ARCH" in
"amd64") DLURL="${dlbase}&arch=x64" ;;
"armhf") DLURL="${dlbase}&arch=arm" ;;
"arm64") DLURL="${dlbase}&arch=arm64" ;;
*)
    echo "Arch not supported"
    exit 1
    ;;
esac
echo ""
echo "Removing previous tarballs"
# -f to Force so we fail if it doesnt exist
rm -f "${app^}".*.tar.gz
echo ""
echo "Downloading..."
wget --content-disposition "$DLURL"
tar -xvzf "${app^}".*.tar.gz
echo ""
echo "Installation files downloaded and extracted"

# remove existing installs
echo "Removing existing installation"
# If you happen to run this script in the installdir the line below will delete the extracted files and cause the mv some lines below to fail.
rm -rf "$bindir"
echo "Installing..."
mv "${app^}" $installdir
chown "$app_uid":"$app_guid" -R "$bindir"
chmod 775 "$bindir"
rm -rf "${app^}.*.tar.gz"
# Ensure we check for an update in case user installs older version or different branch
touch "$datadir"/update_required
chown "$app_uid":"$app_guid" "$datadir"/update_required
echo "App Installed"
# Configure Autostart

# Remove any previous app .service
echo "Removing old service file"
rm -rf /etc/systemd/system/"$app".service

# Create app .service with correct user startup
echo "Creating service file"
cat <<EOF | tee /etc/systemd/system/"$app".service >/dev/null
[Unit]
Description=${app^} Daemon
After=syslog.target network.target
[Service]
User=$app_uid
Group=$app_guid
UMask=$app_umask
Type=simple
ExecStart=$bindir/$app_bin -nobrowser -data=$datadir
TimeoutStopSec=20
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

# Start the App
echo "Service file created. Attempting to start the app"
systemctl -q daemon-reload
systemctl enable --now -q "$app"

# Finish Update/Installation
host=$(hostname -I)
ip_local=$(grep -oP '^\S*' <<<"$host")
echo ""
echo "Install complete"
sleep 10
STATUS="$(systemctl is-active "$app")"
if [ "${STATUS}" = "active" ]; then
    echo "Browse to http://$ip_local:$app_port for the ${app^} GUI"
else
    echo "${app^} failed to start"
fi

# Exit
exit 0
