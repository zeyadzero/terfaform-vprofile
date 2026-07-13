resource "aws_mq_broker" "rmq01" {
  broker_name               = var.mq_broker_name
  engine_type                = "RabbitMQ"
  engine_version              = var.mq_engine_version
  host_instance_type          = var.mq_instance_type
  deployment_mode              = "SINGLE_INSTANCE"
  auto_minor_version_upgrade  = true # required by AWS for RabbitMQ 3.13 brokers

  publicly_accessible = false # access type: private
  security_groups     = [aws_security_group.backend.id]
  subnet_ids           = [local.tomcat1_subnet_id]

  user {
    username = var.mq_username
    password = var.mq_password
  }

  tags = {
    Name = "rmq01"
  }
}

# rmq01.instances[0].endpoints[0] comes back as "amqps://<host>:5671"
# we only need the hostname part for application.properties
locals {
  rmq_host = split(":", replace(aws_mq_broker.rmq01.instances[0].endpoints[0], "amqps://", ""))[0]
}
