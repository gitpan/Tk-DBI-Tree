package Tk::DBI::Tree;
#------------------------------------------------
# automagically updated versioning variables -- CVS modifies these!
#------------------------------------------------
our $Revision           = '$Revision: 1.3 $';
our $CheckinDate        = '$Date: 2003/04/03 15:39:27 $';
our $CheckinUser        = '$Author: xpix $';
# we need to clean these up right here
$Revision               =~ s/^\$\S+:\s*(.*?)\s*\$$/$1/sx;
$CheckinDate            =~ s/^\$\S+:\s*(.*?)\s*\$$/$1/sx;
$CheckinUser            =~ s/^\$\S+:\s*(.*?)\s*\$$/$1/sx;
#-------------------------------------------------
#-- package Tk::DBI::Tree -----------------------
#-------------------------------------------------


use DBIx::Tree;
use Tk::Tree;
use Tk::Compound;
use Tk::ItemStyle;
use Tk::ResizeButton;

use base qw/Tk::Derived Tk::Frame/;

use strict;

Construct Tk::Widget 'DBITree';

# ------------------------------------------
sub ClassInit
# ------------------------------------------
{
	my($class,$mw) = @_;

}

# ------------------------------------------
sub Populate {
# ------------------------------------------
	my ($obj, $args) = @_;
	my $style;

	$obj->{dbh} 		= delete $args->{'-dbh'} 	|| return error("No DB-Handle!");
	$obj->{table}		= delete $args->{'-table'} 	|| return error("No Table!");
	$obj->{debug} 		= delete $args->{'-debug'} 	|| 0;
	$obj->{idx}		= delete $args->{'-idx'}	|| return error("No IndexColumn!");
	$obj->{fields}		= delete $args->{'-fields'} 	|| return error("No Fields!");
	$obj->{textcolumn}	= delete $args->{'-textcolumn'} || return error("No Textcolumn!");
 	$obj->{start_id}	= delete $args->{'-start_id'} 	|| 1;
 	$obj->{callback}	= delete $args->{'-callback'};
	$obj->{parent_id}	= delete $args->{'-parent_id'} 	|| return error("No Parent_id!");
	$obj->{columnWidths}	= delete $args->{'-columnWidths'};
	$obj->{maxchars}	= delete $args->{'-maxchars'};
	$obj->SUPER::Populate($args);

	
	my %specs;
	$specs{refresh} 	= [qw/METHOD refresh 		Refresh/, 		undef];
	$specs{close_all}	= [qw/METHOD close_all 		Close_all/, 		undef];
	$specs{listEntrys}	= [qw/METHOD listEntrys 	ListEntrys/, 		undef];
	$specs{remember}	= [qw/METHOD remember 		Remember/, 		undef];
	$specs{select_entrys}	= [qw/METHOD select_entrys 	Select_entrys/, 	undef];
	
        $obj->ConfigSpecs(%specs);

	$obj->refresh('redraw');

} # end Populate


# Class private methods;
# ------------------------------------------
sub refresh {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my $redraw = shift;
	$obj->Busy();

	# Bildet den Tree in einem Array ab
	unless(defined $obj->{dbtree}) {
		$obj->{dbtree} = DBIx::Tree->new( 
			connection => $obj->{dbh}, 
		        table      => $obj->{table}, 
		        method     => sub { $obj->make_tree_list(@_) },
		        columns    => [$obj->{idx}.'+0', $obj->{textcolumn}, $obj->{parent_id}],
		        start_id   => $obj->{start_id},
	        ); 
	}

	unless(defined $obj->{tree}) {
		$obj->{tree} = $obj->Scrolled('Tree',
			-scrollbars 	=> 'ose',
			-columns	=> scalar @{$obj->{fields}} + 2,
			-header		=> 1,
			-separator	=> ':',
			-selectmode	=> 'extended',
		)->pack(-expand => 1,
			-fill => 'both');

		$obj->Advertise("tree" => $obj->{tree});
	}

	unless(defined $obj->{tree_buttons}) {
		my $c = -1;
		foreach my $name ($obj->{textcolumn}, @{$obj->{fields}}) {
			$c++;
			$obj->{tree_buttons}->{$name} = $obj->{tree}->ResizeButton( 
			  -text 	=> $name, 
			  -relief 	=> 'flat', 
			  -border	=> -2,
			  -pady 	=> -10, 
			  -padx 	=> 10, 
			  -widget 	=> \$obj->{tree},
			  -column 	=> $c,
			);

			$obj->{tree}->headerCreate($c, 
				-itemtype => 'window',
				-widget	  => $obj->{tree_buttons}->{$name}, 
			);

			$obj->{tree}->columnWidth($c, $obj->{columnWidths}->[$c]) 
				if(defined $obj->{columnWidths}->[$c]);

		}	
	}

	$obj->{fieldtypes} = $obj->getFieldTypes
		unless(defined $obj->{fieldtypes});

	$obj->{tree}->configure(-command => $obj->{callback})
		if(defined $obj->{callback} and ref $obj->{callback} eq 'CODE');


	$obj->remember();
	@{$obj->{ListOfAllEntries}} = ();
	$obj->{tree}->delete('all');
	$obj->list();
	$obj->{tree}->focus;
	$obj->select_entrys($obj->{FoundEntrys});

	if($obj->{zoom} and scalar @{$obj->{FoundEntrys}}) {
		$obj->{zoom} = 0;
		$obj->zoom();
	}
	$obj->Unbusy;
}

