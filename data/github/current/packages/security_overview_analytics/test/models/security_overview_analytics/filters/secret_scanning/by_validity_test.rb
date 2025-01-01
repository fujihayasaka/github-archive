# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module SecretScanning
      class ByValidityTest < GitHub::TestCase
        TokenValidity = SecretScanningAlertRevision::SecretScanningTokenValidity

        fixtures do
          @org = create(:business_plus_organization)
          @repo = create(:security_overview_analytics_repository)
          @repo.update(organization_id: @org.id)

          @date_value = Time.current.utc.to_date.freeze
          @date = create(:security_overview_analytics_date, date_value: @date_value)
          @next_date = create(:security_overview_analytics_date, date_value: @date_value + 1.day)

          @ss_1_unknown = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, next_revision_date_id: @next_date.id, alert_number: 1, alert_validity: TokenValidity::TOKEN_VALIDITY_UNKNOWN, repository: @repo.repository)
          @ss_1_latest_active = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @next_date.id, alert_number: 1, alert_validity: TokenValidity::TOKEN_VALIDITY_ACTIVE, repository: @repo.repository)
          @ss_2_active = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, next_revision_date_id: @next_date.id, alert_number: 2, alert_validity: TokenValidity::TOKEN_VALIDITY_ACTIVE, repository: @repo.repository)
          @ss_2_latest_inactive = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @next_date.id, alert_number: 2, alert_validity: TokenValidity::TOKEN_VALIDITY_INACTIVE, repository: @repo.repository)
          @ss_3_inactive = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 3, alert_validity: TokenValidity::TOKEN_VALIDITY_INACTIVE, repository: @repo.repository)
          @ss_4_revoked = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 4, alert_validity: TokenValidity::TOKEN_VALIDITY_REVOKED, repository: @repo.repository)
          @ss_5_unverifiable = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 5, alert_validity: TokenValidity::TOKEN_VALIDITY_UNVERIFIABLE, repository: @repo.repository)
          @ss_6_nil_validity = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 6, repository: @repo.repository)
        end

        setup do
          @ss_rel = SecretScanningAlertRevision.all
        end

        context "#apply" do
          context "no filters are provided" do
            test "does not filter on alerts" do
              assert_query_count(1) do
                ByValidity.new([], []).apply(@ss_rel).to_a
              end.tap do |alerts|
                assert_equal 8, alerts.size
              end
            end
          end

          context "inclusive filters" do
            test "returns nothing if there are no valid filters" do
              assert_query_count(0) do
                ByValidity.new(["foo"], []).apply(@ss_rel).to_a
              end.tap do |alerts|
                assert_empty alerts
              end
            end

            test "filters by the latest validity" do
              assert_query_count(1) do
                ByValidity.new(["active"], []).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_1_unknown, @ss_1_latest_active]
                assert_same_elements expected, alerts
              end
            end

            test "ignores invalid values" do
              assert_query_count(1) do
                ByValidity.new(%w[active foo], []).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_1_unknown, @ss_1_latest_active]
                assert_same_elements expected, alerts
              end
            end

            test "properly maps UI validity values" do
              assert_query_count(1) do
                ByValidity.new(["inactive"], []).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_2_active, @ss_2_latest_inactive, @ss_3_inactive, @ss_4_revoked]
                assert_same_elements expected, alerts
              end

              assert_query_count(1) do
                ByValidity.new(["unknown"], []).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_5_unverifiable, @ss_6_nil_validity]
                assert_same_elements expected, alerts
              end
            end

            test "filters by OR'd validities with multiple filter values" do
              assert_query_count(1) do
                ByValidity.new(%w[active inactive], []).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_1_unknown, @ss_1_latest_active, @ss_2_active, @ss_2_latest_inactive, @ss_3_inactive, @ss_4_revoked]
                assert_same_elements expected, alerts
              end
            end
          end

          context "exclusive filters" do
            test "returns all alerts if there are no valid filters" do
              assert_query_count(1) do
                ByValidity.new([], ["foo"]).apply(@ss_rel).to_a
              end.tap do |alerts|
                assert_equal 8, alerts.size
              end
            end

            test "filters by the latest validity" do
              assert_query_count(1) do
                ByValidity.new([], ["active"]).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_2_active, @ss_2_latest_inactive, @ss_3_inactive, @ss_4_revoked, @ss_5_unverifiable, @ss_6_nil_validity]
                assert_same_elements expected, alerts
              end
            end

            test "ignores invalid negated values" do
              assert_query_count(1) do
                ByValidity.new([], %w[active foo]).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_2_active, @ss_2_latest_inactive, @ss_3_inactive, @ss_4_revoked, @ss_5_unverifiable, @ss_6_nil_validity]
                assert_same_elements expected, alerts
              end
            end

            test "properly maps UI validity values" do
              assert_query_count(1) do
                ByValidity.new([], ["inactive"]).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_1_unknown, @ss_1_latest_active, @ss_5_unverifiable, @ss_6_nil_validity]
                assert_same_elements expected, alerts
              end

              assert_query_count(1) do
                ByValidity.new([], ["unknown"]).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_1_unknown, @ss_1_latest_active, @ss_2_active, @ss_2_latest_inactive, @ss_3_inactive, @ss_4_revoked]
                assert_same_elements expected, alerts
              end
            end

            test "filters by AND'd validities with multiple filter values" do
              assert_query_count(1) do
                ByValidity.new([], %w[active inactive]).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_5_unverifiable, @ss_6_nil_validity]
                assert_same_elements expected, alerts
              end
            end
          end

          context "inclusive and exclusive filters" do
            test "filters by latest validity" do
              assert_query_count(1) do
                ByValidity.new(["active"], ["inactive"]).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_1_unknown, @ss_1_latest_active]
                assert_same_elements expected, alerts
              end
            end

            test "filters by OR'd inclusive validities and AND'd exclusive validities" do
              assert_query_count(1) do
                ByValidity.new(%w[active inactive], ["inactive"]).apply(@ss_rel).to_a
              end.tap do |alerts|
                expected = [@ss_1_unknown, @ss_1_latest_active]
                assert_same_elements expected, alerts
              end

              assert_query_count(0) do
                ByValidity.new(["inactive"], %w[inactive active]).apply(@ss_rel).to_a
              end.tap do |alerts|
                assert_empty alerts
              end
            end

            test "returns no results for conflicting filter values" do
              assert_query_count(0) do
                ByValidity.new(["inactive"], ["inactive"]).apply(@ss_rel).to_a
              end.tap do |alerts|
                assert_empty alerts
              end
            end
          end
        end
      end
    end
  end
end
