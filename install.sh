#!/bin/bash
echo
echo "Prerequisites (not checkin', just sayin'):"
echo " Perl modules MIME::Lite and Proc::Daemon"
echo "It takes perl, cpan, make and gcc to install these."
echo "Should I install these dependencies now ?"

read -p "Your response (y/N) :" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	echo "Okay we're down the waterslide..."
	apt-get install perl make gcc
	cpan -i MIME::Lite
	cpan -i Proc::Daemon
fi

echo
echo "Copying sensormon.pl ..."
cp sensormon.pl /usr/sbin/
echo "Copying sensormon.service ..."
cp sensormon.service /lib/systemd/system/
echo "Enabling sensormon.service ..."
systemctl enable sensormon
echo "Before you try"
echo "   systemctl start sensormon"
echo "you need to create /etc/sensormon.conf  ."
echo "To get a template, just run:"
echo "  sensormon.pl -g"
echo "... and edit sensormon.conf.example, and copy to /etc/sensormon.conf"
echo
