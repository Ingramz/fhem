##############################################
# $Id$
package main;

use strict;
use warnings;
use POSIX;

use Encode qw(encode);

use IO::Uncompress::Gunzip qw(gunzip $GunzipError );


use XML::Simple;

my $modulename='rssFeed';	#Module-Name = TYPE 

my $nb_prefix='n';
my $nb_separator="_";

my $feed_prefix='f'.$nb_separator;
my $debug_prefix='d'.$nb_separator;

my $startup_wait_seconds=10;
my $default_interval=3600;
my $min_interval=300;

my $default_max_lines=10;
my $maximum_max_lines=99;
my $nb_indexlength=length($maximum_max_lines);

my $rdHeadlines='.headlines';

my $defaultReadings="title,description,pubDate";
my $allReadings=$defaultReadings.",link,buildDate,imageTitle,imageURL";

my $defaultDisabledText='this rssFeed ist currently disabled';


sub 
#======================================================================
rssFeed_Log3($$$) 
#======================================================================
#Using my own Log3 method, expecting the same
#parameters as the official method
#rssFeed_Log3 <devicename>,<loglevel>,<logmessage>
#making sure, the device-name is always contained in the log message
{
	my ($name,$lvl,$text)=@_;
	Log3 $name,$lvl,"$name: $text";
	return undef;
}

#======================================================================
sub rssFeed_NotifyFn($$)
#======================================================================
{
	#TODO: Catch global INITIALIZED event!!!
	
	my ($hash,$dev)=@_;
	
	my $name=$hash->{NAME};
	my $src=$dev->{NAME};
	
	if($src eq 'global') {
		foreach my $event (@{$dev->{CHANGED}})
		{
			rssFeed_Log3 $name,5,"global event for $name: $event";
			if($event =~ /ATTR $name disable/) {
				rssFeed_Log3 $name,4,"$name disabled changed";
				if(IsDisabled($name)) {
					rssFeed_update($hash);
					rssFeed_Log3 $hash->{NAME},4,'NotifyFn: Removing timer (disabled)';
					RemoveInternalTimer($hash);    
					readingsSingleUpdate($hash,'state','disabled',1);
				} else {
					my $nexttimer=gettimeofday()+$startup_wait_seconds;

					rssFeed_Log3 $name,4,'NotifyFn: starting timer. First event at '.localtime($nexttimer).' (enable)';
					$hash->{NEXTUPDATE}=localtime($nexttimer);
					InternalTimer($nexttimer, $modulename."_GetUpdate", $hash, 0);
  					readingsSingleUpdate($hash,'state','defined',1);

				}
			} elsif($event eq 'INITIALIZED') {
				if(IsDisabled($name)) {
					rssFeed_update($hash);
					rssFeed_Log3 $hash->{NAME},4,'NotifyFn: Removing timer (disabled)';
					RemoveInternalTimer($hash);    
					readingsSingleUpdate($hash,'state','disabled',1);
				}
				
			}
		}
		
	}
	
	
	rssFeed_Log3 $name,5,"$name hat ein notify von von $src erhalten";
	
	return undef if(IsDisabled($name));
	return undef if($dev->{TYPE} eq 'FRITBOX');
	
	
	foreach my $event (@{$dev->{CHANGED}})
	{
    	rssFeed_Log3 $name,5,"$src EVENT: $event";
	}
	
	return undef;
}

sub 
#======================================================================
rssFeed_GetUpdate($)
#======================================================================
#This ist the Update-Routine called when internal timer has reached
#end. It will call the update routine, updating feed data if device
#is not disabled.
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	rssFeed_Log3 $name,4,$modulename.'_GetUpdate';
	
	rssFeed_update(@_) if(!AttrVal($name,'disable',undef)); 

	#Setting Internal with next timer event time
	my $nexttimer=gettimeofday()+$hash->{INTERVAL};
	$hash->{NEXTUPDATE}=localtime($nexttimer);
		
	#Restarting timer
	rssFeed_Log3 $name,4,"restarting timer: next event ".localtime($nexttimer);
	InternalTimer($nexttimer, $modulename."_GetUpdate", $hash, 1);
	return undef;
}

