#! perl

use Config;
use File::Basename qw(&basename &dirname);
use File::Spec;
use Cwd;

# List explicitly here the variables you want Configure to
# generate.  Metaconfig only looks for shell variables, so you
# have to mention them as if they were shell variables, not
# %Config entries.  Thus you write
#  $startperl
# to ensure Configure will look for $Config{startperl}.
# Wanted:  $archlibexp

# This forces PL files to create target in same directory as PL file.
# This is so that make depend always knows where to find PL derivatives.
$origdir = cwd;
chdir dirname($0);
$file = basename($0, '.PL');
$file .= '.com' if $^O eq 'VMS';

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

# In this section, perl variables will be expanded during extraction.
# You can use $Config{...} to use Configure variables.

print OUT <<"!GROK!THIS!";
$Config{startperl}
    eval 'exec $Config{perlpath} -S \$0 \${1+"\$@"}'
    if \$running_under_some_shell;
--\$running_under_some_shell;
!GROK!THIS!

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';

# Version 2.0, Simon Cozens, Thu Mar 30 17:52:45 JST 2000
# Version 2.01, Tom Christiansen, Thu Mar 30 08:25:14 MST 2000
# Version 2.02, Simon Cozens, Sun Apr 16 01:53:36 JST 2000
# Version 2.03, Edward Peschko, Mon Feb 26 12:04:17 PST 2001
# Version 2.04, Enache Adrian, Fri, 18 Jul 2003 23:15:37 +0300
# Version 2.05, Reini Urban, 2009-12-01 00:00:13
# Version 2.06, Reini Urban, 2009-12-28 21:56:15
# Version 2.07, Reini Urban, 2010-06-30 22:32:20
# Version 2.08, Reini Urban, 2010-07-30 21:30:33
# Version 2.09, Reini Urban, 2010-10-11 13:54:52
# Version 2.10, Reini Urban, 2011-02-11 22:58:37
# Version 2.11, Reini Urban, 2011-04-11 20:16:00
# Version 2.12, Reini Urban, 2011-10-02 05:19:00
# Version 2.13, Reini Urban, 2012-01-10 13:03:00
# Version 2.14, Reini Urban, 2012-02-28 09:04:07
# Version 2.15, Reini Urban, 2013-02-01 10:41:54

use strict;
use warnings;
use 5.006_000;

use FileHandle;
use Config;
use Fcntl qw(:DEFAULT :flock);
use File::Temp qw(tempfile);
use File::Basename qw(basename dirname);
# use Cwd;
use Pod::Usage;
# Time::HiRes does not work with 5.6
# use Time::HiRes qw(gettimeofday tv_interval);
our $VERSION = 2.15;
$| = 1;
eval { require B::C::Flags; };

$SIG{INT} = sub { exit(); } if exists $SIG{INT}; # exit gracefully and clean up after ourselves.

use subs qw{
    cc_harness check_read check_write checkopts_byte choose_backend
    compile_byte compile_cstyle compile_module generate_code
    grab_stash parse_argv sanity_check vprint yclept spawnit
    gettimeofday tv_interval vsystem
};
sub opt(*); # imal quoting
sub is_win32();
sub is_msvc();

our ($Options, $BinPerl, $Backend);
our ($Input => $Output);
our ($logfh);
our ($cfile);
our (@begin_output); # output from BEGIN {}, for testsuite
our ($extra_libs);

# eval { main(); 1 } or die;

main();

sub main {
    parse_argv();
    check_write($Output);
    choose_backend();
    generate_code();
    run_code();
    _die("Not reached?");
}

#######################################################################

sub choose_backend {
    # Choose the backend.
    $Backend = 'C';
    if (opt('B')) {
        checkopts_byte();
        $Backend = 'Bytecode';
    }
    if (opt('S') && opt('c')) {
        # die "$0: Do you want me to compile this or not?\n";
        delete $Options->{S};
    }
    $Backend = 'CC' if opt('O');
}

sub generate_code {

    vprint 4, "Compiling $Input";

    $BinPerl  = yclept();  # Calling convention for perl.

    if (exists $Options->{m}) {
        compile_module();
    } else {
        if ($Backend eq 'Bytecode') {
            compile_byte();
        } else {
            compile_cstyle();
        }
    }
    exit(0) if (!opt('r'));
}

sub run_code {
    if ($Backend eq 'Bytecode') {
        if ($] < 5.007) {
            $Output = "$BinPerl -MByteLoader $Output";
        } else {
            $Output = "$BinPerl $Output";
        }
    }
    if (opt('staticxs') and $extra_libs) {
        my $path = '';
        my $PATHSEP = $^O eq 'MSWin32' ? ';' : ':';
        for (split / /, $extra_libs) {
            s{/[^/]+$}{};
            # XXX qx quote?
            $path .= $PATHSEP.$_ if $_;
        }
        if ($^O =~ /^MSWin32|msys|cygwin$/) {
            $ENV{PATH} .= $path;
            vprint 0, "PATH=\$PATH$path";
        } elsif ($^O ne 'darwin') {
            $ENV{LD_LIBRARY_PATH} .= $path;
            vprint 0, "LD_LIBRARY_PATH=\$LD_LIBRARY_PATH$path";
        }
    }
    vprint 0, "Running code $Output @ARGV";
    run("$Output @ARGV");
    exit(0);
}

