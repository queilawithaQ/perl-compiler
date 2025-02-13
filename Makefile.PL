use ExtUtils::MakeMaker;
use Config;
use File::Spec;
use 5.006;
use Carp;

my $core = grep { $_ eq 'PERL_CORE=1' } @ARGV;
mkdir "lib/B/C" unless -d "lib/B/C";
unless (-e 'lib/B/C/Flags.pm') {
    open PH, ">", "lib/B/C/Flags.pm";
    print PH "package B::C::Flags;\n\n";
    print PH "\n1;\n";
    close PH;
    chmod 0644, "lib/B/C/Flags.pm";
}

# generate lib/B/Asmdata.pm beforehand
# my $X = $^X =~ / / ? qq("$^X") : $^X;
if ($core) {
    system($^X,"-I../../lib/auto","-I../../lib","bytecode.pl");
} else {
    system($^X, "bytecode.pl");
}

my ($use_declare_independent_comalloc, $extra_cflags, $extra_libs) = (0, "", "");
my $have_independent_comalloc = check_independent_comalloc();
if (grep { $_ eq 'INSTALL_PTMALLOC3' } @ARGV) {
    install_independent_comalloc() ;
    $have_independent_comalloc = check_independent_comalloc();
}
{
    my ($e_c) = grep { /-extra-cflags[= ](.+)/ } @ARGV;
    my ($e_l) = grep { /-extra-libs[= ](.+)/ } @ARGV;
    $extra_cflags .= " $e_c" if $e_c;
    $extra_libs .= " $e_l" if $e_l;
}
# cygwin still has the old gdb-6 debugger which does not understand dwarf4 features from gcc-4.5
#if ($Config{gccversion} =~ /^4\.[56]\./) {
#    my $gdb_ver = `gdb --version`;
#    if ($gdb_ver =~ /gdb 6\./) {
#        print "Adding extra_cflags=-gstrict-dwarf for gcc-4.5 for a gdb-6 debugger which does not understand dwarf4 features\n";
#        $extra_cflags .= " -gstrict-dwarf";
#    }
#}
sub write_b_c_flags {
    my $version = shift;
    mkdir "lib/B/C" unless -d "lib/B/C";
    open PH, ">", "lib/B/C/Flags.pm";
    print PH "# written by B::C Makefile.PL. \$extra_{cflags,libs} need a leading space if used.\n";
    print PH "package B::C::Flags;\n\n";
    my $devnull = $^O eq 'MSWin32' ? 'NUL' : '/dev/null';
    print PH "\$VERSION = '$version';\n";
    my $REV = '';
    if (my $sha1 = `git rev-list HEAD -1 --abbrev=7 --abbrev-commit 2>$devnull`) {
        chomp $sha1;
        # POSIX systems only with wc
        if (my $num = `git rev-list --abbrev-commit HEAD | wc -l 2>$devnull`) {
            chomp $num;
            $REV .= "-$num";
        }
        $REV .= '-g'.$sha1;
        print PH "\$B::C::REVISION = '$REV';\n\n";
    }
    print PH "# -fav-init optimization\n";
    print PH "\$have_independent_comalloc = $have_independent_comalloc;\n";
    print PH "\$use_declare_independent_comalloc = $use_declare_independent_comalloc;\n\n";
    print PH "# use extra compiler flags, after ccopts, resp. ldopts\n";
    print PH "\$extra_cflags = \"$extra_cflags\";\n";
    print PH "\$extra_libs = \"$extra_libs\";\n";
    print PH "\n1;\n";
    close PH;
    chmod 0644, "lib/B/C/Flags.pm";
}

# XXX Check for 5.16.0 B-1.34 and offer to patch it? rather use `perlall --patches=Compiler`
# Or not needed as we do not want to support utf8 and \0 in stashes there

if ($] > 5.017003) {
    unless (-d '.git' and `git symbolic-ref -q HEAD` eq "refs/heads/master\n") {
        die "Perl 5.18 PADLIST changes are currently not supported. You can try git master.\n";
    }
}

