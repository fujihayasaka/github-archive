# frozen_string_literal: true

require "test_helper"

class MITREJSONCheckTest < ActiveSupport::TestCase
  test "returns a failed CheckResult if CVE requestor has not been notified" do
    cve_review = create(:assigned_cve_review, :all_fields_populated)
    result = MITREJSONCheck.execute_check(review: cve_review)
    refute result.passed?
  end

  test "returns a failed CheckResult if Advisory is not published" do
    cve_review = create(:cve_review, :curation_state_waiting, :all_fields_populated)
    result = MITREJSONCheck.execute_check(review: cve_review)
    refute result.passed?
  end

  test "returns a failed CheckResult if CVEJSONBuilder model is invalid" do
    cve_review = create(:cve_review, :curation_state_open)
    result = MITREJSONCheck.execute_check(review: cve_review)
    refute result.passed?
  end

  test "returns a failed CheckResult if the JSON schema is invalid" do
    cve_review = create(:cve_review, :curation_state_open, :all_fields_populated)

    # So that the test can reach the condition we are checking
    CVEJSONBuilder.any_instance.stubs(:validate_json_schema).returns([{}])

    result = MITREJSONCheck.execute_check(review: cve_review)
    refute result.passed?
  end

  test "returns a passed CheckResult if CVE JSON is MITRE-compatible" do
    cve_review = create(:cve_review, :curation_state_open, :all_fields_populated)
    result = MITREJSONCheck.execute_check(review: cve_review)
    assert result.passed?
  end
end
