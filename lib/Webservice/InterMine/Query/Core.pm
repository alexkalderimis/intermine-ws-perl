package Webservice::InterMine::Query::Core;

use Moose;
with(
    'Webservice::InterMine::Role::ModelOwner',
    'Webservice::InterMine::Role::Named',
    'Webservice::InterMine::Role::Described',
);

use Carp;
use List::Util qw/reduce/;
use List::MoreUtils qw/uniq/;

use MooseX::Types::Moose qw/Str Bool/;
use InterMine::Model::Types qw/PathList PathHash PathString/;
use Webservice::InterMine::Types qw(
  SortOrder SortOrderList
  ConstraintList LogicOrStr JoinList
  QueryName PathDescriptionList
  ConstraintFactory
);

use Webservice::InterMine::Join;
use Webservice::InterMine::PathDescription;
use Webservice::InterMine::Path qw(:validate type_of);
use Webservice::InterMine::SortOrder;
use Exporter 'import';

our @EXPORT_OK = qw(AND OR);

######### ATTRIBUTES
has '+name' => ( 
    isa => QueryName, 
    coerce => 1,
);

has root_path => (
    init_arg  => 'class', 
    isa       => PathString, 
    is        => 'ro',
    coerce    => 1,
    predicate => 'has_root_path',
    trigger    => sub {
        my ($self, $root) = @_;
        my $err = validate_path( $self->model, $root, $self->type_dict );
        confess $err if $err;
    },
);

has _sort_order => (
    traits     => ['Array'],
    is         => 'ro',
    writer     => '_set_sort_order',
    isa        => SortOrderList,
    lazy_build => 1,
    coerce     => 1,
    predicate  => 'has_sort_order',
    trigger    => sub {
        my $self = shift;
        $self->_validate;
    },
    handles => {
        push_sort_order => 'push',
        sort_orders    => 'elements',
        joined_so      => 'join',
        clear_sort_order => 'clear',
        sort_order_is_empty =>  'is_empty',
    },
);

sub prefix_pathfeature {
    my ($self, $pf) = @_;
    if ($self->has_root_path) {
        my $root = $self->root_path;
        unless ($pf->path =~ /^$root/) {
            my $new_path = $self->root_path . '.' . $pf->path;
            $pf->set_path($new_path);
        }
    }
}

sub add_sort_order {
    my $self = shift;
    my @args = @_;
    my $so = Webservice::InterMine::SortOrder->new(@args);
    $self->prefix_pathfeature($so);
    $self->push_sort_order($so);
}

sub sort_order {
    my $self = shift;
    confess "You can't use this method to modify this attribute"
        if shift;
    if (grep {not defined} $self->sort_orders) {
        return '';
    } else {
        return $self->joined_so(' ');
    } 
}

sub DEMOLISH {
    my $self = shift;
    $self->suspend_validation;
}

sub _build__sort_order {
    my $self = shift;
    return $self->get_view(0);
}

sub set_sort_order {
    my $self = shift;
    $self->_set_sort_order( join( ' ', @_ ) );
}

sub table_format {
    my $self = shift;
    my $format = "%-24s" x $self->view_size;
    return $format . "\n";
}

has view => (
    traits  => ['Array'],
    is      => 'ro',
    isa     => PathList,
    default => sub { [] },
    coerce  => 1,
    lazy    => 1,
    writer  => '_set_view',
    handles => {
        views         => 'elements',
        _add_views    => 'push',
        get_view      => 'get',
        joined_view   => 'join',
        view_is_empty => 'is_empty',
        clear_view    => 'clear',
        view_size     => 'count',
    },
);

sub add_views {
    my $self = shift;
    return $self->add_view(@_);
}

sub add_view {
    my $self = shift;
    my @views = map {split} @_;
    if (my $root = $self->root_path) {
        @views = map {(/^$root/) ? $_ : "$root.$_"} @views;
    }
    my @expanded_views;
    for my $view (@views) {
        if ($view =~ /(.*)\.\*$/) {
            my $path = $1;
            my $cd = $self->model->get_classdescriptor_by_name(type_of($self->model, $path));
            my @expanded = map { $path . '.' . $_->name } sort $cd->attributes;
            push @expanded_views, @expanded;
        } else {
            push @expanded_views, $view;
        }
    }
    $self->_add_views(@expanded_views);
}

