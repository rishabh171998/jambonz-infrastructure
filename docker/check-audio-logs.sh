#!/bin/bash
# Quick script to check audio-related logs

cd /opt/jambonz-infrastructure/docker

echo "=== Feature Server Logs (last 30 lines, audio/media related) ==="
sudo docker compose logs feature-server --tail 100 | grep -iE "audio|media|rtp|play|say|speak|listen|websocket|stream" | tail -30

echo ""
echo "=== RTPEngine Logs (last 30 lines) ==="
sudo docker compose logs rtpengine --tail 30

echo ""
echo "=== FreeSwitch Logs (last 30 lines) ==="
sudo docker compose logs freeswitch --tail 30

echo ""
echo "=== Checking for RTPEngine errors ==="
sudo docker compose logs rtpengine --tail 100 | grep -iE "error|fail|warn|timeout" | tail -10

echo ""
echo "=== Checking for media establishment ==="
sudo docker compose logs feature-server --tail 200 | grep -iE "media|rtp|endpoint|answer" | tail -20

