# Nagios Core 4 as a Kubernetes pod.
#
# The image is a plain Debian package install: Nagios 4 + plugins, Apache with
# CGI, and an entrypoint that renders the lab's object config from the ALB DNS
# the Deployment passes in. No host packages, no /etc/nagios4 edits on nodes.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      # nagios4 is the metapackage: core + cgi + common
      nagios4 \
      monitoring-plugins-basic \
      apache2 \
      apache2-utils \
      gettext-base \
      python3 \
      curl \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 # The packaged localhost.cfg notifies through an MTA this image does not have.
 && rm -f /etc/nagios4/conf.d/localhost.cfg

COPY apache-nagios.conf /etc/apache2/conf-available/scalestack-nagios.conf
COPY config/commands.cfg /etc/nagios4/conf.d/scalestack-commands.cfg
COPY config/contacts.cfg /etc/nagios4/conf.d/scalestack-contacts.cfg
COPY config/scalestack.cfg.tmpl /opt/scalestack/scalestack.cfg.tmpl
COPY check_system_metrics.py /usr/lib/nagios/plugins/check_system_metrics.py
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/lib/nagios/plugins/check_system_metrics.py \
 # Unauthenticated health endpoint for the ALB target group.
 && printf 'ok\n' > /var/www/html/healthz

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -fsS http://127.0.0.1/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
