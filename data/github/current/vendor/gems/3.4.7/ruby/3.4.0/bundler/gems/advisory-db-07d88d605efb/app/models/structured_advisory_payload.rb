# frozen_string_literal: true

class StructuredAdvisoryPayload < ApplicationRecord
  self.table_name = "advisory_payloads"

  extend ::GitHub::Encoding
  force_utf8_encoding :summary
  force_utf8_encoding :description

  has_many :vulnerabilities, class_name: "StructuredAdvisoryPayloadVulnerability", dependent: :destroy, foreign_key: "advisory_payload_id", inverse_of: "payload"
  has_many :references, class_name: "StructuredAdvisoryPayloadReference", dependent: :destroy, foreign_key: "advisory_payload_id", inverse_of: "payload"
  has_many :cwe_ids, class_name: "StructuredAdvisoryPayloadCWEID", dependent: :destroy, foreign_key: "advisory_payload_id", inverse_of: "payload"

  belongs_to :payload_container, polymorphic: true

  before_destroy do
    versions.destroy_all
  end

  def comparison_hash
    {
      description: description,
      severity: severity,
      references: references.map { |r| { url: r.url } },
      vulnerabilities: vulnerabilities.map do |vuln|
        {
          package_ecosystem: vuln.package_ecosystem,
          package_name: vuln.package_name,
          vulnerable_version_range: vuln.vulnerable_version_range,
          first_patched_version: vuln.first_patched_version,
        }
      end,
      cwe_ids: cwe_ids.map(&:cwe_id),
      cvss_v3: cvss_v3,
      cvss_v4: cvss_v4,
    }
  end
end