# usage: vprint [level] msg args
sub vprint {
    my $level;
    if (@_ == 1) {
        $level = 1;
    } elsif ($_[0] =~ /^-?\d$/) {
        $level = shift;
    } else {
        # well, they forgot to use a number; means >0
        $level = 0;
    }
    my $msg = "@_";
    $msg .= "\n" unless substr($msg, -1) eq "\n";
    if (opt('v') > $level)
    {
	if (opt('log')) {
	    print $logfh "$0: $msg" ;
	} else {
	    print        "$0: $msg";
	}
    }
}

sub vsystem {
    if (opt('dryrun')) {
        print "@_\n";
    } else {
       system(@_);
    }
}

sub parse_argv {

    use Getopt::Long;

    # disallows using long arguments
    Getopt::Long::Configure("bundling");
    Getopt::Long::Configure("no_ignore_case");

    # no difference in exists and defined for %ENV; also, a "0"
    # argument or a "" would not help cc, so skip
    unshift @ARGV, split ' ', $ENV{PERLCC_OPTS} if $ENV{PERLCC_OPTS};

    $Options = {};
    # support single dash -Wb. GetOptions requires --Wb with bundling enabled.
    if (my ($wb) = grep /^-Wb=(.+)/, @ARGV) {
        $Options->{Wb} = substr($wb,4);
        @ARGV = grep !/^-Wb=(.+)/, @ARGV;
    }
    # -O2 i.e. -Wb=-O1 (new since 2.13)
    if (my ($o1) = grep /^-O(\d)$/, @ARGV) {
        $Options->{Wb} = $Options->{Wb} ? $Options->{Wb}.",$o1" : $o1;
        @ARGV = grep !/^-O\d$/, @ARGV;
    }
    if (my ($v) = grep /^-v\d$/, @ARGV) {
        $Options->{v} = 0+substr($v,2);
        @ARGV = grep !/^-v\d$/, @ARGV;
    }
    if (grep /^-stash$/, @ARGV) {
        $Options->{stash}++;
        @ARGV = grep !/^-stash$/, @ARGV;
    }
    $Options->{spawn} = 1;
    Getopt::Long::GetOptions( $Options,
        'L=s',          # lib directory
        'I=s',          # include directories (FOR C, NOT FOR PERL)
        'o=s',          # Output executable
        'v:i',          # Verbosity level
        'e=s',          # One-liner
        'm|sharedlib:s',# as Module [name] (new since 2.11, not yet tested)
	'r',            # run resulting executable
        'B',            # Byte compiler backend
        'O',            # Optimised C backend B::CC
         #'O1-4'        # alias for -Wb=-O1 (new since 2.13)
        'dryrun|n',     # only print commands, do not execute
        'c',            # Compile only
        'help|h',       # Help me
        'S',            # Dump C files
        'T',            # run the backend using perl -T
        't',            # run the backend using perl -t
        'u=s@',         # use packages (new since 2.13)
        'U=s@',         # skip packages (new since 2.13)
        'static',       # Link to static libperl (default, new since 2.11)
        'shared',       # Link to shared libperl (new since 2.07)
        'staticxs',     # Link static XSUBs (new since 2.07)
        'sharedxs',     # Link shared XSUBs (default, new since 2.07))
        'stash',        # Detect external packages via B::Stash
	'log:s',        # where to log compilation process information
        'Wb=s',         # pass (comma-seperated) options to backend
        'f=s@',         # pass compiler option(s) to backend (new since 2.14)
        'Wc=s',         # pass (comma-seperated) options to cc (new since 2.13)
        'Wl=s',         # pass (comma-seperated) options to ld (new since 2.13)
        'testsuite',    # try to be nice to testsuite (STDOUT, STDERR handles)
        'spawn!',	# --no-spawn (new since 2.12)
        'time',         # print benchmark timings (new since 2.08)
        'version',      # (new since 2.13)
    );

    $Options->{v} += 0;

    if( opt('t') && opt('T') ) {
        warn "Can't specify both -T and -t, -t ignored";
        $Options->{t} = 0;
    }

    helpme() if opt('help'); # And exit
    if (opt('version')) {
      die version();
    }

    $Options->{Wb} .= ",-O1" if opt('O1');
    $Options->{Wb} .= ",-O2" if opt('O2');
    $Options->{Wb} .= ",-O3" if opt('O3');
    $Options->{Wb} .= ",-O4" if opt('O4');

    if( $Options->{time} or $Options->{spawn} ) {
      eval { require Time::HiRes; }; # 5.6 has no Time::HiRes
      if ($@) {
        warn "--time ignored. No Time::HiRes\n" if $Options->{time};
        $Options->{time} = 0;
      } else {
        sub main::gettimeofday () {};
        Time::HiRes->import('gettimeofday','tv_interval','sleep');
      }
    }
    $logfh  = new FileHandle(">> " . opt('log')) if (opt('log'));

    if (opt('e')) {
        warn "$0: using -e 'code' as input file, ignoring @ARGV\n" if @ARGV;
        # We don't use a temporary file here; why bother?
        # XXX: this is not bullet proof -- spaces or quotes in name!
        $Input = is_win32() ? # Quotes eaten by shell
            '-e "'.opt('e').'"' :
            "-e '".opt('e')."'";
    } else {
        $Input = shift @ARGV;  # XXX: more files?
        _usage_and_die("No input file specified\n") unless $Input;
        # DWIM modules. This is bad but necessary.
        $Options->{m} = '' if $Input =~ /\.pm\z/ and !opt('m');
        vprint 1, "$0: using $Input as input file, ignoring @ARGV\n" if @ARGV;
        check_read($Input);
        check_perl($Input);
    }

    if (opt('o')) {
        $Output = opt('o');
    } elsif (opt('B')) {
        if (opt('e')) {
            my $suffix = '.plc';
            $suffix = '.pmc' if exists $Options->{m};
            (undef, $Output) = tempfile("plcXXXXX", SUFFIX => $suffix);
        } else {
            $Output = basename($Input) . "c";
        }
    } else {
        $Output = ( is_win32() or $^O eq 'cygwin' ) ? 'a.exe' : 'a.out';
    }
    $Output = relativize($Output) unless is_win32();
    sanity_check();
}

