# $Id$
##############################################################################
#
#     70_ENIGMA2.pm
#     An FHEM Perl module for controlling ENIGMA2 based TV receivers
#     via network connection.
#
#     Copyright by Julian Pawlowski
#     e-mail: julian.pawlowski at gmail.com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use 5.012;
use strict;
use warnings;
use Data::Dumper;
use IO::Socket;
use HttpUtils;
use Encode;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';
no if $] >= 5.017011, warnings => 'experimental::lexical_topic';

no warnings "all";

sub ENIGMA2_Set($@);
sub ENIGMA2_Get($@);
sub ENIGMA2_GetStatus($;$);
sub ENIGMA2_Define($$);
sub ENIGMA2_Undefine($$);

#########################
# Forward declaration for remotecontrol module
sub ENIGMA2_RClayout_TV();
sub ENIGMA2_RCmakenotify($$);

###################################
sub ENIGMA2_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "ENIGMA2_Initialize: Entering";

    eval 'use XML::Simple; 1';
    return "Please install XML::Simple to use this module."
      if ($@);

    $hash->{GetFn}   = "ENIGMA2_Get";
    $hash->{SetFn}   = "ENIGMA2_Set";
    $hash->{DefFn}   = "ENIGMA2_Define";
    $hash->{UndefFn} = "ENIGMA2_Undefine";

    $hash->{AttrList} =
"https:0,1 http-method:GET,POST http-noshutdown:1,0 disable:0,1 bouquet-tv bouquet-radio timeout remotecontrol:standard,advanced,keyboard lightMode:0,1 macaddr:textField wakeupCmd:textField "
      . $readingFnAttributes;

    $data{RC_layout}{ENIGMA2_DreamMultimedia_DM500_DM800_SVG} =
      "ENIGMA2_RClayout_DM800_SVG";
    $data{RC_layout}{ENIGMA2_DreamMultimedia_DM500_DM800} =
      "ENIGMA2_RClayout_DM800";
    $data{RC_layout}{ENIGMA2_DreamMultimedia_DM8000_DM800se_SVG} =
      "ENIGMA2_RClayout_DM8000_SVG";
    $data{RC_layout}{ENIGMA2_DreamMultimedia_DM8000_DM800se} =
      "ENIGMA2_RClayout_DM8000";
    $data{RC_layout}{ENIGMA2_DreamMultimedia_RC10_SVG} =
      "ENIGMA2_RClayout_RC10_SVG";
    $data{RC_layout}{ENIGMA2_DreamMultimedia_RC10} = "ENIGMA2_RClayout_RC10";

#  $data{RC_layout}{ENIGMA2_VUplus_Solo2_SVG}  = "ENIGMA2_RClayout_VUplusSolo2_SVG";
#  $data{RC_layout}{ENIGMA2_VUplus_Solo2}  = "ENIGMA2_RClayout_VUplusSolo2";
    $data{RC_layout}{ENIGMA2_VUplus_Duo2_SVG} =
      "ENIGMA2_RClayout_VUplusDuo2_SVG";
    $data{RC_layout}{ENIGMA2_VUplus_Duo2} = "ENIGMA2_RClayout_VUplusDuo2";

#  $data{RC_layout}{ENIGMA2_VUplus_Ultimo_SVG}  = "ENIGMA2_RClayout_VUplusUltimo_SVG";
#  $data{RC_layout}{ENIGMA2_VUplus_Ultimo}  = "ENIGMA2_RClayout_VUplusUltimo";
    $data{RC_makenotify}{ENIGMA2} = "ENIGMA2_RCmakenotify";

    return;
}

#####################################
sub ENIGMA2_GetStatus($;$) {
    my ( $hash, $update ) = @_;
    my $name     = $hash->{NAME};
    my $interval = $hash->{INTERVAL};

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_GetStatus()";

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + $interval, "ENIGMA2_GetStatus", $hash, 0 );

    return
      if ( AttrVal( $name, "disable", 0 ) == 1 );

    if ( !$update ) {
        ENIGMA2_SendCommand( $hash, "powerstate" );
    }
    else {
        ENIGMA2_SendCommand( $hash, "getcurrent" );
    }

    return;
}

###################################
sub ENIGMA2_Get($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $what;

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_Get()";

    return "argument is missing" if ( int(@a) < 2 );

    $what = $a[1];

    if ( $what =~
/^(power|input|volume|mute|channel|currentMedia|currentTitle|nextTitle|providername|servicevideosize)$/
      )
    {
        if ( ReadingsVal( $name, $what, "" ) ne "" ) {
            return ReadingsVal( $name, $what, "" );
        }
        else {
            return "no such reading: $what";
        }
    }

    # streamUrl
    elsif ( $what eq "streamUrl" ) {
        if ( defined( $a[2] ) && $a[2] eq "mobile" ) {
            return
                "http://"
              . $hash->{helper}{ADDRESS} . ":"
              . $hash->{helper}{PORT}
              . "/web/stream.m3u?ref="
              . urlEncode( ReadingsVal( $name, "servicereference", "-" ) )
              . "&device=phone";
        }
        else {
            return
                "http://"
              . $hash->{helper}{ADDRESS} . ":"
              . $hash->{helper}{PORT}
              . "/web/stream.m3u?ref="
              . urlEncode( ReadingsVal( $name, "servicereference", "-" ) )
              . "&device=etc";
        }
    }
    else {
        return
"Unknown argument $what, choose one of power:noArg input:noArg volume:noArg mute:noArg channel:noArg currentMedia:noArg currentTitle:noArg nextTitle:noArg providername:noArg servicevideosize:noArg streamUrl:,mobile ";
    }
}

