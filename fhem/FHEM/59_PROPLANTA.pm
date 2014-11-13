####################################################################################################
# $Id$
#
#  59_PROPLANTA.pm
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
#  
#  Weather forecast values for 12 days are captured from www.proplanta.de
#  inspired by 23_KOSTALPIKO.pm
#
#  Copyright notice
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
####################################################################################################

###############################################
# parser for the weather data
package MyProplantaParser;
use base qw(HTML::Parser);
our @texte = ();
my $lookupTag = "span|b";
my $curTag    = "";
my $curReadingName = "";
my $curRowID = "";
my $curCol = 0;
our $startDay = 0;
my $curTextPos = 0;
my $curReadingType = 0;

  # 1 = span|b Text, 2 = readingName, 3 = Tag-Type
  # Tag-Types: 
  #   1 = Number Col 3
  #   2 = Number Col 2-5 
  #   3 = Number Col 2|4|6|8
  #   4 = Intensity-Text Col 2-5
  #   5 = Time Col 2-5
  #   6 = Time Col 3
  #   7 = Image Col 2-5
  #   8 = MinMaxNummer Col 3
  my @knownNoneIDs = ( ["Temperatur", "temperature", 1] 
      ,["relative Feuchte", "humidity", 1]
      ,["Sichtweite", "visibility", 1]
      ,["Windgeschwindigkeit", "wind", 1]
      ,["Luftdruck", "pressure", 1]
      ,["Taupunkt", "dewPoint", 1]
      ,["Uhrzeit", "obs_time", 6]
      ,["H�he der", "cloudBase", 8]
  );

  # 1 = Tag-ID, 2 = readingName, 3 = Tag-Type (see above)
  my @knownIDs = (  
      ["TMAX", "tempMax", 2]
      ,["TMIN", "tempMin", 2]
      ,["NW", "chOfRainDay", 2]
      ,["NW_Nacht", "chOfRainNight", 2]
      ,["BF", "frost", 4]
      ,["VERDUNST", "evapor", 4]
      ,["TAUBILDUNG", "dew", 4]
      ,["SD", "sun", 2]
      ,["UV", "uv", 2]
      ,["GS", "rad", 3]
      ,["WETTER_ID", "weather", 7]
      ,["WETTER_ID_MORGENS", "weatherMorning", 7]
      ,["WETTER_ID_TAGSUEBER", "weatherDay", 7]
      ,["WETTER_ID_ABENDS", "weatherEvening", 7]
      ,["WETTER_ID_NACHT", "weatherNight", 7]
      ,["T_0", "temp00", 2]
      ,["T_3", "temp03", 2]
      ,["T_6", "temp06", 2]
      ,["T_9", "temp09", 2]
      ,["T_12", "temp12", 2]
      ,["T_15", "temp15", 2]
      ,["T_18", "temp18", 2]
      ,["T_21", "temp21", 2]
      ,["NW_0", "chOfRain00", 2]
      ,["NW_3", "chOfRain03", 2]
      ,["NW_6", "chOfRain06", 2]
      ,["NW_9", "chOfRain09", 2]
      ,["NW_12", "chOfRain12", 2]
      ,["NW_15", "chOfRain15", 2]
      ,["NW_18", "chOfRain18", 2]
      ,["NW_21", "chOfRain21", 2]
      ,["NS_0", "rain00", 2]
      ,["NS_3", "rain03", 2]
      ,["NS_6", "rain06", 2]
      ,["NS_9", "rain09", 2]
      ,["NS_12", "rain12", 2]
      ,["NS_15", "rain15", 2]
      ,["NS_18", "rain18", 2]
      ,["NS_21", "rain21", 2]
      ,["BD_0", "cloud00", 2]
      ,["BD_3", "cloud03", 2]
      ,["BD_6", "cloud06", 2]
      ,["BD_9", "cloud09", 2]
      ,["BD_12", "cloud12", 2]
      ,["BD_15", "cloud15", 2]
      ,["BD_18", "cloud18", 2]
      ,["BD_21", "cloud21", 2]
      ,["MA", "moonRise", 5]
      ,["MU", "moonSet", 5]
  );

   my %intensity = ( "keine" => 0
     ,"nein" => 0
     ,"gering" => 1
     ,"leicht" => 1
     ,"ja" => 1
     ,"m&auml;&szlig;ig" => 2
     ,"stark" => 3
  );
  

