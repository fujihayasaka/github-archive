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

    test "matches item value with parentheses" do
      comparator = MemexProject::Comparator.new(["Done"])
      refute comparator.matches?("Done (Maybe)"), "Expected not to match 'Done' prefix without wildcard"

      comparator = MemexProject::Comparator.new(["Done ("])
      refute comparator.matches?("Done (Maybe)"), "Expected not to match 'Done (' prefix without wildcard"

      comparator = MemexProject::Comparator.new(["Done (*"])
      assert comparator.matches?("Done (Maybe)"), "Expected to match 'Done (*' prefix with wildcard"

      comparator = MemexProject::Comparator.new(["Done (*)"])
      assert comparator.matches?("Done (Maybe)"), "Expected to match 'Done (*' prefix with wildcard"

      comparator = MemexProject::Comparator.new(["Done (Maybe)"])
      assert comparator.matches?("Done (Maybe)"), "Expected to match 'Done (Maybe)' exactly"
    end

    test "matches item value with invalid regex characters" do
      item_value = "Confidence (+1/-1 week)"
      comparator = MemexProject::Comparator.new(["Confidence"])
      refute comparator.matches?(item_value), "Expected not to match 'Confidence' prefix without wildcard"

      comparator = MemexProject::Comparator.new(["Confidence (+1"])
      refute comparator.matches?(item_value), "Expected not to match 'Confidence (+1' prefix without wildcard"

      comparator = MemexProject::Comparator.new(["Confidence (+1*"])
      assert comparator.matches?(item_value), "Expected to match 'Confidence (+1*' prefix with wildcard"

      comparator = MemexProject::Comparator.new([item_value])
      assert comparator.matches?(item_value), "Expected to match 'Confidence (+1/-1 week)' exactly"
    end

    test "matches item value containing wildcard" do
      item_value = "Wild*Card"
      comparator = MemexProject::Comparator.new(["Wild"])
      refute comparator.matches?(item_value), "Expected not to match 'Wild' prefix"

      comparator = MemexProject::Comparator.new(["Wild*"])
      assert comparator.matches?(item_value), "Expected to match 'Wild*' prefix with wildcard"

      comparator = MemexProject::Comparator.new(["Wi*"])
      assert comparator.matches?(item_value), "Expected to match 'Wi' prefix with wildcard"

      comparator = MemexProject::Comparator.new([item_value])
      assert comparator.matches?(item_value), "Expected to match 'Wild*Card' exactly"
    end
  end
end