after qr/^add_/ => sub {
    my $self = shift;
    $self->_validate;
};

has constraints => (
    traits     => ['Array'],
    is         => 'ro',
    isa        => ConstraintList,
    default    => sub { [] },
    auto_deref => 1,
    handles    => {
        all_constraints   => 'elements',
        push_constraint   => 'push',
        find_constraints  => 'grep',
        map_constraints   => 'map',
        delete_constraint => 'delete',
        count_constraints => 'count',
        clear_constraints => 'clear',
    },
);

sub get_constraint {
    my $self = shift;
    my $code = shift;
    confess "get_constraint needs one argument - "
      . "the code of the constraint you want - "
      . "and it must be one or two alphabetic characters"
      unless ( $code and $code =~ /^[A-Z]{1,2}$/ );
    my $criterion = sub { 
        $_->does('Webservice::InterMine::Constraint::Role::Operator')
        &&
        $_->code eq $code 
    };
    my @matches = $self->find_constraints($criterion);
    if ( @matches > 1 ) {
        confess
"more than one constraint found - that should never happen. Please report this bug";
    }
    return $matches[0];
}

sub remove {
    my $self     = shift;
    my $delendum = shift;    # Constraintum delendum est
    my $i        = 0;
    my $type;
    for ($delendum->element_name) {
        if (/pathDescription/) {$type = 'path_description'}
        elsif (/join/)         {$type = 'join'}
        elsif (/constraint/)   {$type = 'constraint'}
        else {confess "Cannot delete elements of type $_ from queries"}
    }
    my $all = 'all_' . $type . 's';
    my $del = 'delete_' . $type;
    for ( $self->$all ) {
        if ( $_ eq $delendum ) {
            $self->$del($i);
        }
        $i++;
    }
}

sub coded_constraints {
    my $self      = shift;
    my $criterion = sub {
        $_->does('Webservice::InterMine::Constraint::Role::Operator');
    };
    return $self->find_constraints($criterion);
}

sub sub_class_constraints {
    my $self = shift;
    my $criterion =
      sub { $_->isa('Webservice::InterMine::Constraint::SubClass') };
    return $self->find_constraints($criterion);
}

sub constraint_codes {
    my $self = shift;
    return map { $_->code } $self->coded_constraints;
}

after push_constraint => sub {
    my $self = shift;
    $self->clear_logic;
};

sub type_dict {
    my $self = shift;
    my @sccs = $self->sub_class_constraints;
    my %type_dict;
    for (@sccs) {
        $type_dict{ $_->path } = $_->type;
    }
    return {%type_dict};
}

sub subclasses {
    my $self = shift;
    my @sccs = $self->sub_class_constraints;
    return map { $_->type } @sccs;
}

has joins => (
    traits     => ['Array'],
    is         => 'ro',
    isa        => JoinList,
    default    => sub { [] },
    auto_deref => 1,
    handles    => {
        all_joins   => 'elements',
        push_join   => 'push',
        map_joins   => 'map',
        clear_joins => 'clear',
        delete_join => 'delete',
    }
);

=head2 add_join( $path )

Specifies the join style of a path on the query. 
The default join style this method adds is "OUTER", but
it can be specified with C<path =&gt; $path, style =&gt; $style>.
Possible join styles are INNER and OUTER.

=cut

sub add_join {
    my $self = shift;
    my $join = Webservice::InterMine::Join->new(@_);
    $self->prefix_pathfeature($join);
    $self->push_join($join);
    return $self;
}

=head2 add_outer_join( $path )

specify that this path is to be treated as an outer join.

=cut

sub add_outer_join {
    my $self = shift;
    my $path = shift;
    confess "Too many arguments to 'add_outer_join', 1 expected" if @_;
    $self->add_join($path);
}

has path_descriptions => (
    traits     => ['Array'],
    is         => 'ro',
    isa        => PathDescriptionList,
    default    => sub { [] },
    auto_deref => 1,
    handles    => {
        all_path_descriptions => 'elements',
        push_path_description => 'push',
        map_path_descriptions => 'map',
        clear_path_descriptions => 'clear',
        delete_path_description => 'delete',
    },
);

