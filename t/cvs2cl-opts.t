# (X)Emacs mode: -*- cperl -*-

use strict;

=head1 Unit Test Package for cvs2cl

This package tests the options functionality of cvs2cl

=cut

use File::Spec            qw( );
use FindBin               qw( $Bin );
use Test                  qw( ok plan );

BEGIN { unshift @INC, $Bin };

sub catfile { File::Spec->catfile(@_) }

use constant LOG_FILE     => 'Audio-WAV.log';
use constant CHECK_FILE_R => 'Audio-WAV-ChangeLog.-r';
use constant CHECK_FILE_B => 'Audio-WAV-ChangeLog.-b';
use constant CHECK_FILE_T => 'Audio-WAV-ChangeLog.-t';
use constant CVS2CL     => $ENV{CVS2CL} || ':cvs2cl';

use test                  qw( DATA_DIR );
use test2                 qw( -no-ipc-run simple_run_test );

BEGIN {
  #  1 for compilation test
  #  1 for runcheck
  #  1 for outputfile
  plan tests  => 10,
       todo   => [],
       ;
}

# ----------------------------------------------------------------------------

=head2 Test 1: compilation

This test confirms that the test script and the modules it calls compiled
successfully.

=cut

# No modules imported

ok 1, 1, 'compilation';

printf STDERR "Using CVS2CL: %s\n", CVS2CL
  if $ENV{TEST_DEBUG};

# -------------------------------------

=head2 Test 2: runcheck

This tests that the invocation of cvs2cl ran without error (exit status
0).

The invocation is run as

  cvs2cl --stdin --stdout -r < data/Audio-WAV.log \
    > Audio-WAV-ChangeLog.-r

=head2 Test 3: outputcheck

This tests that the output of cvs2cl matches what is expected

=head2 Test 4: no extra files

This tests that only the expected output files (Audio-WAV-ChangeLog.vanilla)
are present.

=cut

{
  my $err = '';
  simple_run_test
    ( runargs => [[CVS2CL, '-r', '--stdin', '--stdout'],
                  '<', catfile(DATA_DIR, LOG_FILE),
                  '>', CHECK_FILE_R, '2>', \$err],
      name    => 'cvs2cl -r',
      errref  => \$err,
      checkfiles => [ CHECK_FILE_R ],
    );
}

# -------------------------------------

=head2 Test 5: runcheck

This tests that the invocation of cvs2cl ran without error (exit status
0).

The invocation is run as

  cvs2cl --stdin --stdout -b < data/Audio-WAV.log \
    > Audio-WAV-ChangeLog.-b

=head2 Test 6: outputcheck

This tests that the output of cvs2cl matches what is expected

=head2 Test 7: no extra files

This tests that only the expected output files (Audio-WAV-ChangeLog.vanilla)
are present.

=cut

{
  my $err = '';
  simple_run_test
    ( runargs => [[CVS2CL, '-b', '--stdin', '--stdout'],
                  '<', catfile(DATA_DIR, LOG_FILE),
                  '>', CHECK_FILE_B, '2>', \$err],
      name    => 'cvs2cl -b',
      errref  => \$err,
      checkfiles => [ CHECK_FILE_B ],
    );
}

# -------------------------------------

=head2 Test 8: runcheck

This tests that the invocation of cvs2cl ran without error (exit status
0).

The invocation is run as

  cvs2cl --stdin --stdout -t < data/Audio-WAV.log \
    > Audio-WAV-ChangeLog.-t

=head2 Test 9: outputcheck

This tests that the output of cvs2cl matches what is expected

=head2 Test 10: no extra files

This tests that only the expected output files (Audio-WAV-ChangeLog.vanilla)
are present.

=cut

{
  my $err = '';
  simple_run_test
    ( runargs => [[CVS2CL, '-t', '--stdin', '--stdout'],
                  '<', catfile(DATA_DIR, LOG_FILE),
                  '>', CHECK_FILE_T, '2>', \$err],
      name    => 'cvs2cl -t',
      errref  => \$err,
      checkfiles => [ CHECK_FILE_T ],
    );
}

# ----------------------------------------------------------------------------
