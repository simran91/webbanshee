#!/usr/bin/perl

##################################################################################################################
# 
# File         : webbanshee.pl
# Description  : simple load testing for trivial web pages (more like a DoS tool circa early 90's)
# Original Date: ~1993
# Author       : simran@dn.gs
#
##################################################################################################################

require 5.002;
use Socket;
use Carp;
use FileHandle;
use POSIX;

$|=1;
$version = "1.1 30/Mar/1994";

$timeout = 7;

################ read in args etc... ###################################################################################
#
#
#

($cmd = $0) =~ s:(.*/)::g;
($startdir = $0) =~ s/$cmd$//g;

while (@ARGV) { 
  $arg = "$ARGV[0]";
  $nextarg = "$ARGV[1]";
  if ($arg =~ /^-f$/i) {
    $infile = "$nextarg";
    if ("$infile" ne "-" && (! -f "$infile")) { 
       die "Valid file not defined after -f switch : $!";
    }
    shift(@ARGV);
    shift(@ARGV);
    next;
  }
  elsif ($arg =~ /^-o$/i) {
    $outfile = "$nextarg";
    shift(@ARGV);
    shift(@ARGV);
    next;
  }
  elsif ($arg =~ /^-p$/i) {
    $port = $nextarg;
    die "A valid numeric port number must be given with the -p argument : $!" if ($port !~ /^\d+$/);
    shift(@ARGV);
    shift(@ARGV);
  }
  elsif ($arg =~ /^-t$/i) {
    $timeout = $nextarg;
    die "A valid numeric number must be given with the -t argument : $!" if ($timeout !~ /^\d+$/);
    shift(@ARGV);
    shift(@ARGV);
  }
  elsif ($arg =~ /^-bh$/i) {
    $bulk_handle = $nextarg;
    die "A valid numeric bulk_handle number must be given with the -bh argument : $!" if ($bulk_handle !~ /^\d+$/);
    shift(@ARGV);
    shift(@ARGV);
  }
  elsif ($arg =~ /^-sleep$/i) {
    $sleep_sec = $nextarg;
    die "A valid numeric sleep number must be given with the -sleep argument : $!" if ($sleep_sec !~ /^\d+$/);
    shift(@ARGV);
    shift(@ARGV);
  }
  elsif ($arg =~ /^-r$/i) {
    $repeat = $nextarg;
    die "A valid numeric number must be given with the -r argument : $!" if ($repeat !~ /^\d+$/);
    shift(@ARGV);
    shift(@ARGV);
  }
  elsif ($arg =~ /^-norecv$/i) {
    $norecv = 1;
    shift(@ARGV);
  }
  elsif ($arg =~ /^-h$/i) {
    $host = $nextarg;
    shift(@ARGV);
    shift(@ARGV);
  }
  elsif ($arg =~ /^-samplein$/i) {
    &samplein();
    exit(0);
  }
  elsif ($arg =~ /^-about$/i) {
    shift(@ARGV);
    &about();
  }
  else { 
    print "\n\nArgument $arg not understood.\n";
    &usage();
  }
}

#
#
#
########################################################################################################################


############### forward declarations for subroutines ... ###############################################################
#
#
#

# forward declarations for subroutines

sub spawn;    # subroutine that spawns code... 
sub logmsg;   # subroutine that logs stuff on STDOUT 
sub REAPER;   # reaps zombie process... 
sub alarmcall; # Gets called when it takes more than "$timeout" seconds to answer a request... 

#
#
#
########################################################################################################################

################# main program #########################################################################################
#
#
#

if (! ($host && $infile && $outfile)) {
  &usage();
  exit(0);
}

$repeat = 1 if (! $repeat);
$port = 80 if (! $port);

if ($sleep_sec) {
  die "-sleep switch is not valid without -bh switch" if (! $bulk_handle);
}
elsif ($bulk_handle) {
  die "-bh switch is not valid without -sleep switch" if (! $sleep_sec);
}