sub
#======================================================================
rssFeed_Initialize($)
#======================================================================
#Module instance initialization (constructor)
{
  my ($hash) = @_;

  #Telling FHEM what routines to use for module handling
  $hash->{SetFn}     = $modulename."_Set";		#setter
  $hash->{GetFn}	 = $modulename."_Get";		#getter
  $hash->{DefFn}     = $modulename."_Define";	#define
  $hash->{UndefFn}   = $modulename."_Undef";    #undefine
  $hash->{NotifyFn}  = $modulename."_NotifyFn"; #event handling
  
  #Telling FHEM what attributes are available
  $hash->{AttrList}  = "disable:1,0 "
  	. "rfDebug:1,0 "		#enable (0) or disable (1) the device
	. "rfMaxLines "			#maximum number of title-lines to extract from feed
	. "rfDisplayTitle "		#display a title as first line in headlines (is perl special)
	. "rfTickerChars "		#optional characters to display at the beginning and end of each headline
	. "rfEncode "	        #optional encoding to use for setting the readings (e.g. utf8)
	. "rfReadings:multiple-strict,".$allReadings." "   #readings to fill (comma separated list)
	. "rfDisabledText "
	#. "rfLatin1ToUtf8:1,0"  #optional encoding using latin1ToUtf8 for readings (TEST ONLY)
  	. $readingFnAttributes; #default FHEM FnAttributes -> see commandref.
}


sub 
#======================================================================
rssFeedGetTicker($)
#======================================================================
#getting the Headlines from the given device
#rssFeedGetTicker(<devicename>)
#This routine will ber calle by 'get ticker'.
{
	my ($name)=@_;
	#Checking if device exists ...
	if(!$defs{$name}) {
		return "$name ist not defined";
	}
	#... and has correct TYPE
	if(!($defs{$name}{'TYPE'} eq $modulename)){
	  return "$name is no $modulename device";
	}
	
	#returning the Headlines stored in the corresponding reading
	return ReadingsVal($name,$rdHeadlines,"No headlines available!\nUse $name set update to refresh data.");
	
#--> returning undef here leads to a syntax error.
#    I just don't know why yet???
#return undef;|
}


sub
#======================================================================
rssFeed_Set($@)
#======================================================================
#Setter - Handling set commands for device
{
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $cmd=shift @a;
  #Currently only the update command is available to refressh
  #feed date
  if ($cmd eq 'update') {
	rssFeed_update(@_);
  }
  else {
  	return "Unknown argument $cmd, choose one of update:noArg";
  }

  return undef;
}

sub
#======================================================================
rssFeed_Define($$)
#======================================================================
#defining the device using following syntax
#define <name> rssFeed <feedurl> [interval]
#Example URLs:
#  http://www.tagesschau.de/xml/rss2
#  http://www.spiegel.de/schlagzeilen/tops/index.rss
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  #Check if at least 2 arguments are specified (name and url)
  return "Wrong syntax: use define <name> $modulename <feedURL> [interval]" if(int(@a) < 3);

  my $name=shift @a;
  my $type=shift @a;
  my $url=shift@a;
  my $interval=shift @a;

  if (defined($interval)) {
  	#if interval defined, make sure its a valid number
	#and is at least 5 minutes (seconds)
  	$interval=$interval+0;
  	$interval=$min_interval if ($interval<$min_interval);
  	$hash->{INTERVAL}=$interval;
  } else { 
  	#otherwise set default inteval of one hour
  	$hash->{INTERVAL}=$default_interval;
  }
  
  #Storing the given feed-URL in the internals
  $hash->{URL}=$url;
  
  if(IsDisabled($name)) {
  	readingsSingleUpdate($hash,'state',"disabled",0);
	return undef;
  }
  #return undef if(IsDisabled($name));
  
  #and setting a state reading for device
  #-> ToDo: finding a better state value (something meaningful)
  #-> Done: see in rssFeed_update -> set to last update timestamp
  readingsSingleUpdate($hash,'state','defined',1);

  rssFeed_Log3 $hash->{NAME},4,'Define: Removing probably existing timer';
  RemoveInternalTimer($hash);    

  #Starting first timer loop with waiting for 10 second before first
  #update of feed data. Followint timers will then be started with the given
  #interval. This is for waiting a short ammount of time especially when 
  #FHEM is started.
  my $nexttimer=gettimeofday()+$startup_wait_seconds;

  rssFeed_Log3 $name,4,'Define: starting timer. First event at '.localtime($nexttimer);
  $hash->{NEXTUPDATE}=localtime($nexttimer);
  InternalTimer($nexttimer, $modulename."_GetUpdate", $hash, 0);
  
  my $attReadings=AttrVal($hash->{NAME},"rfReadings",undef);
  $attr{$hash->{NAME}}{rfReadings}=$defaultReadings if (!$attReadings);
  return undef;
}

sub 
#======================================================================
rssFeed_Undef($$)    
#======================================================================
#Undefine of device instance (destructor)
#Simply remove running timer(s) of device instance to be undefined.
{                     
	my ( $hash, $arg ) = @_;
	rssFeed_Log3 $hash->{NAME},4,'Undef: Removing timer';
	RemoveInternalTimer($hash);    
	return undef;                  
}    

