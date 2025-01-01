#!/bin/bash

echo "Migrating notifyd cluster"
./go/bin/migrate

echo "Starting api"
./go/bin/api