# ------------------------------------------
sub select_entrys {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	$obj->{FoundEntrys} = shift || return $obj->{FoundEntrys};
	$obj->{tree}->selectionClear();
	foreach (@{$obj->{FoundEntrys}}) { 
		$obj->{tree}->selectionSet($_);
		
	}
}

# ------------------------------------------
sub remember {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my $rem = shift;
	my $ret;
	unless( $rem ) {
		foreach my $entry (@{$obj->{ListOfAllEntries}}) {
			$ret->{status}->{$entry} = $obj->{tree}->{status}->{$entry} = $obj->{tree}->getmode($entry);
		}
		my $i = 0;
		my $conf;
		foreach my $spalte (@{$obj->{fields}}) {
			push(@{$ret->{widths}}, $obj->{tree}->columnWidth($i++));
		}
	} else {
		$obj->{tree}->{status} = $rem->{status}
			if(defined $rem->{status});
		$obj->{widths} = $rem->{widths}
			if(defined $rem->{widths});
		$obj->refresh('redraw');
	}
	return $ret;
}

# ------------------------------------------
sub make_tree_list {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my %parms = @_;

	my @parent_ids = @{ $parms{$obj->{parent_id}} };
		
	my $treeval = '';
	foreach (@parent_ids) {
		$treeval .= "$_:";
	}
	$treeval .= $parms{$obj->{idx}};
	push @{$obj->{ListOfAllEntries}}, $treeval;
}

# ------------------------------------------
sub get_id {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my $w = shift || return error('No Widget!');
	my $ev = $w->XEvent;
	my $id = $w->nearest($ev->y);
	$obj->{tree}->anchorSet($id);
	$obj->{tree}->selectionClear();
	$obj->{tree}->selectionSet($id);
	my ($col, $col_nr) = &x2col( $ev->x + $w->xview() );
	my $wert = $w->itemCget($id, $col_nr, -text);

	return ($id, $col, $col_nr, $wert);
}

# ------------------------------------------
sub x2col {                                                       
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my $x = shift;
	$obj->{tree} = shift || $obj->{tree};
	my ($c);
	my $von = 0;
	foreach (@{$obj->{fields}}) {
		my $breite = $obj->{tree}->columnWidth( $c++);
		my $bis = $von + $breite;
		return ($_, $c - 1) 
			if($x >= $von && $x <= $bis);
		$von += $breite; 
	}
}

# ------------------------------------------
sub zoom {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	return unless(scalar @{$obj->{FoundEntrys}});
	$obj->{zoom} = ($obj->{zoom} ? undef : 1);
	if($obj->{zoom}) {
		foreach my $entry (sort @{$obj->{ListOfAllEntries}}) {
			next unless($entry);
			my $search = $entry;
			$search =~ s/\:/\\:/sig;
			unless(grep(/^$search/, @{$obj->{FoundEntrys}})) {
				unless($obj->{tree}->infoHidden($entry)) {
					$obj->{tree}->hide('entry', $entry);
					push(@{$obj->{HiddenEntrys}}, $entry);
				}
			}
		}
	} else {
		foreach my $entry (@{$obj->{HiddenEntrys}}) {
			$obj->{tree}->show('entry', $entry)
				if($obj->{tree}->infoHidden($entry));
		}
		@{$obj->{HiddenEntrys}} = qw//;
	}
}


