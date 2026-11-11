# frozen_string_literal: true

require "test_helper"

class ReferencesCheckTest < ActiveSupport::TestCase
  VALID_REPO_ADVISORY_URL = "https://github.com/tlsfuzzer/tlslite-ng/security/advisories/GHSA-wvcv-832q-fjg7"
  VALID_NVD_URL = "https://nvd.nist.gov/vuln/detail/CVE-2019-11027"
  VALID_RANDOM_URL = "https://marc.info/?l=openid-security&m=155154717027534&w=2"
  INVALID_URL = "https://github.com/swordev/merge/blob/master/src/index.ts%23L64"

  test "AdvisoryReview returns a passed CheckResult with all working reference URLs" do
    advisory_review = create(:advisory_review, advisory_payload: {
      references: [VALID_NVD_URL, VALID_RANDOM_URL],
    }.deep_stringify_keys)

    result = VCR.use_cassette("references_checks") do
      ReferencesCheck.execute_check(review: advisory_review)
    end

    assert result.passed?
  end

  test "CVEReview returns a passed CheckResult with all working confirm & misc reference URLs" do
    cve_review = create(:cve_review,
      confirm_reference: VALID_REPO_ADVISORY_URL,
      misc_references: [VALID_NVD_URL, VALID_RANDOM_URL])

    result = VCR.use_cassette("references_checks") do
      ReferencesCheck.execute_check(review: cve_review)
    end

    assert result.passed?
  end

  test "AdvisoryReview returns a failed CheckResult when no references present" do
    advisory_review = create(:advisory_review, advisory_payload: {
      references: [],
    }.deep_stringify_keys)

    result = VCR.use_cassette("references_checks") do
      ReferencesCheck.execute_check(review: advisory_review)
    end

    refute result.passed?
  end

  test "CVEReview returns a failed CheckResult when no confirm reference present" do
    cve_review = create(:cve_review,
      confirm_reference: nil,
      misc_references: [VALID_NVD_URL, VALID_RANDOM_URL])

    result = VCR.use_cassette("references_checks") do
      ReferencesCheck.execute_check(review: cve_review)
    end

    refute result.passed?
  end

  test "CVEReview returns a failed CheckResult when any reference URL contains whitespace" do
    cve_review = create(:cve_review,
      confirm_reference: VALID_REPO_ADVISORY_URL,
      misc_references: ["https://abc.com/ 123", "https://abc.com/345", " https://abc.com/678 "])

    result = ReferencesCheck.execute_check(review: cve_review)

    refute result.passed?
  end

  test "AdvisoryReview returns a warning CheckResult when a reference is invalid" do
    advisory_review = create(:advisory_review, advisory_payload: {
      references: [VALID_NVD_URL, INVALID_URL, VALID_RANDOM_URL],
    }.deep_stringify_keys)

    result = VCR.use_cassette("references_checks") do
      ReferencesCheck.execute_check(review: advisory_review)
    end

    assert result.warning?
  end

  test "AdvisoryReview returns a warning CheckResult when not all refs are checked" do
    advisory_review = create(:advisory_review, advisory_payload: {
      references: [VALID_NVD_URL, VALID_RANDOM_URL],
    }.deep_stringify_keys)

    result = VCR.use_cassette("references_checks") do
      stub_const(::ReferencesCheck, :URL_LIMIT, 1) do
        ReferencesCheck.execute_check(review: advisory_review)
      end
    end

    assert result.warning?
  end

  test "AdvisoryReview caches results" do
    advisory_review = create(:advisory_review, advisory_payload: {
      references: [VALID_NVD_URL, VALID_RANDOM_URL],
    }.deep_stringify_keys)

    result = VCR.use_cassette("references_checks") do
      stub_const(::ReferencesCheck, :URL_LIMIT, 1) do
        ReferencesCheck.execute_check(review: advisory_review)
      end
    end

    assert result.warning?

    result = VCR.use_cassette("references_checks") do
      stub_const(::ReferencesCheck, :URL_LIMIT, 1) do
        ReferencesCheck.execute_check(review: advisory_review)
      end
    end

    assert result.passed?
  end

  test "CVEReview returns a failed CheckResult when confirm reference invalid" do
    cve_review = create(:cve_review,
      confirm_reference: INVALID_URL,
      misc_references: [VALID_NVD_URL, VALID_RANDOM_URL])

    result = VCR.use_cassette("references_checks") do
      ReferencesCheck.execute_check(review: cve_review)
    end

    refute result.passed?
  end

  test "CVEReview returns a warning CheckResult when a misc reference invalid" do
    cve_review = create(:cve_review,
      confirm_reference: VALID_REPO_ADVISORY_URL,
      misc_references: [VALID_NVD_URL, INVALID_URL, VALID_RANDOM_URL])

    result = VCR.use_cassette("references_checks") do
      ReferencesCheck.execute_check(review: cve_review)
    end

    assert result.warning?
  end
end