###################################
sub ENIGMA2_Set($@) {
    my ( $hash, @a ) = @_;
    my $name     = $hash->{NAME};
    my $state    = ReadingsVal( $name, "state", "absent" );
    my $presence = ReadingsVal( $name, "presence", "absent" );
    my $input    = ReadingsVal( $name, "input", "" );
    my $channel  = ReadingsVal( $name, "channel", "" );
    my $channels = "";

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_Set()";

    return "No Argument given" if ( !defined( $a[1] ) );

    # depending on current FHEMWEB instance's allowedCommands,
    # restrict set commands if there is "set-user" in it
    my $adminMode         = 1;
    my $FWallowedCommands = 0;
    $FWallowedCommands = AttrVal( $FW_wname, "allowedCommands", 0 )
      if ( defined($FW_wname) );
    if ( $FWallowedCommands && $FWallowedCommands =~ m/\bset-user\b/ ) {
        $adminMode = 0;
        return "Forbidden command: set " . $a[1]
          if ( lc( $a[1] ) eq "statusrequest"
            || lc( $a[1] ) eq "reboot"
            || lc( $a[1] ) eq "restartgui"
            || lc( $a[1] ) eq "shutdown" );
    }

    # load channel list
    if (
           defined($input)
        && defined($channel)
        && $input ne ""
        && $channel ne ""
        && (   !defined( $hash->{helper}{bouquet}{$input} )
            || !defined( $hash->{helper}{bouquet}{$input}{$channel} ) )
      )
    {
        $channels .= $channel . ",";
    }

    if (   $input ne ""
        && defined( $hash->{helper}{channels}{$input} )
        && ref( $hash->{helper}{channels}{$input} ) eq "ARRAY" )
    {
        $channels .= join( ',', @{ $hash->{helper}{channels}{$input} } );
    }

    my $usage =
        "Unknown argument "
      . $a[1]
      . ", choose one of toggle:noArg on:noArg off:noArg volume:slider,0,1,100 volumeUp:noArg volumeDown:noArg msg remoteControl channelUp:noArg channelDown:noArg play:noArg pause:noArg stop:noArg record:noArg showText channel:"
      . $channels;
    $usage .= " mute:-,on,off"
      if ( ReadingsVal( $name, "mute", "-" ) eq "-" );
    $usage .= " mute:on,off"
      if ( ReadingsVal( $name, "mute", "-" ) ne "-" );
    $usage .= " input:-,tv,radio"
      if ( $input eq "-" );
    $usage .= " input:tv,radio"
      if ( $input ne "-" );

    if ($adminMode) {
        $usage .= " reboot:noArg";
        $usage .= " restartGui:noArg";
        $usage .= " shutdown:noArg";
        $usage .= " statusRequest:noArg";
    }

    my $cmd = '';
    my $result;

    # statusRequest
    if ( lc( $a[1] ) eq "statusrequest" ) {
        Log3 $name, 3, "ENIGMA2 set $name " . $a[1];

        if ( $state ne "absent" ) {
            Log3 $name, 4,
              "ENIGMA2 $name: Clearing cache for bouquet and channels";
            $hash->{helper}{bouquet}  = undef;
            $hash->{helper}{channels} = undef;
        }

        ENIGMA2_GetStatus($hash);
    }

    # toggle
    elsif ( lc( $a[1] ) eq "toggle" ) {
        if ( $state ne "on" ) {
            return ENIGMA2_Set( $hash, $name, "on" );
        }
        else {
            return ENIGMA2_Set( $hash, $name, "off" );
        }
    }

    # shutdown
    elsif ( lc( $a[1] ) eq "shutdown" ) {
        return "Recordings running"
          if ( ReadingsVal( $name, "recordings", "0" ) ne "0" );

        Log3 $name, 3, "ENIGMA2 set $name " . $a[1];

        if ( $state ne "absent" ) {
            $cmd = "newstate=1";
            $result =
              ENIGMA2_SendCommand( $hash, "powerstate", $cmd, "shutdown" );
        }
        else {
            return "Device needs to be ON to be set to standby mode.";
        }
    }

    # reboot
    elsif ( lc( $a[1] ) eq "reboot" ) {
        return "Recordings running"
          if ( ReadingsVal( $name, "recordings", "0" ) ne "0" );

        Log3 $name, 3, "ENIGMA2 set $name " . $a[1];

        if ( $state ne "absent" ) {
            $cmd = "newstate=2";
            $result =
              ENIGMA2_SendCommand( $hash, "powerstate", $cmd, "reboot" );
        }
        else {
            return "Device needs to be reachable to be rebooted.";
        }
    }

    # restartGui
    elsif ( lc( $a[1] ) eq "restartgui" ) {
        return "Recordings running"
          if ( ReadingsVal( $name, "recordings", "0" ) ne "0" );

        Log3 $name, 3, "ENIGMA2 set $name " . $a[1];

        if ( $state eq "on" ) {
            $cmd = "newstate=3";
            $result =
              ENIGMA2_SendCommand( $hash, "powerstate", $cmd, "restartGui" );
        }
        else {
            return "Device needs to be ON to restart the GUI.";
        }
    }

    # on
    elsif ( lc( $a[1] ) eq "on" ) {
        if ( $state eq "absent" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $a[1] . " (wakeup)";
            my $wakeupCmd = AttrVal( $name, "wakeupCmd", "" );
            my $macAddr =
              AttrVal( $name, "macaddr", ReadingsVal( $name, "lanmac", "" ) );

            if ( $wakeupCmd ne "" ) {
                $wakeupCmd =~ s/\$DEVICE/$name/g;
                $wakeupCmd =~ s/\$MACADDR/$macAddr/g;

                if ( $wakeupCmd =~ s/^[ \t]*\{|\}[ \t]*$//g ) {
                    Log3 $name, 4,
                      "ENIGMA2 executing wake-up command (Perl): $wakeupCmd";
                    $result = eval $wakeupCmd;
                }
                else {
                    Log3 $name, 4,
                      "ENIGMA2 executing wake-up command (fhem): $wakeupCmd";
                    $result = fhem $wakeupCmd;
                }
            }
            elsif ( $macAddr ne "" && $macAddr ne "-" ) {
                $result = ENIGMA2_wake( $name, $macAddr );
                return "wake-up command sent to MAC $macAddr";
            }
            else {
                return
"Device MAC address unknown. Please turn on the device manually once or set attribute macaddr.";
            }
        }
        else {
            Log3 $name, 3, "ENIGMA2 set $name " . $a[1];

            $cmd = "newstate=4";
            $result = ENIGMA2_SendCommand( $hash, "powerstate", $cmd, "on" );
        }
    }

    # off
    elsif ( lc( $a[1] ) eq "off" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $a[1];
            $cmd = "newstate=5";
            $result = ENIGMA2_SendCommand( $hash, "powerstate", $cmd, "off" );
        }
        else {
            return "Device needs to be reachable to be set to standby mode.";
        }
    }

    # volume
    elsif ( lc( $a[1] ) eq "volume" ) {
        return "No argument given" if ( !defined( $a[2] ) );

        Log3 $name, 3, "ENIGMA2 set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
            my $_ = $a[2];
            if ( m/^\d+$/ && $_ >= 0 && $_ <= 100 ) {
                $cmd = "set=set" . $a[2];
            }
            else {
                return
"Argument does not seem to be a valid integer between 0 and 100";
            }
            $result = ENIGMA2_SendCommand( $hash, "vol", $cmd );
        }
        else {
            return "Device needs to be ON to adjust volume.";
        }
    }

    # volumeUp/volumeDown
    elsif ( lc( $a[1] ) =~ /^(volumeup|volumedown)$/ ) {
        if ( $state eq "on" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $a[1];

            if ( lc( $a[1] ) eq "volumeup" ) {
                $cmd = "set=up";
            }
            else {
                $cmd = "set=down";
            }
            $result = ENIGMA2_SendCommand( $hash, "vol", $cmd );
        }
        else {
            return "Device needs to be ON to adjust volume.";
        }
    }

    # mute
    elsif ( lc( $a[1] ) eq "mute" || lc( $a[1] ) eq "mutet" ) {
        if ( $state eq "on" ) {
            if ( defined( $a[2] ) ) {
                Log3 $name, 3, "ENIGMA2 set $name " . $a[1] . " " . $a[2];
            }
            else {
                Log3 $name, 3, "ENIGMA2 set $name " . $a[1];
            }

            if ( !defined( $a[2] ) || $a[2] eq "toggle" ) {
                $cmd = "set=mute";
            }
            elsif ( lc( $a[2] ) eq "off" ) {
                if ( ReadingsVal( $name, "mute", "" ) ne "off" ) {
                    $cmd = "set=mute";
                }
            }
            elsif ( lc( $a[2] ) eq "on" ) {
                if ( ReadingsVal( $name, "mute", "" ) ne "on" ) {
                    $cmd = "set=mute";
                }
            }
            else {
                return "Unknown argument " . $a[2];
            }
            $result = ENIGMA2_SendCommand( $hash, "vol", $cmd )
              if ( $cmd ne "" );
        }
        else {
            return "Device needs to be ON to mute/unmute audio.";
        }
    }

    # msg
    elsif ( lc( $a[1] ) eq "msg" ) {
        if ( $state ne "absent" ) {
            return
"No 1st argument given, choose one of yesno info message attention "
              if ( !defined( $a[2] ) );

            return "No 2nd argument given, choose one of timeout "
              if ( !defined( $a[3] ) );

            return "No 3nd argument given, choose one of messagetext "
              if ( !defined( $a[4] ) );

            $_ = $a[3];

            return
                "Argument "
              . $_
              . " is not a valid integer between 0 and 49680"
              if ( !m/^\d+$/ || $_ < 0 || $_ > 49680 );

            Log3 $name, 3, "ENIGMA2 set $name " . $a[1] . " " . $a[2];

            my $i    = 4;
            my $text = $a[$i];
            $i++;

            if ( defined( $a[$i] ) ) {
                my $arr_size = @a;
                while ( $i < $arr_size ) {
                    $text = $text . " " . $a[$i];
                    $i++;
                }
            }
            if ( lc( $a[2] ) eq "yesno" ) {
                $cmd = "type=0&timeout=" . $a[3] . "&text=" . urlEncode($text);
            }
            elsif ( lc( $a[2] ) eq "info" ) {
                $cmd = "type=1&timeout=" . $a[3] . "&text=" . urlEncode($text);
            }
            elsif ( lc( $a[2] ) eq "message" ) {
                $cmd = "type=2&timeout=" . $a[3] . "&text=" . urlEncode($text);
            }
            elsif ( lc( $a[2] ) eq "attention" ) {
                $cmd = "type=3&timeout=" . $a[3] . "&text=" . urlEncode($text);
            }
            else {
                return
                    "Unknown argument "
                  . $a[2]
                  . ", choose one of yesno info message attention ";
            }
            $result = ENIGMA2_SendCommand( $hash, "message", $cmd );
        }
        else {
            return "Device needs to be reachable to send a message to screen.";
        }
    }

    # remoteControl
    elsif ( lc( $a[1] ) eq "remotecontrol" ) {
        if ( $state ne "absent" ) {

            Log3 $name, 3, "ENIGMA2 set $name " . $a[1] . " " . $a[2]
              if !defined( $a[3] );
            Log3 $name, 3,
              "ENIGMA2 set $name " . $a[1] . " " . $a[2] . " " . $a[3]
              if defined( $a[3] );

            if ( !defined( $a[2] ) ) {
                my $commandKeys = "";
                for (
                    sort keys %{
                        ENIGMA2_GetRemotecontrolCommand(
                            "GetRemotecontrolCommands")
                    }
                  )
                {
                    $commandKeys = $commandKeys . " " . $_;
                }
                return "No argument given, choose one of" . $commandKeys;
            }

            my $request = ENIGMA2_GetRemotecontrolCommand( uc( $a[2] ) );
            $request = $a[2]
              if ( $request eq "" && $a[2] =~ /^\d+$/ );

            if ( uc( $a[2] ) eq "POWER" ) {
                return ENIGMA2_Set( $hash, $name, "toggle" );
            }
            elsif ( uc( $a[2] ) eq "MUTE" ) {
                return ENIGMA2_Set( $hash, $name, "mute" );
            }
            elsif ( $request ne "" ) {
                $cmd = "command=" . $request;
                $cmd .= "&rcu=" . AttrVal( $name, "remotecontrol", "" )
                  if ( AttrVal( $name, "remotecontrol", "" ) ne "" );
                $cmd .= "&type=long"
                  if ( defined( $a[3] ) && lc( $a[3] ) eq "long" );
            }
            else {
                my $commandKeys = "";
                for (
                    sort keys %{
                        ENIGMA2_GetRemotecontrolCommand(
                            "GetRemotecontrolCommands")
                    }
                  )
                {
                    $commandKeys = $commandKeys . " " . $_;
                }
                return
                    "Unknown argument "
                  . $a[2]
                  . ", choose one of"
                  . $commandKeys;
            }

            $result = ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
        }
        else {
            return "Device needs to be reachable to be controlled remotely.";
        }
    }

    # channel
    elsif ( lc( $a[1] ) eq "channel" ) {

        return
"No argument given, choose one of channel channelNumber servicereference "
          if ( !defined( $a[2] ) );

        if (   defined( $a[2] )
            && $presence eq "present"
            && $state ne "on" )
        {
            Log3 $name, 4, "ENIGMA2 $name: indirect switching request to ON";
            ENIGMA2_Set( $hash, $name, "on" );
        }

        Log3 $name, 3, "ENIGMA2 set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
            my $_ = $a[2];
            if ( defined( $hash->{helper}{bouquet}{$input}{$_}{sRef} ) ) {
                $result = ENIGMA2_SendCommand( $hash, "zap",
                    "sRef="
                      . urlEncode( $hash->{helper}{bouquet}{$input}{$_}{sRef} )
                );
            }
            elsif (m/^(\d+):(.*):$/) {
                $result =
                  ENIGMA2_SendCommand( $hash, "zap", "sRef=" . urlEncode($_) );
            }
            elsif ( m/^\d+$/ && $_ > 0 && $_ < 10000 ) {
                for ( split( //, $a[2] ) ) {
                    $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand($_);
                    $result =
                      ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
                }
                $result = ENIGMA2_SendCommand( $hash, "remotecontrol",
                    "command=" . ENIGMA2_GetRemotecontrolCommand("OK") );
            }
            elsif ( m/^\d+$/ && ( $_ <= 0 || $_ >= 10000 ) ) {
                return "Numeric channel addressing '" . $_
                  . "' needs to be a number between 1 and 9999.";
            }
            else {
                return
                    "'"
                  . $_
                  . "' does not seem to be a valid channel. Known channels: "
                  . $channels;
            }
        }
        else {
            return
              "Device needs to be present to switch to a specific channel.";
        }
    }

    # channelUp/channelDown
    elsif ( lc( $a[1] ) =~ /^(channelup|channeldown)$/ ) {
        Log3 $name, 3, "ENIGMA2 set $name " . $a[1];

        if ( $state eq "on" ) {
            if ( lc( $a[1] ) eq "channelup" ) {
                $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand("RIGHT");
            }
            else {
                $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand("LEFT");
            }
            $result = ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
        }
        else {
            return "Device needs to be ON to switch channel.";
        }
    }

    # input
    elsif ( lc( $a[1] ) eq "input" ) {

        return "No argument given, choose one of tv radio "
          if ( !defined( $a[2] ) );

        if (   defined( $a[2] )
            && $presence eq "present"
            && $state ne "on" )
        {
            Log3 $name, 4, "ENIGMA2 $name: indirect switching request to ON";
            ENIGMA2_Set( $hash, $name, "on" );
        }

        Log3 $name, 3, "ENIGMA2 set $name " . $a[1] . " " . $a[2];

        if ( $state eq "on" ) {
            if ( lc( $a[2] ) eq "tv" ) {
                $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand("TV");
            }
            elsif ( lc( $a[2] ) eq "radio" ) {
                $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand("RADIO");
            }
            else {
                return
                    "Argument "
                  . $a[2]
                  . " is not valid, please choose one from tv radio ";
            }
            $result = ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
        }
        else {
            return "Device needs to be present to switch input.";
        }
    }

    # play / pause
    elsif ( lc( $a[1] ) =~ /^(play|pause)$/ ) {
        if ( $state eq "on" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $a[1];

            $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand("PLAYPAUSE");
            $result = ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
        }
        else {
            return "Device needs to be ON to play or pause video.";
        }
    }

    # stop
    elsif ( lc( $a[1] ) eq "stop" ) {
        if ( $state eq "on" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $a[1];

            $cmd = "command=" . ENIGMA2_GetRemotecontrolCommand("STOP");
            $result = ENIGMA2_SendCommand( $hash, "remotecontrol", $cmd );
        }
        else {
            return "Device needs to be ON to stop video.";
        }
    }

    # record
    elsif ( lc( $a[1] ) eq "record" ) {
        if ( $state eq "on" ) {
            Log3 $name, 3, "ENIGMA2 set $name " . $a[1];
            $result = ENIGMA2_SendCommand( $hash, "recordnow" );
        }
        else {
            return "Device needs to be ON to start instant recording.";
        }
    }

    # showText
    elsif ( lc( $a[1] ) eq "showtext" ) {
        if ( $state ne "absent" ) {
            return "No argument given, choose one of messagetext "
              if ( !defined( $a[2] ) );

            Log3 $name, 3, "ENIGMA2 set $name " . $a[1];

            my $i    = 2;
            my $text = $a[$i];
            $i++;
            if ( defined( $a[$i] ) ) {
                my $arr_size = @a;
                while ( $i < $arr_size ) {
                    $text = $text . " " . $a[$i];
                    $i++;
                }
            }
            $cmd = "type=1&timeout=8&text=" . urlEncode($text);
            $result = ENIGMA2_SendCommand( $hash, "message", $cmd );
        }
        else {
            return "Device needs to be reachable to send a message to screen.";
        }
    }

    # return usage hint
    else {
        return $usage;
    }

    return;
}

###################################
sub ENIGMA2_Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    my $name = $hash->{NAME};

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_Define()";

    if ( int(@a) < 3 ) {
        my $msg =
"Wrong syntax: define <name> ENIGMA2 <ip-or-hostname> [<port>] [<poll-interval>] [<http-user] [<http-password>]";
        Log3 $name, 4, $msg;
        return $msg;
    }

    $hash->{TYPE} = "ENIGMA2";

    my $address = $a[2];
    $hash->{helper}{ADDRESS} = $address;

    # use port 80 if not defined
    my $port = $a[3] || 80;
    $hash->{helper}{PORT} = $port;

    # use interval of 45sec if not defined
    my $interval = $a[4] || 45;
    $hash->{INTERVAL} = $interval;

    # set http user if defined
    my $http_user = $a[5];
    $hash->{helper}{USER} = $http_user if $http_user;

    # set http password if defined
    my $http_passwd = $a[6];
    $hash->{helper}{PASSWORD} = $http_passwd if $http_passwd;

    # set default settings on first define
    if ($init_done) {

        # use http-method POST for FritzBox environment as GET does not seem to
        # work properly. Might restrict use to newer
        # ENIGMA2 Webif versions or use of OWIF only.
        if ( exists $ENV{CONFIG_PRODUKT_NAME}
            && defined $ENV{CONFIG_PRODUKT_NAME} )
        {
            $attr{$name}{"http-method"} = 'POST';
        }

        # default method is GET and should be compatible to most
        # ENIGMA2 Webif versions
        else {
            $attr{$name}{"http-method"} = 'GET';
        }
        $attr{$name}{webCmd} = 'channel:input';
        $attr{$name}{devStateIcon} =
          'on:rc_GREEN:off off:rc_YELLOW:on absent:rc_STOP:on';
        $attr{$name}{icon} = 'dreambox';
    }

    # start the status update timer
    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 2, "ENIGMA2_GetStatus", $hash, 1 );

    return;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub ENIGMA2_SendCommand($$;$$) {
    my ( $hash, $service, $cmd, $type ) = @_;
    my $name            = $hash->{NAME};
    my $address         = $hash->{helper}{ADDRESS};
    my $port            = $hash->{helper}{PORT};
    my $http_method     = AttrVal( $name, "http-method", "GET" );
    my $http_noshutdown = AttrVal( $name, "http-noshutdown", "1" );
    my $timeout;
    $cmd = ( defined($cmd) ) ? $cmd : "";

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_SendCommand()";

    my $http_proto;
    if ( $port eq "443" ) {
        $http_proto = "https";
        Log3 $name, 5, "ENIGMA2 $name: port 443 implies using HTTPS";
    }
    elsif ( AttrVal( $name, "https", "0" ) eq "1" ) {
        Log3 $name, 5, "ENIGMA2 $name: explicit use of HTTPS";
        $http_proto = "https";
        if ( $port eq "80" ) {
            $port = "443";
            Log3 $name, 5,
              "ENIGMA2 $name: implicit change of from port 80 to 443";
        }
    }
    else {
        Log3 $name, 5, "ENIGMA2 $name: using unencrypted connection via HTTP";
        $http_proto = "http";
    }

    my $http_user   = "";
    my $http_passwd = "";
    if (   defined( $hash->{helper}{USER} )
        && defined( $hash->{helper}{PASSWORD} ) )
    {
        Log3 $name, 5, "ENIGMA2 $name: using BasicAuth";
        $http_user   = $hash->{helper}{USER};
        $http_passwd = $hash->{helper}{PASSWORD};
    }
    if ( defined( $hash->{helper}{USER} ) ) {
        Log3 $name, 5, "ENIGMA2 $name: using BasicAuth (username only)";
        $http_user = $hash->{helper}{USER};
    }
    my $URL;
    my $response;
    my $return;

    if ( !defined($cmd) || $cmd eq "" ) {
        Log3 $name, 4, "ENIGMA2 $name: REQ $service";
    }
    else {
        $cmd = "?" . $cmd . "&"
          if ( $http_method eq "GET" || $http_method eq "" );
        Log3 $name, 4, "ENIGMA2 $name: REQ $service/" . urlDecode($cmd);
    }

    if ( $http_user ne "" && $http_passwd ne "" ) {
        $URL =
            $http_proto . "://"
          . $http_user . ":"
          . $http_passwd . "@"
          . $address . ":"
          . $port . "/web/"
          . $service;
        $URL .= $cmd if ( $http_method eq "GET" || $http_method eq "" );
    }
    elsif ( $http_user ne "" ) {
        $URL =
            $http_proto . "://"
          . $http_user . "@"
          . $address . ":"
          . $port . "/web/"
          . $service;
        $URL .= $cmd if ( $http_method eq "GET" || $http_method eq "" );
    }
    else {
        $URL =
          $http_proto . "://" . $address . ":" . $port . "/web/" . $service;
        $URL .= $cmd if ( $http_method eq "GET" || $http_method eq "" );
    }

    if ( AttrVal( $name, "timeout", "3" ) =~ /^\d+$/ ) {
        $timeout = AttrVal( $name, "timeout", "3" );
    }
    else {
        Log3 $name, 3, "ENIGMA2 $name: wrong format in attribute 'timeout'";
        $timeout = 3;
    }

    # send request via HTTP-GET method
    if ( $http_method eq "GET" || $http_method eq "" || $cmd eq "" ) {
        Log3 $name, 5,
            "ENIGMA2 $name: GET "
          . urlDecode($URL)
          . " (noshutdown="
          . $http_noshutdown . ")";

        HttpUtils_NonblockingGet(
            {
                url        => $URL,
                timeout    => $timeout,
                noshutdown => $http_noshutdown,
                data       => undef,
                hash       => $hash,
                service    => $service,
                cmd        => $cmd,
                type       => $type,
                callback   => \&ENIGMA2_ReceiveCommand,
            }
        );

    }

    # send request via HTTP-POST method
    elsif ( $http_method eq "POST" ) {
        Log3 $name, 5,
            "ENIGMA2 $name: GET "
          . $URL
          . " (POST DATA: "
          . urlDecode($cmd)
          . ", noshutdown="
          . $http_noshutdown . ")";

        HttpUtils_NonblockingGet(
            {
                url        => $URL,
                timeout    => $timeout,
                noshutdown => $http_noshutdown,
                data       => $cmd,
                hash       => $hash,
                service    => $service,
                cmd        => $cmd,
                type       => $type,
                callback   => \&ENIGMA2_ReceiveCommand,
            }
        );
    }

    # other HTTP methods are not supported
    else {
        Log3 $name, 1,
            "ENIGMA2 $name: ERROR: HTTP method "
          . $http_method
          . " is not supported.";
    }

    return;
}

