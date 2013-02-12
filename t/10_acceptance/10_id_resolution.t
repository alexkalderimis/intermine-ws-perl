use strict;

use Test::More;
use Test::Exception;
use Webservice::InterMine;

my $do_live_tests = $ENV{RELEASE_TESTING};

unless ($do_live_tests) {
    plan( skip_all => "Acceptance tests for release testing only" );
} else {
    plan(tests => 3);
    my $url = $ENV{TESTMODEL_URL} || 'http://localhost:8080/intermine-test/service';
    note("Testing against $url");

    my $service = get_service($url, "test-user-token");
    my $job = $service->resolve_ids(
        identifiers => [qw/Anne Brenda Carol/],
        type => 'Employee',
        #extra => ''
    );

    ok($job, "A job has been made");

    $job->poll until ($job->completed);

    my $results = $job->results;

    is(~~@{[keys %$results]}, 3, "Found three things");

    $job->delete();

    throws_ok(
        sub { $job->fetch_results },
        qr/not found/i,
        "Job has been deleted"
    );
}
