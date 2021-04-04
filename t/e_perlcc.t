# -*- cperl -*-
# t/e_perlcc.t - after c, before i(ssue*.t) and m(modules.t)
# test most perlcc options

use strict;
use Test::More tests => 80;
use Config;

my $usedl = $Config{usedl} eq 'define';
my $X = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $exe = $^O =~ /MSWin32|cygwin|msys/ ? 'a.exe' : 'a.out';
my $a   = $^O eq 'MSWin32' ? 'a.exe' : 'a';
my $redir = $^O eq 'MSWin32' ? '' : '2>&1';
my $devnull = $^O eq 'MSWin32' ? '' : '2>/dev/null';
#my $o = '';
#$o = "-Wb=-fno-warnings" if $] >= 5.013005;
#$o = "-Wb=-fno-fold,-fno-warnings" if $] >= 5.013009;
my $perlcc = "$X -Iblib/arch -Iblib/lib blib/script/perlcc";
sub cleanup { unlink ('a.out.c', "a.c", $exe, $a, "a.out.c.lst", "a.c.lst"); }
my $e = q("print q(ok)");

is(`$perlcc -S -o a -r -e $e $devnull`, "ok", "-S -o a -r -e");
ok(-e 'a.c', "-S => a.c file");
ok(-e $a, "keep a executable"); #3
cleanup;

is(`$perlcc -o a -r -e $e $devnull`, "ok", "-o a r -e");
ok(! -e 'a.c', "no a.c file");
ok(-e $a, "keep a executable"); # 6
cleanup;

is(`$perlcc -r -e $e $devnull`, "ok", "-r -e"); #7
ok(! -e 'a.out.c', "no a.out.c file");
ok(-e $exe, "keep default executable"); #9
cleanup;

system(qq($perlcc -o a -e $e $devnull));
ok(-e $a, '-o => -e a');
is($^O eq 'MSWin32' ? `a` : `./a`, "ok", "./a => ok"); #11
cleanup;

# Try a simple XS module which exists in 5.6.2 and blead (test 45)
$e = q("use Data::Dumper ();Data::Dumper::Dumpxs({});print q(ok)");
is(`$perlcc -r -e $e  $devnull`, "ok", "-r xs ".($usedl ? "dynamic" : "static")); #12
cleanup;

SKIP: {
  #skip "--staticxs hangs on darwin", 10 if $^O eq 'darwin';
 TODO: {
    # fails 5.8,5.15 and darwin only
    local $TODO = '--staticxs is experimental' if $^O =~ /^darwin|MSWin32$/ or $] < 5.010;
    is(`$perlcc --staticxs -r -e $e $devnull`, "ok", "-r --staticxs xs"); #13
    ok(-e $exe, "keep executable"); #14
  }
  ok(! -e 'a.out.c', "delete a.out.c file without -S");
  ok(! -e 'a.out.c.lst', "delete a.out.c.lst without -S");
  cleanup;

 TODO: {
    local $TODO = '--staticxs is experimental' if $^O eq 'darwin' or $] < 5.010 or $] > 5.015;
    is(`$perlcc --staticxs -S -o a -r -e $e  $devnull`, "ok",
       "-S -o -r --staticxs xs"); #17
    ok(-e $a, "keep executable"); #18
  }
  ok(-e 'a.c', "keep a.c file with -S");
  ok(-e 'a.c.lst', "keep a.c.lst with -S");
  cleanup;

  is(`$perlcc --staticxs -S -o a -O3 -r -e "print q(ok)"  $devnull`, "ok",
     "-S -o -r --staticxs without xs");
  ok(! -e 'a.c.lst', "no a.c.lst without xs"); #22
  cleanup;
}

my $f = "a.pl";
open F,">",$f;
print F q(print q(ok));
close F;
$e = q("print q(ok)");

is(`$perlcc -S -o a -r $f $devnull`, "ok", "-S -o -r file");
ok(-e 'a.c', "-S => a.c file");
cleanup;

is(`$perlcc -o a -r $f $devnull`, "ok", "-r -o file");
ok(! -e 'a.c', "no a.c file");
ok(-e $a, "keep executable");
cleanup;


is(`$perlcc -o a $f $devnull`, "", "-o file");
ok(! -e 'a.c', "no a.c file");
ok(-e $a, "executable");
is($^O eq 'MSWin32' ? `a` : `./a`, "ok", "./a => ok");
cleanup;

is(`$perlcc -S -o a $f $devnull`, "", "-S -o file");
ok(-e $a, "executable");
is($^O eq 'MSWin32' ? `a` : `./a`, "ok", "./a => ok");
cleanup;

is(`$perlcc -Sc -o a $f $devnull`, "", "-Sc -o file");
ok(-e 'a.c', "a.c file");
ok(! -e $a, "-Sc no executable, compile only");
cleanup;

is(`$perlcc -c -o a $f $devnull`, "", "-c -o file");
ok(-e 'a.c', "a.c file");
ok(! -e $a, "-c no executable, compile only"); #40
cleanup;

