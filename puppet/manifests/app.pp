# Puppet owns the application baseline on each app server:
#   - required OS packages (python3, curl)
#   - the unprivileged service user and config directory
#   - the systemd unit ("web service configuration")
#   - ensuring the service is enabled and running
#
# Puppet deliberately does NOT upgrade OS packages. Ansible owns package
# patching (apt dist-upgrade) in the maintenance workflow.
# Puppet does NOT manage the deployment of /opt/health-app/health_app.py;
# that is done by the Ansible `app` role.

package { ['python3', 'curl', 'ca-certificates']:
  ensure => installed,
}

user { 'healthapp':
  ensure     => present,
  system     => true,
  shell      => '/usr/sbin/nologin',
  home       => '/nonexistent',
  managehome => false,
}

file { '/opt/health-app':
  ensure => directory,
  owner  => 'root',
  group  => 'root',
  mode   => '0755',
}

file { '/etc/health-app':
  ensure  => directory,
  owner   => 'healthapp',
  group   => 'healthapp',
  mode    => '0755',
  require => User['healthapp'],
}

file { '/etc/systemd/system/health-app.service':
  ensure  => file,
  owner   => 'root',
  group   => 'root',
  mode    => '0644',
  content => @(SERVICE),
    [Unit]
    Description=Health-gated patching lab demo application
    After=network.target

    [Service]
    Type=simple
    User=healthapp
    Group=healthapp
    Environment=HEALTH_APP_PORT=8080
    ExecStart=/usr/bin/python3 /opt/health-app/health_app.py
    Restart=always
    RestartSec=2
    NoNewPrivileges=true
    ProtectSystem=strict
    ReadWritePaths=/etc/health-app

    [Install]
    WantedBy=multi-user.target
    | SERVICE
  notify  => Service['health-app'],
}

service { 'health-app':
  ensure     => running,
  enable     => true,
  hasstatus  => true,
  hasrestart => true,
  require    => [
    Package['python3'],
    User['healthapp'],
    File['/etc/systemd/system/health-app.service'],
    File['/etc/health-app'],
  ],
}
