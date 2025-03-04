#!/bin/bash
# BEGIN LICENSE #
#
# CERT Tapioca
#
# Copyright 2018 Carnegie Mellon University. All Rights Reserved.
#
# NO WARRANTY. THIS CARNEGIE MELLON UNIVERSITY AND SOFTWARE
# ENGINEERING INSTITUTE MATERIAL IS FURNISHED ON AN "AS-IS" BASIS.
# CARNEGIE MELLON UNIVERSITY MAKES NO WARRANTIES OF ANY KIND, EITHER
# EXPRESSED OR IMPLIED, AS TO ANY MATTER INCLUDING, BUT NOT LIMITED
# TO, WARRANTY OF FITNESS FOR PURPOSE OR MERCHANTABILITY, EXCLUSIVITY,
# OR RESULTS OBTAINED FROM USE OF THE MATERIAL. CARNEGIE MELLON
# UNIVERSITY DOES NOT MAKE ANY WARRANTY OF ANY KIND WITH RESPECT TO
# FREEDOM FROM PATENT, TRADEMARK, OR COPYRIGHT INFRINGEMENT.
#
# Released under a BSD (SEI)-style license, please see license.txt or
# contact permission@sei.cmu.edu for full terms.
#
# [DISTRIBUTION STATEMENT A] This material has been approved for
# public release and unlimited distribution.  Please see Copyright
# notice for non-US Government use and distribution.
# CERT(R) is registered in the U.S. Patent and Trademark Office by
# Carnegie Mellon University.
#
# DM18-0637
#
# END LICENSE #

user_id=$(whoami)
yum=$(which yum 2>/dev/null)
dnf=$(which dnf 2>/dev/null)
apt=$(which apt-get 2>/dev/null)
zypper=$(which zypper 2>/dev/null)
sudogroup=$(egrep "^wheel:|^sudo:" /etc/group | awk -F: '{print $1}')
tapiocasudo=$(egrep "^$sudogroup" /etc/group | grep tapioca)
arch=$(uname -m)
tshark="/usr/bin/tshark"

if [ -f /etc/os-release ]; then
    source /etc/os-release
fi

if [ -z $(which sudo) ]; then
    echo "sudo command not found"
    echo "Please ensure that sudo is installed before running this installer."
    exit 1
fi

if [ "$user_id" != "tapioca" ] && [ "$user_id" != "root" ]; then
    if [ -z "$apt" ]; then
        # Redhat adduser doesn't prompt to set password
        cat << EOF
Please run this installer as user "tapioca", not $user_id.
For example:
# adduser tapioca
# passwd tapioca
# usermod -aG $sudogroup tapioca
EOF
    else
        # No need to set passwd on Ubuntu-like
        cat << EOF
Please run this installer as user "tapioca", not $user_id.
For example:
# adduser tapioca
# usermod -aG $sudogroup tapioca
EOF
    fi
    exit 1
fi

if [ "$PWD" != "/home/tapioca/tapioca" ]; then
    echo This installer must be run from the /home/tapioca/tapioca directory.
    exit 1
fi

root_privs=$(grep tapioca /etc/sudoers 2>/dev/null)

if [ -n "$root_privs" ] || [ "$user_id" == "root" ]; then
    echo "Please do not run this script with root privileges"
    exit 1
fi

# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
exec > >(tee -i install.log)

# Without this, only stdout would be captured - i.e. your
# log file would not contain any error messages.
# SEE (and upvote) the answer by Adam Spiers, which keeps STDERR
# as a separate stream - I did not want to steal from him by simply
# adding his answer to mine.
exec 2>&1

sudo ls > /dev/null
if [ $? -ne 0 ]; then
  if [ -z "$tapiocasudo" ]; then
      echo "$user_id isn't part of the \"$sudogroup\" group."
      echo "Please run the following command as root and re-run $0:"
      echo "usermod -aG $sudogroup tapioca"
      echo ""
      echo "Logging out and back in again may be required after making this change."
      echo "If you continue to have sudo trouble, ensure that $sudogroup is enabled"
      echo "in the /etc/sudoers file"
      exit 1
  else
      echo "We seem to not be able to use sudo"
      echo "Please run visudo as root and look to see that users in $sudogroup can run commands"
      echo "If they can, you may need to reboot for changes to be made active"
      exit 1
  fi
fi

sudo_configured=$(sudo grep "tapioca ALL=NOPASSWD: ALL" /etc/sudoers)

if [ -z "$sudo_configured" ]; then
    # Don't require password for tapioca sudo
    echo "$user_id isn't properly configured in /etc/sudoers.  Correcting."
    echo "NOTE: You may need to reboot for this change to activate!"
    echo ""
    sudo sh -c "echo 'tapioca ALL=NOPASSWD: ALL' >> /etc/sudoers"
fi

netstat=$(which netstat 2>/dev/null)

# Detect internal and external network adapters
if [ -z "$netstat" ]; then
    detected_external=$(ip route show | egrep "^default " | awk -F' dev ' '{print $2}' | awk '{print $1}' | head -n1)
    detected_internal=$(ip route show | egrep "^10.0.0.0/24 " | awk -F' dev ' '{print $2}' | awk '{print $1}' | head -n1)
else
    detected_external=$(netstat -rn | egrep "^0.0.0.0" | awk '{print $NF}' | head -n1)
    detected_internal=$(netstat -rn | egrep "^10.0.0.0" | awk '{print $NF}' | head -n1)
fi


if [ -n "$detected_external" ]; then
    echo "detected external network adapter: $detected_external"
    # Replace WAN adapter in tapioca.cfg file
    sed -i.bak -e "s/external_net=.*/external_net=$detected_external/" tapioca.cfg
