use strict;

use Test::More;
use Webservice::InterMine;

my $do_live_tests = $ENV{RELEASE_TESTING};

unless ($do_live_tests) {
    plan( skip_all => "Acceptance tests for release testing only" );
} else {
    plan(tests => 4);
    my $service = get_service('localhost/intermine-test');
    my $widgets = $service->widgets;
    ok grep {$_->{name} eq 'contractor_enrichment'} @$widgets;
    ok grep {$_->{widgetType} eq 'enrichment'} @$widgets;

    my @widgets = $service->widgets;
    ok grep {$_->{name} eq 'contractor_enrichment'} @widgets;
    ok grep {$_->{widgetType} eq 'enrichment'} @widgets;
}

