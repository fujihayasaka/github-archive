# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module CodeScanning
      class ByAutofixStatusTest < GitHub::TestCase

        fixtures do
          @autofix_accepted = create(:soa_code_scanning_pr_alert, has_autofix: true, autofix_accepted: true)
          @autofix_suggested = create(:soa_code_scanning_pr_alert, has_autofix: true, autofix_accepted: false)
          @autofix_not_suggested = create(:soa_code_scanning_pr_alert, has_autofix: false, autofix_accepted: false)
        end

        setup do
          @rel = CodeScanningPullRequestAlert.all
        end

        context "#apply" do
          test "filters with inclusive filters" do
            assert_query_count(1) do
              ByAutofixStatus.new(["accepted"], []).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_accepted]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByAutofixStatus.new(["suggested"], []).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_accepted, @autofix_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByAutofixStatus.new(["not-suggested"], []).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_not_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByAutofixStatus.new(["SuGgEsTeD"], []).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_accepted, @autofix_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end

          test "filters with exclusive filters" do
            assert_query_count(1) do
              ByAutofixStatus.new([], ["accepted"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_suggested, @autofix_not_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByAutofixStatus.new([], ["suggested"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_not_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByAutofixStatus.new([], ["not-suggested"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_accepted, @autofix_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByAutofixStatus.new([], ["SuGgEsTeD"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_not_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end

          test "filters with both inclusive and exclusive filters" do
            assert_query_count(1) do
              ByAutofixStatus.new(["accepted"], ["suggested"]).apply(@rel).to_a
            end.tap do |results|
              expected = []
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByAutofixStatus.new(["suggested"], ["accepted"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByAutofixStatus.new(["suggested"], ["not-suggested"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_accepted, @autofix_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end

            assert_query_count(1) do
              ByAutofixStatus.new(["not-suggested"], ["suggested"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_not_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end

          test "filters with unrecognized inclusive filters" do
            assert_query_count(0) do
              ByAutofixStatus.new(["invalid"], []).apply(@rel).to_a
            end.tap do |results|
              expected = []
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end

          test "ignores with unrecognized exclusive filters" do
            assert_query_count(1) do
              ByAutofixStatus.new([], ["invalid"]).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_accepted, @autofix_suggested, @autofix_not_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end

          test "ignores empty filters" do
            assert_query_count(1) do
              ByAutofixStatus.new([], []).apply(@rel).to_a
            end.tap do |results|
              expected = [@autofix_accepted, @autofix_suggested, @autofix_not_suggested]
              assert_same_elements expected.map(&:id), results.map(&:id)
            end
          end
        end
      end
    end
  end
end
