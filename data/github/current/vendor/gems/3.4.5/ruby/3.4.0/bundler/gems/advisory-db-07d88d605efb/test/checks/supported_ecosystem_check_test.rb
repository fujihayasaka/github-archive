# frozen_string_literal: true

require "test_helper"

class SupportedEcosystemCheckTest < ActiveSupport::TestCase
  test "returns a passed CheckResult the review file has only supported ecosystems" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "rubygems",
        },
        1 => {
          ecosystem: "npm",
        },
      },
    }.deep_stringify_keys)

    result = SupportedEcosystemCheck.execute_check(review: advisory_review)

    assert result.passed?
  end

  test "returns a failed CheckResult when unsupported ecosystems present" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "rubygems",
        },
        1 => {
          ecosystem: "unsupported",
        },
      },
    }.deep_stringify_keys)

    result = SupportedEcosystemCheck.execute_check(review: advisory_review)

    refute result.passed?
  end

  test "returns a passed CheckResult when unsupported ecosystem is present only in withdrawn vulnerabilities" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "rubygems",
          withdrawn: false,
        },
        1 => {
          ecosystem: "unsupported",
          withdrawn: true,
        },
      },
    }.deep_stringify_keys)

    result = SupportedEcosystemCheck.execute_check(review: advisory_review)

    assert result.passed?
  end

  test "returns a failed CheckResult when other ecosystem is present without a source code location" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: {
        0 => {
          ecosystem: "rubygems",
        },
        1 => {
          ecosystem: "other",
        },
      },
    }.deep_stringify_keys)

    result = SupportedEcosystemCheck.execute_check(review: advisory_review)

    refute result.passed?
  end

  test "returns a failed CheckResult when other ecosystem is present with a source code location" do
    advisory_review = create(:advisory_review, advisory_payload: {
      source_code_location: "somewhere",
      vulnerabilities: {
        0 => {
          ecosystem: "rubygems",
        },
        1 => {
          ecosystem: "other",
        },
      },
    }.deep_stringify_keys)

    result = SupportedEcosystemCheck.execute_check(review: advisory_review)

    assert result.passed?
  end

  test "returns a failed CheckResult when there is no vulnerabilities key" do
    advisory_review = create(:advisory_review, advisory_payload: {
      XulnerabilitieX: {
        0 => {
          ecosystem: "rubygems",
        },
        1 => {
          ecosystem: "npm",
        },
      },
    }.deep_stringify_keys)

    result = SupportedEcosystemCheck.execute_check(review: advisory_review)

    refute result.passed?
  end

  test "returns a failed CheckResult when there vulnerabilities is not a hash" do
    advisory_review = create(:advisory_review, advisory_payload: {
      vulnerabilities: [
        {
          ecosystem: "rubygems",
        },
      ],
    }.deep_stringify_keys)

    result = SupportedEcosystemCheck.execute_check(review: advisory_review)

    refute result.passed?
  end
end
