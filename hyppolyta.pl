#!/usr/bin/perl
#
# Hyppolyta - The Amazon(r) Queen
# Copyright (C) 2007 Bastian Rieck (canmore [AT] annwfn [THIS_IS_A_DOT] net)
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


use strict;
use warnings;

use LWP::UserAgent qw($ua get);
use MIME::Base64;
use XML::XPath;
use Date::Format;
use Text::CSV_XS;
use Getopt::Long;


# Set this variable to 1 if you want Hyppolyta to output the XML data Amazon
# sends. This data is stored in hyppolyta.xml.
my $debug = 1;

# global options for each request
my @requests = ();
my $req_locale = "de";
my $req_search_index = "Books"; 
my $req_service = "AWSECommerceService";
my $req_key = "[YOUR KEY]";
my $req_op = "ItemLookup";
my $req_ver = "2007-07-16";

# Abandon all hope, ye who change stuff here without knowing what they are
# doing. Read the documentation before you change anything here. Please.

my @attributes_general = (	
				{Name => "EAN", 	NodeIterate => "ItemAttributes/EAN", 	Output => 1 },
				{Name => "Title",	NodeIterate => "ItemAttributes/Title", 	Output => 1},
				{Name => "Binding", 	NodeIterate => "ItemAttributes/Binding"},
				{Name => "Review", 	NodeIterate => "EditorialReviews/EditorialReview/Content"},
				{Name => "Publisher", 	NodeIterate => "ItemAttributes/Publisher"} );

my %attributes_specific = ( 	"Books" => [ 	{Name => "ISBN", 
						NodeIterate => "ItemAttributes/ISBN" },
						{Name => "Author(s)", 
						NodeIterate => "ItemAttributes/Author",
						Output => 1 },
						{Name => "Editor(s)",
						NodeIterate => "ItemAttributes/Creator"},
						{Name => "Publication Date",
						NodeIterate => "ItemAttributes/PublicationDate"},
						{Name => "Number of pages",
						NodeIterate => "ItemAttributes/NumberOfPages"},
						{Name => "Edition",
						NodeIterate => "ItemAttributes/Edition"} ],
				"ForeignBooks" => [
						{Name => "ISBN", 
						NodeIterate => "ItemAttributes/ISBN" },
						{Name => "Author(s)", 
						NodeIterate => "ItemAttributes/Author",
						Output => 1 },
						{Name => "Editor(s)",
						NodeIterate => "ItemAttributes/Creator"},
						{Name => "Publication Date",
						NodeIterate => "ItemAttributes/PublicationDate"},
						{Name => "Number of pages",
						NodeIterate => "ItemAttributes/NumberOfPages"},
						{Name => "Edition",
						NodeIterate => "ItemAttributes/Edition"} ],

				"DVD" => [	{Name => "Director(s)",
						NodeIterate => "ItemAttributes/Director"},
						{Name => "Actor(s)",
						NodeIterate => "ItemAttributes/Actor"},
						{Name => "Region Code",
						NodeIterate => "ItemAttributes/RegionCode"},
						{Name => "Running time",
						NodeIterate => "ItemAttributes/RunningTime"},
						{Name => "Number of Disc(s)",
						NodeIterate => "ItemAttributes/NumberOfItems"},
						{Name => "Audience Rating",
						NodeIterate => "ItemAttributes/AudienceRating"},
						{Name => "Aspect Ratio",
						NodeIterate => "ItemAttributes/AspectRatio"},
						{Name => "Year",
						NodeIterate => "ItemAttributes/TheatricalReleaseDate"},
						{Name => "Language",
						NodeIterate => "ItemAttributes/Languages/Language",
						NodeValue => "Name"}],

				"Music" => [	{Name => "Artist(s)",
						NodeIterate => "ItemAttributes/Artist"},
						{Name => "UPC",
						NodeIterate => "ItemAttributes/UPC"} ]	
				);

my $file_in = "input.txt";
my $file_out = "hyppolyta.csv";

# Allows you to specify a prefix for very image URL. If you home database is
# running on http://foo.bar/ and all images are stored under
# http://foo.bar/baz/images, you might want to consider using this variable.
my $url_prefix  ="";

my $idtype = "ISBN";
my $search_ean = 0;
my $no_images = 0;
my $num_items = 0;
my $cur_item = 0;

my @failed_items = ();