$bulk_handle = $repeat + 1 if (! $bulk_handle);

$SIG{CHLD} = \&REAPER;

&handleRequest();

#
#
#
########################################################################################################################


########################################################################################################################
# logmsg($string): prints messages to stdout
#
#
sub logmsg { 
  print "$) $$: @_ at ", scalar localtime, "\n"; 
}
#
#
#
########################################################################################################################


########################################################################################################################
# REAPER: reaps zombie processes
#
#
sub REAPER {
  my $child;
  $SIG{CHLD} = \&REAPER;
  while ($child = waitpid(-1,WNOHANG) > 0) {
    $Kid_Status{$child} = $?;
  }
  # logmsg "reaped $waitpid" . ($? ? " with exit $?" : "");
}
#
#
#
########################################################################################################################


########################################################################################################################
# spawn: forks code
#        usage: spawn sub { code_you_want_to_spawn };
#
#
sub spawn {
  my $coderef = shift;
  unless (@_ == 0 && $coderef && ref($coderef) eq 'CODE') {
    confess "usage: spawn CODEREF";
  }
  my $pid;
  if (!defined($pid = fork)) {
    logmsg "cannot fork: $!"; return;
  }
  elsif ($pid) {
    # logmsg "begat $pid"; 
    return; # i'm the parent
  }
  # else i'm the child -- go spawn

  open(STDIN,  "<&Client")   || die "can't dup client to stdin";
  open(STDOUT, ">&Client")   || die "can't dup client to stdout";
  ## open(STDERR, ">&STDOUT") || die "can't dup stdout to stderr";
  exit &$coderef();
}
#
#
#
########################################################################################################################


########################################################################################################################
# handleRequest: handles requests sent by browsers... 
#
#
sub handleRequest {

  $SIG{ALRM} = \&alarmcall;

  alarm $timeout;
  
  $starttime = time;

  if ("$infile" eq "-") { open(IN, "<&STDIN") || die "Could not open standard input : $!"; }
  else { open(IN, "$infile") || die "Could not open infile $infile : $!"; }

  @in = <IN>;
  close(IN);

  if ("$outfile" eq "-") { open(OUT, ">&STDOUT") || die "Could not open STDOUT : $!"; }
  else { open(OUT, "> $outfile") || die "Could not open outfile for writing $outfile : $!"; }
  

  OUT->autoflush();

  &passon(@in);
  &passback() unless ($norecv);
  $repeat--;
  $handled++;

  while ($repeat > 0) {
    print STDERR "\rRepeats left : $repeat ";
    if ($handled >= $bulk_handle) {
      $handled = 0; # number of handled requests since last sleep... 
      print STDERR "\nSleeping for $sleep_sec seconds\n";
      sleep($sleep_sec);
    }
    alarm $timeout; # reinstate alarm timeout... 
    $repeat--;
    $handled++;
    &passon(@in);
    @discard = <WebServer> unless ($norecv);
    close(WebServer);
    alarm 0;
  }

  $endtime = time;
  
  $seconds = $endtime - $starttime;

  print STDERR "\rRepeats left : $repeat ";
  print STDERR "\nThe request took $seconds seconds to complete\n";

  alarm 0; # cancel alarm 

}
#
#
#
########################################################################################################################

########################################################################################################################
# passback: get reply from webserver and print to file... 
#
#
sub passback {
  my $inheader = 1;
  my @fullreply;
  my @gotbackheader, @gotbackcontent;

  my $time = scalar localtime;

  @gotback = <WebServer>;

  print OUT join('',@gotback);

  close(OUT);
  close(WebServer);
}
#
#
#
########################################################################################################################

########################################################################################################################
# passon: Pass information on to webserver... 
#
#
sub passon {
  my @in = @_;
  my ($method, $url, $protocol, $remotehost, $remoteport);
  

  $remotehost = "$host";
  $remoteport = "$port";

  $remoteport = 80 if (! $remoteport);
  
  setupWebServer("$remotehost", "$remoteport");
  send(WebServer, join('',@in), 0) || warn "send: $!";
}
#
#
#
########################################################################################################################

