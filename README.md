# Linux Sensor Monitor
a Perl daemon

## Introduction

Given the availability of HW health sensors on modern PC hardware, with driver support in Linux, have you ever wondered, if it would be possible, to have the sensors monitored by something simple, running on the PC, and have any mischief reported by e-mail? There are tools that can do this for HDD health or for RAID array health, but not for the temperatures and fans, apparently?

Ahh yes, there's been the `sensord`, for decades. And that's apparently the trouble. Bitrot and lack of love have led to sensord's deprecation in major distroes.

And, there's always been the option to install and unleash Net-SNMP's snmpd, which allows for polling access and can also throw traps, and has support for lm-sensors out of the box... but what if this is an isolated system, and you do not want the hassle that is SNMP? What if all you need is just an e-mail when something creeps out of bounds...

And that's how sensormon.pl has come to exist.  

## Example report

    From: sensormon@mymachine.example.com
    To: alarms@example.com
	Subject: Sensormon report: ALARM!!!
    
    This is sensormon at mymachine.example.com .
    acpitz.0.temp1_input=36000
    coretemp.0.temp1_input=39000
    coretemp.0.temp2_input=35000
    coretemp.0.temp3_input=35000
    coretemp.0.temp4_input=39000
    coretemp.0.temp5_input=39000
    it8686.0.fan1_input=0 ERROR <100 <200
    it8686.0.fan2_input=1138
    it8686.0.temp1_input=37000
    it8686.0.temp2_input=56000
    it8686.0.temp3_input=73000 WARNING >70000
    it8686.0.temp4_input=33000
    it8686.0.temp5_input=35000
    it8686.0.temp6_input=34000

## Prerequisites / system requirements

### Sensor drivers in the kernel

Sensormon expects to find its sensors alive under `/sys/class/hwmon` - i.e., expects the correct kernel drivers to have been loaded.

In a modern Linux distro on a modern CPU and BIOS, some sensor drivers will be loaded automatically - such as, the `coretemp` or the `acpitz` . If coretemp is absent, and you have an x86 CPU that's not precambrian or otherwise exotic, `modprobe coretemp` is a no-brainer. To have the module loaded on system startup, specify its name in `/etc/modules` (one module per line, just the bare name without the .ko suffix).

The `sensors-detect` script from the lm-sensors project still does a surprisingly good job of detecting various sensor chips in the system - including not so popular SuperIO chips, for which there is no driver in the kernel, and i2c-attached sensors, that are otherwise difficult to detect.

If you're somewhat converstant in the SuperIO chip brands and models, you'll probably know what to look for on the motherboard, or if you don't have visual access to those guts, the superiotool may help (although it generally feels dated).

SuperIO chips can be useful, as some of them give access to fan tacho inputs and PWM outputs.

