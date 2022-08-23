#!/usr/bin/perl

my $cfg_filename = "/etc/sensormon.conf";
my $contact_email = undef; # can be set here, or in the config file
my $smtpserver = undef;    # can be set here, or in the config file
my $do_daemonize = 0;
my $check_every  =    30;  # seconds. # Feel free to override in the config file.
my $report_every = 86400;  # seconds. # Feel free to override in the config file.
my $warn_every   = 43200;  # seconds. # Feel free to override in the config file.
my $err_every    =  7200;  # seconds. # Feel free to override in the config file.
# The warn and err timers are kept per sensor.

my $generate_conf = 0;
my $example_conf_filename = "sensormon.conf.example";
my $example_conf_fd;
my $arg1 = @ARGV[0];

if (($arg1 =~ /^-g$/) || ($arg1 =~ /^--generate-conf.*$/))
{
	$generate_conf = 1;
}
elsif (($arg1 =~ /^-h$/) || ($arg1 =~ /^--help$/))
{
	print "\n$0 usage instructions:\n\n";
	print "Valid command-line args:\n";
	print "   -h or --help : display this help\n";
	print "   -g or --generate-conf : generate a $exampe_conf_filename\n";
	print "	     The $example_conf_filename will list the sensors\n";
	print "      found in the system = only those for which a driver module\n";
	print "      is loaded and the sensor HW is actually present.\n";
	print "\n";
	print "You do not strictly need the lm-sensors package (user space tools).\n";
	print "Feel free to use sensors-detect initially to find your HW sensors and\n";
	print "to get a listing of the desired kernel driver modules, but $0\n";
	print "does not need or use sensors.conf.\n";
	print "$0 expects its own config in a file called $cfg_filename .\n";
	print "Feel free to change the name and location of the config file\n";
	print "at the top of the Perl script that is $0 itself.\n";
	print "$0 uses /sys/class/hwmon/* to find the sensors and to read them.\n";
	print "\n";

	exit 0;
}


#use Sys::Hostname::FQDN;
use Net::Domain qw (hostname hostfqdn hostdomain);
my $machine_name = hostfqdn();
my $sender_addr = "sensormon@" . $machine_name;
#print "Sender address: $sender_addr\n";

if ($generate_conf)
{
	open($example_conf_fd, ">", $example_conf_filename) || die " Couldn't open example config file for output: $!";

	print $example_conf_fd "# A hash mark starts a comment (for that line only).\n";
	print $example_conf_fd "# Empty lines are legitimate and ignored.\n";
	print $example_conf_fd "\n";
	print $example_conf_fd "email alarms\@example.com\n";
	print $example_conf_fd "smtpserver mail.example.com\n";
	print $example_conf_fd "# You can leave the smtpserver undefined, if you have the \"sendmail\"\n";
	print $example_conf_fd "# command present and correctly configured in your local system.\n";
	print $example_conf_fd "\n";
	print $example_conf_fd "# Uncomment to have the program detach from the terminal on startup:\n";
	print $example_conf_fd "#daemon\n";
	print $example_conf_fd "\n";
	print $example_conf_fd "# All the time values are in seconds:\n";
	print $example_conf_fd "check every 30\n";
	print $example_conf_fd "report every 86400\n";
	print $example_conf_fd "warn every=43200\n";
	print $example_conf_fd "err_every 7200\n";
	print $example_conf_fd "# (Mind the erratic underscore and =mark, these are just fine...)\n";
	print $example_conf_fd "\n";
	print $example_conf_fd "# If some sensors have been found alive in your system,\n";
	print $example_conf_fd "# you should find them listed below.\n";
	print $example_conf_fd "# (If there are none or few, consult sensors_detect of lm-senesors.)\n";
	print $example_conf_fd "# You should get a line starting \"hwmon\" for each chip instance\n";
	print $example_conf_fd "# and a line starting \"sensor\" for some likely relevant sensor inputs.\n";
	print $example_conf_fd "# The hwmon chip instance spec can optionally include an index.\n";
	print $example_conf_fd "# The sensor lines are generated as commented (inactive).\n";
	print $example_conf_fd "#   Feel free to uncomment those that suit you.\n";
	print $example_conf_fd "# The sensor lines have optional min/max/warnlow/warnhigh.\n";
	print $example_conf_fd "#   Feel free to erase those args that are not applicable.\n";
	print $example_conf_fd "\n";
}


