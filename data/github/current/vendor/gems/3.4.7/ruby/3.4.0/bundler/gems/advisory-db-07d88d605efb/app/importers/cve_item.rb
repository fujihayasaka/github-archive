# frozen_string_literal: true

require "severity_calculator"

class CVEItem
  attr_reader :raw_payload

  MIN_CURATABLE_YEAR = 2015

  def self.file_path(cve_id)
    year = cve_id.slice(AdvisoryDBToolkit::CVEIDValidator::PATTERN, :year)
    sequence = cve_id.slice(AdvisoryDBToolkit::CVEIDValidator::PATTERN, :sequence)
    "#{year}/#{sequence.sub(/...$/, "xxx")}/#{cve_id}.json"
  end

  def initialize(raw_payload)
    @raw_payload = raw_payload
  end

  def identifier
    "nvd/#{cve_id}"
  end

  def cve_id
    raw_payload["id"]
  end

  def advisory_payload
    {
      summary: summary,
      description: description,
      severity: severity,
      references: references,
      cwe_ids: cwe_ids,
      cvss_v3: cvss_v3_vector_string,
      cvss_v4: cvss_v4_vector_string,
      vulnerabilities: vulnerabilities,
      withdrawn: withdrawn,
    }
  end

  def importer_object
    {
      identifier: identifier,
      cve_id: cve_id,
      raw_payload: raw_payload,
      advisory_payload: advisory_payload,
    }
  end

  private

  def summary
    # right now the summary field is not passed through
    # and there isn't a direct corresponding field in the CVE field
    # so for now we just force it to nil
    nil
  end

  def description
    return @description if defined? @description

    descriptions = raw_payload["descriptions"] || []
    @description = lang_string_value(descriptions) || descriptions.first.fetch("value")
  end

  def references
    return @references if defined? @references

    references = raw_payload["references"] || []
    references.map! { |r| r["url"] }

    @references = AdvisoryDBToolkit::ReferenceSorter.sorted_reference_list(references).unshift("https://nvd.nist.gov/vuln/detail/#{cve_id}")
  end

  def cwe_ids
    return @cwe_ids if defined? @cwe_ids

    weaknesses = raw_payload["weaknesses"] || []

    @cwe_ids = weaknesses.each_with_object([]) do |weakness_data, cwe_ids|
      value = lang_string_value(weakness_data["description"])
      match_data = value&.match(/CWE-\d+/)

      cwe_id = match_data ? match_data[0] : nil
      cwe_ids.append(cwe_id) if cwe_id
    end
  end

  # For CVEs we don't take data from the feed for vulnerabilities
  # See https://github.com/github/advisory-db/issues/326 for more info
  # Could be nice to revisit this in future, and/or work with MITRE to improve data so we can do this accurately
  def vulnerabilities
    {}
  end

  def severity
    return @severity if defined? @severity

    @severity = SeverityCalculator.calculate(
      cvss_v2_base_score: cvss_v2_base_score,
      cvss_v3_base_score: cvss_v3_base_score,
      cvss_v4_base_score: cvss_v4_base_score,
    )
  end

  def withdrawn
    false
  end

  def cvss_v2_base_score
    return @cvss_v2_base_score if defined? @cvss_v2_base_score

    @cvss_v2_base_score = cvss_base_score_for(version: "2")
  end

  def cvss_v3_base_score
    return @cvss_v3_base_score if defined? @cvss_v3_base_score

    @cvss_v3_base_score = cvss_base_score_for(version: "3.1") || cvss_base_score_for(version: "3.0")
  end

  def cvss_v4_base_score
    return @cvss_v4_base_score if defined? @cvss_v4_base_score

    @cvss_v4_base_score = cvss_base_score_for(version: "4.0")
  end

  # Get the base score for any CVSS version.
  # version: One of "2", "3.0", "3.1", or "4.0".
  def cvss_base_score_for(version:)
    primary_cvss_source_for(version: version)&.dig("cvssData", "baseScore")
  end

  def cvss_v3_vector_string
    # We will use either CVSS 3.0 or 3.1, but the API separates them under different keys.
    cvss_v3x = primary_cvss_source_for(version: "3.1") || primary_cvss_source_for(version: "3.0")
    cvss_v3x&.dig("cvssData", "vectorString")
  end

  def cvss_v4_vector_string
    cvss_v4x = primary_cvss_source_for(version: "4.0")
    cvss_v4x&.dig("cvssData", "vectorString")
  end

  # Get the lang_string value for the specified language.
  # See "lang_string" in NVD CVE API JSON schema 2.0
  def lang_string_value(lang_strings, lang: "en")
    desired_lang_string = lang_strings.find { |lang_string| lang_string["lang"] == lang }
    desired_lang_string ? desired_lang_string["value"] : nil
  end

  # Retrieves the first primary source for CVSS info or the first available secondary source if there is no primary source.
  # version: One of "2", "3.0", "3.1", or "4.0".
  def primary_cvss_source_for(version:)
    cvss_metrics = raw_payload.dig("metrics", "cvssMetricV#{version.delete(".")}")
    return unless cvss_metrics

    primary_metric = cvss_metrics.find do |cvss_metric|
      cvss_metric["type"] == "Primary"
    end

    # If there is no primary source, use the first available.
    primary_metric || cvss_metrics.first
  end
end
