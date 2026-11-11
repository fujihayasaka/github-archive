#!/bin/bash
# Rebuild org insights all organizations with atleast one Go repository
# Transition usage: run in #dg-ops .transitions run <PR url> <environment> backfill_go_org_insights.sh [-w]

script/one_off/backfill_dependency_insights.rb --package_manager=go --start_at=0 "$*"