###
### Look around for HWMON sensors in the system
###

my @hwmon_inst_objs;
my %hwmon_inst_by_names;

my $hwmon_path = "/sys/class/hwmon";

opendir my $hwmon_dir, "$hwmon_path" or die "Cannot open $hwmon_path: $!";
my @hwmon_instances = readdir $hwmon_dir;
closedir $hwmon_dir;

foreach $hwmon_inst (@hwmon_instances)
{
	next if ($hwmon_inst =~ /^(\.|\.\.)$/); # skip these pseudo-entries

	my $tmp_fh = undef;
	if (open( $tmp_fh, '<', $hwmon_path . "/" . $hwmon_inst . "/name"))
	{
		my $hwmon_name = <$tmp_fh>;
		chomp($hwmon_name);  # remove trailing newline
		close( $tmp_fh );

		$hwmon_inst =~ /^hwmon([0-9]+)$/;
		my $inst_idx = $1;

		my $inst_ref = { name => $hwmon_name , hwmon => $hwmon_inst, idx1 => $inst_idx };
		# the integer index is unique
		$hwmon_inst_objs[$inst_idx] = $inst_ref;

		# the name is not necessarily unique
		if (!(exists($hwmon_inst_by_names{$hwmon_name}))) # the first instance with this name (a likely case)
		{
			$hwmon_inst_by_names{$hwmon_name} = []; # insert an empty anonymous array, will get populated
		}

		push(@{ $hwmon_inst_by_names{$hwmon_name} }, $inst_ref);
		$inst_ref->{"idx2"} = $#{ $hwmon_inst_by_names{$hwmon_name} }; # know your ordinal index within your name

		print "Inst: $hwmon_inst (= idx: $inst_idx) = Name: $hwmon_name\n";
	}
	else
	{
		print "Warning: could not open $hwmon_inst\n";
	}	
}



# Input: hwmon name, and an optional ordinal number (within that name, zero-based)
# Returns: a hashref to the "hwmon instance" object
sub get_hwmon_inst_by_name_and_order
{
	my $retval = undef;
	my $hwmon_name = shift(@_);
	my $idx = shift(@_);

	if (!(defined($idx)))
	{
		$idx = 0;
	}

	#print "name: $hwmon_name idx: $idx\n";

	if (exists($hwmon_inst_by_names{$hwmon_name}))
	{
		#$retval = ${ $hwmon_inst_by_names{$hwmon_name} }[$idx]; 
		$retval = $hwmon_inst_by_names{$hwmon_name}->[$idx]; 
	}

	#my $tmp_test = $retval->{"name"};
	#print "Referencing hell! Test value: $tmp_test\n";

	return $retval;
}



