# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      class PreventionDataFiltererTest < GitHub::TestCase
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

        context "#has_valid_filters?" do
          context "inclusive filters" do
            test "returns true when no tools are selected and no tool-centric filters are applied" do
              assert new_filterer("archived:false").has_valid_filters?
            end

            test "returns true when only codeql rule filter is applied" do
              assert new_filterer("codeql.rule:java/xss").has_valid_filters?
            end

            test "returns true when codeql is selected in tools" do
              assert new_filterer("tool:codeql,third-party").has_valid_filters?
            end

            test "returns false when third-party filters are applied" do
              refute new_filterer("tool:codeql third-party.rule:foo").has_valid_filters?
            end

            test "returns false when secret scanning filters are applied" do
              refute new_filterer("tool:codeql secret-scanning.validity:active").has_valid_filters?
            end

            test "returns false when dependabot filters are applied" do
              refute new_filterer("tool:codeql dependabot.ecosystem:npm").has_valid_filters?
            end
          end

          context "exclusive filters" do
            test "returns true if non-codeql tools are excluded" do
              assert new_filterer("-tool:third-party").has_valid_filters?
            end

            test "returns true if non-codeql alert-centric filters are excluded" do
              assert new_filterer("-third-party.rule:foo").has_valid_filters?
            end

            test "returns true if only codeql rule filter is excluded" do
              assert new_filterer("-codeql.rule:java/xss").has_valid_filters?
            end

            test "returns false if codeql tool is excluded" do
              refute new_filterer("-tool:codeql").has_valid_filters?
            end
          end

          context "inclusive and exclusive filters" do
            test "returns true if codeql tool is selected and some codeql rules are excluded" do
              assert new_filterer("tool:github -codeql.rule:java/xss").has_valid_filters?
            end

            test "returns true if non-codeql tools are excluded and codeql rules are included" do
              assert new_filterer("-tool:third-party codeql.rule:java/xss").has_valid_filters?
            end

            test "returns false if codeql tool is not selected and codeql rules are included" do
              refute new_filterer("-tool:github codeql.rule:java/xss").has_valid_filters?
            end

            test "returns false if codeql tool is not selected and codeql rules are excluded" do
              refute new_filterer("-tool:codeql -codeql.rule:java/xss").has_valid_filters?
            end
          end
        end

        private

        def new_filterer(query)
          PreventionDataFilterer.new(Search::Queries::SecurityCenter::QueryParser.new(query))
        end
      end
    end
  end
end
