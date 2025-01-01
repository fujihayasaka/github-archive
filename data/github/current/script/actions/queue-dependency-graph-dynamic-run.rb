#!/usr/bin/env safe-ruby
# frozen_string_literal: true

help = "Usage: queue-dependency-graph-dynamic-run.rb --nwo NWO --ref REF"

abort(help) unless [4, 6].include?(ARGV.length)
unless Rails.env.development? || ENV["DEPENDENCY_GRAPH_DYNAMIC_RUN_ENV_RESTRICTION"] == "false"
  abort("error: detected environment `#{Rails.env}`, if you know the risk of running this against `#{Rails.env}` set DEPENDENCY_GRAPH_DYNAMIC_RUN_ENV_RESTRICTION=false")
end

nwo = ""
ref = ""
runs_on = "ubuntu-latest" # Default for this

ARGV.each_slice(2) do |arg, value|
  if arg == "--nwo"
    nwo = value
  elsif arg == "--ref"
    ref = value
  else
    abort(help)
  end
end

# defer the require so the user gets quick feedback on syntax/safety checks
require_relative "../../config/environment"

# DGP uses GHAS as our integration, this is still called 'code_scanning' under the hood.
integration = Apps::Privileged.integration(:code_scanning)
# This is always pre-installed, but we should verify this
abort("error: missing GitHub Advanced Security integration!") if integration.nil?

repo = GitHub::Resources.with_name_with_owner(nwo)
abort("error: repository `#{nwo}` not found") if repo.nil?

workflow_yaml = %{
  on: dynamic
  jobs:
    codespaces:
      runs-on:  self-hosted
      steps:
        - run: exit 0
  }

result = repo.run_dynamic_workflow(
  actor: integration.bot,
  workflow: workflow_yaml,
  inputs: nil,
  ref: ref,
  workflow_name: "Automatic Dependency Submission: Smoke Test",
  slug: "auto-submission",
  integration_name: "github-advanced-security",
  entry_point: :script_actions_queue_dependency_graph_dynamic_run
)

puts("status: #{result.status}")
if result.call_succeeded?
  puts("execution_id: #{result.value.execution_id}")
  puts("workflow_run_id: #{result.value.workflow_run_id}")
else
  puts("error: #{result.options}")
end
