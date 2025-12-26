package Slim::Plugin::ArcamAvrControl::Plugin;

# Lyrion Music Server / Logitech Media Server plugin
# Basic network control for Arcam AVR380 (power, volume, direct mode)


use strict;
use base qw(Slim::Plugin::Base);

use IO::Socket::INET;
use Scalar::Util qw(blessed);
use Time::HiRes ();

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;

if ( main::WEBUI ) {
	require Slim::Plugin::ArcamAvrControl::Settings;
}

my $log = Slim::Utils::Log->addLogCategory({
	category     => 'plugin.arcamavrcontrol',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_ARCAMAVRCONTROL_NAME',
});

my $prefs = preferences('plugin.arcamavrcontrol');

sub getDisplayName { 'PLUGIN_ARCAMAVRCONTROL_NAME' }

sub _hex {
	my ($bytes) = @_;
	return '' unless defined $bytes;
	return join(' ', map { sprintf('%02X', $_) } unpack('C*', $bytes));
}

sub clientPrefs {
	my ($class, $client) = @_;
	return unless $client;

	my $cp = $prefs->client($client);

	# Per-player defaults
	$cp->init({
		enable          => 0,
		host            => '',
		port            => 50000,
		maxVolume       => 85,   # player scale 0..100
		followVolume    => 1,
		powerOnOnPlay   => 1,
		directOnPowerOn => 0,
	});

	# Coerce legacy/blank values (prevents warning spam + makes UI consistent)
	my %defaults = (
		enable          => 0,
		followVolume    => 1,
		powerOnOnPlay   => 1,
		directOnPowerOn => 0,
		port            => 50000,
		maxVolume       => 85,
		host            => '',
	);

	for my $k (keys %defaults) {
		my $v = $cp->get($k);
		if (defined $v && !ref($v) && $v eq '') {
			$cp->set($k, $defaults{$k});
		}
	}

	return $cp;
}

sub _validateBool01OrEmpty {
	# Accept 0/1 as well as "" (some settings UIs submit empty string for unchecked boxes)
	my ($pref, $new) = @_;
	return 1 if !defined $new;
	return 1 if !ref($new) && $new eq '';
	return 1 if !ref($new) && $new =~ /^(0|1)$/;
	return 0;
}

sub initPlugin {
	my ($class) = @_;

	$class->SUPER::initPlugin();

	$prefs->setValidate(\&_validateBool01OrEmpty, 'enable');
	$prefs->setValidate({ validator => 'intlimit', low => 1, high => 65535 }, 'port');
	$prefs->setValidate({ validator => 'intlimit', low => 0, high => 99 }, 'maxVolume');
	$prefs->setValidate(\&_validateBool01OrEmpty, 'followVolume');
	$prefs->setValidate(\&_validateBool01OrEmpty, 'powerOnOnPlay');
	$prefs->setValidate(\&_validateBool01OrEmpty, 'directOnPowerOn');

	if ( main::WEBUI ) {
		Slim::Plugin::ArcamAvrControl::Settings->new;
	}

	# Subscribe to player power changes
	Slim::Control::Request::subscribe(
		\&_powerCmdCallback,
		[['power']],
	);

	# Subscribe to player volume changes
	Slim::Control::Request::subscribe(
		\&_mixerCmdCallback,
		[['mixer'], ['volume']],
	);

	# Optionally power on the AVR when playback starts / changes
	Slim::Control::Request::subscribe(
		\&_playlistCmdCallback,
		[['playlist'], ['play', 'newsong']],
	);
}

sub shutdownPlugin {
	Slim::Control::Request::unsubscribe(\&_powerCmdCallback);
	Slim::Control::Request::unsubscribe(\&_mixerCmdCallback);
	Slim::Control::Request::unsubscribe(\&_playlistCmdCallback);
}

sub _enabled {
	my ($cp) = @_;
	return $cp && $cp->get('enable') && $cp->get('host');
}

sub _powerCmdCallback {
	my ($request) = @_;
	my $client = $request->client();
	return unless $client && blessed($client);
	my $cp = __PACKAGE__->clientPrefs($client) || return;
	return unless _enabled($cp);

	main::DEBUGLOG && $log->is_debug && $log->debug(
		sprintf(
			"event: power (player=%s) host=%s port=%s",
			$client->name,
			($cp->get('host') || ''),
			($cp->get('port') || 50000),
		)
	);

	# Run after command applies, to read final power state reliably.
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time(),
		sub {
			my $isOn = $client->can('power') ? $client->power() : 0;
			if ($isOn) {
				main::DEBUGLOG && $log->is_debug && $log->debug("action: powerOn");
				_powerOn($cp);
			} else {
				# Only power off AVR if no other players controlling the same receiver are on.
				for my $other (Slim::Player::Client::clients()) {
					next unless $other && $other->can('power');
					next if $other->id eq $client->id;

					my $op = __PACKAGE__->clientPrefs($other) || next;
					next unless _enabled($op);
					next unless ($op->get('host') || '') eq ($cp->get('host') || '');
					next unless ($op->get('port') || 50000) == ($cp->get('port') || 50000);

					return if $other->power();
				}
				main::DEBUGLOG && $log->is_debug && $log->debug("action: powerOff");
				_powerOff($cp);
			}
		}
	);
}

