package Indexer;

$| = 1;

use strict;
use warnings;

use Readonly;
use XML::Bare;

use KinoSearch 0.313;
use KinoSearch::Schema;
use KinoSearch::Index::Indexer;
use KinoSearch::Analysis::PolyAnalyzer;
use KinoSearch::FieldType::FullTextType;
 
use Lingua::StopWords qw( getStopWords );
 
use Lingua::Stem::Snowball;
use Text::DoubleMetaphone qw( double_metaphone );

Readonly my $END   => 'end';
Readonly my $START => 'start';

=head1 Indexer

KinoSearch indexer implementation.

=cut

=head2 new

PUBLIC METHOD.

my $indexer = Indexer->new(
    source  => $CIRCULATION_DATA,
    idx_loc => $INDEX_LOCATION,
    verbose => 1,
);
$indexer->build_from_file;

=cut

sub new {
    my ($class, %p) = @_;
    
    my %ref = map { '_'.$_ => $p{$_} } (keys %p);
    return bless \%ref, $class;
}

=head2 build_from_file

PUBLIC METHOD.

Build the index given that the data file location has been passed
into the constructor of the package.

=cut

sub build_from_file {
    my ($self) = @_;

    # Does file exist?
    die "Source file does not exist!\n" unless -f $self->{_source};

    # Handle XML by hand. Preferable to use an XML library in production.
    my $xml = q{};
    my $marker = $END;

    open my $fh, $self->{_source} or die "Unable to open file: $self->{_source}\n";
    while ( <$fh> ) {
       if( m|^<item id="\d+">|i && ($marker eq $END) ) {
            $xml .= $_;
            $marker = $START;
        }
        elsif( m|^</item>|i && ($marker eq $START) ) {
            $xml .= $_;
            $marker = $END;

            my $sludge = new XML::Bare( text => $xml );
            my $docref = $sludge->parse();
            $xml = q{};

            # Index this item:
            $self->_index_doc( $docref );
        }
        elsif( $marker eq $START ) {
            $xml .= $_;
        }
    }

    # Close filehandle & commit inserts into the inverted index.
    close $fh;
    $self->{_index}->commit;

    print STDERR qq{\n} if( $self->{_verbose} );
}

sub _index_doc {
    my ($self, $docref) = @_;

    # The parsing above isn't great so some items come in the form of arrays
    # of hashes. Others arrive as singular hashes.
    my $items = ref($docref->{item}) eq 'ARRAY' ? $docref->{item}
        : [ $docref->{item} ];

    # Create a draft document that we want to index by pulling field values
    # from the XML file.
    foreach my $item ( @{$items} ) {
        # Build document to index:
        my $doc = {
            copies => _extract($item, 'copies'),
            url    => _extract($item, 'url'),
            id     => _extract($item, 'id'),
            title  => _extract($item, 'title'),
            isbn   => _extract($item, 'isbn'),
        };

        # Physically mangle & insert draft document into the inverted index:
        $self->_add_to_index( $doc );
    }

   $self->_increment;;
}

sub _add_to_index {
    my ($self, $doc) = @_;

    # When indexing text, do so in such a way so that searches on the index
    # are effectively case insensitive, exclusive of stopwords and inclusive
    # of word-stem searches.
    # This is achieved by defining a PolyAnalyzer with the above-stated
    # characteristics and passing it through to FieldType instantiation.

    $self->{_tokenizer}    ||= KinoSearch::Analysis::Tokenizer->new;
    $self->{_polyanalyzer} ||= KinoSearch::Analysis::PolyAnalyzer->new(
        analyzers => [
            KinoSearch::Analysis::CaseFolder->new,
            $self->{_tokenizer},
            KinoSearch::Analysis::Stopalizer->new(language => 'en'),
            KinoSearch::Analysis::Stemmer->new(language => 'en'),
        ],
    );

    # This indicates that content of this type should not be indexed.
    $self->{_type_no_idx}   ||= KinoSearch::FieldType::StringType->new(
        indexed => 0
    );

    $self->{_type_no_anlze} ||= KinoSearch::FieldType::FullTextType->new(
        analyzer => $self->{_tokenizer},
    );

    # Fulltext search type.
    # Matched terms should also be highlighted enabling contextual searches:
    $self->{_type_fulltext} ||= KinoSearch::FieldType::FullTextType->new(
        analyzer => $self->{_polyanalyzer},
        highlightable => 1,
    );

    # Define a database schema using the types defined above.
    if( !$self->{_schema} ) {
        $self->{_schema} = KinoSearch::Schema->new;
        
        $self->{_schema}->spec_field( name => 'id',       type => $self->{_type_no_idx}   );
        $self->{_schema}->spec_field( name => 'url',      type => $self->{_type_no_idx}   );
        $self->{_schema}->spec_field( name => 'isbn',     type => $self->{_type_no_idx}   );
        $self->{_schema}->spec_field( name => 'title',    type => $self->{_type_fulltext} );
        $self->{_schema}->spec_field( name => 'copies',   type => $self->{_type_no_idx}   );
        $self->{_schema}->spec_field( name => 'phonetic', type => $self->{_type_no_anlze} );
    }

    # Create an instance of the indexer.
    $self->{_index} ||= KinoSearch::Index::Indexer->new(
        schema   => $self->{_schema},
        index    => $self->{_idx_loc},
        create   => 1,
        truncate => 1,
    );

    # Build an object to help determine words stems of any given word.
    $self->{_stemmerObj} ||= Lingua::Stem::Snowball->new(
        lang     => 'en',
    );
    die $@ if $@;

    # Get a list of stopwords.
    $self->{_stopwords} ||= Lingua::StopWords::getStopWords('en');

    # Build phonetic codes from full terms & word-stems; excluding stopwords:
    my @words = grep {
        !$self->{_stopwords}->{$_}
    } split /\s+/, $doc->{title};

    my @stems = $self->{_stemmerObj}->stem(\@words);
    push @words, @stems;

    my %phonetic = ( );
    foreach my $word (@words) {
        my @codes = Text::DoubleMetaphone::double_metaphone($word);
        foreach my $code (@codes) {
            $phonetic{$code}++ if $code;
        }
    }
    
    # Add phonetic codes to the document.
    $doc->{phonetic} = join ' ', keys %phonetic;

    # Pass the document to the indexer; finally!
    $self->{_index}->add_doc($doc);
}

sub _extract {
    return (
        ref($_[0]) eq 'HASH' && ref($_[0]->{$_[1]}) eq 'HASH' &&
        $_[0] && defined $_[0]->{$_[1]} && defined $_[0]->{$_[1]}->{value}
    ) ?  $_[0]->{$_[1]}->{value} : q{};
}

sub _increment {
    ++$_[0]->{_count};

    if( $_[0]->{_verbose} ) {
        print STDERR qq|$_[0]->{_count} records processed\r|;
    }
}

1;
