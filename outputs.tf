output "rds_endpoint" {
  value = aws_db_instance.db01.address
}

output "rabbitmq_endpoint" {
  value = aws_mq_broker.rmq01.instances[0].endpoints
}

output "memcached_endpoint" {
  value = aws_elasticache_cluster.mc01.cluster_address
}

output "tomcat1_public_ip" {
  value = aws_instance.tomcat1.public_ip
}

output "tomcat2_public_ip" {
  value = aws_instance.tomcat2.public_ip
}

output "load_balancer_dns" {
  value = aws_lb.lb_tomcat.dns_name
}