########################################################################################################################
# setupWebServer: sets up connection to remote server 
#
#
sub setupWebServer { 
  my ($remotehost, $remoteport) = @_;
  my $proto = getprotobyname('tcp');
  my ($remote_iaddr, $remote_paddr);

  $remote_iaddr = inet_aton($remotehost);
  $remote_paddr = sockaddr_in($remoteport,$remote_iaddr);
  socket(WebServer, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";
  if (! connect(WebServer, $remote_paddr)) {
    &alarmcall();
  }
  # if we get this far, we have successfully contact the remote host.. so change the timeout value... 
}
#
#
#
########################################################################################################################


########################################################################################################################
# usage: prints usage... 
#
#
sub usage {
  print "\n\n@_\n";
  print << "EOUSAGE"; 

Usage: $cmd [options]
       
   -samplein    # produces sample 'infile'
   -h hostname  # connects to remote host 'hostname'
   -p num   	# connects to remote host on port 'num' - default 80
   -f infile    # The file that has to be sent... can be "-" for input from STDIN!
   -o outfile   # Output filename... can be "-" for output to STDOUT!
   -r num	# number of times we should send the request... - default 1
   -norecv      # explained below... only useful with -r switch 
   -bh num      # Bulk handle... only useful with -sleep switch, will sleep for specified time
   -t num	# timeout to remote host in 'num' seconds
   		# after every 'num' requests
   -sleep num   # Sleep... only useful with -bh switch, will sleep for 'num' seconds after every
   		# bulk_handle requests
   -about	# About this program

   eg. $cmd -h www.nowhere.com.au -f in.nowhere -o out.nowhere -r 5

   Note: With the '-r' option, the outfile will only be gotten and written the 'first time'
         we connect to the remote server, thereafter, all replies will be received but discarded
	 unless you have specified the -norecv switch in which case we close connection straight
	 after sending the request (and do not wait for the reply) which makes sending a lot quicker.
	 The -norecv switch is useful if we don't want to measure the response time of the server, but
	 just want to add our requests to its log files increasing the hits on the remote server!

EOUSAGE
  exit(0);
}
#
#
#
########################################################################################################################

########################################################################################################################
# sub alarmcall: # the subroutine that is called when requests take too long to get a response for or respond to... 
#
#
sub alarmcall {
  my $signame = shift;
  print STDERR <<"EO_ALRM_MSG";

connection timed out ... or remote host not contactable... 

EO_ALRM_MSG
  exit(1);
}
#
#
#
########################################################################################################################

########################################################################################################################
# samplein: prints out a sample configuration file... 
#
#
sub samplein { 
  print <<"EO_SAMPLE_CONF";
POST /cgi-bin/humpty-test.cgi HTTP/1.0
Referer: http://www.nowhere.com.au/yesno/yesno-test.html
Proxy-Connection: Keep-Alive
User-Agent: Mozilla/4.03 [en] (X11; I; Linux 2.0.30 i686)
Host: www.nowhere.com.au
Accept: image/gif, image/x-xbitmap, image/jpeg, image/pjpeg, */*
Accept-Language: en
Accept-Charset: iso-8859-1,*,utf-8
Cookie: RMID=cb1ab99a3490ef99
Content-type: application/x-www-form-urlencoded
Content-length: 10

humpty=yes

EO_SAMPLE_CONF
}
#
#
#
########################################################################################################################

########################################################################################################################
#
#
#
sub about {
  print <<"EOABOUT";

  WebBanshee version $version 
  ----------------------------------

  Written to "loadtest" a website :-) 
  Can be used for a lot of other purposes :-) even
  non website related. 

  Please mail comments/suggestions to simran\@dn.gs

EOABOUT
  exit(0);
}
#
#
#
########################################################################################################################

