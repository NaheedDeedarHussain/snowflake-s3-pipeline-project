# S3 → Snowpipe → Snowflake Stream/Task Pipeline

Yeh project image mein dikhaye gaye architecture ka runnable demo hai:

```text
EC2/Docker
  ├── Jupyter Notebook
  └── Apache NiFi
          ↓
       Amazon S3
          ↓
       Snowpipe
          ↓
  Snowflake STAGING_EVENTS
          ↓
  Snowflake Stream
          ↓
  Snowflake Task
      ├── TABLE_1_CUSTOMERS
      └── TABLE_2_ORDERS
```

Is repository mein AWS S3 bucket ke liye Terraform template, local Docker services, sample CSV files, S3 upload script aur Snowflake SQL shamil hain. Real AWS aur Snowflake credentials jaan-boojh kar repository mein nahi rakhe gaye.

## 1. Zaroori cheezen

Aap ke system par yeh tools install hone chahiye:

- Docker aur Docker Compose
- AWS CLI
- Terraform
- SnowSQL **ya** Snowflake Snowsight
- Python 3.11 ya us se naya

Aap ke paas AWS account mein S3 create karne ki permission aur Snowflake mein database, warehouse, stage, pipe, stream aur task create karne ki permission honi chahiye. Snowpipe auto-ingest ke liye baad mein S3 event notification aur Snowflake notification integration bhi configure karni hoti hai. Demo ko pehle manual `ALTER PIPE ... REFRESH` ke saath test kiya ja sakta hai.

## 2. Project download/open karein

```bash
cd /home/ubuntu/snowflake-s3-nifi-pipeline
```

Agar aap ne project kisi doosri machine par copy kiya hai to is path ko apne actual project path se replace karein.

## 3. Python environment banayein

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

Har nayi terminal mein kaam shuru karne se pehle yeh command dobara run karein:

```bash
cd /home/ubuntu/snowflake-s3-nifi-pipeline
source .venv/bin/activate
```

## 4. AWS credentials configure karein

Agar AWS CLI pehli dafa use ho rahi hai:

```bash
aws configure
```

Prompts par AWS Access Key, Secret Key, default region aur output format dein. Region ka example:

```text
us-east-1
json
```

Credentials verify karein:

```bash
aws sts get-caller-identity
```

Agar named profile use karna ho:

```bash
aws configure --profile pipeline
export AWS_PROFILE=pipeline
```

## 5. S3 bucket create karein

Pehle Terraform variables copy karein:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

`terraform/terraform.tfvars` mein bucket ka **globally unique** naam likhein. Misal:

```hcl
aws_region  = "us-east-1"
bucket_name = "my-company-pipeline-20260924"
```

Ab Terraform run karein:

```bash
cd terraform
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
cd ..
```

`terraform apply` par `yes` likh kar confirm karein. Bucket verify karein:

```bash
aws s3 ls
```

Terraform resources delete karne ke liye, sirf demo khatam hone par:

```bash
cd terraform
terraform destroy
cd ..
```

## 6. Environment file banayein

```bash
cp .env.example .env
```

`.env` mein kam az kam yeh values set karein:

```dotenv
AWS_REGION=us-east-1
S3_BUCKET=terraform-bucket-ka-output-name
AWS_PROFILE=default
NIFI_PASSWORD=ApnaStrongPassword123!
JUPYTER_TOKEN=ApnaJupyterToken
```

`S3_BUCKET` ka value yeh command de sakti hai:

```bash
cd terraform
terraform output -raw bucket_name
cd ..
```

`.env` ko Git mein commit na karein. Is project mein `.gitignore` is liye bhi diya gaya hai.

## 7. Jupyter aur NiFi start karein

```bash
docker compose --env-file .env up -d
```

Containers ka status check karein:

```bash
docker compose ps
```

Logs dekhne ke liye:

```bash
docker compose logs -f nifi
```

Jupyter browser mein kholein:

```text
http://localhost:8888/lab?token=ApnaJupyterToken
```

NiFi HTTPS browser mein kholein:

```text
https://localhost:8443/nifi
```

Login ke liye `.env` ka `NIFI_USERNAME` aur `NIFI_PASSWORD` use karein. Local self-signed certificate warning ko browser mein accept karna hoga.

## 8. NiFi flow configure karein

NiFi UI mein ek process group bana kar yeh processors add karein:

