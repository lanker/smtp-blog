#!/usr/bin/perl

use Net::SMTP::Server;
use Net::SMTP::Server::Client;
use MIME::Parser;
use MIME::Entity;
use MIME::Words qw(:all);
use XML::Simple;
use LWP::Simple;
use Image::Magick;
use Image::ExifTool qw(:Public);
use Encode qw(from_to is_utf8);
use utf8;
use DBI;
# used for atom feed creation
use XML::Atom::Feed;
use XML::Atom::Entry;
use XML::Atom::Util qw(encode_xml);
use DateTime;

defined($ARGV[0]) or print "Usage:\nsmtp-blog <configfile>\n" and exit;

####### read settings
my $config = XMLin($ARGV[0]);
my $host = defined($config->{host}) ? $config->{host} : 'localhost';
my $port = defined($config->{port}) ? $config->{port} : 25;
my $ok_to = defined($config->{ok_to}) ? $config->{ok_to} : 'blog_address@doe.com';
my $user = defined($config->{user}) ? $config->{user} : 'unknown';
my $image_dir = defined($config->{image_dir}) ? $config->{image_dir} : 'images/';
my $image_small_dir = defined($config->{image_small_dir}) ? $config->{image_small_dir} : 'images/small/';
my $image_small_size = defined($config->{image_small_size}) ? $config->{image_small_size} : 320;
my $image_medium_dir = defined($config->{image_medium_dir}) ? $config->{image_medium_dir} : 'images/medium/';
my $image_medium_size = defined($config->{image_medium_size}) ? $config->{image_medium_size} : 800;
my $video_icon = defined($config->{video_icon}) ? $config->{video_icon} : 'video_icon.png';
my $latitude_id = defined($config->{latitude_id}) ? $config->{latitude_id} : '0123456789012345678';
$ok_to = '<' . $ok_to . '>';

# settings for the atom feed
my $blog_title = defined($config->{blog_title}) ? $config->{blog_title} : 'My Superduper Blog';
my $blog_id = defined($config->{blog_id}) ? $config->{blog_id} : 'http://my.superduper.blog';
my $feed_count = defined($config->{feed_count}) ? $config->{feed_count} : 25;
my $blog_post_id = defined($config->{blog_post_id}) ? $config->{blog_post_id} : 'http://my.superduper.blog/id/';
my $content_url = defined($config->{content_url}) ? $config->{content_url} : 'http://my.superduper.blog/i/';
my $content_url_small = defined($config->{content_url_small}) ? $config->{content_url_small} : 'http://my.superduper.blog/i/s/';
my $feed_file = defined($config->{feed_file}) ? $config->{feed_file} : 'blog.xml';
my $blog_author = defined($config->{blog_author}) ? $config->{blog_author} : 'Jane Doe';
my $blog_email = defined($config->{blog_email}) ? $config->{blog_email} : 'jane@doe.com';

print "logfile = $config->{logdir}\n";
my $logfile = $config->{logdir};


$SIG{INT} = \&clean_up;
sub clean_up {
    $SIG{INT} = \&clean_up;
    logga(0, "Stopping...");
    close(LOG_OUT);
}


sub logga {
    my $level = $_[0];
    my $msg = $_[1];
    my $i = 0;
    for ($i = 0; $i < $level; $i++) {
        $msg = '  ' . $msg;
    }

    ($s, $i, $h, $d, $m, $y, $wd, $yd, $dst) = localtime();
    my $date = sprintf("%4d%02d%02d|%02d%02d%02d", $y+1900,$m+1,$d,$h,$i,$s);
    my $msg = $date . ': ' . $msg . "\n";
    open(LOG_OUT, ">>" . $logfile) or die $!;
    print(LOG_OUT $msg);
    close(LOG_OUT);
}


logga(0, "Starting server...");
my $server = new Net::SMTP::Server($host, $port) or die;
my $conn;
####### main loop
while($conn = $server->accept()) {
    my $client = new Net::SMTP::Server::Client($conn) || croak("Unable to handle client connection: $!\n");

    logga(0, "processing new message");

    $client->process;

    logga(1, "From: " . $client->{FROM});
    logga(1, "To: " . $client->{TO}[0]);
    if ($client->{TO}[0] eq $ok_to) {
        handle_message($client->{MSG});
    }
    else {
        logga(1, 'wrong address: ' . $client->{TO}[0] . " skipping");
    }
}


