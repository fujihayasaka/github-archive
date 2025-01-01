# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module SecretScanning
      class ByBypassedTest < GitHub::TestCase
        fixtures do
          @org = create(:business_plus_organization)
          @repo = create(:security_overview_analytics_repository)
          @repo.update(organization_id: @org.id)
          @date = create(:security_overview_analytics_date)

          @ss_1 = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 1, alert_bypassed: true, repository: @repo.repository)
          @ss_2 = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 2, alert_bypassed: false, repository: @repo.repository)
          @ss_3 = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 3, alert_bypassed: true, repository: @repo.repository)
        end

        setup do
          @ss_rel = SecretScanningAlertRevision.where(next_revision_date_id: 99991231)
        end

        context "#apply" do
          context "no filters are provided" do
            test "does not filter on alert_numbers" do
              assert_query_count(1) do
                ByBypassed.new([], []).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                assert_equal 3, alert_numbers.size
              end
            end
          end

          context "inclusive filters" do
            test "returns nothing if there are no valid filters" do
              assert_query_count(0) do
                ByBypassed.new(["foo"], []).apply(@ss_rel).to_a
              end.tap do |alerts|
                assert_empty alerts
              end
            end

            test "filters by bypassed status" do
              assert_query_count(1) do
                ByBypassed.new(["true"], []).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                expected = [@ss_1.alert_number, @ss_3.alert_number]
                assert_same_elements expected, alert_numbers
              end

              assert_query_count(1) do
                ByBypassed.new(["false"], []).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                expected = [@ss_2.alert_number]
                assert_same_elements expected, alert_numbers
              end
            end

            test "ignores invalid filters" do
              assert_query_count(1) do
                ByBypassed.new(%w[true foo], []).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                expected = [@ss_1.alert_number, @ss_3.alert_number]
                assert_same_elements expected, alert_numbers
              end
            end

            test "filters by OR'd bypassed statuss with multiple filter values" do
              assert_query_count(1) do
                ByBypassed.new(%w[false true], []).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                expected = [@ss_1.alert_number, @ss_2.alert_number, @ss_3.alert_number]
                assert_same_elements expected, alert_numbers
              end
            end
          end

          context "exclusive filters" do
            test "returns all alerts if there are no valid filters" do
              assert_query_count(1) do
                ByBypassed.new([], ["foo"]).apply(@ss_rel).to_a
              end.tap do |alerts|
                assert_equal 3, alerts.size
              end
            end

            test "filters by bypassed status" do
              assert_query_count(1) do
                ByBypassed.new([], ["true"]).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                expected = [@ss_2.alert_number]
                assert_same_elements expected, alert_numbers
              end

              assert_query_count(1) do
                ByBypassed.new([], ["false"]).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                expected = [@ss_1.alert_number, @ss_3.alert_number]
                assert_same_elements expected, alert_numbers
              end
            end

            test "ignores invalid negated filters" do
              assert_query_count(1) do
                ByBypassed.new([], %w[true foo]).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                expected = [@ss_2.alert_number]
                assert_same_elements expected, alert_numbers
              end
            end

            test "filters by AND'd bypassed statuss with multiple filter values" do
              assert_query_count(1) do
                ByBypassed.new([], %w[false true]).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                assert_empty alert_numbers
              end
            end
          end

          context "inclusive and exclusive filters" do
            test "filters by OR'd inclusive bypassed statuss and AND'd exclusive bypassed statuss" do
              assert_query_count(1) do
                ByBypassed.new(%w[false true], ["true"]).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                expected = [@ss_2.alert_number]
                assert_same_elements expected, alert_numbers
              end

              assert_query_count(1) do
                ByBypassed.new(["true"], %w[true false]).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                assert_empty alert_numbers
              end
            end

            test "returns no results for conflicting filter values" do
              assert_query_count(1) do
                ByBypassed.new(["true"], ["true"]).apply(@ss_rel).map(&:alert_number)
              end.tap do |alert_numbers|
                assert_empty alert_numbers
              end
            end
          end
        end
      end
    end
  end
end
