output "jobs_queue_url" {
  description = "URL of the main SQS jobs queue"
  value       = aws_sqs_queue.queue.url
}

output "redis_endpoint" {
  description = "Redis primary endpoint address"
  value       = aws_elasticache_cluster.redis_cluster.cache_nodes[0].address
}