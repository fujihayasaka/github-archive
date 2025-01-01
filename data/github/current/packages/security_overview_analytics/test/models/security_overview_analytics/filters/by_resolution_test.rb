# typed: true
# frozen_string_literal: true

require "test_helper"
require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"
require "turboscan"
require "secret_scanning_proto"

module SecurityOverviewAnalytics
  module Filters
    class ByResolutionTest < GitHub::TestCase
      include ::SecurityOverviewAnalytics::TestFixtures

      fixtures do
        create_alert_fixtures_with_severity_and_resolution
      end

      setup do
        @dbot_rel = DependabotAlertRevision.all
        @cs_rel = CodeScanningAlertRevision.all
        @ss_rel = SecretScanningAlertRevision.all
      end

      context "#apply" do
        context "no filters are provided" do
          test "does not filter on alerts" do
            assert_query_count(1) do
              ByResolution.new([], []).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alerts|
              assert_equal 6, alerts.size
            end
          end
        end

        context "inclusive filters" do
          test "filters by resolution" do
            assert_query_count(1) do
              ByResolution.new(["fixed-or-revoked"], []).apply(@cs_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@cs_5.alert_number]
              assert_same_elements expected, alerts
            end

            assert_query_count(1) do
              ByResolution.new(["auto-dismissed"], []).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@dbot_2.alert_number]
              assert_same_elements expected, alerts
            end
          end

          test "filters by OR'd resolutions with multiple filter values" do
            assert_query_count(1) do
              ByResolution.new(%w[risk-accepted false-positive], []).apply(@cs_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@cs_1.alert_number, @cs_2.alert_number, @cs_3.alert_number]
              assert_same_elements expected, alerts
            end
          end
        end

        context "exclusive filters" do
          test "includes open alerts and alerts with no resolution" do
            assert_query_count(1) do
              ByResolution.new([], ["fixed-or-revoked"]).apply(@cs_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@cs_1.alert_number, @cs_2.alert_number, @cs_3.alert_number, @cs_4.alert_number, @cs_6.alert_number, @cs_7.alert_number]
              assert_same_elements expected, alerts
            end

            assert_query_count(1) do
              ByResolution.new([], ["auto-dismissed"]).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@dbot_1.alert_number, @dbot_3.alert_number, @dbot_4.alert_number, @dbot_5.alert_number, @dbot_6.alert_number]
              assert_same_elements expected, alerts
            end
          end

          test "filters by AND'd resolutions with multiple filter values" do
            assert_query_count(1) do
              ByResolution.new([], %w[risk-accepted false-positive]).apply(@cs_rel).map(&:alert_number)
            end.tap do |alerts|
              expected = [@cs_4.alert_number, @cs_5.alert_number, @cs_6.alert_number, @cs_7.alert_number]
              assert_same_elements expected, alerts
            end
          end
        end

        context "inclusive and exclusive filters" do
          test "filters by resolution" do
            assert_query_count(1) do
              ByResolution.new(["fixed-or-revoked"], ["false-positive"]).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alert_numbers|
              expected = [@dbot_1.alert_number]
              assert_same_elements expected, alert_numbers
            end
          end

          test "filters by OR'd inclusive resolutions and AND'd exclusive resolutions" do
            assert_query_count(1) do
              ByResolution.new(%w[auto-dismissed false-positive], ["false-positive"]).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alert_numbers|
              expected = [@dbot_2.alert_number]
              assert_same_elements expected, alert_numbers
            end

            assert_query_count(1) do
              ByResolution.new(["false-positive"], %w[false-positive risk-accepted]).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alert_numbers|
              assert_empty alert_numbers
            end
          end

          test "returns no results for conflicting filter values" do
            assert_query_count(1) do
              ByResolution.new(["false-positive"], ["false-positive"]).apply(@dbot_rel).map(&:alert_number)
            end.tap do |alert_numbers|
              assert_empty alert_numbers
            end
          end
        end
      end

      context "#is_empty?" do
        test "returns 'true' when provided no filters" do
          assert ByResolution.new([], []).is_empty?
        end

        test "returns 'false' when provided inclusive filters" do
          refute ByResolution.new(["test"], []).is_empty?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByResolution.new([], ["test"]).is_empty?
        end

        test "returns 'false' when provided both inclusive and exclusive filters" do
          refute ByResolution.new(["test"], ["test2"]).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns 'false' when provided no filters" do
          refute ByResolution.new([], []).has_incl_filters?
        end

        test "returns 'true' when provided inclusive filters" do
          assert ByResolution.new(["test"], []).has_incl_filters?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByResolution.new([], ["test"]).has_incl_filters?
        end

        test "returns 'true' when provided both inclusive and exclusive filters" do
          assert ByResolution.new(["test"], ["test2"]).has_incl_filters?
        end
      end
    end
  end
end
