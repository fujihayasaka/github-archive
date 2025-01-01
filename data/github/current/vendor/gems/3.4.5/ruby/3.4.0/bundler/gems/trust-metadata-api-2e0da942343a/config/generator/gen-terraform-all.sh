#!/bin/bash
# This script generates all TMA configuration for all stamps.

set -e

./gen-terraform.sh prod-weu-01 prod westeurope
./gen-terraform.sh prod-ae-01 prod australiaeast
./gen-terraform.sh prod-sdc-01 prod swedencentral
./gen-terraform.sh prod-cus-01 prod centralus
./gen-terraform.sh test-cnc-01 test canadacentral