GetOptions(	"l=s" => \$req_locale,
		"locale=s" => \$req_locale,
		"search-index=s" => \$req_search_index,
		"s=s" => \$req_search_index,
		"ean" => \$search_ean,
		"e" => \$search_ean,
		"input=s" => \$file_in,
		"i=s" => \$file_in,
		"n" => \$no_images,
		"no-images" => \$no_images,
		"output=s" => \$file_out, 
		"o=s" => \$file_out,
		"idtype=s" => \$idtype,
		"t=s" => \$idtype );

my $req_id_type = ( $search_ean ? "EAN" : $idtype );
my $req_end = "http://ecs.amazonaws." . lc($req_locale) . "/onca/xml";

print "* Hyppolyta is searching \"$req_search_index\" via $req_id_type.\n"; 
print "* Images will " . ( $no_images ? "NOT" : "" ) . " be downloaded.\n";
print "* Reading data from \"$file_in\". Building requests...\n";

open( INFILE, $file_in ) or die "ERR: $file_in cannot be opened.\n";
while( <INFILE> )
{
	my $request =
			"$req_end?" .
			"Service=$req_service&" .
			"AWSAccessKeyId=$req_key&" .
			"Operation=$req_op&" .
			"IdType=$req_id_type&" .
			"ResponseGroup=ItemAttributes,Images,EditorialReview&" .
			"SearchIndex=$req_search_index&";


	# one request can hold up to 10 items

	for( my $i = 1; $i <= 10; $i++ )
	{
		chomp $_;
		$request = $request . "ItemId=$_" if $i == 1;
		$request = $request . ",$_" if $i != 1;

		$_ = <INFILE> if $i != 10;

		# TODO: Check whether these are really ISBNs
		# or EANS. For now, we assume that the input
		# is well-defined.

		$num_items++;
		last if !$_;
	}

	$request = $request. "&Version=$req_ver";
	push( @requests, $request );
}

print "* Processed $num_items item(s).\n";
print "* Requests ready. Processing...\n";

close( INFILE );

# process all stored requests

open( DEBUG, "> hyppolyta.xml" ) or die "ERR: Could not open debug file.\n" if $debug;

my $ua = new LWP::UserAgent;
$ua->timeout(10);

# prepare for writing

print "* Sending requests. Data is stored in \"$file_out\".\n\n";
open( OUTFILE, "> $file_out" ) or die "ERR: $file_out cannot be created/opened!\n";

# Write the CSV header. The last item is always the image URL.

my $csv = Text::CSV_XS->new( { 	always_quote => 1,
				binary => 1, 
				eol => "\012" } );
print OUTFILE create_csv_header( $csv );

# process the responses

for( my $i = 0; $i < @requests; $i++ )
{
	my $response = $ua->get($requests[$i]);
	my $xml = $response->content;
	my $xp = XML::XPath->new(xml => $response->content);

	print DEBUG $xml if $debug;

	# store each item in the response
	for( my $j = 1; $j <= $xp->find("count( /ItemLookupResponse/Items/Item)"); $j++ )
	{
		$cur_item++;
		print "* $cur_item/$num_items:";

		# Output in other formats is a mostly trivial matter. Feel free
		# to add some you like.

		print OUTFILE create_csv_data( $xp, $j );
	}

	# output errors. It would be nice to parse the failed EANs/ISBNs
	# automatically, but since there might be other errors (service not
	# available etc.), writing them to STDERR is much safer.
	#
	# UPDATE 08-28-2007: Since the most commong error message is "<ID> is
	# not a valid value for ItemId", a rudimentary parsing of errors is
	# possible.
	for( my $j = 1; $j <= $xp->find( "count(/ItemLookupResponse/Items/Request/Errors/Error)" ); $j++ )
	{
		my $err_msg = $xp->findvalue( "/ItemLookupResponse/Items/Request/Errors/Error[$j]/Message" ); 
		if( index( $err_msg, "is not a valid value for ItemId") > -1 )
		{
			my($tmp) = split( " ", $err_msg );
			push( @failed_items, $tmp );
		}
		else
		{
			print STDERR "ERR: $err_msg\n";
		}
	}
}

close( OUTFILE );
close( DEBUG ) if $debug;

print 	"* Statistics:\n",
	"\tItems (total):\t$num_items\n",
	"\tItems (read):\t$cur_item\n",
	"\tItems (error):\t".($num_items - $cur_item )."\n";

# Print failed items. This is nice if the session is logged via script (1).

