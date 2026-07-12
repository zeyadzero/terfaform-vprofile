# vprofile - Terraform on AWS

Terraform infrastructure for the vprofile stack on AWS: RDS (MySQL), 2x EC2 Tomcat
(RHEL 9) app servers, AmazonMQ (RabbitMQ), ElastiCache (Memcached), and an
Application Load Balancer.

## Architecture

```
Internet
   |
   v
[ALB: lb-tomcat]  (SG: lb, port 80)
   |
   +--> [EC2: tomcat1 - AZ us-east-1a]  --+
   +--> [EC2: tomcat2 - AZ us-east-1b]  --+   (SG: backend, port 8080)
                                          |
                    +---------------------+---------------------+
                    |                     |                     |
              [RDS: db01]          [ElastiCache: mc01]   [AmazonMQ: rmq01]
              MySQL 8.0             Memcached             RabbitMQ 3.13
              (SG: backend)         (SG: backend)          (SG: backend, private)
```

Everything runs in the **default VPC**, region **us-east-1 (N. Virginia)**.

## File structure

| File | Contents |
|---|---|
| `main.tf` | Provider + data sources (default VPC, subnets, RHEL 9 AMI) |
| `variables.tf` | Every configurable value (passwords, instance types, region...) |
| `security-groups.tf` | `backend` and `lb` security groups |
| `rds.tf` | RDS MySQL instance `db01` |
| `ec2.tf` | EC2 instances `tomcat1` (AZ a) and `tomcat2` (AZ b) |
| `amazonmq.tf` | AmazonMQ RabbitMQ broker `rmq01` |
| `elasticache.tf` | ElastiCache Memcached cluster `mc01` |
| `alb.tf` | Application Load Balancer + target group `vprofile` |
| `outputs.tf` | All endpoints, printed after `apply` |
| `scripts/tomcat-userdata.sh.tpl` | User-data template — real RDS/Memcached/RabbitMQ endpoints get injected automatically via `templatefile()` |

## Prerequisites

1. AWS credentials configured (`aws configure` or env vars) with sufficient permissions.
2. A key pair named `po2` already existing in `us-east-1` (EC2 > Key Pairs).
3. Terraform >= 1.5 and AWS provider ~> 5.0 (pinned in `main.tf`).

## Running it

```bash
terraform init
terraform plan
terraform apply
```

RDS and AmazonMQ take several minutes to provision. Once done:

```bash
terraform output
```

## Everything you can/should review before `apply`

### `variables.tf` — most likely things to change

| Variable | Default | Note |
|---|---|---|
| `aws_region` | `us-east-1` | |
| `key_name` | `po2` | must already exist in that region |
| `db_username` / `db_password` | `admin` / `admin123` | weak, fine for a lab, change for anything real |
| `db_instance_class` | `db.t4g.micro` | |
| `mq_username` / `mq_password` | `admin` / `admin12345678` | |
| `mq_instance_type` | `mq.t3.micro` | single-instance broker size — pick your actual size here |
| `cache_node_type` | `cache.r7g.large` | this is a large/expensive node type — double-check this is really what you want for a Memcached cache |
| `cache_num_nodes` | `2` | "node based cluster" as requested — adjust node count as needed |
| `ec2_instance_type` | `t2.large` | |

### `rds.tf`

- `engine_version = "8.0"` — was not specified in the original request; pin an exact
  minor version (e.g. `8.0.35`) if you need reproducibility.
- `skip_final_snapshot = true` — fine for testing, **remove/flip this for production**
  or you lose data on `destroy`.

### `amazonmq.tf` — important caveat

- AmazonMQ RabbitMQ **only exposes the TLS port (5671, `amqps://`)**, not plain 5672.
  The security group now allows both 5672 (as originally requested) and 5671 (the
  port actually used), but **the application itself must be configured to connect
  over TLS/AMQPS**, not plain AMQP. If the vprofile app's RabbitMQ client isn't
  set up for SSL, the connection will fail even though the network path is open.
  This is a code-level change in the app, not something Terraform can fix.

### `elasticache.tf`

- Memcached deployed as a "node based" cluster (`num_cache_nodes = 2`), matching
  what you described. If you actually wanted a single node, set `cache_num_nodes = 1`.

### `alb.tf`

- Subnets are picked dynamically (first 3 default subnets found in the account),
  so it no longer assumes `us-east-1c` exists.
- Health check path is `/login` on port 8080, as requested.

### `scripts/tomcat-userdata.sh.tpl` — what it automates vs. what it doesn't

The template automatically replaces these lines in `application.properties` with
real Terraform-generated values at boot time:

- `jdbc:mysql://db01:` → real RDS endpoint
- `jdbc.username` / `jdbc.password` → `var.db_username` / `var.db_password`
- `memcached.active.host` / `memcached.standBy.host` → real ElastiCache endpoint
- `rabbitmq.address` → real AmazonMQ hostname (extracted from the `amqps://` URL)

**Not automated — check `application.properties` in the cloned repo yourself for:**

- `rabbitmq.username` / `rabbitmq.password` — the broker is created with
  `var.mq_username` / `var.mq_password`, but nothing currently writes these into
  the properties file. Add a `sed` line for this if the file has those keys.
- `rabbitmq.port` — likely defaults to `5672` in the file; AmazonMQ needs `5671`
  with TLS (see caveat above).
- `memcached` port — defaults to `11211`, which matches what's opened in the
  security group, but confirm the properties file agrees.
- Any Spring datasource driver / dialect settings tied to a specific MySQL version.

## Manual steps after `apply`

### 1. Import the database backup

RDS comes up empty. Connect from an EC2 instance inside the same VPC (e.g. `tomcat1`):

```bash
ssh -i po2.pem ec2-user@<tomcat1_public_ip>
sudo dnf install -y mariadb105 git   # or whatever mysql client is available on RHEL 9
mysql -h <rds_endpoint> -u admin -p admin123
```

Then run your SQL import (e.g. `db_backup.sql`) against the right database.

> `<rds_endpoint>` is available via `terraform output rds_endpoint`.

### 2. Verify Tomcat is up

```bash
curl http://<tomcat1_public_ip>:8080/login
curl http://<tomcat2_public_ip>:8080/login
```

### 3. Verify the load balancer

```bash
curl http://$(terraform output -raw load_balancer_dns)/login
```

If the target group shows `unhealthy`, give the health check a bit of time, and
confirm port 8080 is reachable from the `backend` security group (already
configured in the code).

## Security notes

- SSH is open to `0.0.0.0/0` on the `backend` security group — fine for a lab,
  **not production-ready**. Restrict it to your own IP.
- Passwords (RDS, AmazonMQ) are plain defaults in `variables.tf`. For anything
  real, move them into a `terraform.tfvars` file (excluded from git) or AWS
  Secrets Manager / SSM Parameter Store.
- RDS is `publicly_accessible = true` and AmazonMQ is private, matching what
  you asked for.

## Possible future improvements (optional)

- **Route53 private hosted zone** instead of raw endpoints, if you want names
  like `db01.vprofile` to actually resolve.
- **HTTPS** on the ALB instead of HTTP only.
- **Auto Scaling Group** instead of fixed EC2 instances.
- **Remote state** (S3 + DynamoDB lock) instead of local state.
- Move secrets into `terraform.tfvars` and add it to `.gitignore`.

## Cleanup

```bash
terraform destroy
```
