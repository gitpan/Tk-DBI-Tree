package Tk::DBI::Tree;
#------------------------------------------------
# automagically updated versioning variables -- CVS modifies these!
#------------------------------------------------
our $Revision           = '$Revision: 1.4 $';
our $CheckinDate        = '$Date: 2003/05/11 16:33:47 $';
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
 	$obj->{command}		= delete $args->{'-command'};
	$obj->{parent_id}	= delete $args->{'-parent_id'} 	|| return error("No Parent_id!");
	$obj->{columnWidths}	= delete $args->{'-columnWidths'};
	$obj->{maxchars}	= delete $args->{'-maxchars'};
	$obj->{colNames}	= delete $args->{'-colNames'};
	$obj->{entry_create_cb}	= delete $args->{'-entry_create_cb'};
	my $h_style		= delete $args->{'-highlight'}	|| [-foreground => 'blue'];
	my $n_style		= delete $args->{'-normal'}	|| [-foreground => 'black'];
	$obj->{highlight}	= $obj->ItemStyle('imagetext', @{$h_style});
	$obj->{normal}		= $obj->ItemStyle('imagetext', @{$n_style});
	
	$obj->SUPER::Populate($args);

	
	my %specs;
	$specs{refresh} 	= [qw/METHOD refresh 		Refresh/, 		undef];
	$specs{close_all}	= [qw/METHOD close_all 		Close_all/, 		undef];
	$specs{listEntrys}	= [qw/METHOD listEntrys 	ListEntrys/, 		undef];
	$specs{remember}	= [qw/METHOD remember 		Remember/, 		undef];
	$specs{select_entrys}	= [qw/METHOD select_entrys 	Select_entrys/, 	undef];
	$specs{info}		= [qw/METHOD info 		Info/, 			undef];
	$specs{infozoom}	= [qw/METHOD infozoom 		InfoZoom/,		undef];
	$specs{color_all}	= [qw/METHOD color_all 		Color_All/, 		undef];
	$specs{get_id}		= [qw/METHOD get_id 		Get_Id/, 		undef];
	
        $obj->ConfigSpecs(%specs);


	# Bildet den Tree in einem Array ab
	$obj->{dbtree} = DBIx::Tree->new( 
		connection => $obj->{dbh}, 
	        table      => $obj->{table}, 
	        method     => sub { $obj->make_tree_list(@_) },
	        columns    => [$obj->{idx}.'+0', $obj->{textcolumn}, $obj->{parent_id}.'+0'],
	        start_id   => $obj->{start_id},
        ); 

	$obj->{tree} = $obj->Scrolled('Tree',
		-scrollbars 	=> 'ose',
		-columns	=> scalar @{$obj->{fields}} + 1,
		-header		=> 1,
		-separator	=> ':',
		-selectmode	=> 'single',
	)->pack(-expand => 1,
		-fill => 'both');

	$obj->Advertise("tree" => $obj->{tree});

} # end Populate