sub handle_message {
    my $msg = $_[0];
    my $parser = new MIME::Parser;
    $parser->output_under("./posts");
    my $entity = $parser->parse_data($msg);
    my $iso8859 = false;
    my $subject = $entity->head->get('Subject');
    if ($subject =~ m/8859-1/) {
        $iso8859 = true;
    }
    $subject = decode_mimewords($subject);
    # decode_mimewords is supposed to return which charset that is used, but it doesnt't?
    if ($iso8859) {
        from_to($subject, "iso-8859-1", "utf8");
    }

    my $tex = '';
    my $filename = '';
    my $alt = '';
    my $acc = '';
    my $image_date = null;

    logga(1, "is_multipart: " . $entity->is_multipart);
    if ($entity->is_multipart) {
        my $parts = $entity->parts;
        logga(1, "parts: " . $parts);
        my $i = 0;
        while ($i < $parts) {
            my $e = $entity->parts($i);

            logga(1, $e->effective_type);
            # text...
            if ($e->effective_type eq "text/plain") {
                my $body = $e->bodyhandle;
                my $bodyIO = $body->open("r") || die "open body: $!";
                $text = join('', $bodyIO->getlines);
                $bodyIO->close;
                $charset = $e->head->mime_attr('content-type.charset');
                logga(1, "charset: " . $charset);
            }
            # jpeg...
            elsif ($e->effective_type eq "image/jpeg") {
                ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
                $filename = sprintf("%4d%02d%02d_%02d%02d%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec);
                $filename = $filename . '.jpg';
                $body = $e->bodyhandle;
                my $bodyIO = $body->open("r") || die "open body: $!";
                open(FILE_OUT, ">" . $image_dir . $filename) or die $!;
                print(FILE_OUT $bodyIO->getlines);
                close(FILE_OUT);
                $bodyIO->close;

                ####### rotate image and set file timestamp according to exif
                system('jhead -autorot -ft ' . $image_dir . $filename);

                ####### resize image, small
                my $p = new Image::Magick;
                $p->Read($image_dir . $filename);
                $p->Scale(geometry=>$image_small_size . 'x' . $image_small_size);
                $p->Write($image_small_dir . $filename);
                undef $p;

                ####### resize image, medium
                my $p = new Image::Magick;
                $p->Read($image_dir . $filename);
                $p->Scale(geometry=>$image_medium_size . 'x' . $image_medium_size);
                $p->Write($image_medium_dir . $filename);
                undef $p;

                ####### get gps data
                my $exifTool = new Image::ExifTool;
                $exifTool->Options('CoordFormat' => q{%.6f});
                $exifTool->ExtractInfo($image_dir . $filename);
                $lat = $exifTool->GetValue('GPSLatitude');
                $lon = $exifTool->GetValue('GPSLongitude');
                $alt = $exifTool->GetValue('GPSAltitude');

                ####### get image date
                $exifTool->Options(DateFormat => "%s");
                $exifTool->ExtractInfo($image_dir . $filename);
                $image_date = $exifTool->GetValue('CreateDate');
                if ($image_date < 0 || $image_date eq '') {
                    $image_date = null;
                }

            }
            # mp4...
            elsif ($e->effective_type eq "video/mp4" || $e->effective_type eq "video/3gpp") {
                ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
                $filename = sprintf("%4d%02d%02d_%02d%02d%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec);
                my $ext = '';
                if ($e->effective_type eq "video/mp4") {
                    $ext = '.mp4';
                }
                else {
                    $ext = '.3gp';
                }
                my $ogvname = $filename . '.ogv';
                $filename = $filename . $ext;
                my $body = $e->bodyhandle;
                my $bodyIO = $body->open("r") || die "open body: $!";
                open(FILE_OUT, ">" . $image_dir . $filename) or die $!;
                print(FILE_OUT $bodyIO->getlines);
                close(FILE_OUT);
                $bodyIO->close;
                # convert to ogv
                if ($e->effective_type eq "video/3gpp") {
                    system('ffmpeg2theora --inputfps 30 -F 30 ' . $image_dir . $filename . ' -o ' . $image_dir . $ogvname);
                }
                else {
                    system('ffmpeg -i ' . $image_dir . $filename . ' -acodec libvorbis -vcodec libtheora ' . $image_dir . $ogvname);
                }
                # save first frame as jpg
                system('ffmpeg -vframes 1 -i ' . $image_dir . $ogvname . ' -s qvga ' . $image_small_dir . $ogvname . '.jpg');
                # add icon
                my $p = new Image::Magick;
                $p->Read($image_small_dir . $ogvname . '.jpg');
                my $overlay = new Image::Magick;
                $overlay->Read($video_icon);
                $p->Composite(image=>$overlay, gravity=>'NorthEast', blend=>'80');
                $p->Write($image_small_dir . $ogvname . '.jpg');
            }
            $i++;
        }
    }
    else {
        $charset = $entity->head->mime_attr('content-type.charset');
        logga(1, "charset: " . $charset);
        my $body = $entity->bodyhandle;
        my $bodyIO = $body->open("r") || die "open body: $!";
        $text = join('', $bodyIO->getlines);
        $bodyIO->close;
    }

    ####### if no gps, get from latitude
    if (!defined($lat) || !defined($lon)) {
        my $latxml = get('http://www.google.com/latitude/apps/badge/api?user=' . $latitude_id . '&type=kml');
        my $xml = XMLin($latxml);
        my $coord = $xml->{Document}->{Placemark}->{Point}->{coordinates};
        $lon = $coord;
        $lat = $coord;
        $lon =~ s/(.*),.*/\1/;
        $lat =~ s/.*,(.*)/\1/;
        $acc = $xml->{Document}->{Placemark}->{description};
    }

    ####### reverse geocoding
    my $geoxml = get('http://maps.google.com/maps/geo?q=' . $lat . ',' . $lon . '&output=xml');
    my $xml = XMLin($geoxml);
    my $position_name = $xml->{Response}{Placemark}->{p1}->{address};

    if ($charset =~ m/8859-1/) {
        logga(1, "converting text to utf8");
        from_to($text, "iso-8859-1", "utf8");
    }
    if (!is_utf8($position_name)) {
        from_to($postition_name, "iso-8859-1", "utf8");
    }

    $subject =~ s/\n//g;
    ####### add to db
    add_post($subject, $text, $filename, $lon, $lat, $alt, $acc, $position_name, $user, $image_date);

    logga(1, "creating feed");
    create_feed();
    logga(0, "done processing message");

    ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
    my $time = sprintf("%4d%02d%02d|%02d%02d%02d", $year+1900,$mon+1,$mday,$hour,$min,$sec);
    print($time . ": done processing message\n");
}


sub add_post {
    ($title, $text, $files, $lon, $lat, $alt, $acc, $position_name, $user, $image_date) = @_;

    logga(2, "titel: " . $title);
    logga(2, "files: " .$files);
    logga(2, "longitude: " . $lon);
    logga(2, "latitude: " . $lat);
    logga(2, "altitude: " . $alt);
    logga(2, "accuracy: " . $acc);
    logga(2, "position_name: " . $position_name);
    logga(2, "user: " . $user);
    logga(2, "image_date: " . $image_date . " (" . scalar localtime($image_date) . ")");

    $dbh = DBI->connect("dbi:SQLite:blog.db") || die "Cannot connect: $DBI::errstr";
    $sth = $dbh->prepare("INSERT INTO posts VALUES(NULL, strftime('%s', 'now'), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)") or die "Couldn't prepare statement: " . $dbh->errstr;;

    $sth->execute($title, $text, $files, $lon, $lat, $alt, $acc, $position_name, '', $user, '', $image_date);
    $dbh->disconnect();
}


sub create_feed {
    $XML::Atom::DefaultVersion = "1.0";
    $XML::Atom::ForceUnicode = 1;
    my $dt = DateTime->now;
    my $now = $dt->ymd . 'T' . $dt->hms . 'Z';
    my $feed = XML::Atom::Feed->new;
    $feed->title($blog_title);
    $feed->id($blog_id);
    $feed->updated($now);

    my $self_link = XML::Atom::Link->new;
    $self_link->type('application/atom+xml');
    $self_link->rel('self');
    $self_link->href($blog_id);
    $feed->add_link($self_link);

    my $author = XML::Atom::Person->new;
    $author->name($blog_author);
    $author->email($blog_email);
    $feed->author($author);

    my $dbh = DBI->connect("dbi:SQLite:blog.db") || die "Cannot connect: $DBI::errstr";
    my $sth = $dbh->prepare('SELECT * FROM posts ORDER BY MIN(image_timestamp, timestamp) DESC LIMIT 25') or die "Couldn't prepare statement: " . $dbh->errstr;;
    $sth->execute();

    while (($id, $timestamp, $title, $text, $files, $longitude, $latitude, $position_name, $user) = $sth->fetchrow_array) {
        my $dt = DateTime->from_epoch(epoch => $timestamp);
        my $date = $dt->ymd . 'T' . $dt->hms . 'Z';
        my $filetype = '';

        if ($files =~ m/jpg/) {
            $filetype = 'jpg';
        }
        elsif ($files =~ m/mp4/) {
            $filetype = 'ogv';
        }

        my $post_link = XML::Atom::Link->new;
        $post_link->type('text/html');
        $post_link->rel('alternate');
        $post_link->href($blog_post_id . $id);

        my $entry = XML::Atom::Entry->new;
        $entry->title($title);
        $entry->id($blog_post_id . $id);
        $entry->add_link($post_link);
        $entry->published($date);
        $file = '';
        if ($filetype eq "jpg") {
            $file = '<a href="' . $content_url . $files . '"><img src="' . $content_url_small . $files . '"></a><br />';
        }
        elsif ($filetype eq "ogv") {
            $ogv = $files;
            $ogv =~ s/mp4/ogv/;
            $file = '<a href="' . $content_url .  $ogv . '"><img src="' . $content_url_small . $ogv . '.jpg"></a><br />
            Film: <a href="' . $content_url . $ogv . '">' . $ogv . '</a><br />';
        }
        $text =~ s/\n/<br \/>/g;
        $entry->content($file . $text);

        $feed->add_entry($entry);

        my $xml = $feed->as_xml;
        open FILE_OUT, ">" . $feed_file or die $!;
        print FILE_OUT $feed->as_xml();
        close FILE_OUT;
    }

    $dbh->disconnect();
}