# here HTML::text/start/end are overridden
sub text
{
   my ( $self, $text ) = @_;
   my $found = 0;
   my $readingName;
   if ( $curTag =~ $lookupTag )
   {
      $curTextPos++;

      $text =~ s/^\s+//;    # trim string
      $text =~ s/\s+$//;
      $text =~ s/&#48;/0/g;  # replace 0
      
   # Tag-Type 0 = Check for readings without tag-ID (current readings)
      if ($curReadingType == 0)
      {
         if ($startDay == 0 && $curCol == 1 && $curTextPos == 1)
         {
            foreach my $r (@knownNoneIDs) 
            { 
               if ( $$r[0] eq $text ) 
               {
                  $curReadingName = $$r[1];
                  $curReadingType = $$r[2];
                  last;
               }
            }
         }
      }
   # Tag-Type 1 = Number Col 3
      elsif ($curReadingType == 1) 
      {
         if ( $curCol == 3 )
         {
            $readingName = $curReadingName;
            if ( $text =~ m/([-,\+]?\d+[,\.]?\d*)/ )
            {
               $text = $1;
               $text =~ tr/,/./;    # komma durch punkt ersetzen
            }
            push( @texte, $readingName."|".$text ); 
            $curReadingType = 0;
         }
      }
   # Tag-Type 2 = Number Col 2-5
      elsif ($curReadingType == 2) 
      {
         if ( 1 < $curCol && $curCol <= 5 )
         {
            $readingName = "fc".($startDay+$curCol-2)."_".$curReadingName;
            if ( $text =~ m/([-+]?\d+[,.]?\d*)/ )
            {
               $text = $1;
               $text =~ tr/,/./;    # komma durch punkt ersetzen
            }
            push( @texte, $readingName."|".$text ); 
         }
      }
   # Tag-Type 3 = Number Col 2|4|6|8
      elsif ($curReadingType == 3) 
      {
         if ( 2 <= $curCol && $curCol <= 5 )
         {
            if ( $curTextPos % 2 == 1 ) 
            { 
               $readingName = "fc".($startDay+$curCol-2)."_".$curReadingName;
               $text =~ tr/,/./;    # komma durch punkt ersetzen
               push( @texte, $readingName."|".$text ); 
            }
         }
      }
   # Tag-Type 4 = Intensity-Text Col 2-5
      elsif ($curReadingType == 4) 
      {
         if ( 2 <= $curCol && $curCol <= 5 )
         {
            $readingName = "fc".($startDay+$curCol-2)."_".$curReadingName;
            $text = $intensity{$text} if defined $intensity{$text};
            push( @texte, $readingName . "|" . $text ); 
         }
      }
   # Tag-Type 5 = Time Col 2-5
      elsif ($curReadingType == 5) 
      {
         if ( 2 <= $curCol && $curCol <= 5 )
         {
            $readingName = "fc".($startDay+$curCol-2)."_".$curReadingName;
            if ( $text =~ m/([012-]?[-0-9][.:][-0-5][-0-9])/ )
            {
               $text = $1;
               $text =~ tr/./:/;    # Punkt durch Doppelpunkt ersetzen
            }
            push( @texte, $readingName."|".$text ); 
         }
      }
   # Tag-Type 6 = Time Col 3
      elsif ($curReadingType == 6) 
      {
         if ( $curCol == 3 )
         {
            $readingName = $curReadingName;
            if ( $text =~ m/([012-]?[-0-9][.:][-0-5][-0-9])/ )
            {
               $text = $1;
               $text =~ tr/./:/;    # Punkt durch Doppelpunkt ersetzen
            } 
            push( @texte, $readingName."|".$text ); 
         }
      }
   # Tag-Type 8 = MinMaxNumber Col 3
      elsif ($curReadingType == 8) 
      {
         if ( $curCol == 3 )
         {
            $readingName = $curReadingName;
            if ( $text =~ m/(\d+)\s*-\s*(\d+)/ )
            {
               push( @texte, $readingName."Min|".$1 ); 
               push( @texte, $readingName."Max|".$2 ); 
            }
            else
            {
               push( @texte, $readingName."Min|-" ); 
               push( @texte, $readingName."Max|-" ); 
            }
         }
      }
   }
}