1. **GetFile**: Directory `/opt/nifi/input` set karein. `Keep Source File` ko `false` rakhein.
2. **PutS3Object**: AWS credentials, region, bucket aur object key prefix `raw/` configure karein.
3. GetFile ki `success` relationship ko PutS3Object se connect karein.
4. PutS3Object ki `success` relationship ko auto-terminate karein. `failure` ko retry ya failure queue mein bhejein.
5. Dono processors ko start karein.

NiFi ka intended flow yeh hai:

```text
/opt/nifi/input/*.csv → GetFile → PutS3Object → s3://BUCKET/raw/*.csv
```

Agar aap NiFi UI ke baghair sample files upload karke pehle Snowpipe test karna chahte hain, to next section ka Python command use karein. Is tarah NiFi optional smoke-test component rahega, jab ke production flow NiFi se S3 tak chalega.

## 9. Snowflake SQL run karne se pehle placeholders replace karein

In files mein yeh placeholders replace karne hain:

- `<AWS_ACCOUNT_ID>`
- `<SNOWFLAKE_S3_ROLE>`
- `<BUCKET_NAME>`

`<BUCKET_NAME>` ko apne Terraform bucket name se replace karein. Example:

```bash
BUCKET=$(cd terraform && terraform output -raw bucket_name)
sed -i "s/<BUCKET_NAME>/$BUCKET/g" snowflake/01_setup.sql snowflake/02_stage_pipe.sql
```

`01_setup.sql` mein AWS IAM role ARN ko apne actual Snowflake access role ke ARN se replace karein. AWS role trust policy mein Snowflake ki IAM user ARN aur external ID add karna hota hai. Snowflake aap ko required values is command se dega:

```sql
DESC INTEGRATION PIPELINE_S3_INTEGRATION;
```

> Pehli run mein `01_setup.sql` ko placeholder role ke baghair complete karne ke liye integration creation ko temporarily edit karke apna actual role ARN dein. Snowflake storage integration ko real AWS IAM role ke baghair use nahi kiya ja sakta.

## 10. Snowflake SQL execution order

Snowsight ke SQL Worksheet mein files **isi tarteeb** se run karein:

### 10.1 Database, schema, warehouse aur integration

```bash
snowsql -f snowflake/01_setup.sql
```

Ya `snowflake/01_setup.sql` ka complete content Snowsight mein paste karke run karein.

Snowflake integration ka status check karein:

```sql
DESC INTEGRATION PIPELINE_S3_INTEGRATION;
```

### 10. Stage aur Snowpipe

```bash
snowsql -f snowflake/02_stage_pipe.sql
```

Check:

```sql
SHOW PIPES IN SCHEMA PIPELINE_DB.RAW;
DESC PIPE PIPELINE_DB.RAW.PIPELINE_PIPE;
```

### 10. Stream aur Task

```bash
snowsql -f snowflake/03_stream_tasks.sql
```

Task status check karein:

```sql
SHOW TASKS IN SCHEMA PIPELINE_DB.RAW;
```

## 11. S3 mein sample data upload karein

### Option A: NiFi se upload

`sample_data` directory mein files pehle se maujood hain. NiFi ke GetFile processor ka input `/opt/nifi/input` hai, jo host ke `sample_data` folder se mapped hai. NiFi processors start karne ke baad S3 mein check karein:

```bash
aws s3 ls "s3://$S3_BUCKET/raw/"
```

### Option B: Python se direct upload

`.env` load karke command run karein:

```bash
set -a
source .env
set +a
python scripts/upload_to_s3.py
```

S3 files verify karein:

```bash
aws s3 ls "s3://$S3_BUCKET/raw/"
```

## 12. Pehli testing ke liye Snowpipe refresh karein

Agar S3 event notification abhi configure nahi hui, to Snowflake worksheet mein yeh run karein:

```sql
USE DATABASE PIPELINE_DB;
USE SCHEMA RAW;
ALTER PIPE PIPELINE_PIPE REFRESH;
```

Pipe history check karein:

```sql
SELECT *
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'STAGING_EVENTS',
  START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP())
));
```

Staging data check karein:

```sql
SELECT * FROM STAGING_EVENTS ORDER BY loaded_at DESC;
```

## 13. Stream aur Task ka result check karein

Task schedule ke mutabiq maximum 5 minutes mein run hoga. Manual task run karna ho to:

```sql
EXECUTE TASK ROUTE_STAGING_TASK;
```

Final tables check karein:

