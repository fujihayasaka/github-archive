#!/bin/bash
if [[ -z "${DEV_COSMOS_KEY}" ]]; then
    echo "DEV_COSMOS_KEY is not set, logging into Azure"
    /workspaces/billing-platform/script/azure-login
fi

/workspaces/billing-platform/script/set-remote

/workspaces/billing-platform/script/source-goproxyenv

/workspaces/billing-platform/script/helpers/get-database-count