WriteMakefile(
    NAME	 => "B::C",
    VERSION_FROM => "lib/B/C.pm",
    PL_FILES   => { 'script/perlcc.PL'    => 'script/perlcc' },
    EXE_FILES  => [qw(script/perlcc script/cc_harness script/assemble script/disassemble)],
    PREREQ_PM  => {'Opcodes'  => '0',    # optional
		   'IPC::Run' => '0',    # optional
		   'B::Flags' => '0.04', # optional
		   'Time::HiRes' => '0', # optional
                   #'B'        => '1.0901' # required but in CORE
                  },
    'AUTHOR'   => 'Malcolm Beattie (retired), '
	      .   'Reini Urban <perl-compiler@googlegroups.com>',
    'ABSTRACT' => 'Perl compiler',
    'LICENSE'  => 'perl',
    (($ExtUtils::MakeMaker::VERSION gt '6.31' and $ExtUtils::MakeMaker::VERSION lt '6.46') ?
       ('EXTRA_META'  => "recommends:\n" .
        "    B::Flags:  0.04\n".
        "    B::Debug:  1.16\n".
        "    Opcodes:   0.10\n".
        "    IPC::Run:  0\n".
        "    Set::Object: 0\n".
        "    IO::Socket::SSL: 0\n"
       ) : ()),
    ($ExtUtils::MakeMaker::VERSION gt '6.46' ?
    ('META_MERGE'  => {"recommends" =>
                       {
                        'B::Flags' => '0.04',
                        "B::Debug" => '1.16',
                        "Opcodes"  => '0.10',
                        "IPC::Run" => 0,
			"Set::Object" => 0,
			"IO::Socket::SSL" => 0,
                       },
                       resources =>
                       {
                        license     => 'http://dev.perl.org/licenses/',
                        homepage    => 'http://www.perl-compiler.org',
                        bugtracker  => 'http://code.google.com/p/perl-compiler/issues',
                        repository  => 'http://perl-compiler.googlecode.com/',
                        MailingList => 'http://groups.google.com/group/perl-compiler',
                       },
                      }
    ) : ()),
    SIGN  => 1,
    clean => { FILES =>
               "bytecode[0-9]* ".
               "lib/B/Asmdata.pm script/perlcc ccode* cccode* Ccode* ".
 	       "*.core *.stackdump a.out a.exe *.cee *.c *.asm *.dbg *.plc *.obj ".
               "*.concise *~ dll.base dll.exp mod.pl pcc* *.bak *.a"
             },
);

sub headerpath {
    if ($core) {
	return File::Spec->catdir(File::Spec->updir,
				  File::Spec->updir);
    } else {
	return File::Spec->catdir($Config::Config{archlibexp}, "CORE");
    }
}

# Check for Doug Lea's dlmalloc version, or ptmalloc2 included in glibc
# or the best: ptmalloc3 with independent_comalloc().
# http://www.malloc.de/malloc/ptmalloc3-current.tar.gz
# This improves -fav-init startup speed dramatically (18% tested).
# ptmalloc3 needs #include <malloc-2.8.3.h>, but we don't want to clash
# with an existing malloc.h from perl.h, so we declare it by ourselves.
sub try_compile {
    my $testc = shift;
    my $libs = shift;
    # For consistency (without considering LD_PRELOAD) require perl to
    # be compiled with the same malloc library.
    return 0 unless $Config{libs} =~ /\b\Q$libs\E\b/;
    unless (open PROG, ">", "test.c") {
        print ("Can't write test.c\n");
        return 0;
    }
    print PROG $testc;
    close PROG;
    @candidate = ();
    $devnull = $^O eq 'MSWin32' ? "> NUL" : ">/dev/null 2>&1";
    my $cmd = "$Config{cc} $Config{ccflags} test.c";
    push @candidate, "$cmd -o test$Config{EXE_EXT} $libs $devnull";
    push @candidate, "$cmd -otest$Config{EXE_EXT} $libs $devnull";
    while (my $cmd1 = shift (@candidate)) {
	system ($cmd1);
	unlink "test.c", "test$Config{EXE_EXT}";
	$? == 0 && return 1;
    }
    return 0;
}

