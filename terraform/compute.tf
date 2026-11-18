resource "aws_instance" "app" {
  count                       = 3
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.app_instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = aws_subnet.public[count.index % 2].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  tags = {
    Name  = "${var.project_name}-app-${count.index + 1}"
    Role  = "app"
    Index = tostring(count.index + 1)
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }
}

resource "aws_instance" "nagios" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.nagios_instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.nagios.id]
  associate_public_ip_address = true

  tags = {
    Name = "${var.project_name}-nagios"
    Role = "nagios"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }
}
