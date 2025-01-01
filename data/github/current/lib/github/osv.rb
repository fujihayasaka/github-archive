# typed: true
# frozen_string_literal: true

require "advisory_db_toolkit"

module GitHub
  module OSV
    extend self

    def ghsa_to_osv(vulnerability)
      interface = advisory_interface(vulnerability)
      AdvisoryDBToolkit::OSV::Transform.to_osv(interface)
    end

    private

    def advisory_interface(vulnerability)
      AdvisoryDBToolkit::OSV::Interfaces::Advisory.new.tap do |interface|
        # General info
        interface.ghsa_id = vulnerability.ghsa_id
        interface.summary = vulnerability.summary
        interface.description = vulnerability.description
        interface.severity = vulnerability.severity&.upcase
        interface.cve_id = vulnerability.cve_id

        # Metadata
        interface.cvss_v3 = vulnerability.cvss_v3

        if GitHub.flipper[:advisory_db_cvss_v4].enabled?
          interface.cvss_v4 = vulnerability.cvss_v4
        end

        interface.reviewed = !vulnerability.unreviewed?
        interface.source_code_location = vulnerability.source_code_location

        # Relationships
        interface.credits = [] # Not currently used in community contributions
        interface.cwe_ids = vulnerability.cwes.map(&:cwe_id)
        interface.references = vulnerability.vulnerability_references.map(&:url)
        interface.vulnerabilities = vulnerability.vulnerable_version_ranges.map do |vvr|
          vulnerability_interface(vvr)
        end

        # Date fields
        interface.nvd_published_at = vulnerability.nvd_published_at
        interface.published_at = vulnerability.published_at
        interface.reviewed_at = vulnerability.reviewed_at
        interface.updated_at = vulnerability.updated_at
        interface.withdrawn_at = vulnerability.withdrawn_at
      end
    end

    def vulnerability_interface(vulnerable_version_range)
      AdvisoryDBToolkit::OSV::Interfaces::Vulnerability.new.tap do |interface|
        interface.package_ecosystem = vulnerable_version_range.ecosystem&.downcase
        interface.package_name = vulnerable_version_range.affects
        interface.vulnerable_version_range = vulnerable_version_range.requirements
        interface.first_patched_version = vulnerable_version_range.fixed_in || ""
        interface.affected_functions = vulnerable_version_range.affected_functions || []
      end
    end
  end
end