else
    echo "Cannot detect WAN adapter. Be sure to edit tapioca.cfg to specify your device!"
    sleep 10
fi

if [ -n "$detected_internal" ]; then
    echo "detected internal network adapter: $detected_internal"
    # Replace LAN adapter in tapioca.cfg file
    sed -i.bak -e "s/internal_net=.*/internal_net=$detected_internal/" tapioca.cfg
else
    echo "Cannot detect LAN adapter. Be sure to edit tapioca.cfg to specify your device!"
    echo "Recommended configuration is a WiFi adapter that supports HOSTAP or a wired LAN adapter at IP 10.0.0.1/24"
    sleep 10
fi

if [ "$detected_external" = "$detected_internal" ]; then
    echo "Your upstream internet is using the same subnet as the default LAN side (10.0.0.0/24)"
    echo "This will require some manual configuration to avoid conflicts."
    sleep 10
fi

source ./tapioca.cfg

# At some point, I've seen ~/.cache created as root.  That'd be bad.
mkdir -p ~/.cache

if [ ! -f ~/.bash_profile ]; then
    echo "PATH=$PATH" > ~/.bash_profile
fi
path_set=$(egrep "^PATH=" ~/.bash_profile)

if [ -z "$path_set" ]; then
    # there is a ~/.bash_profile file, but no PATH is set
    # so we'll prepend our own
    echo 'PATH=$PATH' > .bash_profile.tmp
    cat ~/.bash_profile >> .bash_profile.tmp
    cp .bash_profile.tmp ~/.bash_profile
fi

if [ -n "$dnf" ] && [ "$ID" == "fedora" ]; then
    # dnf is present. So probably Fedora
    sudo dnf -y group install "Fedora Workstation"
    sudo dnf -y group install xfce "Development tools" "Development Libraries"
    sudo dnf -y install perl-Pod-Html gcc-c++ redhat-rpm-config python3-devel
fi

if [ -n "$yum" ]; then
    #EL and not Fedora
    if [ -n "$PLATFORM_ID" ]; then
      RHELVER=$(echo $PLATFORM_ID | awk -F'el' '{print $2}')
      echo "Detected RHEL / CentOS version $RHELVER ($PLATFORM_ID)"
    else
      RHELVER=$(echo "$VERSION" | grep -oP '^[0-9]+')
      echo "Detected RHEL / CentOS version $RHELVER ($VERSION)"
    fi
      
    sudo yum makecache
    sudo yum -y install epel-release
    if [ $? -ne 0 ]; then
      # Of course things have to be a moving target. Why make things easy when you can choose not to?
      sudo yum config-manager --set-enabled crb
      sudo subscription-manager repos --enable codeready-builder-for-rhel-$RHELVER-$(arch)-rpms
      if [ "$RHELVER" -eq 7 ]; then
        # Weird for a "noarch" RPM to live in an x86_64 directory, but whatevs...
        sudo yum install -y https://archives.fedoraproject.org/pub/archive/epel/7/x86_64/Packages/e/epel-release-7-14.noarch.rpm
        sudo subscription-manager repos --disable=rhel-7-server-e4s-optional-rpms
        sudo subscription-manager repos --disable=rhel-7-server-eus-optional-rpms
      else
        sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-$RHELVER.noarch.rpm
      fi
    fi
    sudo yum -y groupinstall "Development tools" "Server with GUI" xfce "Development Libraries"
    if [ $? -ne 0 ]; then
      # Centos 8 has moved some stuff around
      sudo yum -y groupinstall "Development tools" "Server with GUI" xfce
      if [ -f /etc/yum.repos.d/CentOS-PowerTools.repo ]; then
          sudo sed -i.bak -e 's/^enabled=0/enabled=1/' /etc/yum.repos.d/CentOS-PowerTools.repo
      fi
      sudo yum -y install perl-Pod-Html qt5-devel libpcap-devel libgcrypt-devel
      if [ $? -ne 0 ]; then
        echo We probably have CentOS Stream here.  Installing from PowerTools...
        sudo dnf -y --enablerepo=powertools install perl-Pod-Html qt5-devel libpcap-devel libgcrypt-devel
      fi
    fi

    if [ "$ID" != "fedora" ]; then
      # RHEL / CentOS have an ancient Wireshark.  We'll need to build our own.
      if [ -n "$RHELVER" ] && [ "$RHELVER" -gt 7 ]; then
        tshark=$(which tshark)
      else
        tshark="/usr/local/bin/tshark"
      fi
    fi
fi

