#!/usr/local/bin/perl -w
use strict;
use lib '../.', 
	'/Homes/xpix/projekts/Tk-Moduls';

use Tk;
use Tk::DBI::Tree;
use DBI;
use Data::Dumper;
use IO::File;

my $host = shift || &use_this_so;
my $db   = shift || &use_this_so;
my $user = shift || &use_this_so;
my $pass = shift || &use_this_so;

# DB Handle
my $dbh = DBI->connect(	
	"DBI:mysql:database=${db};host=${host}", 
	$user, $pass)
		or die ("Can't connect to database:", $! );

my $top = MainWindow->new;


my $tkdbi = $top->DBITree(
			-dbh   		=> $dbh,
			-table		=> 'Inventory',
			-textcolumn	=> 'name',
			-idx		=> 'id',
			-columnWidths	=> [undef, undef, undef, 150],
			-fields		=> [qw(changed_by changed_at descr)],
			-parent_id	=> 'parent_id',
			-start_id	=> 1,
			-maxchars	=> { descr => 25 },
		)->pack(
			-expand => 1, 
			-fill => 'both');

my $entrytext = '$tkdbi->select_entrys([qw/1 1:3/])';
my $entry = $top->Entry(
		-text => \$entrytext,
)->pack(-side => 'left', -expand => 1, -fill => 'x');

my $button = $top->Button(
		-text => 'Go!',
		-command => sub{
			eval($entrytext);
			print $@ if($@);
		},
)->pack(-side => 'left');
$tkdbi->Subwidget('tree')->configure(
	-command => sub{ printf "This is id: %s\n", $_[0] },
);

$top->bind('<Escape>', sub{ $dbh->disconnect; exit });
MainLoop;


sub use_this_so {
	print "\nplease use $0 host db user password\n";
	exit;
}