sub start
{
   my ( $self, $tagname, $attr, $attrseq, $origtext ) = @_;
   $curTag = $tagname;
   if ( $tagname eq "tr" )
   {
      $curReadingType = 0;
      $curCol = 0;
      $curTextPos = 0;
      if ( defined( $attr->{id} ) ) 
      {
         foreach my $r (@knownIDs) 
         { 
            if ( $$r[0] eq $attr->{id} ) 
            {
               $curReadingName = $$r[1];
               $curReadingType = $$r[2];
               last;
            }
         }
      }
   }
   elsif ($tagname eq "td") 
   {
      $curCol++;
      $curTextPos = 0;
   }
   #wetterstate and icon
   elsif ($tagname eq "img" && $curReadingType == 7) 
   {
      if ( 2 <= $curCol && $curCol <= 5 )
      {
       # Alternativer text
         $readingName = "fc".($startDay+$curCol-2)."_".$curReadingName;
         $text = $attr->{alt};
         $text =~ s/Wetterzustand: //;
         $text =~ s/�/oe/;
         $text =~ s/�/ae/;
         $text =~ s/�/ue/;
         $text =~ s/�/ss/;
         push( @texte, $readingName . "|" . $text ); 
       # Image URL
         push( @texte, $readingName."Icon" . "|" . $attr->{src} ); 
      }
   }
}

sub end
{
   my ( $self, $tagname, $attr, $attrseq, $origtext ) = @_;
   $curTag = "";

   if ( $tagname eq "tr" ) 
   {       
      $curReadingType = 0 
   };
}


##############################################
package main;
use strict;
use feature qw/say switch/;
use warnings;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request;
use HTML::Parser;
require 'Blocking.pm';
require 'HttpUtils.pm';
use vars qw($readingFnAttributes);

use vars qw(%defs);
my $MODUL          = "PROPLANTA";

   my %url_template_1 =( "de" => "http://www.proplanta.de/Wetter/LOKALERORT-Wetter.html"
   , "at" => "http://www.proplanta.de/Agrarwetter-Oesterreich/LOKALERORT/"
   , "ch" => "http://www.proplanta.de/Agrarwetter-Schweiz/LOKALERORT/"
   , "fr" => "http://www.proplanta.de/Agrarwetter-Frankreich/LOKALERORT/"
   , "it" => "http://www.proplanta.de/Agrarwetter-Italien/LOKALERORT/"
   );

   my %url_template_2 = ( "de" => "http://www.proplanta.de/Wetter/profi-wetter.php?SITEID=60&PLZ=LOKALERORT&STADT=LOKALERORT&WETTERaufrufen=stadt&Wtp=&SUCHE=Wetter&wT="
   , "at" => "http://www.proplanta.de/Wetter-Oesterreich/profi-wetter-at.php?SITEID=70&PLZ=LOKALERORT&STADT=LOKALERORT&WETTERaufrufen=stadt&Wtp=&SUCHE=Wetter&wT="
   , "ch" => "http://www.proplanta.de/Wetter-Schweiz/profi-wetter-ch.php?SITEID=80&PLZ=LOKALERORT&STADT=LOKALERORT&WETTERaufrufen=stadt&Wtp=&SUCHE=Wetter&wT="
   , "fr" => "http://www.proplanta.de/Wetter-Frankreich/profi-wetter-fr.php?SITEID=50&PLZ=LOKALERORT&STADT=LOKALERORT&WETTERaufrufen=stadt&Wtp=&SUCHE=Wetter-Frankreich&wT="
   , "it" => "http://www.proplanta.de/Wetter-Italien/profi-wetter-it.php?SITEID=40&PLZ=LOKALERORT&STADT=LOKALERORT&WETTERaufrufen=stadt&Wtp=&SUCHE=Wetter-Italien&wT="
   );


