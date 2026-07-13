variable "aws_region" {
  description = "AWS region (Virginia)"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
  default     = "po1"
}

# ---------------- RDS ----------------
variable "db_identifier" {
  type    = string
  default = "db01"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_password" {
  type      = string
  default   = "admin123"
  sensitive = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

# ---------------- AmazonMQ (RabbitMQ) ----------------
variable "mq_broker_name" {
  type    = string
  default = "rmq01"
}

variable "mq_username" {
  type    = string
  default = "admin"
}

variable "mq_password" {
  type      = string
  default   = "admin12345678"
  sensitive = true
}

variable "mq_engine_version" {
  type    = string
  default = "3.13"
}

variable "mq_instance_type" {
  description = "Single instance broker size (AWS no longer supports mq.t3.micro for new RabbitMQ brokers - only m7g/m5 families)"
  type        = string
  default     = "mq.m7g.medium"
}

# ---------------- ElastiCache (Memcached) ----------------
variable "cache_cluster_id" {
  type    = string
  default = "mc01"
}

variable "cache_node_type" {
  type    = string
  default = "cache.r7g.large"
}

variable "cache_num_nodes" {
  description = "Node based cluster - number of cache nodes"
  type        = number
  default     = 2
}

# ---------------- EC2 ----------------
variable "ec2_instance_type" {
  type    = string
  default = "t2.large"
}

variable "ec2_root_volume_size" {
  type    = number
  default = 20
}
