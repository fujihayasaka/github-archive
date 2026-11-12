# frozen_string_literal: true

# Represents an advisory from the Go vulnerability database
# Format of YAML found here: https://github.com/golang/vulndb/blob/master/doc/format.md
# Note that this format is internal and subject to changes, so periodic updates may be needed.
class GoAdvisory
  def initialize(raw_payload:)
    @raw_payload = raw_payload
  end

  def importer_objects
    return @importer_objects if defined? @importer_objects

    importer_objects = []

    osv_transform = AdvisoryDB::OSV.osv_to_ghsa(raw_payload, custom_identifier: identifier)

    # Golang vulns store the url reference to their vulnerability in the database_specific field.
    database_specific_affected_fields = raw_payload["affected"].filter_map { |a| a.dig("database_specific", "url") if a.present? }.uniq
    database_specific_affected_fields.each { |url| osv_transform[:references] << url }
    osv_transform[:references] = AdvisoryDBToolkit::ReferenceSorter.sorted_reference_list(osv_transform[:references])

    vulnerabilities_hash_instead_of_array = {}
    # OSV transform returns ecosystem in package_ecosystem but ingestion expects `ecosystem`
    osv_transform[:vulnerabilities].each do |v|
      v[:ecosystem] = v[:package_ecosystem]
      v.delete(:package_ecosystem)
    end

    # OSV transform returns vulnerabilities as an array but ingestion expects a hash
    osv_transform[:vulnerabilities].each_with_index { |v, k| vulnerabilities_hash_instead_of_array[k] = v }
    osv_transform[:vulnerabilities] = vulnerabilities_hash_instead_of_array

    if cve_ids.length <= 1 && ghsa_ids.length <= 1
      importer_objects << {
        identifier: identifier,
        cve_id: cve_ids.first,
        ghsa_id: ghsa_ids.first,
        raw_payload: raw_payload,
        advisory_payload: osv_transform,
      }
    else
      cve_ids.each do |cve_id|
        importer_objects << {
          identifier: "#{identifier}/#{cve_id}",
          cve_id: cve_id,
          ghsa_id: nil,
          raw_payload: raw_payload,
          advisory_payload: osv_transform,
        }
      end

      ghsa_ids.each do |ghsa_id|
        importer_objects << {
          identifier: "#{identifier}/#{ghsa_id}",
          cve_id: nil,
          ghsa_id: ghsa_id,
          raw_payload: raw_payload,
          advisory_payload: osv_transform,
        }
      end
    end

    @importer_objects = importer_objects
  end

  # Unique identifier. Example: "golang/GO-2020-0014"
  def identifier
    "golang/#{raw_payload["id"]}"
  end

  # Returns all CVE looking IDs or empty array.
  def cve_ids
    raw_payload["aliases"]&.select { |a| a.start_with?("CVE-") } || []
  end

  # Short 255-character summary is not provided in a Go advisory.
  def summary
    nil
  end

  def description
    raw_payload["details"]
  end

  # No severity information is available in the Golang advisory
  def severity
    nil
  end

  # Returns all GHSA looking IDs or empty array.
  def ghsa_ids
    raw_payload["aliases"]&.select { |a| a.upcase.start_with?("GHSA-") } || []
  end

  # No CVSS is available in Golang advisories
  def cvss
    nil
  end

  private

  attr_reader :raw_payload
end
