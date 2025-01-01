# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      class PullRequestAlertsFiltererTest < GitHub::TestCase
        include SecurityCenter::TestFixtures
        include ::SecurityOverviewAnalytics::TestFixtures

        fixtures do
          @repository = create(:private_repository)
          create_pull_request_alerts(repository: @repository)
        end

        setup do
          @rel = CodeScanningPullRequestAlert.all
        end

        context "#apply" do
          test "scopes to code scanning enabled repository" do
            assert new_filterer("").apply(@rel).count > 0

            FeatureStatusRevision.where(repository: @repository).update_all(code_scanning_enabled: false)

            assert_equal 0, new_filterer("").apply(@rel).count
          end

          context "when no filters applied" do
            test "it returns expected alerts" do
              rel = new_filterer("").apply(@rel)

              refute_equal @rel.count, rel.count
              assert_same_elements ["CodeQL"], rel.map(&:tool).uniq
              assert_same_elements %w[critical high medium low], rel.map(&:alert_severity).uniq
            end
          end

          context "when filtered by severity" do
            test "it returns expected alerts" do
              rel = new_filterer("severity:high").apply(@rel)

              refute_equal @rel.count, rel.count
              assert_same_elements ["CodeQL"], rel.map(&:tool).uniq
              assert_same_elements ["high"], rel.map(&:alert_severity).uniq
            end
          end

          context "when filtered by rule" do
            test "it returns expected alerts" do
              rel = new_filterer("codeql.rule:java/xss").apply(@rel)

              refute_equal @rel.count, rel.count
              assert_same_elements ["CodeQL"], rel.map(&:tool).uniq
              assert_same_elements %w[critical high medium low], rel.map(&:alert_severity).uniq
              assert_same_elements ["java/xss"], rel.map(&:rule_sarif_identifier).uniq
            end
          end

          context "when filtered by resolution" do
            test "it returns expected alerts" do
              rel = new_filterer("resolution:false-positive").apply(@rel)

              refute_equal @rel.count, rel.count
              assert_same_elements ["CodeQL"], rel.map(&:tool).uniq
              assert_same_elements %w[critical high medium low], rel.map(&:alert_severity).uniq
              assert_same_elements [::Turboscan::Proto::ResultResolution::FALSE_POSITIVE], rel.map(&:alert_resolution).uniq
            end
          end

          context "when filtered by autofix state" do
            test "it returns expected alerts" do
              rel = new_filterer("codeql.autofix:suggested").apply(@rel)

              refute_equal @rel.count, rel.count
              assert_same_elements ["CodeQL"], rel.map(&:tool).uniq
              assert_same_elements %w[critical high medium low], rel.map(&:alert_severity).uniq
              assert_same_elements [true], rel.map(&:has_autofix).uniq
            end
          end

          context "when filtered by state" do
            test "it returns expected alerts for unresolved" do
              rel = new_filterer("state:unresolved").apply(@rel)

              refute_equal @rel.count, rel.count
              assert_same_elements ["CodeQL"], rel.map(&:tool).uniq
              assert_same_elements %w[critical high medium low], rel.map(&:alert_severity).uniq
              assert_same_elements [false], rel.map(&:alert_resolved).uniq
              assert_same_elements [nil], rel.map(&:alert_resolution).uniq
            end

            test "it returns expected alerts for dismissed" do
              rel = new_filterer("state:dismissed").apply(@rel)

              refute_equal @rel.count, rel.count
              assert_same_elements ["CodeQL"], rel.map(&:tool).uniq
              assert_same_elements %w[critical high medium low], rel.map(&:alert_severity).uniq
              assert_same_elements [true], rel.map(&:alert_resolved).uniq
              assert_same_elements Filters::CodeScanning::ByState::DISMISSED_RESOLUTIONS, rel.map(&:alert_resolution).uniq
            end

            test "it returns expected alerts for fixed" do
              rel = new_filterer("state:fixed").apply(@rel)

              refute_equal @rel.count, rel.count
              assert_same_elements ["CodeQL"], rel.map(&:tool).uniq
              assert_same_elements %w[critical high medium low], rel.map(&:alert_severity).uniq
              assert_same_elements [true], rel.map(&:alert_resolved).uniq
              assert_same_elements [nil], rel.map(&:alert_resolution).uniq
            end
          end
        end

        private

        def new_filterer(query)
          PullRequestAlertsFilterer.new(Search::Queries::SecurityCenter::QueryParser.new(query))
        end
      end
    end
  end
end
