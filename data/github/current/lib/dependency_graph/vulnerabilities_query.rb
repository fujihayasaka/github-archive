# typed: true
# frozen_string_literal: true

module DependencyGraph::VulnerabilitiesQuery
  include PlatformHelper

  def self.vulnerabilities_for_range_ids(range_ids:, batch_size: 100)
    hash_of_vvr_id_to_vulns = {}
    return hash_of_vvr_id_to_vulns if range_ids.empty?

    VulnerableVersionRange.preload(:vulnerability).where(id: range_ids).in_batches(of: batch_size) do |batch|
      batch.each do |vvr|
        security_vulnerability = vvr.becomes(SecurityVulnerability)
        security_advisory = vvr.vulnerability.becomes(SecurityAdvisory)

        hash_of_vvr_id_to_vulns[vvr.id] = {
          vulnerability: security_vulnerability,
          advisory: security_advisory
        }
      end
    end
    hash_of_vvr_id_to_vulns
  end
end
