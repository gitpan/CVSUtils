# (X)Emacs mode: -*- cperl -*-

package test;

=head1 NAME

test - tools for helping in test suites (not including running external programs).

=head1 SYNOPSIS

  use FindBin               1.42 qw( $Bin );
  use Test                  1.13 qw( ok plan );

  BEGIN { unshift @INC, $Bin };

  use test                  qw( DATA_DIR
                                evcheck runcheck );

  BEGIN {
    plan tests  => 3,
         todo   => [],
         ;
  }

  ok evcheck(sub {
               open my $fh, '>', 'foo';
               print $fh "$_\n"
                 for 'Bulgaria', 'Cholet';
               close $fh;
             }, 'write foo'), 1, 'write foo';

  save_output('stderr', *STDERR{IO});
  warn 'Hello, Mum!';
  print restore_output('stderr');

=head1 DESCRIPTION

This package provides some variables, and sets up an environment, for test
scripts, such as those used in F<t/>.

This package does not including running external programs; that is provided by
C<test2.pm>.  This is so that suites not needing that can include only
test.pm, and so not require the presence of C<IPC::Run>.

Setting up the environment includes:

=over 4

=item Pushing the module F<lib/> dir onto the @PERL5LIB var

For executed scripts.

=item Pushing the module F<lib/> dir onto the @INC var

For internal C<use> calls.

=item Changing directory to a temporary directory

To avoid cluttering the local dir, and/or allowing the local directory
structure to affect matters.

=item Cleaning up the temporary directory afterwards

Unless TEST_DEBUG is set in the environment.

=back

=cut

# ----------------------------------------------------------------------------

# Pragmas -----------------------------

use 5.00503;
use strict;
use vars qw( @EXPORT_OK );

# Inheritance -------------------------

use base qw( Exporter );

=head2 EXPORTS

The following symbols are exported upon request:

=over 4

=item BIN_DIR

=item DATA_DIR

=item REF_DIR

=item LIB_DIR

=item check_req

=item compare

=item evcheck

=item only_files

=item save_output

=item restore_output

=item tmpnam

=item tempdir

=back

=cut

@EXPORT_OK = qw( BIN_DIR DATA_DIR REF_DIR LIB_DIR
                 check_req compare evcheck only_files
                 save_output restore_output tempdir tmpnam );

# Utility -----------------------------

use Carp                          qw( carp croak );
use Cwd                      2.01 qw( cwd );
use Env                           qw( PERL5LIB );
use Fatal                    1.02 qw( close open seek sysopen unlink );
use Fcntl                    1.03 qw( :DEFAULT );
use File::Compare          1.1002 qw( );
use File::Path             1.0401 qw( mkpath rmtree );
use File::Spec                0.6 qw( );
use FindBin                  1.42 qw( $Bin );
use POSIX                    1.02 qw( );
use Test                    1.122 qw( ok skip );

# ----------------------------------------------------------------------------

sub rel2abs {
  if ( File::Spec->file_name_is_absolute($_[0]) ) {
    return $_[0];
  } else {
    return catdir(cwd, $_[0]);
  }
}

sub catdir {
  File::Spec->catdir(@_);
}

sub catfile {
  File::Spec->catfile(@_);
}

sub updir {
  File::Spec->updir(@_);
}

# -------------------------------------
# PACKAGE CONSTANTS
# -------------------------------------

use constant BIN_DIR  => catdir $Bin, updir, 'bin';
use constant DATA_DIR => catdir $Bin, updir, 'data';
use constant REF_DIR  => catdir $Bin, updir, 'testref';
use constant LIB_DIR  => catdir $Bin, updir, 'lib';

# -------------------------------------
# PACKAGE ACTIONS
# -------------------------------------

# @PERL5LIB not available in Env for perl 5.00503
# unshift @PERL5LIB, LIB_DIR;
$PERL5LIB = join ':', LIB_DIR, $PERL5LIB;
unshift @INC,      LIB_DIR;

$_ = rel2abs($_)
  for @INC;

my $tmpdn = tempdir();
$| = 1;

mkpath $tmpdn;
die "Couldn't create temp dir: $tmpdn: $!\n"
  unless -r $tmpdn and -w $tmpdn and -x $tmpdn and -o $tmpdn and -d $tmpdn;

#@INC = map rel2abs($_), @INC;
chdir $tmpdn;

