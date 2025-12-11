#!/bin/bash
# Script to request SSL certificates for telephony.graine.ai and sipwebapp.graine.ai

set -e

REGION="ap-south-1"  # Mumbai

echo "=========================================="
echo "Requesting SSL Certificates for Jambonz"
echo "=========================================="
echo ""
echo "Region: $REGION"
echo ""

# Request certificate for telephony.graine.ai
echo "1. Requesting certificate for telephony.graine.ai..."
TELEPHONY_CERT_ARN=$(aws acm request-certificate \
  --domain-name telephony.graine.ai \
  --validation-method DNS \
  --region $REGION \
  --query 'CertificateArn' \
  --output text 2>/dev/null || echo "")

if [ -n "$TELEPHONY_CERT_ARN" ]; then
  echo "✅ Certificate requested: $TELEPHONY_CERT_ARN"
else
  echo "❌ Failed to request certificate"
  exit 1
fi

# Request certificate for sipwebapp.graine.ai
echo ""
echo "2. Requesting certificate for sipwebapp.graine.ai..."
WEBAPP_CERT_ARN=$(aws acm request-certificate \
  --domain-name sipwebapp.graine.ai \
  --validation-method DNS \
  --region $REGION \
  --query 'CertificateArn' \
  --output text 2>/dev/null || echo "")

if [ -n "$WEBAPP_CERT_ARN" ]; then
  echo "✅ Certificate requested: $WEBAPP_CERT_ARN"
else
  echo "❌ Failed to request certificate"
  exit 1
fi

echo ""
echo "=========================================="
echo "Certificate Validation Required"
echo "=========================================="
echo ""
echo "Get DNS validation records:"
echo ""
echo "For telephony.graine.ai:"
aws acm describe-certificate \
  --certificate-arn "$TELEPHONY_CERT_ARN" \
  --region $REGION \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
  --output json

echo ""
echo "For sipwebapp.graine.ai:"
aws acm describe-certificate \
  --certificate-arn "$WEBAPP_CERT_ARN" \
  --region $REGION \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
  --output json

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Add DNS validation records to your DNS provider"
echo "2. Wait for validation (can take a few minutes)"
echo "3. Check validation status:"
echo "   aws acm describe-certificate --certificate-arn $TELEPHONY_CERT_ARN --region $REGION --query 'Certificate.Status'"
echo "   aws acm describe-certificate --certificate-arn $WEBAPP_CERT_ARN --region $REGION --query 'Certificate.Status'"
echo ""
echo "4. Once validated, update terraform.tfvars:"
echo "   telephony_certificate_arn = \"$TELEPHONY_CERT_ARN\""
echo "   webapp_certificate_arn = \"$WEBAPP_CERT_ARN\""
echo ""