sub add_pathdescription {
    my $self = shift;
    my $pd   = Webservice::InterMine::PathDescription->new(@_);
    $self->prefix_pathfeature($pd);
    $self->push_path_description($pd);
    return $self;
}
has logic => (
    writer  => 'set_logic',
    reader  => 'logic',
    isa     => LogicOrStr,
    lazy    => 1,
    clearer => 'clear_logic',
    trigger => \&check_logic,
    default => sub {
        my $self = shift;
        reduce { $a & $b } $self->coded_constraints;
    },
);

has constraint_factory => (
    is         => 'ro',
    isa        => ConstraintFactory,
    lazy_build => 1,
);

sub _build_constraint_factory {
    Webservice::InterMine::ConstraintFactory->new;
}

has is_validating => (
    traits  => ['Bool'],
    is      => 'ro',
    isa     => Bool,
    default => 1,
    handles => {
        suspend_validation => 'unset',
        resume_validation  => 'set',
    },
);

has is_dubious => (
    isa     => Bool,
    default => 0,
    is      => 'ro',
);
sub all_paths {
    my $self    = shift;
    my $to_path = sub { $_->path };
    my @paths   = (
        $self->views,               
        $self->map_constraints($to_path),
        $self->map_joins($to_path), 
        $self->map_path_descriptions($to_path),
    );
    return uniq(@paths);
}

sub all_children {
    my $self = shift;
    my @children;
    for my $meth (qw/all_path_descriptions all_joins all_constraints/) {
        push @children, $self->$meth;
    }
    return @children;
}
############### METHODS

sub check_logic {
    my ( $self, $value ) = @_;
    unless ( blessed $value) {
        my $new_value = _parse_logic( $value, $self->coded_constraints );
        $self->set_logic($new_value);
    }
}

use Webservice::InterMine::LogicParser;

has logic_parser => (
    isa => 'Webservice::InterMine::LogicParser',
    is => 'ro',
    lazy_build => 1,
);

sub _build_logic_parser {
    my $self = shift;
    return Webservice::InterMine::LogicParser->new(query => $self);
}

sub _parse_logic {

   # eg: Organism_interologues: which has the fiercesome:
   # (B or G) and (I or F) and J and C and D and E and H and K and L and M and A
    my $logic_string = shift;
    my @cons         = @_;
    my %found_con;
    for my $con (@cons) {
        $found_con{ $con->code } = $con;
    }

    my @bits = split /\s?\b\s?/, $logic_string;
    my @processed_bits;

    for my $bit (@bits) {
        if ( $bit =~ /^[\(\)]$/ ) {
            push @processed_bits, $bit;
        }
        elsif ( $bit =~ /^[A-Z]+$/ ) {
            if ( $found_con{$bit} ) {
                push @processed_bits, '$found_con{' . $bit . '}';
            }
            else {
                confess "No constraint with code $bit in this query "
                  . " - we only have "
                  . join( ', ', keys %found_con );
            }
        }
        elsif ( $bit =~ /^and$/ ) {
            push @processed_bits, ' & ';
        }
        elsif ( $bit =~ /^or$/ ) {
            push @processed_bits, ' | ';
        }
        else {
            croak "unexpected element in logic string: $bit";
        }
    }
    return eval join '', @processed_bits;
}

sub add_constraint {
    my $self       = shift;
    my %args       = parse_constraint_string(@_);
    my $constraint = $self->constraint_factory->make_constraint(%args);
    if ( $constraint->can('code') ) {
        while ( grep { $constraint->code eq $_ } $self->constraint_codes ) {
            my $code = $constraint->code;
            $constraint->set_code( ++$code );
        }
    }
    $self->prefix_pathfeature($constraint);
    $self->push_constraint($constraint);
    return $constraint;
}

sub parse_constraint_string {
    if ( @_ > 1 ) {
        if ( @_ % 2 == 0 ) {
            my %args = @_;
            my @keys = keys %args;
            if (    ( grep { $_ eq 'path' } @keys )
                and ( grep { $_ =~ /^(?:type|op)$/ } @keys ) )
            {
                return %args;
            }
        }
        my %args;
        @args{qw/path op value extra_value/} = @_;
        if ( ref $args{value} eq 'ARRAY' ) {
            $args{values} = delete $args{value};
        }
        return map { $_ => $args{$_} } grep { defined $args{$_} } keys(%args);
    }
    else {
        my $constraint_string = shift;
        my %args;
        my @bits = split /\s+/, $constraint_string, 2;
        if ( @bits < 2 ) {
            croak "can't parse constraint: $constraint_string";
        }
        $args{path} = $bits[0];
        $constraint_string = $bits[1];
        @bits = $constraint_string =~ m/^
                (
                IS\sNOT\sNULL|
                IS\sNULL|
                NOT\sIN|\S+
                )
        	   (
               ?:\s+(.*)
               )?
	        /x;
        if ( @bits < 1 ) {
            croak "can't parse constraint: $constraint_string\n";
        }

        $args{op} = $bits[0];
        $args{value} = $bits[1] if $bits[1];
        return %args;
    }
}