# ------------------------------------------
sub makeSql {
# ------------------------------------------
	my $obj = shift || return error('No Object');

	my $sql = sprintf('select %s, %s, %s from %s %s ORDER BY %s, %s',
			$obj->{idx}, $obj->{textcolumn},join(',', @{$obj->{fields}}),
			$obj->{table}, 
			(defined $obj->{where} ? $obj->{where} : ''),
			$obj->{parent_id}, $obj->{idx}
			);
	$obj->debug($sql);
	return $sql;
}

# ------------------------------------------
sub getFieldTypes {
# ------------------------------------------
	my $obj 	= shift or return warn("No object");
	my $dbh 	= $obj->{dbh};
	my $table	= $obj->{table};

	return $obj->{fieldtypes}
		if(defined $obj->{$table}->{fieldtypes});

	
	my $ret = $dbh->selectall_hashref("show fields from $table", 'Field')
		or return $obj->debug($dbh->errstr);

	return $ret;
}


# ------------------------------------------
sub list {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my $len = $1 if($obj->getFieldTypes->{$obj->{idx}}->{Type} =~ /(\d+)/);

	$obj->{dbtree}->do_query;	
	$obj->{dbtree}->tree;

	my $sql = $obj->makeSql;
        my $DATA = $obj->{dbh}->selectall_hashref( $sql, $obj->{idx} ) 
        		or return error($obj->{dbh}->errstr);
	my $row = $DATA->{$obj->{start_id}} || $DATA->{sprintf("%0${len}d", $obj->{start_id})};		


	$obj->{tree}->add($obj->{start_id}, 
		-data => $row,
		-text => $obj->parse_text($row->{$obj->{textcolumn}}, $obj->{textcolumn}), 
	);
	my $c = 1;
	foreach my $field (@{$obj->{fields}}) {
		$obj->{tree}->itemCreate( 
			$obj->{start_id}, $c++, 
			-text => $obj->parse_text($row->{$field}, $field) 
		);
	}


	foreach my $id (@{$obj->{ListOfAllEntries}}) { 
		my $item_id = (split( /:/, $id ))[-1];
		my $row = $DATA->{$item_id} || $DATA->{sprintf("%0${len}d", $item_id)};		
		next if(int($row->{$obj->{idx}}) eq $obj->{start_id});

		$obj->{tree}->add($id, 
			-data => $row, 
			-text => $obj->parse_text($row->{$obj->{textcolumn}}, $obj->{textcolumn}) );

		my $c = 1;
		foreach my $field (@{$obj->{fields}}) {
			$obj->{tree}->itemCreate( $id, $c++, -text => $obj->parse_text($row->{$field}, $field) );
		}
	}

	# Draw Indicators
	$obj->{tree}->autosetmode;

	foreach my $entry (@{$obj->{ListOfAllEntries}}) {
		$obj->{tree}->close($entry)
			if(defined $obj->{tree}->{status}->{$entry} and $obj->{tree}->{status}->{$entry} eq 'open');
	}

}

# ------------------------------------------
sub close_all {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	foreach my $entry (sort @{$obj->{ListOfAllEntries}}) {
		$obj->{tree}->close($entry);
	}
}

# ------------------------------------------
sub to_parent_open{
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my $entry = shift;
	my $path = '0';
	foreach my $e (split(/:/, $entry)) {
		next unless($e);
		$path .= sprintf(':%d', $e);		
		$obj->{tree}->open($path);
	}
}

# ------------------------------------------
sub getFields {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my $table = shift || return error('No Table!');

	my $sth = $obj->{dbh}->prepare("select * from $table limit 0,0");
	$sth->execute();
	my $field_names = $sth->{'NAME'};

	return $field_names;
}
 
# ------------------------------------------
sub parse_text {
# ------------------------------------------
	my $obj = shift;
	my $text = shift || return ' ';
	my $field = shift || return error('No FieldName!');
	my $maxchars = 
		(ref $obj->{maxchars} eq 'HASH' 
			? $obj->{maxchars}->{$field} 
			: $obj->{maxchars} 
		) || 0;
	$text = substr($text, 0, $maxchars).'...' 
		if($maxchars and length($text)>$maxchars);
	$text =~ s/(\r|\n)//sig;
	return $text;
} 