sub check_independent_comalloc {
    my $testori = "
#include <stdlib.h>
#include <malloc.h>
int main() {
    void* chunks[3];
    size_t sizes[3] = {3,25,4};
    if (independent_comalloc( 3, sizes, chunks ) == 0) { exit(1); };
    return 0;
}
";
    my $testc = $testori;
    if (try_compile($testc)) {
	warn "-fav-init2 available: independent_comalloc() as-is activated\n";
	return 1;
    }

    my @extra_libs = ("-lptmalloc3", "-lptmalloc", "-ldlmalloc", "-lnedmalloc");
    for my $lib (@extra_libs) {
        $lib =~ s/^-l(.+)$/lib$1.lib/ if $^O eq 'MSWin32';
        if (try_compile($testc, $lib)) {
            $extra_libs = " $lib";
	    warn "-fav-init2 available: independent_comalloc() with $lib activated\n";
            return 1;
        }
    }
    # try without the ptmalloc3 header, just the library
    $testc =~ s/#include <malloc>/void** dlindependent_comalloc(size_t, size_t*, void**);/;
    for (@extra_libs) {
	my $lib = $_;
        $lib = 'libptmalloc3.lib' if $^O eq 'MSWin32';
        $lib =~ s/^-l(.+)$/lib$1.lib/ if $^O eq 'MSWin32';
        if (try_compile($testc, $lib)) {
            $extra_libs = " $lib";
            $use_declare_independent_comalloc = 1;
	    warn "-fav-init2 available: dlindependent_comalloc() with $lib activated\n";
            return 1;
        }
    }
    # Desperate. External ptmalloc3 header to overcome -I path shadowing
    $testc = $testori;
    $testc =~ s/#include <malloc.h>/#include "malloc-2.8.3.h"/;
    my $lib = "-lptmalloc3";
    $lib = 'libptmalloc3.lib' if $^O eq 'MSWin32';
    if (try_compile($testc, $lib)) {
	$extra_cflags = " -DNEED_MALLOC_283";
	$extra_libs = " $lib";
	warn "-fav-init2 available: independent_comalloc() with -DNEED_MALLOC_283 $lib activated\n";
	return 1;
    }
    #warn "-fav-init2 not available, independent_comalloc() not detected.\n";
    #warn "  Install on POSIX systems with:\n";
    #warn "  $^X Makefile.PL INSTALL_PTMALLOC3\n\n";
    return 0;
}

sub _system{
    print join(" ",@_),"\n";
    local $!;
    system @_;
    croak $! if $!;
}