sub clean_out_SCCs {
    my $self = shift;
    for ( $self->sub_class_constraints ) {
        if ( end_is_class( $self->model, $_->path ) ) {
            $self->remove($_); # remove it because it is not a class
        } elsif (type_of($self->model, $_->path) eq $_->type) {
            $self->remove($_); # remove it because it is constraine to itself
        }
    }
}

sub to_string {
    my $self = shift;
    my $ret = '';
    $ret .= 'VIEW: [' . $self->joined_view(', ') . ']';
    if ($self->constraints) {
        $ret .= ', CONSTRAINTS: [';
        for my $con ($self->constraints) {
            $ret .= '[' . $con->to_string . '],';
        }
        $ret .= ']';
    }
    $ret .= ', LOGIC: ' . $self->logic->code if ($self->coded_constraints > 1);
    $ret .= ', SORT_ORDER: ' . $self->joined_so(' ');
    return $ret;
}

#########################
### VALIDATION

sub validate {    # called externally - forces validation
    my $self = shift;
    $self->resume_validation;
    $self->_validate;
}

sub _validate {    # called internally, obeys is_validating
    my $self = shift;
    return unless $self->is_validating;    # Can be paused, and resumed
    my @errs = @_;
    push @errs, $self->validate_paths;
    push @errs, $self->validate_sort_order;
    push @errs, $self->validate_subclass_constraints;
    push @errs, $self->validate_consistency;

    #   push @errs, $self->validate_logic;
    @errs = grep { $_ } @errs;
    croak join( '', @errs ) if @errs;
}

before _validate => sub {
    my $self = shift;
    if ($self->has_root_path and $self->view_is_empty) {
        $self->add_view('id');
    }
};

sub validate_paths {
    my $self = shift;
    my @paths = ( $self->all_paths, $self->subclasses );
    my @errs =
      map { validate_path( $self->model, $_, $self->type_dict ) } @paths;
    return @errs;
}

sub validate_consistency {
    my $self = shift;
    my @roots =
      map { root( $self->model, $_, $self->type_dict ) } $self->all_paths;
    unless ( uniq(@roots) == 1 ) {
        return
            "Inconsistent query: all paths must descend from the same root."
          . " - we got: "
          . join( ', ', map { $_->name } uniq @roots ) . "\n";
    }
    return undef;
}

sub validate_sort_order {
    my $self = shift;
    return if $self->view_is_empty;
    if ($self->has_sort_order) {
        for my $so ($self->sort_orders) {
            unless ( grep { $so->path eq $_ } $self->views ) {
                return $so->path . " is not in the view\n";
            }
        }
    }
    return;
}

sub validate_subclass_constraints {
    my $self = shift;
    my @errs;
    push @errs, map { end_is_class( $self->model, $_ ) }
      map { ( $_->path, $_->type ) } $self->sub_class_constraints;
    push @errs, map { b_is_subclass_of_a( $self->model, @$_ ) }
      map { [ $_->path, $_->type ] } $self->sub_class_constraints;
    return @errs;
}

# sub validate_logic {
#     my $self = shift;
#     my @errs;
#     my @constraints_in_logic = $self->logic->constraints;
#     my @constraints_in_query = $self->coded_constraints;
#     for my $con (@constraints_in_query) {
# 	unless (grep {$_ eq $con} @constraints_in_logic) {
# 	    push @errs, "Constraint " . $con->code . " is not in the logic (" .
# 		        $self->logic->code . ")\n";
# 	}
#     }
#     return @errs;
# }

########## DEPRECATED BITS

# Left in for backwards compatability

=head2 AND

=cut

sub AND {
    my ( $l, $r ) = @_;
    return $l & $r;
}

=head2 OR

=cut

sub OR {
    my ( $l, $r ) = @_;
    return $l | $r;
}
__PACKAGE__->meta->make_immutable;
no Moose;
1;