sub opt(*) {
    my $opt = shift;
    return exists($Options->{$opt}) && ($Options->{$opt} || 0);
}

sub compile_module {
    if ($Backend eq 'Bytecode') {
        compile_byte('-m'.$Options->{m});
    } else {
        compile_cstyle("-m".$Options->{m});
    }
}

sub compile_byte {

    vprint 3, "Writing B on $Output";
    my $opts = $] < 5.007 ? "" : "-H,-s,";
    if ($] >= 5.007 and $Input =~ /^-e/) {
        $opts = "-H,";
    }
    if (@_ == 1) {
        $opts .= $_[0].",";
    }
    my $addoptions = opt('Wb');
    if( $addoptions ) {
        $opts .= '-v,' if opt('v') > 4;
        $opts .= '-DM,-DG,-DA,-DComment,' if opt('v') > 5;
        $opts .= "$addoptions,";
    } elsif (opt('v') > 4) {
        $opts .= '-v,';
        $opts .= '-DM,-DG,-DA,-DComment,' if opt('v') > 5;
    }
    my $command = "$BinPerl -MO=Bytecode,$opts-o$Output $Input";
    $Input =~ s/^-e.*$/-e/;
    vprint 5, "Compiling...";
    vprint 0, "Calling $command";

    my $t0 = [gettimeofday] if opt('time');
    my ($output_r, $error_r, $errcode) = spawnit($command);
    my $elapsed = tv_interval ( $t0 ) if opt('time');
    vprint -1, "c time: $elapsed" if opt('time');

    if (@$error_r && $errcode != 0) {
	_die("$Input did not compile $errcode:\n@$error_r\n");
    } else {
	my @error = grep { !/^$Input syntax OK$/o } @$error_r;
	warn "$0: Unexpected compiler output\n@error" if @error and opt('v')<5;
	warn "@error" if @error and opt('v')>4;
    }

    unless (opt('dryrun')) {
      chmod 0777 & ~umask, $Output    or _die("can't chmod $Output: $!\n");
    }
}

