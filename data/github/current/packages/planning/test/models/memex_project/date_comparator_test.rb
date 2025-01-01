# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectDateComparatorTest < GitHub::TestCase
  context "when filter value has no relational operator" do
    test "exact value returns true" do
      comparator = MemexProject::DateComparator.new(%w[2020-01-02])

      assert comparator.matches?("2020-01-02")
    end

    test "inexact value returns false" do
      comparator = MemexProject::DateComparator.new(%w[2020-01-02])

      refute comparator.matches?("2020-01-03")
    end
  end

  context "when filter value has 'less than' relational operator" do
    test "lesser value returns true" do
      comparator = MemexProject::DateComparator.new(%w[<2020-01-02])

      assert comparator.matches?("2019-01-02")
    end

    test "equal value returns false" do
      comparator = MemexProject::DateComparator.new(%w[<2020-01-02])

      refute comparator.matches?("2020-01-02")
    end

    test "greater value returns false" do
      comparator = MemexProject::DateComparator.new(%w[<2020-01-02])

      refute comparator.matches?("2021-01-02")
    end
  end

  context "when filter_value contains quote characters" do
    test "surrounding double quotes does not affect filter_value parsing" do
      comparator = MemexProject::DateComparator.new(%w["<=2020-01-02"])

      assert comparator.matches?("2020-01-02")
    end

    test "surrounding single quotes does not affect filter_value parsing" do
      comparator = MemexProject::DateComparator.new(%w['<=2020-01-02'])

      assert comparator.matches?("2020-01-02")
    end

    test "inside double quotes does not affect filter_value parsing" do
      comparator = MemexProject::DateComparator.new(%w[<="2020-01-02"])

      assert comparator.matches?("2020-01-02")
    end

    test "inside single quotes does not affect filter_value parsing" do
      comparator = MemexProject::DateComparator.new(%w[<='2020-01-02'])

      assert comparator.matches?("2020-01-02")
    end
  end

  context "when filter value has 'less than or equal to' relational operator" do
    test "lesser value returns true" do
      comparator = MemexProject::DateComparator.new(%w[<=2020-01-02])

      assert comparator.matches?("2019-01-02")
    end

    test "equal value returns true" do
      comparator = MemexProject::DateComparator.new(%w[<=2020-01-02])

      assert comparator.matches?("2020-01-02")
    end

    test "greater value returns false" do
      comparator = MemexProject::DateComparator.new(%w[<=2020-01-02])

      refute comparator.matches?("2021-01-02")
    end
  end

  context "when filter value has 'greater than' relational operator" do
    test "greater value returns true" do
      comparator = MemexProject::DateComparator.new(%w[>2020-01-02])

      assert comparator.matches?("2021-01-02")
    end

    test "equal value returns false" do
      comparator = MemexProject::DateComparator.new(%w[>2020-01-02])

      refute comparator.matches?("2020-01-02")
    end

    test "lesser value returns false" do
      comparator = MemexProject::DateComparator.new(%w[>2020-01-02])

      refute comparator.matches?("2019-01-02")
    end
  end

  context "when filter value has 'greater than or equal to' relational operator" do
    test "greater value returns true" do
      comparator = MemexProject::DateComparator.new(%w[>=2020-01-02])

      assert comparator.matches?("2021-01-02")
    end

    test "equal value returns true" do
      comparator = MemexProject::DateComparator.new(%w[>=2020-01-02])

      assert comparator.matches?("2020-01-02")
    end

    test "lesser value returns false" do
      comparator = MemexProject::DateComparator.new(%w[>=2020-01-02])

      refute comparator.matches?("2019-01-02")
    end
  end

  context "when filter value has 'range' relational operator with start and end dates" do
    test "equal to start value returns true" do
      comparator = MemexProject::DateComparator.new(%w[2020-01-02..2021-01-02])

      assert comparator.matches?("2020-01-02")
    end

    test "equal to end value returns true" do
      comparator = MemexProject::DateComparator.new(%w[2020-01-02..2021-01-02])

      assert comparator.matches?("2021-01-02")
    end

    test "value between returns true" do
      comparator = MemexProject::DateComparator.new(%w[2020-01-02..2021-01-02])

      assert comparator.matches?("2020-10-10")
    end

    test "value before start returns false" do
      comparator = MemexProject::DateComparator.new(%w[2020-01-02..2021-01-02])

      refute comparator.matches?("2019-01-01")
    end

    test "value after end returns false" do
      comparator = MemexProject::DateComparator.new(%w[2020-01-02..2021-01-02])

      refute comparator.matches?("2022-01-01")
    end
  end

  context "when filter value has 'range' relational operator with just a start date" do
    test "equal to start value returns true" do
      comparator = MemexProject::DateComparator.new(%w[2020-01-02..])

      assert comparator.matches?("2020-01-02")
    end

    test "value greater than start date returns true" do
      comparator = MemexProject::DateComparator.new(%w[2020-01-02..])

      assert comparator.matches?("2099-01-02")
    end

    test "value before start returns false" do
      comparator = MemexProject::DateComparator.new(%w[2020-01-02..])

      refute comparator.matches?("2019-01-01")
    end

    test "if the end date is an asterisk then value greater will return true" do
      comparator = MemexProject::DateComparator.new(%w[2020-01-02..*])

      assert comparator.matches?("2099-01-02")
    end
  end

  context "when filter value has 'range' relational operator with just an end date" do
    test "equal to end value returns true" do
      comparator = MemexProject::DateComparator.new(%w[..2020-01-02])

      assert comparator.matches?("2020-01-02")
    end

    test "value less than end date returns true" do
      comparator = MemexProject::DateComparator.new(%w[..2020-01-02])

      assert comparator.matches?("2019-01-02")
    end

    test "value after end date returns false" do
      comparator = MemexProject::DateComparator.new(%w[..2020-01-02])

      refute comparator.matches?("2021-01-01")
    end

    test "if the start date is an asterisk then a lesser value will return true" do
      comparator = MemexProject::DateComparator.new(%w[*..2020-01-02])

      assert comparator.matches?("2019-01-02")
    end
  end

  context "when filter value has 'range' relational operator with no dates" do
    test "any date returns true" do
      comparator = MemexProject::DateComparator.new(%w[..])

      assert comparator.matches?("2122-01-01")
      assert comparator.matches?("1776-07-04")
    end

    test "if both dates are an asterisk then any date returns true" do
      comparator = MemexProject::DateComparator.new(%w[*..*])

      assert comparator.matches?("1934-01-02")
    end
  end
end
