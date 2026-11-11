# frozen_string_literal: true

require "test_helper"

class Test < ActiveSupport::TestCase
  test "knows its source" do
    assert_equal "cve_review", CVEReviewImporter.source
    cve_review = create :assigned_cve_review, :notified
    assert_equal "cve_review", CVEReviewImporter.new(cve_review_id: cve_review.id).source
  end

  test "raises exception if given non-existent cve review id" do
    assert_raises(ActiveRecord::RecordNotFound) do
      CVEReviewImporter.new(cve_review_id: 999)
    end
  end

  # we only import when a CVE ID was actually assigned, otherwise there isn't really anything to import
  test "raises exception if given not_assigned cve review" do
    cve_review = create :not_assigned_cve_review, :notified
    assert_raises(CVEReviewImporter::NotImportableError) do
      CVEReviewImporter.new(cve_review_id: cve_review.id)
    end
  end

  test "raises exception if given assigned cve review that is open" do
    cve_review = create :assigned_cve_review
    assert_raises(CVEReviewImporter::NotImportableError) do
      CVEReviewImporter.new(cve_review_id: cve_review.id)
    end
  end

  test "produces an importer object with expected properties" do
    cve_id = "CVE-2020-12345"
    ghsa_id = "GHSA-qqxw-m5fj-f7gv"
    cve_review = create :assigned_cve_review,
      :notified,
      ghsa_id: ghsa_id,
      assigned_cve_id: cve_id,
      title: "A big bug in SoftwareProduct",
      description: "SoftwareProduct before 1.2.3 has an XSS vulnerability",
      cvss_vectorString: "CVSS:3.1/AV:N/AC:L/PR:L/UI:R/S:C/C:H/I:L/A:N",
      confirm_reference: "https://github.com/testorg/testreponame/security/advisories/#{ghsa_id}",
      misc_references: [
        "https://github.com/testorg/testreponame/commit/5ac1b9e24ff6afc465756edf845d2e9660bd34bf",
      ],
      problemtype_values: [
        "CWE-79: Improper Neutralization of Input During Web Page Generation ('Cross-site Scripting')",
        "This is a non-CWE problem type",
        "CWE-200: Exposure of Sensitive Information to an Unauthorized Actor",
      ]

    import_items = CVEReviewImporter.new(cve_review_id: cve_review.id).map { |importer_item| importer_item }

    assert_equal 1, import_items.length

    expected_import_item = {
      identifier: "cve_review/#{ghsa_id}",
      ghsa_id: ghsa_id,
      cve_id: cve_id,
      raw_payload: cve_review.attributes,
      advisory_payload: {
        summary: "A big bug in SoftwareProduct",
        description: "SoftwareProduct before 1.2.3 has an XSS vulnerability",
        severity: "high",
        references: [
          "https://github.com/testorg/testreponame/security/advisories/#{ghsa_id}",
          "https://github.com/testorg/testreponame/commit/5ac1b9e24ff6afc465756edf845d2e9660bd34bf",
        ],
        cwe_ids: ["CWE-79", "CWE-200"],
        cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:L/UI:R/S:C/C:H/I:L/A:N",
        cvss_v4: "",
        vulnerabilities: {},
        withdrawn: false,
      },
    }
    assert_equal expected_import_item, import_items.first
  end

  test "produces an importer object with optional properties" do
    cve_id = "CVE-2020-12345"
    ghsa_id = "GHSA-qqxw-m5fj-f7gv"
    cve_review = create :assigned_cve_review,
      :notified,
      ghsa_id: ghsa_id,
      assigned_cve_id: cve_id,
      description: "",
      cvss_vectorString: ""

    import_items = CVEReviewImporter.new(cve_review_id: cve_review.id).map { |importer_item| importer_item }

    assert_equal 1, import_items.length

    expected_import_item = {
      identifier: "cve_review/#{ghsa_id}",
      ghsa_id: ghsa_id,
      cve_id: cve_id,
      raw_payload: cve_review.attributes,
      advisory_payload: {
        summary: cve_review.title,
        description: "",
        severity: nil,
        references: ["https://github.com/testorg/testrepo/security/advisories/#{ghsa_id}"],
        cwe_ids: [],
        cvss_v3: "",
        cvss_v4: "",
        vulnerabilities: {},
        withdrawn: false,
      },
    }
    assert_equal expected_import_item, import_items.first
  end
end
