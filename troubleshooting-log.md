# vprofile on AWS — Troubleshooting Log

سجل كامل بكل الأخطاء اللي ظهرت أثناء نشر مشروع vprofile بالـ Terraform، وترتيبها الزمني، وسبب كل واحدة، والحل اللي اتطبق.

---

## 1) `Error: no matching EC2 Subnet found`

**وقتها حصلت:** `terraform plan`، أول مرة.

**الرسالة:**
```
Error: no matching EC2 Subnet found
  with data.aws_subnet.az_a
  with data.aws_subnet.az_b
```

**السبب:**
الكود كان بيفترض إن الـ default VPC فيه default subnet في كل Availability Zone (`us-east-1a`, `us-east-1b`, `us-east-1c`). لكن الحساب الفعلي كان عنده **default subnet واحد بس** في الـ VPC كله.

**الحل:**
1. عملنا default subnets في الـ AZs الناقصة عن طريق AWS CLI مباشرة:
   ```bash
   aws ec2 create-default-subnet --availability-zone us-east-1b
   aws ec2 create-default-subnet --availability-zone us-east-1c
   ```
2. غيّرنا الكود عشان يبقى **ديناميكي** بدل ما يفترض AZs معينة — بيختار أول subnet وثاني subnet من أي subnets موجودة فعلاً في الحساب:
   ```hcl
   locals {
     default_subnet_ids = data.aws_subnets.default.ids
     tomcat1_subnet_id   = local.default_subnet_ids[0]
     tomcat2_subnet_id   = length(local.default_subnet_ids) > 1 ? local.default_subnet_ids[1] : local.default_subnet_ids[0]
     alb_subnet_ids       = slice(local.default_subnet_ids, 0, min(3, length(local.default_subnet_ids)))
   }
   ```

---

## 2) `AccessDeniedException: mq:CreateBroker`

**وقتها حصلت:** `terraform apply`، وقت إنشاء الـ AmazonMQ broker.

**الرسالة:**
```
User: arn:aws:iam::...:user/devops is not authorized to perform: mq:CreateBroker
```

**السبب:**
اليوزر `devops` بتاع IAM مكنش معاه صلاحيات AmazonMQ خالص.

**الحل:**
إضافة الـ policy المدارة `AmazonMQFullAccess` لليوزر:
```bash
aws iam attach-user-policy \
  --user-name devops \
  --policy-arn arn:aws:iam::aws:policy/AmazonMQFullAccess
```
> لاحظ: مفيش داعي لعمل `destroy`، Terraform بيكمل من حيث وقف بعد إصلاح الصلاحيات.

---

## 3) `BadRequestException: autoMinorVersionUpgrade must be true`

**وقتها حصلت:** `terraform apply`، بعد حل مشكلة الـ IAM.

**الرسالة:**
```
Brokers on [RabbitMQ] version [3.13] must have [autoMinorVersionUpgrade] set to [true]
```

**السبب:**
AWS بتفرض إن أي broker RabbitMQ بنسخة 3.13 لازم يكون معاه auto minor version upgrade مفعّل — القيمة الافتراضية في الكود كانت `false` (ضمنيًا).

**الحل:**
إضافة السطر ده في `amazonmq.tf`:
```hcl
resource "aws_mq_broker" "rmq01" {
  ...
  auto_minor_version_upgrade = true
}
```

---

## 4) `BadRequestException: host instance type [mq.t3.micro] not supported`

**وقتها حصلت:** `terraform apply`، بعد حل مشكلة الـ auto minor version upgrade.

**الرسالة:**
```
Broker engine type [RabbitMQ] does not support host instance type [mq.t3.micro]
```

**السبب:**
AWS بطّلت دعم `mq.t3.micro` كنوع instance لبروكرز RabbitMQ الجديدة. الأنواع المتاحة دلوقتي بس `m7g` و`m5`.

**الحل:**
تغيير الـ default في `variables.tf`:
```hcl
variable "mq_instance_type" {
  default = "mq.m7g.medium"
}
```

---

## 5) `InvalidKeyPair.NotFound: The key pair 'po2' does not exist`

**وقتها حصلت:** `terraform apply`، وقت إنشاء الـ EC2 instances.

**السبب:**
الاسم المفترض للـ key pair (`po2`) مكنش هو الاسم الفعلي المسجل في الحساب. بعد الفحص، الاسم الحقيقي كان `po1`.

**الحل:**
```hcl
variable "key_name" {
  default = "po1"
}
```
> نصيحة عامة: قبل أي apply، اتأكد دايمًا من الأسماء الفعلية بأمر:
> ```bash
> aws ec2 describe-key-pairs --region us-east-1 --query "KeyPairs[].KeyName"
> ```

---

## 6) SSH: `Permission denied (publickey...)` رغم استخدام المفتاح الصح

**وقتها حصلت:** أول محاولة SSH على الـ EC2 instance.

**الرسالة:**
```
WARNING: UNPROTECTED PRIVATE KEY FILE!
Permissions 0664 for 'po1.pem' are too open.
Load key "po1.pem": bad permissions
```

