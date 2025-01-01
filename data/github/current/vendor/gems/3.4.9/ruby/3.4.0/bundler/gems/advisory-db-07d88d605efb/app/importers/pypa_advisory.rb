# frozen_string_literal: true

# represent an advisory from the Python Packaging Advisory Database
# These advisories have a yaml file with data about the advisory.
# The path is relative to the affected package, however the advisory also includes package information
#
# For https://github.com/pypa/advisory-database/blob/6a4053574edd830655c61a85e64a2c4d34201502/vulns/django/PYSEC-2021-9.yaml
# The content is quite extensive but the `affects` key and subkeys are the primary source of information

class PypaAdvisory
  PypaAdvisoryError = Class.new(StandardError)

  REPO_NWO = "pypa/advisory-database"
  FILE_BASE_PATH = "https://github.com/#{REPO_NWO}/tree/main/".freeze
  RAW_FILE_BASE_PATH = "https://raw.githubusercontent.com/#{REPO_NWO}/main/".freeze
  ADVISORY_FILE_PATTERN = %r{vulns/[a-z\-0-9]+/PYSEC-[1-9]\d{3}-\d+.yaml}

  def self.file_url(path)
    FILE_BASE_PATH + path
  end

  def self.raw_file_url(path)
    RAW_FILE_BASE_PATH + path
  end

  def self.initialize_from_path(path)
    unless path.match?(ADVISORY_FILE_PATTERN)
      raise PypaAdvisoryError, "Not a valid advisory file path"
    end

    res = Net::HTTP.get_response(URI(raw_file_url(path)))
    case res.code
    when "200"
      parsed_yaml = YAML.safe_load(res.body, permitted_classes: [Date, Time])
      new(raw_payload: parsed_yaml, path: path)
    when "404"
      raise PypaAdvisoryError, "Advisory file no longer exists on main"
    else
      raise StandardError, "HTTP response code #{res.code} when fetching advisory file"
    end
  end

  attr_reader :raw_payload, :path

  def initialize(raw_payload:, path:)
    if raw_payload["id"].presence
      @raw_payload = raw_payload
      @path = path
    else
      raise PypaAdvisoryError, "No advisory ID"
    end
  end

  def identifier
    return "pypa_advisory/#{path}" if path.match?(ADVISORY_FILE_PATTERN)

    raise { NameError.new("Invalid path set for advisory") }
  end

  def cve_id
    raw_payload["aliases"]&.find do |reference|
      AdvisoryDBToolkit::CVEIDValidator::PATTERN.match(reference)
    end
  end

  def ghsa_id
    raw_payload["aliases"]&.find do |reference|
      AdvisoryDBToolkit::GHSAIDValidator::PATTERN.match(reference)
    end
  end

  def advisory_payload
    # TODO: these files are formateed using OSV, so we should use our OSV parser to compute this payload,
    # but AdvisoryDBToolkit::OSV::Transform.osv_to_ghsa(raw_payload) currently throws error because references may not be WEB etc.
    {
      summary: summary,
      description: description,
      severity: nil,
      references: references,
      vulnerabilities: vulnerabilities,
      withdrawn: false,
    }
  end

  def importer_object
    {
      identifier: identifier,
      cve_id: cve_id,
      ghsa_id: ghsa_id,
      raw_payload: raw_payload,
      advisory_payload: advisory_payload,
    }
  rescue StandardError => error
    Failbot.report!(error, { path: path })
  end

  def summary
    raw_payload["summary"].presence
  end

  def description
    raw_payload["details"].presence
  end

  def references
    AdvisoryDBToolkit::ReferenceSorter.sorted_reference_list(
      raw_payload.fetch("references", []).map { |ref| ref.fetch("url") }.append(FILE_BASE_PATH + path),
    )
  end

  def vulnerabilities
    package_ranges = raw_payload.dig("affected", 0, "ranges")&.select { |vuln_range| vuln_range["type"] == "ECOSYSTEM" } # type GIT exists and references repo hashes
    return {} if package_ranges.blank?

    ranges = package_ranges.dig(0, "events").each_slice(2).map do |vuln|
      [
        vuln.dig(0, "introduced"),
        vuln.dig(1, "fixed"),
      ]
    end
    return {} if ranges.empty?

    package_name = raw_payload.dig("affected", 0, "package", "name")

    ranges.each.with_index.with_object({}) do |(vuln_range, index), memo|
      version = ">= #{vuln_range[0]}"
      version += ", < #{vuln_range[1]}" if vuln_range[1].present?

      memo[index] = {
        ecosystem: "pip",
        package_name: package_name,
        vulnerable_version_range: version,
        first_patched_version: vuln_range[1].presence,
      }
    end
  end
end
