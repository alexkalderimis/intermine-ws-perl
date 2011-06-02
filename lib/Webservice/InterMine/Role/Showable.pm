package Webservice::InterMine::Role::Showable;

use Moose::Role;

requires qw/to_string views table_format results_iterator/;

use IO::Handle;

sub show {
    my $self = shift;
    my $fh = shift || \*STDOUT;

    binmode $fh, ':encoding(utf8)';
    print $fh $self->to_string, "\n";
    printf $fh $self->table_format, $self->views;
    my $iter = $self->results_iterator;
    while (<$iter>) {
        printf $fh $self->table_format, map {(defined $_) ? $_ : 'UNDEF'} @$_;
    }
}

=head2 print_results( %options )

returns the results from a query in the result format
specified. 

The following options are available:

=over 4

=item * to => $filename|GlobRef

A file name to open, or a file handle opened for writing.

=item * as => $format

Possible values: (tsv|csv|arrayrefs|hashrefs|jsonobjects|jsonrows|count)

The format to print results in. The default is C<tsv>

=item * size => $size

The number of results to return. Leave undefined for "all" (default).

=item * start => $start 

The first result to return (starting at 0). The default is 0.

=item * addheaders => 0/1/friendly/path

Whether to return the column headers at the top of TSV/CSV results. The default is
false. There are two styles - friendly: "Gene > pathways > name" and 
path: "Gene.pathways.name". The default style is friendly if a true value is entered and
it is not "path".

=item * json => $json_processor

Possible values: (inflate|instantiate|perl)

What to do with JSON results. The results can be returned as inflated objects,
full instantiated Moose objects, a raw json string, or as a perl
data structure. (default is C<perl>). B<THIS OPTION MAKES LITTLE SENSE WHEN 
PRINTING RESULTS.>

=back

=cut

sub print_results {
    my $self = shift;
    my %args = @_;
    my $to = delete($args{to}) || \*STDOUT;
    $args{as} ||= 'tab'; # For printing, we default to TSV.
    my $out; 
    if ($to) {
        if (ref $to eq 'GLOB') {
            $out = $to;
        } else {
            open($out, '>', $to) or confess "Cannot open $to, $!";
        }
    } else {
        $out = \*STDOUT;
    }
    binmode $out, ':encoding(utf8)';
    my $iter = $self->results_iterator(%args);
    while (my $line = <$iter>) {
        $out->print($line, "\n");
    }
}

1;
