resource "aws_elasticache_cluster" "mc01" {
  cluster_id      = var.cache_cluster_id
  engine          = "memcached"
  node_type       = var.cache_node_type
  num_cache_nodes = var.cache_num_nodes # node based cluster
  port            = 11211

  security_group_ids = [aws_security_group.backend.id]
  subnet_group_name  = aws_elasticache_subnet_group.default.name

  tags = {
    Name = "mc01"
  }
}

resource "aws_elasticache_subnet_group" "default" {
  name       = "default-vpc-cache-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}
