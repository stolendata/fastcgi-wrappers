#!/usr/bin/perl

# Original author: Denis S. Filimonov
# Patched by Lewin Bormann <lbo@spheniscida.de>
# Changes (quite much):
#   - Using STDIN as socket, for cooperation with Apache's mod_fcgid.
#   - No daemonization.
#   - No fork()s anymore, instead "inline" execution by first reading the
#     script and then executing it using eval().
#     This should result in far superior performance with perl scripts.

use FCGI;
use Socket;
use POSIX 'setsid';

require 'syscall.ph';

&daemonize;

#this keeps the program alive or something after exec'ing perl scripts
END() { } BEGIN() { }
*CORE::GLOBAL::exit = sub { die "fakeexit\nrc=".shift()."\n"; };
eval q{exit};
exit if( $@ and $@ !~ /^fakeexit/ );

&main;

sub daemonize()
{
    chdir '/' or die "Can't chdir to /: $!";
    defined( my $pid = fork ) or die "Can't fork: $!";
    exit if $pid;
    setsid or die "Can't start a new session: $!";
    umask 0;
}

sub main
{
    $socket = FCGI::OpenSocket( "127.0.0.1:8999", 10 ); #use IP sockets
    $request = FCGI::Request( \*STDIN, \*STDOUT, \*STDERR, \%req_params, $socket );
    request_loop() if $request;
    FCGI::CloseSocket( $socket );
}

sub request_loop
{
    while( $request->Accept() >= 0 )
    {
        #running the cgi app
        $ENV{$_} = $req_params{$_} foreach keys %req_params;

        my $script_content;
        open( my $script, '<', $req_params{SCRIPT_FILENAME} );
        {
            local $/;
            $script_content = <$script>;
        }
        close( $script );
        my $result = eval( $script_content );

        if( $@ or !defined($result) )
        {
            print "Content-type: text/plain\n\n";
            print "Error: $@\n" and next if $@;
            print "$req_params{SCRIPT_FILENAME} returned no output\n";
        }
    }
}
