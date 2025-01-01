# frozen_string_literal: true

require "test_helper"

class MatchingSeverityCheckTest < ActiveSupport::TestCase
  test "fails if CVSS v4 and severity do not match" do
    advisory_review = create(:advisory_review, advisory_payload: {
      cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H", # Has a "high" severity
      severity: "low",
    })
    result = MatchingSeverityCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "CVSS 4 severity \"high\" does not match severity \"low\"", result.summary
  end

  test "passes if CVSS v4 and severity match" do
    advisory_review = create(:advisory_review, :with_cvss_v4)
    result = MatchingSeverityCheck.execute_check(review: advisory_review)

    assert result.passed?
    assert_equal "CVSS 4 severity \"high\" matches severity \"high\"", result.summary
  end

  test "passes if CVSS v4 is empty and severity is populated" do
    advisory_review = create(:advisory_review, advisory_payload: {
      cvss_v4: "",
      severity: "critical",
    })
    result = MatchingSeverityCheck.execute_check(review: advisory_review)

    assert result.passed?
    assert_equal "No CVSS present, using severity", result.title
    assert_equal "Severity is \"critical\"", result.summary
  end

  test "passes if CVSS v4 is populated and severity is empty" do
    advisory_review = create(:advisory_review, advisory_payload: {
      cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H",
      severity: "",
    })
    result = MatchingSeverityCheck.execute_check(review: advisory_review)

    assert result.passed?
    assert_equal "CVSS is present but no severity is present.", result.title
    assert_equal "Please set the severity if applicable.", result.summary
  end

  test "passes if both CVSS v4 and severity are empty" do
    advisory_review = create(:advisory_review, advisory_payload: {
      cvss_v4: "",
      severity: "",
    })

    result = MatchingSeverityCheck.execute_check(review: advisory_review)

    assert result.passed?
    assert_equal "No CVSS or severity present", result.title
    assert_equal "Nothing to compare", result.summary
  end

  test "does not compare CVSS v3 and severity when both CVSS v3 and CVSS v4 are present" do
    advisory_review = create(:advisory_review, advisory_payload: {
      cvss_v3: "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N",
      cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H",
      severity: "high",
    })

    result = MatchingSeverityCheck.execute_check(review: advisory_review)

    assert result.passed?
    assert_equal "CVSS 4 severity \"high\" matches severity \"high\"", result.summary
  end

  test "fails if CVSS v3 and severity mismatch and CVSS 4 is blank" do
    advisory_review = create(:advisory_review, advisory_payload: {
      cvss_v3: "CVSS:3.1/AV:L/AC:H/PR:L/UI:N/S:U/C:H/I:H/A:H", # Has a "high" severity
      cvss_v4: "",
      severity: "low",
    })

    result = MatchingSeverityCheck.execute_check(review: advisory_review)

    refute result.passed?
    assert_equal "CVSS 3 severity \"high\" does not match severity \"low\"", result.summary
  end

  test "passes if CVSS v3 and severity match and CVSS 4 is blank" do
    advisory_review = create(:advisory_review, :with_cvss_v3) # Has a "moderate" severity and blank CVSS 4
    result = MatchingSeverityCheck.execute_check(review: advisory_review)

    assert result.passed?
    assert_equal "CVSS 3 severity \"moderate\" matches severity \"moderate\"", result.summary
  end

  test "passes if CVSS v3 is empty and severity is populated and CVSS 4 is blank" do
    advisory_review = create(:advisory_review, advisory_payload: {
      cvss_v3: "",
      cvss_v4: "",
      severity: "low",
    })
    result = MatchingSeverityCheck.execute_check(review: advisory_review)

    assert result.passed?
    assert_equal "No CVSS present, using severity", result.title
    assert_equal "Severity is \"low\"", result.summary
  end

  test "passes if CVSS v3 is populated and severity is empty and CVSS 4 is blank" do
    advisory_review = create(:advisory_review, advisory_payload: {
      cvss_v3: "CVSS:3.1/AV:L/AC:H/PR:L/UI:N/S:U/C:H/I:H/A:H",
      cvss_v4: "",
      severity: "",
    })
    result = MatchingSeverityCheck.execute_check(review: advisory_review)

    assert result.passed?
    assert_equal "CVSS is present but no severity is present.", result.title
    assert_equal "Please set the severity if applicable.", result.summary
  end

  test "passes if both CVSS v3 and severity are empty" do
    advisory_review = create(:advisory_review, advisory_payload: {
      cvss_v3: "",
      severity: "",
    })
    result = MatchingSeverityCheck.execute_check(review: advisory_review)

    assert result.passed?
    assert_equal "No CVSS or severity present", result.title
    assert_equal "Nothing to compare", result.summary
  end
end
