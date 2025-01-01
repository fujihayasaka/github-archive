# frozen_string_literal: true

require "test_helper"

class CVERequestTest < ActiveSupport::TestCase
  test "can be made when a related CVE Review exists" do
    cve_request = build :cve_request
    create :cve_review, ghsa_id: cve_request.ghsa_id, num_cve_requests: 0
    assert cve_request.save!
  end

  test "can be made when a related CVE review does not exist" do
    cve_request = build :cve_request
    assert cve_request.save!
  end

  test "attribute with UTF8 encoding forced can handle variety of values" do
    cve_request = create :cve_request, title: "abc"
    assert_equal "abc", cve_request.title

    cve_request.title = "Test emojii 🤠 ❤️."
    assert_equal "Test emojii 🤠 ❤️.", cve_request.title
    cve_request.save!
    assert_equal "Test emojii 🤠 ❤️.", cve_request.reload.title

    cve_request.title = ""
    assert_equal "", cve_request.title
    cve_request.save!
    assert_equal "", cve_request.reload.title

    # UTF forcing code needs to handle nil attribute, if one should happen
    cve_request.title = nil
    assert_nil cve_request.title
    # nil is not allowed in DB
    assert_raises(ActiveRecord::NotNullViolation) do
      cve_request.save!
    end
  end

  test "#current_cve_request knows the lastest added cve_request" do
    cve_review = create :cve_review
    assert_equal CVERequest.order(:created_at).last, cve_review.current_cve_request

    new_cve_request = create :cve_request, ghsa_id: cve_review.ghsa_id
    assert_equal new_cve_request, cve_review.current_cve_request
  end

  test "can be assigned CWE IDs" do
    cve_request = create(:cve_request, cwe_ids: ["CWE-79", "CWE-200"])
    assert_equal ["CWE-79", "CWE-200"], cve_request.cwe_ids
  end

  test "can be assigned a cvss_v3 vector string" do
    cve_request = build :cve_request
    cve_request.cvss_v3 = "CVSS:3.1/AV:N/AC:H/PR:L/UI:R/S:C/C:H/I:L/A:L"

    assert cve_request.save
  end

  test "can be assigned a cvss_v4 vector string" do
    cve_request = build :cve_request
    cve_request.cvss_v4 = "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H"

    assert cve_request.save
  end

  test "can have a serialized payload of multiple affected products" do
    expected_affected_products = [
      {
        ecosystem: "npm",
        package: "nodemon",
        affected_versions: "< 1.0.0",
        patches: "1.0.0",
      },
      {
        ecosystem: "go",
        package: "gomon",
        affected_versions: "< 1.2.3",
        patches: "1.2.3",
      },
      {
        ecosystem: "nuget",
        package: "nugetmon",
        affected_versions: "< 2.3.4",
        patches: "2.3.4",
      },
    ].map(&:with_indifferent_access)
    cve_request = create(:cve_request, affected_products_payload: expected_affected_products)

    assert_equal 3, cve_request.affected_products_payload.length
    expected_affected_products.each_with_index do |expected_affected_product, index|
      assert_equal expected_affected_product[:ecosystem], cve_request.affected_products_payload[index]["ecosystem"]
      assert_equal expected_affected_product[:package], cve_request.affected_products_payload[index]["package"]
      assert_equal expected_affected_product[:affected_versions], cve_request.affected_products_payload[index]["affected_versions"]
      assert_equal expected_affected_product[:patches], cve_request.affected_products_payload[index]["patches"]
    end
  end

  test "cannot be saved with invalid fields within the affected_products_payload" do
    affected_products_payload = [
      {
        ecosystem: "npm",
        invalid_field_here: "some_value",
        affected_versions: "< 1.0.0",
        patches: "1.0.0",
      },
      {
        ecosystem: "go",
        package: "gomon",
        affected_versions: "< 1.2.3",
        patches: "1.2.3",
      },
    ]
    cve_request = build(:cve_request, affected_products_payload: affected_products_payload)

    refute cve_request.save
    assert_equal "Affected products payload can't have the field invalid_field_here", cve_request.errors.full_messages[0]
  end
end