sub 
#======================================================================
rssFeed_Get($@) 
#======================================================================
# getter - Handling get requests
{

	my ($hash,@a)=@_;
	
	my $name=shift @a;
	my $cmd=shift @a;
	
	#Getting the ticker data (Healines)
	if ($cmd eq 'ticker') {
		return rssFeedGetTicker($name);
	} else {
		return "Unknown argument $cmd, choose one of ticker:noArg";
	}
	return undef;
}


sub 
#======================================================================
rssFeed_update(@) 
#======================================================================
#This subroutine is actually doing the update of the feed data for
#the device. It's called by 'set update' and rssFeed_GetUpdate when 
#timer is up.
{
  
  my ($dhash,@a)=@_;
  
  my $name=$dhash->{NAME};
  
  #Check if something wrong with the device's hash.
  if (!$name) {
  	rssFeed_Log3($modulename.'_update',3,'Unable to extract device name');
  }

  rssFeed_Log3 $name,4,'updating feed data...';
  
  my $rfDebug=AttrVal($name,"rfDebug",undef);

  #Delete all previously stored data from the readings.
  #-> ToDo: maybe I'll extract this to a clear readings [what] command
  fhem("deletereading $name $nb_prefix.*[0-9]{$nb_indexlength}.*",1); 
  fhem("deletereading $name $debug_prefix.*",1);
  fhem("deletereading $name $feed_prefix.*",1);
  fhem("deletereading $name preparedLines",1);
  
  #Checking if ticker characters are defined.
  #They will surround each headline in the ticker data
  my ($tt_start,$tt_end);
  my $ttt=AttrVal($name,'rfTickerChars','');
  if ($ttt) {
  	$tt_start="$ttt ";
	$tt_end=" $ttt";
  } else {
  	$tt_start='';
	$tt_end='';
  }
  
  #get encoding attribute
  my $enc=AttrVal($name,'rfEncode',undef);
  
  #TEST ONLY:
  #my $lutf=AttrVal($name,"latin1ToUtf8",undef);
  
  my $rfReadings=AttrVal($name,'rfReadings',$defaultReadings);
  my @setReadings = split /,/, $rfReadings;
  my %params = map { $_ => 1 } @setReadings;
    
  #setting state to the same value as it is more meaningful than 
  #just 'defined'
  readingsSingleUpdate($dhash,'state',localtime(gettimeofday()),1) if(!IsDisabled($name));

  #if the device is disabled then there will be no further update an only the
  #information, that the ticke is deactivated will be stored to ticker headlines
  # -> ToDo: This point will currently never be automatically reached, as this update-Routine
  #          is not called by the timer event routine (rssFeed_GetUpdate) when the disable
  #          attribute is set. Shoud be called at least once, when attribute dsable is set.
  if(AttrVal($name,'disable',undef)) {
  	my $disabledText=AttrVal($name,"rfDisabledText",$defaultDisabledText);
  	readingsSingleUpdate($dhash,$rdHeadlines,$tt_start.$disabledText.$tt_end,0);
  	return ;
  }

  #Get how many lines should be extracted from feed from attributes.
  #Set default to 10 if not specified
  my ($lines) = shift;
  $lines = AttrVal($name,'rfMaxLines','10')+0;
  $lines =$default_max_lines if ($lines<=0);
  $lines =$maximum_max_lines if ($lines>$maximum_max_lines);

  rssFeed_Log3 $name,4,"rfMaxLines: $lines";
  
  my ($i,$nachrichten,$response,@ticker,$ua,$url,$xml);

  $i = 0;
  
  #Getting URL from internals
  $url=InternalVal($name,'URL',''); 
  if (!$url) {
  	#If there's no URL in internals, something is very wrong (see define)
  	rssFeed_Log3 $name,3,'url not defined';
	return;
  }
  rssFeed_Log3 $name,4,$url;
  
  #Getting feed data (hopefully it's xml data) from url
  my $urlbase=eval('URI->new("'.$url.'")->host');  
  $response = GetFileFromURLQuiet($url,3,undef,1);
  
  if(!$response) {
  	#Problem: no response was returned!
  	rssFeed_Log3 $name,3,'no response getting rss data from url';
	return;
  }
  
  #If verbose is set to 5 then log complete response
  rssFeed_Log3 $name,5,$response;
    
  #Trying to unzip received response
  my $runzipped=undef;
  gunzip \$response => \$runzipped;
  
  rssFeed_Log3 $name,5,"unzipError: $GunzipError";

  #If the response was not zipped, the unzip-result is the original response data
  my $zipped=0;
  $zipped=1 if($runzipped ne $response);
  readingsSingleUpdate($dhash,"gzippedFeed",$zipped,0);

  #If rfDebug attribute is set then store complete response in reading
  if ($rfDebug) {
    readingsSingleUpdate($dhash,$debug_prefix."LastResponse",$response,0);  
	readingsSingleUpdate($dhash,$debug_prefix."UnzippedResponse",$runzipped,0) if ($zipped);
  }

  #using unzipped responsedata if it was originally zipped
  $response=$runzipped if($zipped);
  
  #Convert xml data from reponse to an array (hash?)
  $xml         = new XML::Simple;
  
  rssFeed_Log3 $name,5,'Trying to convert xml to array...';
  eval {$xml->XMLin($response, ForceArray => ['item']);};
  rssFeed_Log3 $name,5,"evalXMLerror: $@";
  
  #rssFeed_Log3 $name,4,"evalXMLresult: $evResult";
  
  if(!$@) {
  	$nachrichten = $xml->XMLin($response, ForceArray => ['item']);
  }
  
  
  
  # -> ToDo: Add a title line to the ticker data e.g. to describe what's
  #          displayed. This should be a perl-special to evaluate, so 
  #          the data could possibly extracted from readings.
  #my $title=AttrVal($name,'rnDisplayTitle',undef);
  #$title=$urlbase if($title eq '@');
  #push (@ticker,$title) if ($title);
  
  
  #Extracting data from array and converting it to utf8 where necessary.
  my $feedTitle=$nachrichten->{channel}{title};
  #$feedTitle=latin1ToUtf8($feedTitle) if($lutf);
  $feedTitle=encode($enc,$feedTitle) if($enc);
  
  my $feedDescription=$nachrichten->{channel}{description};
  #$feedDescription=latin1ToUtf8($feedDescription) if($lutf);
  $feedDescription=encode($enc,$feedDescription) if ($enc);
  
  my $feedLink=$nachrichten->{channel}{link};
  my $feedBuildDate=$nachrichten->{channel}{lastBuildDate};
  my $feedPubDate=$nachrichten->{channel}{pubDate};
  
  my $feedImageURL=$nachrichten->{channel}{image}{url};
  
  my $feedImageTitle=$nachrichten->{channel}{image}{title};
  #$feedImageTitle=latin1ToUtf8($feedImageTitle) if ($lutf);
  $feedImageTitle=encode($enc,$feedImageTitle) if ($enc);
  
  #Now starting update of the readings
  readingsBeginUpdate($dhash);
  
  readingsBulkUpdate($dhash,$feed_prefix.'title',$feedTitle) if ($feedTitle && $params{'title'});
  readingsBulkUpdate($dhash,$feed_prefix.'description',$feedDescription) if ($feedDescription && $params{'description'});
  readingsBulkUpdate($dhash,$feed_prefix.'link',$feedLink) if ($feedLink && $params{'link'});
  readingsBulkUpdate($dhash,$feed_prefix.'pubDate',$feedPubDate) if ($feedPubDate && $params{'pubDate'});
  readingsBulkUpdate($dhash,$feed_prefix.'buildDate',$feedBuildDate) if ($feedBuildDate && $params{'buildDate'});
  readingsBulkUpdate($dhash,$feed_prefix.'imageTitle',$feedImageTitle) if ($feedImageTitle && $params{'imageTitle'});
  readingsBulkUpdate($dhash,$feed_prefix.'imageURL',$feedImageURL) if ($feedImageURL && $params{'imageURL'});
  
  #Loop through the array to extract the data for each single news block in 
  #the feed data array
  while ($i < $lines) {
    if($nachrichten->{channel}{item}[$i]{title}) {
	my $cline=$nachrichten->{channel}{item}[$i]{title};
	#$cline=latin1ToUtf8($cline) if($lutf);
	$cline=encode($enc,$cline) if ($enc);
	
	my $cdesc=$nachrichten->{channel}{item}[$i]{description};
	#$cdesc=latin1ToUtf8($cdesc) if($lutf);
	$cdesc=encode($enc,$cdesc) if ($enc);
	
	my $clink=$nachrichten->{channel}{item}[$i]{link};
	#$clink=latin1ToUtf8($clink) if ($lutf);
	$clink=encode($enc,$clink) if ($enc);

	my $cdate=$nachrichten->{channel}{item}[$i]{pubDate};
	#$cdate=latin1ToUtf8($cdate) if ($lutf);
	$cdate=encode($enc,$cdate) if ($enc);
	
	#my $cenc=$nachrichten->{channel}{item}[$i]{enclosure}{url};

	last unless $cline;
	
	#store headlines tor ticker-array for later joining to healines string
    my $h = $tt_start.$cline.$tt_end;
    last unless $h;
    push (@ticker,$h);
	
	#Index for numbering each news-block
	my $ndx=sprintf('%0'.$nb_indexlength.'s',$i);

	readingsBulkUpdate($dhash,$nb_prefix.$ndx.$nb_separator."title",$cline) if ($params{'title'}); 
	readingsBulkUpdate($dhash,$nb_prefix.$ndx.$nb_separator."description", $cdesc) if ($cdesc && $params{'description'}); 
	readingsBulkUpdate($dhash,$nb_prefix.$ndx.$nb_separator."link", $clink) if ($params{'link'}); 
	readingsBulkUpdate($dhash,$nb_prefix.$ndx.$nb_separator."pubDate", $cdate) if ($params{'pubDate'}); 
	#readingsBulkUpdate($dhash,$nb_prefix.$ndx.$nb_separator."image",$cenc) if ($cenc);

	}
    $i++;
  }
  
  my $tickerLines=@ticker;
  readingsBulkUpdate($dhash,"preparedLines", $tickerLines); 
  
  #mass updating/generation of readings is complete so
  #tell FHEM to update them now!
  readingsEndUpdate($dhash,0);
  
  #joining all headlines separated by newlin in a single string and
  #store it in the readings
  my $tickerHeadlines=join("\n", @ticker);
  readingsSingleUpdate($dhash,$rdHeadlines, $tickerHeadlines,0);
  
return;
}


