# frozen_string_literal: true

require "severity_calculator"

# RepositoryAdvisoryCurationData Struct
# holds the data needed for repo advisory curation
# corresponds with data we get from a hydro request
RepositoryAdvisoryCurationData = Struct.new(
  :ghsa_id,
  :permalink,
  :title,
  :description,
  :severity,
  :cve_id,
  :cvss_v3,
  :cvss_v4,
  :cwe_ids,
  :affected_products,
  keyword_init: true, # allow initializing with keyword args
) do
  # accepts a raw hydro message, and returns RepositoryAdvisoryCurationData
  def self.create_from_repository_advisory_hydro_message(msg)
    new(
      ghsa_id: msg[:repository_advisory_content][:ghsa_id],
      permalink: msg[:repository_advisory_content][:permalink],
      title: msg[:repository_advisory_content][:title],
      description: msg[:repository_advisory_content][:description],
      severity: msg[:repository_advisory_content][:severity].to_s.downcase, # enum comes in as a symbol, causes issue
      cve_id: msg[:repository_advisory_content][:cve_id],
      cwe_ids: msg[:repository_advisory_content][:cwe_ids],
      cvss_v3: msg[:repository_advisory_content][:cvss_v3],
      cvss_v4: msg[:repository_advisory_content][:cvss_v4],
      affected_products: msg[:repository_advisory_content][:affected_products],
    )
  end

  def identifier
    "repository_advisory/#{ghsa_id}"
  end

  def raw_payload
    to_h
  end

  def references
    [permalink]
  end

  def cve_id
    self[:cve_id].presence
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
    else
      self[:severity]
    end
  end

  def source_code_location
    permalink.split("/security/advisories/GHSA").first
  end

  def vulnerabilities
    vulnerabilities_by_index = {}
    affected_products&.each_with_index do |affected_product, index|
      vulnerabilities_by_index[index] = {
        ecosystem: affected_product["package_ecosystem"],
        package_name: affected_product["package_name"],
        vulnerable_version_range: affected_product["vulnerable_version_range"],
        first_patched_version: affected_product["first_patched_version"],
      }
      # In dotcom, RepositoryAdvisories use PascalCase for RubyGems, but not other ecosystems
      if vulnerabilities_by_index[index][:ecosystem] == "RubyGems"
        vulnerabilities_by_index[index][:ecosystem] = "rubygems"
      end
    end
    vulnerabilities_by_index
  end

  def advisory_payload
    {
      summary: title,
      description: description,
      source_code_location: source_code_location,
      severity: severity,
      cvss_v3: cvss_v3,
      cvss_v4: cvss_v4,
      references: references,
      cwe_ids: cwe_ids,
      vulnerabilities: vulnerabilities,
      withdrawn: false,
    }
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

  # override #to_h so the hash string keys
  # this allows it to be used as args for ActiveJob
  def to_h
    super.deep_stringify_keys
  end
end
