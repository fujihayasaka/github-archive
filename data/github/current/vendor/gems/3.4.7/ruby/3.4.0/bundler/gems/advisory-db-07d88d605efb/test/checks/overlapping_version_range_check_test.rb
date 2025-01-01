# frozen_string_literal: true

require "test_helper"

class OverlappingVersionRangeCheckTest < ActiveSupport::TestCase
  test "Check passes for normal range patterns" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: ">= 2.0.0, <= 2.1.3",
          first_patched_version: "2.1.4",
          withdrawn: false,
        },
        1 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: ">= 3.0.0, < 3.3.3",
          first_patched_version: "3.3.3",
          withdrawn: false,
        },
        2 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: "= 4.1.0",
          first_patched_version: "4.1.1",
          withdrawn: false,
        },
        3 => {
          ecosystem: "npm",
          package_name: "another_package",
          vulnerable_version_range: "< 3.4.5",
          first_patched_version: "3.4.5",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = OverlappingVersionRangeCheck.execute_check(review: advisory_review)

    assert result.passed?
  end

  test "Check ignores ranges from different packages" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: "< 1.0.0",
          first_patched_version: "1.0.0",
          withdrawn: false,
        },
        1 => {
          ecosystem: "npm",
          package_name: "another_package",
          vulnerable_version_range: "< 1.0.0",
          first_patched_version: "1.0.0",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = OverlappingVersionRangeCheck.execute_check(review: advisory_review)

    assert result.passed?
  end

  test "Check ignores ranges from different ecosystems" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: "< 1.0.0",
          first_patched_version: "1.0.0",
          withdrawn: false,
        },
        1 => {
          ecosystem: "rubygems",
          package_name: "example_package",
          vulnerable_version_range: "< 1.0.0",
          first_patched_version: "1.0.0",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = OverlappingVersionRangeCheck.execute_check(review: advisory_review)

    assert result.passed?
  end

  test "Rediculous version ranges still pass" do
    # A set of ranges where the only difference is the operators
    # This is still technically valid
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: "< 1.0.0",
          first_patched_version: "1.0.0",
          withdrawn: false,
        },
        1 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: "> 1.0.0",
          first_patched_version: nil,
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = OverlappingVersionRangeCheck.execute_check(review: advisory_review)

    assert result.passed?
  end

  test "Check fails when there are multiple less than ranges" do
    # ---- < A
    # -------- < B
    # Both version ranges are using less than '<'
    # Range B overlaps range A

    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: "< 3.0.7",
          first_patched_version: "",
          withdrawn: false,
        },
        1 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: "< 4.0.14",
          first_patched_version: "",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = OverlappingVersionRangeCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "Vulnerable version range overlap", result.title
    assert_equal "Vulnerable version range < 3.0.7 overlapps range < 4.0.14", result.summary
  end

  test "Check fails when version ranges overlap each other" do
    # > A ---- < B
    #    > C ---- < D
    # Both version ranges are overlapping
    # Version numbers B and C need to be checked

    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: ">= 2.0.0, <= 2.1.3",
          first_patched_version: "",
          withdrawn: false,
        },
        1 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: ">= 2.1.0, < 2.2.0",
          first_patched_version: "",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = OverlappingVersionRangeCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "Vulnerable version range overlap", result.title
    assert_equal "Vulnerable version range >= 2.0.0, <= 2.1.3 overlapps range >= 2.1.0, < 2.2.0", result.summary
  end

  test "Check fails when a range overlapps a fixed version" do
    # > A ---- < B C
    #         > D ---- < E
    # Patched version C is within a range
    # Both C and D version numbers need to be checked

    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: ">= 2.0.0, < 2.1.3",
          first_patched_version: "2.2.0",
          withdrawn: false,
        },
        1 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: ">= 2.2.0, < 2.3.0",
          first_patched_version: "2.3.0",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = OverlappingVersionRangeCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "Vulnerable version range overlap", result.title
    assert_equal "Vulnerable version range >= 2.2.0, < 2.3.0 contains first patched version 2.2.0", result.summary
  end

  test "Check fails when ranges are identical" do
    # ---- < A
    # ---- < B
    # Both ranges need to be checked

    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: "< 1.0.0",
          first_patched_version: "1.0.0",
          withdrawn: false,
        },
        1 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: "< 1.0.0",
          first_patched_version: "1.0.0",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = OverlappingVersionRangeCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "Vulnerable version range overlap", result.title
    assert_equal "Vulnerable version range < 1.0.0 overlapps range < 1.0.0", result.summary
  end

  test "Check fails when one range completely covers another" do
    # > A ----------- < B
    #     > C -- < D
    # Both ranges need to be checked

    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: ">= 1.0.0, < 4.0.0",
          first_patched_version: "5.0.0",
          withdrawn: false,
        },
        1 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: ">= 2.0.0, < 3.0.0",
          first_patched_version: "",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = OverlappingVersionRangeCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "Vulnerable version range overlap", result.title
    assert_equal "Vulnerable version range >= 1.0.0, < 4.0.0 overlapps range >= 2.0.0, < 3.0.0", result.summary
  end
end
