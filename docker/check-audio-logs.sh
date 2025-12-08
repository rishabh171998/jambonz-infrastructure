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

echo ""
echo "=== Checking FreeSwitch container status ==="
sudo docker compose ps freeswitch

echo ""
echo "=== Checking FreeSwitch environment variables ==="
if sudo docker compose ps freeswitch | grep -q "Up"; then
    sudo docker compose exec freeswitch env | grep -i "MOD_AUDIO_FORK" || echo "⚠️  MOD_AUDIO_FORK environment variables not found - container may need to be recreated"
else
    echo "⚠️  FreeSwitch container is not running - cannot check environment variables"
fi

echo ""
echo "=== Checking for FreeSwitch crashes/restarts ==="
sudo docker compose logs freeswitch --tail 200 | grep -iE "crash|segfault|abort|fatal|exit" | tail -10 || echo "No crash indicators found in recent logs"

