# -*- cperl -*-
# t/modules.t [OPTIONS] [t/mymodules]
# check if some common CPAN modules exist and
# can be compiled successfully. Only B::C is fatal,
# CC and Bytecode optional. Use -all for all three (optional), and
# -log for the reports (now default).
#
# OPTIONS:
#  -all     - run also B::CC and B::Bytecode
#  -subset  - run only random 10 of all modules. default if ! -d .svn
#  -no-subset  - all 100 modules
#  -no-date - no date added at the logfile
#  -t       - run also tests
#  -log     - save log file. default on test10 and without subset
#
# The list in t/mymodules comes from two bigger projects.
# Recommended general lists are Task::Kensho and http://ali.as/top100/
# We are using 10 problematic modules from the latter.
# We are NOT running the full module testsuite yet with -t, we can do that
# in another author test to burn CPU for a few hours resp. days.
#
# Reports:
# for p in 5.6.2 5.8.9 5.10.1 5.12.2; do make -S clean; perl$p Makefile.PL; make; perl$p -Mblib t/modules.t -log; done
#
# How to installed skip modules:
# grep ^skip log.modules-bla|perl -lane'print $F[1]'| xargs perlbla -S cpan
# or t/testm.sh -s

use strict;
use Test::More;
use File::Temp;

# Try some simple XS module which exists in 5.6.2 and blead
# otherwise we'll get a bogus 40% failure rate
my $staticxs = '';
my $Mblib = $^O eq 'MSWin32' ? '-Iblib\arch -Iblib\lib' : "-Iblib/arch -Iblib/lib";
BEGIN {
  $staticxs = '--staticxs';
  # check whether linking with xs works at all. Try with and without --staticxs
  if ($^O eq 'darwin') { $staticxs = ''; goto BEGIN_END; }
  my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
  my $Mblib = $^O eq 'MSWin32' ? '-Iblib\arch -Iblib\lib' : "-Iblib/arch -Iblib/lib";
  my $tmp = File::Temp->new(TEMPLATE => 'pccXXXXX');
  my $out = $tmp->filename;
  my $result = `$X $Mblib blib/script/perlcc --staticxs -o$out -e"use Data::Dumper;"`;
  my $exe = $^O eq 'MSWin32' ? "$out.exe" : $out;
  unless (-e $exe or -e 'a.out') {
    my $result = `$X $Mblib blib/script/perlcc -o$out -e"use Data::Dumper;"`;
    unless (-e $out or -e 'a.out') {
      plan skip_all => "perlcc cannot link XS module Data::Dumper. Most likely wrong ldopts.";
      unlink $out;
      exit;
    } else {
      $staticxs = '';
    }
  }
 BEGIN_END:
  unshift @INC, 't';
}

our %modules;
our $keep = '';
our $log = 0;
use modules;
require "test.pl";

my $opts_to_test = 1;
my $do_test;
$opts_to_test = 3 if grep /^-all$/, @ARGV;
$do_test = 1 if grep /^-t$/, @ARGV;

# Determine list of modules to action.
our @modules = get_module_list();
my $test_count = scalar @modules * $opts_to_test * ($do_test ? 5 : 4);
# $test_count -= 4 * $opts_to_test * (scalar @modules - scalar(keys %modules));
plan tests => $test_count;

use Config;
use B::C;
use POSIX qw(strftime);

eval { require IPC::Run; };
my $have_IPC_Run = defined $IPC::Run::VERSION;
log_diag("Warning: IPC::Run is not available. Error trapping will be limited, no timeouts.")
  unless $have_IPC_Run;

my @opts = ("");				  # only B::C
@opts = ("", "-O", "-B") if grep /-all/, @ARGV;  # all 3 compilers
my $perlversion = perlversion();
$log = 0 if @ARGV;
$log = 1 if grep /top100$/, @ARGV;
$log = 1 if grep /-log/, @ARGV or $ENV{TEST_LOG};
my $nodate = 1 if grep /-no-date/, @ARGV;

if ($log) {
  $log = (@ARGV and !$nodate)
    ? "log.modules-$perlversion-".strftime("%Y%m%d-%H%M%S",localtime)
    : "log.modules-$perlversion";
  if (-e $log) {
    use File::Copy;
    copy $log, "$log.bak";
  }
  open(LOG, ">", "$log");
  close LOG;
}
unless (is_subset) {
  my $svnrev = "";
  if (-d '.svn') {
    local $ENV{LC_MESSAGES} = "C";
    $svnrev = `svn info|grep Revision:`;
    chomp $svnrev;
    $svnrev =~ s/Revision:\s+/r/;
    my $svnstat = `svn status lib/B/C.pm t/test.pl t/*.t`;
    chomp $svnstat;
    $svnrev .= " M" if $svnstat;
  } elsif (-d '.git') {
    local $ENV{LC_MESSAGES} = "C";
    $svnrev = `git log -1 --pretty=format:"%h %ad | %s" --date=short`;
    chomp $svnrev;
    my $gitdiff = `git diff lib/B/C.pm t/test.pl t/*.t`;
    chomp $gitdiff;
    $svnrev .= " M" if $gitdiff;
  }
  log_diag("B::C::VERSION = $B::C::VERSION $svnrev");
  log_diag("perlversion = $perlversion");
  log_diag("path = $^X");
  my $bits = 8 * $Config{ptrsize};
  log_diag("platform = $^O $bits"."bit ".(
	   $Config{'useithreads'} ? "threaded"
	   : $Config{'usemultiplicity'} ? "multi"
	     : "non-threaded").
	   ($Config{ccflags} =~ m/-DDEBUGGING/ ? " debug" : ""));
}

