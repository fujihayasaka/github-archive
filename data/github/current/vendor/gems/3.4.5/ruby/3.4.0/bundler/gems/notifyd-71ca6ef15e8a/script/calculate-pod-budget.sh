#!/bin/bash
#

# This is based on the 25% default maxSurge settings in kubernetes
# (https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
SURGE_FACTOR=0.25
# The minimal count of pods to allocate for surge. This should be at least one
# as for example 25% of 2 is 0.5 but we can't spin up half a container. We are
# setting this to 2 to allow for terminating containers that aren't counted
# for the basis of surge but count against the overall pod quota.
MIN_SURGE_COUNT=2
# this is an arbitrary number to allow for a couple of transition jobs to run
CAPACITY_BUFFER=5
# configuration file for pod quota
pod_quota_config=config/kubernetes/default/resourcequotas/gh-default.yaml


current_quota=$(grep -o 'pods: "[0-9]*"' ${pod_quota_config}  | awk -F\" '{ print $2}')
replicas=$(grep -o "replicas: [0-9]*" config/kubernetes/default/deployments/* | awk '{pods += $2} END {print pods}')
surge_capacity=$(grep -o "replicas: [0-9]*" config/kubernetes/default/deployments/* | awk -v surge_factor="${SURGE_FACTOR}" -v min_surge_count="${MIN_SURGE_COUNT}" '{cap += int($2 * surge_factor + min_surge_count)} END {print cap}')

recommended_quota=$((replicas + surge_capacity + CAPACITY_BUFFER))


echo "current quota is ${current_quota}, recommended quota is ${recommended_quota} (${replicas} replicas, ${surge_capacity} surge capacity, ${CAPACITY_BUFFER} overflow buffer for transition jobs and other spikes)"


if [ ${current_quota} -lt ${recommended_quota} ]; then
  echo "not enough configured pod quota. Please adjust to at least the recommndation."
  exit 1
else
  echo "pod quota configuration suitable."
fi
