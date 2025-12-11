variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"  # Mumbai
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "jambonz"
}

variable "vpc_id" {
  description = "VPC ID where ALB will be created"
  type        = string
}

variable "telephony_certificate_arn" {
  description = "ARN of SSL certificate for telephony.graine.ai (API server). Can use wildcard *.graine.ai for both domains."
  type        = string
}

variable "webapp_certificate_arn" {
  description = "ARN of SSL certificate for sipwebapp.graine.ai (webapp). Can use same certificate as telephony if wildcard."
  type        = string
}


variable "enable_deletion_protection" {
  description = "Enable deletion protection on ALB"
  type        = bool
  default     = false
}

variable "instance_ids" {
  description = "List of EC2 instance IDs to register with target groups"
  type        = list(string)
  default     = []
}

