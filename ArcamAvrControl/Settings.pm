package Plugins::ArcamAvrControl::Settings;

# Lyrion Music Server / Logitech Media Server plugin settings

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('plugin.arcamavrcontrol');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_ARCAMAVRCONTROL_NAME');
}

sub needsClient {
	return 1;
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/ArcamAvrControl/settings/basic.html');
}

sub handler {
	my ($class, $client, $params) = @_;

	# Must have a selected player for per-player settings
	if (!$client) {
		$params->{warning} ||= string('CHOOSE_PLAYER');
		return $class->SUPER::handler($client, $params);
	}

	my $cp = Plugins::ArcamAvrControl::Plugin->clientPrefs($client);

	# Save (coerce checkboxes to 0/1)
	if ($params->{saveSettings}) {
		my %toSave = (
			enable          => $params->{pref_enable} ? 1 : 0,
			host            => defined $params->{pref_host} ? $params->{pref_host} : '',
			port            => $params->{pref_port},
			followVolume    => $params->{pref_followVolume} ? 1 : 0,
			maxVolume       => $params->{pref_maxVolume},
			powerOnOnPlay   => $params->{pref_powerOnOnPlay} ? 1 : 0,
			directOnPowerOn => $params->{pref_directOnPowerOn} ? 1 : 0,
			forceFixedOutput => $params->{pref_forceFixedOutput} ? 1 : 0,
		);

		for my $k (keys %toSave) {
			my (undef, $ok) = $cp->set($k, $toSave{$k});
			if (!$ok) {
				$params->{warning} .= sprintf(string('SETTINGS_INVALIDVALUE'), $toSave{$k}, $k) . '<br/>';
			}
		}

		# Apply (and potentially restore) fixed-output setting on the player after saving prefs.
		Plugins::ArcamAvrControl::Plugin->applyFixedOutput($client);
	}

	# Provide prefs to template
	$params->{prefs}->{pref_enable}          = $cp->get('enable');
	$params->{prefs}->{pref_host}            = $cp->get('host');
	$params->{prefs}->{pref_port}            = $cp->get('port');
	$params->{prefs}->{pref_followVolume}    = $cp->get('followVolume');
	$params->{prefs}->{pref_maxVolume}       = $cp->get('maxVolume');
	$params->{prefs}->{pref_powerOnOnPlay}   = $cp->get('powerOnOnPlay');
	$params->{prefs}->{pref_directOnPowerOn} = $cp->get('directOnPowerOn');
	$params->{prefs}->{pref_forceFixedOutput} = $cp->get('forceFixedOutput');

	return $class->SUPER::handler($client, $params);
}

1;


