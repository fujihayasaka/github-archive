# frozen_string_literal: true

# An interface layer between AdvisoryDB and the OSV transformation methods
module AdvisoryDB
  module OSV
    extend self

    def osv_to_ghsa(osv_data, custom_identifier: nil)
      interface = AdvisoryDBToolkit::OSV::Transform.from_osv(osv_data)
      interface.identifier = custom_identifier if AdvisoryDBToolkit::Utility.present?(custom_identifier)
      interface.to_h
    end

    def ghsa_to_osv(advisory)
      interface = advisory_interface(advisory)
      AdvisoryDBToolkit::OSV::Transform.to_osv(interface)
    end

    private

    def advisory_interface(advisory)
      AdvisoryDBToolkit::OSV::Interfaces::Advisory.new.tap do |interface|
        # General info
        interface.ghsa_id = advisory.ghsa_id
        interface.summary = advisory.summary
        interface.description = advisory.description
        interface.severity = advisory.severity&.upcase
        interface.cve_id = advisory.cve_id

        # Metadata
        interface.cvss_v3 = advisory.cvss_v3
        interface.cvss_v4 = advisory.cvss_v4
        interface.reviewed = advisory.reviewed?
        interface.source_code_location = advisory.source_code_location

        # Relationships
        interface.credits = [] # Not currently used in community contributions
        interface.cwe_ids = advisory.cwes.pluck(:cwe_id)
        interface.references = advisory.references.map(&:url)
        interface.vulnerabilities = advisory.vulnerabilities.filter_map do |v|
          next if v.withdrawn_at?

          vulnerability_interface(v)
        end

        # Date fields
        interface.nvd_published_at = advisory.nvd_published_at
        interface.published_at = advisory.published_at
        interface.reviewed_at = advisory.reviewed_at
        interface.updated_at = advisory.updated_at
        interface.withdrawn_at = advisory.withdrawn_at
      end
    end

    def vulnerability_interface(vulnerability)
      AdvisoryDBToolkit::OSV::Interfaces::Vulnerability.new.tap do |interface|
        interface.package_ecosystem = vulnerability.package_ecosystem&.downcase
        interface.package_name = vulnerability.package_name
        interface.first_patched_version = vulnerability.first_patched_version
        interface.vulnerable_version_range = vulnerability.vulnerable_version_range || ""
      end
    end
  end
end