# -------------------------------------
# PACKAGE FUNCTIONS
# -------------------------------------

=head2 only_files

=over 4

=item ARGUMENTS

=over 4

=item expect

Arrayref of names of files to expect to exist.

=back

=item RETURNS

=over 4

=item ok

1 if exactly expected files exist, false otherwise.

=back

=back

=cut

sub only_files {
  my ($expect) = @_;

  local *MYDIR;
  opendir MYDIR, '.';
  my %files = map { $_ => 1 } readdir MYDIR;
  closedir MYDIR;

  my $ok = 1;

  for (@$expect, '.', '..') {
    if ( exists $files{$_} ) {
      delete $files{$_};
    } elsif ( ! -e $_ ) { # $_ might be absolute
      carp "File not found: $_\n"
        if $ENV{TEST_DEBUG};
      $ok = 0;
    }
  }

  for (keys %files) {
    carp "Extra file found: $_\n"
      if $ENV{TEST_DEBUG};
    $ok = 0;
  }

  if ( $ok ) {
    return 1;
  } else {
    return;
  }
}

# -------------------------------------

=head2 evcheck

Eval code, return status

=over 4

=item ARGUMENTS

=over 4

=item code

Coderef to eval

=item name

Name to use in error messages

=back

=item RETURNS

=over 4

=item okay

1 if eval was okay, 0 if not.

=back

=back

=cut

sub evcheck {
  my ($code, $name) = @_;

  my $ok = 0;

  eval {
    &$code;
    $ok = 1;
  }; if ( $@ ) {
    carp "Code $name failed: $@\n"
      if $ENV{TEST_DEBUG};
    $ok = 0;
  }

  return $ok;
}

# -------------------------------------

=head2 save_output

Redirect a filehandle to temporary storage for later examination.

=over 4

=item ARGUMENTS

=over 4

=item name

Name to store as (used in L<restore_output>)

=item filehandle

The filehandle to save

=back

=cut

# Map from names to saved filehandles.

# Values are arrayrefs, being filehandle that was saved (to restore), the
# filehandle being printed to in the meantime, and the original filehandle.
# This may be treated as a stack; to allow multiple saves... push & pop this
# stack.

my %grabs;

sub save_output {
  croak sprintf("%s takes 2 arguments\n", (caller 0)[3])
    unless @_ == 2;
  my ($name, $filehandle) = @_;

  my $tmpnam = POSIX::tmpnam;
  sysopen my $tmpfh, $tmpnam, O_RDWR | O_CREAT | O_EXCL;
  unlink $tmpnam;
  select((select($tmpfh), $| = 1)[0]);

  open my $savefh, '>&' . fileno $filehandle
    or die "can't dup $name: $!";
  open $filehandle, '>&' . fileno $tmpfh
    or die "can't open $name to tempfile: $!";

  push @{$grabs{$name}}, $savefh, $tmpfh, $filehandle;
}

# -------------------------------------

=head2 restore_output

Restore a saved filehandle to its original state, return the saved output.

=over 4

=item ARGUMENTS

=over 4

=item name

Name of the filehandle to restore (as passed to L<save_output>).

=back

=item RETURNS

=over 4

=item saved_string

A single string being the output saved.

=back

=cut

sub restore_output {
  my ($name) = @_;

  croak "$name has not been saved\n"
    unless exists $grabs{$name};
  croak "All saved instances of $name have been restored\n"
    unless @{$grabs{$name}};
  my ($savefh, $tmpfh, $origfh) = splice @{$grabs{$name}}, -3;

  close $origfh
    or die "cannot close $name opened to tempfile: $!";
  open  $origfh, '>&' . fileno $savefh
    or die "cannot dup $name back again: $!";

  seek $tmpfh, 0, 0;
  local $/ = undef;
  my $string = <$tmpfh>;
  close $tmpfh;

  return $string;
}

sub _test_save_restore_output {
  warn "to stderr 1\n";
  save_output("stderr", *STDERR{IO});
  warn "Hello, Mum!";
  print 'SAVED:->:', restore_output("stderr"), ":<-\n";
  warn "to stderr 2\n";
}

# -------------------------------------

=head2 tmpnam

Very much like the one in L<POSIX> or L<File::Temp>, but does not get deleted
if TEST_DEBUG has SAVE in the value.

=over 4

=item ARGUMENTS

=over 4

=item name