1;
#======================================================================
#======================================================================
#
# HTML Documentation for help and commandref
#
#======================================================================
#======================================================================
=pod
=item device
=begin html

<a name="rssFeed"></a>
<h3>rssFeed</h3>
<ul>
  This device helps to extract data from an rss feed specified by the
  url given in the DEF section. Trhe results will be extracted to 
  several corresponding readings. Also the headlines of the news
  elements will be extracted to a special "ticker"-string that could
  be retrieved via GET or a special function.
  The data will be updated automatically after the given interval.
  <br/><br/>

  <a name="rssFeeddefine"></a>
  <b>Define</b>
  <ul>
      <code>define &lt;name&gt; rssFeed &lt;url&gt; [interval]</code>
      <br/><br/>
      <ul>
          url = url of the rss feed
      </ul>
      <ul>
          interval = actualization interval in seconds
          <br/>
          Minimum for this value is 600 and maximum is 86400
      </ul>
      <br/>
      Example:
      <ul>
          <code>define rssGEA rssFeed http://www.gea.de/rss?cat=Region%20Reutlingen&amp;main=true 3600</code>
          <br/><br/>
          The example will retrieve the data from the rss feed every hour
      </ul>
  </ul>
  <br/>

  <a name="rssFeedset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; update</code><br/>
    retrieving the data from feed and updateing readings data
  </ul>
  <br/>

  <a name="rssFeedget"></a>
  <b>Get</b><br/>
  <ul>
      <code>get &lt;name&gt; ticker</code><br/>
      getting the headlines from the feed with specified formatting
      (also see attributes)
  </ul>
  <br/>
  <a name="rssFeedattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="disabled">disable</a><br/>
        This attribute can be used to disable the entier feed device (1)
        or to activate it again (0 or attribute missing).
        If the device is disabled all readings will be removed, except
        the state reading which will then be set to "disabled".
        Data will no longer be automatically retrieved from the url.
        The ticker data contains only one line indicating the disabled
        ticker device. (s.a. attribute rfDisabledText).
        <br/>
    </li>
    <li><a name="rfDisabledText">rfDisabledText</a><br/>
        The text in this attribute will be returnde by GET ticker when the 
        device is disabled (s.a. attribute disable).
        If this attribute is not specified a default text is returned.<br/>
        Example: <code>attr &lt;name&gt; rfDisabledText This feed is disabled</code>
    </li>
    <li><a name="rfTickerChars">rfTickerChars</a><br/>
        Specifies a string which will surround each headline in the ticker data.<br/>
        Example: <code>attr &lt;name&gt; rfTickerChars +++</code>
        <br/>
        Result: <code>+++ This is a sample headline +++</code>
        <br/>
    </li>
    <li><a name="rfMaxLines">rfMaxLines</a><br/>
        Defines the maximum number of news items that will be extracted from the
        feed. If there are less items in the feed then specified by this attribute 
        then only that few items are extracted.
        If this attribute is missing a default of 10 will be assumed.<br/>
        Example: <code>attr &lt;name&gt; rfMaxLines 15</code>
        <br/>
    </li>
    <li><a name="rfEncode">rfEncode</a><br/>
        Defines an encoding which will be used for any text extracted from the 
        feed that will be applied before setting the readings. Therefore the
        encode method of the Perl-core module Encode is used.
        If the attribute is missng then no encoding will be performed.
        Sometimes this is necessary when feeds contain wide characters that
        could sometimes lead to malfunction in FHEMWEB.
        Also the headlines data returned by rssFeedFunctions and get ticker
        are encoded using this method.
        <br/>
    </li>
    <li><a name="rfReadings">rfReadings</a><br/>
        This attribute defines the readings that will be created from the extracted
        data. It is a comma separated list of the following values:
        <ul>
            <li>title = title section<br/>
                extract the title section of the feed and each news item to a 
                corresponding reading<br/>
            </li>
            <li>description = description section<br/>
                extract the description section of the feed and each news item
                to a corresponding reading
                <br/>
            </li>
            <li>pubDate = Publication time of feed and of each news item will
                be extracted to a corresponding reading.
                <br/>
            </li>
            <li>link = link url to the feed or to the full article of a 
                single news items in the feed.
                <br/>
            </li>
            <li>buildDate = time of the last feed actulization by the feed  
                vendor.
                <br/>
            </li>
            <li>imageURl = url of a probably available image of a news item
                <br/>
            </li>
            <li>imageTitle = image title of a probably available news item
                image.
                <br/>
            </li>
        </ul>
        If this attribute is missing "title,description,pubDate" will be assumed
        as default value. When the device is defined for the first time the 
        attribute will be automatically created with the default value.
        <br/>
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br/>
  <a name="rssFeedfunctions"></a>
  <b>Functions</b>
  <ul>
      <li>rssFeedGetTicker<br/>
          This function will returned the foratted headlines as a single string.
          Each headline will be separated by a new line character.
          The result of this function can for example be used in InfoPanel as
          ticker data.
          The function takes the name of a rssFeed device as single parameter.
          The result is the same as from <code>get ticker</code> as it uses this function too.
          Syntax: <code> rssFeedGetTicker(&lt;rssFeedDevice&gt;)</code><br/>
      </li>
  </ul><br/>
   <a name="rssFeedreadings"></a>
  <b>Readings</b>
  <ul>
      Depending on the attribute rfReadings a bunch of readings is created
      from the extracted news feed data.
      Some of the readings ar prefixed to tell to which part of the feed the
      data belongs to.
  </ul>
  <ul>
      <br/>
      <li><code>Nxx_</code><br/>
          readings with that prefix correspond to the news items in the feed.
          <code>xx</code> index of the news item
          <br/>
          Example showing the readings of a single news item<br/>
          <ul>
              <code> N00_title </code><br/>
              <code> N00_descripton </code><br/>
              <code> N00_pubDate </code><br/>
          </ul>
      </li>
      <li><code>f_</code><br/>
          redings with that prefix correspond to the feed itself.
          <br/>
          Example of feed-readings:
          <ul>
              <code> f_title </code><br/>
              <code> f_descripton </code><br/>
              <code> f_buildDate </code><br/>
          </ul>
      </li>
      <li><code>preparedLines</code><br/>
        This readings contains the number of new items that were extracted
        in the last update of the feed data.
      </li>
      <li><code>gzippedFeed</code><br/>
        Sometimes RSS-Feed data is delivered gzipped. This is automatically
		recognized by the module. So if the received data was originally
		gzipped this reading is set to 1 otherwise it is set to 0
      </li>
      <li><code>state</code><br/>
        The state reading contains the timestamp of the last automatic or manual
        update of the device data from the feed, as long as the device is not
        disabled.
        If the device is disabled state contains "disabled".
        When the device is defined then the start of cyclic updates is retarded
        for about 10 seconds. During that time state is set to "defined"
      </li>
  </ul><br/>
  