if [ -n "$zypper" ]; then
    # Try packages for modern OpenSUSE
    if sudo zypper -n install patterns-devel-base-devel_basis patterns-xfce-xfce_basis \
     man libxml2-devel libxml2 libxslt libxslt-devel python3-devel libopenssl-devel dnsmasq tcpdump \
    dhcp bind-utils nano wget net-tools telnet xdotool nmap xterm \
    tmux iw hostapd mousepad tk-devel \
    glib2-devel libgnutls-devel c-ares-devel libsmi-devel libcap-devel \
    libnl3-devel libpcap-devel gnome-icon-theme \
    conntrack-tools libqt5-qtbase-devel libqt5-linguist snappy-devel \
    libnghttp2-devel libcap-progs NetworkManager-applet gdm dhcp-server \
    net-tools-deprecated xclip sqlite3-devel wireshark; then
      echo Modern OpenSUSE detected
      sudo zypper -n install libGeoIP-devel
      sudo zypper -n install python3-colorama
      sudo zypper -n install libqt4-devel
      if [ $? -ne 0 ]; then
          echo "No Qt4 available. Will configure Tapioca to use PyQt5 installed via pip..."
          pyqt5=1
      fi
    else
      echo Older OpenSUSE detected
      sudo zypper -n install patterns-openSUSE-devel_basis patterns-openSUSE-xfce_basis \
      man libxml2-devel libxml2 libxslt libxslt-devel python3-devel openssl-devel dnsmasq tcpdump \
      dhcp bind-utils nano wget net-tools telnet xdotool nmap xterm \
      tmux iw hostapd wxPython mousepad tk-devel \
      glib2-devel qt-devel gnutls-devel libcares-devel libsmi-devel libcap-devel \
      libGeoIP-devel libnl3-devel libpcap-devel gnome-icon-theme \
      conntrack-tools libqt5-qtbase-devel libqt5-linguist snappy-devel \
      libnghttp2-devel libcap-progs NetworkManager-gnome gdm dhcp-server xclip \
      sqlite3-devel wireshark
      if [ $? -ne 0 ]; then
        echo "Error installing dependency packages. Please check errors and try again."
        exit 1
      fi
    fi
elif [ -n "$yum" ]; then
    # yum is present. EL7 and Fedora.
    sudo yum -y install wxPython
    sudo yum -y install libsq3-devel
    sudo yum -y install dhcp
    sudo yum -y install dhcp-server
    sudo yum -y install libsmi-devel
    sudo yum -y install gnome-icon-theme.noarch
    sudo yum -y install snappy-devel
    sudo yum -y install csnappy-devel
    sudo yum -y install libnghttp2-devel
    sudo yum -y install GeoIP-devel 
    sudo yum -y install libpcap-devel 
    if [ $? -ne 0 ]; then
      echo We probably have CentOS Stream here.  Installing from PowerTools...
      sudo dnf -y --enablerepo=powertools install libnghttp2-devel
    fi
    sudo yum -y install gcc libxml2 libxml2-devel libxslt libxslt-devel \
    openssl-devel dnsmasq tcpdump \
    bind-utils nano chromium wget net-tools telnet xdotool nmap xterm \
    tmux iptables-services iw hostapd mousepad tk-devel \
    glib2-devel gnutls-devel c-ares-devel libcap-devel \
    libnl3-devel libffi-devel \
    conntrack-tools qt5-qtbase-devel qt5-linguist \
    libgcrypt-devel xclip wireshark
    if [ $? -ne 0 ]; then
      echo "Error installing dependency packages. Please check errors and try again."
      exit 1
    fi
    sudo yum -y install PyQt4
    if [ $? -ne 0 ]; then
        echo "No PyQt4 available. Will configure Tapioca to use PyQt5 installed via pip..."
        pyqt5=1
    fi

elif [ -n "$apt" ]; then
    #apt-get is present.  So Debian or ubuntu
    sudo apt-get -y update
    if DEBIAN_FRONTEND=noninteractive sudo -E apt-get -y install chromium; then
      echo Debian-like OS detected
      sudo snap list | grep chromium > /dev/null
      if [ $? -eq 0 ]; then
        # No need to muck with icon on Ubuntu 24.04
        echo "Chromium was installed via snap on modern OS..."
      else
        # Fix Chromium icon
        sed -i.bak -e 's/^Icon=chromium-browser/Icon=chromium/' config/xfce4/panel/launcher-11/14849268213.desktop
      fi
    else
      DEBIAN_FRONTEND=noninteractive sudo -E snap install chromium
      if [ $? -ne 0 ]; then
        echo "snap didn't work. Attempting to apt-get install chromium..."
        DEBIAN_FRONTEND=noninteractive sudo -E apt-get -y install chromium-browser
      else
        # snap-installed chromium doesn't provie an icon.  Because of course.
        sed -i.bak -e 's/^Icon=chromium-browser/Icon=web-browser/' config/xfce4/panel/launcher-11/14849268213.desktop
      fi
      echo Ubuntu-like OS detected
    fi
    DEBIAN_FRONTEND=noninteractive sudo -E apt-get -y install libsqlite3-dev
    DEBIAN_FRONTEND=noninteractive sudo -E apt-get -y install xfce4 xfce4-goodies build-essential libxml2-dev \
    libxslt1-dev libssl-dev dnsmasq tcpdump isc-dhcp-server \
    telnet nano xdotool tmux iptables iw nmap xterm \
    libglib2.0-dev libc-ares-dev libsmi2-dev \
    libcap-dev libgeoip-dev libnl-3-dev libpcap-dev \
    python3-pip wireshark tshark\
    network-manager ethtool hostapd gnome-icon-theme \
    libwiretap-dev zlib1g-dev libcurl4-gnutls-dev curl conntrack iptables-persistent\
    libsnappy-dev libgcrypt-dev ifupdown xclip psmisc
    if [ $? -ne 0 ]; then
      echo "Error installing dependency packages. Please check errors and try again."
      exit 1
    fi
    DEBIAN_FRONTEND=noninteractive sudo -E apt-get -y install libqt4-dev \
    python3-pyqt4 python3-colorama
    if [ $? -ne 0 ]; then
        echo "No PyQt4 available. Will configure Tapioca to use PyQt5 installed via pip..."
        pyqt5=1
    fi
fi

if [ "$arch" == "x86_64" ] || [ "$arch" == "i686" ] || [ "$arch" == "i386" ] || [ "$arch" == "x86" ]; then
  echo We will be able to use miniconda here...
  # If we are using miniconda for our universal python version,
  # we need to install PyQt5 via miniconda.
  pyqt5=1