I<Optional>.  If defined, a name by which to refer to the tmpfile in user
messages.

=back

=item RETURNS

=over 4

=item filename

Name of temporary file.

=item fh

Open filehandle to temp file, in r/w mode.  Only created & returned in list
context.

=back

=back

=cut

my @tmpfns;
sub tmpnam {
  my $tmpnam = POSIX::tmpnam;

  if (@_) {
    push @tmpfns, [ $tmpnam, $_[0] ];
  } else {
    push @tmpfns, $tmpnam;
  }

  if (wantarray) {
    sysopen my $tmpfh, $tmpnam, O_RDWR | O_CREAT | O_EXCL;
    return $tmpnam, $tmpfh;
  } else {
    return $tmpnam;
  }
}

END {
  if ( defined $ENV{TEST_DEBUG} and $ENV{TEST_DEBUG} =~ /\bSAVE\b/ ) {
    for (@tmpfns) {
      if ( ref $_ ) {
        printf "Used temp file: %s (%s)\n", @$_;
      } else {
        print "Used temp file: $_\n";
      }
    }
  } else {
    unlink map((ref $_ ? $_->[0] : $_), @tmpfns)
      if @tmpfns;
  }
}

# -------------------------------------

=head2 tempdir

Very much like the one in L<POSIX> or L<File::Temp>, but does not get deleted
if TEST_DEBUG has SAVE in the value (does get deleted otherwise).

=over 4

=item ARGUMENTS

I<None>

=item RETURNS

=over 4

=item name

Name of temporary dir.

=back

=back

=cut

my @tmpdirs;
sub tempdir {
  my $tempdir = POSIX::tmpnam;
  mkdir $tempdir, 0700
    or die "Failed to create temporary directory $tempdir: $!\n";

  if (@_) {
    push @tmpdirs, [ $tempdir, $_[0] ];
  } else {
    push @tmpdirs, $tempdir;
  }

  return $tempdir;
}

END {
  for (@tmpdirs) {
    if ( ref $_ ) {
      if ( defined $ENV{TEST_DEBUG} and $ENV{TEST_DEBUG} =~ /\bSAVE\b/ ) {
        printf "Used temp dir: %s (%s)\n", @$_;
      } else {
        rmtree $_->[0];
      }
    } else {
      if ( defined $ENV{TEST_DEBUG} and $ENV{TEST_DEBUG} =~ /\bSAVE\b/ ) {
        print "Used temp dir: $_\n";
      } else {
        rmtree $_;
      }
    }
  }
}

# -------------------------------------

=head2 compare

  ok compare($fn1, $fn2), 1, 'test name';

Compare two files, return 1 if they are the same, 0 if they differ, -1 if file
cannot be read, -2 if file 2 cannot be read, -4 if both cannot be read.  -8
for a usage error.

In TEST_DEBUG mode, if the files do not compare, outputs file info on STDERR.

=cut

sub compare {
  my ($fn1, $fn2) = @_;

  for ( grep ! defined, $fn1, $fn2 ) {
    carp "Usage: compare($fn1, $fn2)\n"
        if $ENV{TEST_DEBUG};
    return -8;
  }

  {
    my $err = 0;

    for (0..1) {
      my $fn = ($fn1, $fn2)[$_];
      if ( ! -e $fn ) {
        carp "Does not exist: $fn\n"
          if $ENV{TEST_DEBUG};
        $err |= 2 ** $_;
      } elsif ( ! -r $fn ) {
        carp "Cannot read: $fn\n"
          if $ENV{TEST_DEBUG};
        $err |= 2 ** $_;
      }
    }

    return -$err
      if $err;
  }

  return 1
    unless File::Compare::compare($fn1, $fn2);

  if ( $ENV{TEST_DEBUG} ) {
    my $pid = fork;
    die "Fork failed: $!\n"
      unless defined $pid;

    if ( $pid ) { # Parent
      my $waitpid = waitpid($pid, 0);
      die "Waitpid got: $waitpid (expected $pid)\n"
        unless $waitpid == $pid;
    } else { # Child
      open *STDOUT{IO}, ">&" . fileno STDERR;
      exec qw(ls -l), $fn1, $fn2;
    }

    my $fh1 = IO::File->new($fn1, O_RDONLY)
      or die "$fn1: $!\n";
    my $fh2 = IO::File->new($fn2, O_RDONLY)
      or die "$fn2: $!\n";

    local $/ = "\n";

    my $found = 0;
    while ( ! $found and my $line1 = <$fh1> ) {
      my $line2 = <$fh2>;
      if ( ! defined $line2 ) {
        print STDERR "$fn2 ended at line: $.\n";
        $found = 1;
      } elsif ( $line2 ne $line1 ) {
        print STDERR
          "Difference at line $.:\n-1->$line1<---\n-2->$line2<---\n-";
        $found = 1;
      }
    }

    if ( ! $found ) {
      my $line2 = <$fh2>;
      if ( defined $line2 ) {
        print STDERR "$fn1 ended before line: $.\n";
      } else {
        print STDERR "Difference between $fn1, $fn2 not found!\n";
      }
    }

    close $fh1;
    close $fh2;
  }

  return 0;
}

