# frozen_string_literal: true

require "test_helper"

class UnusualVersionRangeCheckTest < ActiveSupport::TestCase
  test "returns a passed CheckResult the review file has normal range patterns" do
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
          vulnerable_version_range: "< 3.3.3",
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
          vulnerable_version_range: "<= 3.4.5",
          first_patched_version: "",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = UnusualVersionRangeCheck.execute_check(review: advisory_review)

    assert result.passed?
  end

  test "returns a passed CheckResult when all versions are affected and no patched version" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "all_versions_package",
          vulnerable_version_range: ">= 0.0.0",
          first_patched_version: nil,
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = UnusualVersionRangeCheck.execute_check(review: advisory_review)

    assert result.passed?
  end

  test "returns a failed CheckResult when range has pattern of `> 1.2.3` where floor version is > 0" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: "> 1.2.3",
          first_patched_version: "1.2.3",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = UnusualVersionRangeCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "One or more versions ranges do not look reasonable", result.title
    assert_equal "Vulnerable version range > 1.2.3 has no max version, but there is a first_patched_version defined", result.summary
  end

  test "returns a failed CheckResult when range has lower uppper version than lower version" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: ">= 2.0.0, < 1.9.9",
          first_patched_version: "",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = UnusualVersionRangeCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "One or more versions ranges do not look reasonable", result.title
    assert_equal "Vulnerable version range >= 2.0.0, < 1.9.9 upper version is not higher than lower version", result.summary
  end

  test "returns a failed CheckResults when range has fix version that is less than upper version" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: ">= 2.0.0, < 2.3.4",
          first_patched_version: "2.2.4",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = UnusualVersionRangeCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "One or more versions ranges do not look reasonable", result.title
    assert_equal "Vulnerable version range >= 2.0.0, < 2.3.4 contains first patched version 2.2.4", result.summary
  end

  test "returns a failed CheckResults when range has fix version that is less than version range" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: ">= 2.0.0, < 2.3.4",
          first_patched_version: "1.2.4",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = UnusualVersionRangeCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "One or more versions ranges do not look reasonable", result.title
    assert_equal "Vulnerable version range >= 2.0.0, < 2.3.4 is above first patched version 1.2.4", result.summary
  end

  test "returns a failed CheckResults when range has fix version that equals the only version" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "npm",
          package_name: "example_package",
          vulnerable_version_range: "= 1.2.3",
          first_patched_version: "1.2.3",
          withdrawn: false,
        },
      },
    }.deep_stringify_keys)

    result = UnusualVersionRangeCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "One or more versions ranges do not look reasonable", result.title
    assert_equal "Vulnerable version range = 1.2.3 contains first patched version 1.2.3", result.summary
  end
end