my @hwmon_names = keys(%hwmon_inst_by_names);
foreach $hwmon_name (@hwmon_names)
{
	# The $# operator returns the highest index in an array.
	# In an array with 1 element, the $# returns a 0.
	my $num_insts = $#{ $hwmon_inst_by_names{$hwmon_name} } + 1; # number of instances sharing this name
	#print "Name: $hwmon_name ... $num_insts instances\n";

	#my $discard_this = get_hwmon_inst_by_name_and_order($tmp_name,0);

	# Iterate across thte (tiny) array of instances, carrying the same $hwmon_name
	my $num_insts_this_name = $#{ $hwmon_inst_by_names{$hwmon_name} };
	foreach my $hwmon_inst (@{ $hwmon_inst_by_names{$hwmon_name} })
	{
		my $tmp_name = $hwmon_inst->{"name"};
		my $tmp_hwmon = $hwmon_inst->{"hwmon"};
		my $tmp_idx1 = $hwmon_inst->{"idx1"};
		my $tmp_idx2 = $hwmon_inst->{"idx2"};
		#print "Contemplating $tmp_name" . "[:" . $tmp_idx2 . "] AKA $tmp_hwmon [$tmp_idx1]...\n";

		if ($generate_conf) # Create the example config file
		{
			my $inst_num_str = "";
			if ($num_insts_this_name > 0)
			{
				$inst_num_str = " $tmp_idx2";
			}
			# else the instance ordinal number is optional
			
			print $example_conf_fd "hwmon $tmp_name" . $inst_num_str . "\n";
		}

		opendir my $hwmon_dir, "$hwmon_path/$tmp_hwmon" or die "Cannot open $hwmon_path/$tmp_hwmon: $!";
		my @sensors = readdir $hwmon_dir;
		closedir $hwmon_dir;

		# Get rid of the pseudo-entries for this and the parent directory.
		# Note: this depends on the dot and double-dot being the first in the list! Is that a bug?
		while ( $sensors[0] =~ /^(\.|\.\.)$/ )
		{
			shift (@sensors);
		}

		$hwmon_inst->{"sensors"} = {};
		# let's approximate an auto-associative ordered container, like a C++ std::set .
		# Will be useful later on when checking for the sensor required in user config.
		#foreach $tmp_sensor (@sensors)
		foreach $tmp_sensor (sort(@sensors))
		{
			$hwmon_inst->{"sensors"}->{$tmp_sensor} = $tmp_sensor; # could've as well assigned an undef or whatever
			# MAYBE: implement any heuristic witticisms regarding PWM or other particularities?
			# weed out some generic nonsense out of here?

			if ($generate_conf) # Create the example config file
			{
				# Only temp and fan inputs are added into example config.
				# Other sensor types will also be processed, if specified manually in the config.
				if ($tmp_sensor =~ /^fan[0-9].+input$/)
				{
					print $example_conf_fd "#sensor $tmp_sensor min=100 max=10000 warnlow=200 warnhigh=5000\n";
				}
				elsif ($tmp_sensor =~ /^temp[0-9].+input$/)
				{
					print $example_conf_fd "#sensor $tmp_sensor min=-20 max=85000 warnlow=0 warnhigh=70000\n";
				}
			}
		}
	}
}

if ($generate_conf)
{
	close($example_conf_fd);
	print "Example config generated.\n";
	print "Edit $example_conf_filename to suit your needs.\n";
	print "Rename the config file to $cfg_filename to activate it.\n";
	exit 0;
}


###
### Read the desired configuration
###

my $line_num = 0;       # Line numbers in the cfg file shall be one-based.
my $last_hwmon = undef; # the hwmon recently mentioned in cfg. The sensors will bind to this.
my %sensors_to_watch;   # a global container (no point in making this private to a hwmon instance)



sub cfg_warning
{
	my $line = shift;
	my $msg = shift;
	print "WARNING, while parsing config file $cfg_filename :\n";
	print "Parsing \"$line\" at line $line_num\n";
	print "$msg\n";
}



sub last_hwmon_verbose
{
	return( "hwmon" . $last_hwmon->{"idx1"} . " AKA " . $last_hwmon->{"name"} . "[" . $last_hwmon->{"idx2"} . "]" );
}



open($cfg_file, "<", $cfg_filename) or die "Cannot open $cfg_filename: $!";

