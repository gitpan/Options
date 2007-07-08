#!/usr/bin/env perl

##################################################################
# Options.pm 1.5
# 
# A perl module to provide better support for command-line option
# parsing, hopefully better than GetOpts.
# 
# Copyright (C) 2005-2007 by Phil Christensen
##################################################################

package Options;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '1.5';

=head1 NAME

Options -   A perl module to provide better support for command-line option
			parsing, hopefully better than GetOpts.

=head1 SYNOPSIS

	use Options;
	
	$options = new Options(params => [
							['port', 'p', undef, 'The port to connect to.'],
							['host', 'h', 'localhost', 'The host to connect to.']
							],
							flags =>  [
							['secure', 's', 'Use SSL for encryption.'],
							['quit', 'q', 'Quit after connecting.'],
							]);
	
	# Parse the default option source (@ARGV)
	%results = $options->get_options();
	
	# Provide usage
	if($options->get_result('help')){
		$options->print_usage();
		exit(1);
	}

=head1 CONTENTS

 Options 1.50

=head1 DESCRIPTION

 Options was created to somewhat emulate the syntax of the Twisted Python's
 core usage library of the same name. It provides a parser for command-line
 options that is integrated with an automatic usage generator. Support exists
 for both flags and parameters, in long and short form, required parameters,
 and default params.

=head2 EXPORT

None by default.

=head1 GETTING OPTIONS

=over 4

=item new Options()

 Create a new instance of the Options class. To do so, pass the constructor
 two optional, named arguments. 'params' are command-line switches with
 arguments, while flags are boolean switches. (duh.)

 Each argument consists of an anonymous array reference which contains
 an anonymous array for each option you wish to support.

 Params arrays must be four elements long, consisting of the long and short
 versions of the switch, a default value, and a description to be printed in
 the usage guide. If the default value is specified as "undef", it becomes a
 required value, and the program will not continue without it. Options without
 defaults can specify the empty string ("") to omit the default.

 Flags arrays are simpler, and omit the default element.

=back

=cut
sub new{
	my $self = {};
	my $class = shift;
	bless $self, $class;
	my %passed_params = @_;
	if($passed_params{'params'}){
		$self->{'params'} = $passed_params{'params'};
	}
	else{
		$self->{'params'} = [];
	}
	
	if($passed_params{'flags'}){
		$self->{'flags'} = $passed_params{'flags'};
	}
	else{
		$self->{'flags'} = [];
	}
	$self->{'exit'} = 1;
	return $self;
}

=over 4

=item $options->get_options()

 This method is called with no arguments, and begins the parsing of
 the global variable @ARGV, or an array passed as the first argument
 to the function. When finished, it returns a hash where the
 keys are the long option names, and the values are the result of the
 parse, i.e., strings for params, and boolean values (1 or 0 actually)
 for flag-type options.

 If the parser encounters an unknown flag, or a bare word without a
 recognized switch before it, these are left in the @ARV array in the
 order they are found, so that a script can do additional processing of
 @ARGV.

 If the result is missing a required parameter, the module prints the
 usage table, and exits with a 1 status code.

=back

=cut
sub get_options{
	my $self = shift;
	
	my @args = @_;
	unless(@args){
		@args = @ARGV;
	}
	$self->{'last_args'} = \@args;
	
	my @unrecognized = ();
	my %results = ();
	
	for(my $i = 0; $i <= $#args; $i++){
		my $item = $args[$i];
		if($item =~ m/^(\-{1,2})(.*)$/){
			my $item_text = $2;
			my $result;
			if($1 eq '--'){
				$result = $self->_is_supported_option($item_text, 1);
			}
			elsif(length($item_text) == 1){
				$result = $self->_is_supported_option($item_text, 0);
			}
			else{
				no warnings;
				my @flags = split(undef, $item_text);
				use warnings;
				
				foreach my $flag (@flags){
					$result = $self->_is_supported_option($flag, 0);
					# if this is a valid flag, it can be grouped
					if($result){
						if(scalar(@{$result->[1]}) == 3){
							push @args, "-$flag";
						}
						else{
							my $param = $result->[1][1];
							$self->_found_error("Parameter '$param' found in grouped flags '-$item_text'.");
						}
					}
					else{
						$self->_found_error("'$flag' is not a supported flag.");
					}
				}
				next;
			}
			if($result){
				my $type = $result->[0];
				my @option = @{$result->[1]};
				if($type eq 'params'){
					if($args[$i + 1] and $args[$i + 1] !~ m/^\-{1,2}(.*)/){
						my $current = $results{$option[0]};
						my $arg = $args[++$i];
						if($current){
							if(ref($current) eq 'ARRAY'){
								my @list = @$current;
								push(@list, $arg);
								$results{$option[0]} = \@list;
							}
							elsif(ref($current) eq ''){
								$results{$option[0]} = [$current, $arg];
							}
						}
						else{
							$results{$option[0]} = $arg;
						}
					}
					else{
						$self->_found_error("Missing argument for '$option[0]' parameter.");
					}
				}
				else{
					$results{$option[0]} = 1;
				}
			}
			else{
				push(@unrecognized, $item);
			}
		}
		else{
			push(@unrecognized, $item);
		}
	}
	
	#then check and see if any required params were missing, and fill in defaults
	foreach my $item (@{$self->{'params'}}){
		my @option = @{$item};
		unless($results{$option[0]}){
			if(defined($option[2])){
				$results{$option[0]} = $option[2];
			}
		}
		unless(defined($option[2])){
			unless($results{$option[0]}){
				$self->_found_error("Missing required option '$option[0]'");
			}
		}
	}
	
	unless(@_){
		@ARGV = @unrecognized;
	}
	$self->{'results'} = \%results;
	return %results;
}