```sql
SELECT * FROM TABLE_1_CUSTOMERS ORDER BY customer_id;
SELECT * FROM TABLE_2_ORDERS ORDER BY order_id;
SELECT * FROM PIPELINE_ERRORS;
```

Expected result mein customers `TABLE_1_CUSTOMERS` aur orders `TABLE_2_ORDERS` mein nazar aayenge.

Task history dekhne ke liye:

```sql
SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
  TASK_NAME => 'ROUTE_STAGING_TASK',
  SCHEDULED_TIME_RANGE_START => DATEADD('hour', -2, CURRENT_TIMESTAMP())
))
ORDER BY SCHEDULED_TIME DESC;
```

## 14. Auto-ingest ko production mein enable karna

Manual refresh testing ke baad production-like auto-ingest ke liye:

1. Snowflake integration mein `STORAGE_ALLOWED_LOCATIONS` sahi bucket/prefix par set karein.
2. AWS mein Snowflake ke diye hue IAM policy statements apply karein.
3. S3 bucket par `s3:ObjectCreated:*` event notification configure karein.
4. Notification ko Snowflake pipe ke `notification_channel` / SQS channel ke saath connect karein.
5. Ek nayi file `raw/` prefix mein upload karke `COPY_HISTORY` check karein.

Pipe ka notification channel yahan milega:

```sql
DESC PIPE PIPELINE_DB.RAW.PIPELINE_PIPE;
```

AWS IAM aur notification integration account-specific hoti hai. Is liye un values ko is demo mein hard-code nahi kiya gaya.

## 15. Local services band karna

```bash
docker compose down
```

Containers ke saath named volumes bhi delete karne ke liye, jo NiFi state ko delete karega:

```bash
docker compose down -v
```

## 16. Troubleshooting

**`AccessDenied` S3 error:** AWS profile, bucket name aur IAM permissions check karein.

**Snowflake stage access error:** Storage integration ka ARN, trust policy aur `STORAGE_ALLOWED_LOCATIONS` verify karein. `DESC INTEGRATION PIPELINE_S3_INTEGRATION` se Snowflake ki required IAM values dobara dekhein.

**Pipe mein files load nahi ho rahi:** Pehle `ALTER PIPE PIPELINE_PIPE REFRESH;` run karein. Phir `COPY_HISTORY` aur `DESC PIPE` check karein. File path `raw/` ke andar hona chahiye aur extension `.csv` honi chahiye.

**Stream empty hai:** Stream create hone ke baad jo rows insert hui hain sirf woh capture hoti hain. Stream create karne se pehle loaded data ko dobara ingest karna padega, ya test ke liye nayi files upload karein.

**Task run nahi ho raha:** `SHOW TASKS` se state dekhein. Task suspended ho to:

```sql
ALTER TASK ROUTE_STAGING_TASK RESUME;
EXECUTE TASK ROUTE_STAGING_TASK;
```

**NiFi login nahi ho raha:** `.env` ki password value check karein. Password kam az kam 12 characters ki rakhein aur fresh container initialize karne ke liye zaroorat par:

```bash
docker compose down -v
docker compose --env-file .env up -d
```

## 17. Security notes

`.env`, AWS keys aur Snowflake passwords ko Git mein commit na karein. Production mein AWS access keys ki jagah IAM roles use karein. Snowflake ke liye key-pair authentication aur least-privilege roles behtar hain. Demo bucket ko public na karein. Production mein S3 encryption, lifecycle policy, audit logging aur separate dev/stage/prod accounts configure karein.

## 18. Folder structure

```text
.
├── .env.example
├── .gitignore
├── docker-compose.yml
├── requirements.txt
├── README.md
├── sample_data/
│   ├── customers.csv
│   └── orders.csv
├── scripts/
│   └── upload_to_s3.py
├── snowflake/
│   ├── 01_setup.sql
│   ├── 02_stage_pipe.sql
│   └── 03_stream_tasks.sql
└── terraform/
    ├── main.tf
    └── terraform.tfvars.example
```

## References

[1]: https://docs.snowflake.com/en/user-guide/data-load-snowpipe-intro "Snowflake Snowpipe overview"
[2]: https://docs.snowflake.com/en/user-guide/streams-intro "Snowflake streams"
[3]: https://docs.snowflake.com/en/user-guide/tasks-intro "Snowflake tasks"
[4]: https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html "Amazon S3 user guide"
[5]: https://nifi.apache.org/documentation/ "Apache NiFi documentation"
"# snowflake-s3-pipeline-project" 
"# snowflake-s3-pipeline-project" 
