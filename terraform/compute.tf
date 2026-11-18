# Dedicated Nagios Core Continuous Monitoring Server
resource "aws_instance" "nagios" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.nagios_instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.nagios.id]
  associate_public_ip_address = true

  # Auto-install Nagios Core 4 + Apache on boot
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -uo pipefail

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y nagios4 monitoring-plugins-basic apache2 apache2-utils

    # Create nagiosadmin digest authentication (password: NagiosAdmin123!)
    python3 -c 'import hashlib; u, p = "nagiosadmin", "NagiosAdmin123!"; print(f"{u}:Nagios4:" + hashlib.md5(f"{u}:Nagios4:{p}".encode()).hexdigest())' > /etc/nagios4/htdigest.users
    chown root:www-data /etc/nagios4/htdigest.users
    chmod 0640 /etc/nagios4/htdigest.users

    # Remove default Swap check (t3.micro has no swap; would stay critical)
    python3 -c "
path = '/etc/nagios4/objects/localhost.cfg'
import re
s = open(path).read()
new = re.sub(r'define service \{[^}]*Swap Usage[^}]*\}\n?', '', s)
open(path, 'w').write(new)
" 2>/dev/null || true

    # Enable CGI execution in Apache
    a2enmod cgid

    # Restart and enable services
    systemctl restart nagios4 apache2
    systemctl enable nagios4 apache2
  EOF
  )

  tags = {
    Name    = "Nagios-Server"
    Role    = "nagios"
    Project = var.project_name
    Lab     = "true"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }
}
