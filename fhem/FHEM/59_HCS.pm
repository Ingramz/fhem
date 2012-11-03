################################################################
# $Id: $
#
#  (c) 2012 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################

package main;
use strict;
use warnings;

sub HCS_Initialize($$);
sub HCS_Define($$);
sub HCS_Undef($$);
sub HCS_checkState($);
sub HCS_Get($@);
sub HCS_Set($@);
sub HCS_setState($$);
sub HCS_getValves($$);

my %gets = (
  "valves"    => "",
);

my %sets = (
  "interval"          => "",
  "on"                => "",
  "off"               => "",
  "valveThresholdOn"  => "",
  "valveThresholdOff" => "",
);

#####################################
sub
HCS_Initialize($$)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "HCS_Define";
  $hash->{UndefFn}  = "HCS_Undef";
  $hash->{GetFn}    = "HCS_Get";
  $hash->{SetFn}    = "HCS_Set";
  $hash->{AttrList} = "device deviceCmdOn deviceCmdOff ".
                      "sensor sensorThresholdOn sensorThresholdOff sensorReading ".
                      "valvesExcluded valveThresholdOn valveThresholdOff ".
                      "do_not_notify:1,0 event-on-update-reading event-on-change-reading ".
                      "showtime:1,0 loglevel:0,1,2,3,4,5,6 disable:0,1";
}

#####################################
sub
HCS_Define($$) {
  my ($hash, $def) = @_;

  # define <name> HCS <device> [interval] [valveThresholdOn] [valveThresholdOff]
  # define heatingControl HCS KG.hz.LC.SW1.01 10 40 30

  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use 'define <name> HCS <device> [interval] [valveThresholdOn] [valveThresholdOff]'"
    if(@a < 3 || @a > 6);

  my $name = $a[0];
  $attr{$name}{device}        = $a[2];
  $attr{$name}{deviceCmdOn}       = AttrVal($name,"deviceCmdOn","on");
  $attr{$name}{deviceCmdOff}      = AttrVal($name,"deviceCmdOff","off");
  $attr{$name}{interval}          = AttrVal($name,"interval",(defined($a[3]) ? $a[3] : 10));
  $attr{$name}{valveThresholdOn}  = AttrVal($name,"valveThresholdOn",(defined($a[4]) ? $a[4] : 40));
  $attr{$name}{valveThresholdOff} = AttrVal($name,"valveThresholdOff",(defined($a[5]) ? $a[5] : 35));

  my $type = $hash->{TYPE};
  my $ret;

  if(!defined($defs{$a[2]})) {
    $ret = "Device $a[2] not defined. Please add this device first!";
    Log 1, "$type $name $ret";
    return $ret;
  }

  $hash->{STATE} = "Defined";

  my $interval = AttrVal($name,"interval",10);
  my $timer;

  $ret = HCS_getValves($hash,0);
  HCS_setState($hash,$ret);

  $timer = gettimeofday()+60;
  InternalTimer($timer, "HCS_checkState", $hash, 0);
  $hash->{NEXTCHECK} = FmtTime($timer);

  return undef;
}

#####################################
sub
HCS_Undef($$) {
  my ($hash, $name) = @_;

  delete($modules{HCS}{defptr}{$hash->{NAME}});
  RemoveInternalTimer($hash);

  return undef;
}

#####################################
sub
HCS_checkState($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $interval = $attr{$name}{interval};
  my $timer;
  my $ret;

  $ret = HCS_getValves($hash,0);
  HCS_setState($hash,$ret);

  $timer = gettimeofday()+($interval*60);
  InternalTimer($timer, "HCS_checkState", $hash, 0);
  $hash->{NEXTCHECK} = FmtTime($timer);

  return undef;
}

#####################################
sub
HCS_Get($@) {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $ret;

  # check syntax
  return "argument is missing @a"
    if(int(@a) != 2);
  # check argument
  return "Unknown argument $a[1], choose one of ".join(" ", sort keys %gets)
    if(!defined($gets{$a[1]}));
 
  # get argument
  my $arg = $a[1];

  if($arg eq "valves") {
    $ret = HCS_getValves($hash,1);
    return $ret;
  }

  return undef;
}

