# frozen_string_literal: true

require "test_helper"
require "json_schemer"
require "normal_yaml"
require "pathname"

class CVEJSONBuilderTest < ActiveSupport::TestCase
  setup do
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
  end

  test "Happy path: makes CVE JSON for basic CVE" do
    example_builder = cve_json_builder

    assert_equal \
      load_cve_fixture("CVE-2019-1234567").chomp,
      example_builder.to_json
  end

  test "Happy path: makes CVE JSON for basic CVE with CVSS 4 data" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cvss_v4").at_least_once.returns(true)

    example_builder = cve_json_builder(
      cvss_vectorString: "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H",
    )

    assert_equal \
      load_cve_fixture("CVE-2024-1234567").chomp,
      example_builder.to_json
  end

  test "multiple version_values" do
    example_builder = cve_json_builder(
      version_values: [
        "< 1.2.3",
        ">= 2.0.0, < 2.3.4",
        ">= 3.0.0, < 3.4.5",
      ],
    )

    expected_version_data = [
      { "version" => "< 1.2.3", "status" => "affected" },
      { "version" => ">= 2.0.0, < 2.3.4", "status" => "affected" },
      { "version" => ">= 3.0.0, < 3.4.5", "status" => "affected" },
    ]

    # I am embarrased for this json ...
    actual_version_data = example_builder.to_h.dig("containers", "cna", "affected", 0, "versions")

    assert_equal expected_version_data, actual_version_data
  end

  test "is invalid when there are duplicate version_values" do
    builder = cve_json_builder(
      version_values: [
        "< 1.2.3",
        ">= 2.0.0, < 2.3.4",
        "< 1.2.3",
      ],
    )

    refute builder.valid?
    assert builder.errors[:version_values].any?
  end

  test "multiple problemtype_values" do
    example_builder = cve_json_builder(
      problemtype_values: [
        "CWE-123: Write-what-where Condition",
        "CWE-234: Failure to Handle Missing Parameter",
        "pebkac", # it can be literally any string, does not have to be a CWE
      ],
    )

    expected_problem_type_data = [
      {
        "descriptions" => [
          {
            "cweId" => "CWE-123",
            "lang" => "en",
            "description" => "CWE-123: Write-what-where Condition",
            "type" => "CWE",
          },
        ],
      },
      {
        "descriptions" => [
          {
            "cweId" => "CWE-234",
            "lang" => "en",
            "description" => "CWE-234: Failure to Handle Missing Parameter",
            "type" => "CWE",
          },
        ],
      },
      {
        "descriptions" => [
          {
            "lang" => "en",
            "description" => "pebkac",
          },
        ],
      },
    ]

    actual_problem_type_data = example_builder.to_h.dig("containers", "cna", "problemTypes")

    assert_equal expected_problem_type_data, actual_problem_type_data
  end

  test "reference list never includes links to NVD or MITRE sites" do
    # This test ensures we do not submit self-referencing links in our CVE JSON.
    # Since the reference list can be re-used between internal and external advisories,
    # we should ensure that only internal advisories link to the NVD/MITRE page.
    example_builder = cve_json_builder(
      confirm_reference: "https://github.com/FakeInc/Software/security/advisories/GHSA-1111-2222-3333",
      misc_references: [
        "https://nvd.nist.gov/vuln/detail/CVE-2019-16760",
        "https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2019-16760",
        "https://github.com/FakeInc/Software/commit/7fecaee81f59926b6e1913511c90650e76673b38",
        "https://github.com/FakeInc/Software/pull/123",
        "https://github.com/FakeInc/Software/issues/456",
        "https://hackerone.com/reports/1234",
        "https://otherurl.org/some/random/link",
      ],
    )

    expected_reference_data = [
      {
        "name" => "https://github.com/FakeInc/Software/security/advisories/GHSA-1111-2222-3333",
        "tags" => ["x_refsource_CONFIRM"],
        "url" => "https://github.com/FakeInc/Software/security/advisories/GHSA-1111-2222-3333",
      },
      {
        "name" => "https://github.com/FakeInc/Software/issues/456",
        "tags" => ["x_refsource_MISC"],
        "url" => "https://github.com/FakeInc/Software/issues/456",
      },
      {
        "name" => "https://github.com/FakeInc/Software/pull/123",
        "tags" => ["x_refsource_MISC"],
        "url" => "https://github.com/FakeInc/Software/pull/123",
      },
      {
        "name" => "https://github.com/FakeInc/Software/commit/7fecaee81f59926b6e1913511c90650e76673b38",
        "tags" => ["x_refsource_MISC"],
        "url" => "https://github.com/FakeInc/Software/commit/7fecaee81f59926b6e1913511c90650e76673b38",
      },
      {
        "name" => "https://hackerone.com/reports/1234",
        "tags" => ["x_refsource_MISC"],
        "url" => "https://hackerone.com/reports/1234",
      },
      {
        "name" => "https://otherurl.org/some/random/link",
        "tags" => ["x_refsource_MISC"],
        "url" => "https://otherurl.org/some/random/link",
      },
    ]

    assert_equal expected_reference_data, example_builder.to_h["containers"]["cna"]["references"]
  end

  test "CVSS v3 base score 7.0" do
    example_builder = cve_json_builder(
      cvss_vectorString: "CVSS:3.1/AV:L/AC:H/PR:L/UI:N/S:C/C:L/I:H/A:L",
    )
    expected_cvss_obj = {
      "attackComplexity" => "HIGH",
      "attackVector" => "LOCAL",
      "availabilityImpact" => "LOW",
      "baseScore" => 7.0,
      "baseSeverity" => "HIGH",
      "confidentialityImpact" => "LOW",
      "integrityImpact" => "HIGH",
      "privilegesRequired" => "LOW",
      "scope" => "CHANGED",
      "userInteraction" => "NONE",
      "vectorString" => "CVSS:3.1/AV:L/AC:H/PR:L/UI:N/S:C/C:L/I:H/A:L",
      "version" => "3.1",
    }

    assert_equal expected_cvss_obj, example_builder.to_h["containers"]["cna"]["metrics"][0]["cvssV3_1"]
  end

  test "CVSS v3 base score 3.1" do
    example_builder = cve_json_builder(
      cvss_vectorString: "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:N/I:N/A:L",
    )
    expected_cvss_obj = {
      "attackComplexity" => "HIGH",
      "attackVector" => "NETWORK",
      "availabilityImpact" => "LOW",
      "baseScore" => 3.1,
      "baseSeverity" => "LOW",
      "confidentialityImpact" => "NONE",
      "integrityImpact" => "NONE",
      "privilegesRequired" => "LOW",
      "scope" => "UNCHANGED",
      "userInteraction" => "NONE",
      "vectorString" => "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:N/I:N/A:L",
      "version" => "3.1",
    }

    assert_equal expected_cvss_obj, example_builder.to_h["containers"]["cna"]["metrics"][0]["cvssV3_1"]
  end

  test "CVSS v3 base score 4.8" do
    example_builder = cve_json_builder(
      cvss_vectorString: "CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:L/I:L/A:N",
    )
    expected_cvss_obj = {
      "attackComplexity" => "HIGH",
      "attackVector" => "NETWORK",
      "availabilityImpact" => "NONE",
      "baseScore" => 4.8,
      "baseSeverity" => "MEDIUM",
      "confidentialityImpact" => "LOW",
      "integrityImpact" => "LOW",
      "privilegesRequired" => "NONE",
      "scope" => "UNCHANGED",
      "userInteraction" => "NONE",
      "vectorString" => "CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:L/I:L/A:N",
      "version" => "3.1",
    }

    assert_equal expected_cvss_obj, example_builder.to_h["containers"]["cna"]["metrics"][0]["cvssV3_1"]
  end

  test "CVSS v4 base score 7.3" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cvss_v4").at_least_once.returns(true)

    example_builder = cve_json_builder(
      cvss_vectorString: "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H",
    )
    expected_cvss_obj = {
      "attackVector" => "ADJACENT",
      "attackComplexity" => "HIGH",
      "attackRequirements" => "NONE",
      "privilegesRequired" => "LOW",
      "userInteraction" => "NONE",
      "vulnConfidentialityImpact" => "LOW",
      "vulnIntegrityImpact" => "HIGH",
      "vulnAvailabilityImpact" => "HIGH",
      "subConfidentialityImpact" => "HIGH",
      "subIntegrityImpact" => "LOW",
      "subAvailabilityImpact" => "HIGH",
      "baseScore" => 7.3,
      "baseSeverity" => "HIGH",
      "vectorString" => "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H",
      "version" => "4.0",
    }

    assert_equal expected_cvss_obj, example_builder.to_h["containers"]["cna"]["metrics"][0]["cvssV4_0"]
  end

  test "knows if it has valid data or not" do
    example_builder = cve_json_builder(
      ghsa_id: "not a ghsa id",
    )
    refute example_builder.valid?

    example_builder.ghsa_id = generate(:ghsa_id)
    refute example_builder.valid?

    create(:cve_review, :notified, ghsa_id: example_builder.ghsa_id)
    refute example_builder.valid?

    advisory_review = create(:advisory_review, ghsa_id: example_builder.ghsa_id)
    create(:repository_advisory_feed_entry, advisory_review: advisory_review)
    assert example_builder.valid?
  end

  test "returns meaningful error messages for each and every blank value" do
    empty_builder = CVEJSONBuilder.new
    expected_errors = [
      "GHSA can't be blank",
      "CVE can't be blank",
      "Title is too short (minimum is 2 characters)",
      "Description is too short (minimum is 2 characters)",
      "Vendor name is too short (minimum is 2 characters)",
      "Product can't be blank",
      "Version values is too short (minimum is 1 character)",
      "Problemtype values is too short (minimum is 1 character)",
      "Confirm reference is too short (minimum is 63 characters)",
      "CVSS vectorstring can't be blank",
      "No CVE Review found for ghsa_id: ",
    ]
    refute empty_builder.valid?
    assert_equal expected_errors, empty_builder.errors.full_messages
  end

  test "returns meaningful values for any invalid data" do
    invalid_builder = cve_json_builder(
      ghsa_id: "not a ghsa id",
      cve_id: "CVE-12345678",
      title: "X",
      description: "X",
      vendor_name: "X",
      product: " ",
      cvss_vectorString: "not a vector string",
      version_values: [],
      problemtype_values: [],
      confirm_reference: "https://tooshort.com",
    )
    refute invalid_builder.valid?
    expected_errors = [
      "GHSA is invalid",
      "CVE is invalid",
      "Title is too short (minimum is 2 characters)",
      "Description is too short (minimum is 2 characters)",
      "Vendor name is too short (minimum is 2 characters)",
      "Product can't be blank",
      "Version values is too short (minimum is 1 character)",
      "Problemtype values is too short (minimum is 1 character)",
      "Confirm reference is too short (minimum is 63 characters)",
      "CVSS vectorstring is invalid",
      "No CVE Review found for ghsa_id: not a ghsa id",
    ]
    assert_equal expected_errors, invalid_builder.errors.full_messages
  end

  test "can generate JSON when cvss_vectorString is missing" do
    example_builder = cve_json_builder(cvss_vectorString: nil)

    assert_nothing_raised do
      example_builder.to_json
    end

    assert_equal [], example_builder.to_h["containers"]["cna"]["metrics"]
  end

  test "can generate JSON even if a CVSS v3 vector string has invalid metrics" do
    example_builder = cve_json_builder(cvss_vectorString: "CVSS:3.1/invalid")
    expected_cvss_obj = {
      "attackComplexity" => "HIGH",
      "attackVector" => "PHYSICAL",
      "availabilityImpact" => "NONE",
      "baseScore" => 0.0,
      "baseSeverity" => "NONE",
      "confidentialityImpact" => "NONE",
      "integrityImpact" => "NONE",
      "privilegesRequired" => "HIGH",
      "scope" => "UNCHANGED",
      "userInteraction" => "REQUIRED",
      "vectorString" => "CVSS:3.1/AV:P/AC:H/PR:H/UI:R/S:U/C:N/I:N/A:N",
      "version" => "3.1",
    }

    assert_nothing_raised do
      example_builder.to_json
    end

    assert_equal expected_cvss_obj, example_builder.to_h["containers"]["cna"]["metrics"][0]["cvssV3_1"]
  end

  test "can generate JSON even if a CVSS v4 vector string has invalid metrics" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cvss_v4").at_least_once.returns(true)

    example_builder = cve_json_builder(cvss_vectorString: "CVSS:4.0/invalid")
    expected_cvss_obj = {
      "attackVector" => "NETWORK",
      "attackComplexity" => "LOW",
      "attackRequirements" => "NONE",
      "privilegesRequired" => "NONE",
      "userInteraction" => "NONE",
      "vulnConfidentialityImpact" => "NONE",
      "vulnIntegrityImpact" => "NONE",
      "vulnAvailabilityImpact" => "NONE",
      "subConfidentialityImpact" => "NONE",
      "subIntegrityImpact" => "NONE",
      "subAvailabilityImpact" => "NONE",
      "baseScore" => 0.0,
      "baseSeverity" => "NONE",
      "vectorString" => "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N",
      "version" => "4.0",
    }

    assert_nothing_raised do
      example_builder.to_json
    end

    assert_equal expected_cvss_obj, example_builder.to_h["containers"]["cna"]["metrics"][0]["cvssV4_0"]
  end

  # Tests for CVE JSON:

  test "CVE metadata is filled properly" do
    assert_equal({
      "cveId" => "CVE-2019-1234567",
      "assignerOrgId" => "a0819718-46f1-4df5-94e2-005712e83aaa",
      "state" => "PUBLISHED",
    }, cve_json_builder.to_h["cveMetadata"])
  end

  test "fields with non-nested value, under containers.cna property, are filled properly" do
    assert_equal "XSS in FakeSoftware", cve_json_builder.to_h["containers"]["cna"]["title"]
  end

  test "fields with non-nested value, in the top level, are filled properly" do
    cve_record = cve_json_builder.to_h
    assert_equal "CVE_RECORD", cve_record["dataType"]
    assert_equal "5.0", cve_record["dataVersion"]
  end

  test "fields with non-nested value, in the top level, are filled properly when advisory_db_cvss_v4 feature flag is enabled" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cvss_v4").at_least_once.returns(true)

    cve_record = cve_json_builder.to_h
    assert_equal "CVE_RECORD", cve_record["dataType"]
    assert_equal "5.1.0", cve_record["dataVersion"]
  end

  test "problemTypes under containers.cna property are filled properly" do
    assert_equal([
      {
        "descriptions" => [
          {
            "cweId" => "CWE-123",
            "lang" => "en",
            "description" => "CWE-123: Write-what-where Condition",
            "type" => "CWE",
          },
        ],
      },
    ], cve_json_builder.to_h["containers"]["cna"]["problemTypes"])
  end

  test "CVSS v3 metrics under containers.cna property are filled properly" do
    assert_equal([
      {
        "cvssV3_1" => {
          "version" => "3.1",
          "attackVector" => "NETWORK",
          "attackComplexity" => "HIGH",
          "privilegesRequired" => "LOW",
          "userInteraction" => "NONE",
          "scope" => "CHANGED",
          "confidentialityImpact" => "HIGH",
          "integrityImpact" => "NONE",
          "availabilityImpact" => "NONE",
          "baseScore" => 6.3,
          "baseSeverity" => "MEDIUM",
          "vectorString" => "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:C/C:H/I:N/A:N",
        },
      },
    ], cve_json_builder.to_h["containers"]["cna"]["metrics"])
  end

  test "CVSS v4 metrics under containers.cna property are filled properly" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cvss_v4").at_least_once.returns(true)

    assert_equal([
      {
        "cvssV4_0" => {
          "attackVector" => "ADJACENT",
          "attackComplexity" => "HIGH",
          "attackRequirements" => "NONE",
          "privilegesRequired" => "LOW",
          "userInteraction" => "NONE",
          "vulnConfidentialityImpact" => "LOW",
          "vulnIntegrityImpact" => "HIGH",
          "vulnAvailabilityImpact" => "HIGH",
          "subConfidentialityImpact" => "HIGH",
          "subIntegrityImpact" => "LOW",
          "subAvailabilityImpact" => "HIGH",
          "baseScore" => 7.3,
          "baseSeverity" => "HIGH",
          "vectorString" => "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H",
          "version" => "4.0",
        },
      },
    ], cve_json_builder(
        cvss_vectorString: "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H",
      ).to_h["containers"]["cna"]["metrics"])
  end

  test "metrics under containers.cna.cvssV3_1.attackVector uses ADJACENT_NETWORK for AV:A" do
    builder = cve_json_builder(cvss_vectorString: "CVSS:3.1/AV:A/AC:L/PR:L/UI:N/S:C/C:H/I:N/A:N")

    assert_equal("ADJACENT_NETWORK", builder.to_h["containers"]["cna"]["metrics"][0]["cvssV3_1"]["attackVector"])
  end

  test "metrics under containers.cna property can take CVSS 3.0" do
    builder = cve_json_builder(cvss_vectorString: "CVSS:3.0/AV:N/AC:H/PR:L/UI:N/S:C/C:H/I:N/A:N")

    assert_equal([
      {
        "cvssV3_0" => {
          "version" => "3.0",
          "attackVector" => "NETWORK",
          "attackComplexity" => "HIGH",
          "privilegesRequired" => "LOW",
          "userInteraction" => "NONE",
          "scope" => "CHANGED",
          "confidentialityImpact" => "HIGH",
          "integrityImpact" => "NONE",
          "availabilityImpact" => "NONE",
          "baseScore" => 6.3,
          "baseSeverity" => "MEDIUM",
          "vectorString" => "CVSS:3.0/AV:N/AC:H/PR:L/UI:N/S:C/C:H/I:N/A:N",
        },
      },
    ], builder.to_h["containers"]["cna"]["metrics"])
  end

  test "providerMetadata under containers.cna property is filled properly" do
    assert_equal({
      "orgId" => "a0819718-46f1-4df5-94e2-005712e83aaa",
    }, cve_json_builder.to_h["containers"]["cna"]["providerMetadata"])
  end

  test "descriptions under containers.cna property are filled properly" do
    assert_equal([
      {
        "lang" => "en",
        "value" => "FakeSoftware before 1.2.3 has an XSS that eats your dinner when you blink into the camera, on windows.",
      },
    ], cve_json_builder.to_h["containers"]["cna"]["descriptions"])
  end

  test "affected under containers.cna property is filled properly" do
    assert_equal([
      {
        "vendor" => "FakeInc",
        "product" => "Software",
        "versions" => [
          {
            "version" => "before 1.2.3",
            "status" => "affected",
          },
        ],
      },
    ], cve_json_builder.to_h["containers"]["cna"]["affected"])
  end

  test "references under containers.cna property are filled properly" do
    assert_equal([
      {
        "name" => "https://github.com/FakeInc/Software/security/advisories/GHSA-2222-bbbb-8888",
        "tags" => [
          "x_refsource_CONFIRM",
        ],
        "url" => "https://github.com/FakeInc/Software/security/advisories/GHSA-2222-bbbb-8888",
      },
      {
        "name" => "https://github.com/FakeInc/Software/issues/456",
        "tags" => [
          "x_refsource_MISC",
        ],
        "url" => "https://github.com/FakeInc/Software/issues/456",
      },
      {
        "name" => "https://github.com/FakeInc/Software/pull/123",
        "tags" => [
          "x_refsource_MISC",
        ],
        "url" => "https://github.com/FakeInc/Software/pull/123",
      },
      {
        "name" => "https://github.com/FakeInc/Software/commit/7fecaee81f59926b6e1913511c90650e76673b38",
        "tags" => [
          "x_refsource_MISC",
        ],
        "url" => "https://github.com/FakeInc/Software/commit/7fecaee81f59926b6e1913511c90650e76673b38",
      },
      {
        "name" => "https://hackerone.com/reports/1234",
        "tags" => [
          "x_refsource_MISC",
        ],
        "url" => "https://hackerone.com/reports/1234",
      },
      {
        "name" => "https://otherurl.org/some/random/link",
        "tags" => [
          "x_refsource_MISC",
        ],
        "url" => "https://otherurl.org/some/random/link",
      },
    ], cve_json_builder.to_h["containers"]["cna"]["references"])
  end

  test "validates that the JSON 5.0 schema is correct" do
    schema = Pathname.new("lib/cve/CVE_JSON_5.0_bundled.json")
    schemer = JSONSchemer.schema(schema)
    example_builder = cve_json_builder

    assert schemer.valid?(example_builder.to_h)
  end

  test "validates that the JSON 5.1.0 schema is correct" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cvss_v4").at_least_once.returns(true)

    schema = Pathname.new("lib/cve/CVE_Record_Format_bundled.json")
    schemer = JSONSchemer.schema(schema)
    example_builder = cve_json_builder

    assert schemer.valid?(example_builder.to_h)
  end

  test "validates that the JSON schema is correct when it includes CVSS v4 data" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cvss_v4").at_least_once.returns(true)

    schema = Pathname.new("lib/cve/CVE_Record_Format_bundled.json")
    schemer = JSONSchemer.schema(schema)
    example_builder = cve_json_builder(
      cvss_vectorString: "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H",
    )

    assert schemer.valid?(example_builder.to_h)
  end

  private

  def cve_json_builder(overrides = {})
    args = {
      ghsa_id: "GHSA-2222-bbbb-8888",
      cve_id: "CVE-2019-1234567",
      title: "XSS in FakeSoftware",
      description: "FakeSoftware before 1.2.3 has an XSS that eats your dinner when you blink into the camera, on windows.",
      vendor_name: "FakeInc",
      product: "Software",
      cvss_vectorString: "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:C/C:H/I:N/A:N",
      version_values: [
        "before 1.2.3",
      ],
      problemtype_values: [
        "CWE-123: Write-what-where Condition",
      ],
      confirm_reference: "https://github.com/FakeInc/Software/security/advisories/GHSA-2222-bbbb-8888",
      misc_references: [
        "https://github.com/FakeInc/Software/commit/7fecaee81f59926b6e1913511c90650e76673b38",
        "https://github.com/FakeInc/Software/pull/123",
        "https://github.com/FakeInc/Software/issues/456",
        "https://hackerone.com/reports/1234",
        "https://otherurl.org/some/random/link",
      ],
    }.merge(overrides)

    CVEJSONBuilder.new(args)
  end
end
