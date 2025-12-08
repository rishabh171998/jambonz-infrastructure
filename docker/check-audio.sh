#!/bin/bash
# Script to diagnose audio playback issues

cd /opt/jambonz-infrastructure/docker

echo "=== Audio Service Status ==="
echo ""
echo "RTPEngine:"
sudo docker compose ps rtpengine

echo ""
echo "FreeSwitch:"
sudo docker compose ps freeswitch

echo ""
echo "Feature Server:"
sudo docker compose ps feature-server

echo ""
echo "=== RTPEngine Logs (last 20 lines) ==="
sudo docker compose logs rtpengine --tail 20

echo ""
echo "=== FreeSwitch Logs (last 20 lines) ==="
sudo docker compose logs freeswitch --tail 20

echo ""
echo "=== Feature Server Logs (last 20 lines, audio related) ==="
sudo docker compose logs feature-server --tail 50 | grep -i "audio\|play\|say\|speak\|media\|rtp" || echo "No audio-related logs found"

echo ""
echo "=== Checking RTPEngine connectivity ==="
sudo docker compose exec rtpengine netstat -uln | grep 22222 || echo "RTPEngine NG port 22222 not listening"

echo ""
echo "=== Checking network connectivity ==="
echo "RTPEngine IP: 172.10.0.11"
echo "FreeSwitch IP: 172.10.0.51"
echo "Feature Server IP: 172.10.0.60"

echo ""
echo "=== Testing RTPEngine from feature-server ==="
sudo docker compose exec feature-server ping -c 2 rtpengine > /dev/null 2>&1 && echo "✓ Can ping rtpengine" || echo "✗ Cannot ping rtpengine"

echo ""
echo "=== Testing FreeSwitch from feature-server ==="
sudo docker compose exec feature-server ping -c 2 freeswitch > /dev/null 2>&1 && echo "✓ Can ping freeswitch" || echo "✗ Cannot ping freeswitch"

echo ""
echo "=== RTPEngine status ==="
sudo docker compose exec rtpengine rtpengine-ctl list 2>/dev/null || echo "Cannot query rtpengine status"