**السبب:**
استخدام `chmod +600` أو `chmod +400` (بعلامة `+`) بيضيف صلاحيات فوق الموجود، مش بيستبدلها بالكامل — فضلت صلاحيات القراءة للمجموعة/الغرباء موجودة (0664).

**الحل:**
استخدام `chmod` **من غير علامة `+`**، عشان يمسح كل الصلاحيات الزيادة:
```bash
chmod 400 po1.pem
```

---

## 7) `tomcat1_public_ip` فاضي في مخرجات Terraform

**وقتها حصلت:** بعد أول `apply` ناجح، `terraform output`.

**السبب:**
الـ subnet الأصلي (اللي كان موجود قبل ما نعمل default subnets إضافية) لم يكن مضمونًا أن `map_public_ip_on_launch` مفعّل بشكل ثابت عليه.

**الحل:**
فرض تخصيص public IP صراحة على مستوى الـ instance نفسه، بدل الاعتماد على إعداد الـ subnet:
```hcl
resource "aws_instance" "tomcat1" {
  ...
  associate_public_ip_address = true
}
```
> ملحوظة: إضافة الخاصية دي على instance موجود بالفعل بتسبب **replace** إجباري (الـ instance بيتعمله destroy/create من جديد)، وده طبيعي ومتوقع.

---

## 8) `mysql -h <host> -u admin -p admin123` → `ERROR 1049: Unknown database 'admin123'`

**وقتها حصلت:** أول محاولة اتصال بالـ RDS من جوه EC2.

**السبب:**
مسافة بعد `-p` خلت الـ shell يفسّر الكلمة اللي بعدها (`admin123`) على إنها **اسم قاعدة بيانات** إضافي في نهاية الأمر، مش الباسورد.

**الحل:**
```bash
# طريقة 1: من غير مسافة بعد -p
mysql -h <endpoint> -u admin -padmin123

# طريقة 2 (أفضل، الباسورد ميظهرش في history)
mysql -h <endpoint> -u admin -p
# ثم يُكتب الباسورد عند الطلب
```

---

## 9) استيراد الـ backup فشل: `ERROR 1049: Unknown database 'accounts'`

**وقتها حصلت:** أثناء تنفيذ `mysql -u root -padmin123 accounts < db_backup.sql`.

**السبب:**
الأمر ماكانش فيه `-h <rds_endpoint>` خالص — يعني كان بيحاول يتصل بسيرفر MySQL **محلي** على نفس الـ EC2 (مش موجود)، مش بالـ RDS.

**الحل:**
```bash
mysql -h db01.ckjscwguuz5e.us-east-1.rds.amazonaws.com -u admin -padmin123 accounts < src/main/resources/db_backup.sql
```

---

## 10) `tomcat.service: Failed` — `ExecStart... code=exited, status=203/EXEC`

**وقتها حصلت:** بعد الـ `apply` اللي عمل replace للـ instances (بسبب فيكس الـ public IP).

**السبب:**
مرحلة تجهيز Tomcat في الـ user-data script فشلت من الأساس — `/usr/local/tomcat/webapps` مش موجود أصلاً، يعني الـ `wget`/`tar` لفك ضغط Tomcat فشلوا (أو Java مكنش موجود وقت التنفيذ).

**التشخيص:**
```bash
sudo tail -100 /var/log/cloud-init-output.log
```

**الحالة:** ده أعمق سبب محتمل هو إن رابط التحميل القديم (`archive.apache.org/dist/tomcat/tomcat-9/v9.0.75/...`) بقى غير متاح، أو تثبيت `java-11-openjdk` فشل بسبب اختلاف في مستودعات RHEL 9. **(محتاج تأكيد نهائي من محتوى اللوج).**

---

## 11) `curl -I http://localhost:8080/login` → `HTTP/1.1 405`

**مش خطأ حقيقي.** `curl -I` بيبعت HEAD request، والـ endpoint `/login` بيقبل GET بس (`Allow: GET` واضحة في الـ header). الحل: استخدم `curl` من غير `-I`.

---

## 12) `SocketTimeoutException: connect timed out` (RabbitMQ) في `catalina.out`

**السبب:**
AmazonMQ RabbitMQ بيشتغل بس على **TLS (بورت 5671، `amqps://`)**. الـ `application.properties` بتاعة التطبيق كانت متظبطة على البورت العادي 5672 من غير SSL، فكل محاولة اتصال بتعمل timeout.

**الحل:**
تعديل `application.properties`:
```properties
rabbitmq.address=<rabbitmq-hostname-only>
rabbitmq.port=5671
rabbitmq.useSSL=true
rabbitmq.username=admin
rabbitmq.password=admin12345678
```
> هام: لازم الاسم بس (`b-xxxx.mq.us-east-1.on.aws`) من غير `amqps://` والبورت، لأن الكود بياخدهم من `rabbitmq.port` و`rabbitmq.useSSL` لوحدهم.

---

## 13) `HTTP Status 403 – Forbidden`: `Expected CSRF token not found`

