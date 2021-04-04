#! /usr/bin/env perl
# http://code.google.com/p/perl-compiler/issues/detail?id=68
# newPMOP assertion >=5.10 threaded
use strict;
my $name = "ccode68i";
use Test::More tests => 1;
use Config;

my $source = <<'EOF';
package A;
sub test {
   use Data::Dumper ();
   
   $_ =~ /^(.*?)\d+$/;
   "Some::Package"->new();
}
print q(ok);
EOF

open F, ">", "$name.pl";
print F $source;
close F;

my $expected = "ok";
my $runperl = $^X =~ m/\s/ ? qq{"$^X"} : $^X;
my $Mblib = "-Iblib/arch -Iblib/lib";
if ($] < 5.008) {
  system "$runperl -MO=Bytecode,-o$name.plc $name.pl";
} else {
  system "$runperl $Mblib -MO=-qq,Bytecode,-H,-o$name.plc $name.pl";
}
unless (-e "$name.plc") {
  print "not ok 1 #B::Bytecode failed.\n";
  exit;
}
my $runexe = $] < 5.008
  ? "$runperl -MByteLoader $name.plc"
  : "$runperl $Mblib $name.plc";
my $result = `$runexe`;
$result =~ s/\n$//;

TODO: {
  use B::Bytecode;
  local $TODO = "threaded >= 5.010" if $] >= 5.010 and $Config{useithreads} and $B::Bytecode::VERSION lt "1.14";
  ok($result eq $expected, "issue68 - newPMOP assert");
}

END {
  unlink($name, "$name.plc", "$name.pl")
    if $result eq $expected;
}