# -------------------------------------

=head2 check_req

Perform a requisite check on a given executable.  This will skip if the
required modules are not present.

4+(n+m)*2 tests are performed, where n is the number of prerequisites
expected, and m is the number of outputs expected.

=over 4

=item SYNOPSIS

  check_req('ccu-touch',
            ['/etc/passwd'],
            [[REQ_FILE, '/etc/passwd']],
            [[REQ_FILE, 'passwd.foo']],
            'requisites 1');


=item ARGUMENTS

=over 4

=item cmd_name

The name of the command to run.  It is assumed that this command is in
blib/script; hence it should be an executable in this package, and C<make>
shuold have been run recently.

=item args

The arguments to pass to the cmd_name, as an arrayref.

=item epres

The expected prerequisites, as an arrayref, wherein every member is a
two-element arrayref, the members being the requisite type, and the requisite
value.

=item eouts

The expected outputs, in the same format as the L<epres|"epres">.

=item testname

The name to use in error messages.

=back

=back

=cut

sub check_req {
  my ($cmd_name, $args, $epres, $eouts, $testname) = @_;

  eval "use Pipeline::DataFlow 1.03 qw( :req_types );";
  my $skip;
  if ( $@ ) {
    print STDERR "$@\n"
      if $ENV{TEST_DEBUG};
    $skip = 'Skipped: Pipeline::DataFlow 1.03 not found';
  } else {
    $skip = 0;
  }

  my $count = 1;
  my $test = sub {
    my ($code, $expect) = @_;
    my $name = sprintf "%s (%2d)", $testname, $count++;
    my $value = UNIVERSAL::isa($code, 'CODE') ? $code->($name) : $code;
    skip $skip, $value, $expect, $name;
  };

  # Initialize nicely to cope when read_reqs fails
  my ($pres, $outs) = ([], []);

  $test->(sub {
            evcheck(sub {
                      ($pres, $outs) = Pipeline::DataFlow->read_reqs
                        ([catfile($Bin, updir, 'blib', 'script', $cmd_name),
                          @$args]);
                    }, $_[0]),},
          1);

  $test->(scalar @$pres, scalar @$epres);

  my (@epres, @pres);
  @epres = sort { $a->[1] cmp $b->[1] } @$epres;
  @pres =  sort { $a->[1] cmp $b->[1] } @$pres;

  for (my $i = 0; $i < @epres; $i++) {
    my ($type, $value) = @{$epres[$i]};
    $test->($type,  @pres > $i ? $pres[$i]->[0] : undef);
    $test->($value, @pres > $i ? $pres[$i]->[1] : undef);
  }

  $test->(scalar @$outs, scalar @$eouts);

  my (@eouts, @outs);
  @eouts = sort { $a->[1] cmp $b->[1] } @$eouts;
  @outs =  sort { $a->[1] cmp $b->[1] } @$outs;

  for (my $i = 0; $i < @eouts; $i++) {
    my ($type, $value) = @{$eouts[$i]};
    $test->($type,  @outs > $i ? $outs[$i]->[0] : undef);
    $test->($value, @outs > $i ? $outs[$i]->[1] : undef);
  }

  $test->(only_files([]), 1);
}

# ----------------------------------------------------------------------------

=head1 EXAMPLES

Z<>

=head1 BUGS

Z<>

=head1 REPORTING BUGS

Email the author.

=head1 AUTHOR

Martyn J. Pearce C<fluffy@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2001, 2002 Martyn J. Pearce.  This program is free software; you
can redistribute it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

Z<>

=cut

1; # keep require happy.

__END__
