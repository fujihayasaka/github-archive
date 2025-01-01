# frozen_string_literal: true

require "test_helper"

class OSVInterfacesAdvisoryTest < Minitest::Test
  def setup
    @subject = AdvisoryDBToolkit::OSV::Interfaces::Advisory.new
  end

  def test_it_is_instantiatable
    @subject.ghsa_id = "MY-GHSA-ID"
    assert_equal "MY-GHSA-ID", @subject.ghsa_id
  end

  def test_can_be_converted_to_a_hash
    # General info
    @subject.ghsa_id = ghsa_id = "ghsa_id"
    @subject.summary = summary = "summary"
    @subject.description = description = "description"
    @subject.severity = severity = "severity"
    @subject.cve_id = cve_id = "cve_id"

    # Metadata
    @subject.cvss_v3 = cvss_v3 = "cvss_v3"
    @subject.cvss_v4 = cvss_v4 = "cvss_v4"
    @subject.identifier = identifier = "identifier"
    @subject.reviewed = reviewed = "reviewed"
    @subject.source_code_location = source_code_location = "source_code_location"

    # Relationships
    @subject.credits = credits = ["credits"]
    @subject.cwe_ids = cwe_ids = ["cwe_ids"]
    @subject.references = references = ["references"]
    @subject.vulnerabilities = vulnerabilities = [
      AdvisoryDBToolkit::OSV::Interfaces::Vulnerability.new.tap do |vulnerability|
        vulnerability.package_ecosystem = "package_ecosystem"
        vulnerability.package_name = "package_name"
        vulnerability.first_patched_version = "first_patched_version"
        vulnerability.vulnerable_version_range = "vulnerable_version_range"
      end,
    ]

    # Date fields
    @subject.nvd_published_at = nvd_published_at = "nvd_published_at"
    @subject.published_at = published_at = "published_at"
    @subject.reviewed_at = reviewed_at = "reviewed_at"
    @subject.updated_at = updated_at = "updated_at"
    @subject.withdrawn_at = withdrawn_at = "withdrawn_at"

    assert_equal({
      ghsa_id:,
      summary:,
      description:,
      severity:,
      cve_id:,

      # Metadata
      cvss_v3:,
      cvss_v4:,
      identifier:,
      reviewed:,
      source_code_location:,

      # Relationships
      credits:,
      cwe_ids:,
      references:,
      vulnerabilities: vulnerabilities.map(&:to_h),

      # Date fields
      nvd_published_at:,
      published_at:,
      reviewed_at:,
      updated_at:,
      withdrawn_at:,
    }, @subject.to_h)
  end
end