########################################
sub PROPLANTA_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/PROPLANTA_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $instName, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}
###################################
sub PROPLANTA_Initialize($)
{
   my ($hash) = @_;
   $hash->{DefFn}    = "PROPLANTA_Define";
   $hash->{UndefFn}  = "PROPLANTA_Undef";
   $hash->{SetFn}    = "PROPLANTA_Set";
   $hash->{AttrList} = "INTERVAL URL disable:0,1 " . $readingFnAttributes;
}
###################################
sub PROPLANTA_Define($$)
{
   my ( $hash, $def ) = @_;
   my $name = $hash->{NAME};
   my $lang = "";
   my @a    = split( "[ \t][ \t]*", $def );
   
   return "Wrong syntax: use define <name> PROPLANTA [City] [CountryCode]" if int(@a) > 4;

   $lang = "de" if int(@a) == 3;
   $lang = lc( $a[3] ) if int(@a) == 4;

   if ( $lang ne "")
   { # {my $test="http://www.proplanta.de/Wetter/LOKALERORT-Wetter.html";; $test =~ s/LOKALERORT/M�nchen/g;; return $test;;}
      return "Wrong country code '$lang': use " . join(" | ",  keys( %url_template_1 ) ) unless defined( $url_template_1{$lang} );
      my $URL = $url_template_1{$lang};
      $URL =~ s/LOKALERORT/$a[2]/g;
      $hash->{URL} = $URL;
      $URL = $url_template_2{$lang};
      $URL =~ s/LOKALERORT/$a[2]/g;
      $hash->{URL2} = $URL;
   }

   $hash->{STATE}          = "Initializing";
   $hash->{LOCAL}          = 0;
   $hash->{INTERVAL}       = 3600;
   $hash->{fhem}{modulVersion} = '$Date$';
   
   RemoveInternalTimer($hash);
   
   #Get first data after 12 seconds
   InternalTimer( gettimeofday() + 12, "PROPLANTA_Start", $hash, 0 );

   return undef;
}
#####################################
sub PROPLANTA_Undef($$)
{
   my ( $hash, $arg ) = @_;

   RemoveInternalTimer( $hash );
   
   BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
   
   return undef;
}
#####################################
sub PROPLANTA_Set($@)
{
   my ( $hash, @a ) = @_;
   my $name    = $hash->{NAME};
   my $reUINT = '^([\\+]?\\d+)$';
   my $usage   = "Unknown argument $a[1], choose one of update:noArg ";
 
   return $usage if ( @a < 2 );
   
   my $cmd = lc( $a[1] );
   given ($cmd)
   {
      when ("?")
      {
         return $usage;
      }
      when ("update")
      {
         PROPLANTA_Log $hash, 3, "set command: " . $a[1];
         $hash->{LOCAL} = 1;
         PROPLANTA_Start($hash);
         $hash->{LOCAL} = 0;
      }
       default
      {
         return $usage;
      }
   }
   return;
}

#####################################
# acquires the html page
sub PROPLANTA_HtmlAcquire($$)
{
   my ($hash, $URL)  = @_;
   my $name    = $hash->{NAME};
   return unless (defined($hash->{NAME}));
 
   PROPLANTA_Log $hash, 4, "Start capturing of $URL";

   my $err_log  = "";
   my $agent    = LWP::UserAgent->new( env_proxy => 1, keep_alive => 1, protocols_allowed => ['http'], timeout => 10 );
   my $request   = HTTP::Request->new( GET => $URL );
   my $response = $agent->request($request);
   $err_log = "Can't get $URL -- " . $response->status_line
     unless $response->is_success;
     
   if ( $err_log ne "" )
   {
      readingsSingleUpdate($hash, "lastConnection", $response->status_line, 1);
      PROPLANTA_Log $hash, 1, "Error: $err_log";
      return "Error|Error " . $response->status_line;
   }

   PROPLANTA_Log $hash, 4, length($response->content)." characters captured";
   return $response->content;
}


#####################################
sub PROPLANTA_Start($)
{
   my ($hash) = @_;
   my $name   = $hash->{NAME};
   
   return unless (defined($hash->{NAME}));
   
   $hash->{INTERVAL} = AttrVal( $name, "INTERVAL",  $hash->{INTERVAL} );
   
   if(!$hash->{LOCAL} && $hash->{INTERVAL} > 0) {
    # set up timer if automatically call
      RemoveInternalTimer( $hash );
      InternalTimer(gettimeofday() + $hash->{INTERVAL}, "PROPLANTA_Start", $hash, 1 );  
      return undef if( AttrVal($name, "disable", 0 ) == 1 );
   }
   
   if ( AttrVal( $name, 'URL', '') eq '' && not defined( $hash->{URL} ) )
   {
      PROPLANTA_Log $hash, 3, "missing URL";
      return;
   }
  
   $hash->{helper}{RUNNING_PID} =
           BlockingCall( 
           "PROPLANTA_Run",   # callback worker task
           $name,                    # name of the device
           "PROPLANTA_Done",  # callback result method
           120,                       # timeout seconds
           "PROPLANTA_Aborted", #  callback for abortion
           $hash );                 # parameter for abortion
}

