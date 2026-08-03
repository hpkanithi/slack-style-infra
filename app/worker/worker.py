import json
import os
import time

import boto3
import redis

QUEUE_URL = os.environ["QUEUE_URL"]
REDIS_ENDPOINT = os.environ["REDIS_ENDPOINT"]
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))

sqs = boto3.client("sqs", region_name=os.environ.get("AWS_REGION", "us-east-2"))
r = redis.Redis(host=REDIS_ENDPOINT, port=REDIS_PORT, decode_responses=True)


def process(payload: dict) -> None:
    # Simulated "unfurl" delay — stands in for Slack's link-unfurl / notification work
    time.sleep(2)

    # Poison-message hook for the T4.4 DLQ drill:
    # POST {"text": "poison"} and this raises every time, so SQS redelivers
    # it up to maxReceiveCount (3) before routing it to the DLQ.
    if payload.get("text") == "poison":
        raise ValueError(f"simulated processing failure for message {payload['id']}")

    result = {
        "id": payload["id"],
        "text": payload["text"],
        "processed": True,
    }
    r.set(f"message:{payload['id']}", json.dumps(result))
    print(f"processed {payload['id']}", flush=True)


def main():
    print("worker started, polling SQS...", flush=True)
    while True:
        response = sqs.receive_message(
            QueueUrl=QUEUE_URL,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=10,  # long polling — avoid tight-loop API calls
        )
        messages = response.get("Messages", [])
        if not messages:
            continue

        msg = messages[0]
        payload = json.loads(msg["Body"])

        try:
            process(payload)
            # Only delete on success — a crash before this line means the
            # message becomes visible again after the 60s visibility timeout
            # and gets retried, up to maxReceiveCount.
            sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=msg["ReceiptHandle"])
        except Exception as e:
            print(f"failed to process {payload.get('id')}: {e}", flush=True)
            # deliberately no delete — let SQS's redrive policy handle it


if __name__ == "__main__":
    main()