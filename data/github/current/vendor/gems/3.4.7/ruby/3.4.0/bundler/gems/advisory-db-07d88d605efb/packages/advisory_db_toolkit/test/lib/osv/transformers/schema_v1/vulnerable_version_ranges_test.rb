# frozen_string_literal: true

require "test_helper"

class OSVTransformersSchemaV1VulnerableVersionRangesTest < Minitest::Test
  def setup
    @subject = AdvisoryDBToolkit::OSV::Transformers::SchemaV1::VulnerableVersionRanges
    @last_known_affected_key = "last_known_affected_version_range"
  end

  # last_affected is an official OSV range event type
  # last_known_affected is our custom hinting attribute
  def process_affected(introduced: nil, fixed: nil, versions: [], last_known_affected: nil, last_affected: nil)
    affected = {}
    range = {}
    affected["versions"] = versions if versions.any?
    range["events"] = [{ "introduced" => introduced }] if introduced

    if fixed
      range["events"] ||= []
      range["events"] << { "fixed" => fixed }
    elsif last_affected
      range["events"] ||= []
      range["events"] << { "last_affected" => last_affected }
    end

    if last_known_affected
      affected["database_specific"] = {
        @last_known_affected_key => last_known_affected,
      }
    end

    affected["ranges"] = [range]

    vvr = @subject.new(affected)
    vvr.process_affected
    vvr
  end

  def test_raises_toomanyosvaffectedranges_if_there_is_more_than_one_affected_range
    affected = { "ranges" => [{}, {}] }
    assert_raises(@subject::TooManyOSVAffectedRanges) do
      @subject.new(affected)
    end
  end

  def test_raises_toomanyosvaffectedrangeevents_if_there_is_more_than_one_introduced_range_event
    affected = { "ranges" => [{ "events" => [
      { "introduced" => "1.0.0" },
      { "introduced" => "2.0.0" },
    ] }] }
    assert_raises(@subject::TooManyOSVAffectedRangeEvents) do
      @subject.new(affected)
    end
  end

  def test_raises_toomanyosvaffectedrangeevents_if_there_is_more_than_one_fixed_range_event
    affected = { "ranges" => [{ "events" => [
      { "fixed" => "1.0.1" },
      { "fixed" => "2.0.1" },
    ] }] }
    assert_raises(@subject::TooManyOSVAffectedRangeEvents) do
      @subject.new(affected)
    end
  end

  def test_raises_toomanyosvaffectedversions_if_there_is_more_than_one_explicit_versions_listed
    affected = { "versions" => ["1.0.1", "2.0.1"] }
    assert_raises(@subject::TooManyOSVAffectedVersions) do
      @subject.new(affected)
    end
  end

  def test_raises_unsupportedosvaffectedrangeeventtype_if_there_are_any_range_event_types_for_limit_because_ghsa_does_not_support_it
    affected = { "ranges" => [{ "events" => [
      { "introduced" => "1.0.1" },
      { "fixed" => "2.0.1" },
      { "limit" => "1.0.9" },
    ] }] }
    assert_raises(@subject::UnsupportedOSVAffectedRangeEventType) do
      @subject.new(affected)
    end
  end

  def test_raises_unsupportedosvaffectedrangeeventtype_if_there_are_any_range_event_types_that_do_not_exist
    affected = { "ranges" => [{ "events" => [
      { "introduced" => "1.0.1" },
      { "fixed" => "2.0.1" },
      { "invalid" => "1.0.9" },
    ] }] }
    assert_raises(@subject::UnsupportedOSVAffectedRangeEventType) do
      @subject.new(affected)
    end
  end

  def test_allows_last_affected_as_an_event_type_for_the_range
    affected = { "ranges" => [{ "events" => [
      { "introduced" => "1.0.1" },
      { "last_affected" => "2.0.1" },
    ] }] }

    @subject.new(affected)
  end

  def test_allows_single_version_without_ranges
    affected = { "versions" => ["1.0.1"] }

    @subject.new(affected)
  end

  # JSON Schema validation should have already taken care of validating this,
  # but because the gem json_schema does not validate it (due to lack of support
  # for the latest draft implementation), write this manual check. This check can
  # be removed once the gem that validates the json schema supports the proper validation.
  def test_raises_exclusiveosvaffectedrangeeventtype_if_fixed_and_last_affected_events_both_appear_in_the_events_array
    affected = { "ranges" => [{ "events" => [
      { "fixed" => "2.0.1" },
      { "last_affected" => "2.0.0" },
    ] }] }
    assert_raises(@subject::ExclusiveOSVAffectedRangeEventType) do
      @subject.new(affected)
    end
  end

  ## `< a.b.c`, `> 0, < d.e.f`

  def test__less_than__a_b_c__rehydrates_without_patched_version_from_zeroed_introduced_event_and_rehydration_hint
    vvr = process_affected(introduced: "0", last_known_affected: "< 1.2.3")
    assert_equal ["> 0", "< 1.2.3"], vvr.vulnerable_version_ranges.first
    assert_nil vvr.first_patched_version
  end

  def test__less_than__a_b_c__rehydrates_with_patched_version_from_zeroed_introduced_event_and_fixed_event_without_rehydration_hint
    vvr = process_affected(introduced: "0", fixed: "1.2.3")
    assert_equal ["> 0", "< 1.2.3"], vvr.vulnerable_version_ranges.first
    assert_equal "1.2.3", vvr.first_patched_version
  end

  def test__less_than__a_b_c__rehydrates_with_patched_version_from_zeroed_introduced_event__fixed_event__and_rehydration_hint
    vvr = process_affected(introduced: "0", last_known_affected: "< 1.2.3",
      fixed: "1.2.4")
    assert_equal ["> 0", "< 1.2.3"], vvr.vulnerable_version_ranges.first
    assert_equal "1.2.4", vvr.first_patched_version
  end

  ## `<= a.b.c`, `> 0, <= d.e.f`

  def test__less_than_or_equal__a_b_c__rehydrates_without_patched_version_from_zeroed_introduced_event_and_rehydration_hint
    vvr = process_affected(introduced: "0", last_known_affected: "<= 1.2.3")
    assert_equal ["> 0", "<= 1.2.3"], vvr.vulnerable_version_ranges.first
    assert_nil vvr.first_patched_version
  end

  def test__less_than_or_equal__a_b_c__rehydrates_without_patched_version_from_zeroed_introduced_event_and_last_affected
    vvr = process_affected(introduced: "0", last_affected: "1.2.3")
    assert_equal ["> 0", "<= 1.2.3"], vvr.vulnerable_version_ranges.first
    assert_nil vvr.first_patched_version
  end

  def test__less_than_or_equal__a_b_c__rehydrates_with_patched_version_from_zeroed_introduced_event__fixed_event__and_rehydration_hint
    vvr = process_affected(introduced: "0", last_known_affected: "<= 1.2.3",
      fixed: "1.2.4")
    assert_equal ["> 0", "<= 1.2.3"], vvr.vulnerable_version_ranges.first
    assert_equal "1.2.4", vvr.first_patched_version
  end

  # `= a.b.c`

  def test__equal_to__a_b_c__rehydrates_without_patched_version_from_legacy_format_with_introduced_event_and_lone_version
    vvr = process_affected(introduced: "1.2.3", versions: ["1.2.3"])
    assert_equal ["= 1.2.3"], vvr.vulnerable_version_ranges.first
    assert_nil vvr.first_patched_version
  end

  def test__equal_to__a_b_c__rehydrates_without_patched_version_or_introduced_event_from_lone_version
    vvr = process_affected(versions: ["1.2.3"])
    assert_equal ["= 1.2.3"], vvr.vulnerable_version_ranges.first
    assert_nil vvr.first_patched_version
  end

  def test__equal_to__a_b_c__rehydrates_with_patched_version_from_introduced_event__fixed_event__and_lone_version
    vvr = process_affected(introduced: "1.2.3", versions: ["1.2.3"],
      fixed: "1.2.4")
    assert_equal ["= 1.2.3"], vvr.vulnerable_version_ranges.first
    assert_equal "1.2.4", vvr.first_patched_version
  end

  ## `>= a.b.c`

  def test__greater_than_or_equal__a_b_c__rehydrates_without_patched_version_from_introduced_event_and_no_rehydration_hint
    vvr = process_affected(introduced: "1.2.3")
    assert_equal [">= 1.2.3"], vvr.vulnerable_version_ranges.first
    assert_nil vvr.first_patched_version
  end

  def test__greater_than_or_equal__a_b_c__rehydrates_with_patched_version_from_introduced_and_fixed_events__and_no_rehydration_hint
    vvr = process_affected(introduced: "1.2.3", fixed: "1.2.4")
    assert_equal [">= 1.2.3", "< 1.2.4"], vvr.vulnerable_version_ranges.first
    assert_equal "1.2.4", vvr.first_patched_version
  end

  ## `>= a.b.c, < d.e.f`

  def test__greater_than_or_equal__a_b_c__less_than__d_e_f__rehydrates_without_patched_version_from_introduced_event_and_rehydration_hint
    vvr = process_affected(introduced: "1.2.3", last_known_affected: "< 1.2.4")
    assert_equal [">= 1.2.3", "< 1.2.4"], vvr.vulnerable_version_ranges.first
    assert_nil vvr.first_patched_version
  end

  def test__greater_than_or_equal__a_b_c__less_than__d_e_f__rehydrates_with_patched_version_from_introduced_and_fixed_events__and_no_rehydration_hint
    vvr = process_affected(introduced: "1.2.3", fixed: "1.2.4")
    assert_equal [">= 1.2.3", "< 1.2.4"], vvr.vulnerable_version_ranges.first
    assert_equal "1.2.4", vvr.first_patched_version
  end

  def test__greater_than_or_equal__a_b_c__less_than__d_e_f__rehydrates_with_patched_patched_version_from_introduced_and_fixed_events__and_rehydration_hint
    vvr = process_affected(introduced: "1.2.3", last_known_affected: "< 1.2.4",
      fixed: "1.2.5")
    assert_equal [">= 1.2.3", "< 1.2.4"], vvr.vulnerable_version_ranges.first
    assert_equal "1.2.5", vvr.first_patched_version
  end

  ## `>= a.b.c, <= d.e.f`

  def test__greater_than_or_equal__a_b_c__less_than_or_equal__d_e_f__rehydrates_without_patched_version_from_introduced_event_and_rehydration_hint
    vvr = process_affected(introduced: "1.2.3", last_known_affected: "<= 1.3.0")
    assert_equal [">= 1.2.3", "<= 1.3.0"], vvr.vulnerable_version_ranges.first
    assert_nil vvr.first_patched_version
  end

  def test__greater_than_or_equal__a_b_c__less_than_or_equal__d_e_f__rehydrates_without_patched_version_from_introduced_event_and_last_affected
    vvr = process_affected(introduced: "1.2.3", last_affected: "1.3.0")
    assert_equal [">= 1.2.3", "<= 1.3.0"], vvr.vulnerable_version_ranges.first
    assert_nil vvr.first_patched_version
  end

  def test__greater_than_or_equal__a_b_c__less_than_or_equal__d_e_f__rehydrates_with_patched_version_from_introduced_and_fixed_events__and_rehydration_hint
    vvr = process_affected(introduced: "1.2.3", last_known_affected: "<= 1.3.0",
      fixed: "1.4.0")
    assert_equal [">= 1.2.3", "<= 1.3.0"], vvr.vulnerable_version_ranges.first
    assert_equal "1.4.0", vvr.first_patched_version
  end

  def test_multiple_semver_version_parts_are_supported
    vvr = @subject.new(
      { "ranges" => [{
        "type" => "SEMVER",
        "events" => [
          { "introduced" => "0" }, { "fixed" => "1.11.13" },
          { "introduced" => "1.12.0" }, { "fixed" => "1.12.8" }
        ],
      }] },
    )
    vvr.process_affected

    assert_equal ["< 1.11.13"], vvr.vulnerable_version_ranges[0]
    assert_equal [">= 1.12.0", "< 1.12.8"], vvr.vulnerable_version_ranges[1]
  end

  def test_multiple_semver_version_parts_are_sorted
    vvr = @subject.new(
      { "ranges" => [{
        "type" => "SEMVER",
        "events" => [
          { "introduced" => "3.0.8" }, { "fixed" => "3.1.5" },
          { "introduced" => "4.1.5" }, { "fixed" => "4.3.8" },
          { "introduced" => "2.0.0" }, { "fixed" => "2.9.0" },
          { "introduced" => "1.9.9" }, { "fixed" => "1.99.99" },
          { "introduced" => "0.12.0" }, { "fixed" => "0.20.8" }
        ],
      }] },
    )
    vvr.process_affected

    assert_equal 5, vvr.vulnerable_version_ranges.length
    assert_equal [">= 0.12.0", "< 0.20.8"], vvr.vulnerable_version_ranges[0]
    assert_equal [">= 1.9.9", "< 1.99.99"], vvr.vulnerable_version_ranges[1]
    assert_equal [">= 2.0.0", "< 2.9.0"], vvr.vulnerable_version_ranges[2]
    assert_equal [">= 3.0.8", "< 3.1.5"], vvr.vulnerable_version_ranges[3]
    assert_equal [">= 4.1.5", "< 4.3.8"], vvr.vulnerable_version_ranges[4]
  end
end