#####################################
sub
HCS_Set($@) {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $timer;
  my $ret;

  # check syntax
  return "argument is missing @a"
    if(int(@a) < 2 || int(@a) > 3);
  # check argument
  return "Unknown argument $a[1], choose one of ".join(" ", sort keys %sets)
    if(!defined($sets{$a[1]}));
 
  # get argument
  my $arg = $a[1];

  if($arg eq "interval") {

    return "Wrong interval format: Only digits are allowed!"
      if($a[2] !~ m/^\d+$/);

    my $intervalNew = $a[2];
    my $intervalOld = AttrVal($name,"interval",10);
    RemoveInternalTimer($hash);
    $attr{$name}{interval} = $intervalNew;
    $timer = gettimeofday()+($intervalNew*60);
    InternalTimer($timer, "HCS_checkState", $hash, 0);
    $hash->{NEXTCHECK} = FmtTime($timer);
    Log 1, "$type $name interval changed from $intervalOld to $intervalNew";

  } elsif($arg eq "valveThresholdOn") {

    return "Wrong interval format: Only digits are allowed!"
      if($a[2] !~ m/^\d+$/);

    my $thresholdNew = $a[2];
    my $thresholdOld = AttrVal($name,"valveThresholdOn",40);
    $attr{$name}{valveThresholdOn} = $thresholdNew;
    Log 1, "$type $name valveThresholdOn changed from $thresholdOld to $thresholdNew";

  } elsif($arg eq "valveThresholdOff") {

    return "Wrong interval format: Only digits are allowed!"
      if($a[2] !~ m/^\d+$/);

    my $thresholdNew = $a[2];
    my $thresholdOld = AttrVal($name,"valveThresholdOff",35);
    $attr{$name}{valveThresholdOff} = $thresholdNew;
    Log 1, "$type $name valveThresholdOff changed from $thresholdOld to $thresholdNew";

  } elsif($arg eq "on") {
    RemoveInternalTimer($hash);
    HCS_checkState($hash);
    Log 1, "$type $name monitoring of valves started";
  } elsif($arg eq "off") {
    RemoveInternalTimer($hash);
    #$hash->{STATE} = "off";
    $hash->{NEXTCHECK} = "offline";
    readingsBeginUpdate($hash);
    readingsUpdate($hash, "state", "off");
    readingsEndUpdate($hash, 1);
    Log 1, "$type $name monitoring of valves interrupted";
  }

}

#####################################
sub
HCS_setState($$) {
  my ($hash,$heatDemand) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $device       = AttrVal($name,"device","");
  my $deviceCmdOn  = AttrVal($name,"deviceCmdOn","on");
  my $deviceCmdOff = AttrVal($name,"deviceCmdOff","off");
  my $sensor = AttrVal($name,"sensor",undef);
  my $cmd;
  my $overdrive = 0;
  my $state;

  if($heatDemand == 1) {
    $state = "demand";
    $cmd = $deviceCmdOn;
  } elsif($heatDemand == 2) {
    $overdrive = 1;
    $state = "demand (overdrive)";
    $cmd = $deviceCmdOn;
  } elsif($heatDemand == 3) {
    $overdrive = 1;
    $state = "idle (overdrive)";
    $cmd = $deviceCmdOff;
  } else {
    $state = "idle";
    $cmd = $deviceCmdOff;
  }

  $state = "error" if(!defined($defs{$device}));

  readingsBeginUpdate($hash);
  readingsUpdate($hash, "overdrive", $overdrive) if($sensor);
  readingsUpdate($hash, "state", $state);
  readingsEndUpdate($hash, 1);

  if($defs{$device}) {
    my $cmdret = CommandSet(undef,"$device $cmd");
    Log 1, "$type $name An error occurred while switching device '$device': $cmdret"
      if($cmdret); 
  } else {
    Log 1, "$type $name device '$device' does not exists.";
  }

  return undef;
}

