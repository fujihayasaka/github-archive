# frozen_string_literal: true

require "test_helper"
require_relative "../osv_helper"
require "advisory_db_toolkit"

class OSVTransformersSchemaV1ToOSVTest < Minitest::Test
  include OSVHelper

  def setup
    @subject = AdvisoryDBToolkit::OSV::Transformers::SchemaV1
  end

  def test_converts_advisories_to_osv_version_1_3_0
    advisory = create_advisory_interface
    osv = @subject.to_osv(advisory)
    @subject.validate_schema!(osv)
    assert_kind_of Hash, osv
    assert_equal "1.4.0", osv["schema_version"]
    assert_equal advisory.ghsa_id, osv["id"]
    assert_equal advisory.summary, osv["summary"]
    assert_equal advisory.description, osv["details"]
  end

  def test_normalizes_irregular_line_breaks_in_advisory_description
    advisory = create_advisory_interface
    advisory.description = "This\r\nis\ra\ntest"
    osv = @subject.to_osv(advisory)
    refute_equal "This\r\nis\ra\ntest", osv["details"]
    assert_equal "This\nis\na\ntest", osv["details"]
  end

  def test_formats_datetime_properites_to_utc_strings_when_present
    advisory = create_advisory_interface
    osv = @subject.to_osv(advisory)
    assert_equal advisory.updated_at.utc.strftime("%FT%TZ"), osv["modified"]
    assert_equal advisory.published_at.utc.strftime("%FT%TZ"), osv["published"]
    assert_nil osv["withdrawn"]
  end

  def test_formats_cvssv3_score_as_severity_when_present
    advisory = create_advisory_interface
    osv = @subject.to_osv(advisory)
    assert_empty osv["severity"]

    advisory = create_advisory_interface
    advisory.cvss_v3 = "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:U/C:L/I:H/A:N"
    osv = @subject.to_osv(advisory)
    assert_equal [
      { "type" => "CVSS_V3", "score" => advisory.cvss_v3 },
    ], osv["severity"]
  end

  def test_formats_cvssv4_score_as_severity_when_present
    advisory = create_advisory_interface
    osv = @subject.to_osv(advisory)
    assert_empty osv["severity"]

    advisory = create_advisory_interface
    advisory.cvss_v4 = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:L/VA:L/SC:L/SI:L/SA:L"
    osv = @subject.to_osv(advisory)
    assert_equal [
      { "type" => "CVSS_V4", "score" => advisory.cvss_v4 },
    ], osv["severity"]
  end

  def test_excludes_severity_when_blank
    advisory = create_advisory_interface
    osv = @subject.to_osv(advisory)
    assert_empty osv["severity"]

    advisory.cvss_v3 = ""
    osv = @subject.to_osv(advisory)
    assert_empty osv["severity"]
  end

  def test_formats_cve_id_as_an_aliase_when_present
    advisory = create_advisory_interface
    osv = @subject.to_osv(advisory)
    assert_empty osv["aliases"]

    advisory = create_advisory_interface
    advisory.cve_id = "CVE-2021-0001"
    osv = @subject.to_osv(advisory)
    assert_equal ["CVE-2021-0001"], osv["aliases"]
  end

  def test_formats_references_and_source_code_location_when_present
    advisory = create_advisory_interface
    advisory.references = []
    osv = @subject.to_osv(advisory)
    assert_empty osv["references"]

    github_ref = append_advisory_reference(advisory: advisory, url: "http://github.com/advisories/#{advisory.ghsa_id}")
    nist_ref = append_advisory_reference(advisory: advisory, url: "http://nvd.nist.gov/vuln/detail/CVE-2021-0001")
    node_ref = append_advisory_reference(advisory: advisory, url: "https://www.npmjs.com/advisories/1234")
    advisory.source_code_location = "http://github.com/github/github"
    osv = @subject.to_osv(advisory)
    assert_equal [
      { "type" => "WEB", "url" => node_ref },
      { "type" => "ADVISORY", "url" => github_ref },
      { "type" => "PACKAGE", "url" => advisory.source_code_location },
      { "type" => "ADVISORY", "url" => nist_ref },
    ], osv["references"]
  end

  def test_formats_vulnerabilities_as_individual_affected_packages
    advisory = create_advisory_interface
    osv = @subject.to_osv(advisory)
    assert_empty osv["affected"]

    append_vulnerability_interface(advisory: advisory,
      package_ecosystem: "maven",
      package_name: "com.google.protobuf:protobuf-kotlin",
      first_patched_version: "3.19.2",
      vulnerable_version_range: ">= 3.19.0, < 3.19.2")
    append_vulnerability_interface(advisory: advisory,
      package_ecosystem: "maven",
      package_name: "com.google.protobuf:protobuf-kotlin",
      first_patched_version: "3.18.2",
      vulnerable_version_range: ">= 3.18.0, < 3.18.2")
    append_vulnerability_interface(advisory: advisory,
      package_ecosystem: "maven",
      package_name: "com.google.protobuf:protobuf-java",
      first_patched_version: "3.19.2",
      vulnerable_version_range: ">= 3.19.0, < 3.19.2")
    append_vulnerability_interface(advisory: advisory,
      package_ecosystem: "maven",
      package_name: "com.google.protobuf:protobuf-java",
      first_patched_version: "3.18.2",
      vulnerable_version_range: ">= 3.18.0, < 3.18.2")
    append_vulnerability_interface(advisory: advisory,
      package_ecosystem: "maven",
      package_name: "com.google.protobuf:protobuf-java",
      first_patched_version: "3.16.1",
      vulnerable_version_range: "< 3.16.1")
    append_vulnerability_interface(advisory: advisory,
      package_ecosystem: "rubygems",
      package_name: "google-protobuf",
      first_patched_version: "3.19.2",
      vulnerable_version_range: "< 3.19.2")
    osv = @subject.to_osv(advisory)
    assert_equal [
      {
        "package" => {
          "ecosystem" => "Maven",
          "name" => "com.google.protobuf:protobuf-kotlin",
        },
        "ranges" => [{
          "type" => "ECOSYSTEM",
          "events" => [{ "introduced" => "3.19.0" }, { "fixed" => "3.19.2" }],
        }],
      },
      {
        "package" => {
          "ecosystem" => "Maven",
          "name" => "com.google.protobuf:protobuf-kotlin",
        },
        "ranges" => [{
          "type" => "ECOSYSTEM",
          "events" => [{ "introduced" => "3.18.0" }, { "fixed" => "3.18.2" }],
        }],
      },
      {
        "package" => {
          "ecosystem" => "Maven",
          "name" => "com.google.protobuf:protobuf-java",
        },
        "ranges" => [{
          "type" => "ECOSYSTEM",
          "events" => [{ "introduced" => "3.19.0" }, { "fixed" => "3.19.2" }],
        }],
      },
      {
        "package" => {
          "ecosystem" => "Maven",
          "name" => "com.google.protobuf:protobuf-java",
        },
        "ranges" => [{
          "type" => "ECOSYSTEM",
          "events" => [{ "introduced" => "3.18.0" }, { "fixed" => "3.18.2" }],
        }],
      },
      {
        "package" => {
          "ecosystem" => "Maven",
          "name" => "com.google.protobuf:protobuf-java",
        },
        "ranges" => [{
          "type" => "ECOSYSTEM",
          "events" => [{ "introduced" => "0" }, { "fixed" => "3.16.1" }],
        }],
      },
      {
        "package" => {
          "ecosystem" => "RubyGems",
          "name" => "google-protobuf",
        },
        "ranges" => [{
          "type" => "ECOSYSTEM",
          "events" => [{ "introduced" => "0" }, { "fixed" => "3.19.2" }],
        }],
      },
    ], osv["affected"]
  end

  def test_maps_vulnerability_packages_appropriately
    advisory = create_advisory_interface
    ecosystem_map = AdvisoryDBToolkit::Ecosystems::ECOSYSTEM_OSV_MAP
    ecosystem_map.each_key do |ecosystem|
      next unless AdvisoryDBToolkit::Ecosystems.ghsa_to_osv_ecosystem(ecosystem)

      append_vulnerability_interface(advisory: advisory, package_ecosystem: ecosystem)
    end

    osv = @subject.to_osv(advisory)
    mapped_packages = osv["affected"].map { |v| v["package"]["ecosystem"] }
    assert_equal ecosystem_map.values.compact, mapped_packages
  end

  # This test can be removed/disabled when we have no supported ecosystems that
  # remain unmapped to an OSV supported ecosystem
  def test_raises_an_error_for_unmapped_vulnerability_packages
    advisory = create_advisory_interface
    append_vulnerability_interface(advisory: advisory, package_ecosystem: "other")
    assert_raises(@subject::UnsupportedOSVEcosystem) do
      @subject.to_osv(advisory)
    end
  end

  def test_handles_vulnerabilities_with_no_ecosystem
    advisory = create_advisory_interface
    append_vulnerability_interface(advisory: advisory, package_ecosystem: nil)
    assert_raises(@subject::UnsupportedOSVEcosystem) do
      @subject.to_osv(advisory)
    end
  end

  def test_includes_ghsa_specific_data_like_severity_rating_and_cwe_ids
    advisory = create_advisory_interface
    advisory.severity = "low"
    advisory.cwe_ids = ["CWE-79", "CWE-1302"]
    advisory.nvd_published_at = Time.now
    advisory.reviewed = true
    osv = @subject.to_osv(advisory)
    assert_equal advisory.severity, osv["database_specific"]["severity"]
    assert_equal advisory.cwe_ids, osv["database_specific"]["cwe_ids"]
    assert_equal advisory.reviewed, osv["database_specific"]["github_reviewed"]
    assert_equal advisory.reviewed_at.utc.strftime("%FT%TZ"), osv["database_specific"]["github_reviewed_at"]
    assert_equal advisory.nvd_published_at.utc.strftime("%FT%TZ"), osv["database_specific"]["nvd_published_at"]
  end
end
