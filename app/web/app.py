import json
import os
import uuid

import boto3
import redis
from flask import Flask, jsonify, request

app = Flask(__name__)

QUEUE_URL = os.environ["QUEUE_URL"]
REDIS_ENDPOINT = os.environ["REDIS_ENDPOINT"]
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))

sqs = boto3.client("sqs", region_name=os.environ.get("AWS_REGION", "us-east-2"))
r = redis.Redis(host=REDIS_ENDPOINT, port=REDIS_PORT, decode_responses=True)


@app.route("/health")
def health():
    # ALB target group hits this. Keep it cheap — no SQS/Redis calls here,
    # or a slow dependency can take healthy tasks out of rotation.
    return "ok", 200


@app.route("/message", methods=["POST"])
def post_message():
    body = request.get_json(silent=True) or {}
    text = body.get("text", "")

    message_id = str(uuid.uuid4())
    payload = {"id": message_id, "text": text}

    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(payload),
    )

    # 202: accepted, not yet processed — this is the whole point of the pattern
    return jsonify({"id": message_id, "status": "queued"}), 202


@app.route("/messages", methods=["GET"])
def get_messages():
    keys = r.keys("message:*")
    messages = [json.loads(r.get(k)) for k in keys]
    return jsonify(messages), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000)