sub install_independent_comalloc {
    print "INSTALL_PTMALLOC3 from <http://www.malloc.de/en/index.html>\n";
    -f 'ptmalloc3-current.tar.gz'
      or _system(qw(wget http://www.malloc.de/malloc/ptmalloc3-current.tar.gz));
    -d 'ptmalloc3'
      or _system('tar xfz ptmalloc3-current.tar.gz');
    chdir "ptmalloc3" or die;
    if ($Config{useithreads}) { 
	# linux-pthread is basically the same. linux-shared is also an option.
	# just Solaris, SGI and HPUX need different options.
	_system(qw(make posix));
    } else {
	_system(qw(make nothreads));
    }
    _system('make check');
    _system('sudo cp libptmalloc3.a /usr/lib/');
    warn "No you must recompile your perl with linking to this library\n";
    chdir "..";
}

package MY;

sub libscan {
    # Ignore temp testing files
    return 0 if $_[1] =~ /^(\.git|\.svn|jit.*|i386|.*\.orig|bytecode.*\.pl|c?ccode.*|regen_lib\.pl)$/;
    return 0 if $_[1] =~ /\.svn|~/; # needed for msys perl5.6
    # Ignore Bytecode on 5.6 for now. The 5.6 CORE module produces better code (until fixed :)
    # Not even the Byteloader works for 5.6 assembled code. The Disassembler does not stop at ret.
    return 0 if $] < 5.007 and $_[1] =~ /ByteLoader|Asmdata\.pm|Bytecode\.pm|Assembler\.pm/;
    return $_[1];
}


# Fix ActivePerl for MSVC6
# The linker for cl 12.0.8804 has no -opt:ref,icf, which is MSVC8 linker syntax.
sub const_config {
    my $s = shift->SUPER::const_config(@_);
    if ($Config::Config{ccversion} eq '12.0.8804' and $Config::Config{cc} eq 'cl') {
	$s =~ s/ -opt:ref,icf//gm;
    }
    $s
}

sub post_constants {
    my $mm = shift;
    main::write_b_c_flags($mm->{VERSION});
    my $libs = "\nLIBS = $Config::Config{libs}";
    $libs .= $extra_libs if $extra_libs;
    #XXX PERL_MALLOC_DEF = -DPERL_EXTMALLOC_DEF -Dmalloc=Perl_malloc -Dfree=Perl_mfree -Drealloc=Perl_realloc -Dcalloc=Perl_calloc
    return "$libs\n";
}

sub ccflags {
    my $ccflags = shift->SUPER::ccflags(@_);
    $ccflags .= " -DHAVE_INDEPENDENT_COMALLOC" if $have_independent_comalloc;
    $ccflags .= $extra_cflags if $extra_cflags;
    return $ccflags unless -d ".svn" or -d ".git";
    # Recommended by http://www.network-theory.co.uk/docs/gccintro/gccintro_32.html
    # -ansi -pedantic -Wall -W -Wconversion -Wshadow -Wcast-qual -Wwrite-strings (-W => -WExtra)
    $ccflags .= " -ansi -pedantic -Wall -Wextra -Wconversion -Wshadow -Wcast-qual -Wwrite-strings"
      if $Config{cc} =~ /gcc/;
}

sub depend {
    my $headerpath = main::headerpath();
    my @headers = map { File::Spec->catfile($headerpath, $_) } qw(op.h cop.h sv.h);
    my $asmdata = File::Spec->catfile('lib', 'B', 'Asmdata.pm');
    my $byterun_c = File::Spec->catfile('ByteLoader', 'byterun.c');
    my $byterun_h = File::Spec->catfile('ByteLoader', 'byterun.h');
    my $cc_runtime_h = File::Spec->catfile($headerpath, 'cc_runtime.h');
    my $result = "
$asmdata : Makefile bytecode.pl @headers
	\$(PERL) bytecode.pl

$byterun_c : Makefile bytecode.pl @headers
	\$(PERL) bytecode.pl

$byterun_h : Makefile bytecode.pl @headers
	\$(PERL) bytecode.pl

TAGS : $asmdata
	etags --language=perl lib/B/*.pm
";
    if ($] > 5.009) {
        $result .= "\ntest :: subdirs-test\n\n";
    }
    if ($Config{make} eq 'mingw32-make') { # mingw32 make different to msys make
        $result .= "\n.PHONY : \$(CONFIGDEP)\n\n";
    }
    $result;
}

sub install {
    my $result = shift->SUPER::install(@_);
    if ($] > 5.013007 and !-e File::Spec->catfile($headerpath, 'cc_runtime.h')) {
        $result =~ s/install :: pure_install doc_install/install :: pure_install doc_install ccinc_install/;
	$result .= '
ccinc_install :: $(PERL_INC)/cc_runtime.h

$(PERL_INC)/cc_runtime.h : cc_runtime.h
	$(NOECHO) $(MOD_INSTALL) \
	    	read $(PERL_ARCHLIB)/auto/$(FULLEXT)/.packlist \
		write $(DESTINSTALLARCHLIB)/auto/$(FULLEXT)/.packlist \
		cc_runtime.h $@
';
    }
    $result
}

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
