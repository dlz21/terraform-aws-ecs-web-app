variable "name" {
  type        = "string"
  description = "Name (unique identifier for app or service)"
}

variable "namespace" {
  type        = "string"
  description = "Namespace (e.g. `cp` or `cloudposse`)"
}

variable "delimiter" {
  type        = "string"
  description = "The delimiter to be used in labels."
  default     = "-"
}

variable "stage" {
  type        = "string"
  description = "Stage (e.g. `prod`, `dev`, `staging`)"
}

variable "attributes" {
  type        = "list"
  description = "List of attributes to add to label."
  default     = []
}

variable "tags" {
  type        = "map"
  description = "Map of key-value pairs to use for tags."
  default     = {}
}

variable "create" {
  description = "Whether to create all resources"
  default     = true
}

variable "create_sns_topic" {
  description = "Whether to create new SNS topic"
  default     = true
}

variable "create_with_kms_key" {
  description = "Whether to create resources with KMS encryption"
  default     = false
}

variable "kms_key_arn" {
  type        = "string"
  description = "ARN of the KMS key used for decrypting slack webhook url"
  default     = ""
}

variable "lambda_function_name" {
  type        = "string"
  description = "The name of the Lambda function to create"
  default     = ""
}

variable "sns_topic_name" {
  type        = "string"
  description = "Name of the SNS topic to subscribe to."
  default     = ""
}

variable "aws_region" {
  description = "The AWS region"
}

variable "http_listener_arn" {
  description = "Production (HTTP) listener ARN"
}

variable "ssl_listener_arn" {
  description = "SSL Listener ARN update its ingress rules."
}

variable "ecs_cluster_name" {
  type        = "string"
  description = "The ECS Cluster Name to use in ECS Code Pipeline Deployment step"
}

variable "available_target_groups" {
  type        = "list"
  default     = []
  description = "Available target groups for listener."
}

variable "codedeploy_app_name" {
  type        = "string"
  description = "Code Deploy Application Name Lambda needs to update w/status"
}

variable "codedeploy_group_name" {
  type        = "string"
  description = "Code Deploy Group Name Lambda needs to update w/status"
}
