resource "aws_sqs_queue" "queue_dlq" {
  name = "slack-style-dlq"
}

resource "aws_sqs_queue" "queue" {
  name                       = "slack-style-queue"
  visibility_timeout_seconds = 60
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.queue_dlq.arn
    maxReceiveCount     = 3
  })
}