#SKIP: {
TODO: {
  #skip "--stash hangs < 5.12", 3 if $] < 5.012; #because of DB?
  #skip "--stash hangs >= 5.14", 3 if $] >= 5.014; #because of DB?
  local $TODO = "B::Stash imports too many";
  is(`$perlcc -stash -r -o a $f $devnull`, "ok", "old-style -stash -o file"); #41
  is(`$perlcc --stash -r -oa $f $devnull`, "ok", "--stash -o file");
  ok(-e $a, "executable");
  cleanup;
}#}

is(`$perlcc -t -o a $f $devnull`, "", "-t -o file"); #44
TODO: {
  local $TODO = '-t unsupported with 5.6' if $] < 5.007;
  ok(-e $a, "executable"); #45
  is($^O eq 'MSWin32' ? `a` : `./a`, "ok", "./a => ok"); #46
}
cleanup;

is(`$perlcc -T -o a $f $devnull`, "", "-T -o file");
ok(-e $a, "executable");
is($^O eq 'MSWin32' ? `a` : `./a`, "ok", "./a => ok");
cleanup;

# compiler verboseness
isnt(`$perlcc --Wb=-fno-fold,-v -o a $f $redir`, '/Writing output/m',
     "--Wb=-fno-fold,-v -o file");
TODO: {
  local $TODO = "catch STDERR not STDOUT" if $^O =~ /bsd$/i; # fails freebsd only
  like(`$perlcc -B --Wb=-DG,-v -o a $f $redir`, "/-PV-/m",
       "-B -v5 --Wb=-DG -o file"); #51
}
cleanup;
is(`$perlcc -Wb=-O1 -r $f $devnull`, "ok", "old-style -Wb=-O1");

# perlcc verboseness
isnt(`$perlcc -v 1 -o a $f $devnull`, "", "-v 1 -o file");
isnt(`$perlcc -v1 -o a $f $devnull`, "", "-v1 -o file");
isnt(`$perlcc -v2 -o a $f $devnull`, "", "-v2 -o file");
isnt(`$perlcc -v3 -o a $f $devnull`, "", "-v3 -o file");
isnt(`$perlcc -v4 -o a $f $devnull`, "", "-v4 -o file");
TODO: {
  local $TODO = "catch STDERR not STDOUT" if $^O =~ /bsd$/i; # fails freebsd only
  like(`$perlcc -v5 $f $redir`, '/Writing output/m',
       "-v5 turns on -Wb=-v"); #58
  like(`$perlcc -v5 -B $f $redir`, '/-PV-/m',
       "-B -v5 turns on -Wb=-v"); #59
  like(`$perlcc -v6 $f $redir`, '/saving magic for AV/m',
       "-v6 turns on -Dfull"); #60
  like(`$perlcc -v6 -B $f $redir`, '/nextstate/m',
       "-B -v6 turns on -DM,-DG,-DA"); #61
}
cleanup;

# switch bundling since 2.10
is(`$perlcc -r -e$e $devnull`, "ok", "-e$e");
cleanup;
like(`$perlcc -v1 -r -e$e $devnull`, '/ok$/m', "-v1");
cleanup;
is(`$perlcc -oa -r -e$e $devnull`, "ok", "-oa");
cleanup;

is(`$perlcc -OSr -oa $f $devnull`, "ok", "-OSr -o file");
ok(-e 'a.c', "-S => a.c file");
cleanup;

is(`$perlcc -Or -oa $f $devnull`, "ok", "-Or -o file");
ok(! -e 'a.c', "no a.c file");
ok(-e $a, "keep executable");
cleanup;

# -BS: ignore -S
like(`$perlcc -BSr -oa.plc -e $e $redir`, '/-S ignored/', "-BSr -o -e");
ok(-e 'a.plc', "a.plc file");
cleanup;

is(`$perlcc -Br -oa.plc $f $devnull`, "ok", "-Br -o file");
ok(-e 'a.plc', "a.plc file");
cleanup;

is(`$perlcc -B -oa.plc -e$e $devnull`, "", "-B -o -e");
ok(-e 'a.plc', "a.plc");
TODO: {
  local $TODO = 'yet unsupported 5.6' if $] < 5.007;
  is(`$X -Iblib/arch -Iblib/lib a.plc`, "ok", "executable plc"); #76
}
cleanup;

#-f directly
{
  like(`$perlcc -fstash -v1 $f -c $redir`, '/,-fstash,/', "-fstash");
  like(`$perlcc --f stash -v1 $f -c $redir`, '/,-fstash,/', "--f stash");
  my $out = `$perlcc -fstash -v1 -fno-delete-pkg $f -c $redir`;
  like($out, '/,-fstash,/', "mult. -fstash");
  like($out, '/,-fno-delete-pkg,/', "mult. -fno-delete-pkg");
}

#TODO: -m

unlink ($f);