# ------------------------------------------
sub listEntrys {
# ------------------------------------------
	my $obj = shift;
	return $obj->{ListOfAllEntries};
} 


# ------------------------------------------
sub debug {
# ------------------------------------------
	my $obj = shift;
	my $msg = shift || return;
	printf("\nInfo: %s\n", $msg); 
} 

# ------------------------------------------
sub error {
# ------------------------------------------
	my $msg = shift;
        my ($package, $filename, $line, $subroutine, $hasargs,
                $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller(1);
	my $error = sprintf("ERROR in %s:%s #%d: %s",
                $package, $subroutine, $line, sprintf($msg, @_));
	warn $error;
	return undef;
} 


1;

__END__

=head1 NAME

Tk::DBI::Tree - Megawidget to display a table column in a tree.

=head1 SYNOPSIS

	use Tk;
	use Tk::DBI::Tree;
	
	my $top = MainWindow->new;
	my $tkdbi = $top->DBITree(
			-table		=> 'table',
			-index		=> 'id',
			-fields		=> [qw(col1 col2 col3)],
			-where		=> 'WHERE mammut == 1',
			-dbh   		=> $dbh,
			-parent_id	=> 'parent_id',
			-start_id	=> 1,
		)->pack(expand => 1, -fill => 'both');
	
	MainLoop;

=head1 DESCRIPTION

This is a megawidget to display a sql statement from your database in a TreeTable. 
The features are:
- every column has a ResizeButton for flexible width

=cut


=head1 WIDGET-SPECIFIC OPTIONS

=head2 -dbh => $dbh

A database handle, this will return a error if not defined.



=head2 -table 

The table to display.



=head2 -debug [I<0>|1]

This is a switch for debug output to the normal console (STDOUT)



=head2 -fields [col0, col1, col2, ...]

Fields to Display.


=head2 -textcolumn text

Text column to display in Tree..


=head2 -start_id 

The id, was start to work on the tree.


=head2 -columnWidths [colWidth_0, colWidth_1, colWidth_2, ...]

Default width for field columns.

=head2 -maxchars number or {col1 => number}

Maximum displaying chars in the cells. Global or only in named columns.
I.E.:

  -maxchars	=> { 
	descr => 25, 
	name => 10,
  },

=head1 METHODS

These are the methods you can use with this Widget.


=head2 $DBITree->refresh;

Refresh the tree.

=head2 $DBITree->close_all;

close all trees.

=head2 $DBITree->ListEntrys;

This returnd a sorted ref array with all entrys in tree.

=head2 $DBITree->select_entrys([en1, en2, en3, ...]);

This returnd an sorted ref array with all selected entrys 
in tree or you can give an array with entrys to select.


=head2 $DBITree->remember( $hash );

This method is very usefull, when you will remember on the last tree status 
and widths from the resize buttons. This returnd a ref hash with following 
keys, if this call without parameter. 

=over 4

=item widths - an ref array with from every column

=item stats - a ref hash with status (open close none) from every entry

=back

You can give a old Hash (may load at program start) and the tree is remember on this values.

I.E.:

  $tree->rembember( $tree->rembember );

  # or ...
  
  $tree->remember( {
	status => {
		'0:1' => 'open',
		'0:1:2' => 'close',
		...
  	},
	widths => [165, 24, 546],
  } );
  

=head1 ADVERTISED WIDGETS


=head2 'tree' => Tree-Widget


This is a normal Tree widget. I.e.:

	$DBITree->Subwidget('tree')->configure(
		-command => sub{ printf "This is id: %s\n", $_[0] },
	};


=head2 'HB_<column number>' => Button-Widget

This is a (Resize)Button widget. This displays a Compound image with text and image.

=head1 CHANGES

  $Log: Tree.pm,v $


=head1 AUTHOR

Copyright (C) 2003 , Frank (xpix) Herrmann. All rights reserved.

http://www.xpix.de

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 KEYWORDS

Tk::DBI::*, Tk::ResizeButton, Tk::Tree, DBIx::Tree


__END__