# Class private methods;
# ------------------------------------------
sub refresh {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my $redraw = shift;

	unless(defined $obj->{tree_buttons}) {
		my $c = -1;
		foreach my $name ($obj->{textcolumn}, @{$obj->{fields}}) {
			$c++;
			$obj->{tree_buttons}->{$name} = $obj->{tree}->ResizeButton( 
			  -text 	=> $obj->{colNames}->[$c] || $name, 
			  -relief 	=> 'flat', 
			  -border	=> -2,
			  -pady 	=> -10, 
			  -padx 	=> 10, 
			  -widget 	=> \$obj->{tree},
			  -column 	=> $c,
			);

			$obj->Advertise(sprintf("HB_%s",$name) => $obj->{tree_buttons}->{$name});

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

	$obj->{tree}->configure(-command => $obj->{command})
		if(defined $obj->{command} and ref $obj->{command} eq 'CODE');


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
}

# ------------------------------------------
sub select_entrys {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	$obj->{FoundEntrys} = shift || return $obj->{FoundEntrys};
	$obj->color_all();

	unless(grep(/\:/, @{$obj->{FoundEntrys}})){
		my @FoundEntrys;
		foreach my $id (sort @{$obj->{FoundEntrys}} ) {
			$id = int($id);
			foreach my $entry (sort @{$obj->listEntrys}) {
				if($entry =~ /\:${id}$/) {
					push(@FoundEntrys, $entry);
					last;
				}
			}
		}
		$obj->{FoundEntrys} = \@FoundEntrys;	
	}		

	foreach (@{$obj->{FoundEntrys}}) { 
		return error(sprintf('Item <%s> doesnt exist!',$_))
			unless($obj->{tree}->infoExists($_));
		$obj->to_parent_open($_);
		$obj->color_row($_, $obj->{highlight});
	}
	my $entry = $obj->{FoundEntrys}->[0];
	$obj->{tree}->anchorSet($entry);
	$obj->{tree}->selectionSet($entry);
	$obj->{tree}->see($entry);
}

# ------------------------------------------
sub color_row {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my $id = shift || return error('No Id');
	my $color = shift || $obj->{normal};

	my $i = 0;
	foreach ($obj->{textcolumn}, @{$obj->{fields}}) {
		$obj->{tree}->itemConfigure($id, $i, -style => $color);
		$i++;
	}
}


# ------------------------------------------
sub color_all {
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my $color = shift || $obj->{normal};

	foreach my $entry (sort @{$obj->{ListOfAllEntries}}) {
		$obj->color_row($entry, $color);
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
			my $mode = $obj->{tree}->getmode($entry);
			$ret->{status}->{$entry} = $obj->{tree}->{status}->{$entry} = $mode
				unless($mode eq 'none');
		}
		my $i = 0;
		my $conf;
		foreach my $spalte ($obj->{textcolumn}, @{$obj->{fields}}) {
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
	my @parent_ids = @{ $parms{parent_id} };
		
	my $treeval = '';
	foreach (@parent_ids) {
		$treeval .= "$_:";
	}
	$treeval .= $parms{id};
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
	my ($col, $col_nr) = $obj->x2col( $ev->x + $w->xview() );
	my $wert = $w->itemCget($id, $col_nr, -text);

	return ($id, $col, $col_nr, $wert);
}

# ------------------------------------------
sub x2col {                                                       
# ------------------------------------------
	my $obj = shift || return error('No Object');
	my $x = shift;
	my $c = 0;
	my $von = 0;
	foreach my $name ($obj->{textcolumn}, @{$obj->{fields}}) {
		my $breite = $obj->{tree}->columnWidth( $c);
		my $bis = $von + $breite;
		return (($obj->{colNames}->[$c] || $name), $c) 
			if($x >= $von && $x <= $bis);
		$von += $breite; 
		$c++;
	}
}

# ------------------------------------------
sub infozoom {
# ------------------------------------------
	my $obj = shift || return error('No Object');
 	return $obj->{zoom};
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

	if($DBIx::Tree::VERSION < 1) {
		$obj->{dbtree}->do_query;	
		$obj->{dbtree}->tree;
	} else {
		$obj->{dbtree}->traverse;	
	}
	
	my $sql = $obj->makeSql;
        my $DATA = $obj->{dbh}->selectall_hashref( $sql, $obj->{idx} ) 
        		or return error($obj->{dbh}->errstr);
	my $row = $DATA->{$obj->{start_id}} || $DATA->{sprintf("%0${len}d", $obj->{start_id})};		

	foreach my $id (sort @{$obj->{ListOfAllEntries}}) { 
		my $item_id = (split( /:/, $id ))[-1];
		my $row = $DATA->{$item_id} || $DATA->{sprintf("%0${len}d", $item_id)};		
		$obj->{tree}->add($id, 
			-itemtype	=> 'imagetext', 
			-data 		=> $row, 
			-text 		=> $obj->parse_text($row->{$obj->{textcolumn}}, $obj->{textcolumn}),
			-style 		=> $obj->{normal},
			 );

		&{$obj->{entry_create_cb}}($obj->{tree}, $id, $row)
			if(defined $obj->{entry_create_cb} and ref $obj->{entry_create_cb} eq 'CODE');

		my $c = 1;
		foreach my $field (@{$obj->{fields}}) {
			$obj->{tree}->itemCreate( $id, $c++, 
				-text => $obj->parse_text($row->{$field}, $field),
				-style => $obj->{normal},
			);
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
	my $path = $obj->{start_id};
	foreach my $e (split(/\:/, $entry)) {
		next if($e eq $obj->{start_id});
		$path .= sprintf(':%d', $e);		
		$obj->{tree}->open($path);
	}
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
sub info {
# ------------------------------------------
	my $obj = shift;
	my $typ = shift || 'data';
	my $entry = shift;
	return $obj->{tree}->info(${typ}, $entry);
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


=head1 NAME

Tk::DBI::Tree - Megawidget to display a table column in a tree.

=head1 SYNOPSIS

  use Tk;
  use Tk::DBI::Tree;

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
		)->pack(-expand => 1, 
		  	-fill => 'both');

  MainLoop;

=head1 DESCRIPTION

This is a megawidget to display a sql statement from your database in a tree view
widget. When you've got one of those nasty self-referential tables that you
want to bust out into a tree, this is the module to check out.

=head1 WIDGET-SPECIFIC OPTIONS

=head2 -dbh => $ref_on_database_handle

A database handle, this will return an error if it is'nt defined.

=head2 -debug => [I<0>|1]

This is a switch to turn on debug output to the standard console (STDOUT)

=head2 -table => 'tablename'

The table to display.

=head2 -idx => 'index_column'

The index column from the table.

=head2 -fields => [col0, col1, col2, ...]

List of additional fields to display. 

=head2 -colNames => [col0, col1, col2, ...]

List of alternative names for every column. This will display on header.

=head2 -where => 'WHERE foo == 1, ...'

Additional where statement for choice rows in table.

=head2 -textcolumn => colname

The name of the column to be displayed in the tree..

=head2 -start_id => integer

The id, where the widget will start to create the tree. Default is 1.

=head2 -columnWidths => [colWidth_0, colWidth_1, colWidth_2, ...]

Default field column width.

=head2 -command => sub{ ... }

Callback on TreeWidget at browsing.

=head2 -entry_create_cb => sub{ ... }

Callback if a entry created. The routine have 2 parameters:

=over 4

=item entry - a ref to created entry

=item data - a ref hash with row information.

=back

i.e;

  -entry_create_cb => sub{
	my($w, $path, $row) = @_;
	if(exists $DOC->{ $row->{id} } and exists $EVENT->{ $row->{id} } ) {
		$w->entryconfigure($path, -image => $pics{'icon_document_event'});
	}
  },

=head2 -highlight => I<[-foreground => 'blue']>

Style for founded Entries.

=head2 -normal => I<[-foreground => 'black']>

Default style for Entries.

=head2 -maxchars => number or {col1 =number}

Maximum number of characters to be displayed within the cells. Global
validity or set only for named columns.
I.E.:

  -maxchars => {
	 descr => 25,
	 name => 10,
  },
  # or ....
  -maxchars => 25, # global for all fields

=head1 METHODS

These are the methods you can use with this Widget.

=head2 $DBITree->refresh('reload');

Refresh the tree. if you call this method with the parameter reload 
then this will reload the table from database.

=head2 $DBITree->close_all;

close all tree branches.

=head2 $DBITree->info('anchor, bbox, children, B<data>, dragsite, dropsite ...', $id);

This is a wrapper to the HList Method ->info. The default method is info('data', ...).
Please read the manual from Tk::HList.

=head2 $DBITree->ListEntrys;

This returnd a sorted ref array with all entrys in the tree.

=head2 $DBITree->select_entrys([en1, en2, en3, ...]);

This returns a sorted ref array with all selected entries
in the tree or you can set an array of selected entries.
Also you can use only the id's, i.e.:

  $dbitree->select_entrys(qw/1:2 1:3 1:4/);
  
  # or ... 
  
  $dbitree->select_entrys(qw/2 3 4/);

These is friendly if you use i.e. a statement 'select id from table where foo == bla'
and you have only the id's without the pathinformation. Tk::DBI::Tree know, select only
the entries have at last position this id in path.

=head2 $DBITree->zoom;

Shrink or unshrink tree to display only founded entries.

=head2 $DBITree->infozoom;

Returnd true if zoom active.

=head2 $DBITree->color_all([style]);

Set all entries to normal style without parameters. 
You can put a new Style to all entries.

i.e:

  $DBITree->color_all([-background => 'gray50']);



=head2 $DBITree->get_id;

select the row under mouseposition and returnd following parameters.

=over 4

=item path - The path from the entry under mouseposition.

=item col - Column name under mouseposition.

=item path - Column number under mouseposition.

=item value - Cell value under mouseposition.

=back


=head2 $DBITree->remember( $hash );

This method is very useful, when you want to remember the last tree status
and column widths for the resize button. This returns a ref hash with following
keys, if this call is done without parameters.

=over 4

=item widths - a ref array including the width of each column.

=item stats - a ref hash with status information(open close none) for each entry.

=back

You can give an old Hash (may eval-load at program start) and the tree
remembers this status.

I.E.:

  $tree->rembember( $tree->rembember );

  # or ...

  $tree->remember( {
	 status => {
		  '0:1' ='open',
		  '0:1:2' ='close',
		  ...
	 },
 	 widths =[165, 24, 546],
  } );


=head1 ADVERTISED WIDGETS

=head2 'tree' => Tree-Widget

This is a normal Tree widget. I.e.:

 $DBITree->Subwidget('tree')->configure(
	-background => 'gray50',
 };

=head2 'HB_<column name>' => ResizeButton-Widget

This is a (Resize)Button widget.

=head1 CHANGES

  $Log: Tree.pm,v $
  Revision 1.4  2003/05/11 16:33:47  xpix
  * new option -colNames
  * new option -entry_create_cb
  * new option -higlight
  * new option -normal
  * new method info
  * new method infozoom
  * new method color_all
  * new method get_id
  ! much bugfixes
  * better select_entrys (without pathinformation)

  Revision 1.3  2003/05/05 16:02:06  xpix
  * correct the documentation and write a little more ;-)

  Revision 1.2  2003/05/04 23:38:25  xpix
  ! bug in make_tree_list

  Revision 1.1  2003/05/04 20:52:13  xpix
  * New Widget for display a table in a tree

=head1 AUTHOR

Copyright (C) 2003 , Frank (xpix) Herrmann. All rights reserved.

http://www.xpix.de

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 KEYWORDS

Tk::DBI::*, Tk::ResizeButton, Tk::Tree, DBIx::Tree

__END__
