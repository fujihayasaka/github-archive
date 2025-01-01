# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module CodeScanning
      class ByRuleTest < GitHub::TestCase
        fixtures do
          @org = create(:business_plus_organization)
          @repo = create(:security_overview_analytics_repository)
          @repo.update(organization_id: @org.id)
          @date = create(:security_overview_analytics_date)

          @codeql_1 = create(:soa_code_scanning_alert_revision, date_id: @date.id, alert_number: 1, rule_sarif_identifier: "rule-1", repository: @repo.repository)
          @codeql_2 = create(:soa_code_scanning_alert_revision, date_id: @date.id, alert_number: 2, rule_sarif_identifier: "Rule 2", repository: @repo.repository)
          @codeql_3 = create(:soa_code_scanning_alert_revision, date_id: @date.id, alert_number: 3, rule_sarif_identifier: "", repository: @repo.repository)
          @third_party_1 = create(:soa_code_scanning_alert_revision, date_id: @date.id, alert_number: 4, tool: "some-tool", rule_sarif_identifier: "rule-1", repository: @repo.repository)
          @third_party_2 = create(:soa_code_scanning_alert_revision, date_id: @date.id, alert_number: 5, tool: "another-tool", rule_sarif_identifier: "Rule 3", repository: @repo.repository)
        end

        setup do
          @cs_rel = CodeScanningAlertRevision.where(next_revision_date_id: 99991231)
        end

        context "#apply" do
          context "no filters are provided" do
            test "does not filter on rules for codeql" do
              assert_query_count(1) do
                ByRule.new([], []).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                assert_equal 5, rule_sarif_identifiers.size
              end
            end

            test "does not filter on rules for third-party tools" do
              assert_query_count(1) do
                ByRule.new([], [], codeql_rule: false).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                assert_equal 5, rule_sarif_identifiers.size
              end
            end
          end

          context "inclusive filters" do
            test "filters by rules" do
              assert_query_count(1) do
                ByRule.new(["rule-1"], []).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                expected = [@codeql_1.rule_sarif_identifier]
                assert_same_elements expected, rule_sarif_identifiers
              end

              assert_query_count(1) do
                ByRule.new(["Rule 2"], []).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                expected = [@codeql_2.rule_sarif_identifier]
                assert_same_elements expected, rule_sarif_identifiers
              end
            end

            test "filters are case-insensitive" do
              assert_query_count(1) do
                ByRule.new(["RuLe-1"], []).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                expected = [@codeql_1.rule_sarif_identifier]
                assert_same_elements expected, rule_sarif_identifiers
              end
            end

            test "filters by OR'd rules with multiple filter values" do
              assert_query_count(1) do
                ByRule.new(["rule-1", "Rule 2"], []).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                expected = [@codeql_1.rule_sarif_identifier, @codeql_2.rule_sarif_identifier]
                assert_same_elements expected, rule_sarif_identifiers
              end
            end

            test "filters by codeql OR all third party tools" do
              # filter by codeql
              assert_query_count(1) do
                ByRule.new(["rule-1"], []).apply(@cs_rel).pluck(:rule_sarif_identifier, :tool)
              end.tap do |rule_sarif_identifiers|
                expected = [[@codeql_1.rule_sarif_identifier, "CodeQL"]]
                assert_same_elements expected, rule_sarif_identifiers
              end

              # filter by third party tools
              assert_query_count(1) do
                ByRule.new(["rule-1"], [], codeql_rule: false).apply(@cs_rel).pluck(:rule_sarif_identifier, :tool)
              end.tap do |rule_sarif_identifiers|
                expected = [[@third_party_1.rule_sarif_identifier, "some-tool"]]
                assert_same_elements expected, rule_sarif_identifiers
              end
            end
          end

          context "exclusive filters" do
            test "filters by rules" do
              assert_query_count(1) do
                ByRule.new([], ["rule-1"]).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                expected = [@codeql_2.rule_sarif_identifier, @codeql_3.rule_sarif_identifier]
                assert_same_elements expected, rule_sarif_identifiers
              end

              assert_query_count(1) do
                ByRule.new([], ["Rule 2"]).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                expected = [@codeql_1.rule_sarif_identifier, @codeql_3.rule_sarif_identifier]
                assert_same_elements expected, rule_sarif_identifiers
              end
            end

            test "filters are case-insensitive" do
              assert_query_count(1) do
                ByRule.new([], ["RuLe-1"]).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                expected = [@codeql_2.rule_sarif_identifier, @codeql_3.rule_sarif_identifier]
                assert_same_elements expected, rule_sarif_identifiers
              end
            end

            test "filters by AND'd rules with multiple filter values" do
              assert_query_count(1) do
                ByRule.new([], ["rule-1", "Rule 2"]).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                expected = [@codeql_3.rule_sarif_identifier]
                assert_same_elements expected, rule_sarif_identifiers
              end
            end

            test "filters by codeql OR all third party tools" do
              # exclude by codeql
              assert_query_count(1) do
                ByRule.new([], ["rule-1"]).apply(@cs_rel).pluck(:rule_sarif_identifier, :tool)
              end.tap do |rule_sarif_identifiers|
                expected = [[@codeql_2.rule_sarif_identifier, "CodeQL"], [@codeql_3.rule_sarif_identifier, "CodeQL"]]
                assert_same_elements expected, rule_sarif_identifiers
              end

              # exclude by third party tools
              assert_query_count(1) do
                ByRule.new([], ["rule-1"], codeql_rule: false).apply(@cs_rel).pluck(:rule_sarif_identifier, :tool)
              end.tap do |rule_sarif_identifiers|
                expected = [[@third_party_2.rule_sarif_identifier, "another-tool"]]
                assert_same_elements expected, rule_sarif_identifiers
              end
            end
          end

          context "inclusive and exclusive filters" do
            test "filters by rules" do
              assert_query_count(1) do
                ByRule.new(["rule-1"], ["Rule 2"]).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                expected = [@codeql_1.rule_sarif_identifier]
                assert_same_elements expected, rule_sarif_identifiers
              end
            end

            test "filters by OR'd inclusive rules and AND'd exclusive rules" do
              assert_query_count(1) do
                ByRule.new(["rule-1", "Rule 2"], ["rule-1"]).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                expected = [@codeql_2.rule_sarif_identifier]
                assert_same_elements expected, rule_sarif_identifiers
              end

              assert_query_count(1) do
                ByRule.new(["rule-1"], %w[rule-1 Rule 2]).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                assert_empty rule_sarif_identifiers
              end
            end

            test "returns no results for conflicting filter values" do
              assert_query_count(1) do
                ByRule.new(["Rule 2"], ["Rule 2"]).apply(@cs_rel).map(&:rule_sarif_identifier)
              end.tap do |rule_sarif_identifiers|
                assert_empty rule_sarif_identifiers
              end
            end
          end
        end
      end
    end
  end
end