else
  echo Miniconda is not available on $arch
  # We're going to have to get our own PyQt5 with pip
  # Start with just OpenSUSE for now...
  if [ -n "$zypper" ]; then
    pyqt5=1
  fi
fi

if [ -n "$zypper" ]; then
    sudo zypper -n install chromium
fi

if [ -n "$yum" ] && [ "$ID" != "fedora" ]; then
    if [ -n "$RHELVER" ] && [ "$RHELVER" -gt 7 ]; then
      # new-enough RHEL won't need a compiled wireshark
      sudo yum remove -y pyOpenSSL 2> /dev/null
    else
      # If already installed, these packages can interfere with our Wireshark
      sudo yum remove -y pyOpenSSL wireshark 2> /dev/null
    fi
fi

if [ -n "$apt" ]; then
    # set the default terminal emulator
    sudo update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal.wrapper

    # Newer ubuntu versions have different package names between releases.
    # Don't error out on these if they're not present
    sudo apt-get -y install gnome-icon-theme-full
    sudo apt-get -y install libgnutls-dev
    sudo apt-get -y install libgnutls28-dev
    sudo apt-get -y install libffi-dev
    sudo apt-get -y install network-manager-gnome
    sudo apt-get -y install net-tools
    sudo apt-get -y install qttools5-dev-tools
    sudo apt-get -y install qttools5-dev
    sudo apt-get -y install libnghttp2-dev
    sudo apt-get -y install python-dev
    sudo apt-get -y install python2-dev
    sudo apt-get -y install python3-pyqt4
    sudo apt-get -y install libqt4-dev
    sudo apt-get -y install python-qt4
    sudo apt-get -y install python-colorama
    sudo apt-get -y install libxcb-xinerama0

fi

if [ -f /etc/sysconfig/dhcpd ]; then
    sudo sed -i.bak -e 's/^DHCPD_INTERFACE=""/DHCPD_INTERFACE="ANY"/' /etc/sysconfig/dhcpd
fi

# Make xfce the default for tapioca user
if sudo [ -f /var/lib/AccountsService/users/tapioca ]; then
    # There may be a default session
    sudo egrep "^Session=" /var/lib/AccountsService/users/tapioca > /dev/null
    if [ $? -eq 0 ]; then
        # Match found.  Replace existing Session line
        sudo sed -i.bak -e 's/Session=.*/Session=xfce/' /var/lib/AccountsService/users/tapioca
        sessionset=1
    fi   
    sudo egrep "^XSession=" /var/lib/AccountsService/users/tapioca > /dev/null
    if [ $? -eq 0 ]; then
        # Match found.  Replace existing XSession line
        sudo sed -i.bak -e 's/XSession=.*/XSession=xfce/' /var/lib/AccountsService/users/tapioca
        sessionset=1
    fi
    if [ -z "$sessionset" ]; then
        # Append a new XSession line
        sudo bash -c "echo XSession=xfce >> /var/lib/AccountsService/users/tapioca"
    fi
else
    # Set x-session-manager alternative (Raspberry Pi)
    sudo update-alternatives --set x-session-manager /usr/bin/xfce4-session
    # This file still may not exist if we've never booted with gdm3
    if [ -d /var/lib/AccountsService ]; then
      if sudo [ ! -f /var/lib/AccountsService/users/tapioca ]; then
        sudo bash -c 'echo "[User]" > /var/lib/AccountsService/users/tapioca'
        sudo bash -c 'echo "  XSession=xfce" >> /var/lib/AccountsService/users/tapioca'
        sudo chown root /var/lib/AccountsService/users/tapioca
        sudo chgrp root /var/lib/AccountsService/users/tapioca
        sudo chmod 644 /var/lib/AccountsService/users/tapioca
      fi
    fi

fi

if [ "$ID" = "raspbian" ]; then
    # Switch to using NetworkManager (Raspberry Pi)
    sudo apt-get -y install network-manager-gnome
    sudo apt-get -y purge openresolv dhcpcd5
    sudo ln -sf /lib/systemd/resolv.conf /etc/resolv.conf
fi

# Automatically log in as tapioca user with gdm3 (e.g. Ubuntu)
if [ -f /etc/gdm3/custom.conf ]; then
    # Match found.  Replace existing AutomaticLogin line
    sudo sed -i.bak -e 's/AutomaticLogin=.*/AutomaticLogin=tapioca/' /etc/gdm3/custom.conf
    sudo sed -i.bak -e 's/#  AutomaticLoginEnable = true/AutomaticLoginEnable = true/' /etc/gdm3/custom.conf
    sudo sed -i.bak -e 's/#  AutomaticLogin = user1/AutomaticLogin = tapioca/' /etc/gdm3/custom.conf
    sudo sed -i.bak -e 's/#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf
fi

# Automatically log in as tapioca user with lightdm
if [ -f /etc/lightdm/lightdm.conf ]; then
    # Match found.  Replace existing autologin-user line
    sudo sed -i.bak -e 's/autologin-user=.*/autologin-user=tapioca/' /etc/lightdm/lightdm.conf
