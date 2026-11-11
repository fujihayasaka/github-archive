#!/bin/bash
set -e

# Ensure we are in the root of the repo if run from there, or navigate correctly
cd "$(dirname "$0")/../.."

echo "Running Encoder Comparison Benchmark..."
bundle exec ruby script/benchmark_otel_encoder/benchmark_otel_encoder.rb

echo ""
echo "---------------------------------------------------"
echo ""

echo "Running Main Thread Offload Benchmark..."
bundle exec ruby script/benchmark_otel_encoder/benchmark_otel_offload.rb