#####################################
sub PROPLANTA_Run($)
{
   my ($name) = @_;
   my $ptext=$name;
   my $URL;
   return unless ( defined($name) );
   
   my $hash = $defs{$name};
   return unless (defined($hash->{NAME}));
   
   my $attrURL = AttrVal( $name, 'URL', "" );
   if ($attrURL eq "")
   {
      $URL = $hash->{URL};
   }
   else
   {
      $URL = $attrURL;
   }

   # acquire the html-page
   my $response = PROPLANTA_HtmlAcquire($hash,$URL); 
   
   if ($response =~ /^Error\|/)
   {
      $ptext .= "|".$response;
   }
   else
   {
      PROPLANTA_Log $hash, 4, "Start HTML parsing of captured page";

      my $parser = MyProplantaParser->new;
      $parser->report_tags(qw(tr td span b img));
      @MyProplantaParser::texte = ();
      $MyProplantaParser::startDay = 0;

      # parsing the complete html-page-response, needs some time
      $parser->parse($response);

   # add next periods
      if ($attrURL eq "")
      {
         $URL = $hash->{URL2};
         foreach (4, 7, 11)
         {
            $response = PROPLANTA_HtmlAcquire($hash,$URL . $_); 
            $MyProplantaParser::startDay = $_;
            if ($response !~ /^Error\|/)
            {
               PROPLANTA_Log $hash, 4, "Start HTML parsing of captured page";
               $parser->parse($response);
            }
         }
     }
      
      PROPLANTA_Log $hash, 4, "Found terms: " . @MyProplantaParser::texte;
      
      # pack the results in a single string
      if (@MyProplantaParser::texte > 0) 
      {
         $ptext .= "|". join('|', @MyProplantaParser::texte);
      }
      PROPLANTA_Log $hash, 5, "Parsed string: " . $ptext;
   }
   return $ptext;
}
#####################################
# asyncronous callback by blocking
sub PROPLANTA_Done($)
{
   my ($string) = @_;
   return unless ( defined($string) );
   
   # all term are separated by "|" , the first is the name of the instance
   my ( $name, %values ) = split( "\\|", $string );
   my $hash = $defs{$name};
   return unless ( defined($hash->{NAME}) );
   
   # delete the marker for RUNNING_PID process
   delete( $hash->{helper}{RUNNING_PID} );  

   # Wetterdaten speichern
   readingsBeginUpdate($hash);

   if ( defined $values{Error} )
   {
      readingsBulkUpdate( $hash, "lastConnection", $values{Error} );
   }
   else
   {
      my $x = 0;
      while (my ($rName, $rValue) = each(%values) )
      {
         readingsBulkUpdate( $hash, $rName, $rValue );
         PROPLANTA_Log $hash, 5, "reading:$rName value:$rValue";
      }
      
      if (keys %values > 0) 
      {
        # Achtung! Um Mitternacht fehlen die aktuellen Werte
         readingsBulkUpdate($hash, "state", "Tmin: " . $values{fc0_tempMin} . " Tmax: " . $values{fc0_tempMax} . " T: " . $values{temperature} . " H: " . $values{humidity} . " W: " . $values{wind} . " P: " .  $values{pressure} );
         readingsBulkUpdate( $hash, "lastConnection", keys( %values )." values captured" );
         PROPLANTA_Log $hash, 4, keys( %values )." values captured";
      }
      else
      {
         readingsBulkUpdate( $hash, "lastConnection", "no data found" );
         PROPLANTA_Log $hash, 1, "No data found. Check city name or URL.";
      }
   }
   readingsEndUpdate( $hash, 1 );
}
#####################################
sub PROPLANTA_Aborted($)
{
   my ($hash) = @_;
   delete( $hash->{helper}{RUNNING_PID} );
}

