# typed: strict
#!/usr/bin/env safe-ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "report_axe_routes_coverage"
require "report_axe_violations"
require "report_axe_report_summary"

# Report number of routes with and without scans.
ReportAxeRoutesCoverage.new(
  artifact_path: "/tmp/github-routes-for-axe-coverage-artifacts/routes_axe_coverage_by_service.json"
).submit_report!

# Report metadata about Axe violations detected.
ReportAxeViolations.new(
  artifact_path: "/tmp/github-routes-for-axe-coverage-artifacts/axe_violations_by_service.json"
).submit_report!

# Report metadata about Axe scans conducted.
ReportAxeReportSummary.new(
  artifact_path: "/tmp/github-routes-for-axe-coverage-artifacts/combined_axe_report_summary.jsonl"
).submit_report!
