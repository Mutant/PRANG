
package PRANG::Marshaller;

use Moose;
use MooseX::Method::Signatures;
use Moose::Util::TypeConstraints;

use XML::LibXML 1.70;
use PRANG::Util qw(types_of);

BEGIN {
	class_type 'Moose::Meta::Class';
	class_type "Moose::Meta::Role";
	class_type "XML::LibXML::Element";
	class_type "XML::LibXML::Node";
	role_type "PRANG::Graph";
};

has 'class' =>
	isa => "Moose::Meta::Class|Moose::Meta::Role",
	is => "ro",
	required => 1,
	handles => [qw(marshall_in_element to_libxml)],
	;

our %marshallers;  # could use MooseX::NaturalKey?
method get($inv: Str $class) {
	if ( ref $inv ) {
		$inv = ref $inv;
	}
	$class->can("meta") or do {
		my $filename = $class;
		$filename =~ s{::}{/}g;
		$filename .= ".pm";
		if ( !$INC{$filename} ) {
			eval { require $filename };
		}
		$class->can("meta") or
			die "cannot marshall $class; no ->meta";
	};
	my $meta = $class->meta;
	if ( $meta->does_role("PRANG::Graph") or
		     $meta->does_role("PRANG::Graph::Class")
		    ) {
		$marshallers{$class} ||= do {
			$inv->new( class => $class->meta );
		}
	}
	else {
		die "cannot marshall ".$meta->name
			."; not a PRANG Class/Node";
	}
}

method parse( Str $xml ) {

	my $dom = XML::LibXML->load_xml(
		string => $xml,
	       );

	my $rootNode = $dom->documentElement;
	my $rootNodeNS = $rootNode->namespaceURI;

	my $xsi = {};
	if ( $self->class->isa("Moose::Meta::Role") ) {
		my @possible = types_of($self->class);
		my $found;
		my $root_localname = $rootNode->localname;
		my @expected;
		for my $class ( @possible ) {
			if ( $root_localname eq
				     $class->name->root_element ) {
				# yeah, this is lazy ;-)
				$self = (ref $self)->get($class->name);
				$found = 1;
				last;
			}
			else {
				push @expected, $class->name->root_element;
			}
		}
		if ( !$found ) {
			die "No type of ".$self->class->name
				." that expects '$root_localname' as a root element (expected: @expected)";
		}
	}
	my $expected_ns = $self->class->name->xmlns;
	if ( $rootNodeNS and $expected_ns ) {
		if ( $rootNodeNS ne $expected_ns ) {
			die "Namespace mismatch: expected '$expected_ns', found '$rootNodeNS'";
		}
	}
	if ( !defined($rootNode->prefix) and
		     !defined($rootNode->getAttribute("xmlns")) ) {
		# namespace free;
		$xsi->{""}="";
	}

	my $context = PRANG::Graph::Context->new(
		base => $self,
		xpath => "/".$rootNode->nodeName,
		xsi => $xsi,
		prefix => ($rootNode->prefix||""),
	       );

	my $rv = $self->class->marshall_in_element(
		$rootNode,
		$context,
	       );
	$rv;
}

method xml_version { "1.0" };
method encoding { "UTF-8" };

# nothing to see here ... move along please ...
our $zok;
our %zok_seen;
our @zok_themes = (qw( tmnt octothorpe quantum pokemon hhgg pasta
		       phonetic sins punctuation discworld lotr
		       loremipsum batman tld garbage python pooh
		       norse_mythology ));
our $zok_theme;

our $gen_prefix;

method generate_prefix( Str $xmlns ) {
	if ( $zok or eval { require Acme::MetaSyntactic; 1 } ) {
		my $name;
		do {
			$zok ||= do {
				%zok_seen=();
				if ( defined $zok_theme ) {
					$zok_theme++;
					if ( $zok_theme > $#zok_themes ) {
						$zok_theme = 0;
					}
				}
				else {
					$zok_theme = int(time / 86400)
						% scalar(@zok_themes);
				}
				Acme::MetaSyntactic->new(
					$zok_themes[$zok_theme],
				       );
			};
			do {
				$name = $zok->name;
				if ($zok_seen{$name}++) {
					undef($zok);
					undef($name);
					goto next_theme;
				};
			} while ( length($name) > 10 or
					  $name !~ m{^[A-Za-z]\w+$} );
			next_theme:
		}
			until ($name);
		return $name;
	}
	else {
		# revert to a more boring prefix :)
		$gen_prefix ||= "a";
		$gen_prefix++;
	}
}

method to_xml_doc( PRANG::Graph $item ) {
	my $xmlns = $item->xmlns;
	my $prefix = "";
	if ( $item->can("preferred_prefix") ) {
		$prefix = $item->preferred_prefix;
	}
	my $xsi = { $prefix => ($xmlns||"") };
	# whoops, this is non-reentrant
	%zok_seen=();
	undef($gen_prefix);
	my $doc = XML::LibXML::Document->new(
		$self->xml_version, $self->encoding,
	       );
	my $root = $doc->createElement(
		($prefix ? "$prefix:" : "" ) .$item->root_element,
	       );
	if ( $xmlns ) {
		$root->setAttribute(
			"xmlns".($prefix?":$prefix":""),
			$xmlns,
		       );
	}
	$doc->setDocumentElement( $root );
	my $ctx = PRANG::Graph::Context->new(
		xpath => "/".$root->nodeName,
		base => $self,
		prefix => $prefix,
		xsi => $xsi,
	       );
	$item->meta->to_libxml( $item, $root, $ctx );
	$doc;
}

method to_xml( PRANG::Graph $item ) {
	my $document = $self->to_xml_doc($item);
	$document->toString;
}

1;

