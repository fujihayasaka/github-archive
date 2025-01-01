# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module CodeScanning
      class ByStateTest < GitHub::TestCase

        fixtures do
          @unresolved = create(:soa_code_scanning_pr_alert, alert_resolved: false, alert_resolution: nil)
          @false_positive = create(:soa_code_scanning_pr_alert, alert_resolved: true, alert_resolution: Turboscan::Proto::ResultResolution::FALSE_POSITIVE)
          @risk_accepted = create(:soa_code_scanning_pr_alert, alert_resolved: true, alert_resolution: Turboscan::Proto::ResultResolution::WONT_FIX)
          @fixed = create(:soa_code_scanning_pr_alert, alert_resolved: true, alert_resolution: nil)
        end

        setup do
          @rel = CodeScanningPullRequestAlert.all
        end

        context "#apply" do
          test "filters with inclusive filters" do
            assert_query_count(1) do
              ByState.new(["unresolved"], []).apply(@rel).to_a
            end.tap do |results|
              expected = [@unresolved]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByState.new(["dismissed"], []).apply(@rel).to_a
            end.tap do |results|
              expected = [@false_positive, @risk_accepted]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByState.new(["fixed"], []).apply(@rel).to_a
            end.tap do |results|
              expected = [@fixed]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByState.new(%w[unresolved dismissed], []).apply(@rel).to_a
            end.tap do |results|
              expected = [@unresolved, @false_positive, @risk_accepted]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByState.new(["DiSmiSsEd"], []).apply(@rel).to_a
            end.tap do |results|
              expected = [@false_positive, @risk_accepted]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end

          test "filters with exclusive filters" do
            assert_query_count(1) do
              ByState.new([], ["unresolved"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@fixed, @false_positive, @risk_accepted]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByState.new([], ["dismissed"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@unresolved, @fixed]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByState.new([], ["fixed"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@unresolved, @false_positive, @risk_accepted]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByState.new([], %w[fixed dismissed]).apply(@rel).to_a
            end.tap do |results|
              expected = [@unresolved]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByState.new([], ["DiSmiSsEd"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@unresolved, @fixed]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end

          test "filters with both inclusive and exclusive filters" do
            assert_query_count(1) do
              ByState.new(["unresolved"], ["dismissed"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@unresolved]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByState.new(["dismissed"], ["fixed"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@false_positive, @risk_accepted]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByState.new(["dismissed"], ["dismissed"]).apply(@rel).to_a
            end.tap do |results|
              expected = []
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByState.new(%w[dismissed fixed], ["dismissed"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@fixed]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end

          test "filters with unrecognized inclusive filters" do
            assert_query_count(0) do
              ByState.new(["invalid"], []).apply(@rel).to_a
            end.tap do |results|
              expected = []
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end

          test "ignores with unrecognized exclusive filters" do
            assert_query_count(1) do
              ByState.new([], ["invalid"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@unresolved, @false_positive, @risk_accepted, @fixed]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end

          test "ignores empty filters" do
            assert_query_count(1) do
              ByState.new([], []).apply(@rel).to_a
            end.tap do |results|
              expected = [@unresolved, @false_positive, @risk_accepted, @fixed]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end
        end
      end
    end
  end
end