sub _mixerCmdCallback {
	my ($request) = @_;
	my $client = $request->client();
	return unless $client && blessed($client);
	my $cp = __PACKAGE__->clientPrefs($client) || return;
	return unless _enabled($cp);
	return unless $cp->get('followVolume');

	main::DEBUGLOG && $log->is_debug && $log->debug(
		sprintf(
			"event: mixer volume (player=%s) host=%s port=%s",
			$client->name,
			($cp->get('host') || ''),
			($cp->get('port') || 50000),
		)
	);

	# Run after command applies, to read final volume reliably.
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time(),
		sub {
			my $vol = $client->can('volume') ? ($client->volume() || 0) : 0;
			main::DEBUGLOG && $log->is_debug && $log->debug("action: setVolumeFromPlayer playerVol=$vol");
			_setVolumeFromPlayer($cp, $vol);
		}
	);
}

sub _playlistCmdCallback {
	my ($request) = @_;
	my $client = $request->client();
	return unless $client && blessed($client);
	my $cp = __PACKAGE__->clientPrefs($client) || return;
	return unless _enabled($cp);
	return unless $cp->get('powerOnOnPlay');

	main::DEBUGLOG && $log->is_debug && $log->debug(
		sprintf(
			"event: playlist %s (player=%s) host=%s port=%s",
			($request->getRequest(1) || ''),
			$client->name,
			($cp->get('host') || ''),
			($cp->get('port') || 50000),
		)
	);

	# Power on when playback starts (playlist play/newsong).
	Slim::Utils::Timers::setTimer(
		$client,
		Time::HiRes::time(),
		sub {
			main::DEBUGLOG && $log->is_debug && $log->debug("action: powerOn (from playback)");
			_powerOn($cp);
		}
	);
}

# --- Arcam protocol helpers -------------------------------------------------
# Frame format used by the Arcam protocol:
# [ 0x21, zone, command, 0x01, data, 0x0D ]
#
# Examples from Arcam doc (SH256E Issue 2):
# - Power On:  0x21 0x01 0x08 0x02 0x10 0x7B 0x0D
# - Standby:   0x21 0x01 0x08 0x02 0x10 0x7C 0x0D
# - Volume:    0x21 0x01 0x0D 0x01 <level> 0x0D
# - Direct:    0x21 0x01 0x0F 0x01 0x01|0x00 0x0D

sub _sendFrame {
	my ($cp, $cmd, $data) = @_;

	my $host = $cp->get('host') || return;
	my $port = $cp->get('port') || 50000;

	# AVR380: implement main zone only (zone byte = 0x01)
	my $frame = pack('C6', 0x21, 0x01, $cmd, 0x01, $data, 0x0D);

	main::DEBUGLOG && $log->is_debug && $log->debug(
		sprintf("build: host=%s port=%s cmd=0x%02X data=0x%02X frame=[%s]", $host, $port, $cmd, $data, _hex($frame))
	);

	return _sendRawFrame($cp, $frame, sprintf('cmd=0x%02X data=0x%02X', $cmd, $data));
}

sub _sendRawFrame {
	my ($cp, $frame, $label) = @_;

	my $host = $cp->get('host') || return;
	my $port = $cp->get('port') || 50000;

	main::DEBUGLOG && $log->is_debug && $log->debug(
		sprintf(
			"tx: host=%s port=%s %s frame=[%s]",
			$host,
			$port,
			($label || ''),
			_hex($frame),
		)
	);

	my $sock = IO::Socket::INET->new(
		PeerAddr => $host,
		PeerPort => $port,
		Proto    => 'tcp',
		Timeout  => 1,
	);

	if (!$sock) {
		main::INFOLOG && $log->is_info && $log->info("Unable to connect to Arcam at $host:$port: $!");
		main::DEBUGLOG && $log->is_debug && $log->debug("tx failed: connect error: $!");
		return;
	}

	my $written = $sock->syswrite($frame);
	main::DEBUGLOG && $log->is_debug && $log->debug(
		defined $written ? "tx ok: wrote $written bytes" : "tx failed: write error: $!"
	);
	$sock->close();
}

sub _powerOn {
	my ($cp) = @_;
	# Corrected power command from Arcam doc (SH256E Issue 2):
	# 0x21 0x01 0x08 0x02 0x10 0x7B 0x0D
	my $frame = pack('C7', 0x21, 0x01, 0x08, 0x02, 0x10, 0x7B, 0x0D);
	_sendRawFrame($cp, $frame, 'powerOn');
	if ($cp->get('directOnPowerOn')) {
		_sendFrame($cp, 0x0F, 0x01);
	}
}

sub _powerOff {
	my ($cp) = @_;
	# Corrected standby command from Arcam doc (SH256E Issue 2):
	# 0x21 0x01 0x08 0x02 0x10 0x7C 0x0D
	my $frame = pack('C7', 0x21, 0x01, 0x08, 0x02, 0x10, 0x7C, 0x0D);
	_sendRawFrame($cp, $frame, 'standby');
}

sub _setVolumeFromPlayer {
	my ($cp, $playerVol) = @_;

	$playerVol = 0   if !defined $playerVol;
	$playerVol = 0   if $playerVol < 0;
	$playerVol = 100 if $playerVol > 100;

	my $max = $cp->get('maxVolume');
	$max = 99 if !defined $max;
	$max = 0  if $max < 0;
	$max = 99 if $max > 99;

	# Rescale LMS 0..100 to Arcam 0..max (so 100% => maxVolume, 50% => maxVolume/2, etc.)
	my $avrVol = int(($playerVol * $max / 100) + 0.5);
	$avrVol = 0  if $avrVol < 0;
	$avrVol = 99 if $avrVol > 99;

	_sendFrame($cp, 0x0D, $avrVol);
}

1;


