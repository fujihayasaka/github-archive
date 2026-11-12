#!/bin/sh
# This script runs the statsd host locally in a way that ruby can talk to it, at least for the puma statsd plugin
image_id=$(docker build -q .)
docker run -p 8125:8125/udp "$image_id"
