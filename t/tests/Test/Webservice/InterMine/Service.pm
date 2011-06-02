package Test::Webservice::InterMine::Service;

#TODO - add tests for apply role, and new_query

use strict;
use warnings;
use base 'Test::Class';
use Test::More;
use Test::Exception;
use Test::MockObject;
use InterMine::Model::TestModel;

sub class         { 'Webservice::InterMine::Service' }
sub fake_queryurl { 'fake.url/path' }
sub fake_viewlist { [qw/one two three/] }
sub user_agent    { 'WebserviceInterMinePerlAPIClient' }

sub object {
    my $test = shift;
    return $test->{object};
}

sub setup : Test(setup) {
    my $test = shift;

    # Set up all the mock stuff

    my $model = InterMine::Model::TestModel->instance;
    $test->{model} = $model;

    my $fake_query = Test::MockObject->new;
    $fake_query->fake_module( 'Webservice::InterMine::Query', new => sub { }, );
    $test->{fq} = $fake_query;
    my $connection = Test::MockObject->new;
    $connection->fake_module(
        'Net::HTTP',
        new => sub {
            my $class = shift;
            my @args  = @_;
            $connection->{_init_args} = {@args};
            return $connection;
        },
    );
    $connection->mock(
        write_request => sub {
            my $self = shift;
            my @args = @_;
            $self->{_write_args} = {@args};
            return $self;
        },
    );
    $test->{connection} = $connection;
    $test->{version}    = 1_000_000;
    $test->{release}    = 'SOME RELEASE STRING';
    $test->{listdata}    = 'SOME LIST DATA';

    my $fakeRes = Test::MockObject->new;
    $fakeRes->fake_module(
        'Webservice::InterMine::ResultIterator',
        new => sub {
            my $class = shift;
            my @args  = @_;
            $fakeRes->{_init_args} = {@args};
            return $fakeRes;
        },
    );
    $fakeRes->mock( status_line => sub { "Hello, I'm a status line" } )->mock(
        content => sub {
            my $self = shift;
            return $self->{_content};
        },
    );
    $fakeRes->set_false('is_error')->mock( code => sub { 'FAKE_CODE' } )
      ->mock( message => sub { 'FAKE_MESSAGE' } );
    $test->{Res} = $fakeRes;

    my $fakeLWP = Test::MockObject->new();
    $fakeLWP->{get_count} = 0;
    $fakeLWP->fake_module( 'LWP::UserAgent', new => sub { return $fakeLWP }, );
    $fakeLWP->set_isa('LWP::UserAgent');
    $fakeLWP->mock( env_proxy => sub { } )->mock(
        agent => sub {
            my $self         = shift;
            my $agent_string = shift;
            $self->{agent} = $agent_string;
        }
      )->mock(
        get => sub {
            my ( $self, $uri ) = @_;
            $self->{get_count}++;
            my $url = "$uri";
            if ( $url =~ m!/model! ) {
                $fakeRes->{_content} = $model;
            }
            elsif ( $url =~ m!/lists! ) {
                $fakeRes->{_content} = $test->{listdata};
            }
            elsif ( $url =~ m!/release! ) {
                $fakeRes->{_content} = $test->{release};
            }
            elsif ( $url =~ m!/version! ) {
                $fakeRes->{_content} = $test->{version};
            }
            else {
                $fakeRes->{_content} .= $url;
            }
            return $fakeRes;
        }
      )->mock(
        default_header => sub {
            my ($self, @header)  = @_;
            $self->{header} = \@header;
        }
    );
    $test->{LWP} = $fakeLWP;

    my $fake_TemplateFactory = Test::MockObject->new;
    $fake_TemplateFactory->fake_module(
        'Webservice::InterMine::TemplateFactory',
        new => sub {
            return $fake_TemplateFactory;
        },
    );
    $fake_TemplateFactory->set_isa('Webservice::InterMine::TemplateFactory');
    $fake_TemplateFactory->mock(
        get_template_by_name => sub {
            my $self = shift;
            my $name = shift;
            return "Mock Template Result - $name";
        },
    )->mock(get_templates => sub {"Many Templates"});
    $test->{TF} = $fake_TemplateFactory;

    my $fake_ListFactory = Test::MockObject->new;
    $fake_TemplateFactory->fake_module(
        'Webservice::InterMine::ListFactory',
        new => sub {
            return $fake_ListFactory;
        },
    );
    $fake_ListFactory->set_isa('Webservice::InterMine::ListFactory');
    $test->{LF} = $fake_ListFactory;
}

sub _compilation : Test(1)  {
    my $test = shift;
    use_ok( $test->class );
}

sub basic_service : Test(3) {
    my $test = shift;
    my @args = ( root => $test->fake_queryurl );
    my $service = new_ok( $test->class, [@args] );
    is( $service->version, $test->{version}, "It gets its version ok" );

    is($service->get_authstring, undef, "No user, no authentication");

}

sub auth_service : Test(2) {
    my $test = shift;
    my @args = ( root => $test->fake_queryurl, user => 'Foo', pass => 'Bar' );
    my $service = new_ok( $test->class, [@args] );
    isnt($service->get_authstring, undef, "With a user, there is authentication");
}
    

sub bad_services : Test(3) {
    my $test = shift;
    my @args = ( root => $test->fake_queryurl );

    throws_ok {$test->class->new(@args, user => "Foo")} qr/not both/, 
        "demands a password for a user";

    throws_ok {$test->class->new(@args, pass => "Foo")} qr/not both/, 
        "demands a user for a password";

    $test->{version} = 0;
    throws_ok {$test->class->new(@args)} qr/check the url/, 
        "Throws a sensible error when it can't get the version";
}

sub release : Test(2) {
    my $test = shift;
    my @args = ( root => $test->fake_queryurl );
    my $service = $test->class->new(@args);
    my $c = $test->{LWP}->{get_count};
    is($service->release, $test->{release}, "Can get the release string");
    is($test->{LWP}->{get_count}, $c + 1, "Was fetched lazily");
}

sub templates : Test(2) {
    my $test = shift;
    my @args = ( root => $test->fake_queryurl );
    my $service = $test->class->new(@args);
    is($service->template('Foo'), "Mock Template Result - Foo", 
        "Can delegate template fetching");
    is($service->get_templates, "Many Templates", 
        "Can delegate fetching of all templates");
}

sub list_methods : Test(3) {
    my $test = shift;
    my @args = ( root => $test->fake_queryurl );
    my $service = $test->class->new(@args);
    can_ok($service, qw/list lists lists_with_object list_names new_list 
        join_lists subtract_lists intersect_lists diff_lists delete_lists 
        delete_temp_lists list_count refresh_lists/);
    is($service->get_list_data, $test->{listdata}, "Can fetch list data");

    $test->{version} = 3;
    $service = $test->class->new(@args);
    throws_ok {$service->get_list_data} qr/not support list operations/, 
        "Informs the user if the webservice cannot handle lists";
    
}

    

1;