print STDERR "* The following items failed:\n" if @failed_items;
for( my $i = 0; $i < @failed_items; $i++ )
{
	print STDERR "$failed_items[$i]\n";
}

# Generates the header for the CSV file. This is performed by searching the names
# for all general and specific attributes. These field names are combined to a
# string (which is the return value of the sub).

sub create_csv_header
{
	my ( $csv ) = @_;
	my @header = ();

	# REMARK:
	# Only the names of the columns are added to the header.
	
	for( my $i = 0; $i < @attributes_general; $i++ )
	{
		push( @header, ${$attributes_general[ $i ]}{"Name"} );
	}

	for( my $i = 0; $i < @{$attributes_specific{$req_search_index}}; $i++ ) 
	{
		push( @header, ${$attributes_specific{$req_search_index}}[$i]{"Name"} );
	}

	# NOTA BENE: The image column should always be the last column. If you
	# want to change this, it has to be changed in create_csv_data, too.

	push( @header, "Image" ) if !$no_images;

	$csv->combine( @header );
	return $csv->string;
}

# Creates CSV (comma separated values) data according to the search index. Since
# CSV is a very simple format, all useful information about an item will be
# included in the output.

sub create_csv_data
{
	my ($xp, $i) = @_;
	my @data = ();

	# The lists are filled with almost any attribute available.

	for( my $j = 0; $j < @attributes_general; $j++ )
	{
		push( @data, get_element( $xp, $i, %{$attributes_general[$j]} ) );
	}

	for( my $j = 0; $j < @{$attributes_specific{$req_search_index}}; $j++ )
	{
		push( @data, get_element( $xp, $i, %{$attributes_specific{$req_search_index}[$j]} ) );
	}

	# NOTA BENE: This should be the last attribute added. If you want to
	# change this, change it in create_csv_header, too.
	push( @data, get_image( $xp, $i ) ) if !$no_images;


	$csv->combine( @data );
	return $csv->string;
};

# Returns all data that is available in the request for one specific response
# element.  For example, one might look for actors, directors, images etc.. The
# list is concatenated via ",", thus allowing you to distinguish between the
# original values.

sub get_element
{
	my( $xp, $i, %element ) = @_;
	my ( $data, $lookup_string ) = "";

	for( my $j = 1; $j <= $xp->find( "count(/ItemLookupResponse/Items/Item[$i]/" . $element{NodeIterate} ); $j++ )
	{
		$lookup_string = "/ItemLookupResponse/Items/Item[$i]/".$element{NodeIterate}."[".$j."]" if defined $element{NodeIterate};
		$lookup_string .= "/".$element{NodeValue} if defined $element{NodeValue};

		$data = $data . ", " if $j > 1;
		$data = $data . $xp->findvalue( $lookup_string );
	}

	print "\t".$element{Name}.": ".$data."\n" if defined $element{Output} and $element{Output} and $data;
	return $data;
}

sub get_image
{
	my( $xp, $i ) = @_;
	
	my $id = $xp->findvalue( "/ItemLookupResponse/Items/Item[$i]/ItemAttributes/EAN" );
	my $image = "";
	my $url = "";

	$url = $xp->findvalue( "/ItemLookupResponse/Items/Item[$i]/LargeImage/URL" );
	$url = $xp->findvalue( "/ItemLookupResponse/Items/Item[$i]/MediumImage/URL" ) if !$url;
	$url = $xp->findvalue( "/ItemLookupResponse/Items/Item[$i]/SmallImage/URL" ) if !$url;
	$url = $xp->findvalue( "/ItemLookupResponse/Items/Item[$i]/ImageSets/ImageSet/LargeImage/URL" ) if !$url;
	$url = $xp->findvalue( "/ItemLookupResponse/Items/Item[$i]/ImageSets/ImageSet/MediumImage/URL" ) if !$url;
	$url = $xp->findvalue( "/ItemLookupResponse/Items/Item[$i]/ImageSets/ImageSet/SmallImage/URL" ) if !$url;

	if( $url )
	{
		print "\tFetching image...";
		
		system( "wget -q -O " . lc( $req_search_index ) . "/$id.jpg $url" );
		$image = $url_prefix . lc( $req_search_index ) . "/" . $id . ".jpg";

		print "done.\n";

	}

	if( !$image )
	{
		# TODO:
		# You can add your own image path here if you want to.

		print "\tWARNING: No image available for $id.\n";
		$image = "n/a";
	}
	
	return $image;
};
