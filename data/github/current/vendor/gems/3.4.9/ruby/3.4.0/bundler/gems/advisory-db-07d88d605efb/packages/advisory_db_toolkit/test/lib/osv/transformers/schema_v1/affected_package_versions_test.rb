# frozen_string_literal: true

require "test_helper"

class OSVTransformersSchemaV1AffectedPackageVersionsTest < Minitest::Test
  def setup
    @subject = AdvisoryDBToolkit::OSV::Transformers::SchemaV1::AffectedPackageVersions
  end

  def process_vulnerability(vulnerability, first_patched = nil)
    parsed_range = AdvisoryDBToolkit::OSV::Transformers::SchemaV1::ParsedRange.parse(vulnerability)
    affected_versions = @subject.new
    affected_versions.process_vulnerability(parsed_range, first_patched)
    affected_versions.finalize
    affected_versions
  end

  ## `< a.b.c`

  def test__less_than__a_b_c__range_without_patched_version_adds_zeroed_introduced_event_and_rehydration_hint
    affected = process_vulnerability("< 1.2.3", nil)
    assert_equal [{ "introduced" => "0" }], affected.events
    assert_equal({ "last_known_affected_version_range" => "< 1.2.3" },
      affected.extra)
    assert_empty affected.versions
  end

  def test__less_than__a_b_c__range_with_matching_patched_version_adds_zeroed_introduced_event__fixed_event__and_no_rehydration_hint
    affected = process_vulnerability("< 1.2.3", "1.2.3")
    assert_equal [
      { "introduced" => "0" },
      { "fixed" => "1.2.3" },
    ], affected.events
    assert_empty affected.extra
    assert_empty affected.versions
  end

  def test__less_than__a_b_c__range_with_mismatched_patched_version_adds_zeroed_introduced_event__fixed_event__and_rehydration_hint
    affected = process_vulnerability("< 1.2.3", "1.2.4")
    assert_equal [
      { "introduced" => "0" },
      { "fixed" => "1.2.4" },
    ], affected.events
    assert_equal({ "last_known_affected_version_range" => "< 1.2.3" },
      affected.extra)
    assert_empty affected.versions
  end

  ## `<= a.b.c`

  def test__less_than_or_equal__a_b_c__range_without_patched_version_adds_zeroed_introduced_event_and_last_affected_event
    affected = process_vulnerability("<= 1.2.3", nil)
    assert_equal [{ "introduced" => "0" }, { "last_affected" => "1.2.3" }], affected.events
    assert_equal({},
      affected.extra)
    assert_empty affected.versions
  end

  def test__less_than_or_equal__a_b_c__range_with_patched_version_adds_zeroed_introduced_event__fixed_event__and_rehydration_hint
    affected = process_vulnerability("<= 1.2.3", "1.2.4")
    assert_equal [
      { "introduced" => "0" },
      { "fixed" => "1.2.4" },
    ], affected.events
    assert_equal({ "last_known_affected_version_range" => "<= 1.2.3" },
      affected.extra)
    assert_empty affected.versions
  end

  # `= a.b.c`

  def test__equal_to__a_b_c__range_without_patched_version_does_not_add_introduced_event_but_appends_to__versions__for_rehydration
    affected = process_vulnerability("= 1.2.3", nil)
    assert_empty affected.events
    assert_empty affected.extra
    assert_equal ["1.2.3"], affected.versions
  end

  def test__equal_to__a_b_c__range_with_patched_version_adds_introduced_and_fixed_events__and_appends_to__versions__for_rehydration
    affected = process_vulnerability("= 1.2.3", "1.2.4")
    assert_equal [
      { "introduced" => "1.2.3" },
      { "fixed" => "1.2.4" },
    ], affected.events
    assert_empty affected.extra
    assert_equal ["1.2.3"], affected.versions
  end

  ## `> a.b.c`

  def test__greater_than__0__range_without_patched_version_adds_zeroed_introduced_event_and_no_rehydration_hint
    affected = process_vulnerability("> 0", nil)
    assert_equal [{ "introduced" => "0" }], affected.events
    assert_empty affected.extra
    assert_empty affected.versions
  end

  def test__greater_than__0__range_with_patched_version_adds_zeroed_introduced_event__fixed_event__and_no_rehydration_hint
    affected = process_vulnerability("> 0", "1.2.3")
    assert_equal [
      { "introduced" => "0" },
      { "fixed" => "1.2.3" },
    ], affected.events
    assert_empty affected.extra
    assert_empty affected.versions
  end

  def test__greater_than__a_b_c__range_other_than__greater_than__0__raises_an_error
    assert_raises(@subject::RangeOperatorError) do
      process_vulnerability("> 0.1.2", nil)
    end
  end

  ## `> a.b.c, < d.e.f`

  def test__greater_than__0__less_than__d_e_f__range_without_patched_version_adds_zeroed_introduced_event_and_rehydration_hint
    affected = process_vulnerability("> 0, < 1.2.3", nil)
    assert_equal [{ "introduced" => "0" }], affected.events
    assert_equal({ "last_known_affected_version_range" => "< 1.2.3" },
      affected.extra)
    assert_empty affected.versions
  end

  def test__greater_than__0__less_than__d_e_f__range_with_matching_patched_version_adds_zeroed_introduced_event__fixed_event__and_no_rehydration_hint
    affected = process_vulnerability("> 0, < 1.2.3", "1.2.3")
    assert_equal [
      { "introduced" => "0" },
      { "fixed" => "1.2.3" },
    ], affected.events
    assert_empty affected.extra
    assert_empty affected.versions
  end

  def test__greater_than__0__less_than__d_e_f__range_with_mismatched_patched_version_adds_zeroed_introduced_event__fixed_event__and_rehydration_hint
    affected = process_vulnerability("> 0, < 1.2.3", "1.2.4")
    assert_equal [
      { "introduced" => "0" },
      { "fixed" => "1.2.4" },
    ], affected.events
    assert_equal({ "last_known_affected_version_range" => "< 1.2.3" },
      affected.extra)
    assert_empty affected.versions
  end

  def test__greater_than__a_b_c__less_than__d_e_f__range_other_than__greater_than__0__less_than__d_e_f__raises_an_error
    assert_raises(@subject::RangeOperatorError) do
      process_vulnerability("> 0.1.2, < 1.2.3", nil)
    end
  end

  ## `> a.b.c, <= d.e.f`

  def test__greater_than__0__less_than_or_equal__d_e_f__range_without_patched_version_adds_zeroed_introduced_event_and_last_affected_event
    affected = process_vulnerability("> 0, <= 1.2.3", nil)
    assert_equal [{ "introduced" => "0" }, { "last_affected" => "1.2.3" }], affected.events
    assert_equal({},
      affected.extra)
    assert_empty affected.versions
  end

  def test__greater_than__0__less_than_or_equal__d_e_f__range_with_patched_version_adds_zeroed_introduced_event__fixed_event__and_rehydration_hint
    affected = process_vulnerability("> 0, <= 1.2.3", "1.2.4")
    assert_equal [
      { "introduced" => "0" },
      { "fixed" => "1.2.4" },
    ], affected.events
    assert_equal({ "last_known_affected_version_range" => "<= 1.2.3" },
      affected.extra)
    assert_empty affected.versions
  end

  def test__greater_than__a_b_c__less_than_or_equal__d_e_f__range_other_than__greater_than__0__less_than_or_equal__d_e_f__raises_an_error
    assert_raises(@subject::RangeOperatorError) do
      process_vulnerability("> 0.1.2, <= 1.2.3", nil)
    end
  end

  ## `>= a.b.c`

  def test__greater_than_or_equal__a_b_c__range_without_patched_version_adds_introduced_event_and_no_rehydration_hint
    affected = process_vulnerability(">= 1.2.3", nil)
    assert_equal [{ "introduced" => "1.2.3" }], affected.events
    assert_empty affected.extra
    assert_empty affected.versions
  end

  def test__greater_than_or_equal__a_b_c__range_with_patched_version_adds_introduced_and_fixed_events__and_no_rehydration_hint
    affected = process_vulnerability(">= 1.2.3", "1.2.4")
    assert_equal [
      { "introduced" => "1.2.3" },
      { "fixed" => "1.2.4" },
    ], affected.events
    assert_empty affected.extra
    assert_empty affected.versions
  end

  ## `>= a.b.c, < d.e.f`

  def test__greater_than_or_equal__a_b_c__less_than__d_e_f__range_without_patched_version_adds_introduced_event_and_rehydration_hint
    affected = process_vulnerability(">= 1.2.3, < 1.2.4", nil)
    assert_equal [{ "introduced" => "1.2.3" }], affected.events
    assert_equal({ "last_known_affected_version_range" => "< 1.2.4" },
      affected.extra)
    assert_empty affected.versions
  end

  def test__greater_than_or_equal__a_b_c__less_than__d_e_f__range_with_matching_patched_version_adds_introduced_and_fixed_events__and_no_rehydration_hint
    affected = process_vulnerability(">= 1.2.3, < 1.2.4", "1.2.4")
    assert_equal [
      { "introduced" => "1.2.3" },
      { "fixed" => "1.2.4" },
    ], affected.events
    assert_empty affected.extra
    assert_empty affected.versions
  end

  def test__greater_than_or_equal__a_b_c__less_than__d_e_f__range_with_mismatched_patched_version_adds_introduced_and_fixed_events__and_rehydration_hint
    affected = process_vulnerability(">= 1.2.3, < 1.2.4", "1.2.5")
    assert_equal [
      { "introduced" => "1.2.3" },
      { "fixed" => "1.2.5" },
    ], affected.events
    assert_equal({ "last_known_affected_version_range" => "< 1.2.4" },
      affected.extra)
    assert_empty affected.versions
  end

  ## `>= a.b.c, <= d.e.f`

  def test__greater_than_or_equal__a_b_c__less_than_or_equal__d_e_f__range_without_patched_version_adds_introduced_and_last_affected_events
    affected = process_vulnerability(">= 1.2.3, <= 1.3.0", nil)
    assert_equal [{ "introduced" => "1.2.3" }, { "last_affected" => "1.3.0" }], affected.events
    assert_equal({},
      affected.extra)
    assert_empty affected.versions
  end

  def test__greater_than_or_equal__a_b_c__less_than_or_equal__d_e_f__range_with_patched_version_adds_introduced_and_fixed_events__and_rehydration_hint
    affected = process_vulnerability(">= 1.2.3, <= 1.3.0", "1.4.0")
    assert_equal [
      { "introduced" => "1.2.3" },
      { "fixed" => "1.4.0" },
    ], affected.events
    assert_equal({ "last_known_affected_version_range" => "<= 1.3.0" },
      affected.extra)
    assert_empty affected.versions
  end
end