=over 4

=item $options->get_result(option)

 Although get_options returns a hash, and that is an
 acceptable way to use the results, this function provides
 some level of convenience when dealing with options that
 may return a reference to a list of results for that option.
 When called in a list context, this will return a list of
 results, even if only one argument was provided.
 However, calling it in a scalar context when there are
 multiple arguments will be, shall we say, disappointing.

=back

=cut
sub get_result{
	my $self = shift;
	my $option = shift;
	my %results = %{$self->{'results'}};
	my $result = $results{$option};
	if(ref($result) eq 'ARRAY'){
		my @result = @$result;
		return @result;
	}
	else{
		return (wantarray ? ($result) : $result);
	}
}

=over 4

=item $options->print_usage($optional_message)

 Options will automatically display usage information if a required
 parameter is omitted, but this method can be used to implement a
 --help parameter.

=back

=cut
sub print_usage{
	my $self = shift;
	my $reason = shift;
	
	my $err_handle;
	if($self->{'err_handle'}){
		$err_handle = $self->{'err_handle'};
	}
	else{
		$err_handle = \*STDERR;
	}
	
	my $app = $self->{'last_args'}[0];
	unless(defined($app)){
		$app = $0;
	}
	
	print $err_handle "$reason\n\n";
	print $err_handle "Usage: $app [options]\n";
	print $err_handle "Options:\n";
	
	my $item;
	my @rows = ();
	my $max_width = 0;
	
	my $flags = $self->{'flags'};
	foreach $item (@$flags){
		my @parts = @$item;
		my $first_col = "  -$parts[1], --$parts[0]";
		if(length($first_col) > $max_width){
			$max_width = length($first_col);
		}
		my $row = [$first_col, $parts[2]];
		push(@rows, $row);
	}
	
	my $params = $self->{'params'};
	foreach $item (@$params){
		my @parts = @$item;
		my $first_col = "  -$parts[1], --$parts[0]";
		if(length($first_col) > $max_width){
			$max_width = length($first_col);
		}
		my $default = (defined($parts[2]) && $parts[2] ne '' ? "[default: $parts[2]]" : "");
		my $required = (defined($parts[2]) ? "" : "[required]");
		my $row = [$first_col, "$parts[3] $default   $required"];
		push(@rows, $row);
	}
	
	foreach $item (@rows){
		my @row = @$item;
		print $err_handle _pad($row[0], $max_width + 2), $row[1], "\n";
	}
}

=head1 AUTHOR

Phil Christensen, E<lt>phil@bubblehouse.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005-2007 by Phil Christensen

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.


=cut

# A private internal function that checks to see if a specified
# option will be sought on the command line (i.e., whether this
# instance was constructed with a given option)
sub _is_supported_option{
	my $self = shift;
	my $option = shift;
	my $is_long = shift;
	foreach my $key('params', 'flags'){
		my $options = $self->{$key};
		foreach my $item (@$options){
			my @parts = @$item;
			if($is_long){
				if($parts[0] eq $option){
					return [$key, $item];
				}
			}
			else{
				no warnings;
				my @letters = split(undef, $option);
				use warnings;
				foreach my $letter (@letters){
					if($parts[1] eq $letter){
						return [$key, $item];
					}
				}
			}
		}
	}
	return 0;
}


#
# A private internal function to assist in making the
# usage guide come out all pretty-looking.
#
sub _pad{
	my $text = shift;
	my $length = shift;
	if($length > length($text)){
		return $text . (" " x ($length - length($text)));
	}
	return $text;
}

sub _found_error{
	my $self = shift;
	my $reason = shift;
	$self->print_usage($reason);
	if($self->{'exit'}){
		exit(1);
	}
	die($reason);
}

1;