fi
while [ -z "$mitmproxy_ok" ]; do
  # Not really a while loop.  Just a "goto" equivalent in case mitmproxy install
  # fails with miniconda
  if [ -n "$skip_miniconda" ] || [ "$ID" == "fedora" ] || ([ "$ID" == "centos" ] && [ "$VERSION_ID" == "8" ]) || ([ "$ID" == "rhel" ] && [ "$VERSION_ID" == "8" ]); then
    echo "We won't attempt to use miniconda on Fedora or CENTOS 8"
    # https://bugzilla.redhat.com/show_bug.cgi?id=1829790
    # Also miniconda recently fails to install mitmproxy due to a conflict with
    # ruamel-yaml.  We can't count on this being fixed.
    unset miniconda_python
  else
    # Check if the miniconda python3.8 binary exists
    if [ ! -f ~/miniconda/bin/python3.8 ]; then
        # install miniconda
        if [ "$arch" == "x86_64" ]; then
            echo "Installing x86_64 miniconda..."
            curl https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh -o miniconda.sh -L
            bash ./miniconda.sh -f -b -p $HOME/miniconda
            if [ $? -eq 0 ]; then
              miniconda_python=1
            fi
        elif [ "$arch" == "i686" ] || [ "$arch" == "i386" ] || [ "$arch" == "x86" ]; then
            echo "Installing x86 miniconda..."
            curl https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86.sh -o miniconda.sh -L
            bash ./miniconda.sh -f -b -p $HOME/miniconda
            if [ $? -eq 0 ]; then
              miniconda_python=1
            fi
        fi
        if [ -f ~/miniconda/bin/python3 ]; then
          # We don't have a python3.8 to run.
          # Miniconda is a moving target, and I don't like this.  But YOLO.
          ln -s ~/miniconda/bin/python3 ~/miniconda/bin/python3.8
        fi
        if [ -d /etc/ld.so.conf.d ]; then
          # PyQt5 will require that libxcb-util.so.1 exists.
          # But it may not be there, like on Debian.  Fun!
          for path in $(grep -h /lib /etc/ld.so.conf.d/*.conf)
          do
            if [ ! -f $path/libxcb-util.so.1 ] && [ -f $path/libxcb-util.so.0 ]; then
              echo $path/libxcb-util.so.1 does not exist!
              echo Symlinking $path/libxcb-util.so.0 to it...
              sudo ln -s $path/libxcb-util.so.0 $path/libxcb-util.so.1
            fi
          done

        fi
    else
        # Miniconda already installed
        miniconda_python=1
    fi
  fi

  if [ -z "$miniconda_python" ]; then
      # No miniconda (e.g. Raspberry Pi), so standard Python install
      python38=$(which python3.8 2> /dev/null)

      if [ -z "$python38" ]; then
        mkdir -p ~/in
        pushd ~/in
        rm -f Python-3.8.19.tgz
        rm -rf Python-3.8.19
        curl -OL https://www.python.org/ftp/python/3.8.19/Python-3.8.19.tgz
        tar xavf Python-3.8.19.tgz
        pushd Python-3.8.19/
        ./configure --prefix=/usr/local && sudo make altinstall
        if [ $? -ne 0 ]; then
          echo "Error building python 3.8. Please check errors and try again."
          exit 1
        fi
        popd; popd
      fi

      if [ -n "$zypper" ]; then
        if [ -d /usr/local/lib64/python3.8/lib-dynload/ ]; then
          echo "Fixing OpenSUSE bug with python outside of /usr/local"
          # https://bugs.python.org/issue34058
          sudo ln -s /usr/local/lib64/python3.8/lib-dynload/ /usr/local/lib/python3.8/lib-dynload
        fi
      fi

  else
      # miniconda python install
      # Check if the PATH var is already set in .bash_profile
      touch ~/.bash_profile
      path_set=$(egrep "^PATH=" ~/.bash_profile | grep $HOME/miniconda/bin)


      if [ -z "$path_set" ]; then
          # Put miniconda path at beginning
          sed -i.bak -e "s@^PATH=@PATH=$HOME/miniconda/bin/:@" ~/.bash_profile
      fi

      sbin_path_set=$(grep PATH= ~/.bash_profile | grep /sbin)

      if [ -z "$sbin_path_set" ]; then
          # Put the sbin paths into the PATH env variable.
          sed -i.bak -e "s@^PATH=@PATH=/sbin:/usr/sbin:@" ~/.bash_profile
      fi


      # Check if the PATH var is already set in .profile
      profile_exists=$(grep PATH= ~/.profile)

      if [ -n "$profile_exists" ]; then
          path_set=$(grep PATH=$HOME/miniconda/bin ~/.profile)
          if [ -z "$path_set" ]; then
              cat ~/.profile > ~/.profile.orig
              echo "PATH=$HOME/miniconda/bin:$PATH" > ~/.profile
              cat ~/.profile.orig >> ~/.profile
          fi
      fi

      xsessionrc_sources=$(grep HOME/.profile ~/.xsessionrc)

      if [ -z "$xsessionrc_sources" ]; then
        # LightDM doesn't source ~/.profile automatically
        echo '. $HOME/.profile' >> ~/.xsessionrc
      fi

      export PATH="$HOME/miniconda/bin:$PATH"

      python38=$(which python3.8 2> /dev/null)

      if [ -z "$python38" ]; then
          # Python 3.8 binary is there, but not in path
          export PATH="$HOME/miniconda/bin:$PATH"
          python38=$(which python3.8 2> /dev/null)
      fi


      if [ -z "$python38" ]; then
          echo "python 3.8 not found in path. Please check miniconda installation."
          echo "Simply removing the ~/miniconda directory can allow for a clean installation."
          exit 1
      fi

  fi


  # Ubuntu with qt5 installed (e.g. UbuFuzz)
  qt5=$(dpkg -l qt5-qmake 2>/dev/null)
  if [ -n "$qt5" ] && [ -n "$apt" ]; then
      # We need qttools5-dev-tools to compile wireshark
      sudo apt-get -y install qttools5-dev-tools
  fi

  # Build Wireshark if tshark isn't there
  if [ ! -f $tshark ]; then
      mkdir -p ~/in
      pushd ~/in
      rm -f wireshark-2.6.20.tar.xz
      rm -rf wireshark-2.6.20
      curl -OL https://www.wireshark.org/download/src/all-versions/wireshark-2.6.20.tar.xz
      tar xavf wireshark-2.6.20.tar.xz
      pushd wireshark-2.6.20/
      ./configure && make && sudo make install
      if [ $? -ne 0 ]; then
        PYTHON=$python38 ./configure && make && sudo make install
        if [ $? -ne 0 ]; then
          echo "Error building Wireshark. Please check errors and try again."
          exit 1
        fi
      fi
      if [ "$ID" = "raspbian" ]; then
          # Wireshark install on raspbian doesn't colorize by default.
          # Why?  Nobody knows.
          mkdir -p ~/.config/wireshark
          cp colorfilters ~/.config/wireshark
      fi
      sudo ldconfig
      popd; popd
  fi

  # Set capture permissions
  sudo setcap cap_net_raw,cap_net_admin+ep $(which dumpcap 2> /dev/null)


  # Confirm pip is there
  if [ -z "$miniconda_python" ]; then
      # No miniconda (e.g. Raspberry Pi), so standard Python install
      mypip=$(which pip3.8 2> /dev/null)
      if [ -z "$mypip" ]; then
        # The detected python 3.8 was not one we compiled/installed
        # There's probably not a "pip3.8" binary
        echo Using already-installed python 3.8
        mypip=$(which pip3 2> /dev/null)
        pipver=$($mypip -V)
        echo Found pip version $pipver
        if [[ "$pipver" != *"3.8"* ]]; then
          echo pip for python 3.8 not found!
          unset $mypip
        fi
      fi
      echo "Using systemwide pip: $mypip"
  else
      # miniconda python
      mypip=$(which pip 2> /dev/null)
      echo "Using miniconda pip: $mypip"
  fi

  if [ -z "$mypip" ]; then
      "python 3.8 not found in path. Please check miniconda installation."
      exit 1
  fi

  if [ -n "$pyqt5" ]; then
    if [ ! -f /usr/bin/qmake ] && [ -f /usr/bin/qmake-qt5 ]; then
      # Fedora (and others?) don't have qmake.  But rather qmake-qt5
      # PyQt5 won't build without "qmake"
      echo Creating symlink to /usr/bin/qmake...
      sudo ln -s /usr/bin/qmake-qt5 /usr/bin/qmake
    fi
    if [ -f /usr/bin/qmake ] && [ -f /usr/bin/qmake-qt5 ]; then
      # OpenSUSE has qmake (for Qt4) and qmake-qt5
      # PyQt5 won't build with Qt4's qmake
      echo Backing up original /usr/bin/qmake...
      sudo mv /usr/bin/qmake /usr/bin/qmake.orig
      echo Creating symlink to /usr/bin/qmake...
      sudo ln -s /usr/bin/qmake-qt5 /usr/bin/qmake
    fi
  fi

  # Install mitmproxy pyshark and deps into miniconda installation
  if [ -n "$miniconda_python" ]; then
      # We have miniconda, so leverage that for what we can
      conda install -y sortedcontainers passlib certifi pyparsing click ruamel_yaml colorama pyopenssl
      $mypip install pyshark GitPython
      $mypip install mitmproxy
      if [ $? -ne 0 ]; then
        echo Trouble installing mitmproxy with $mypip. Retrying python install...
        rm -rf ~/miniconda
        skip_miniconda=1
      else
        mitmproxy_ok=1
      fi

      if [ -n "$pyqt5" ]; then
        #$mypip install PyQt5
        echo "Installing PyQt5 via conda, since we have miniconda..."
        conda install -y pyqt
        if [ $? -ne 0 ]; then
          echo "Problem installing PyQt5 with $mypip. Retrying without miniconda..."
          rm -rf ~/miniconda
          unset mitmproxy_ok
          skip_miniconda=1
        fi
      fi
  else
      # system-wide installed python
      sudo $mypip install colorama pyshark GitPython
      # pip is a moving target and everything is terrible
      # https://techoverflow.net/2022/04/07/how-to-fix-jupyter-lab-importerror-cannot-import-name-soft_unicode-from-markupsafe/
      # https://stackoverflow.com/questions/77213053/why-did-flask-start-failing-with-importerror-cannot-import-name-url-quote-fr
      sudo $mypip install markupsafe==2.0.1 "werkzeug<3.0"
      sudo $mypip install mitmproxy pyshark
      # Clean up old user-specific mitmproxy
      rm ~/.local/bin/mitm*
      

      if [ "$arch" == "aarch64" ]; then
          sudo apt install -y python3-pyqt5
          if [ $? -ne 0 ]; then
            echo "Cannot figure out how to get PyQt5 on this platform. You're on your own here..."
          else
            echo "We've gotten PyQt5 via APT. No need to manually install it"
            unset pyqt5
            echo "Overriding shebang in python code that uses PyQt5 to use system-wide python3"
            sed -i.bak -e 's/#!\/usr\/bin\/env python3.8/#!\/usr\/bin\/env python3/' tapioca.py
            sed -i.bak -e 's/#!\/usr\/bin\/env python3.8/#!\/usr\/bin\/env python3/' noproxy.py
            sed -i.bak -e 's/#!\/usr\/bin\/env python3.8/#!\/usr\/bin\/env python3/' proxy.py
            sed -i.bak -e 's/#!\/usr\/bin\/env python3.8/#!\/usr\/bin\/env python3/' ssltest.py
            sed -i.bak -e 's/#!\/usr\/bin\/env python3.8/#!\/usr\/bin\/env python3/' tcpdump.py
          fi
      fi

      # pip is a moving target and everything is terrible
      # https://techoverflow.net/2022/04/07/how-to-fix-jupyter-lab-importerror-cannot-import-name-soft_unicode-from-markupsafe/
      sudo $mypip install markupsafe==2.0.1

      mitmproxy_ok=1
      if [ -n "$pyqt5" ]; then
        QT_SELECT=qt5 sudo -E $mypip install PyQt5
        if [ $? -ne 0 ]; then
        # At some point in 2022, attempting to install PyQt5 with pip will eat up
        # all available RAM until it dies. Why? Nobody knows.
          echo "Problem installing PyQt5 with $mypip. Retrying with PyQt-builder..."
          sudo $mypip install PyQt-builder PyQt5-sip
          pushd ~/in
          curl -OL https://files.pythonhosted.org/packages/e1/57/2023316578646e1adab903caab714708422f83a57f97eb34a5d13510f4e1/PyQt5-5.15.7.tar.gz
          tar xavf PyQt5-5.15.7.tar.gz
          cd PyQt5-5.15.7
          echo yes | sudo sip-install
          if [ $? -ne 0 ]; then
            # Of course things won't just compile by default
            sed -i.bak -e "s/Q_PID pid() const;/qint64 pid() const;/" ~/in/PyQt5-5.15.7/sip/QtCore/qprocess.sip
            echo yes | sudo /usr/local/bin/sip-install
            if [ $? -ne 0 ]; then
              # Maybe sip-install isn't in the path
              echo yes | sudo /usr/local/bin/sip-install              
              if [ $? -ne 0 ]; then
                # Everything is broken. https://stackoverflow.com/questions/75671456/error-installing-pyqt5-under-aarch64-architecture
                echo "*** Even sip-install for PyQt5 has failed! You'll have to figure out how to get PyQt5 installed for $python38 ***"
              fi
            fi
          fi
          popd
        fi
      fi
    fi
done

# Enable services on boot
if [ -n "$zypper" ]; then
    sudo systemctl set-default graphical.target
    sudo systemctl enable NetworkManager
    sudo systemctl enable dnsmasq
    sudo systemctl enable dhcpd
    sudo systemctl disable firewalld
elif [ -n "$yum" ]; then
    sudo systemctl disable libvirtd
    sudo systemctl enable dnsmasq
    sudo systemctl enable dhcpd
    sudo systemctl disable firewalld
    sudo systemctl enable iptables
elif [ -n "$apt" ]; then
    sudo update-rc.d dnsmasq enable
    sudo update-rc.d isc-dhcp-server enable
fi

# Ubuntu 24.04 takes way too long to boot when it's waiting for a network it doesn't understand.
# Probably can't hurt on other platforms as well
sudo systemctl disable systemd-networkd-wait-online.service

# Save default iptables rule if both network devices detected
if [ "$internal_net" != "LAN_DEVICE" ] && [ "$external_net" !=  "WAN_DEVICE" ] ; then
    # LAN and WAN devices are already configured.  Load passthrough iptables rule
    sudo ./iptables_noproxy.sh
    # Save iptables rule as default
    sudo service iptables save
    sudo iptables-save
    sudo netfilter-persistent save
else
    # Set up basic iptables default deny for incoming traffic

    # Flush existing rules
    sudo iptables -F

    # Set default chain policies
    sudo iptables -P INPUT DROP
    sudo iptables -P FORWARD DROP
    sudo iptables -P OUTPUT ACCEPT

    # Accept on localhost
    sudo iptables -A INPUT -i lo -j ACCEPT
    sudo iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established sessions to receive traffic
    sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    sudo iptables-save
    sudo service iptables save
fi

# The icon names for Wireshark changed in Ubuntu 22.04
# This is why we can't have nice things.
new_wireshark_icons=$(find /usr/share/icons -name "org.wireshark.Wireshark*")

# Copy over preconfigured xfce
if [ -d ~/.config ]; then
    if [ -d ~/.config/xfce4 ]; then
        mv ~/.config/xfce4 ~/.config/xfce4.orig
    fi
else
    mkdir -p ~/.config
fi

if [ -n "$pyqt5" ] && [ -n "$apt" ]; then
  # Prevent stray terminal on Ubuntu 20.04
  sed -i.bak -e "s/Terminal=true/Terminal=false/" config/xfce4/panel/launcher-19/14849278144.desktop
fi

cp -r config/xfce4 ~/.config/
cp config/mimeapps.list ~/.config/

if [ -d ~/.local ]; then
    if [ -d ~/.local/share ]; then
        mv ~/.local/share ~/.local/share.orig
    fi
else
    mkdir -p ~/.local
fi

cp -r local/share ~/.local/

if [ -n "$new_wireshark_icons" ]; then
    find ~/.config/xfce4/panel/ -name "*.desktop" | xargs egrep -l "^Icon=application-wireshark-doc" | xargs -n1 sed -i.bak -e "s/^Icon=application-wireshark-doc/Icon=org.wireshark.Wireshark-mimetype/"
    find ~/.config/xfce4/panel/ -name "*.desktop" | xargs egrep -l "^Icon=wireshark" | xargs -n1 sed -i.bak -e "s/^Icon=wireshark/Icon=org.wireshark.Wireshark/"
    find ~/.local/share/applications/ -name "*.desktop" | xargs egrep -l "^Icon=wireshark" | xargs -n1 sed -i.bak -e "s/^Icon=wireshark/Icon=org.wireshark.Wireshark/"
fi

pushd ~/.local/share/mime
update-mime-database $PWD
popd

mkdir -p ~/tapioca/results

mkdir -p ~/.config/Mousepad
touch ~/.config/Mousepad/mousepadrc
mousepad_wordwrap=$(grep "ViewWordWrap=true" ~/.config/Mousepad/mousepadrc)
if [ -z "$mousepad_wordwrap" ]; then
    # Wrap mousepad long lines by default
    echo ViewWordWrap=true >> ~/.config/Mousepad/mousepadrc
fi
gsettings set org.xfce.mousepad.preferences.view word-wrap true

sudo cp mitmweb.sh /usr/local/bin/

# Start x / xfce on login
if [ -f ~/.xinitrc ]; then
    cp ~/.xinitrc ~/.xinitrc.orig
fi
echo "sudo service dnsmasq restart" > ~/.xinitrc
echo "sudo service dhcpd restart" >> ~/.xinitrc
if [ -n "$RHELVER" ] && [ "$RHELVER" -eq 7 ]; then
  echo 'eval $(dbus-launch --auto-syntax)' >> ~/.xinitrc
  echo 'startxfce4' >> ~/.xinitrc
else
  echo 'DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus exec /usr/bin/xfce4-session' >> ~/.xinitrc
fi
startx=$(grep startx ~/.bash_profile)
if [ -z "$startx" ]; then
    echo startx >> ~/.bash_profile
fi


if [ -n "$apt" ]; then
    # Ubuntu systems need to have network-manager for Tapioca
    sudo mv /etc/network/interfaces /etc/network/interfaces.orig
    sudo cp etc/network/interfaces /etc/network/interfaces
    sudo sed -i.bak -e 's@#DAEMON_CONF=""@DAEMON_CONF="/etc/hostapd/hostapd.conf"@' /etc/default/hostapd
    sudo mv /etc/dnsmasq.d/network-manager /etc/dnsmasq.d/network-manager.orig 2>/dev/null

    if [ -e "/etc/netplan/01-netcfg.yaml" ]; then
        # Ubuntu 17.10 uses networkd instead of NetworkManager.  We need the latter.
        sudo mv /etc/netplan/01-netcfg.yaml /etc/netplan/01-network-manager-all.yaml
        sudo sed -i.bak -e "s/  renderer: networkd/  renderer: NetworkManager/" /etc/netplan/01-network-manager-all.yaml
        sudo netplan apply
        sudo service network-manager restart
    fi

    if [ -e "/etc/netplan/50-cloud-init.yaml" ]; then
        # Ubuntu 18.04 uses networkd instead of NetworkManager.  We need the latter.
        sudo mv /etc/netplan/50-cloud-init.yaml /etc/netplan/01-network-manager-all.yaml
        networkmanager=$(grep "renderer: NetworkManager" /etc/netplan/01-network-manager-all.yaml)
        if [ -z "$networkmanager" ]; then
            sudo bash -c "echo '    renderer: NetworkManager' >> /etc/netplan/01-network-manager-all.yaml"
        fi
        sudo netplan apply
        sudo service network-manager restart
    fi

    # Ubuntu 23.04 seems to need adjustments to make dnsmasq work
    sudo sed -i.bak -e 's/#IGNORE_RESOLVCONF=yes/IGNORE_RESOLVCONF=yes/' /etc/default/dnsmasq
    sudo sed -i.bak -e 's/#DNSMASQ_EXCEPT="lo"/DNSMASQ_EXCEPT="lo"/' /etc/default/dnsmasq
fi

if [ -e "/etc/systemd/resolved.conf" ]; then
    # Ubuntu 18.04 uses systemd-resolve instead of dnsmasq.
    # We need to enable udp-listening resolver.
    udplistener=$(egrep "^DNSStubListener=udp" /etc/systemd/resolved.conf)
    if [ -z "$udplistener" ]; then
        sudo bash -c "echo 'DNSStubListener=udp' >> /etc/systemd/resolved.conf"
    fi
fi

if [ -n "$dnf" ] && [ ! -f /usr/bin/xfce4-session ]; then
    # Fedora can be silly.  It can have xfce installed, but not present.
    # In such a case, remove it and reinstall it.
    sudo dnf -y group remove xfce
    sudo dnf -y group install xfce
fi

# Some distros (e.g. Fedora) may configure dnsmasq to only listen on loopback
if [ -f /etc/dnsmasq.conf ]; then
  loopback_dnsmasq=$(egrep "^interface=lo" /etc/dnsmasq.conf)
  if [ -n "$loopback_dnsmasq" ]; then
    echo Unsetting dnsmasq directive to only bind to loopback...
    sudo sed -i.bak -e "s/^interface=lo/#interface=lo/" /etc/dnsmasq.conf
  fi
  bind_interfaces=$(egrep "^bind-interfaces" /etc/dnsmasq.conf)
  if [ -n "$bind_interfaces" ]; then
    echo Unsetting dnsmasq bind-interfaces directive...
    sudo sed -i.bak -e "s/^bind-interfaces/#bind-interfaces/" /etc/dnsmasq.conf
  fi
fi

# Note that this will only work if installer is being run from within X11
echo "Setting default icon set to gnome..."
xfconf-query -c xsettings -p /Net/IconThemeName -s "gnome"

# Install system-wide config files
sudo cp ~/tapioca/sysctl.conf /etc/
if [ -d /etc/dhcp ]; then
    sudo cp ~/tapioca/dhcpd.conf /etc/dhcp/
fi
if [ -f /etc/dhcpd.conf ]; then
    # Some platforms (e.g. openSUSE) put dhdpd.conf in /etc
    sudo cp ~/tapioca/dhcpd.conf /etc/dhcpd.conf
fi

echo Installation complete!
echo Please reboot and log in.
