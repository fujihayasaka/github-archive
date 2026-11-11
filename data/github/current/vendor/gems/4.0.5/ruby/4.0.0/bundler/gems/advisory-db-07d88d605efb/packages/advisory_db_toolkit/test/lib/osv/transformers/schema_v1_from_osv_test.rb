# frozen_string_literal: true

require "test_helper"
require_relative "../osv_helper"

class OSVTransformersSchemaV1FromOSVTest < Minitest::Test
  include OSVHelper

  def setup
    @subject = AdvisoryDBToolkit::OSV::Transformers::SchemaV1
  end

  def test_converts_osv_version_1_4_0_json_to_an_advisory_interface_object
    osv_data = create_osv_data
    advisory = @subject.from_osv(osv_data)
    assert_kind_of AdvisoryDBToolkit::OSV::Interfaces::Advisory, advisory
    assert_equal osv_data["aliases"][0], advisory.ghsa_id
    assert_equal osv_data["summary"], advisory.summary
    assert_equal osv_data["details"], advisory.description
  end

  def test_normalizes_irregular_line_breaks_in_osv_details
    osv_data = create_osv_data(vulnerability_count: 0)
    osv_data["details"] = "This\r\nis\ra\ntest"
    advisory = @subject.from_osv(osv_data)
    refute_equal "This\r\nis\ra\ntest", advisory.description
    assert_equal "This\nis\na\ntest", advisory.description
  end

  def test_rehydrates_ghsa_specific_data__like_severity_rating_and_cwe_ids
    osv_data = create_osv_data(vulnerability_count: 0)
    osv_data["database_specific"]["cwe_ids"] = ["CWE-79", "CWE-1302"]
    osv_data["database_specific"]["severity"] = "low"
    advisory = @subject.from_osv(osv_data)
    assert_equal osv_data["database_specific"]["cwe_ids"], advisory.cwe_ids
    assert_equal osv_data["database_specific"]["severity"], advisory.severity
  end

  def test_rehydrates_individual_affected_products_to_vulnerabilities
    osv_data = create_osv_data(vulnerability_count: 0)
    advisory = @subject.from_osv(osv_data)
    assert_empty advisory.vulnerabilities

    append_osv_vulnerability(advisory: osv_data,
      ecosystem: "Maven",
      name: "com.google.protobuf:protobuf-kotlin",
      fixed_in: "3.19.2",
      introduced_in: "3.19.0")
    append_osv_vulnerability(advisory: osv_data,
      ecosystem: "Maven",
      name: "com.google.protobuf:protobuf-kotlin",
      fixed_in: "3.18.2",
      introduced_in: "3.18.0")
    append_osv_vulnerability(advisory: osv_data,
      ecosystem: "Maven",
      name: "com.google.protobuf:protobuf-java",
      fixed_in: "3.19.2",
      introduced_in: "3.19.0")
    append_osv_vulnerability(advisory: osv_data,
      ecosystem: "Maven",
      name: "com.google.protobuf:protobuf-java",
      fixed_in: "3.18.2",
      introduced_in: "3.18.0")
    append_osv_vulnerability(advisory: osv_data,
      ecosystem: "Maven",
      name: "com.google.protobuf:protobuf-java",
      fixed_in: "3.16.1")
    append_osv_vulnerability(advisory: osv_data,
      ecosystem: "RubyGems",
      name: "google-protobuf",
      fixed_in: "3.19.2")
    advisory =  @subject.from_osv(osv_data)
    assert advisory.vulnerabilities.all? do |vulnerability|
      vulnerability.is_a?(AdvisoryDBToolkit::OSV::Interfaces::Vulnerability)
    end
    assert_equal [{
      package_ecosystem: "maven",
      package_name: "com.google.protobuf:protobuf-kotlin",
      first_patched_version: "3.19.2",
      vulnerable_version_range: ">= 3.19.0, < 3.19.2",
    }, {
      package_ecosystem: "maven",
      package_name: "com.google.protobuf:protobuf-kotlin",
      first_patched_version: "3.18.2",
      vulnerable_version_range: ">= 3.18.0, < 3.18.2",
    }, {
      package_ecosystem: "maven",
      package_name: "com.google.protobuf:protobuf-java",
      first_patched_version: "3.19.2",
      vulnerable_version_range: ">= 3.19.0, < 3.19.2",
    }, {
      package_ecosystem: "maven",
      package_name: "com.google.protobuf:protobuf-java",
      first_patched_version: "3.18.2",
      vulnerable_version_range: ">= 3.18.0, < 3.18.2",
    }, {
      package_ecosystem: "maven",
      package_name: "com.google.protobuf:protobuf-java",
      first_patched_version: "3.16.1",
      vulnerable_version_range: "> 0, < 3.16.1",
    }, {
      package_ecosystem: "rubygems",
      package_name: "google-protobuf",
      first_patched_version: "3.19.2",
      vulnerable_version_range: "> 0, < 3.19.2",
    }], advisory.vulnerabilities.map(&:to_h)
  end

  def test_affected_product_with_single_version_and_without_ranges_is_transformed
    osv_data = create_osv_data(vulnerability_count: 1)
    vuln = osv_data["affected"].first
    vuln["ranges"] = []
    vuln["versions"] = ["1.2.3"]
    advisory = @subject.from_osv(osv_data)
    assert_equal "= 1.2.3", advisory.vulnerabilities.first.vulnerable_version_range
  end

  def test_raises_an_error_for_unmapped_vulnerability_packages
    osv_data = create_osv_data(vulnerability_count: 0)
    v = osv_data["affected"]
    v << {
      "package" => {
        "name" => "ignored",
        "ecosystem" => "garbage",
      },
    }

    assert_raises(@subject::UnsupportedOSVEcosystem) do
      @subject.from_osv(osv_data)
    end
  end

  def test_rehydrates_references_and_source_code_location
    osv_data = create_osv_data(vulnerability_count: 0)
    advisory = @subject.from_osv(osv_data)
    assert_nil advisory.source_code_location
    assert_empty advisory.references

    append_osv_reference(advisory: osv_data, url: "http://github.com/advisories/#{osv_data["aliases"][0]}")
    append_osv_reference(advisory: osv_data, url: "https://www.npmjs.com/advisories/1234")
    append_osv_reference(advisory: osv_data, url: "http://nvd.nist.gov/vuln/detail/CVE-2021-0001")
    append_osv_reference(advisory: osv_data, type: "PACKAGE", url: "http://github.com/github/github")

    advisory = @subject.from_osv(osv_data)
    assert_equal "http://github.com/github/github", advisory.source_code_location
    ghsa_reference_set = Set.new(advisory.references)
    # All references except for PACKAGE are interpreted into the references collection.
    assert Set.new(osv_data["references"].map { |r| r["url"] }.reject { |url| url == "http://github.com/github/github" }) == ghsa_reference_set
  end

  def test_rehydrates_cve_id_from_aliases
    osv_data = create_osv_data(vulnerability_count: 0)
    advisory = @subject.from_osv(osv_data)
    assert_nil advisory.cve_id
    expected_cve_id = "CVE-2021-0001"
    osv_data["aliases"] = [expected_cve_id]
    advisory = @subject.from_osv(osv_data)
    assert_equal expected_cve_id, advisory.cve_id
  end

  def test_rehydrates_ghsa_id_from_aliases_if_present
    osv_data = create_osv_data(vulnerability_count: 0)
    osv_data["aliases"] = ["GHSA-2c7v-qcjp-4mg2"]
    advisory = @subject.from_osv(osv_data)
    assert_equal "GHSA-2c7v-qcjp-4mg2", advisory.ghsa_id
  end

  def test_rehydrates_cvss_v4_and_v3_from_severities
    osv_data = create_osv_data(vulnerability_count: 0)
    advisory = @subject.from_osv(osv_data)
    assert_nil advisory.cvss_v3
    assert_nil advisory.cvss_v4

    osv_data["severity"] = [
                              { "type" => "CVSS_V3", "score" => "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:U/C:L/I:H/A:N" },
                              { "type" => "CVSS_V4", "score" => "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:L/VA:L/SC:L/SI:L/SA:L" },
                           ]
    advisory = @subject.from_osv(osv_data)
    assert_equal "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:U/C:L/I:H/A:N", advisory.cvss_v3
    assert_equal "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:L/VA:L/SC:L/SI:L/SA:L", advisory.cvss_v4
  end

  def test_gracefully_handles_minimal_osv_json
    osv_data = create_osv_data(vulnerability_count: 0)
    # Only keep required fields
    osv_data = osv_data.slice("id", "modified")
    osv_data["aliases"] = ["GHSA-2c7v-qcjp-4mg2"]
    advisory = @subject.from_osv(osv_data)
    assert_kind_of AdvisoryDBToolkit::OSV::Interfaces::Advisory, advisory
    assert_equal osv_data["aliases"][0], advisory.ghsa_id
    assert_nil advisory.summary
    assert_nil advisory.description
  end

  def test_all_expected_reference_types_are_handled
    osv_data = create_osv_data(vulnerability_count: 1)

    # Use a set package_ecosystem because other won't translate.
    vuln = osv_data["affected"].first
    vuln["package_ecosystem"] = "maven"

    osv_data["references"] = [
      { "type" => "WEB", "url" => "https://some_web_url.com" },
      { "type" => "PACKAGE", "url" => "https://some_package_url.com" },
      { "type" => "ADVISORY", "url" => "https://some_advisory_url.com" },
      { "type" => "FIX", "url" => "https://some_fix_url.com" },
      { "type" => "REPORT", "url" => "https://some_report_url.com" },
      { "type" => "ARTICLE", "url" => "https://some_article_url.com" },
      { "type" => "EVIDENCE", "url" => "https://some_evidence_url.com" },
    ]

    advisory = @subject.from_osv(osv_data)
    assert_equal advisory.source_code_location, "https://some_package_url.com"

    assert_includes advisory.references, "https://some_web_url.com"
    assert_includes advisory.references, "https://some_advisory_url.com"
    assert_includes advisory.references, "https://some_fix_url.com"
    assert_includes advisory.references, "https://some_report_url.com"
    assert_includes advisory.references, "https://some_article_url.com"
    refute_includes advisory.references, "https://some_package_url.com"
    refute_includes advisory.references, "https://some_evidence_url.com"
  end

  def test_missing_vvrs_on_affected_product_fail_to_parse
    osv_data = create_osv_data(vulnerability_count: 1)

    # Use a set package_ecosystem because other won't translate.
    vuln = osv_data["affected"].first
    vuln["package_ecosystem"] = "maven"

    osv_data["affected"].first["ranges"] = []

    assert_raises AdvisoryDBToolkit::OSV::Transformers::SchemaV1::UnsupportedOSVNoVulnerableVersionRanges do
      @subject.from_osv(osv_data)
    end
  end
end