my $module_count = 0;
my ($skip, $pass, $fail, $todo) = (0,0,0,0);

MODULE:
for my $module (@modules) {
  $module_count++;
  local($\, $,);   # guard against -l and other things that screw with
                   # print

  # Possible binary files.
  my $name = $module;
  $name =~ s/::/_/g;
  $name =~ s{(install|setup|update)}{substr($1,0,4)}ie;
  my $out = 'pcc'.$name;
  my $out_c  = "$out.c";
  my $out_pl = "$out.pl";
  $out = "$out.exe" if $^O eq 'MSWin32';

 SKIP: {
    # if is a special module that can't be required like others
    unless ($modules{$module}) {
      $skip++;
      log_pass("skip", "$module", 0);

      skip("$module not installed", 4 * scalar @opts);
      next MODULE;
    }
    if (is_skip($module)) { # !$have_IPC_Run is not really helpful here
      my $why = is_skip($module);
      $skip++;
      log_pass("skip", "$module #$why", 0);

      skip("$module $why", 4 * scalar @opts);
      next MODULE;
    }
    $module = 'if(1) => "Sys::Hostname"' if $module eq 'if';

  TODO: {
      my $s = is_todo($module);
      local $TODO = $s if $s;
      $todo++ if $TODO;

      open F, ">", $out_pl or die;
      print F "use $module;\nprint 'ok';\n" or die;
      close F or die;

      my ($result, $stdout, $err);
      my $module_passed = 1;
      my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
      foreach my $opt (@opts) {
        $opt .= " $keep" if $keep;
        # TODO ./a often hangs but perlcc not
        my @cmd = grep {!/^$/}
	  $runperl,split(/ /,$Mblib),"blib/script/perlcc",split(/ /,$opt),$staticxs,"-o$out","-r",$out_pl;
        my $cmd = "$runperl $Mblib blib/script/perlcc $opt $staticxs -o$out -r"; # only for the msg
	# My Macbook Air with gcc-mp and with 1GB RAM has insane compile times
        ($result, $stdout, $err) = run_cmd(\@cmd, 720); # in secs.
        ok(-s $out,
           "$module_count: use $module  generates non-zero binary")
          or $module_passed = 0;
        is($result, 0,  "$module_count: use $module $opt exits with 0")
          or $module_passed = 0;
	$err =~ s/^Using .+blib\n//m if $] < 5.007;
        like($stdout, qr/ok$/ms, "$module_count: use $module $opt gives expected 'ok' output");
        unless ($stdout =~ /ok$/ms) { # crosscheck for a perlcc problem (XXX not needed anymore)
          my ($r, $err1);
          $module_passed = 0;
          @cmd = ($runperl,$Mblib,"-MO=C,-o$out_c",$out_pl);
          ($r, $stdout, $err1) = run_cmd(\@cmd, 60); # in secs
          @cmd = ($runperl,$Mblib,"script/cc_harness","-o$out",$out_c);
          ($r, $stdout, $err1) = run_cmd(\@cmd, 360); # in secs
          @cmd = ($^O eq 'MSWin32' ? "$out" : "./$out");
          ($r, $stdout, $err1) = run_cmd(\@cmd, 20); # in secs
          if ($stdout =~ /ok$/ms) {
            $module_passed = 1;
            diag "crosscheck that only perlcc $staticxs failed. With -MO=C + cc_harness => ok";
          }
        }
        log_pass($module_passed ? "pass" : "fail", $module, $TODO);

        if ($module_passed) {
          $pass++;
        } else {
          diag "Failed: $cmd -e 'use $module; print \"ok\"'";
          $fail++;
        }

      TODO: {
          local $TODO = 'STDERR from compiler warnings in work' if $err;
          is($err, '', "$module_count: use $module  no error output compiling")
            && ($module_passed)
              or log_err($module, $stdout, $err)
            }
      }
      if ($do_test) {
        TODO: {
          local $TODO = 'all module tests';
          `$runperl $Mblib -It -MCPAN -Mmodules -e "CPAN::Shell->testcc("$module")"`;
        }
      }
      for ($out_pl, $out, $out_c, $out_c.".lst") {
	unlink $_ if -f $_ ;
      }
    }}
}

