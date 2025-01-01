# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Notifications
  class EvaluatorTest < GitHub::TestCase
    test "returns results for highest thresholds" do
      evaluator = Evaluator.new(thresholds: [5, 10, 20])
      evaluator.add_case { 1 }
      evaluator.add_case { 5 }
      evaluator.add_case { 21 }
      results = evaluator.results
      assert_equal 2, results.size
      assert_equal 21, results[0].value
      assert_equal 20, results[0].threshold
      assert_equal 5, results[1].value
      assert_equal 5, results[1].threshold
    end

    test "sorts thresholds in the event they're out of order" do
      evaluator = Evaluator.new(thresholds: [10, 5, 20])
      evaluator.add_case { 11 }
      evaluator.add_case { 21 }
      results = evaluator.results
      assert_equal 2, results.size
      assert_equal 21, results[0].value
      assert_equal 20, results[0].threshold
      assert_equal 11, results[1].value
      assert_equal 10, results[1].threshold
    end

    test "skips evaluations with nil result" do
      evaluator = Evaluator.new(thresholds: [5])
      evaluator.add_case { 5 }
      evaluator.add_case { nil }
      assert_equal [5], evaluator.results.map(&:value)
    end

    test "returns empty array if no cases cross a threshold" do
      evaluator = Evaluator.new(thresholds: [5])
      evaluator.add_case { 1 }
      evaluator.add_case { 2 }
      assert_equal [], evaluator.results
    end

    test "can add cases with tags and optionally run certain tags" do
      evaluator = Evaluator.new(thresholds: [5, 10, 20])
      evaluator.add_case { 1 }
      evaluator.add_case(:tag1) { 5 }
      evaluator.add_case(:tag1, :tag2) { 11 }
      evaluator.add_case(:tag3) { 21 }
      assert_equal [21, 11, 5], evaluator.results.map(&:value)
      assert_equal [11, 5], evaluator.results(tags: :tag1).map(&:value)
      tag3_results = evaluator.results(tags: :tag3)
      assert_equal [21], tag3_results.map(&:value)
      assert_equal [:tag3], tag3_results.first.tags
    end

    test "rules can also have context set" do
      evaluator = Evaluator.new(thresholds: [0])
      evaluator.add_case do |context|
        context[:custom] = "only in 1"
        1
      end
      evaluator.add_case(:tag1) { 5 }
      results = evaluator.results
      assert_equal 5, results[0].value
      assert_equal({}, results[0].context)

      assert_equal 1, results[1].value
      assert_equal({ custom: "only in 1" }, results[1].context)
    end
  end
end
