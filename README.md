# vprofile - Terraform on AWS

بنية تحتية كاملة لتطبيق vprofile على AWS باستخدام Terraform: RDS (MySQL), 2x EC2 Tomcat
(RHEL 9), AmazonMQ (RabbitMQ), ElastiCache (Memcached), وApplication Load Balancer.

## البنية (Architecture)

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

كل المكونات على الـ **default VPC** في region **us-east-1 (Virginia)**.

## الملفات

| الملف | المحتوى |
|---|---|
| `main.tf` | provider + data sources (default VPC, subnets, RHEL 9 AMI) |
| `variables.tf` | كل القيم القابلة للتعديل (باسوردات، instance types...) |
| `security-groups.tf` | `backend` و `lb` |
| `rds.tf` | RDS MySQL `db01` |
| `ec2.tf` | EC2 `tomcat1` (AZ a) و `tomcat2` (AZ b) |
| `amazonmq.tf` | AmazonMQ RabbitMQ broker `rmq01` |
| `elasticache.tf` | ElastiCache Memcached `mc01` |
| `alb.tf` | Application Load Balancer + Target Group `vprofile` |
| `outputs.tf` | كل الـ endpoints بعد الـ apply |
| `scripts/tomcat-userdata.sh.tpl` | user-data template بيتحط فيه الـ endpoints الحقيقية أوتوماتيك (RDS/Memcached/RabbitMQ) عن طريق `templatefile()` |

## قبل ما تشغل

1. **AWS credentials** مظبوطة (`aws configure` أو env vars) بصلاحيات كافية.
2. **Key pair** اسمه `po2` موجود فعلاً في region `us-east-1` (تحقق منه في AWS Console > EC2 > Key Pairs).
3. **Terraform** >= 1.5 و **AWS provider** ~> 5.0 (متعرّفين في `main.tf`).

## التشغيل

```bash
terraform init
terraform plan
terraform apply
```

هياخد وقت شوية بسبب AmazonMQ و RDS (دقايق مش ثواني). بعد ما يخلص هتلاقي كل الـ endpoints
في الـ output:

```bash
terraform output
```

## خطوات يدوية بعد الـ apply

### 1. استيراد الـ backup على قاعدة البيانات

الـ RDS بيتعمل فاضي. علشان تعمل import للبيانات، اتصل من أي EC2 instance عندك وصلاحية
جوه نفس الـ VPC (مثلاً `tomcat1`) على الـ RDS مباشرة:

```bash
ssh -i po2.pem ec2-user@<tomcat1_public_ip>
sudo dnf install -y mariadb105 git   # أو mysql client المتاح على RHEL 9
mysql -h <rds_endpoint> -u admin -p admin123
```

بعد الاتصال، شغّل الـ SQL script بتاعك لعمل import للـ backup (زي `db_backup.sql`) داخل
قاعدة البيانات المناسبة.

> `<rds_endpoint>` تلاقيه في `terraform output rds_endpoint`.

### 2. التأكد إن Tomcat شغال

```bash
curl http://<tomcat1_public_ip>:8080/login
curl http://<tomcat2_public_ip>:8080/login
```

### 3. التأكد من الـ Load Balancer

```bash
curl http://$(terraform output -raw load_balancer_dns)/login
```

لو الـ Target Group لسه `unhealthy`، استنى شوية (health check بياخد وقت) أو تأكد إن
الـ security group `backend` فاتح بورت 8080 من جوه الـ VPC (متظبط بالفعل في الكود).

## ملاحظات أمان مهمة

- SSH مفتوح `0.0.0.0/0` على الـ security group `backend` — ده مقبول للتجربة بس **مش
  production-ready**. الأفضل تحصره على الـ IP بتاعك فقط.
- الباسوردات (RDS, AmazonMQ) متحطة كـ defaults في `variables.tf` بشكل واضح. للإنتاج
  الفعلي استخدم `terraform.tfvars` (مش على git) أو AWS Secrets Manager / SSM Parameter Store.
- RDS و AmazonMQ عندهم `publicly_accessible` / `access type` مضبوطين زي ما طلبت
  (RDS public / MQ private).

## نقاط ممكن تتحسّن مستقبلًا (اختياري)

- **Route53 private hosted zone** بدل استخدام الـ endpoints الخام مباشرة (لو حبيت
  أسامي زي `db01.vprofile` تشتغل فعلاً).
- **HTTPS** على الـ ALB بدل HTTP فقط.
- **Auto Scaling Group** بدل EC2 instances ثابتة.
- **Remote state** (S3 + DynamoDB lock) بدل local state.
- فصل الباسوردات في `terraform.tfvars` وإضافته لـ `.gitignore`.

## تنظيف الموارد

```bash
terraform destroy
```
