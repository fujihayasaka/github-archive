#!/bin/bash
if [[ -z "${DEV_COSMOS_KEY}" ]]; then
    echo "DEV_COSMOS_KEY is not set, logging into Azure"
    /workspaces/billing-platform/script/azure-login
fi

/workspaces/billing-platform/script/cosmos-emulator

/workspaces/billing-platform/script/source-goproxyenv
