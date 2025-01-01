# frozen_string_literal: true

require "test_helper"

class StructuredAdvisoryPayloadTest < ActiveSupport::TestCase
  test "commits a full factory advisory payload and validates it is stored" do
    advisory_review = create(:advisory_review, advisory_payload: create(:advisory_payload, vulnerability_count: 2, reference_count: 2))

    ap = advisory_review.advisory_payload
    advisory_review.structured_advisory_payload = StructuredAdvisoryPayload.new(
      summary: ap["summary"],
      description: ap["description"],
      source_code_location: ap["source_code_location"],
      severity: ap["severity"],
      cvss_v3: ap["cvss_v3"],
      withdrawn: ap["withdrawn"],
    )

    advisory_review.structured_advisory_payload.save!
    advisory_review.structured_advisory_payload.reload

    assert_equal ap["summary"], advisory_review.structured_advisory_payload.summary
    assert_equal ap["description"], advisory_review.structured_advisory_payload.description
    assert_equal ap["source_code_location"], advisory_review.structured_advisory_payload.source_code_location
    assert_equal ap["severity"], advisory_review.structured_advisory_payload.severity
    assert_equal ap["cvss_v3"], advisory_review.structured_advisory_payload.cvss_v3
    assert_equal ap["withdrawn"], advisory_review.structured_advisory_payload.withdrawn

    ap["cwe_ids"].each_with_index do |cwe_id, i|
      advisory_review.structured_advisory_payload.cwe_ids.create!(
        cwe_id: cwe_id,
        index: i,
      )
    end

    advisory_review.structured_advisory_payload.reload
    db_cwe_ids = advisory_review.structured_advisory_payload.cwe_ids.order(index: :asc)
    assert_equal ap["cwe_ids"][0], db_cwe_ids[0].cwe_id

    ap["references"].each_with_index do |ref, i|
      advisory_review.structured_advisory_payload.references.create!(
        url: ref,
        index: i,
      )
    end

    advisory_review.structured_advisory_payload.reload
    db_refs = advisory_review.structured_advisory_payload.references.order(index: :asc)

    assert_equal ap["references"][0], db_refs[0].url
    assert_equal ap["references"][1], db_refs[1].url
    assert_equal 0, db_refs[0].index
    assert_equal 1, db_refs[1].index

    ap["vulnerabilities"].each do |i, vuln|
      advisory_review.structured_advisory_payload.vulnerabilities.create!(
        index: i,
        package_ecosystem: vuln["ecosystem"],
        package_name: vuln["package_name"],
        vulnerable_version_range: vuln["vulnerable_version_range"],
        first_patched_version: vuln["first_patched_version"],
      )
    end

    advisory_review.structured_advisory_payload.reload
    db_vulns = advisory_review.structured_advisory_payload.vulnerabilities.order(index: :asc)
    assert_equal 2, db_vulns.count
    db_vulns.each_with_index do |vuln, i|
      apv = ap["vulnerabilities"][i]
      assert_equal apv["ecosystem"], vuln.package_ecosystem
      assert_equal apv["package_name"], vuln.package_name
      assert_equal apv["vulnerable_version_range"], vuln.vulnerable_version_range
      assert_equal apv["first_patched_version"], vuln.first_patched_version
    end
  end
end
