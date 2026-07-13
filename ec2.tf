resource "aws_instance" "tomcat1" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = var.ec2_instance_type
  key_name               = var.key_name
  subnet_id              = local.tomcat1_subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.backend.id]

  root_block_device {
    volume_size = var.ec2_root_volume_size
    volume_type = "gp2"
  }

  user_data = templatefile("${path.module}/scripts/tomcat-userdata.sh.tpl", {
    db_endpoint  = aws_db_instance.db01.address
    db_username  = var.db_username
    db_password  = var.db_password
    mc_endpoint  = aws_elasticache_cluster.mc01.cluster_address
    rmq_endpoint = local.rmq_host
  })

  tags = {
    Name = "tomcat1"
  }
}

resource "aws_instance" "tomcat2" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = var.ec2_instance_type
  key_name               = var.key_name
  subnet_id              = local.tomcat2_subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.backend.id]

  root_block_device {
    volume_size = var.ec2_root_volume_size
    volume_type = "gp2"
  }

  user_data = templatefile("${path.module}/scripts/tomcat-userdata.sh.tpl", {
    db_endpoint  = aws_db_instance.db01.address
    db_username  = var.db_username
    db_password  = var.db_password
    mc_endpoint  = aws_elasticache_cluster.mc01.cluster_address
    rmq_endpoint = local.rmq_host
  })

  tags = {
    Name = "tomcat2"
  }
}
