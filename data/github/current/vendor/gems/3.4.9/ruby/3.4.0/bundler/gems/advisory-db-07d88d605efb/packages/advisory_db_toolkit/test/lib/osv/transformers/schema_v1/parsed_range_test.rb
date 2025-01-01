# frozen_string_literal: true

require "test_helper"

class OSVTransformersSchemaV1ParsedRangeTest < Minitest::Test
  def setup
    @subject = AdvisoryDBToolkit::OSV::Transformers::SchemaV1::ParsedRange
  end

  def test_parses_exact_version_ranges_from_a_string_to_a_versionspec
    exact_range = "= 1.2.3"
    parsed_range = @subject.parse(exact_range)
    assert_kind_of AdvisoryDBToolkit::OSV::Transformers::SchemaV1::VersionSpec,
      parsed_range.exact
    assert_equal "=", parsed_range.exact.operator
    assert_equal "1.2.3", parsed_range.exact.version

    specific_version = "1.2.3"
    parsed_range = @subject.parse(specific_version)
    assert_equal "=", parsed_range.exact.operator
    assert_equal "1.2.3", parsed_range.exact.version
  end

  def test_parses_lower_bound_version_ranges_from_a_string_to_a_versionspec
    gt_range = "> 1.2.3"
    parsed_range = @subject.parse(gt_range)
    assert_kind_of AdvisoryDBToolkit::OSV::Transformers::SchemaV1::VersionSpec,
      parsed_range.lower
    assert_equal ">", parsed_range.lower.operator
    assert_equal "1.2.3", parsed_range.lower.version

    gte_range = ">= 1.2.3"
    parsed_range = @subject.parse(gte_range)
    assert_equal ">=", parsed_range.lower.operator
    assert_equal "1.2.3", parsed_range.lower.version
  end

  def test_parses_upper_bound_version_ranges_from_a_string_to_a_versionspec
    lt_range = "< 1.2.3"
    parsed_range = @subject.parse(lt_range)
    assert_kind_of AdvisoryDBToolkit::OSV::Transformers::SchemaV1::VersionSpec,
      parsed_range.upper
    assert_equal "<", parsed_range.upper.operator
    assert_equal "1.2.3", parsed_range.upper.version

    lte_range = "<= 1.2.3"
    parsed_range = @subject.parse(lte_range)
    assert_equal "<=", parsed_range.upper.operator
    assert_equal "1.2.3", parsed_range.upper.version
  end

  def test_raises_an_error_if_the_string_contains_an_exact_and_lower_range
    exact_and_gt_range = "> 1.2.3, = 4.5.6"
    assert_raises(@subject::RangeParsingError) do
      @subject.parse(exact_and_gt_range)
    end
  end

  def test_raises_an_error_if_the_string_contains_an_exact_and_upper_range
    exact_and_lt_range = "= 1.2.3, < 4.5.6"
    assert_raises(@subject::RangeParsingError) do
      @subject.parse(exact_and_lt_range)
    end
  end

  def test_doesnt_raise_if_the_string_contains_only_lower_and_upper_ranges
    lt_and_gt_range = "> 1.2.3, < 4.5.6"
    parsed_range = @subject.parse(lt_and_gt_range)
    assert_equal ">", parsed_range.lower.operator
    assert_equal "1.2.3", parsed_range.lower.version
    assert_equal "<", parsed_range.upper.operator
    assert_equal "4.5.6", parsed_range.upper.version
  end
end
