# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class BySeverityTest < GitHub::TestCase
      fixtures do
        @org = create(:business_plus_organization)
        @repo = create(:security_overview_analytics_repository)
        @repo.update(organization_id: @org.id)
        @date = create(:security_overview_analytics_date)

        # Dbot revisions
        @dbot_1 = create(:security_overview_analytics_dependabot_alert_revision, date_id: @date.id, alert_number: 1, repository: @repo.repository, alert_severity: "low")
        @dbot_2 = create(:security_overview_analytics_dependabot_alert_revision, date_id: @date.id, alert_number: 2, repository: @repo.repository, alert_severity: "moderate")
        @dbot_3 = create(:security_overview_analytics_dependabot_alert_revision, date_id: @date.id, alert_number: 4, repository: @repo.repository, alert_severity: "high")
        @dbot_4 = create(:security_overview_analytics_dependabot_alert_revision, date_id: @date.id, alert_number: 3, repository: @repo.repository, alert_severity: "critical")
        # CS revisions
        @cs_1 = create(:security_overview_analytics_code_scanning_alert_revision, date_id: @date.id, alert_number: 1, repository: @repo.repository, alert_severity: "low")
        @cs_2 = create(:security_overview_analytics_code_scanning_alert_revision, date_id: @date.id, alert_number: 2, repository: @repo.repository, alert_severity: "medium")
        @cs_3 = create(:security_overview_analytics_code_scanning_alert_revision, date_id: @date.id, alert_number: 4, repository: @repo.repository, alert_severity: "high")
        @cs_4 = create(:security_overview_analytics_code_scanning_alert_revision, date_id: @date.id, alert_number: 3, repository: @repo.repository, alert_severity: "critical")
        # SS revisions
        @ss_1 = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 1, repository: @repo.repository)
      end

      setup do
        @dbot_rel = DependabotAlertRevision.where(next_revision_date_id: 99991231)
        @cs_rel = CodeScanningAlertRevision.where(next_revision_date_id: 99991231)
        @ss_rel = SecretScanningAlertRevision.where(next_revision_date_id: 99991231)
      end

      context "#apply" do
        context "no filters are provided" do
          test "does not filter on alerts" do
            assert_query_count(1) do
              BySeverity.new([], []).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alerts|
              assert_equal 4, alerts.size
            end
          end
        end

        context "inclusive filters" do
          test "filters by severity" do
            assert_query_count(1) do
              BySeverity.new(["low"], []).apply(@cs_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@cs_1.alert_number]
              assert_same_elements expected, alerts
            end

            assert_query_count(1) do
              BySeverity.new(["medium"], []).apply(@cs_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@cs_2.alert_number]
              assert_same_elements expected, alerts
            end
          end

          test "filters by OR'd severities with multiple filter values" do
            assert_query_count(1) do
              BySeverity.new(%w[critical high], []).apply(@cs_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@cs_3.alert_number, @cs_4.alert_number]
              assert_same_elements expected, alerts
            end
          end

          test "correctly maps 'medium' to 'moderate' for Dependabot" do
            assert_query_count(1) do
              BySeverity.new(["medium"], []).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@dbot_2.alert_number]
              assert_same_elements expected, alerts
            end
          end

          test "correctly only considers 'critical' alerts for Secret Scanning" do
            assert_query_count(1) do
              BySeverity.new(%w[critical high], []).apply(@ss_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@ss_1.alert_number]
              assert_same_elements expected, alerts
            end

            assert_query_count(0) do
              BySeverity.new(["high"], []).apply(@ss_rel).map(&:alert_number)
            end.tap do |alerts|
              assert_empty alerts
            end
          end
        end

        context "exclusive filters" do
          test "filters by severity" do
            assert_query_count(1) do
              BySeverity.new([], ["low"]).apply(@cs_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@cs_2.alert_number, @cs_3.alert_number, @cs_4.alert_number]
              assert_same_elements expected, alerts
            end

            assert_query_count(1) do
              BySeverity.new([], ["medium"]).apply(@cs_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@cs_1.alert_number, @cs_3.alert_number, @cs_4.alert_number]
              assert_same_elements expected, alerts
            end
          end

          test "filters by AND'd severities with multiple filter values" do
            assert_query_count(1) do
              BySeverity.new([], %w[critical high]).apply(@cs_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@cs_1.alert_number, @cs_2.alert_number]
              assert_same_elements expected, alerts
            end
          end

          test "correctly maps 'medium' to 'moderate' for Dependabot" do
            assert_query_count(1) do
              BySeverity.new([], ["medium"]).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@dbot_1.alert_number, @dbot_3.alert_number, @dbot_4.alert_number]
              assert_same_elements expected, alerts
            end
          end

          test "correctly only considers 'critical' alerts for Secret Scanning" do
            assert_query_count(0) do
              BySeverity.new([], ["critical"]).apply(@ss_rel).map(&:alert_number)
            end.tap do |alerts|
              assert_empty alerts
            end

            assert_query_count(1) do
              BySeverity.new([], ["high"]).apply(@ss_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@ss_1.alert_number]
              assert_same_elements expected, alerts
            end
          end
        end

        context "inclusive and exclusive filters" do
          test "filters by severity" do
            assert_query_count(1) do
              BySeverity.new(["low"], ["high"]).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alert_numbers|
              expected = [@dbot_1.alert_number]
              assert_same_elements expected, alert_numbers
            end
          end

          test "filters by OR'd inclusive severities and AND'd exclusive severities" do
            assert_query_count(1) do
              BySeverity.new(%w[medium high], ["high"]).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alert_numbers|
              expected = [@dbot_2.alert_number]
              assert_same_elements expected, alert_numbers
            end

            assert_query_count(1) do
              BySeverity.new(["high"], %w[high critical]).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alert_numbers|
              assert_empty alert_numbers
            end
          end

          test "returns no results for conflicting filter values" do
            assert_query_count(1) do
              BySeverity.new(["high"], ["high"]).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alert_numbers|
              assert_empty alert_numbers
            end
          end
        end
      end

      context "#is_empty?" do
        test "returns 'true' when provided no filters" do
          assert BySeverity.new([], []).is_empty?
        end

        test "returns 'false' when provided inclusive filters" do
          refute BySeverity.new(["high"], []).is_empty?
        end

        test "returns 'false' when provided exclusive filters" do
          refute BySeverity.new([], ["high"]).is_empty?
        end

        test "returns 'false' when provided both inclusive and exclusive filters" do
          refute BySeverity.new(["high"], ["low"]).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns 'false' when provided no filters" do
          refute BySeverity.new([], []).has_incl_filters?
        end

        test "returns 'true' when provided inclusive filters" do
          assert BySeverity.new(["high"], []).has_incl_filters?
        end

        test "returns 'false' when provided exclusive filters" do
          refute BySeverity.new([], ["high"]).has_incl_filters?
        end

        test "returns 'true' when provided both inclusive and exclusive filters" do
          assert BySeverity.new(["high"], ["low"]).has_incl_filters?
        end
      end
    end
  end
end
