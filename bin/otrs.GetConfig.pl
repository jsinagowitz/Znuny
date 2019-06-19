#!/usr/bin/perl
# --
# Copyright (C) 2001-2019 OTRS AG, https://otrs.com/
# --
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

use strict;
use warnings;

use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . '/Kernel/cpan-lib';
use lib dirname($RealBin) . '/Custom';

use Kernel::Config;
use Kernel::System::Encode;
use Kernel::System::Log;
use Kernel::System::Main;

# common objects
my %CommonObject = ();
$CommonObject{ConfigObject} = Kernel::Config->new();
$CommonObject{EncodeObject} = Kernel::System::Encode->new(%CommonObject);
$CommonObject{LogObject}    = Kernel::System::Log->new(
    LogPrefix => 'OTRS-otrs.GetConfig',
    %CommonObject,
);
$CommonObject{MainObject} = Kernel::System::Main->new(%CommonObject);

# print wanted var
my $Key = shift || '';
if ($Key) {
    chomp $Key;
    if ( ref( $CommonObject{ConfigObject}->{$Key} ) eq 'ARRAY' ) {
        for ( @{ $CommonObject{ConfigObject}->{$Key} } ) {
            print "$_;";
        }
        print "\n";
    }
    elsif ( ref( $CommonObject{ConfigObject}->{$Key} ) eq 'HASH' ) {
        for my $SubKey ( sort keys %{ $CommonObject{ConfigObject}->{$Key} } ) {
            print "$SubKey=$CommonObject{ConfigObject}->{$Key}->{$SubKey};";
        }
        print "\n";
    }
    else {
        print $CommonObject{ConfigObject}->{$Key} . "\n";
    }
}
else {

    # print all vars
    for ( sort keys %{ $CommonObject{ConfigObject} } ) {
        print $_. ":";
        if ( ref( $CommonObject{ConfigObject}->{$_} ) eq 'ARRAY' ) {
            for ( @{ $CommonObject{ConfigObject}->{$_} } ) {
                print "$_;";
            }
            print "\n";
        }
        elsif ( ref( $CommonObject{ConfigObject}->{$_} ) eq 'HASH' ) {
            for my $Key ( sort keys %{ $CommonObject{ConfigObject}->{$_} } ) {
                print "$Key=$CommonObject{ConfigObject}->{$_}->{$Key};";
            }
            print "\n";
        }
        else {
            print $CommonObject{ConfigObject}->{$_} . "\n";
        }
    }
}