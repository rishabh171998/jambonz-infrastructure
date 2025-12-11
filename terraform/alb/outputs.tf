output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.jambonz.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the load balancer (for Route53 alias)"
  value       = aws_lb.jambonz.zone_id
}

output "telephony_api_url" {
  description = "Telephony API endpoint URL (telephony.graine.ai)"
  value       = "https://telephony.graine.ai/api/v1"
}

output "telephony_swagger_url" {
  description = "Swagger UI URL (telephony.graine.ai)"
  value       = "https://telephony.graine.ai/swagger/"
}

output "webapp_url" {
  description = "Webapp URL (sipwebapp.graine.ai)"
  value       = "https://sipwebapp.graine.ai"
}

output "webapp_internal_url" {
  description = "Webapp internal URL example"
  value       = "https://sipwebapp.graine.ai/internal/accounts"
}

output "sip_domain" {
  description = "SIP domain (sip.graine.ai) - for SIP/RTP traffic (direct EC2 access)"
  value       = "sip.graine.ai"
}