##### noch nicht fertig ###########
sub #####################################
PROPLANTA_Html($)
{
  my ($d) = @_;
  $d = "<none>" if(!$d);
  return "$d is not a PROPLANTA instance<br>"
        if(!$defs{$d} || $defs{$d}{TYPE} ne "PROPLANTA");

  my $uselocal= 0; #AttrVal($d,"localicons",0);
  my $isday;
   if ( exists &isday) 
   {
      $isday = isday();
   }
   else 
   {
      $isday = 1; #($hour>6 && $hour<19);
   }
        
  my $ret = "<table>";
  $ret .= sprintf '<tr><td>%s</td><td><br></td></tr>', $defs{$d}{DEF};

#  $ret .= sprintf('<tr><td>%s</td><td>%s %s<br>temp: %s �C, hum %s<br>wind: %s km/h %s<br>pressure: %s bar visibility: %s km</td></tr>',
#        WWOIconIMGTag(ReadingsVal($d, "icon", ""),$uselocal,$isday),
#        ReadingsVal($d, "localObsDateTime", ""),ReadingsVal($d, "weatherDesc", ""),
#        ReadingsVal($d, "temp_C", ""), ReadingsVal($d, "humidity", ""),
#        ReadingsVal($d, "windspeedKmph", ""), ReadingsVal($d, "winddir16Point", ""),
#        ReadingsVal($d, "pressure", ""),ReadingsVal($d, "visibility", ""));

  # for(my $i=0; $i<=4; $i++) {
    # $ret .= sprintf('<tr><td>%s</td><td>%s: %s<br>min %s �C max %s �C<br>wind: %s km/h %s<br>precip: %s mm</td></tr>',
        # WWOIconIMGTag(ReadingsVal($d, "fc${i}_weatherDayIcon", ""),$uselocal,$isday),
        # ReadingsVal($d, "fc${i}_date", ""),
        # ReadingsVal($d, "fc${i}_weatherDay", ""),
        # ReadingsVal($d, "fc${i}_tempMinC", ""), ReadingsVal($d, "fc${i}_tempMaxC", ""),
  # }
  
  $ret .= "</table>";

  return $ret;
}

##################################### 
1;

=pod
=begin html

