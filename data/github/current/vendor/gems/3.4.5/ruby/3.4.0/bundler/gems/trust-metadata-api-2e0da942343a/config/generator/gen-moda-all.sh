#!/bin/bash
# This script generates all TSA configuration for all stamps.

set -e

./gen-moda.sh prod-weu-01 prod
./gen-moda.sh prod-ae-01 prod
./gen-moda.sh prod-sdc-01 prod
./gen-moda.sh prod-cus-01 prod
./gen-moda.sh test-cnc-01 staging
