import json
import urllib.parse
import boto3

s3 = boto3.client("s3")


def lambda_handler(event, context):
    """Triggered when a new log archive (.tar.gz) is uploaded to the S3 bucket."""
    print("Received event: " + json.dumps(event, indent=2))

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"], encoding="utf-8")
        size = record["s3"]["object"].get("size", 0)

        print(f"Log Archive Verified: s3://{bucket}/{key}")
        print(f"Archive Size: {size} bytes")

        # In production: extract logs, parse 500 error counts, or trigger alert
        print("Successfully processed S3 log backup event.")

    return {
        "statusCode": 200,
        "body": json.dumps("Log archive processed successfully")
    }
