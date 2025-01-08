#!/usr/bin/env perl -w

use v5.38;
use strict;
use warnings;
use feature 'postderef'; 
use File::Basename;
use File::Spec;
use lib File::Spec->catdir( File::Spec->catdir( File::Spec->rel2abs( dirname( $0 ) ) , File::Spec->updir() ) , 'local' , 'lib', 'perl5' ) ;
use Data::Printer;
use LWP::UserAgent;
my $ua = LWP::UserAgent->new;
use Digest::MD5 qw(md5_hex);
use autodie qw(:all);
use MIME::Base64 ('encode_base64');
use List::MoreUtils qw(natatime);
use Getopt::Long;

Getopt::Long::Configure("bundling", "no_ignore_case", "permute", "no_getopt_compat"); 

GetOptions(
	'v|verbose'	=> \(my $DEBUG = 0),
);


$ua->agent("MyApp/0.1");

my $var_dir = File::Spec->catdir( File::Spec->rel2abs( dirname( $0 ) ) , File::Spec->updir() , 'var' );

my $slurp = do { local $/; <> };

my @vcards = ( $slurp =~ /^BEGIN:VCARD\s*$(.+?)\s*^END:VCARD/msg );

@vcards = map { $_ =~ s/\s* $ \s* ^\s//msgx; $_ } @vcards;

for my $vcard ( @vcards ) {
	my $content;
	if ( $vcard =~ /^PHOTO:(?<url>http.+)$/m ) {
		my $filename = File::Spec->catdir($var_dir, md5_hex($+{url}));
		if ( -e $filename.".png" ) {
			$filename = $filename.".png";
			$DEBUG && say STDERR "$filename already exists";
			open my $fh, "<", $filename;
			my $slurp = do { local $/; <$fh> };
			$content = "PHOTO;ENCODING=b;TYPE=JPEG:".encode_base64($slurp, '');
		}
		elsif ( -e $filename.".jpeg" ) {
			$filename = $filename.".jpeg";
			$DEBUG && say STDERR "$filename already exists";
			open my $fh, "<", $filename;
			my $slurp = do { local $/; <$fh> };
			$content = "PHOTO;ENCODING=b;TYPE=PNG:".encode_base64($slurp, '');
		}
		else {
			$DEBUG && say STDERR "Downloading ", $+{url};
			my $req = HTTP::Request->new(GET => $+{url});
			my $res = $ua->request($req);
			if ($res->is_success) {
				$DEBUG && say STDERR "GET: ".$+{url};
				$DEBUG && say STDERR $res->content_type;	
				if ( $res->content_type eq 'image/jpeg' ) {
					$filename = $filename.".jpeg";
					$content = "PHOTO;ENCODING=b;TYPE=JPEG:".encode_base64($res->content, '');
				}
				elsif ( $res->content_type eq 'image/png' ) {
					$filename = $filename.".png";
					$content = "PHOTO;ENCODING=b;TYPE=PNG:".encode_base64($res->content, '');
				}
				else {
					die "Cannot handle ",$res->content_type;
				}
				open(my $fh, '>', $filename);
				print $fh $res->content;
			}
			else {
				$DEBUG && say STDERR $res->status_line;
			}	
		}
			
	}
	my $it = natatime 2, ( $vcard =~ /^(\S+?):(.+?)$/mg );
	my @items = ();
	while (my @item = $it->()) {
		my $str;
		if ($item[0] eq 'PHOTO') {
			$str = $content
		}
		else {
			$str = $item[0].":".$item[1]
		}	
		push @items, $str if defined $str;
	}
	
	my $vcard_str = "BEGIN:VCARD\n".join("\n", @items)."\nEND:VCARD";
	say $vcard_str;
}