while (<$cfg_file>)
{
	$line_num++;
	chomp;
	s/^\s+//;
	next if (/^\#/);
	next if (/^$/);
	if (/^email (.+)$/)
	{
		$contact_email = $1;	
	}
	elsif (/^smtpserver (.+)$/)
	{
		$smtpserver = $1;	
	}
	elsif (/^daemon.*$/)
	{
		$do_daemonize = 1;	
	}
	elsif (/^check[ _]every[ =]([0-9]+)$/)
	{
		$check_every = $1;
	}
	elsif (/^report[ _]every[ =]([0-9]+)$/)
	{
		$report_every = $1;
	}
	elsif (/^warn[ _]every[ =]([0-9]+)$/)
	{
		$warn_every = $1;
	}
	elsif (/^err[ _]every[ =]([0-9]+)$/)
	{
		$err_every = $1;
	}
	elsif (/^(hwmon (.+)|hwmon([0-9]+))$/) # permits: hwmon <whatever including spaces> | hwmon2
	{
		if (defined($3)) # hwmon2
		{
			if (exists($hwmon_inst_objs[$3]))
			{
				$last_hwmon = $hwmon_inst_objs[$3];
				print 
			}
			else
			{
				$last_hwmon = undef;
			}
		}
		else
		{
			my $undecided = $2; # whatever including spaces
			
			if ($undecided =~ /^(hwmon)?([0-9]+)$/)
			{
				if (exists($hwmon_inst_objs[$2]))
				{
					$last_hwmon = $hwmon_inst_objs[$2];
				}
				else
				{
					$last_hwmon = undef;
				}
			}
			# else just a misc string, should better be a name, optionally followed by a number
			elsif ($undecided =~ /^([^\s]*)( ([0-9]+))?$/)
			{
				#print "DEBUG 1 : $1 $3\n";
				$last_hwmon = get_hwmon_inst_by_name_and_order($1,$3);
			}
			# There is no "else" here. Anything should already match the previous regexp.
		}

		if (!(defined($last_hwmon)))
		{
			print "Warning: HWMON \"$_\" unknown in this machine...\n";
		}
	}
	elsif (/^[\s]*sensor +(.*)$/)
	{
		if (!(defined($last_hwmon)))
		{
			cfg_warning($_,"Before declaring sensors, first declare a HWMON instance that the sensors belong to.");
			next;
		}

		my @sensor_spec = split(' ', $1);
		my $sensor_name = shift(@sensor_spec);

		if ($sensor_name =~ /^(device|name|power|subsystem|uevent)$/) # how about "alarms" ?
		{
			cfg_warning($_,"Come on, \"$sensor_name\" is not an actual sensor.");
			next;
		}	

		if (!(exists($last_hwmon->{"sensors"}->{$sensor_name})))
		{
			my $tmp_hwmon_verb = last_hwmon_verbose();
			cfg_warning($_,"Sensor $sensor_name does not seem to exist in $tmp_hwmon_verb .");
			next;
		} # else a directory entry by that name exists

		my $sensor_entry = {};
		$sensors_to_watch{ $last_hwmon->{"name"} . "." . $last_hwmon->{"idx2"} . "." . $sensor_name } = $sensor_entry;
		$sensor_entry->{"name"} = $sensor_name;
		$sensor_entry->{"hwmon"} = $last_hwmon; # owner
		$sensor_entry->{"val"} = undef;
		$sensor_entry->{"lasterr"} = 0;
		$sensor_entry->{"lastwarn"} = 0;
		$sensor_entry->{"doerr"} = 0;
		$sensor_entry->{"dowarn"} = 0;

		my $sensor_args = []; # create an empty anonymous array, to store the sensor's arguments
		$sensor_entry->{"args"} = $sensor_args;
	
		# Note: let's make it legal to have zero arguments.
		# Such a sensor will appear in reports, but will never trigger an alarm.	
		while (my $this_arg = shift(@sensor_spec))
		{
			my $arg_ref = {};

			if ($this_arg =~ /^min=(\-?[0-9]+)$/)
			{
				$arg_ref->{"fn"} = "min";
				$arg_ref->{"val"} = $1;
			}
			elsif ($this_arg =~ /^max=([0-9]+)$/)
			{
				$arg_ref->{"fn"} = "max";
				$arg_ref->{"val"} = $1;
			}
			elsif ($this_arg =~ /^warnhigh=([0-9]+)$/)
			{
				$arg_ref->{"fn"} = "warnhigh";
				$arg_ref->{"val"} = $1;
			}
			elsif ($this_arg =~ /^warnlow=(\-?[0-9]+)$/)
			{
				$arg_ref->{"fn"} = "warnlow";
				$arg_ref->{"val"} = $1;
			}
			else
			{
				cfg_warning($_,"Sensor $sensor_name has an unknown arg $this_arg .");
				$arg_ref = undef;
			}
			
			if (defined($arg_ref))
			{
				print "Adding arg $this_arg\n";
				push(@{ $sensor_args },$arg_ref);
				$arg_ref->{"trig"} = 0;
			} # else discard silently
		}

		print "Sensor $sensor_name : " . ($#$sensor_args + 1) . " arguments scanned.\n";
	}
	else
	{
		cfg_warning($_,"Unknown curse encountered in the config file. Check your syntax.");
	}
}

close($cfg_file);



###
### Prepare for the e-mail reporting
###

# Prerequisites for the e-mail stuff:
# apt-get install make
# cpan -i MIME::Lite
use MIME::Lite;

sub send_email
{
	my $msgTextRef = shift;
	defined($msgTextRef) || return;
	my $severity = shift; # just text

	my $msgObj = MIME::Lite->new(
				From => $sender_addr,
				To => $contact_email,
				Subject => "Sensormon report: " . $severity,
				Data => $$msgTextRef
				);

	$msgObj->attr("content-type" => "text/plain");

	if (defined($smtpserver))
	{
		$msgObj->send('smtp', $smtpserver); # SMTP auth also possible with a bit of extra effort
	}
	else
	{
		$msgObj->send; # requires sendmail in the system
	}
}



###
### If desired, daemonize
###

# Prerequisites:
# apt-get install gcc
# cpan -i Proc::Daemon
use Proc::Daemon;

if ($do_daemonize)
{
	Proc::Daemon::Init;
}



###
### Watch the sensors
###

my @sensor_to_watch_keys = sort( keys( %sensors_to_watch ) );
($#sensor_to_watch_keys >= 0) or die "No sensors to watch! Nothing to do? Exiting.";

# Open the sensor pseudo-files and keep the open file-handles.
foreach my $tmp_sensor_key (@sensor_to_watch_keys)
{
	my $sensor_to_watch = $sensors_to_watch{$tmp_sensor_key};
	my $sensor_filename = $hwmon_path . "/hwmon" . $sensor_to_watch->{"hwmon"}->{"idx1"} . "/" . $sensor_to_watch->{"name"};
	print "Opening $sensor_filename\n";

	my $fh;
	if (!(open($fh, "<", $sensor_filename)))
	{
		print "Warning: couldn't open $sensor_filename : $!\n";
		# Do not exit just yet. Let's skip dud sensors while checking.
		$fh = undef;
	}
	
	$sensor_to_watch->{"handle"} = $fh;
}


my $last_check=0;  # seconds since the epoch
my $last_report=0; # seconds since the epoch
my $global_do_err;
my $global_do_warn;
my $global_do_report;

my $sig_rcvd = undef;
$SIG{INT} = sub { $sig_rcvd = 2; };
$SIG{TERM} = sub { $sig_rcvd = 15; };

while (1)
{
	if (defined($sig_rcvd))
	{
		print "\nStopping upon a signal: $sig_rcvd\n";
		last;
	}

	my $time_now = time();
	$last_check = $time_now; # is this pretty useless, actually ? We sleep at the end of the loop anyway...
	$global_do_err = 0;
	$global_do_warn = 0;
	$global_do_report = 0;
	if ($time_now > $last_report + $report_every)
	{
		$last_report = $time_now;
		$global_do_report = 1;
	}

	### check and decide
	
	foreach my $tmp_sensor_key (@sensor_to_watch_keys)
	{
		my $sensor_to_watch = $sensors_to_watch{$tmp_sensor_key};

		defined($sensor_to_watch->{"handle"}) or next;
		my $tmp_handle = $sensor_to_watch->{"handle"};
		seek($tmp_handle, 0, SEEK_SET) or next;
		(my $cur_val = <$tmp_handle>) or next;
		chomp($cur_val);
		$sensor_to_watch->{"val"} = $cur_val;
		$sensor_to_watch->{"warn"} = 0; # an immediate flag, not subject to timeout
		$sensor_to_watch->{"err"} = 0; # an immediate flag, not subject to timeout

		my $mintrig = 0;       # current status only, this check iteration
		my $maxtrig = 0;       # current status only, this check iteration
		my $warnlowtrig = 0;   # current status only, this check iteration
		my $warnhightrig = 0;  # current status only, this check iteration

		# The way the following ~three-stage error/warning detection works,
		# a warning will always be flagged if an error=alarm got flagged as well.
		# As long as the warning threshold is configured to trigger earlier than the error threshold.
		# => In the report, the ALARM=ERROR will override the WARNING.
		# => In the per-sensor timeouts, lastwarn will get reset along with (by) lasterr. Not the other way around.
		my $args_arrayref = $sensor_to_watch->{"args"};
		foreach my $this_arg (@$args_arrayref)
		{
			my $trig = 0;

			if ($this_arg->{"fn"} eq "min")
			{
				if ($cur_val < $this_arg->{"val"})
				{
					$mintrig = 1;
					$trig = 1;
				}
			}
			elsif ($this_arg->{"fn"} eq "max")
			{
				if ($cur_val > $this_arg->{"val"})
				{
					$maxtrig = 1;
					$trig = 1;
				}
			}
			elsif ($this_arg->{"fn"} eq "warnlow")
			{
				if ($cur_val < $this_arg->{"val"})
				{
					$warnlowtrig = 1;
					$trig = 1;
				}
			}
			elsif ($this_arg->{"fn"} eq "warnhigh")
			{
				if ($cur_val > $this_arg->{"val"})
				{
					$warnhightrig = 1;
					$trig = 1;
				}
			}

			#print "DEBUG Evaluating arg: " . $this_arg->{"fn"} . " val: " . $this_arg->{"val"} . " trig: $trig\n";

			$this_arg->{"trig"} = $trig; # useful to report what arg bombed
		}
		
		if (($mintrig) || ($maxtrig)) # severity level now: error
		{
			$sensor_to_watch->{"err"} = 1; # this flag is NOT subject to timeout
			if ($time_now > $sensor_to_watch->{"lasterr"} + $err_every)
			{    # okay, it's about time
				$global_do_err = 1; # this will add up across sensors, every check iteration
			}
			# else error active, but it's not time for another error report yet, 
			# as far as this sensor is concerned. May get reported anyway, along with others, decided later on.
		}
		#mind: no elsif
		if (($warnlowtrig) || ($warnhightrig)) # severity level now: a mere warning
		{
			$sensor_to_watch->{"warn"} = 1; # this flag is NOT subject to timeout
			if ($time_now > $sensor_to_watch->{"lastwarn"} + $warn_every)
			{    # okay, it's about time
				$global_do_warn = 1; # this will add up across sensors, every check iteration
			}
			# else warning active, but it's not time for another warning report yet,
			# as far as this sensor is concerned. May get reported anyway, along with others, decided later on.
		}

		#print "DEBUG " . $sensor_to_watch->{"name"} . " : $cur_val, triggers : $mintrig,$maxtrig,$warnlowtrig,$warnhightrig;$do_err,$do_warn\n";
	}

	### do any necessary reporting

	# Only compose the report if necessary (do not waste compute power if no report is to be sent)
	if ($global_do_report || $global_do_warn || $global_do_err)
	#if (1)
	{
		my $msgText = "This is sensormon at $machine_name .\n";

		foreach my $tmp_sensor_key (@sensor_to_watch_keys)
		{
			my $sensor_to_watch = $sensors_to_watch{$tmp_sensor_key};
			my $output_line = $tmp_sensor_key . "=" . $sensor_to_watch->{"val"};

			if ($sensor_to_watch->{"warn"} > 0)
			{
				$sensor_to_watch->{"lastwarn"} = $time_now; # Should get reset when there's an error too
				$output_line .= " WARNING"; # may get overridden by the " ERROR" below
			}
			# mind: no elsif
			if ($sensor_to_watch->{"err"} > 0)
			{
				$sensor_to_watch->{"lasterr"} = $time_now;
				$output_line .= " ERROR"; # may override the " WARNING" above
			}

			my $args_arrayref = $sensor_to_watch->{"args"};
			foreach my $this_arg (@$args_arrayref)
			{
				if ($this_arg->{"trig"} > 0)
				{
					if (($this_arg->{"fn"} eq "max") || ($this_arg->{"fn"} eq "warnhigh"))
					{
						$output_line .= " >" . $this_arg->{"val"};
					}
					elsif (($this_arg->{"fn"} eq "min") || ($this_arg->{"fn"} eq "warnlow"))
					{
						$output_line .= " <" . $this_arg->{"val"};
					}
				}
				#else stay silent, this condition has not fired
			}

			$msgText .= $output_line . "\n";
		}
		
		print $msgText;

		my $msgSeverity = "All sensors OK";
		if ($global_do_err)
		{
			$msgSeverity = "ALARM!!!";
		}
		elsif ($global_do_warn)
		{
			$msgSeverity = "WARNING";
		}

		send_email(\$msgText, $msgSeverity);
	}

	#print "DEBUG Check every $check_every\n";
	sleep($check_every);	
}



foreach my $tmp_sensor_key (@sensor_to_watch_keys)
{
	close( $sensors_to_watch{$tmp_sensor_key}->{"handle"} );
}

exit 0;