<a name="PROPLANTA"></a>
<h3>PROPLANTA</h3>
<div  style="width:800px"> 
<ul>
   The module extracts weather data from <a href="http://www.proplanta.de">www.proplanta.de</a>.
   <br>
   The website provides a forecast for 12 days, for the first 7 days in a 3-hours-interval.
   <br>
   It uses the perl moduls HTTP::Request, LWP::UserAgent and HTML::Parse.
   <br/><br/>
   <a name="PROPLANTAdefine"></a>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;name&gt; PROPLANTA [City] [CountryCode]</code>
      <br>
      Example:
      <br>
      <code>define wetter PROPLANTA Bern ch</code>
      <br>
      <code>define wetter PROPLANTA Wittingen+(Niedersachsen)</code>
      <br>&nbsp;
      <li><code>[City]</code>
         <br>
         Optional. The city must be selectable on <a href="http://www.proplanta.de">www.proplanta.de</a>.
         <br>
         Please pay attention to the <b>Capital</b> letters in the city names.
         Spaces within the name are replaced by a + (plus).
      </li><br>
      <li><code>[CountryCode]</code>
         <br>
         Optional. Possible values: de (default), at, ch, fr, it 
      </li><br>
   </ul>
   <br>
  
   <a name="PROPLANTAset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         The weather data are immediately polled from the website.
      </li><br>
   </ul>  
   <br>
  
   <a name="PROPLANTAattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>Interval &lt;seconds&gt;</code>
         <br>
         Poll interval for weather data in seconds (default 3600 = 1 hour)
      </li><br>
      <li><code>URL &lt;internet address&gt;</code>
         <br>
         URL to extract information from. Overwrites the values in the 'define' term.
      </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br>

   <a name="PROPLANTAreading"></a>
   <b>Forecast readings</b>
   <ul>
      <br>
      <li><b>fc</b><i>0|1|2|3|...|13</i><b>_...</b> - forecast values for <i>today|tommorrow|in 2|3|...|13 days</i></li>
      <li><b>fc</b><i>0</i><b>_...<i>00|03|06|09|12|15|18|21</i></b> - forecast values for <i>today</i> at <i>00|03|06|09|12|15|18|21</i> o'clock</li>
      <li><b>fc</b><i>0</i><b>_chOfRain</b><i>Day|Night</i> - chance of rain <i>today</i> by <i>day|night</i> in %</li>
      <li><b>fc</b><i>0</i><b>_chOfRain</b><i>15</i> - chance of rain <i>today</i> at <i>15:00</i> in %</li>
      <li><b>fc</b><i>0</i><b>_cloud</b><i>15</i> - cloud coverage <i>today</i> at <i>15:00</i> in %</li>
      <li><b>fc</b><i>0</i><b>_dew</b> - dew formation <i>today</i> (0=none, 1=small, 2=medium, 3=strong)</li>
      <li><b>fc</b><i>0</i><b>_evapor</b> - evaporation <i>today</i> (0=none, 1=small, 2=medium, 3=strong)</li>
      <li><b>fc</b><i>0</i><b>_frost</b> - ground frost <i>today</i> (0=no, 1=yes)</li>
      <li><b>fc</b><i>0</i><b>_moon</b><i>Rise|Set</i> - moon <i>rise|set today</i></li>
      <li><b>fc</b><i>0</i><b>_rad</b> - global radiation <i>today</i></li>
      <li><b>fc</b><i>0</i><b>_rain</b><i>15</i> - amount of rainfall <i>today</i> at <i>15:00</i> o'clock in mm</li>
      <li><b>fc</b><i>0</i><b>_sun</b> - relative sun shine duration <i>today</i> in % (between sun rise and set)</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>Min|Max</i> - <i>minimal|maximal</i> temperature <i>today</i> in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>15</i> - temperatur <i>today</i> at <i>15:00</i> o'clock in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_uv</b> - UV-Index <i>today</i></li>
      <li><b>fc</b><i>0</i><b>_weather</b><i>Morning|Day|Evening|Night</i> - weather situation <i>today morning|during day|in the evening|during night</i></li>
      <li><b>fc</b><i>0</i><b>_weather</b><i>Day</i><b>Icon</b> - icon of weather situation <i>today</i> by <i>day</i></li>
      <li>etc.</li>
   </ul>
   <br>
</ul>
</div>

=end html

=begin html_DE