my $count = scalar @modules - $skip;
log_diag("$count / $module_count modules tested with B-C-${B::C::VERSION} - perl-$perlversion");
log_diag(sprintf("pass %3d / %3d (%s)", $pass, $count, percent($pass,$count)));
log_diag(sprintf("fail %3d / %3d (%s)", $fail, $count, percent($fail,$count)));
log_diag(sprintf("todo %3d / %3d (%s)", $todo, $fail, percent($todo,$fail)));
log_diag(sprintf("skip %3d / %3d (%s not installed)\n",
                 $skip, $module_count, percent($skip,$module_count)));

exit;

# t/todomod.pl
# for t in $(cat t/top100); do perl -ne"\$ARGV=~s/log.modules-//;print \$ARGV,': ',\$_ if / $t\s/" t/modules.t `ls log.modules-5.0*|grep -v .err`; read; done
sub is_todo {
  my $module = shift or die;
  my $DEBUGGING = ($Config{ccflags} =~ m/-DDEBUGGING/);
  # ---------------------------------------
  foreach(qw(
    Module::Build
  )) { return 'overlong linking time' if $_ eq $module; }
  foreach(qw(
      Test::NoWarnings
  )) { return 'print() on unopened filehandle $Testout' if $_ eq $module; }
  #if ($] < 5.007) { foreach(qw(
  #  ExtUtils::CBuilder
  #)) { return '5.6' if $_ eq $module; }}
  if ($] >= 5.008004 and $] < 5.0080006) { foreach(qw(
    Module::Pluggable
  )) { return '5.8.5 CopFILE_set' if $_ eq $module; }}
  # restricted v_string hash?
  if ($] eq '5.010000') { foreach(qw(
   IO
   Path::Class
   DateTime::TimeZone
  )) { return '5.10.0 restricted hash/...' if $_ eq $module; }}
  # fixed between v5.15.6-210-g5343a61 and v5.15.6-233-gfb7aafe
  if ($] > 5.015 and $] < 5.015006) { foreach(qw(
   B::Hooks::EndOfScope
  )) { return '> 5.15' if $_ eq $module; }}
  #if ($] > 5.015) { foreach(qw(
  #    Moose
  #    MooseX::Types
  #    DateTime
  #)) { return '> 5.15 (unshare_hek)' if $_ eq $module; }}

  # ---------------------------------------
  if ($Config{useithreads}) {
    if (!$DEBUGGING) { foreach(qw(
      Test::Tester
    )) { return 'non-debugging with threads' if $_ eq $module; }}
    if ($] >= 5.008005 and $] < 5.008006) { foreach(qw(
      Module::Build
      Test::NoWarnings
      Test::Warn
      Test::Simple
      Test::Exception
      Test::Tester
      Test::Deep
    )) { return '5.8.4-5 shared_scalar n-magic (\156)' if $_ eq $module; }}
    if ($] > 5.008001 and $] < 5.008009) { foreach(qw(
      Test::Pod
    )) { return '5.8.1-5.8.8 with threads' if $_ eq $module; }}
    if ($] >= 5.009 and $] < 5.012) { foreach(qw(
      Carp::Clan
      DateTime
      Encode
      ExtUtils::Install
      Module::Build
      MooseX::Types
      Pod::Text
      Template::Stash
    )) { return '5.10 with threads' if $_ eq $module; }}
    # XXX 5.12.0 not tested recently
    if ($] eq 5.012000) { foreach(qw(
      DBI
      DateTime
      DateTime::Locale
      Filter::Util::Call
      Storable
      Sub::Name
    )) { return '5.12.0 with threads' if $_ eq $module; }}
  } else { #no threads --------------------------------
    # This was related to aelemfast->sv with SPECIAL pads fixed with 033d200
    if ($] > 5.008004 and $] <= 5.008005) { foreach(qw(
      DateTime
    )) { return '5.8.5 without threads' if $_ eq $module; }}
    if ($] > 5.015) { foreach(qw(
      DateTime::TimeZone
      Module::Build
    )) { return '> 5.15 without threads' if $_ eq $module; }}
  }
  # ---------------------------------------
}

sub is_skip {
  my $module = shift or die;

  if ($] >= 5.011004) {
    #foreach (qw(Attribute::Handlers)) {
    #  return 'fails $] >= 5.011004' if $_ eq $module;
    #}
    if ($Config{useithreads}) { # hangs and crashes threaded since 5.12
      foreach (qw(  )) {
        # Old: Recursive inheritance detected in package 'Moose::Object' at /usr/lib/perl5/5.13.10/i686-debug-cygwin/DynaLoader.pm line 103
        # Update: Moose works ok with r1013
	 return 'hangs threaded, $] >= 5.011004' if $_ eq $module;
      }
    }
  }
}
