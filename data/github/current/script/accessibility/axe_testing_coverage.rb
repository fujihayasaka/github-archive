# typed: strict
#!/usr/bin/env safe-ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require_relative "../routes_for_axe_coverage"
require "process_axe_testing_data"
require_relative "../../config/environment"

PRODUCTION_RESULTS_ARTIFACT_PATH = "./tmp/e2e-axe-artifacts/snek-e2e-accessibility-axe-report-production-artifacts/test-results/axe_results.jsonl"
DEVELOPMENT_RESULTS_ARTIFACT_PATH = "./tmp/e2e-axe-artifacts/snek-e2e-accessibility-axe-report-development-artifacts/test-results/axe_results.jsonl"
PRODUCTION_SUMMARY_ARTIFACT_PATH = "./tmp/e2e-axe-artifacts/snek-e2e-accessibility-axe-report-production-artifacts/test-results/axe_report_summary.jsonl"
DEVELOPMENT_SUMMARY_ARTIFACT_PATH = "./tmp/e2e-axe-artifacts/snek-e2e-accessibility-axe-report-development-artifacts/test-results/axe_report_summary.jsonl"

missing_artifacts = []
[PRODUCTION_RESULTS_ARTIFACT_PATH, DEVELOPMENT_RESULTS_ARTIFACT_PATH, PRODUCTION_SUMMARY_ARTIFACT_PATH, DEVELOPMENT_SUMMARY_ARTIFACT_PATH].each do |path|
  unless File.exist?(path)
    missing_artifacts.push(path)
  end
end

if missing_artifacts.any?
  raise "Unable to report to Datadog because the following axe artifacts could not be found: #{missing_artifacts.join(',')}"
end

COMBINED_AXE_RESULTS_PATH = "/tmp/github-routes-for-axe-coverage-artifacts/combined_axe_results.jsonl"
combined_axe_results_data = File.readlines(PRODUCTION_RESULTS_ARTIFACT_PATH) + File.readlines(DEVELOPMENT_RESULTS_ARTIFACT_PATH)
File.open(COMBINED_AXE_RESULTS_PATH, "w+") do |file|
  combined_axe_results_data.each do |line|
    file.puts line
  end
end

combined_summary_data = File.readlines(PRODUCTION_SUMMARY_ARTIFACT_PATH) + File.readlines(DEVELOPMENT_SUMMARY_ARTIFACT_PATH)
File.open("/tmp/github-routes-for-axe-coverage-artifacts/combined_axe_report_summary.jsonl", "w+") do |file|
  combined_summary_data.each do |line|
    file.puts line
  end
end

RoutesForAxeCoverage.new(
  routes: Rails.application.routes.routes,
  output_directory: "/tmp/github-routes-for-axe-coverage-artifacts/"
).generate_report

ProcessAxeTestingData.new(
  routes: Rails.application.routes.routes,
  artifact_path: COMBINED_AXE_RESULTS_PATH,
  final_routes_path: "/tmp/github-routes-for-axe-coverage-artifacts/final_routes_list.json",
  output_directory: "/tmp/github-routes-for-axe-coverage-artifacts/"
).generate_report