###################################
sub ENIGMA2_ReceiveCommand($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash     = $param->{hash};
    my $name     = $hash->{NAME};
    my $service  = $param->{service};
    my $cmd      = $param->{cmd};
    my $state    = ReadingsVal( $name, "state", "off" );
    my $presence = ReadingsVal( $name, "presence", "absent" );
    my $type     = ( $param->{type} ) ? $param->{type} : "";
    my $return;

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_ReceiveCommand()";

    readingsBeginUpdate($hash);

    # device not reachable
    if ($err) {

        # powerstate
        if ( $service eq "powerstate" ) {
            $state = "absent";

            if ( !defined($cmd) || $cmd eq "" ) {
                Log3 $name, 4, "ENIGMA2 $name: RCV TIMEOUT $service";
            }
            else {
                Log3 $name, 4,
                  "ENIGMA2 $name: RCV TIMEOUT $service/" . urlDecode($cmd);
            }

            $presence = "absent";
            readingsBulkUpdate( $hash, "presence", $presence )
              if ( ReadingsVal( $name, "presence", "" ) ne $presence );
        }
    }

    # data received
    elsif ($data) {
        $presence = "present";
        readingsBulkUpdate( $hash, "presence", $presence )
          if ( ReadingsVal( $name, "presence", "" ) ne $presence );

        if ( !defined($cmd) || $cmd eq "" ) {
            Log3 $name, 4, "ENIGMA2 $name: RCV $service";
        }
        else {
            Log3 $name, 4, "ENIGMA2 $name: RCV $service/" . urlDecode($cmd);
        }

        if ( $data ne "" ) {
            if ( $data =~ /^<\?xml/ && $data !~ /<\/html>/ ) {
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3 $name, 5, "ENIGMA2 $name: RES $service\n" . $data;
                }
                else {
                    Log3 $name, 5,
                        "ENIGMA2 $name: RES $service/"
                      . urlDecode($cmd) . "\n"
                      . $data;
                }

                my $parser = XML::Simple->new(
                    NormaliseSpace => 2,
                    KeepRoot       => 0,
                    ForceArray     => 0,
                    SuppressEmpty  => 1,
                    KeyAttr        => {}
                );

                eval
                  '$return = $parser->XMLin( Encode::encode_utf8($data) ); 1';
                if ($@) {

                    if ( !defined($cmd) || $cmd eq "" ) {
                        Log3 $name, 5,
"ENIGMA2 $name: RES ERROR $service - unable to parse malformed XML: $@\n"
                          . $data;
                    }
                    else {
                        Log3 $name, 5,
                            "ENIGMA2 $name: RES ERROR $service/"
                          . urlDecode($cmd)
                          . " - unable to parse malformed XML: $@\n"
                          . $data;

                    }

                    return undef;
                }

                undef $parser;
            }
            else {
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3 $name, 5,
                      "ENIGMA2 $name: RES ERROR $service - not in XML format\n"
                      . $data;
                }
                else {
                    Log3 $name, 5,
                        "ENIGMA2 $name: RES ERROR $service/"
                      . urlDecode($cmd)
                      . " - not in XML format\n"
                      . $data;
                }

                return undef;
            }
        }

        $return = Encode::encode_utf8($data)
          if ( $return && ref($return) ne "HASH" );

        #######################
        # process return data
        #

        # powerstate
        if ( $service eq "powerstate" ) {
            if ( defined($return)
                && ref($return) eq "HASH" )
            {

                # Cache bouquet information - get favorite bouquet
                # if not available from helper
                if (
                    !defined($type)
                    || (   $type ne "shutdown"
                        && $type ne "reboot"
                        && $type ne "restartGui"
                        && $type ne "off" )
                  )
                {
                    foreach my $input ( "tv", "radio" ) {
                        if (   !defined( $hash->{helper}{bouquet}{$input} )
                            || !defined( $hash->{helper}{channels}{$input} ) )
                        {
                            my $service_uri =
'1:7:2:0:0:0:0:0:0:0:(type == 2)FROM BOUQUET "bouquets.'
                              . $input
                              . '" ORDER BY bouquet';

                            # trigger cache update
                            if (
                                AttrVal( $name, "bouquet-" . $input, "" ) ne
                                "" )
                            {
                                ENIGMA2_SendCommand(
                                    $hash,
                                    "getservices",
                                    "sRef="
                                      . urlEncode(
                                        AttrVal(
                                            $name, "bouquet-" . $input, ""
                                        )
                                      ),
                                    "services-" . $input
                                );
                            }

                            # set attributes first
                            else {
                                ENIGMA2_SendCommand(
                                    $hash, "getservices",
                                    "sRef=" . urlEncode($service_uri),
                                    "defBouquet-" . $input
                                );
                            }
                        }
                    }
                }

                if (   $type eq "shutdown"
                    || $type eq "reboot"
                    || $type eq "restartGui"
                    || $type eq "off"
                    || ( $return->{e2instandby} eq "true" && $type ne "on" ) )
                {
                    $state = "off";

                    # Keep updating timer information during standby
                    ENIGMA2_SendCommand( $hash, "timerlist" )
                      if ( !AttrVal( $name, "lightMode", 0 ) );
                }
                else {
                    $state = "on";

                    # Read Boxinfo every 15 minutes only
                    if (
                        !defined( $hash->{helper}{lastFullUpdate} )
                        || ( defined( $hash->{helper}{lastFullUpdate} )
                            && $hash->{helper}{lastFullUpdate} + 900 le time() )
                      )
                    {
                        ENIGMA2_SendCommand( $hash, "about" );

                        # Update state
                        $hash->{helper}{lastFullUpdate} = time();
                    }

                    # get current states
                    ENIGMA2_SendCommand( $hash, "getcurrent" );
                    ENIGMA2_SendCommand( $hash, "timerlist" )
                      if ( !AttrVal( $name, "lightMode", 0 ) );
                    ENIGMA2_SendCommand( $hash, "vol" )
                      if ( !AttrVal( $name, "lightMode", 0 ) );
                    ENIGMA2_SendCommand( $hash, "signal" )
                      if ( !AttrVal( $name, "lightMode", 0 ) );
                }
            }
            elsif ( $state ne "undefined" ) {
                Log3 $name, 2,
                  "ENIGMA2 $name: ERROR: Undefined state of device";

                $state = "undefined";
            }
        }

        # update attributes for bouquet names
        elsif ( $service eq "getservices"
            && ( $type eq "defBouquet-tv" || $type eq "defBouquet-radio" ) )
        {
            my $input = ( $type eq "defBouquet-tv" ) ? "tv" : "radio";

            # set FHEM device attribute if not available
            #  multiple
            if (   ref($return) eq "HASH"
                && defined( $return->{e2service} )
                && ref( $return->{e2service} ) eq "ARRAY"
                && defined( $return->{e2service}[0]{e2servicereference} )
                && $return->{e2service}[0]{e2servicereference} ne "" )
            {
                Log3 $name, 3,
                    "ENIGMA2 $name: Adding attribute bouquet-"
                  . $input . " = "
                  . $return->{e2service}[0]{e2servicereference};

                $attr{$name}{ "bouquet-" . $input } =
                  $return->{e2service}[0]{e2servicereference};
            }

            #  single
            elsif (ref($return) eq "HASH"
                && defined( $return->{e2service}{e2servicereference} )
                && $return->{e2service}{e2servicereference} ne "" )
            {
                Log3 $name, 3,
                    "ENIGMA2 $name: Adding attribute bouquet-"
                  . $input . " = "
                  . $return->{e2service}{e2servicereference};

                $attr{$name}{ "bouquet-" . $input } =
                  $return->{e2service}{e2servicereference};
            }
            elsif ( AttrVal( $name, "bouquet-" . $input, "" ) eq "" ) {
                Log3 $name, 3,
                    "ENIGMA2 $name: ERROR: Unable to read any "
                  . $input
                  . " bouquets from device";
            }

            # trigger cache update
            ENIGMA2_SendCommand(
                $hash,
                "getservices",
                "sRef="
                  . urlEncode( AttrVal( $name, "bouquet-" . $input, "" ) ),
                "services-" . $input
            ) if ( AttrVal( $name, "bouquet-" . $input, "" ) ne "" );
        }

        # update cache of tv and radio channels
        elsif ( $service eq "getservices"
            && ( $type eq "services-tv" || $type eq "services-radio" ) )
        {
            my $input = ( $type eq "services-tv" ) ? "tv" : "radio";

            # Read channels
            if ( ref($return) eq "HASH"
                && defined( $return->{e2service} ) )
            {
                # multiple
                if (   ref( $return->{e2service} ) eq "ARRAY"
                    && defined( $return->{e2service}[0]{e2servicename} )
                    && $return->{e2service}[0]{e2servicename} ne ""
                    && defined( $return->{e2service}[0]{e2servicereference} )
                    && $return->{e2service}[0]{e2servicereference} ne "" )
                {
                    my $i = 0;

                    # TODO this loop is >5.012 only
                    for ( keys @{ $return->{e2service} } ) {
                        my $channel =
                          $return->{e2service}[$_]{e2servicename};
                        $channel =~ s/\s/_/g;

                        # ignore markers
                        if ( $return->{e2service}[$_]{e2servicereference} =~
                            /^1:64:/ )
                        {
                            Log3 $name, 4,
                              "ENIGMA2 $name: Ignoring marker "
                              . $return->{e2service}[$_]{e2servicename};
                            next;
                        }

                        if ( $channel ne "" ) {
                            $hash->{helper}{bouquet}{$input}{$channel} =
                              { 'sRef' =>
                                  $return->{e2service}[$_]{e2servicereference}
                              };

                            $hash->{helper}{channels}{$input}[$i] =
                              $channel;
                        }

                        $i++;
                    }

                    Log3 $name, 4,
                        "ENIGMA2 $name: Cached favorite "
                      . $input
                      . " channels: "
                      . join( ', ', @{ $hash->{helper}{channels}{$input} } );
                }

                # single
                elsif (defined( $return->{e2service}{e2servicename} )
                    && $return->{e2service}{e2servicename} ne ""
                    && defined( $return->{e2service}{e2servicereference} )
                    && $return->{e2service}{e2servicereference} ne "" )
                {
                    # ignore markers
                    if ( $return->{e2service}{e2servicereference} =~ /^1:64:/ )
                    {
                        Log3 $name, 4,
                          "ENIGMA2 $name: Ignoring marker "
                          . $return->{e2service}{e2servicename};
                    }
                    else {
                        my $channel = $return->{e2service}{e2servicename};
                        $channel =~ s/\s/_/g;

                        if ( $channel ne "" ) {
                            $hash->{helper}{bouquet}{$input}{$channel} =
                              { 'sRef' =>
                                  $return->{e2service}{e2servicereference} };

                            $hash->{helper}{channels}{$input}[0] =
                              $channel;

                            Log3 $name, 4,
                                "ENIGMA2 $name: Cached favorite "
                              . $input
                              . " channels: "
                              . $hash->{helper}{channels}{$input}[0];
                        }
                    }

                }
                else {
                    Log3 $name, 4,
                        "ENIGMA2 $name: ERROR: bouquet-"
                      . $input
                      . " seems to be empty.";
                }
            }
            elsif ( $input eq "radio" ) {
                Log3 $name, 4,
                    "ENIGMA2 $name: ERROR: Unable to read "
                  . $input
                  . " bouquet '"
                  . AttrVal( $name, "bouquet-" . $input, "" )
                  . "' from device";
            }
            else {
                Log3 $name, 3,
                    "ENIGMA2 $name: ERROR: Unable to read "
                  . $input
                  . " bouquet '"
                  . AttrVal( $name, "bouquet-" . $input, "" )
                  . "' from device";
            }
        }

        # boxinfo
        elsif ( $service eq "about" ) {
            my $reading;
            my $e2reading;
            if ( ref($return) eq "HASH" ) {

                # General readings
                foreach (
                    "enigmaversion", "imageversion", "webifversion",
                    "fpversion",     "lanmac",       "model",
                  )
                {
                    $reading   = $_;
                    $e2reading = "e2" . $_;

                    if ( defined( $return->{e2about}{$e2reading} ) ) {
                        if (   $return->{e2about}{$e2reading} eq "False"
                            || $return->{e2about}{$e2reading} eq "True" )
                        {
                            if ( ReadingsVal( $name, $reading, "" ) ne
                                lc( $return->{e2about}{$e2reading} ) )
                            {
                                readingsBulkUpdate( $hash, $reading,
                                    lc( $return->{e2about}{$e2reading} ) );
                            }
                        }
                        else {
                            if ( ReadingsVal( $name, $reading, "" ) ne
                                $return->{e2about}{$e2reading} )
                            {
                                readingsBulkUpdate( $hash, $reading,
                                    $return->{e2about}{$e2reading} );
                            }
                        }

                        # model
                        if ( $reading eq "model"
                            && ReadingsVal( $name, "model", "" ) ne "" )
                        {
                            my $model = ReadingsVal( $name, "model", "" );
                            $model =~ s/\s/_/g;
                            $hash->{model} = $model;
                        }
                    }

                    else {
                        readingsBulkUpdate( $hash, $reading, "-" )
                          if ( ReadingsVal( $name, $reading, "" ) ne "-" );
                    }
                }

                # HDD
                if ( defined( $return->{e2about}{e2hddinfo} ) ) {

                    # multiple
                    if ( ref( $return->{e2about}{e2hddinfo} ) eq "ARRAY" ) {
                        Log3 $name, 5, "ENIGMA2 $name: multiple HDDs detected";

                        my $i        = 0;
                        my $arr_size = @{ $return->{e2about}{e2hddinfo} };

                        while ( $i < $arr_size ) {
                            my $counter     = $i + 1;
                            my $readingname = "hdd" . $counter . "_model";
                            readingsBulkUpdate( $hash, $readingname,
                                $return->{e2about}{e2hddinfo}[$i]{model} )
                              if ( ReadingsVal( $name, $readingname, "" ) ne
                                $return->{e2about}{e2hddinfo}[$i]{model} );

                            $readingname = "hdd" . $counter . "_capacity";
                            my @value =
                              split( / /,
                                $return->{e2about}{e2hddinfo}[$i]{capacity} );
                            readingsBulkUpdate( $hash, $readingname, $value[0] )
                              if ( @value
                                && ReadingsVal( $name, $readingname, "" ) ne
                                $value[0] );

                            $readingname = "hdd" . $counter . "_free";
                            @value =
                              split( / /,
                                $return->{e2about}{e2hddinfo}[$i]{free} );
                            readingsBulkUpdate( $hash, $readingname, $value[0] )
                              if ( @value
                                && ReadingsVal( $name, $readingname, "" ) ne
                                $value[0] );

                            $i++;
                        }
                    }

                    #  single
                    elsif ( ref( $return->{e2about}{e2hddinfo} ) eq "HASH" ) {
                        Log3 $name, 5, "ENIGMA2 $name: single HDD detected";

                        my $readingname = "hdd1_model";
                        readingsBulkUpdate( $hash, $readingname,
                            $return->{e2about}{e2hddinfo}{model} )
                          if ( ReadingsVal( $name, $readingname, "" ) ne
                            $return->{e2about}{e2hddinfo}{model} );

                        $readingname = "hdd1_capacity";
                        my @value =
                          split( / /, $return->{e2about}{e2hddinfo}{capacity} );
                        readingsBulkUpdate( $hash, $readingname, $value[0] )
                          if ( @value
                            && ReadingsVal( $name, $readingname, "" ) ne
                            $value[0] );

                        $readingname = "hdd1_free";
                        @value =
                          split( / /, $return->{e2about}{e2hddinfo}{free} );
                        readingsBulkUpdate( $hash, $readingname, $value[0] )
                          if ( @value
                            && ReadingsVal( $name, $readingname, "" ) ne
                            $value[0] );
                    }
                    else {
                        Log3 $name, 5,
                          "ENIGMA2 $name: no HDD seems to be installed";
                    }
                }

                # Tuner
                if ( defined( $return->{e2about}{e2tunerinfo}{e2nim} ) ) {

                    # multiple
                    if (
                        ref( $return->{e2about}{e2tunerinfo}{e2nim} ) eq
                        "ARRAY" )
                    {
                        Log3 $name, 5,
                          "ENIGMA2 $name: multi-tuner configuration detected";

                        foreach my $tuner (
                            @{ $return->{e2about}{e2tunerinfo}{e2nim} } )
                        {
                            my $tuner_name = lc( $tuner->{name} );
                            $tuner_name =~ s/\s/_/g;

                            readingsBulkUpdate( $hash, $tuner_name,
                                $tuner->{type} )
                              if ( ReadingsVal( $name, $tuner_name, "" ) ne
                                $tuner->{type} );
                        }
                    }

                    #  single
                    elsif (
                        ref( $return->{e2about}{e2tunerinfo}{e2nim} ) eq
                        "HASH" )
                    {
                        Log3 $name, 5,
                          "ENIGMA2 $name: single-tuner configuration detected";

                        my $tuner_name =
                          lc( $return->{e2about}{e2tunerinfo}{e2nim}{name} );
                        $tuner_name =~ s/\s/_/g;

                        readingsBulkUpdate( $hash, $tuner_name,
                            $return->{e2about}{e2tunerinfo}{e2nim}{type} )
                          if ( ReadingsVal( $name, $tuner_name, "" ) ne
                            $return->{e2about}{e2tunerinfo}{e2nim}{type} );
                    }
                    else {
                        Log3 $name, 5,
                          "ENIGMA2 $name: no tuner could be detected";
                    }
                }
            }
            else {
                Log3 $name, 2,
"ENIGMA2 $name: ERROR: boxinfo could not be read - /about sent malformed response";
            }
        }

        # currsrvinfo
        elsif ( $service eq "getcurrent" ) {
            my $reading;
            my $e2reading;
            if ( ref($return) eq "HASH" ) {

                # Service readings
                foreach (
                    "servicereference", "servicename",
                    "providername",     "servicevideosize",
                    "videowidth",       "videoheight",
                    "iswidescreen",     "apid",
                    "vpid",             "pcrpid",
                    "pmtpid",           "txtpid",
                    "tsid",             "onid",
                    "sid"
                  )
                {
                    $reading   = $_;
                    $e2reading = "e2" . $_;

                    if (   defined( $return->{e2service}{$e2reading} )
                        && lc( $return->{e2service}{$e2reading} ) ne "n/a"
                        && lc( $return->{e2service}{$e2reading} ) ne "n/axn/a"
                        && lc( $return->{e2service}{$e2reading} ) ne "0x0" )
                    {
                        if (   $return->{e2service}{$e2reading} eq "False"
                            || $return->{e2service}{$e2reading} eq "True" )
                        {
                            Log3 $name, 5,
"ENIGMA2 $name: transforming value of $reading to lower case";

                            $return->{e2service}{$e2reading} =
                              lc( $return->{e2service}{$e2reading} );
                        }

                        if ( ReadingsVal( $name, $reading, "" ) ne
                            $return->{e2service}{$e2reading} )
                        {
                            readingsBulkUpdate( $hash, $reading,
                                $return->{e2service}{$e2reading} );

                            # channel
                            if ( $reading eq "servicename" ) {
                                my $val = $return->{e2service}{$e2reading};
                                $val =~ s/\s/_/g;
                                readingsBulkUpdate( $hash, "channel", $val );
                            }

                            # currentMedia
                            readingsBulkUpdate( $hash, "currentMedia",
                                $return->{e2service}{$e2reading} )
                              if $reading eq "servicereference";
                        }

                        # input
                        if ( $reading eq "servicereference" ) {
                            my @servicetype =
                              split( /:/, $return->{e2service}{$e2reading} );

                            if (   defined( $servicetype[2] )
                                && $servicetype[2] ne "2"
                                && $servicetype[2] ne "10" )
                            {
                                Log3 $name, 5,
"ENIGMA2 $name: detected servicereference type: tv";
                                readingsBulkUpdate( $hash, "input", "tv" )
                                  if (
                                    ReadingsVal( $name, "input", "" ) ne "tv" );

                            }
                            elsif (
                                defined( $servicetype[2] )
                                && (   $servicetype[2] eq "2"
                                    || $servicetype[2] eq "10" )
                              )
                            {
                                Log3 $name, 5,
"ENIGMA2 $name: detected servicereference type: radio";
                                readingsBulkUpdate( $hash, "input", "radio" )
                                  if ( ReadingsVal( $name, "input", "" ) ne
                                    "radio" );
                            }
                            else {
                                Log3 $name, 2,
"ENIGMA2 $name: ERROR: servicereference type could not be detected (neither 'tv' nor 'radio')";
                            }
                        }
                    }
                    else {
                        Log3 $name, 5,
"ENIGMA2 $name: received no value for reading $reading";

                        if ( ReadingsVal( $name, $reading, "" ) ne "-" ) {
                            readingsBulkUpdate( $hash, $reading, "-" );

                            # channel
                            readingsBulkUpdate( $hash, "channel", "-" )
                              if $reading eq "servicename";

                            # currentMedia
                            readingsBulkUpdate( $hash, "currentMedia", "-" )
                              if $reading eq "servicereference";
                        }
                    }
                }

                # Event readings
                #
                if ( defined( $return->{e2eventlist} ) ) {
                    my $eventNow;
                    my $eventNext;

                    if ( ref( $return->{e2eventlist}{e2event} ) eq "ARRAY" ) {
                        Log3 $name, 5,
                          "ENIGMA2 $name: detected multiple event details";

                        $eventNow  = $return->{e2eventlist}{e2event}[0];
                        $eventNext = $return->{e2eventlist}{e2event}[1]
                          if ( defined( $return->{e2eventlist}{e2event}[1] ) );
                    }
                    else {
                        Log3 $name, 5,
                          "ENIGMA2 $name: detected single event details";
                        $eventNow = $return->{e2eventlist}{e2event};
                    }

                    foreach (
                        "eventstart",       "eventduration",
                        "eventremaining",   "eventcurrenttime",
                        "eventdescription", "eventtitle",
                        "eventname",
                      )
                    {
                        $reading   = $_;
                        $e2reading = "e2" . $_;

                        # current event
                        if (   defined( $eventNow->{$e2reading} )
                            && lc( $eventNow->{$e2reading} ) ne "n/a"
                            && $eventNow->{$e2reading} ne "0"
                            && $eventNow->{$e2reading} ne "" )
                        {
                            Log3 $name, 5,
"ENIGMA2 $name: detected valid reading $e2reading for current event";

                            if ( ReadingsVal( $name, $reading, "" ) ne
                                $eventNow->{$e2reading} )
                            {
                                readingsBulkUpdate( $hash, $reading,
                                    $eventNow->{$e2reading} );

                                # currentTitle
                                readingsBulkUpdate( $hash, "currentTitle",
                                    $eventNow->{$e2reading} )
                                  if $reading eq "eventtitle";
                            }
                        }
                        else {
                            Log3 $name, 5,
"ENIGMA2 $name: no valid reading $e2reading found for current event";

                            if ( ReadingsVal( $name, $reading, "" ) ne "-" ) {
                                readingsBulkUpdate( $hash, $reading, "-" );

                                # currentTitle
                                readingsBulkUpdate( $hash, "currentTitle", "-" )
                                  if $reading eq "eventtitle";
                            }
                        }

                        # next event
                        $reading = $_ . "_next";
                        if (   defined( $eventNext->{$e2reading} )
                            && lc( $eventNext->{$e2reading} ) ne "n/a"
                            && $eventNext->{$e2reading} ne "0"
                            && $eventNext->{$e2reading} ne "" )
                        {
                            Log3 $name, 5,
"ENIGMA2 $name: detected valid reading $e2reading for next event";

                            if ( ReadingsVal( $name, $reading, "" ) ne
                                $eventNext->{$e2reading} )
                            {
                                readingsBulkUpdate( $hash, $reading,
                                    $eventNext->{$e2reading} );

                                # nextTitle
                                readingsBulkUpdate( $hash, "nextTitle",
                                    $eventNext->{$e2reading} )
                                  if $reading eq "eventtitle_next";
                            }
                        }
                        else {
                            Log3 $name, 5,
"ENIGMA2 $name: no valid reading $e2reading found for next event";

                            if ( ReadingsVal( $name, $reading, "" ) ne "-" ) {
                                readingsBulkUpdate( $hash, $reading, "-" );

                                # nextTitle
                                readingsBulkUpdate( $hash, "nextTitle", "-" )
                                  if $reading eq "eventtitle_next";
                            }
                        }
                    }

                    # convert date+time into human readable formats
                    foreach (
                        "eventstart",    "eventcurrenttime",
                        "eventduration", "eventremaining"
                      )
                    {
                        $reading   = $_ . "_hr";
                        $e2reading = "e2" . $_;

                        # current event
                        if (   defined( $eventNow->{$e2reading} )
                            && $eventNow->{$e2reading} ne "0"
                            && $eventNow->{$e2reading} ne "" )
                        {
                            my $timestring;
                            if (   $_ eq "eventduration"
                                || $_ eq "eventremaining" )
                            {
                                my @t = localtime( $eventNow->{$e2reading} );
                                $timestring = sprintf( "%02d:%02d:%02d",
                                    $t[2] - 1,
                                    $t[1], $t[0] );
                            }
                            else {
                                $timestring =
                                  substr(
                                    FmtDateTime( $eventNow->{$e2reading} ),
                                    11 );
                            }

                            readingsBulkUpdate( $hash, $reading, $timestring )
                              if ( ReadingsVal( $name, $reading, "" ) ne
                                $timestring );
                        }
                        else {
                            readingsBulkUpdate( $hash, $reading, "-" )
                              if ( ReadingsVal( $name, $reading, "" ) ne "-" );
                        }

                        # next event
                        $reading = $_ . "_next_hr";
                        if (   defined( $eventNext->{$e2reading} )
                            && $eventNext->{$e2reading} ne "0"
                            && $eventNext->{$e2reading} ne "" )
                        {
                            my $timestring;
                            if (   $_ eq "eventduration"
                                || $_ eq "eventremaining" )
                            {
                                my @t = localtime( $eventNext->{$e2reading} );
                                $timestring = sprintf( "%02d:%02d:%02d",
                                    $t[2] - 1,
                                    $t[1], $t[0] );
                            }
                            else {
                                $timestring =
                                  substr(
                                    FmtDateTime( $eventNext->{$e2reading} ),
                                    11 );
                            }

                            readingsBulkUpdate( $hash, $reading, $timestring )
                              if ( ReadingsVal( $name, $reading, "" ) ne
                                $timestring );
                        }
                        else {
                            readingsBulkUpdate( $hash, $reading, "-" )
                              if ( ReadingsVal( $name, $reading, "" ) ne "-" );
                        }
                    }
                }
            }
            else {
                Log3 $name, 2,
"ENIGMA2 $name: ERROR: current service info could not be read - /getcurrent sent malformed response";
            }

        }

        # timerlist
        elsif ( $service eq "timerlist" ) {
            my $activeRecordings = 0;
            my %recordings;

            my $recordingsNext_time       = "0";
            my $recordingsNext_time_hr    = "-";
            my $recordingsNext_counter    = "0";
            my $recordingsNext_counter_hr = "-";
            my $recordingsNextServicename = "-";
            my $recordingsNextName        = "-";

            my $recordingsError    = 0;
            my $recordingsFinished = 0;

            if ( ref($return) eq "HASH" ) {
                if ( ref( $return->{e2timer} ) eq "HASH" ) {
                    Log3 $name, 5,
                      "ENIGMA2 $name: detected single event in timerlist";

                    # queued recording
                    if (   defined( $return->{e2timer}{e2state} )
                        && $return->{e2timer}{e2state} eq "0"
                        && defined( $return->{e2timer}{e2disabled} )
                        && $return->{e2timer}{e2disabled} eq "0"
                        && defined( $return->{e2timer}{e2eit} )
                        && defined( $return->{e2timer}{e2servicename} )
                        && defined( $return->{e2timer}{e2name} ) )
                    {

                        my $timeleft =
                          $return->{e2timer}{e2startprepare} - time();

                        # only add if starttime is smaller
                        if (   $recordingsNext_time eq "0"
                            || $timeleft < $recordingsNext_time - time() )
                        {
                            my @t =
                              localtime( $return->{e2timer}{e2startprepare} );

                            $recordingsNext_time =
                              $return->{e2timer}{e2startprepare};
                            $recordingsNext_time_hr =
                              sprintf( "%02d:%02d:%02d", $t[2], $t[1], $t[0] );
                            $recordingsNext_counter = int( $timeleft + 0.5 );
                            $recordingsNextServicename =
                              $return->{e2timer}{e2servicename};
                            $recordingsNextName = $return->{e2timer}{e2name};

                            # human readable
                            my @t2 = localtime($timeleft);
                            $recordingsNext_counter_hr =
                              sprintf( "%02d:%02d:%02d",
                                $t2[2] - 1,
                                $t2[1], $t2[0] );
                        }
                    }

                    # failed recording
                    if ( defined( $return->{e2timer}{e2state} )
                        && $return->{e2timer}{e2state} eq "1" )
                    {
                        $recordingsError++;
                    }

                    # active recording
                    if (   defined( $return->{e2timer}{e2state} )
                        && $return->{e2timer}{e2state} eq "2"
                        && defined( $return->{e2timer}{e2servicename} )
                        && defined( $return->{e2timer}{e2name} ) )
                    {
                        $activeRecordings++;
                        $recordings{$activeRecordings}{servicename} =
                          $return->{e2timer}{e2servicename};
                        $recordings{$activeRecordings}{name} =
                          $return->{e2timer}{e2name};
                    }

                    # finished recording
                    if ( defined( $return->{e2timer}{e2state} )
                        && $return->{e2timer}{e2state} eq "3" )
                    {
                        $recordingsFinished++;
                    }
                }
                elsif ( ref( $return->{e2timer} ) eq "ARRAY" ) {

                    Log3 $name, 5,
                      "ENIGMA2 $name: detected multiple events in timerlist";

                    my $i        = 0;
                    my $arr_size = @{ $return->{e2timer} };

                    while ( $i < $arr_size ) {

                        # queued recording
                        if (   defined( $return->{e2timer}[$i]{e2state} )
                            && $return->{e2timer}[$i]{e2state} eq "0"
                            && defined( $return->{e2timer}[$i]{e2disabled} )
                            && $return->{e2timer}[$i]{e2disabled} eq "0"
                            && defined( $return->{e2timer}[$i]{e2eit} )
                            && defined( $return->{e2timer}[$i]{e2servicename} )
                            && defined( $return->{e2timer}[$i]{e2name} ) )
                        {

                            my $timeleft =
                              $return->{e2timer}[$i]{e2startprepare} - time();

                            # only add if starttime is smaller
                            if (   $recordingsNext_time eq "0"
                                || $timeleft < $recordingsNext_time - time() )
                            {
                                my @t =
                                  localtime(
                                    $return->{e2timer}[$i]{e2startprepare} );

                                $recordingsNext_time =
                                  $return->{e2timer}[$i]{e2startprepare};
                                $recordingsNext_time_hr =
                                  sprintf( "%02d:%02d:%02d",
                                    $t[2], $t[1], $t[0] );
                                $recordingsNext_counter = $timeleft;
                                $recordingsNextServicename =
                                  $return->{e2timer}[$i]{e2servicename};
                                $recordingsNextName =
                                  $return->{e2timer}[$i]{e2name};

                                # human readable
                                my @t2 = localtime($timeleft);
                                $recordingsNext_counter_hr =
                                  sprintf( "%02d:%02d:%02d",
                                    $t2[2] - 1,
                                    $t2[1], $t2[0] );
                            }
                        }

                        # failed recording
                        if ( defined( $return->{e2timer}[$i]{e2state} )
                            && $return->{e2timer}[$i]{e2state} eq "1" )
                        {
                            $recordingsError++;
                        }

                        # active recording
                        if (   defined( $return->{e2timer}[$i]{e2state} )
                            && $return->{e2timer}[$i]{e2state} eq "2"
                            && defined( $return->{e2timer}[$i]{e2servicename} )
                            && defined( $return->{e2timer}[$i]{e2name} ) )
                        {
                            $activeRecordings++;
                            $recordings{$activeRecordings}{servicename} =
                              $return->{e2timer}[$i]{e2servicename};
                            $recordings{$activeRecordings}{name} =
                              $return->{e2timer}[$i]{e2name};
                        }

                        # finished recording
                        if ( defined( $return->{e2timer}[$i]{e2state} )
                            && $return->{e2timer}[$i]{e2state} eq "3" )
                        {
                            $recordingsFinished++;
                        }

                        $i++;
                    }
                }
            }
            else {
                Log3 $name, 5, "ENIGMA2 $name: timerlist seems to be empty";
            }

            my $recordingsElementsCount = scalar( keys %recordings );
            my $readingname;

            readingsBulkUpdate( $hash, "recordings", $recordingsElementsCount )
              if ( ReadingsVal( $name, "recordings", "" ) ne
                $recordingsElementsCount );

            if ( $recordingsElementsCount > 0 ) {
                my $i = 0;

                while ( $i < $recordingsElementsCount ) {
                    $i++;

                    $readingname = "recordings" . $i . "_servicename";
                    readingsBulkUpdate( $hash, $readingname,
                        $recordings{$i}{servicename} )
                      if ( ReadingsVal( $name, $readingname, "" ) ne
                        $recordings{$i}{servicename} );

                    $readingname = "recordings" . $i . "_name";
                    readingsBulkUpdate( $hash, $readingname,
                        $recordings{$i}{name} )
                      if ( ReadingsVal( $name, $readingname, "" ) ne
                        $recordings{$i}{name} );
                }
            }

            # clear inactive recordingsX_* readings
            foreach my $recReading (
                grep { /recordings\d_.*/ }
                keys %{ $defs{$name}{READINGS} }
              )
            {
                Log3 $name, 5,
                  "ENIGMA2 $name: old reading $recReading was deleted";
                delete( $defs{$name}{READINGS}{$recReading} );
            }

            readingsBulkUpdate( $hash, "recordings_next", $recordingsNext_time )
              if ( ReadingsVal( $name, "recordings_next", "" ) ne
                $recordingsNext_time );

            readingsBulkUpdate( $hash, "recordings_next_hr",
                $recordingsNext_time_hr )
              if ( ReadingsVal( $name, "recordings_next_hr", "" ) ne
                $recordingsNext_time_hr );

            readingsBulkUpdate( $hash, "recordings_next_counter",
                $recordingsNext_counter )
              if ( ReadingsVal( $name, "recordings_next_counter", "" ) ne
                $recordingsNext_counter );

            readingsBulkUpdate( $hash, "recordings_next_counter_hr",
                $recordingsNext_counter_hr )
              if ( ReadingsVal( $name, "recordings_next_counter_hr", "" ) ne
                $recordingsNext_counter_hr );

            readingsBulkUpdate( $hash, "recordings_next_servicename",
                $recordingsNextServicename )
              if ( ReadingsVal( $name, "recordings_next_servicename", "" ) ne
                $recordingsNextServicename );

            readingsBulkUpdate( $hash, "recordings_next_name",
                $recordingsNextName )
              if ( ReadingsVal( $name, "recordings_next_name", "" ) ne
                $recordingsNextName );

            readingsBulkUpdate( $hash, "recordings_error", $recordingsError )
              if ( ReadingsVal( $name, "recordings_error", "" ) ne
                $recordingsError );

            readingsBulkUpdate( $hash, "recordings_finished",
                $recordingsFinished )
              if ( ReadingsVal( $name, "recordings_finished", "" ) ne
                $recordingsFinished );
        }

        # volume
        elsif ( $service eq "vol" ) {
            if ( ref($return) eq "HASH" && defined( $return->{e2current} ) ) {
                readingsBulkUpdate( $hash, "volume", $return->{e2current} )
                  if (
                    ReadingsVal( $name, "volume", "" ) ne $return->{e2current}
                  );
            }
            else {
                Log3 $name, 5,
                  "ENIGMA2 $name: ERROR: no volume could be extracted";
            }

            if ( ref($return) eq "HASH" && defined( $return->{e2ismuted} ) ) {
                my $muteState = "on";
                $muteState = "off"
                  if ( lc( $return->{e2ismuted} ) eq "false" );
                readingsBulkUpdate( $hash, "mute", $muteState )
                  if ( ReadingsVal( $name, "mute", "" ) ne $muteState );
            }
            else {
                Log3 $name, 5,
                  "ENIGMA2 $name: ERROR: no mute state could be extracted";
            }
        }

        # signal
        elsif ( $service eq "signal" ) {
            my $reading;
            my $e2reading;
            if ( ref($return) eq "HASH"
                && defined( $return->{e2snrdb} ) )
            {
                foreach ( "snrdb", "snr", "ber", "acg", ) {
                    $reading   = $_;
                    $e2reading = "e2" . $_;

                    if ( defined( $return->{$e2reading} )
                        && lc( $return->{$e2reading} ) ne "n/a" )
                    {
                        my @value = split( / /, $return->{$e2reading} );
                        if ( defined( $value[1] ) || $reading eq "ber" ) {
                            readingsBulkUpdate( $hash, $reading, $value[0] );
                        }
                        else {
                            readingsBulkUpdate( $hash, $reading, "0" );
                        }
                    }
                    else {
                        readingsBulkUpdate( $hash, $reading, "0" );
                    }
                }
            }
            else {
                Log3 $name, 5,
                  "ENIGMA2 $name: ERROR: no signal information could be found";
            }
        }

        # all other command results
        else {
            ENIGMA2_GetStatus( $hash, 1 );
        }
    }

    # Set reading for power
    #
    my $readingPower = "off";
    $readingPower = "on"
      if ( $state eq "on" );
    readingsBulkUpdate( $hash, "power", $readingPower )
      if ( ReadingsVal( $name, "power", "" ) ne $readingPower );

    # Set reading for state
    #
    readingsBulkUpdate( $hash, "state", $state )
      if ( ReadingsVal( $name, "state", "" ) ne $state );

    # Set ENIGMA2 online-only readings to "-" in case box is in
    # offline or in standby mode
    if (   $state eq "off"
        || $state eq "absent"
        || $state eq "undefined" )
    {
        foreach (
            'servicename',            'providername',
            'servicereference',       'videowidth',
            'videoheight',            'servicevideosize',
            'apid',                   'vpid',
            'pcrpid',                 'pmtpid',
            'txtpid',                 'tsid',
            'onid',                   'sid',
            'iswidescreen',           'mute',
            'volume',                 'channel',
            'currentTitle',           'nextTitle',
            'currentMedia',           'eventcurrenttime',
            'eventcurrenttime_hr',    'eventdescription',
            'eventduration',          'eventduration_hr',
            'eventremaining',         'eventremaining_hr',
            'eventstart',             'eventstart_hr',
            'eventtitle',             'eventname',
            'eventcurrenttime_next',  'eventcurrenttime_next_hr',
            'eventdescription_next',  'eventduration_next',
            'eventduration_next_hr',  'eventremaining_next',
            'eventremaining_next_hr', 'eventstart_next',
            'eventstart_next_hr',     'eventtitle_next',
            'eventname_next',
          )
        {
            readingsBulkUpdate( $hash, $_, "-" )
              if ( ReadingsVal( $name, $_, "" ) ne "-" );
        }

        # special handling for signal values
        foreach ( 'acg', 'ber', 'snr', 'snrdb', ) {
            readingsBulkUpdate( $hash, $_, "0" )
              if ( ReadingsVal( $name, $_, "" ) ne "0" );
        }
    }

    # Set ENIGMA2 online+standby readings to "-" in case box is in
    # offline mode
    if ( $state eq "absent" || $state eq "undefined" ) {
        readingsBulkUpdate( $hash, "input", "-" )
          if ( ReadingsVal( $name, "input", "" ) ne "-" );
    }

    readingsEndUpdate( $hash, 1 );

    undef $return;
    return;
}

