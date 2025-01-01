# typed: true
# frozen_string_literal: true
require "test_helper"

class MemexProjectComparatorTest < GitHub::TestCase
  setup do
    @comparator = MemexProject::Comparator.new(%w[fOo bar baz mcfly])
  end

  context "#matches?" do
    test "exact value returns true" do
      assert @comparator.matches?("fOo")
    end

    test "case-different value returns true" do
      assert @comparator.matches?("FoO")
    end

    test "different value returns false" do
      refute @comparator.matches?("i-dont-exist")
    end

    test "wildcard value matches predictably" do
      positive_test_cases = {
        "ba*" => "bar",
        "*f*" => "mcfly",
        "*ar" => "bar",
        "*" => "whatever",
      }
      positive_test_cases.each do |filter_value, item_value|
        assert MemexProject::Comparator.new([filter_value]).matches?(item_value), "Expected #{item_value} to match #{filter_value}"
      end

      refute MemexProject::Comparator.new(["c*"]).matches?("not-a-match")
    end
  end
end
