#!/usr/bin/env bash
# Render the lab's Nagios objects from runtime configuration, then run Nagios
# and Apache in one container.
#
# Required environment:
#   ALB_DNS                 ALB DNS name (or an in-cluster service name)
#   NAGIOS_ADMIN_PASSWORD   password for the nagiosadmin digest login
set -euo pipefail

: "${ALB_DNS:?ALB_DNS must be set (Deployment reads it from the scalestack-nagios-config ConfigMap)}"
: "${NAGIOS_ADMIN_PASSWORD:?NAGIOS_ADMIN_PASSWORD must be set (Deployment reads the scalestack-nagios-secret Secret)}"

echo "==> rendering Nagios objects for ALB '${ALB_DNS}'"
envsubst '${ALB_DNS}' \
  < /opt/scalestack/scalestack.cfg.tmpl \
  > /etc/nagios4/conf.d/scalestack.cfg

echo "==> writing the nagiosadmin digest login"
# htdigest -c asks for the password twice (password + confirmation); feed both.
printf '%s\n%s\n' "${NAGIOS_ADMIN_PASSWORD}" "${NAGIOS_ADMIN_PASSWORD}" \
  | htdigest -c /etc/nagios4/htdigest.users "Nagios4" nagiosadmin >/dev/null
chown root:www-data /etc/nagios4/htdigest.users
chmod 0640 /etc/nagios4/htdigest.users

# The CGIs build their links from url_html_path; the ALB serves us under /nagios.
sed -i 's|^url_html_path=.*|url_html_path=/nagios|' /etc/nagios4/cgi.cfg

a2enmod cgid auth_digest >/dev/null
a2enconf scalestack-nagios >/dev/null
a2disconf nagios4-cgi >/dev/null 2>&1 || true

echo "==> validating the Nagios configuration"
if ! nagios4 -v /etc/nagios4/nagios.cfg > /tmp/nagios-verify.log 2>&1; then
  cat /tmp/nagios-verify.log
  echo "ERROR: Nagios configuration is invalid; refusing to start." >&2
  exit 1
fi

echo "==> starting Nagios Core"
/usr/sbin/nagios4 -d /etc/nagios4/nagios.cfg

echo "==> starting Apache (UI at /nagios, health at /healthz)"
exec apache2ctl -D FOREGROUND
