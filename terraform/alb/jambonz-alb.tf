# Application Load Balancer for Jambonz

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"  # Mumbai
}

# Data sources
data "aws_vpc" "main" {
  id = var.vpc_id
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  
  filter {
    name   = "tag:Type"
    values = ["public"]
  }
}

# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Security group for Jambonz ALB"
  vpc_id      = var.vpc_id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  # HTTPS (port 443 for both telephony.graine.ai and sipwebapp.graine.ai)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS (telephony.graine.ai and sipwebapp.graine.ai)"
  }

  # SIP UDP
  ingress {
    from_port   = 5060
    to_port     = 5060
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SIP UDP"
  }

  # SIP TCP
  ingress {
    from_port   = 5060
    to_port     = 5060
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SIP TCP"
  }

  # RTP (adjust range as needed)
  ingress {
    from_port   = 10000
    to_port     = 60000
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "RTP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "jambonz" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids

  enable_deletion_protection = var.enable_deletion_protection
  enable_http2               = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

# Target Group for API Server (port 3000)
resource "aws_lb_target_group" "api_server" {
  name     = "${var.name_prefix}-api-server"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/api/v1"
    protocol            = "HTTP"
    matcher             = "200,301,302"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.name_prefix}-api-server-tg"
  }
}

# Target Group for Webapp (port 3001)
resource "aws_lb_target_group" "webapp" {
  name     = "${var.name_prefix}-webapp"
  port     = 3001
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200,301,302"
  }

  deregistration_delay = 30

  tags = {
    Name = "${var.name_prefix}-webapp-tg"
  }
}

# HTTP Listener (redirect all HTTP to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.jambonz.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS Listener (port 443) with SNI support for multiple certificates
# Using primary certificate for telephony.graine.ai
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.jambonz.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.telephony_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_server.arn
  }
}

# Add additional certificate for SNI (sipwebapp.graine.ai)
resource "aws_lb_listener_certificate" "webapp" {
  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = var.webapp_certificate_arn
}

# Listener Rule: telephony.graine.ai → API Server
resource "aws_lb_listener_rule" "telephony" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_server.arn
  }

  condition {
    host_header {
      values = ["telephony.graine.ai"]
    }
  }
}

# Listener Rule: sipwebapp.graine.ai → Webapp
resource "aws_lb_listener_rule" "webapp" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 90

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webapp.arn
  }

  condition {
    host_header {
      values = ["sipwebapp.graine.ai"]
    }
  }
}

# Outputs
output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.jambonz.dns_name
}

output "alb_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.jambonz.arn
}

output "alb_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.jambonz.zone_id
}

output "api_target_group_arn" {
  description = "ARN of the API server target group"
  value       = aws_lb_target_group.api_server.arn
}

output "webapp_target_group_arn" {
  description = "ARN of the webapp target group"
  value       = aws_lb_target_group.webapp.arn
}

