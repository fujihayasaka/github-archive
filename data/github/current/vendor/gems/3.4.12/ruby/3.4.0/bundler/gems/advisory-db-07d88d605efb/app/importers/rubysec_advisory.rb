# frozen_string_literal: true

require "severity_calculator"

# represent an advisory from Rubysec
class RubysecAdvisory
  RubysecAdvisoryError = Class.new(StandardError)

  REPO_NWO = "rubysec/ruby-advisory-db"
  FILE_BASE_PATH = "https://github.com/#{REPO_NWO}/blob/master/".freeze
  TREE_BASE_PATH = "https://api.github.com/repos/#{REPO_NWO}/git/trees/master".freeze
  RAW_FILE_BASE_PATH = "https://raw.githubusercontent.com/#{REPO_NWO}/master/".freeze

  # Returns the github.com URL for the given file path
  def self.file_url(path)
    File.join(FILE_BASE_PATH, path)
  end

  # Returns the raw user content URL for the given file path
  def self.raw_file_url(path)
    File.join(RAW_FILE_BASE_PATH, path)
  end

  # Creates a populated instance from a Rubysec advisory file path
  def self.initialize_from_path(path)
    res = Net::HTTP.get_response(URI(raw_file_url(path)))
    case res.code
    when "200"
      parsed_yaml = YAML.safe_load(res.body, permitted_classes: [Date, Time])
      new(raw_payload: parsed_yaml, path: path)
    when "404"
      raise RubysecAdvisoryError, "Advisory file no longer exists on main"
    else
      raise RubysecAdvisoryError, "HTTP response code #{res.code} when fetching advisory file"
    end
  end

  attr_reader :raw_payload, :path

  # raw_payload is the parsed yaml of the advisory file
  # path is the relative path of the advisory file in the repo
  def initialize(raw_payload:, path:)
    if !raw_payload["gem"] || !raw_payload["url"] || !raw_payload["title"] || !raw_payload["date"] || !raw_payload["description"]
      raise RubysecAdvisoryError, "Payload missing required fields" # https://github.com/rubysec/ruby-advisory-db#schema
    end

    @raw_payload = raw_payload
    @path = path
  end

  # link to the advisory on github
  def file_url
    self.class.file_url(path)
  end

  def importer_object
    {
      identifier: identifier,
      cve_id: cve_id,
      rubysec_id: path,
      raw_payload: raw_payload,
      advisory_payload: advisory_payload,
    }
  end

  # Unique identifier for each rubysec advisory
  # Rubysec filenames are CVE/GHSA/OSVDB identifiers
  def identifier
    "rubysec/#{path}"
  end

  # Returns a full CVE ID string
  #
  # The CVE ID is stored as "cve: 2019-1234" in the yaml files
  #   so if the ID is present we return it as a complete ID
  def cve_id
    return nil unless raw_payload["cve"]

    "CVE-#{raw_payload["cve"]}"
  end

  def advisory_payload
    {
      summary: summary,
      description: description,
      severity: severity,
      references: references,
      vulnerabilities: vulnerabilities,
      withdrawn: false,
    }
  end

  def summary
    raw_payload["title"]
  end

  def description
    raw_payload["description"]
  end

  def severity
    SeverityCalculator.calculate(
      cvss_v2_base_score: raw_payload["cvss_v2"],
      cvss_v3_base_score: raw_payload["cvss_v3"],
      cvss_v4_base_score: raw_payload["cvss_v4"],
    )
  end

  def references
    AdvisoryDBToolkit::ReferenceSorter.sorted_reference_list([raw_payload["url"].presence, file_url])
  end

  # We are currently generating incomplete vulnerabilities because we do not populate
  # the vulnerable version range.
  #
  # There is an open Issue (https://github.com/github/team-advisory-database/issues/4604)
  # to tackle this in the future.
  #
  # Currently, we return a vulnerability with the correct package name, ecosystem, and
  # patched version so that all that the Curator has to do is fill in the affected versions
  # and possibly modify the equality operators of the patched version.
  def vulnerabilities
    vulnerabilities = {}

    if raw_payload["patched_versions"]
      raw_payload["patched_versions"].each_with_index do |patched_version, index|
        vulnerabilities[index] = vulnerability(nil, patched_version)
      end

      vulnerabilities
    else
      {
        0 => vulnerability(nil, nil),
      }
    end
  end

  # Returns a populated vulnerability hash
  def vulnerability(version_range, patched_version)
    {
      ecosystem: "rubygems",
      package_name: package_name,
      vulnerable_version_range: version_range,
      first_patched_version: patched_version,
    }
  end

  def package_name
    raw_payload["gem"]
  end
end
