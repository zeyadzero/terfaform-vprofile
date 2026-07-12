resource "aws_db_instance" "db01" {
  identifier     = var.db_identifier
  engine         = "mysql"
  engine_version = "8.0"

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp2"

  username = var.db_username
  password = var.db_password # self managed credentials

  db_subnet_group_name  = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.backend.id]
  publicly_accessible    = true

  # no AZ preference -> let AWS pick within the default subnet group
  multi_az = false

  skip_final_snapshot = true
  apply_immediately    = true

  tags = {
    Name = "db01"
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "default-vpc-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "default-vpc-subnet-group"
  }
}