###################################
sub ENIGMA2_Undefine($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "ENIGMA2 $name: called function ENIGMA2_Undefine()";

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return;
}

###################################
sub ENIGMA2_wake ($$) {
    my ( $name, $mac_addr ) = @_;
    my $address;
    my $port;

    if ( !defined $address ) { $address = '255.255.255.255' }
    if ( !defined $port || $port !~ /^\d+$/ ) { $port = 9 }

    my $sock = new IO::Socket::INET( Proto => 'udp' )
      or die "socket : $!";
    die "Can't create WOL socket" if ( !$sock );

    my $ip_addr = inet_aton($address);
    my $sock_addr = sockaddr_in( $port, $ip_addr );
    $mac_addr =~ s/://g;
    my $packet =
      pack( 'C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16 );

    setsockopt( $sock, SOL_SOCKET, SO_BROADCAST, 1 )
      or die "setsockopt : $!";

    Log3 $name, 4,
      "ENIGMA2 $name: Waking up by sending Wake-On-Lan magic package to "
      . $mac_addr;
    send( $sock, $packet, 0, $sock_addr ) or die "send : $!";
    close($sock);

    return;
}

#####################################
# Callback from 95_remotecontrol for command makenotify.
sub ENIGMA2_RCmakenotify($$) {
    my ( $nam, $ndev ) = @_;
    my $nname = "notify_$nam";

    fhem( "define $nname notify $nam set $ndev remoteControl " . '$EVENT', 1 );
    Log3 undef, 2, "[remotecontrol:ENIGMA2] Notify created: $nname";
    return "Notify created by ENIGMA2: $nname";
}

#####################################
# RC layouts

# Dreambox DM500 + DM800 with SVG
sub ENIGMA2_RClayout_DM800_SVG() {
    my @row;

    $row[0] = ":rc_BLANK.svg,:rc_BLANK.svg,POWER:rc_POWER.svg";
    $row[1] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[2] = "1:rc_1.svg,2:rc_2.svg,3:rc_3.svg";
    $row[3] = "4:rc_4.svg,5:rc_5.svg,6:rc_6.svg";
    $row[4] = "7:rc_7.svg,8:rc_8.svg,9:rc_9.svg";
    $row[5] = "LEFTBRACE:rc_PREVIOUS.svg,0:rc_0.svg,RIGHTBRACE:rc_NEXT.svg";
    $row[6] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[7] = "VOLUMEUP:rc_VOLPLUS.svg,MUTE:rc_MUTE.svg,CHANNELUP:rc_UP.svg";
    $row[8] =
      "VOLUMEDOWN:rc_VOLMINUS.svg,EXIT:rc_EXIT.svg,CHANNELDOWN:rc_DOWN.svg";
    $row[9] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[10] = "INFO:rc_INFO.svg,UP:rc_UP.svg,MENU:rc_MENU.svg";
    $row[11] = "LEFT:rc_LEFT.svg,OK:rc_OK.svg,RIGHT:rc_RIGHT.svg";
    $row[12] = "AUDIO:rc_AUDIO.svg,DOWN:rc_DOWN.svg,VIDEO:rc_VIDEO.svg";
    $row[13] = ":rc_BLANK.svg,EXIT:rc_EXIT.svg,:rc_BLANK.svg";

    $row[14] =
"RED:rc_REWred.svg,GREEN:rc_PLAYgreen.svg,YELLOW:rc_PAUSEyellow.svg,BLUE:rc_FFblue.svg";
    $row[15] =
"TV:rc_TVstop.svg,RADIO:rc_RADIOred.svg,TEXT:rc_TEXT.svg,HELP:rc_HELP.svg";

    $row[16] = "attr rc_iconpath icons/remotecontrol";
    $row[17] = "attr rc_iconprefix black_btn_";
    return @row;
}

# Dreambox DM500 + DM800 with PNG
sub ENIGMA2_RClayout_DM800() {
    my @row;

    $row[0] = ":blank,:blank,POWER:POWEROFF";
    $row[1] = ":blank,:blank,:blank";

    $row[2] = "1,2,3";
    $row[3] = "4,5,6";
    $row[4] = "7,8,9";
    $row[5] = "LEFTBRACE:LEFT2,0:0,RIGHTBRACE:RIGHT2";
    $row[6] = ":blank,:blank,:blank";

    $row[7] = "VOLUMEUP:VOLUP,MUTE,CHANNELUP:CHUP2";
    $row[8] = "VOLUMEDOWN:VOLDOWN,EXIT,CHANNELDOWN:CHDOWN2";
    $row[9] = ":blank,:blank,:blank";

    $row[10] = "INFO,UP,MENU";
    $row[11] = "LEFT,OK,RIGHT";
    $row[12] = "AUDIO,DOWN,VIDEO";
    $row[13] = ":blank,:blank,:blank";

    $row[14] = "RED:REWINDred,GREEN:PLAYgreen,YELLOW:PAUSEyellow,BLUE:FFblue";
    $row[15] = "TV:TVstop,RADIO:RADIOred,TEXT,HELP";

    $row[16] = "attr rc_iconpath icons/remotecontrol";
    $row[17] = "attr rc_iconprefix black_btn_";
    return @row;
}

# Dreambox DM800se + DM8000 with SVG
sub ENIGMA2_RClayout_DM8000_SVG() {
    my @row;

    $row[0] = ":rc_BLANK.svg,:rc_BLANK.svg,POWER:rc_POWER.svg";
    $row[1] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[2] = "1:rc_1.svg,2:rc_2.svg,3:rc_3.svg";
    $row[3] = "4:rc_4.svg,5:rc_5.svg,6:rc_6.svg";
    $row[4] = "7:rc_7.svg,8:rc_8.svg,9:rc_9.svg";
    $row[5] = "LEFTBRACE:rc_PREVIOUS.svg,0:rc_0.svg,RIGHTBRACE:rc_NEXT.svg";
    $row[6] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[7] = "VOLUMEUP:rc_VOLPLUS.svg,MUTE:rc_MUTE.svg,CHANNELUP:rc_UP.svg";
    $row[8] =
      "VOLUMEDOWN:rc_VOLMINUS.svg,EXIT:rc_EXIT.svg,CHANNELDOWN:rc_DOWN.svg";
    $row[9] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[10] = "INFO:rc_INFO.svg,UP:rc_UP.svg,MENU:rc_MENU.svg";
    $row[11] = "LEFT:rc_LEFT.svg,OK:rc_OK.svg,RIGHT:rc_RIGHT.svg";
    $row[12] = "AUDIO:rc_AUDIO.svg,DOWN:rc_DOWN.svg,VIDEO:rc_VIDEO.svg";
    $row[13] = ":rc_BLANK.svg,EXIT:rc_EXIT.svg,:rc_BLANK.svg";

    $row[14] =
      "RED:rc_RED.svg,GREEN:rc_GREEN.svg,YELLOW:rc_YELLOW.svg,BLUE:rc_BLUE.svg";
    $row[15] =
"REWIND:rc_REW.svg,PLAY:rc_PLAY.svg,STOP:rc_STOP.svg,FASTFORWARD:rc_FF.svg";
    $row[16] =
      "TV:rc_TV.svg,RADIO:rc_RADIO.svg,TEXT:rc_TEXT.svg,RECORD:rc_REC.svg";

    $row[17] = "attr rc_iconpath icons/remotecontrol";
    $row[18] = "attr rc_iconprefix black_btn_";
    return @row;
}

# Dreambox DM800se + DM8000 with PNG
sub ENIGMA2_RClayout_DM8000() {
    my @row;

    $row[0] = ":blank,:blank,POWER:POWEROFF";
    $row[1] = ":blank,:blank,:blank";

    $row[2] = "1,2,3";
    $row[3] = "4,5,6";
    $row[4] = "7,8,9";
    $row[5] = "LEFTBRACE:LEFT2,0:0,RIGHTBRACE:RIGHT2";
    $row[6] = ":blank,:blank,:blank";

    $row[7] = "VOLUMEUP:VOLUP,MUTE,CHANNELUP:CHUP2";
    $row[8] = "VOLUMEDOWN:VOLDOWN,EXIT,CHANNELDOWN:CHDOWN2";
    $row[9] = ":blank,:blank,:blank";

    $row[10] = "INFO,UP,MENU";
    $row[11] = "LEFT,OK,RIGHT";
    $row[12] = "AUDIO,DOWN,VIDEO";
    $row[13] = ":blank,:blank,:blank";

    $row[14] = "RED,GREEN,YELLOW,BLUE";
    $row[15] = "REWIND,PLAY,STOP,FASTFORWARD:FF";
    $row[16] = "TV,RADIO,TEXT,RECORD:REC";

    $row[17] = "attr rc_iconpath icons/remotecontrol";
    $row[18] = "attr rc_iconprefix black_btn_";
    return @row;
}

# Dreambox RC10 with SVG
sub ENIGMA2_RClayout_RC10_SVG() {
    my @row;

    $row[0] = ":rc_BLANK.svg,:rc_BLANK.svg,POWER:rc_POWER.svg";
    $row[1] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[2] = "1:rc_1.svg,2:rc_2.svg,3:rc_3.svg";
    $row[3] = "4:rc_4.svg,5:rc_5.svg,6:rc_6.svg";
    $row[4] = "7:rc_7.svg,8:rc_8.svg,9:rc_9.svg";
    $row[5] = "LEFTBRACE:rc_PREVIOUS.svg,0:rc_0.svg,RIGHTBRACE:rc_NEXT.svg";
    $row[6] =
      "RED:rc_RED.svg,GREEN:rc_GREEN.svg,YELLOW:rc_YELLOW.svg,BLUE:rc_BLUE.svg";
    $row[7] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[8]  = "INFO:rc_INFO.svg,UP:rc_UP.svg,MENU:rc_MENU.svg";
    $row[9]  = "LEFT:rc_LEFT.svg,OK:rc_OK.svg,RIGHT:rc_RIGHT.svg";
    $row[10] = "AUDIO:rc_AUDIO.svg,DOWN:rc_DOWN.svg,VIDEO:rc_VIDEO.svg";
    $row[11] = ":rc_BLANK.svg,EXIT:rc_EXIT.svg,:rc_BLANK.svg";

    $row[12] = "VOLUMEUP:rc_VOLPLUS.svg,:rc_BLANK.svg,CHANNELUP:rc_UP.svg";
    $row[13] =
      "VOLUMEDOWN:rc_VOLMINUS.svg,MUTE:rc_MUTE.svg,CHANNELDOWN:rc_DOWN.svg";
    $row[14] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[15] =
"REWIND:rc_REW.svg,PLAY:rc_PLAY.svg,STOP:rc_STOP.svg,FASTFORWARD:rc_FF.svg";
    $row[16] =
      "TV:rc_TV.svg,RADIO:rc_RADIO.svg,TEXT:rc_TEXT.svg,RECORD:rc_REC.svg";

    $row[17] = "attr rc_iconpath icons";
    $row[18] = "attr rc_iconprefix rc_";
    return @row;
}

# Dreambox RC10 with PNG
sub ENIGMA2_RClayout_RC10() {
    my @row;

    $row[0] = ":blank,:blank,POWER:POWEROFF";
    $row[1] = ":blank,:blank,:blank";

    $row[2] = "1,2,3";
    $row[3] = "4,5,6";
    $row[4] = "7,8,9";
    $row[5] = "LEFTBRACE:LEFT2,0:0,RIGHTBRACE:RIGHT2";
    $row[6] = "RED,GREEN,YELLOW,BLUE";
    $row[7] = ":blank,:blank,:blank";

    $row[8]  = "INFO,UP,MENU";
    $row[9]  = "LEFT,OK,RIGHT";
    $row[10] = "AUDIO,DOWN,VIDEO";
    $row[11] = ":blank,EXIT,:blank";

    $row[12] = "VOLUMEUP:VOLUP,:blank,CHANNELUP:CHUP2";
    $row[13] = "VOLUMEDOWN:VOLDOWN,MUTE,CHANNELDOWN:CHDOWN2";
    $row[14] = ":blank,:blank,:blank";

    $row[15] = "REWIND,PLAY,STOP,FASTFORWARD:FF";
    $row[16] = "TV,RADIO,TEXT,RECORD:REC";

    $row[17] = "attr rc_iconpath icons/remotecontrol";
    $row[18] = "attr rc_iconprefix black_btn_";
    return @row;
}

# VU+ Duo2 with SVG
sub ENIGMA2_RClayout_VUplusDuo2_SVG() {
    my @row;

    $row[0] = ":rc_BLANK.svg,MUTE:rc_MUTE.svg,POWER:rc_POWER.svg";
    $row[1] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[2] = "REWIND:rc_REW.svg,PLAY:rc_PLAY.svg,FASTFORWARD:rc_FF.svg";
    $row[3] = "RECORD:rc_REC.svg,STOP:rc_STOP.svg,VIDEO:rc_VIDEO.svg";
    $row[4] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[5] = "TV:rc_TV.svg,AUDIO:rc_AUDIO.svg,RADIO:rc_RADIO.svg";
    $row[6] = "TEXT:rc_TEXT.svg,HELP:rc_HELP.svg,AV:rc_AV.svg";
    $row[7] = "INFO:rc_EPG.svg,MENU:rc_MENU.svg,EXIT:rc_EXIT.svg";
    $row[8] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[9]  = "VOLUMEUP:rc_VOLPLUS.svg,UP:rc_UP.svg,CHANNELUP:rc_PLUS.svg";
    $row[10] = "LEFT:rc_LEFT.svg,OK:rc_OK.svg,RIGHT:rc_RIGHT.svg";
    $row[11] =
      "VOLUMEDOWN:rc_VOLMINUS.svg,DOWN:rc_DOWN.svg,CHANNELDOWN:rc_MINUS.svg";

    $row[12] = ":rc_BLANK.svg,:rc_BLANK.svg,:rc_BLANK.svg";

    $row[13] =
      "RED:rc_RED.svg,GREEN:rc_GREEN.svg,YELLOW:rc_YELLOW.svg,BLUE:rc_BLUE.svg";
    $row[14] = "1:rc_1.svg,2:rc_2.svg,3:rc_3.svg";
    $row[15] = "4:rc_4.svg,5:rc_5.svg,6:rc_6.svg";
    $row[16] = "7:rc_7.svg,8:rc_8.svg,9:rc_9.svg";
    $row[17] = "LEFTBRACE:rc_PREVIOUS.svg,0:rc_0.svg,RIGHTBRACE:rc_NEXT.svg";

    $row[18] = "attr rc_iconpath icons";
    $row[19] = "attr rc_iconprefix rc_";
    return @row;
}

# VU+ Duo2 with PNG
sub ENIGMA2_RClayout_VUplusDuo2() {
    my @row;

    $row[0] = ":blank,MUTE,POWER:POWEROFF";
    $row[1] = ":blank,:blank,:blank";

    $row[2] = "REWIND,PLAY,FASTFORWARD:FF";
    $row[3] = "RECORD:REC,STOP,VIDEO";
    $row[4] = ":blank,:blank,:blank";

    $row[5] = "TV,AUDIO,RADIO:RADIO";
    $row[6] = "TEXT,HELP,AV";
    $row[7] = "INFO,MENU,EXIT";
    $row[8] = ":blank,:blank,:blank";

    $row[9]  = "VOLUMEUP:VOLUP,UP,CHANNELUP:CHUP2";
    $row[10] = "LEFT,OK,RIGHT";
    $row[11] = "VOLUMEDOWN:VOLDOWN,DOWN,CHANNELDOWN:CHDOWN2";

    $row[12] = ":blank,:blank,:blank";

    $row[13] = "RED,GREEN,YELLOW,BLUE";
    $row[14] = "1,2,3";
    $row[15] = "4,5,6";
    $row[16] = "7,8,9";
    $row[17] = "LEFTBRACE:LEFT2,0:0,RIGHTBRACE:RIGHT2";

    $row[18] = "attr rc_iconpath icons/remotecontrol";
    $row[19] = "attr rc_iconprefix black_btn_";
    return @row;
}

###################################
sub ENIGMA2_GetRemotecontrolCommand($) {
    my ($command) = @_;
    my $commands = {
        'RESERVED'       => 0,
        'ESC'            => 1,
        '1'              => 2,
        '2'              => 3,
        '3'              => 4,
        '4'              => 5,
        '5'              => 6,
        '6'              => 7,
        '7'              => 8,
        '8'              => 9,
        '9'              => 10,
        '0'              => 11,
        'MINUS'          => 12,
        'EQUAL'          => 13,
        'BACKSPACE'      => 14,
        'TAB'            => 15,
        'Q'              => 16,
        'W'              => 17,
        'E'              => 18,
        'R'              => 19,
        'T'              => 20,
        'Y'              => 21,
        'U'              => 22,
        'I'              => 23,
        'O'              => 24,
        'P'              => 25,
        'LEFTBRACE'      => 26,
        'RIGHTBRACE'     => 27,
        'ENTER'          => 28,
        'LEFTCTRL'       => 29,
        'A'              => 30,
        'S'              => 31,
        'D'              => 32,
        'F'              => 33,
        'G'              => 34,
        'H'              => 35,
        'J'              => 36,
        'K'              => 37,
        'L'              => 38,
        'SEMICOLON'      => 39,
        'APOSTROPHE'     => 40,
        'GRAVE'          => 41,
        'LEFTSHIFT'      => 42,
        'BACKSLASH'      => 43,
        'Z'              => 44,
        'X'              => 45,
        'C'              => 46,
        'V'              => 47,
        'B'              => 48,
        'N'              => 49,
        'M'              => 50,
        'COMMA'          => 51,
        'DOT'            => 52,
        'SLASH'          => 53,
        'RIGHTSHIFT'     => 54,
        'KPASTERISK'     => 55,
        'LEFTALT'        => 56,
        'SPACE'          => 57,
        'CAPSLOCK'       => 58,
        'F1'             => 59,
        'F2'             => 60,
        'F3'             => 61,
        'F4'             => 62,
        'F5'             => 63,
        'F6'             => 64,
        'F7'             => 65,
        'F8'             => 66,
        'F9'             => 67,
        'F10'            => 68,
        'NUMLOCK'        => 69,
        'SCROLLLOCK'     => 70,
        'KP7'            => 71,
        'KP8'            => 72,
        'KP9'            => 73,
        'KPMINUS'        => 74,
        'KP4'            => 75,
        'KP5'            => 76,
        'KP6'            => 77,
        'KPPLUS'         => 78,
        'KP1'            => 79,
        'KP2'            => 80,
        'KP3'            => 81,
        'KP0'            => 82,
        'KPDOT'          => 83,
        '103RD'          => 84,
        'F13'            => 85,
        '102ND'          => 86,
        'F11'            => 87,
        'F12'            => 88,
        'F14'            => 89,
        'F15'            => 90,
        'F16'            => 91,
        'F17'            => 92,
        'F18'            => 93,
        'F19'            => 94,
        'F20'            => 95,
        'KPENTER'        => 96,
        'RIGHTCTRL'      => 97,
        'KPSLASH'        => 98,
        'SYSRQ'          => 99,
        'RIGHTALT'       => 100,
        'LINEFEED'       => 101,
        'HOME'           => 102,
        'UP'             => 103,
        'PAGEUP'         => 104,
        'LEFT'           => 105,
        'RIGHT'          => 106,
        'END'            => 107,
        'DOWN'           => 108,
        'PAGEDOWN'       => 109,
        'INSERT'         => 110,
        'DELETE'         => 111,
        'MACRO'          => 112,
        'MUTE'           => 113,
        'VOLUMEDOWN'     => 114,
        'VOLDOWN'        => 114,
        'VOLUMEUP'       => 115,
        'VOLUP'          => 115,
        'POWER'          => 116,
        'KPEQUAL'        => 117,
        'KPPLUSMINUS'    => 118,
        'PAUSE'          => 119,
        'F21'            => 120,
        'F22'            => 121,
        'F23'            => 122,
        'F24'            => 123,
        'KPCOMMA'        => 124,
        'LEFTMETA'       => 125,
        'RIGHTMETA'      => 126,
        'COMPOSE'        => 127,
        'STOP'           => 128,
        'AGAIN'          => 129,
        'PROPS'          => 130,
        'UNDO'           => 131,
        'FRONT'          => 132,
        'COPY'           => 133,
        'OPEN'           => 134,
        'PASTE'          => 135,
        'FIND'           => 136,
        'CUT'            => 137,
        'HELP'           => 138,
        'MENU'           => 139,
        'CALC'           => 140,
        'SETUP'          => 141,
        'SLEEP'          => 142,
        'WAKEUP'         => 143,
        'FILE'           => 144,
        'SENDFILE'       => 145,
        'DELETEFILE'     => 146,
        'XFER'           => 147,
        'PROG1'          => 148,
        'PROG2'          => 149,
        'WWW'            => 150,
        'MSDOS'          => 151,
        'COFFEE'         => 152,
        'DIRECTION'      => 153,
        'CYCLEWINDOWS'   => 154,
        'MAIL'           => 155,
        'BOOKMARKS'      => 156,
        'COMPUTER'       => 157,
        'BACK'           => 158,
        'FORWARD'        => 159,
        'CLOSECD'        => 160,
        'EJECTCD'        => 161,
        'EJECTCLOSECD'   => 162,
        'NEXTSONG'       => 163,
        'PLAYPAUSE'      => 164,
        'PREVIOUSSONG'   => 165,
        'STOPCD'         => 166,
        'RECORD'         => 167,
        'REWIND'         => 168,
        'PHONE'          => 169,
        'ISO'            => 170,
        'CONFIG'         => 171,
        'HOMEPAGE'       => 172,
        'REFRESH'        => 173,
        'EXIT'           => 174,
        'MOVE'           => 175,
        'EDIT'           => 176,
        'SCROLLUP'       => 177,
        'SCROLLDOWN'     => 178,
        'KPLEFTPAREN'    => 179,
        'KPRIGHTPAREN'   => 180,
        'INTL1'          => 181,
        'INTL2'          => 182,
        'INTL3'          => 183,
        'INTL4'          => 184,
        'INTL5'          => 185,
        'INTL6'          => 186,
        'INTL7'          => 187,
        'INTL8'          => 188,
        'INTL9'          => 189,
        'LANG1'          => 190,
        'LANG2'          => 191,
        'LANG3'          => 192,
        'LANG4'          => 193,
        'LANG5'          => 194,
        'LANG6'          => 195,
        'LANG7'          => 196,
        'LANG8'          => 197,
        'LANG9'          => 198,
        'PLAYCD'         => 200,
        'PAUSECD'        => 201,
        'PROG3'          => 202,
        'PROG4'          => 203,
        'SUSPEND'        => 205,
        'CLOSE'          => 206,
        'PLAY'           => 207,
        'FASTFORWARD'    => 208,
        'BASSBOOST'      => 209,
        'PRINT'          => 210,
        'HP'             => 211,
        'CAMERA'         => 212,
        'SOUND'          => 213,
        'QUESTION'       => 214,
        'EMAIL'          => 215,
        'CHAT'           => 216,
        'SEARCH'         => 217,
        'CONNECT'        => 218,
        'FINANCE'        => 219,
        'SPORT'          => 220,
        'SHOP'           => 221,
        'ALTERASE'       => 222,
        'CANCEL'         => 223,
        'BRIGHTNESSDOWN' => 224,
        'BRIGHTNESSUP'   => 225,
        'MEDIA'          => 226,
        'UNKNOWN'        => 240,
        'BTN_0'          => 256,
        'BTN_1'          => 257,
        'OK'             => 352,
        'SELECT'         => 353,
        'GOTO'           => 354,
        'CLEAR'          => 355,
        'POWER2'         => 356,
        'OPTION'         => 357,
        'INFO'           => 358,
        'TIME'           => 359,
        'VENDOR'         => 360,
        'ARCHIVE'        => 361,
        'PROGRAM'        => 362,
        'CHANNEL'        => 363,
        'FAVORITES'      => 364,
        'EPG'            => 365,
        'PVR'            => 366,
        'MHP'            => 367,
        'LANGUAGE'       => 368,
        'TITLE'          => 369,
        'SUBTITLE'       => 370,
        'ANGLE'          => 371,
        'ZOOM'           => 372,
        'MODE'           => 373,
        'KEYBOARD'       => 374,
        'SCREEN'         => 375,
        'PC'             => 376,
        'TV'             => 377,
        'TV2'            => 378,
        'VCR'            => 379,
        'VCR2'           => 380,
        'SAT'            => 381,
        'SAT2'           => 382,
        'CD'             => 383,
        'TAPE'           => 384,
        'RADIO'          => 385,
        'TUNER'          => 386,
        'PLAYER'         => 387,
        'TEXT'           => 388,
        'DVD'            => 389,
        'AUX'            => 390,
        'MP3'            => 391,
        'AUDIO'          => 392,
        'VIDEO'          => 393,
        'DIRECTORY'      => 394,
        'LIST'           => 395,
        'MEMO'           => 396,
        'CALENDAR'       => 397,
        'RED'            => 398,
        'GREEN'          => 399,
        'YELLOW'         => 400,
        'BLUE'           => 401,
        'CHANNELUP'      => 402,
        'CHANUP'         => 402,
        'CHANNELDOWN'    => 403,
        'CHANDOWN'       => 403,
        'FIRST'          => 404,
        'LAST'           => 405,
        'AB'             => 406,
        'NEXT'           => 407,
        'RESTART'        => 408,
        'SLOW'           => 409,
        'SHUFFLE'        => 410,
        'BREAK'          => 411,
        'PREVIOUS'       => 412,
        'DIGITS'         => 413,
        'TEEN'           => 414,
        'TWEN'           => 415,
        'DEL_EOL'        => 448,
        'DEL_EOS'        => 449,
        'INS_LINE'       => 450,
        'DEL_LINE'       => 451,
        'ASCII'          => 510,
        'MAX'            => 511
    };

    if ( defined( $commands->{$command} ) ) {
        return $commands->{$command};
    }
    elsif ( $command eq "GetRemotecontrolCommands" ) {
        return $commands;
    }
    else {
        return "";
    }
}

1;

=pod
=item device
=begin html

    <p>
      <a name="ENIGMA2" id="ENIGMA2"></a>
    </p>
    <h3>
      ENIGMA2
    </h3>
    <ul>
      <a name="ENIGMA2define" id="ENIGMA2define"></a> <b>Define</b>
      <ul>
        <code>define &lt;name&gt; ENIGMA2 &lt;ip-address-or-hostname&gt; [&lt;port&gt;] [&lt;poll-interval&gt;] [&lt;http-user&gt;] [&lt;http-password&gt;]</code><br>
        <br>
        This module controls ENIGMA2 based devices like Dreambox or VUplus via network connection.<br>
        <br>
        Defining an ENIGMA2 device will schedule an internal task (interval can be set with optional parameter &lt;poll-interval&gt; in seconds, if not set, the value is 45 seconds), which periodically reads the status of the device and triggers notify/filelog commands.<br>
        <br>
        Example:<br>
        <ul>
          <code>define SATReceiver ENIGMA2 192.168.0.10<br>
          <br>
          # With custom port<br>
          define SATReceiver ENIGMA2 192.168.0.10 8080<br>
          <br>
          # With custom interval of 20 seconds<br>
          define SATReceiver ENIGMA2 192.168.0.10 80 20<br>
          <br>
          # With HTTP user credentials<br>
          define SATReceiver ENIGMA2 192.168.0.10 80 20 root secret</code>
        </ul>
      </ul><br>
      <br>
      <a name="ENIGMA2set" id="ENIGMA2set"></a> <b>Set</b>
      <ul>
        <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Currently, the following commands are defined.<br>
        <ul>
          <li>
            <b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device and send a WoL magic package if needed
          </li>
          <li>
            <b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in standby mode
          </li>
          <li>
            <b>toggle</b> &nbsp;&nbsp;-&nbsp;&nbsp; switch between on and off
          </li>
          <li>
            <b>shutdown</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in deepstandby mode
          </li>
          <li>
            <b>reboot</b> &nbsp;&nbsp;-&nbsp;&nbsp;reboots the device
          </li>
          <li>
            <b>restartGui</b> &nbsp;&nbsp;-&nbsp;&nbsp;restarts the GUI / ENIGMA2 process
          </li>
          <li>
            <b>channel</b> channel,0...999,sRef &nbsp;&nbsp;-&nbsp;&nbsp; zap to specific channel or service reference
          </li>
          <li>
            <b>channelUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; zap to next channel
          </li>
          <li>
            <b>channelDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; zap to previous channel
          </li>
          <li>
            <b>volume</b> 0...100 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage
          </li>
          <li>
            <b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level
          </li>
          <li>
            <b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level
          </li>
          <li>
            <b>mute</b> on,off,toggle &nbsp;&nbsp;-&nbsp;&nbsp; controls volume mute
          </li>
          <li>
            <b>play</b> &nbsp;&nbsp;-&nbsp;&nbsp; starts/resumes playback
          </li>
          <li>
            <b>pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; pauses current playback or enables timeshift
          </li>
          <li>
            <b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; stops current playback
          </li>
          <li>
            <b>record</b> &nbsp;&nbsp;-&nbsp;&nbsp; starts recording of current channel
          </li>
          <li>
            <b>input</b> tv,radio &nbsp;&nbsp;-&nbsp;&nbsp; switches between tv and radio mode
          </li>
          <li>
            <b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device
          </li>
          <li>
            <b>remoteControl</b> UP,DOWN,... &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control commands; see remoteControl help for full command list<br />
            Note: You may add the word "long" after the command to simulate a long key press.
          </li>
          <li>
            <b>showText</b> text &nbsp;&nbsp;-&nbsp;&nbsp; sends info message to screen to be displayed for 8 seconds
          </li>
          <li>
            <b>msg</b> yesno,info... &nbsp;&nbsp;-&nbsp;&nbsp; allows more complex messages as showText, see commands as listed below
          </li>
        </ul>
        <ul>
            <u>Note:</u> If you would like to restrict access to admin set-commands (-> statusRequest, reboot, restartGui, shutdown) you may set your FHEMWEB instance's attribute allowedCommands like 'set,set-user'.
            The string 'set-user' will ensure only non-admin set-commands can be executed when accessing FHEM using this FHEMWEB instance.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Messaging</u><br>
        <br>
        <ul>
          showText has predefined settings. If you would like to send more individual messages to your TV screen, the function msg can be used. For this application the following commands are available:<br>
          <br>
          <u>Type Selection:</u><br>
          <ul>
            <code>msg yesno<br>
            msg info<br>
            msg message<br>
            msg attention<br></code>
          </ul><br>
          <br>
          The following parameter are essentially needed after type specification:
          <ul>
            <code>msg &lt;TYPE&gt; &lt;TIMEOUT&gt; &lt;YOUR MESSAGETEXT&gt;<br></code>
          </ul>
        </ul>
      </ul><br>
      <br>
      <a name="ENIGMA2get" id="ENIGMA2get"></a> <b>Get</b>
      <ul>
        <code>get &lt;name&gt; &lt;what&gt;</code><br>
        <br>
        Currently, the following commands are defined:<br>
        <br>
        <ul>
          <code>channel<br>
          currentMedia<br>
          currentTitle<br>
          mute<br>
          nextTitle<br>
          power<br>
          providername<br>
          servicevideosize<br>
          input<br>
          streamUrl<br>
          volume<br></code>
        </ul>
      </ul><br>
      <br>
      <a name="ENIGMA2attr" id="ENIGMA2attr"></a> <b>Attributes</b><br>
      <ul>
        <ul>
          <li>
            <b>bouquet-tv</b> - service reference address where the favorite television bouquet can be found (initially set automatically during define)
          </li>
          <li>
            <b>bouquet-radio</b> - service reference address where the favorite radio bouquet can be found (initially set automatically during define)
          </li>
          <li>
            <b>disable</b> - Disable polling (true/false)
          </li>
          <li>
            <b>http-method</b> - HTTP access method to be used; e.g. a FritzBox might need to use POST instead of GET (GET/POST)
          </li>
          <li>
            <b>http-noshutdown</b> - Set FHEM-internal HttpUtils connection close behaviour (defaults=1)
          </li>
          <li>
            <b>https</b> - Access box via secure HTTP (true/false)
          </li>
          <li>
            <b>lightMode</b> - reduces regular queries (resulting in less functionality), e.g. for low performance devices. (true/false)
          </li>
          <li>
            <b>macaddr</b> - manually set specific MAC address for device; overwrites value from reading "lanmac". (true/false)
          </li>
          <li>
            <b>remotecontrol</b> - Explicitly set specific remote control unit format. This will only be considered for set-command <strong>remoteControl</strong> as of now.
          </li>
          <li>
            <b>timeout</b> - Set different polling timeout in seconds (default=6)
          </li>
          <li>
            <b>wakeupCmd</b> - Set a command to be executed when turning on an absent device. Can be an FHEM command or Perl command in {}. Available variables: ENIGMA2 device name -> $DEVICE, ENIGMA2 device MAC address -> $MACADDR  (default=Wake-on-LAN)
          </li>
        </ul>
      </ul><br>
      <br>
      <br>
      <b>Generated Readings/Events:</b><br>
      <ul>
        <ul>
          <li>
            <b>acg</b> - Shows Automatic Gain Control value in percent; reflects overall signal quality strength
          </li>
          <li>
            <b>apid</b> - Shows the audio process ID for current channel
          </li>
          <li>
            <b>ber</b> - Shows Bit Error Rate for current channel
          </li>
          <li>
            <b>channel</b> - Shows the service name of current channel or media file name; part of FHEM-4-AV-Devices compatibility
          </li>
          <li>
            <b>currentMedia</b> - The service reference ID of current channel; part of FHEM-4-AV-Devices compatibility
          </li>
          <li>
            <b>currentTitle</b> - Shows the title of the running event; part of FHEM-4-AV-Devices compatibility
          </li>
          <li>
            <b>enigmaversion</b> - Shows the installed version of ENIGMA2
          </li>
          <li>
            <b>eventcurrenttime</b> - Shows the current time of running event as UNIX timestamp
          </li>
          <li>
            <b>eventcurrenttime_hr</b> - Shows the current time of running event in human-readable format
          </li>
          <li>
            <b>eventcurrenttime_next</b> - Shows the current time of next event as UNIX timestamp
          </li>
          <li>
            <b>eventcurrenttime_next_hr</b> - Shows the current time of next event in human-readable format
          </li>
          <li>
            <b>eventdescription</b> - Shows the description of running event
          </li>
          <li>
            <b>eventdescription_next</b> - Shows the description of next event
          </li>
          <li>
            <b>evenduration</b> - Shows the total duration time of running event in seconds
          </li>
          <li>
            <b>evenduration_hr</b> - Shows the total duration time of running event in human-readable format
          </li>
          <li>
            <b>evenduration_next</b> - Shows the total duration time of next event in seconds
          </li>
          <li>
            <b>evenduration_next_hr</b> - Shows the total duration time of next event in human-readable format
          </li>
          <li>
            <b>eventname</b> - Shows the name of running event
          </li>
          <li>
            <b>eventname_next</b> - Shows the name of next event
          </li>
          <li>
            <b>eventremaining</b> - Shows the remaining duration time of running event in seconds
          </li>
          <li>
            <b>eventremaining_hr</b> - Shows the remaining duration time of running event in human-readable format
          </li>
          <li>
            <b>eventremaining_next</b> - Shows the remaining duration time of next event in seconds
          </li>
          <li>
            <b>eventremaining_next_hr</b> - Shows the remaining duration time of next event in human-readable format
          </li>
          <li>
            <b>eventstart</b> - Shows the starting time of running event as UNIX timestamp
          </li>
          <li>
            <b>eventstart_hr</b> - Shows the starting time of running event in human readable format
          </li>
          <li>
            <b>eventstart_next</b> - Shows the starting time of next event as UNIX timestamp
          </li>
          <li>
            <b>eventstart_next_hr</b> - Shows the starting time of next event in human readable format
          </li>
          <li>
            <b>eventtitle</b> - Shows the title of the running event
          </li>
          <li>
            <b>eventtitle_next</b> - Shows the title of the next event
          </li>
          <li>
            <b>fpversion</b> - Shows the firmware version for the front processor
          </li>
          <li>
            <b>hddX_capacity</b> - Shows the total capacity of the installed hard drive in GB
          </li>
          <li>
            <b>hddX_free</b> - Shows the free capacity of the installed hard drive in GB
          </li>
          <li>
            <b>hddX_model</b> - Shows hardware details for the installed hard drive
          </li>
          <li>
            <b>imageversion</b> - Shows the version for the installed software image
          </li>
          <li>
            <b>input</b> - Shows currently used input; part of FHEM-4-AV-Devices compatibility
          </li>
          <li>
            <b>iswidescreen</b> - Indicates widescreen format - 0=off 1=on
          </li>
          <li>
            <b>lanmac</b> - Shows the device MAC address
          </li>
          <li>
            <b>model</b> - Shows details about the device hardware
          </li>
          <li>
            <b>mute</b> - Reports the mute status of the device (can be "on" or "off")
          </li>
          <li>
            <b>nextTitle</b> - Shows the title of the next event; part of FHEM-4-AV-Devices compatibility
          </li>
          <li>
            <b>onid</b> - The ON ID
          </li>
          <li>
            <b>pcrpid</b> - The PCR process ID
          </li>
          <li>
            <b>pmtpid</b> - The PMT process ID
          </li>
          <li>
            <b>power</b> - Reports the power status of the device (can be "on" or "off")
          </li>
          <li>
            <b>presence</b> - Reports the presence status of the receiver (can be "absent" or "present"). In case of an absent device, control is basically limited to turn it on again. This will only work if the device supports Wake-On-LAN packages, otherwise command "on" will have no effect.
          </li>
          <li>
            <b>providername</b> - Service provider of current channel
          </li>
          <li>
            <b>recordings</b> - Number of active recordings
          </li>
          <li>
            <b>recordingsX_name</b> - name of active recording no. X
          </li>
          <li>
            <b>recordingsX_servicename</b> - servicename of active recording no. X
          </li>
          <li>
            <b>recordings_next</b> - Shows the time of next recording as UNIX timestamp
          </li>
          <li>
            <b>recordings_next_hr</b> - Shows the time of next recording as human-readable format
          </li>
          <li>
            <b>recordings_next_counter</b> - Shows the time until next recording starts in seconds
          </li>
          <li>
            <b>recordings_next_counter_hr</b> - Shows the time until next recording starts human-readable format
          </li>
          <li>
            <b>recordings_next_name</b> - name of next recording
          </li>
          <li>
            <b>recordings_next_servicename</b> - servicename of next recording
          </li>
          <li>
            <b>recordings_error</b> - counter for failed recordings in timerlist
          </li>
          <li>
            <b>recordings_finished</b> - counter for finished recordings in timerlist
          </li>
          <li>
            <b>servicename</b> - Name for current channel
          </li>
          <li>
            <b>servicereference</b> - The service reference ID of current channel
          </li>
          <li>
            <b>servicevideosize</b> - Video resolution for current channel
          </li>
          <li>
            <b>sid</b> - The S-ID
          </li>
          <li>
            <b>snr</b> - Shows Signal to Noise for current channel in percent
          </li>
          <li>
            <b>snrdb</b> - Shows Signal to Noise in dB
          </li>
          <li>
            <b>state</b> - Reports current power state and an absence of the device (can be "on", "off" or "absent")
          </li>
          <li>
            <b>tsid</b> - The TS ID
          </li>
          <li>
            <b>tuner_X</b> - Details about the used tuner hardware
          </li>
          <li>
            <b>txtpid</b> - The TXT process ID
          </li>
          <li>
            <b>videoheight</b> - Height of the video resolution for current channel
          </li>
          <li>
            <b>videowidth</b> - Width of the video resolution for current channel
          </li>
          <li>
            <b>volume</b> - Reports current volume level of the receiver in percentage values (between 0 and 100 %)
          </li>
          <li>
            <b>vpid</b> - The Video process ID
          </li>
          <li>
            <b>webifversion</b> - Type and version of the used web interface
          </li>
        </ul>
      </ul>
    </ul>

=end html

=begin html_DE

    <p>
      <a name="ENIGMA2" id="ENIGMA2"></a>
    </p>
    <h3>
      ENIGMA2
    </h3>
    <ul>
      Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden. Die englische Version ist hier zu finden:
    </ul>
    <ul>
      <a href='http://fhem.de/commandref.html#ENIGMA2'>ENIGMA2</a>
    </ul>

=end html_DE

=cut