sub compile_cstyle {
    my $stash = opt('stash') ? grab_stash() : "";
    $stash .= "," if $stash; #stash can be empty
    $stash .= "-u$_," for @{$Options->{u}};
    $stash .= "-U$_," for @{$Options->{U}};

    my $taint = opt('T') ? ' -T' :
                       opt('t') ? ' -t' : '';

    # What are we going to call our output C file?
    my $lose = 0;
    my ($cfh);
    my $testsuite = '';
    my $addoptions = '';
    if (@_ == 1) {
        $addoptions .= $_[0].",";
    }
    $addoptions .= opt('Wb');
    if( $addoptions ) {
        $addoptions .= ',-Dfull' if opt('v') >= 6;
        $addoptions .= ',-Dsp,-v' if opt('v') == 5;
        $addoptions .= ',';
    } elsif (opt('v') > 4) {
        $addoptions = '-Dsp,-v,';
        $addoptions = '-Dfull,-v,' if opt('v') >= 6;
    }
    if (opt('f')) {
        $addoptions .= "-f$_," for @{$Options->{f}};
    }

    my $staticxs = opt('staticxs') ? "-staticxs," : '';
    warn "--staticxs on darwin does not work yet\n"
        if $staticxs and $^O eq 'darwin';
    if (opt('testsuite')) {
        my $bo = join '', @begin_output;
        $bo =~ s/\\/\\\\\\\\/gs;
        $bo =~ s/\n/\\n/gs;
        $bo =~ s/,/\\054/gs;
        # don't look at that: it hurts
        $testsuite = q{-fuse-script-name,-fsave-data,-fsave-sig-hash,}.
            qq[-e"print q{$bo}",] .
            q{-e"open(Test::Builder::TESTOUT\054 '>&STDOUT') or die $!",} .
            q{-e"open(Test::Builder::TESTERR\054 '>&STDERR') or die $!",};
    }
    if (opt('o')) {
        $cfile = opt('o').".c";
    } elsif (opt('S') || opt('c')) { # We need to keep it
        if (opt('e')) {
            $cfile = opt('o') ? opt('o').".c" : "a.out.c";
        } else {
            $cfile = basename($Input);
            # File off extension if present
            # hold on: plx is executable; also, careful of ordering!
            $cfile =~ s/\.(?:p(?:lx|l|h)|m)\z//i;
            $cfile .= ".c";
            $cfile = $Output if opt('c') && $Output =~ /\.c\z/i;
        }
        check_write($cfile);
    } else { # Do not keep tempfiles (no -S nor -c nor -o)
        $lose = 1;
        ($cfh, $cfile) = tempfile("pccXXXXX", SUFFIX => ".c");
        close $cfh; # See comment just below
    }
    vprint 3, "Writing C on $cfile";

    my $max_line_len = '';
    if ($^O eq 'MSWin32' && $Config{cc} =~ /^cl/i) {
        $max_line_len = '-l2000,';
    }

    my $options = "$addoptions$testsuite$max_line_len$staticxs$stash";
    # This has to do the write itself, so we can't keep a lock. Life
    # sucks.
    my $command = "$BinPerl$taint -MO=$Backend,$options"."-o$cfile $Input";
    vprint 5, "Compiling...";
    vprint 0, "Calling $command";

    my $t0 = [gettimeofday] if opt('time');
    my ($output_r, $error_r, $errcode) = spawnit($command);
    my $elapsed = tv_interval ( $t0 ) if opt('time');
    my @output = @$output_r;
    my @error = @$error_r;

    if (@error && $errcode != 0) {
        _die("$Input did not compile, which can't happen $errcode:\n@error\n");
    } else {
        my $i = substr($Input,0,2) eq '-e' ? '-e' : $Input;
        @error = grep { !/^$i syntax OK$/o } @error;
        warn "$0: Unexpected compiler output\n@error" if @error and opt('v')<5;
        warn "@error" if @error and opt('v')>4;
    }
    vprint -1, "c time: $elapsed" if opt('time');
    $extra_libs = '';
    my %rpath;
    if ($staticxs and open(XS, "<", $cfile.".lst")) {
        while (<XS>) {
            my ($s, $l) = m/^([^\t]+)(.*)$/;
            next if grep { $s eq $_ } @{$Options->{U}};
            $stash .= ",-u$s";
            if ($l) {
                $l = substr($l,1);
                if ($^O eq 'darwin' and $l =~/\.bundle$/) {
                    my $ofile = $l;
                    $ofile =~ s/\.bundle$/.o/;
                    $ofile =~ s{^.*/auto/}{};
                    $ofile =~ s{(.*)/[^/]+\.o}{$1.o};
                    $ofile =~ s{/}{_}g;
                    $ofile = 'pcc'.$ofile;
                    if (-e $ofile) {
                        vprint 3, "Using ".$ofile;
                    } else {
                        vprint 3, "Creating ".$ofile;
                        # This fails sometimes
                        my $cmd = "otool -tv $l | \"$^X\" -pe "
        . q{'s{^/}{# .file /};s/^00[0-9a-f]+\s/\t/;s/^\(__(\w+)(,__.*?)?\) section/q(.).lc($1)/e'} 
        . " | as -o \"$ofile\"";
                        vprint 3, $cmd;
                        vsystem($cmd);
                    }
                    $extra_libs .= " ".$l if -e $ofile;
                } else {
                    $extra_libs .= " ".$l;
                    $rpath{dirname($l)}++;
                }
            }
        }
        close XS;
        my ($rpath) = $Config{ccdlflags} =~ /^(.+rpath,)/;
        ($rpath) = $Config{ccdlflags} =~ m{^(.+-R,)/} unless $rpath;
        if (!$rpath and $Config{gccversion}) {
            $rpath = '-Wl,-rpath,';
        }
        $rpath =~ s/^-Wl,-E// if $rpath;         # already done via ccdlflags
        # $extra_libs .= " $rpath".join(" ".$rpath,keys %rpath) if $rpath and %rpath;
        vprint 4, "staticxs: $stash $extra_libs";
    }

    $t0 = [gettimeofday] if opt('time');
    is_msvc ?
        cc_harness_msvc($cfile, $stash, $extra_libs) :
        cc_harness($cfile, $stash, $extra_libs) unless opt('c');
    $elapsed = tv_interval ( $t0 ) if opt('time');
    vprint -1, "cc time: $elapsed" if opt('time');

    if ($lose and -s $Output) {
        vprint 3, "Unlinking $cfile";
        unlink $cfile or _die("can't unlink $cfile: $!\n");
    }
}

