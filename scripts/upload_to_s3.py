#!/usr/bin/env python3
"""Upload local pipeline files to an S3 raw prefix."""
from pathlib import Path
import os
import boto3
from dotenv import load_dotenv

load_dotenv()
root = Path(__file__).resolve().parents[1]
source_dir = root / "sample_data"
bucket = os.environ["S3_BUCKET"]
prefix = os.getenv("S3_RAW_PREFIX", "raw/").strip("/") + "/"
region = os.getenv("AWS_REGION", "us-east-1")

session = boto3.Session(profile_name=os.getenv("AWS_PROFILE") or None, region_name=region)
s3 = session.client("s3")
for path in sorted(source_dir.glob("*.csv")):
    key = f"{prefix}{path.name}"
    s3.upload_file(str(path), bucket, key)
    print(f"uploaded s3://{bucket}/{key}")