#####################################
sub
HCS_getValves($$) {
  my ($hash,$list) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $excluded = AttrVal($name,"valvesExcluded","");
  my $heatDemand = 0;
  my $valveThresholdOn  = AttrVal($name,"valveThresholdOn",40);
  my $valveThresholdOff = AttrVal($name,"valveThresholdOff",35);
  my %valves = ();
  my $valvesIdle = 0;
  my $valveState;
  my $valveLastDemand;
  my $valveNewDemand;
  my $value;
  my $ret;

  # reset counter
  my $sumDemand   = 0;
  my $sumFHT      = 0;
  my $sumHMCCTC   = 0;
  my $sumValves   = 0;
  my $sumExcluded = 0;
  my $sumIgnored  = 0;


  foreach my $d (sort keys %defs) {
    # skipping unneeded devices
    next if($defs{$d}{TYPE} ne "FHT" && $defs{$d}{TYPE} ne "CUL_HM");
    next if($defs{$d}{TYPE} eq "CUL_HM" && $attr{$d}{model} ne "HM-CC-TC");

    # get current actuator state from each device
    $valveState = $defs{$d}{READINGS}{"actuator"}{VAL};
    $valveState =~ s/[\s%]//g;

    if($attr{$d}{ignore}) {
      $value = "$valveState% (ignored)";
      $valves{$defs{$d}{NAME}}{state} = $value;
      $valves{$defs{$d}{NAME}}{demand} = 0;
      $ret .= "$defs{$d}{NAME}: $value\n" if($list);
      Log 4, "$type $name $defs{$d}{NAME}: $value";
      $sumIgnored++;
      $sumValves++;
      $sumFHT++     if($defs{$d}{TYPE} eq "FHT");
      $sumHMCCTC++  if(defined($attr{$d}{model}) && $attr{$d}{model} eq "HM-CC-TC");
      next;
    }

    if($excluded =~ m/$d/) {
      $value = "$valveState% (excluded)";
      $valves{$defs{$d}{NAME}}{state} = $value;
      $valves{$defs{$d}{NAME}}{demand} = 0;
      $ret .= "$defs{$d}{NAME}: $value\n" if($list);
      Log 4, "$type $name $defs{$d}{NAME}: $value";
      $sumExcluded++;
      $sumValves++;
      $sumFHT++     if($defs{$d}{TYPE} eq "FHT");
      $sumHMCCTC++  if(defined($attr{$d}{model}) && $attr{$d}{model} eq "HM-CC-TC");
      next;
    }

    $value = "$valveState%";
    $valves{$defs{$d}{NAME}}{state} = $value;
    $ret .= "$defs{$d}{NAME}: $value" if($list);
    Log 4, "$type $name $defs{$d}{NAME}: $value";

    # get last readings
    $valveLastDemand = ReadingsVal($name,$d."_demand",0);

    # check heat demand from each valve
    if($valveState >= $valveThresholdOn) {
      $heatDemand = 1;
      $valveNewDemand = $heatDemand;
      $ret .= " (demand)\n" if($list);
      $sumDemand++;
    } else {

      if($valveLastDemand == 1) {
        if($valveState > $valveThresholdOff) {
          $heatDemand = 1;
          $valveNewDemand = $heatDemand;
          $ret .= " (demand)\n" if($list);
          $sumDemand++;
        } else {
          $valveNewDemand = 0;
          $ret .= " (idle)\n" if($list);
          $valvesIdle++;
        }
      } else {
        $valveNewDemand = 0;
        $ret .= " (idle)\n" if($list);
        $valvesIdle++;
      }
    }

    $valves{$defs{$d}{NAME}}{demand} = $valveNewDemand;

    # count devices
    $sumFHT++     if($defs{$d}{TYPE} eq "FHT");
    $sumHMCCTC++  if($attr{$d}{model} eq "HM-CC-TC");
    $sumValves++;
  }

  # overdrive mode
  my $sensor = AttrVal($name,"sensor",undef);
  my $sensorReading      = AttrVal($name,"sensorReading",undef);
  my $sensorThresholdOn  = AttrVal($name,"sensorThresholdOn",undef);
  my $sensorThresholdOff = AttrVal($name,"sensorThresholdOff",undef);
  my $tempValue;
  my $overdrive = "no";

  if(defined($sensor) && defined($sensorThresholdOn) && defined($sensorThresholdOff) && defined($sensorReading)) {
    
    if(!defined($defs{$sensor})) {
      Log 1, "$type $name Device $sensor not defined. Please add this device first!";
    } else {
      $tempValue = ReadingsVal($sensor,$sensorReading,"");
      if(!$tempValue || $tempValue !~ m/^.*\d+.*$/) {
        Log 1, "$type $name Device $sensor has no valid value.";
      } else {
        $tempValue =~ s/(\s|°|[A-Z]|[a-z])+//g;
    
        $heatDemand = 2 if($tempValue <= $sensorThresholdOn);
        $heatDemand = 3 if($tempValue > $sensorThresholdOff);
        $overdrive = "yes" if($heatDemand == 2 || $heatDemand == 3);
      }
    }
  } else {
    if(!$sensor) {
      delete $hash->{READINGS}{sensor};
      delete $hash->{READINGS}{overdrive};
      delete $attr{$name}{sensorReading};
      delete $attr{$name}{sensorThresholdOn};
      delete $attr{$name}{sensorThresholdOff};
    }
  }

  #my $sumDemand = $sumValves-$valvesIdle-$sumIgnored-$sumExcluded;
  Log 3, "$type $name Found $sumValves Device(s): $sumFHT FHT, $sumHMCCTC HM-CC-TC. ".
         "demand: $sumDemand, idle: $valvesIdle, ignored: $sumIgnored, excluded: $sumExcluded, overdrive: $overdrive";

  readingsBeginUpdate($hash);
  for my $d (sort keys %valves) {
    readingsUpdate($hash, $d."_state", $valves{$d}{state});
    readingsUpdate($hash, $d."_demand", $valves{$d}{demand});
  }
  readingsUpdate($hash, "sensor", $tempValue) if(defined($tempValue) && $tempValue ne "");
  readingsEndUpdate($hash, 1);

  return ($list) ? $ret : $heatDemand;
}

# vim: ts=2:et

1;