sub cc_harness_msvc {
    my ($cfile, $stash, $extra_libs) = @_;
    use ExtUtils::Embed ();
    my $obj = "${Output}.obj";
    my $compile = ExtUtils::Embed::ccopts." -c -Fo$obj $cfile ";
    my $link = "-out:$Output $obj";
    $compile .= " -DHAVE_INDEPENDENT_COMALLOC" if $B::C::Flags::have_independent_comalloc;
    $compile .= $B::C::Flags::extra_cflags;
    $compile .= " -I".$_ for split /\s+/, opt('I');
    $compile .= " -DNO_DYNAMIC_LOADING" if opt('staticxs');
    $compile .= " ".opt('Wc') if opt('Wc');

    $link .= " -libpath:".$_ for split /\s+/, opt('L');
    # TODO: -shared,-static,-sharedxs
    if ($stash) {
        my @mods = split /,?-?u/, $stash; # XXX -U stashes
        $link .= " ".ExtUtils::Embed::ldopts("-std", \@mods);
        # XXX staticxs need to check if the last mods for staticxs found a static lib.
        # XXX only if not use the extra_libs
    } else {
        $link .= " ".ExtUtils::Embed::ldopts("-std");
    }
    if ($Config{ccversion} eq '12.0.8804') {
        $link =~ s/ -opt:ref,icf//;
    }
    $link .= " ".opt('Wl') if opt('Wl');
    $link .= $extra_libs;
    $link .= " perl5$Config{PERL_VERSION}.lib kernel32.lib msvcrt.lib";
    $link .= $B::C::Flags::extra_libs;
    vprint 3, "Calling $Config{cc} $compile";
    vsystem("$Config{cc} $compile");
    vprint 3, "Calling $Config{ld} $link";
    vsystem("$Config{ld} $link");
}

sub cc_harness {
    my ($cfile, $stash, $extra_libs) = @_;
    use ExtUtils::Embed ();
    my $command = ExtUtils::Embed::ccopts." -o $Output $cfile ";
    $command .= " -DHAVE_INDEPENDENT_COMALLOC" if $B::C::Flags::have_independent_comalloc;
    $command .= $B::C::Flags::extra_cflags if $B::C::Flags::extra_cflags;
    $command .= " -I".$_ for split /\s+/, opt('I');
    $command .= " -L".$_ for split /\s+/, opt('L');
    $command .= " -DNO_DYNAMIC_LOADING" if opt('staticxs');
    $command .= " ".opt('Wc') if opt('Wc');
    my $ccflags = $command;

    my $useshrplib = $Config{useshrplib};
    _die("--sharedxs with useshrplib=false\n") if !$useshrplib and opt('sharedxs');
    my $ldopts;
    if ($stash) {
        my @mods = split /,?-?u/, $stash; # XXX -U stashes
        $ldopts = ExtUtils::Embed::ldopts("-std", \@mods);
    } else {
        $ldopts = ExtUtils::Embed::ldopts("-std");
    }
    $ldopts .= " ".opt('Wl') if opt('Wl');

    # gcc crashes with this duplicate -fstack-protector arg
    my $ldflags = $Config{ldflags};
    if ($ccflags =~ /-fstack-protector/ and $ldopts =~ /-fstack-protector/) {
        $ldopts =~ s/-fstack-protector//;
        $ldflags =~ s/-fstack-protector// if $extra_libs;
    }
    my $libperl = $Config{libperl};
    my $libdir  = $Config{prefix} . "/lib";
    my $coredir = $ENV{PERL_SRC} || $Config{archlib}."/CORE";
    if ($extra_libs) {
        # splice extra_libs after $Config{ldopts} before @archives
        my $i_ldopts = index($ldopts, $ldflags);
        if ($ldflags and $i_ldopts >= 0) {
            my $l = $i_ldopts + length($ldflags);
            $ldopts = substr($ldopts,0,$l).$extra_libs." ".substr($ldopts,$l);
        } else {
            $ldopts = $extra_libs." ".$ldopts;
        }
    }
    if (opt('shared')) {
        warn "--shared with useshrplib=false might not work\n" unless $useshrplib;
        my @plibs = ($libperl, "$coredir/$libperl", "$libdir/$libperl");
	if ($libperl !~ /$Config{dlext}$/) {
            $libperl = "libperl.".$Config{dlext};
            @plibs = ($libperl, "$coredir/$libperl", "$libdir/$libperl");
            push @plibs, glob "$coredir/*perl5*".$Config{dlext};
            push @plibs, glob "$coredir/*perl.".$Config{dlext};
            push @plibs, glob $libdir."/*perl5*.".$Config{dlext};
            push @plibs, glob $libdir."/*perl.".$Config{dlext};
            push @plibs, glob $Config{bin}."/perl*.".$Config{dlext};
        }
        for my $lib (@plibs) {
            if (-e $lib) {
	        $ldopts =~ s|-lperl |$lib |;
	        $ldopts =~ s|\s+\S+libperl\w+\.a | $lib |;
	        $ldopts = "$coredir/DynaLoader.o $ldopts" if -e "$coredir/DynaLoader.o";
	        last;
            }
        }
    } elsif (opt('static')) {
        for my $lib ($libperl, "$coredir/$libperl", "$coredir/$libperl",
                   "$coredir/libperl.a", "$libdir/libperl.a") {
            if (-e $lib) {
	        $ldopts =~ s|-lperl |$lib |;
	        $ldopts = "$coredir/DynaLoader.o $ldopts" if -e "$coredir/DynaLoader.o";
	        last;
            }
        }
    } else {
        if ( $useshrplib and -e $libdir."/".$Config{libperl}) {
	    # debian: only /usr/lib/libperl.so.5.10.1 and broken ExtUtils::Embed::ldopts
	    $ldopts =~ s|-lperl |$libdir/$Config{libperl} |;
        }
        if ( $useshrplib and -e $coredir."/".$Config{libperl}) {
            # help cygwin debugging
	    $ldopts =~ s|-lperl |$coredir/$Config{libperl} |;
        }
    }
    $ldopts .= " -lperl" unless $command =~ /perl/;
    $command .= " ".$ldopts;
    $command .= $B::C::Flags::extra_libs if $B::C::Flags::extra_libs;
    vprint 3, "Calling $Config{cc} $command";
    vsystem("$Config{cc} $command");
}