**السبب:**
عندنا **2 Tomcat instances** خلف Load Balancer، وكل واحد بيخزن الـ session (وبالتالي الـ CSRF token) في الـ memory بتاعه لوحده. لو صفحة `/login` (GET) راحت لـ `tomcat1`، والـ submit (POST) راح لـ `tomcat2`، الـ CSRF token اللي اتعمل على الأول مش موجود على التاني، فالطلب بيترفض.

**الحل:**
تفعيل **Sticky Sessions** على الـ Target Group عشان كل زائر يفضل يروح لنفس الـ instance طول الـ session:
```hcl
resource "aws_lb_target_group" "vprofile" {
  ...
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }
}
```
**حل أعمق (لسه معلّق):** تفعيل shared session storage عبر Memcached (`memcached-session-manager` في Tomcat) عشان الـ sessions تبقى مشتركة فعليًا ومش نحتاج stickiness أصلاً.

---

## 14) `Your username and password is invalid.`

**السبب المحتمل الأول:** الباسوردات في الجدول متشفرة بـ BCrypt (`$2a$11$...`)، ومفيش طريقة تعرف بيها القيمة الأصلية من الهاش.

**الحل المتبع:**
توليد هاش BCrypt جديد لباسورد معروف (`admin123`) وتحديث اليوزر مباشرة في القاعدة:
```sql
UPDATE user
SET password = '$2a$11$KdtdkNcUuyDiVLUFk2P.FOaFva6lDgzadE7zDR.sdSqSpsYCUoaNG'
WHERE username = 'admin_vp';
```
(الهاش ده بيمثل الباسورد `admin123`)

**لو المشكلة استمرت بعد التحديث، الاحتمالات:**
- **Memcached caching** لسه شايل نسخة قديمة من بيانات اليوزر (الكاش ماتفرغش لما القاعدة اتغيرت). الحل: تفريغ الكاش وإعادة تشغيل Tomcat:
  ```bash
  echo -e "flush_all\r\nquit\r\n" | nc mc01.e691bc.cfg.use1.cache.amazonaws.com 11211
  sudo systemctl restart tomcat   # على كل الـ instances
  ```
- **لخبطة بين نسختين مختلفتين من المشروع** (أهم سبب مكتشف): فيه فرق بين:
  - الكود اللي فعليًا شغال على Tomcat (`/home/vagrant/vprofile`, من `zeyadzero/vprofile`) — ده اللي فيه الـ endpoints الحقيقية اتحطت أوتوماتيك بواسطة الـ user-data script.
  - الكود اللي اتعمله clone يدوي (`~/vprofile-project`, من `hkhcoder/vprofile-project`) لغرض استيراد الـ backup بس — ده مشروع مختلف بالكامل، وتعديل `application.properties` بتاعه **مالوش أي تأثير** على التطبيق الشغال فعليًا.

  **الحل:** التأكد دايمًا من تعديل الملف الصحيح:
  ```bash
  cat /home/vagrant/vprofile/src/main/resources/application.properties
  ```
  وتحديث القيم فيه بالـ endpoints الحقيقية (مش في الريبو التاني).

---

## 15) `HTTP Status 500`: `NoRouteToHostException` أثناء Registration

**السبب:**
فشل شبكة/اتصال **لحظي** بين الـ EC2 والـ RDS وقت محاولة إنشاء حساب جديد (مش خطأ دائم في الكود أو الباسورد).

**التشخيص:**
```bash
# اختبار الاتصال المباشر
mysql -h db01.ckjscwguuz5e.us-east-1.rds.amazonaws.com -u admin -padmin123 accounts -e "SELECT 1;"

# حالة الـ RDS نفسه
aws rds describe-db-instances --db-instance-identifier db01 --query "DBInstances[0].DBInstanceStatus"
```
لو الحالة رجعت `available` والاتصال شغال، يبقى كانت مشكلة عابرة (زي RDS في نص عملية صيانة لحظتها).

---

## خلاصة الدروس المستفادة (Lessons Learned)

1. **افترض أقل ما يمكن عن بيئة الحساب** — عدد الـ AZs، أسماء الـ key pairs، وحتى الـ instance types المدعومة كلها بتختلف من حساب لحساب ومن وقت لوقت (AWS بتغيّر قوائم الدعم باستمرار).
2. **افصل بوضوح بين المشروع الأوتوماتيكي (user-data) والمشروع اليدوي** — استخدام تاني ريبو لغرض استيراد الـ backup بس سبب لخبطة كبيرة، لأن أي تعديل في الريبو التاني ماكانش بيأثر على التطبيق الفعلي.
3. **الـ CSRF/Session errors في multi-instance apps** غالبًا سببها غياب shared session state، مش خطأ في الكود نفسه.
4. **RabbitMQ على AmazonMQ = TLS إجباري (5671)**، الإعداد الافتراضي في أغلب نسخ vprofile على الإنترنت (5672 بلا SSL) مش هيشتغل من غير تعديل.
5. **صلاحيات ملفات SSH لازم `chmod 400` بالظبط**، مش `chmod +400`.
