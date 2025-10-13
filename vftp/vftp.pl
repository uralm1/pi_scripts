#!/usr/bin/perl -wT

use strict;
use warnings;
use FindBin;
my $script_path;
BEGIN {
if ($FindBin::Bin =~ /(.*)/) {
  $script_path = $1;
} else {
  die "Invalid script path";
}}

use lib "$script_path/lib";

use Ural::VFtp::Server;

my $ftps = Ural::VFtp::Server->run(["-C=$FindBin::Bin/vftp.conf", '-s']);