As a notable example, let me mention the [it87](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/hwmon/it87.c) driver, catering for several chips by [ITE Tech. Inc.](https://www.ite.com.tw/) In the upstream kernel, this driver actually hasn't been updated for quite some time. There's an updated version [hovering about the Github](https://github.com/xdarklight/hwmon-it87) (check the tree of forks if interested). A few years ago, after some debate, it has been decided *not to* merge these additions upstream, because many of those ITE SuperIO chips (quite popular) for ATOM-based and "mobile" platforms actually contain an Embedded Controller (MCU core) and reportedly there's an unhandled/undocumented race condition between access from the host CPU vs. from the EC MCU, which might lead to unpredictable system misbehaviors... (e.g. freezes). Some people report happy production operation with no problems... To get this updated "out of tree" driver, you need to compile your kernel from source :-(

Obviously you do not need to have all the drivers loaded, for all your physically present sensors, to be able to use software such as sensormon at least for some of them. E.g. coretemp is a low hanging fruit and goes a long way. It's a pity if you don't get information about your fans - but as for PWM control, unless you have a good reason to strive for `fancontrol`, you can as well run with the autonomus feedback in SuperIO chip hardware, which can typically be configured in the BIOS SETUP. 

### Software tidbits
Sensormon.pl is a Perl script, so that's supposed to run just anywhere, right?

Unfortunately, there are further dependencies. Sensormon requires two Perl modules from CPAN: [MIME::Lite](https://metacpan.org/pod/MIME::Lite) for e-mail handling and [Proc::Daemon](https://metacpan.org/pod/Proc::Daemon) for daemonization. Apparently, MIME::Lite is reportedly a little stale, but it does work fine for me and it can send using a smarthost = unlike many alternatives, it does not require a sendmail (or postfix) to be installed.

AFAICT, those two modules are not available as .DEB packages. In order to get them, you need to use the Perl's own module downloader tool called "cpan". And, in turn, the installation of the modules will need to compile some snippets of C, which is controlled by Makefiles. So, you need approximately this sequence:

	apt-get install perl make gcc
	cpan -i MIME::Lite
	cpan -i Proc::Daemon

Along with `sensormon.pl`, you should've obtained an `install.sh` that offers to do this for you, pending your confirmation (there's a y/N prompt).
But, maybe hold your horses with `install.sh` just yet. 

## Installation

Once the required dependencies are in place, we still need to install the sensormon itself, i.e. 2-3 more files:

	/usr/sbin/sensormon.pl
	/etc/sensormon.conf
	/lib/systemd/system/sensormon.service

The last one is a config file for systemd.
You can run `sensormon.pl` stand-alone, or you can have systemd start it for you.

Again you can use the aforementioned `install.sh` to help you with the copying. It does try to install the `sensormon.service` and enable it, no questions asked. It does *not* start the service, because you're still missing the config file.

## Configuration

You may have noticed that **no boilerplate config file** is supplied along with `sensormon.pl`. This is because sensormon can generate a boilerplate config for you, based on the set of sensors that it finds up and running in your Linux system. This is how it works: 

	sensormon.pl -g

...and look for a file called `sensormon.conf.example` in your local directory. Uncomment the sensors that meet your requirements. You can enable daemonization or leave it disabled. (For Systemd, do keep internal daemonization *disabled*!)

A minimalist sensormon.conf could look like this:

    email alarms@example.com
    smtpserver mail.example.com
    
    # Uncomment to have the program detach from the terminal on startup:
    #daemon
    
    # All the time values are in seconds:
    check every 30
    report every 86400
    warn every=43200
    err_every 3600
    # (Mind the erratic underscore and =mark, these are just fine...)
    
    hwmon it8686
     sensor fan2_input min=100 warnlow=200
    hwmon coretemp
     sensor temp1_input warnhigh=55000 max=70000
     sensor temp2_input warnhigh=55000 max=70000
     sensor temp3_input warnhigh=55000 max=70000
     sensor temp4_input warnhigh=55000 max=70000
     sensor temp5_input warnhigh=55000 max=70000

Once you're happy with your initial config, rename the file to `/etc/sensormon.conf` and finally start sensormon. Either by hand, or using 

	systemctl start sensormon

You should get a first e-mail report right away on sensormon startup.

The generated example config file is richly commented, no point in reproducing it all here.

The threshold conditions are all optional. If you want to have a particular sensor included in your e-mailed reports, but not trigger any alarms/warnings, just do not append any threshold conditions - or, set the thresholds safely out of the way, as demonstrated in the generated example.

Note that sensormon ignores any alarm thresholds that may be maintained by the various kernel-space hwmon drivers, as presented by the various "sysfs nodes" in the respective hwmon instance directory. Sensormon has its own thresholds = those configured explicitly in sensormon.conf.

Sensormon also does not make use of the "label" hwmon entries, available from some drivers... feel free to submit a patch if you're missing that perk :-)

When generating the boilerplate config, sensormon only suggests the `fan_input` and `temp_input` "sysfs nodes". But, if you happen to have some other control or output value of interest (say PWM for instance), you can include that in the config file by hand, and sensormon should happily include that in the report.

## Operation

Sensormon runs as a service. Can daemonize itself on startup if desired, or you can let Systemd handle daemonization.

On startup, sensormon scans the contents of `/sys/class/hwmon` for candidate sensors, loads a config file (mandatory), checks if the configured sensors are indeed available, opens their "sysfs device nodes", and periodically checks their values. And, it sends reports by e-mail, to the configured e-mail address, using a configured SMTP server (alternatively, it can also use sendmail locally on the Linux box).

Sensormon can send e-mail reports upon the following occasions:

 - a periodic report, suggested once a day, even if all is fine (like a heartbeat). **The first periodic report is sent on sensormon startup.**
 - a report when a warning condition gets triggered (repeated with configurable periodicity, as long as condition lasts)
 - a report when an error=alarm condition gets triggered (repeated with configurable periodicity, as long as condition lasts)

The *Warning* severity level gets overridden by the *Error=Alarm* severity level.
The warning and alarm repeat-rate timeouts are kept per sensor but get reset globally, for every sensor currently firing, by a report getting generated for whichever sensor.

## References / credits / inspirations

### LM Sensors
= the project that has brought HW monitoring into Linux. 

I seem to recall that decades ago, LM-sensors started as a stand-alone project. There was a sibling project for generic I2C support in Linux = a dependency to LM-sensors. During the years, the kernel drivers of these two projects have been merged into upstream/mainstream Linux, and new ones have been added directly into upstream. There have been changes to the kernel/user interface, and some changes to the kernel-space driver guts (API) as well. The I2C and HWMON drivers now have a life and evolution of their own, as part of the vanilla Linux project.

The LM-sensors project/repository originally lived at lm-sensors.nu, then at lm-sensors.org, by now all that is left of the LM-sensors user space software has found [a home at github](https://github.com/lm-sensors/lm-sensors). The `sensors-detect` utility is still useful, and the `sensors` tool still works too. The `fancontrol` + `pwmconfig` are just as useful as ever. The original `sensord` daemon has meanwhile been deprecated by distroes such as Debian - due to bitrot that has made it struggle under modern Linux. 

The I2C-tools user space programs now have a [repository hosted at kernel.org](https://git.kernel.org/pub/scm/utils/i2c-tools/i2c-tools.git/).

In general, if you're happy with the output of the sysfs interface under /sys/class/hwmon, you do not really need the lm-sensors user space tools anymore.

### Superiotool
A fairly stand-alone [sub-project of Coreboot](https://www.coreboot.org/Superiotool). May help you detect LPC SuperIO chips in your system. Perhaps not kept up to date all that well with the evolution of SuperIO chips. Up to date versions of sensors-detect tend to be more useful.

### mdadm
The Linux vanilla MD RAID user-space config tool and monitoring daemon - [the source code lives at github](https://github.com/neilbrown/mdadm). Its e-mail notification capability has been an inspiration to my sensormon.

### The smartd of smartmontools
The HDD S.M.A.R.T. stats monitoring daemon, from the [smartmontools](https://www.smartmontools.org/) project. Its e-mail notification capability has been an inspiration to my sensormon.

## Author

Frank Rysanek [Frantisek DOT Rysanek (AT) post DOT cz]

## License
I'd prefer something BSD-style. Not sure if Perl or Linux prevent me. My other choice would be GPL v2.

This software is provided as is.
Feel free to use it for whatever you want,
but don't hold me responsible if it eats your... snack. Or whatever.
