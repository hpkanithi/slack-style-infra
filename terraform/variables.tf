variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-2"
}
variable "alert_email" {
  description = "alert email address"
  type        = string
}