# Where Perl is, and which include path to give it.
sub yclept {
    my $command = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
    # DWIM the -I to be Perl, not C, include directories.
    if (opt('I') && $Backend eq "Bytecode") {
        for (split /\s+/, opt('I')) {
            if (-d $_) {
                push @INC, $_;
            } else {
                warn "$0: Include directory $_ not found, skipping\n";
            }
        }
    }
    my %OINC;
    $OINC{$Config{$_}}++ for (qw(privlib archlib sitelib sitearch vendorlib vendorarch));
    $OINC{'.'}++ unless ${^TAINT};
    $OINC{$_}++ for split ':', $Config{otherlibdirs};
    if (my $incver = $Config{inc_version_list}) {
        my $incpre = dirname($Config{sitelib});
        $OINC{$_}++ for map { File::Spec->catdir($incpre,$_) } split(' ',$incver);
    }
    for my $i (@INC) {
        my $inc = $i =~ m/\s/ ? qq{"$i"} : $i;
        $command .= " -I$inc" unless $OINC{$i}; # omit internal @INC dirs
    }

    return $command;
}

# Use B::Stash to find additional modules and stuff.
{
    my $_stash;
    sub grab_stash {

        warn "already called grab_stash once" if $_stash;

        my $taint = opt('T') ? ' -T' :
                    opt('t') ? ' -t' : '';
        my $command = "$BinPerl$taint -MB::Stash -c $Input";
        # Filename here is perfectly sanitised.
        vprint 3, "Calling $command\n";

        my ($stash_r, $error_r, $errcode) = spawnit($command);
        my @stash = @$stash_r;
        my @error = @$error_r;

        if (@error && $errcode != 0) {
            _die("$Input did not compile $errcode:\n@error\n");
        }

        # band-aid for modules with noisy BEGIN {}
        foreach my $i ( @stash ) {
            $i =~ m/-[ux](?:[\w:]+|\<none\>)$/ and $stash[0] = $i and next;
            push @begin_output, $i;
        }
        chomp $stash[0];
        $stash[0] =~ s/,-[ux]\<none\>//;
        $stash[0] =~ s/^.*?-([ux])/-$1/s;
        vprint 2, "Stash: ", join " ", split /,?-[ux]/, $stash[0];
        chomp $stash[0];
        return $_stash = $stash[0];
    }
}

# Check the consistency of options if -B is selected.
# To wit, (-B|-O) ==> no -shared, no -S, no -c
sub checkopts_byte {

    _die("Please choose one of either -B and -O.\n") if opt('O');

    for my $o ( qw[shared sharedxs static staticxs] ) {
        if (exists($Options->{$o}) && $Options->{$o}) {
            warn "$0: --$o incompatible with -B\n";
            delete $Options->{$o};
        }
    }
    # TODO make -S produce an .asm also?
    for my $o ( qw[c S] ) {
        if (exists($Options->{$o}) && $Options->{$o}) {
            warn "$0: Compiling to bytecode is a one-pass process. ",
                  "-$o ignored\n";
            delete $Options->{$o};
        }
    }

}

# Check the input and output files make sense, are read/writeable.
sub sanity_check {
    if ($Input eq $Output) {
        if ($Input eq 'a.out') {
            _die("Compiling a.out is probably not what you want to do.\n");
            # You fully deserve what you get now. No you *don't*. typos happen.
        } else {
            warn "$0: Will not write output on top of input file, ",
                "compiling to a.out instead\n";
            $Output = (is_win32 or $^O eq 'cygwin') ? 'a.exe' : 'a.out';
        }
    }
}

sub check_read {
    my $file = shift;
    unless (-r $file) {
        _die("Input file $file is a directory, not a file\n") if -d _;
        unless (-e _) {
            _die("Input file $file was not found\n");
        } else {
            _die("Cannot read input file $file: $!\n");
        }
    }
    unless (-f _) {
        # XXX: die?  don't try this on /dev/tty
        warn "$0: WARNING: input $file is not a plain file\n";
    }
}