</ul>

=end html

=begin html_DE

<a name="rssFeed"></a>
<h3>rssFeed</h3>
<ul>

  Mit diesem Hilfs-Device kann ein RSS-Feed per URL abgerufen werden.
  Das Ergebnis wird zum einen in entsprechende Readings (s.u.) eingetragen,
  zum Anderen k&ouml;nnen die Schlagzeilen (Headlines) noch per GET oder per
  bereitgestellter Funktion als Ticker-Daten abgerufen werden.
  Die Daten des RSS-Feeds werden dabei jeweils im angegebenen Interval
  aktualisiert.
  <br><br>

  <a name="rssFeeddefine"></a>
  <b>Define</b>
  <ul>
      <code>define &lt;name&gt; rssFeed &lt;url&gt; [interval]</code>
      <br><br>
      <ul>
          url = URL zum RSS-Feed
      </ul>
      <ul>
          interval = Aktualisierungsinterval in Sekunden<br>
          minimum Wert sind 600 Sekunden (10 Minuten)<br>
          maximum Wert sind 86400 Sekunden (24 Stunden)
      </ul>
      <br>
      Beispiel:
      <ul>
          <code>define rssGEA rssFeed http://www.gea.de/rss?cat=Region%20Reutlingen&main=true 3600</code>
          <br><br>
          Damit wird st&uuml;ndlich der RSS-Feed des Reutlinger Generalanzeigers 
          abgerufen.
      </ul>
  </ul>
  <br>

  <a name="rssFeedset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; update</code><br>
    Abrufen der Daten vom rssFeed und aktualisieren der Readings
  </ul>
  <br>

  <a name="rssFeedget"></a>
  <b>Get</b><br>
  <ul>
      <code>get &lt;name&gt; ticker</code><br>
      Abrufen der zuletzt gelesenen Schlagzeilen im gew&uuml;nschten 
      Format (s. Attribute)
  </ul>
  <br>
  <a name="rssFeedattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a name="disabled">disabled</a><br>
        Mit diesem Attribut kann das Device deaktiviert (1) werden
        bzw. auch wieder aktiviert (0 oder Attribut nicht vorhandn).
        Wenn das device deaktiviert ist, sind keine Readings mehr
        vorhanden, au&szlig;er state. Au&szlig;erdem werden die Daten nicht mehr
        zyklisch aktualisiert und get ticker liefert nur noch die
        Information zur&uuml;ck, dass der Ticker nicht mehr aktiv ist
        (s. dazu auch Attribut rfDisabledText).
        <br>
    </li>
    <li><a name="rfDisabledText">rfDisabledText</a><br>
		Der hier eingetragenee Text wird beim Abruf der Schlagzeilen als einzige
        Zeile&nbsp;angezeigt, wenn der rssFeed disabled ist (s. Attribut disabled).
        Ist dieses Attribut nicht angegeben, so wird ein Standardtext angezeigt.<br>
        Beispiel: <code>attr &lt;name&gt; rfDisabledText Dieser Feed wurde deaktiviert</code>
    </li>
    <li><a name="rfTickerChars">rfTickerChars</a><br>
        Hiermit kann eine Zeichenfolge festgelegt werden, die bei den Schlagzeilen 
        f&uuml;r den get-Abruf vor und nach jeder Schlagzeile, wie bei einem Nachrichten-Ticker
        angef&uuml;gt wird.
        Beispiel: <code>attr &lt;name&gt; rfTickerChars +++</code>
        <br>
        Ergebnis: <code>+++ Dies ist eine Beispiel-Schlagzeile +++</code>
        <br>
    </li>
    <li><a name="rfMaxLines">rfMaxLines</a><br>
        Bestimmt, wieviele Schlagzeilen maximal aus dem Feed extrahiert werden sollen.<br>
        Sind weniger Nachrichten-Elemente im Feed enthalten, als &uuml;ber rfMaxLines angegeben,
        so werden eben nur so viele Schlagzeilen extrahiert, wie vorhanden sind.<br>
        Ist dieses Attribut nich angegeben, so wird daf&uuml;r der Standard-Wert 10 angenommen.<br>
        Beispiel: <code>attr &lt;name&gt; rfMaxLines 15</code>
        <br>
    </li>
    <li><a name="rfEncode">rfEncode</a><br>
        Hier kann eine Encoding-Methode (Bspw. utf8) angegeben werden.
        Die Texte die aus dem Feed extrahiert werden (title, descripton, ...) 
        werden dann vor der Zuwesung an die Readings mittels encode (Perl core-Module Encode) 
        enkodiert. Fehlt dieses Attribut, so findet keine umkodierung statt.
        Das kann u.U. notwendig sein, wenn in den zur&uuml;ckgelieferten Feed-Daten s.g. wide Characters
        enthalten sind. Dies kann evtl. dazu f&uuml;hren, das u.a. die Darstellung in FHEMWEB nicht mehr
        korrekt erfolgt.
        Dies betrifft auch das Ergebnis von rssFeedFunctions, bzw. get ticker.
        <br>
    </li>
    <li><a name="rfReadings">rfReadings</a><br>
        &Uuml;ber dieses Attribut kann angegeben werden, welche Daten aus dem RSS-Feed in 
        Readings extrahiert werden sollen. Das Attribut ist als Komma getrennte Liste 
        anzugeben.<br>
        Zur Auswahl stehen dabei folgende m&ouml;glichen Werte:
        <ul>
            <li>title = Titelzeile<br>
                Dies erzeugt ein Reading f&uuml;r den Feed-Titel und f&uuml;r jedes
                Nachrichten-Element aus dem Feed.<br>
            </li>
            <li>description = Beschreibungstext
                Dies erzeugt ein Reading f&uuml;r die Feed-Beschreibung, bzw.
                f&uuml;r den Beschreibungstext jeden Nachrichten-Eelements.<br>
            </li>
            <li>pubDate = Zeitpunkt der Ver&ouml;ffentlichung des Feeds, bzw. der einzelnen 
                Nachrichten-Elemente
                <br>
            </li>
            <li>link = Link zum Feed, bzw. zum einzelnen Nachrichten-Element auf
                der Homepage des Feeds.
                <br>
            </li>
            <li>buildDate = Zeitpunkt der letzten aktualisierung der Feed-Daten
                vom Feed-Betreiber.
                <br>
            </li>
            <li>imageURl = URL zum ggf. vorhandenen Bild eines Nachrichten-Elements, 
                bzw. zum Nachrichten-Feed.
                <br>
            </li>
            <li>imageTitle = Titel eines ggf. zum Feed oder Nachrichten-Element
                vorhandenen Bildes.
                <br>
            </li>
        </ul>
        Ist Dieses Attribut nicht vorhanden, so werden die Werte "title,description,pubDate" als
        Voreinstellung angenommen. Beim ersten Anlegen des Device wird das Attribut automatisch
        erste einmal mit genau dieser Voreinstellung belegt.
            
        <br>
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
  <a name="rssFeedfunctions"></a>
  <b>Funktionen</b>
  <ul>
      <li>rssFeedGetTicker<br>
          Diese Funktion gibt die ermittelten und formatierten Schlagzeilen als Zeichenkette
          zur&uuml;ck. Die einzelnen Schlagzeilen sind dabei durch Zeilenvorschub getrenn.
          Dieses Ergebnis kann bspw. in einem InfoPanel f&uuml;r einen Ticker verwendet werden.
          Der Funktion muss dazu der Name eines rssFeed-Devices &uuml;bergeben werden.
          Die Ausgabe ist praktisch die selbe wie das Ergebnis, das bei <code>get ticker</code>
          geliefert wird.<br>
          Syntax: <code> rssFeedGetTicker(&lt;rssFeedDevice&gt;)</code><br>
      </li>
  </ul><br>
   <a name="rssFeedreadings"></a>
  <b>Readings</b>
  <ul>
      Je nach Auswahl der Attribute werden verschiedene Readings bereitgestellt.
      Diese Readings sind teilweise mit einem Pr&auml;fix versehen um sie bspw. dem Feed 
      selbst oder einem Nachrichten-Element zuozuordnen.
  </ul>
  <ul>
      <br>
      <li><code>Nxx_</code><br>
          Diese Readings beziehen sich alle auf die einzelnen Nachrichten-Elemente, wobei
          <code>xx</code> den Index des jeweiligen Nachrichten-Elements angibt.
          <br>
          Beispiel f&uuml;r die Readings eines Nachrichten-Elements:<br>
          <ul>
              <code> N00_title </code><br/>
              <code> N00_descripton </code><br/>
              <code> N00_pubDate </code><br/>
          </ul>
      </li>
      <li><code>f_</code><br>
          Diese Readings beziehen sich alle auf den Nachrichten-Feed selbst.
          <br>
          Beispiel f&uuml;r die Readings des Nachrichten-Feeds<br>
          <ul>
              <code> f_title </code><br/>
              <code> f_descripton </code><br/>
              <code> f_buildDate </code><br/>
          </ul>
      </li>
      <li><code>preparedLines</code><br>
        Dieses Reading gibt an, wie viele Schlagzeilen tats&auml;chlich beim letzten
        update aus dem Nachrichten-Feed extrahiert wurden.
      </li>
      <li><code>gzippedFeed</code><br>
		Manche Feeds werden in gezippter (gzip) Form ausgeliefert. Das wird vom
		Modul automatisch erkannt und die Daten im Bedarfsfall dekomprimiert.
		Wurde beim letzten update der Feed in gezippter Form ausgeliefert, so wird
		dieses Reading auf 1 gesetzt, andernfalls auf 0.
	  </li>
      <li><code>state</code><br>
        Dieses Reading gibt, wenn das Device nicht disabled ist, den Zeitpunkt
        der letzten aktualisierung mittels update an, egal ob automatisch oder
        manuell ausgel&ouml;st. Ist das device disabled, steht genau das im Reading.
        Beim Anlegegen des Device mittels define findet das erste Aktualisieren 
        der Daten verz&ouml;gert statt. W&auml;hrend dieser Verz&ouml;gerung steht der state
        auf "defined".
      </li>
  </ul><br>
  
</ul>

=end html_DE
=cut
