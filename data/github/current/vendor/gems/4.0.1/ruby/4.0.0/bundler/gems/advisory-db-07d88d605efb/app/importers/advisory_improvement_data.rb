# frozen_string_literal: true

require "severity_calculator"

# AdvisoryImprovementData Struct
# holds the data needed for advisory improvement
# corresponds with data we get from a hydro request
AdvisoryImprovementData = Struct.new(
  :ghsa_id,
  :summary,
  :description,
  :source_code_location,
  :severity,
  :cvss_v3,
  :cvss_v4,
  :cwe_ids,
  :references,
  :affected_products,
  :actor_id,
  :actor_login,
  :pr_number,
  keyword_init: true, # allow initializing with keyword args
) do
  def self.create_from_improve_advisory_pr_json(pr_number:, json:, actor_login:, actor_id:)
    ghsa = AdvisoryDB::OSV.osv_to_ghsa(json)
    new(
      ghsa_id: ghsa[:ghsa_id],
      summary: ghsa[:summary],
      description: ghsa[:description],
      source_code_location: ghsa[:source_code_location],
      severity: ghsa[:severity],
      cvss_v3: ghsa[:cvss_v3],
      cvss_v4: ghsa[:cvss_v4],
      cwe_ids: ghsa[:cwe_ids],
      references: AdvisoryDBToolkit::ReferenceSorter.sorted_reference_list(ghsa[:references]),
      affected_products: ghsa[:vulnerabilities],
      actor_id: actor_id,
      actor_login: actor_login,
      pr_number: pr_number,
    )
  end

  def identifier
    "advisory_improvement/#{actor_id}/#{ghsa_id}"
  end

  def raw_payload
    to_h
  end

  def cve_id
    Advisory.find_by(ghsa_id: ghsa_id)&.cve_id
  end

  def cvss_v3
    self[:cvss_v3].presence
  end

  def cvss_v4
    self[:cvss_v4].presence
  end

  def severity
    if cvss_v4.present?
      SeverityCalculator.from_cvss_v4(cvss_v4)
    elsif cvss_v3.present?
      SeverityCalculator.from_cvss_v3(cvss_v3)
    elsif self[:severity] == "unknown"
      nil
    else
      self[:severity]
    end
  end

  def vulnerabilities
    vulnerabilities_by_index = {}
    affected_products.each_with_index do |affected_product, index|
      vulnerabilities_by_index[index] = {
        ecosystem: affected_product[:package_ecosystem],
        package_name: affected_product[:package_name],
        vulnerable_version_range: affected_product[:vulnerable_version_range],
        first_patched_version: affected_product[:first_patched_version],
        withdrawn: false,
      }
    end
    vulnerabilities_by_index
  end

  def advisory_payload
    {
      summary: summary,
      description: description,
      source_code_location: source_code_location,
      severity: severity,
      cvss_v3: cvss_v3,
      cvss_v4: cvss_v4,
      references: references || [],
      cwe_ids: cwe_ids,
      vulnerabilities: vulnerabilities,
      withdrawn: false,
    }
  end

  def advisory_payload_changes(advisory_review:)
    review_data = self.class.new(
      ghsa_id: advisory_review.ghsa_id,
      summary: advisory_review.summary,
      description: advisory_review.description,
      source_code_location: advisory_review.source_code_location,
      severity: advisory_review.severity,
      cvss_v3: advisory_review.cvss_v3,
      cvss_v4: advisory_review.cvss_v4,
      cwe_ids: advisory_review.cwe_ids,
      references: advisory_review.references,
      affected_products: advisory_review.vulnerabilities.values.map do |v|
        vulnerability = v.dup.symbolize_keys
        vulnerability[:package_ecosystem] = vulnerability.delete(:ecosystem)
        vulnerability
      end,
    )
    {
      ghsa_id: changes_for(:ghsa_id, review_data),
      summary: changes_for(:summary, review_data),
      description: changes_for(:description, review_data),
      source_code_location: changes_for(:source_code_location, review_data),
      severity: changes_for(:severity, review_data),
      cvss_v3: changes_for(:cvss_v3, review_data),
      cvss_v4: changes_for(:cvss_v4, review_data),
      cwe_ids: changes_for(:cwe_ids, review_data),
      references: changes_for(:references, review_data),
      vulnerabilities: changes_for(:vulnerabilities, review_data),
    }.compact
  end

  def importer_object
    {
      identifier: identifier,
      ghsa_id: ghsa_id,
      cve_id: cve_id,
      raw_payload: raw_payload,
      advisory_payload: advisory_payload,
    }
  end

  # override #to_h so the hash has string keys
  # this allows it to be used as args for ActiveJob
  def to_h
    super.deep_stringify_keys
  end

  def changes_for(attribute, current)
    current_value = current.send(attribute)
    new_value = send(attribute)
    [current_value, new_value] unless current_value == new_value
  end
end