sub check_write {
    my $file = shift;
    if (-d $file) {
        _die("Cannot write on $file, is a directory\n");
    }
    if (-e _) {
        _die("Cannot write on $file: $!\n") unless -w _;
    }
    unless (-w '.') {
        _die("Cannot write in this directory: $!\n");
    }
}

sub check_perl {
    my $file = shift;
    unless (-T $file) {
        warn "$0: Binary `$file' sure doesn't smell like perl source!\n";
        print "Checking file type... ";
        vsystem("file", $file);
        _die("Please try a perlier file!\n");
    }

    open(my $handle, "<", $file)    or _die("Can't open $file: $!\n");
    local $_ = <$handle>;
    if (/^#!/ && !/perl/) {
        _die("$file is a ", /^#!\s*(\S+)/, " script, not perl\n");
    }
}

# File spawning and error collecting
sub spawnit {
    my $command = shift;
    my (@error,@output,$errname,$errcode);
    if (opt('dryrun')) {
        print "$command\n";;
    }
    elsif ($Options->{spawn}) {
        (undef, $errname) = tempfile("pccXXXXX");
        {
	    my $pid = open (S_OUT, "$command 2>$errname |")
	      or _die("Couldn't spawn the compiler.\n");
            $errcode = $?;
            my $kid;
            do {
              $kid = waitpid($pid, 0);
            } while $kid > 0;
            @output = <S_OUT>;
        }
        open (S_ERROR, $errname) or _die("Couldn't read the error file.\n");
        @error = <S_ERROR>;
        close S_ERROR;
        close S_OUT;
        unlink $errname or _die("Can't unlink error file $errname\n");
    } else {
        @output = split /\n/, `$command`;
    }
    return (\@output, \@error, $errcode);
}

sub version {
    require B::C::Flags;
    no warnings 'once';
    my $BC_VERSION = $B::C::Flags::VERSION . $B::C::REVISION;
    return "perlcc $VERSION, B-C-${BC_VERSION} built for $Config{perlpath} $Config{archname}\n";
}

sub helpme {
    print version(),"\n";
    if (opt('v')) {
	pod2usage( -verbose => opt('v') );
    } else {
	pod2usage( -verbose => 0 );
    }
}

sub relativize {
    my ($args) = @_;

    return() if ($args =~ m"^[/\\]");
    return("./$args");
}

sub _die {
    my @args = ("$0: ", @_);
    $logfh->print(@args) if opt('log');
    print STDERR @args;
    exit(); # should die eventually. However, needed so that a 'make compile'
            # can compile all the way through to the end for standard dist.
}

sub _usage_and_die {
    _die(<<EOU);
Usage:
$0 [-o executable] [-h][-r] [-O|-B|-c|-S] [-I /foo] [-L /foo] [--log log] [source[.pl] | -e code]
More options (see perldoc perlcc)
  -v[1-4]
  --stash     --staticxs --shared --static
  --testsuite --time
EOU
}

sub run {
    my (@commands) = @_;

    my $t0 = [gettimeofday] if opt('time');
    print interruptrun(@commands) if (!opt('log'));
    $logfh->print(interruptrun(@commands)) if (opt('log'));
    my $elapsed = tv_interval ( $t0 ) if opt('time');
    vprint -1, "r time: $elapsed" if opt('time');
}

sub interruptrun {
    my (@commands) = @_;

    my $command = join('', @commands);
    local(*FD);
    my $pid = open(FD, "$command |");
    my $text;

    local($SIG{HUP}, $SIG{INT}) if exists $SIG{HUP};
    $SIG{HUP} = $SIG{INT} = sub { kill 9, $pid; exit } if exists $SIG{HUP};

    my $needalarm =
          ($ENV{PERLCC_TIMEOUT} &&
	   exists $SIG{ALRM} &&
	  $Config{'osname'} ne 'MSWin32' &&
	  $command =~ m"(^|\s)perlcc\s");

    eval {
         local($SIG{ALRM}) = sub { die "INFINITE LOOP"; } if exists $SIG{ALRM};
         alarm($ENV{PERLCC_TIMEOUT}) if $needalarm;
	 $text = join('', <FD>);
	 alarm(0) if $needalarm;
    };

    if ($@) {
        eval { kill 'HUP', $pid };
        vprint 0, "SYSTEM TIMEOUT (infinite loop?)\n";
    }

    close(FD);
    return($text);
}

sub is_win32() { $^O =~ m/^MSWin/ }
sub is_msvc() { is_win32 && $Config{cc} =~ m/^cl/i }

END {
    if ($cfile && !opt('S') && !opt('c') && -e $cfile) {
        vprint 4, "Unlinking $cfile";
        unlink $cfile;
    }
    if (opt('staticxs') and !opt('S')) {
        vprint 4, "Unlinking $cfile.lst";
        unlink "$cfile.lst";
    }
}

__END__

=head1 NAME

perlcc - generate executables from Perl programs

=head1 SYNOPSIS

    perlcc hello.pl            # Compiles into executable 'a.out'
    perlcc -o hello hello.pl   # Compiles into executable 'hello'

    perlcc -O file.pl          # Compiles using the optimised CC backend
    perlcc -O3 file.pl         # Compiles with C, using -O3 optimizations
    perlcc -B file.pl          # Compiles using the bytecode backend
    perlcc -B -m file.pm       # Compiles a module to file.pmc

    perlcc -c file.pl          # Creates a C file, 'file.c'
    perlcc -S -o hello file.pl # Keep C file
    perlcc -c out.c file.pl    # Creates a C file, 'out.c' from 'file'
    perlcc --staticxs -r -o hello hello.pl # Compiles,links and runs with
                               # XS modules static/dynaloaded

    perlcc -e 'print q//'      # Compiles a one-liner into 'a.out'
    perlcc -c -e 'print q//'   # Creates a C file 'a.out.c'

    perlcc -I /foo hello       # extra headers for C
    perlcc -L /foo hello       # extra libraries for C
    perlcc --Wb=-Dsp           # extra perl compiler options
    perlcc -fno-delete-pkg     # extra perl compiler options
    perlcc --Wc=-fno-openmp    # extra C compiler options
    perlcc --Wl=-s             # extra C linker options

    perlcc -uIO::Socket        # force saving IO::Socket
    perlcc -UB                 # "unuse" B, compile without any B symbols

    perlcc -r hello            # compiles 'hello' into 'a.out', runs 'a.out'
    perlcc -r hello a b c      # compiles 'hello' into 'a.out', runs 'a.out'
                               # with arguments 'a b c'

    perlcc hello -log c.log    # compiles 'hello' into 'a.out', log into 'c.log'

    perlcc -h       	       # help, only SYNOPSIS
    perlcc -v2 -h  	       # verbose help, also DESCRIPTION and OPTIONS
    perlcc --version  	       # prints internal perlcc and the B-C release version

=head1 DESCRIPTION

F<perlcc> creates standalone executables from Perl programs, using the
code generators provided by the L<B> module. At present, you may
either create executable Perl bytecode, using the C<-B> option, or
generate and compile C files using the standard and 'optimised' C
backends.

The code generated in this way is not guaranteed to work. The whole
codegen suite (C<perlcc> included) should be considered B<very>
experimental. Use for production purposes is strongly discouraged.

=head1 OPTIONS

=over 4

=item -LI<C library directories>

Adds the given directories to the library search path when C code is
passed to your C compiler.

=item -II<C include directories>

Adds the given directories to the include file search path when C code is
passed to your C compiler; when using the Perl bytecode option, adds the
given directories to Perl's include path.

=item -o I<output file name>

Specifies the file name for the final compiled executable.

=item -c I<C file name>

Create C code only; do not compile to a standalone binary.

=item -e I<perl code>

Compile a one-liner, much the same as C<perl -e '...'>

=item -S

"Keep source".
Do not delete generated C code after compilation.

=item -B

Use the Perl bytecode code generator.

=item -O

Use the 'optimised' C code generator B::CC. This is more experimental than
everything else put together, and the code created is not guaranteed to
compile in finite time and memory, or indeed, at all.

=item -OI<1-4>

Pass the numeric optimisation option to the compiler backend.
Shortcut for C<-Wb=-On>.

This does not enforce B::CC.

=item -v I<0-6>

Set verbosity of output from 0 to max. 6.

=item -r

Run the resulting compiled script after compiling it.

=item --log I<logfile>

Log the output of compiling to a file rather than to stdout.

=item -f<option> or --f=<option>

Pass the options to the compiler backend, such as
C<-fstash> or C<-fno-delete-pkg>.

=item --Wb=I<options>

Pass the options to the compiler backend, such as C<--Wb=-O2,-v>

=item --Wc=I<options>

Pass comma-seperated options to cc.

=item --Wl=I<options>

Pass comma-seperated options to ld.

=item -T or -t

run the backend using perl -T or -t

=item -u package

Add package(s) to compiler and force linking to it.

=item -U package

Skip package(s). Do not compile and link.

=item --stash

Detect external packages automatically via B::Stash

=item --static

Link to static libperl.a

=item --staticxs

Link to static XS if available.
If the XS libs are only available as shared libs link to those ("prelink").

Systems without rpath (windows, cygwin) must be extend LD_LIBRARY_PATH/PATH at run-time.
Together with -static, purely static modules and no run-time eval or
require this will gain no external dependencies.

=item --shared

Link to shared libperl

=item --sharedxs

Link shared XSUBs if the linker supports it. No DynaLoader needed.
This will still require the shared XSUB libraries to be installed
at the client, modification of @INC in the source is probably required.
(Not yet implemented)

=item -m|--sharedlib [Modulename]

Create a module, resp. a shared library.
Currently only enabled for Bytecode and CC. I<(not yet tested)>

=item --testsuite

  perlcc -r --testsuite t/harness

=item --time

Benchmark the different phases B<c> I<(B::* compilation)>,
B<cc> I<(cc compile + link)>, and B<r> (runtime).

=item --no-spawn

Do not spawn subprocesses for compilation, because broken
shells might not be able to kill its children.

=back

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
!NO!SUBS!

close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
chdir $origdir;
