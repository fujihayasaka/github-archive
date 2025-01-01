# frozen_string_literal: true

require "test_helper"

class AdvisoryTest < ActiveSupport::TestCase
  test "requires a GHSA ID" do
    advisory = build(:advisory, advisory_review: nil, ghsa_id: nil)

    assert advisory.invalid?
    assert advisory.errors.details[:ghsa_id].present?
    assert advisory.errors.details[:ghsa_id].include?(error: :blank)
  end

  test "#extracted_npm_id returns nil if no reference is an NPM advisory" do
    advisory = create(:advisory, reference_count: 3)
    assert_nil NPMIDExtractor.extract(advisory)
  end

  test "#extracted_npm_id returns the ID when a nodesecurity reference is present" do
    advisory = create(:advisory, reference_count: 3)
    create(:reference, advisory: advisory, url: "https://nodesecurity.io/advisories/558")
    assert_equal 558, NPMIDExtractor.extract(advisory)
  end

  test "#extracted_npm_id returns the ID when a npm advisory reference is present" do
    advisory = create(:advisory, reference_count: 3)
    create(:reference, advisory: advisory, url: "https://www.npmjs.com/advisories/1488")
    assert_equal 1488, NPMIDExtractor.extract(advisory)
  end

  test "has CWE IDs" do
    advisory = create(:advisory)
    # Add 9,000 to some standard CWE IDs to avoid test database collisions.
    cwe_id_1 = create(:cwe, cwe_id: "CWE-9079")
    cwe_id_2 = create(:cwe, cwe_id: "CWE-9200")
    advisory.cwe_ids = [cwe_id_1.cwe_id, cwe_id_2.cwe_id]

    assert_equal ["CWE-9079", "CWE-9200"], advisory.cwe_ids
  end

  test "has a cvss_v3 field" do
    advisory = build(:advisory)
    advisory.cvss_v3 = "CVSS:3.1/AV:N/AC:H/PR:L/UI:R/S:C/C:H/I:L/A:L"

    assert advisory.save

    advisory.cvss_v3 = "CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:N"

    assert advisory.save
  end

  test "cannot have an invalid cvss_v3 field" do
    advisory = build(:advisory)
    advisory.cvss_v3 = "abcdefghijklmnopqrstuvwxyz"

    refute advisory.valid?
  end

  test "includes the cvss_v3 in the hydro_payload" do
    cvss_v3 = "CVSS:3.1/AV:N/AC:H/PR:L/UI:R/S:C/C:H/I:L/A:L"
    advisory = create(:advisory, cvss_v3: cvss_v3)

    assert_equal cvss_v3, advisory.hydro_payload[:cvss_v3]
  end

  test "excludes withdrawn vulnerabilities from the hydro_payload" do
    advisory = create(:advisory, vulnerability_count: 3)
    advisory.vulnerabilities.first.update_attribute(:withdrawn_at, Time.current)

    assert_equal 2, advisory.hydro_payload[:vulnerabilities].length
  end

  test "reviewed advisories require full information" do
    advisory = create(:unreviewed_advisory)

    assert advisory.valid?

    advisory.reviewed = true

    refute advisory.valid?
  end

  test "has a hydro status" do
    advisory = create(:unreviewed_advisory)
    assert_equal :UNREVIEWED, advisory.hydro_status

    advisory.reviewed = true
    assert_equal :REVIEWED, advisory.hydro_status
  end

  test "hydro classification is either GENERFAL or MALWARE when there is a malware feed entry in the AdvisoryReview" do
    advisory = create(:advisory)
    assert_equal :GENERAL, advisory.hydro_payload[:classification]

    create(:malware_feed_entry, advisory_review: advisory.advisory_review)
    advisory.reload
    assert_equal :MALWARE, advisory.hydro_payload[:classification]
  end
end