<a name="PROPLANTA"></a>
<h3>PROPLANTA</h3>
<div  style="width:800px"> 
<ul>
   <a name="PROPLANTAdefine"></a>
   Das Modul extrahiert Wetterdaten von der Website <a href="http://www.proplanta.de">www.proplanta.de</a>.
   <br/>
   Es stellt eine Vorhersage f&uuml;r 12 Tage, w&aauml;hrend der ersten 7 Tage im 3-Stunden-Intervall, zur Verf&uuml;gung.
   <br>
   Es nutzt die Perl-Module HTTP::Request, LWP::UserAgent und HTML::Parse.
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; PROPLANTA [Stadt] [L&auml;ndercode]</code>
      <br>
      Beispiel:
      <br>
      <code>define wetter PROPLANTA Bern ch</code>
      <br>
      <code>define wetter PROPLANTA Wittingen+(Niedersachsen)</code>
      <br>&nbsp;
      <li><code>[Stadt]</code>
         <br>
         Optional. Die Stadt muss auf <a href="http://www.proplanta.de">www.proplanta.de</a> ausw&auml;hlbar sein. 
         <br>
         Wichtig!! Auf die <b>gro&szlig;en</b> Anfangsbuchstaben achten.
         Leerzeichen im Stadtnamen werden durch ein + (Plus) ersetzt.
      </li><br>
      <li><code>[L&auml;ndercode]</code>
         <br>
         Optional. M&ouml;gliche Werte: de (Standard), at, ch, fr, it
      </li><br>
   </ul>
   <br>
  
   <a name="PROPLANTAset"></a>
   <b>Set</b>
   <ul>
      <br>
      <li><code>set &lt;name&gt; update</code>
         <br>
         Startet sofort ein neues Auslesen der Wetterdaten.
      </li><br>
   </ul>  
  
   <a name="PROPLANTAattr"></a>
   <b>Attribute</b>
   <ul>
      <br>
      <li><code>INTERVAL &lt;Abfrageinterval&gt;</code>
         <br>
         Abfrageinterval in Sekunden (Standard 3600 = 1 Stunde)
      </li><br>
      <li><code>URL &lt;Internetadresse&gt;</code>
         <br>
         Internetadresse, von der die Daten ausgelesen werden (&uuml;berschreibt die Werte im 'define'-Term
      </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
   <br><br>


   <a name="PROPLANTAreading"></a>
   <b>Vorhersagewerte</b>
   <ul>
      <br>
      <li><b>fc</b><i>0|1|2|3...|13</i><b>_...</b> - Vorhersagewerte f&uumlr <i>heute|morgen|&uuml;bermorgen|in 3|...|13 Tagen</i></li>
      <li><b>fc</b><i>0</i><b>_...<i>00|03|06|09|12|15|18|21</i></b> - Vorhersagewerte f&uumlr <i>heute</i> um <i>00|03|06|09|12|15|18|21</i> Uhr</li>
      <li><b>fc</b><i>0</i><b>_chOfRain</b><i>Day|Night</i> - <i>heutiges</i> Niederschlagsrisiko <i>tags&uuml;ber|nachts</i> in %</li>
      <li><b>fc</b><i>1</i><b>_chOfRain</b><i>15</i> - <i>morgiges</i> Niederschlagsrisiko um <i>15</i>:00 Uhr in %</li>
      <li><b>fc</b><i>2</i><b>_cloud</b><i>15</i> - Wolkenbedeckungsgrad <i>&uuml;bermorgen</i> um <i>15</i>:00 Uhr in %</li>
      <li><b>fc</b><i>0</i><b>_dew</b> - Taubildung <i>heute</i> (0=keine, 1=leicht, 2=m&auml;&szlig;ig, 3=stark)</li>
      <li><b>fc</b><i>0</i><b>_evapor</b> - Verdunstung <i>heute</i> (0=keine, 1=gering, 2=m&auml;&szlig;ig, 3=stark)</li>
      <li><b>fc</b><i>0</i><b>_frost</b> - Bodenfrost <i>heute</i> (0=nein, 1=ja)</li>
      <li><b>fc</b><i>1</i><b>_moon</b><i>Rise|Set</i> - Mond<i>auf|unter</i>gang <i>morgen</i></li>
      <li><b>fc</b><i>0</i><b>_rad</b> - Globalstrahlung <i>heute</i></li>
      <li><b>fc</b><i>0</i><b>_rain</b><i>15</i> - Niederschlagsmenge <i>heute</i> um <i>15</i>:00 Uhr in mm</li>
      <li><b>fc</b><i>0</i><b>_sun</b> - relative Sonnenscheindauer <i>heute</i> in % (zwischen Sonnenauf- und -untergang)</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>Min|Max</i> - <i>Minimal|Maximal</i>temperatur <i>heute</i> in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_temp</b><i>15</i> - Temperatur <i>heute</i> um <i>15</i>:00 Uhr in &deg;C</li>
      <li><b>fc</b><i>0</i><b>_uv</b> - UV-Index <i>heute</i></li>
      <li><b>fc</b><i>0</i><b>_weather</b><i>Morning|Day|Evening|Night</i> - Wetterzustand <i>heute morgen|tags&uuml;ber|abends|nachts</i></li>
      <li><b>fc</b><i>0</i><b>_weather</b><i>Day</i><b>Icon</b> - Icon Wetterzustand <i>heute tags&uuml;ber</i></li>
      <li>etc.</li>
   </ul>
   <br>
   <b>Aktuelle Werte</b>
   <ul>
      <br>
      <li><b>cloudBase</b><i>Min|Max</i> - H&ouml;he der <i>minimalen|maximalen</i> Wolkenuntergrenze in m</li>
      <li><b>dewPoint</b> - Taupunkt in &deg;C</li>
      <li><b>humidity</b> - relative Feuchtigkeit in %</li>
      <li><b>obs_time</b> - Uhrzeit der Wetterbeobachtung</li>
      <li><b>pressure</b> - Luftdruck in hPa</li>
      <li><b>temperature</b> - Temperature in &deg;C</li>
      <li><b>visibility</b> - Sichtweite in km</li>
      <li><b>wind</b> - Windgeschwindigkeit in km/h</li>
   </ul>
   <br><br>
</ul>
</div> 

=end html_DE
=cut