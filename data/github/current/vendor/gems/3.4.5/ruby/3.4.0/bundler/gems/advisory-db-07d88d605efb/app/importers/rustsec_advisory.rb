# frozen_string_literal: true

require "severity_calculator"

# Represent an advisory from Rustsec
class RustsecAdvisory
  RustsecAdvisoryError = Class.new(StandardError)

  REPO_NWO = "RustSec/advisory-db"
  FILE_BASE_PATH = "https://github.com/#{REPO_NWO}/blob/main/".freeze
  RAW_FILE_BASE_PATH = "https://raw.githubusercontent.com/#{REPO_NWO}/main/".freeze
  RUSTSEC_ID_PATTERN = /RUSTSEC-(2\d{3})-(\d{4,31})/
  RUSTSEC_ADVISORY_PATTERN = %r{
    \A
    \s* # Allow leading whitespace

    # Matches all of the TOML front matter
    ```toml\R
    (?<toml>.*?)\R
    ```\R

    \s* # Allow whitespace after front matter
    (?:\#\s+(?<summary>.+?)\R)? # Match optional summary
    \s* # Allow whitespace between summary and description
    (?<description>.*) # Use the rest of the file as the description
    \z
  }mx

  def self.file_url(path)
    FILE_BASE_PATH + path
  end

  def self.raw_file_url(path)
    RAW_FILE_BASE_PATH + path
  end

  def self.initialize_from_path(path)
    raise RustsecAdvisoryError, "Cannot import a non-RUSTSEC advisory" unless path.match?(RUSTSEC_ID_PATTERN)

    res = Net::HTTP.get_response(URI(raw_file_url(path)))
    case res.code
    when "200"
      new(raw_payload: String.new(res.body, encoding: "UTF-8"), path: path)
    when "404"
      raise RustsecAdvisoryError, "Advisory file no longer exists on main"
    else
      raise RustsecAdvisoryError, "HTTP response code #{res.code} when fetching advisory file"
    end
  end

  attr_reader :raw_payload, :path

  def initialize(raw_payload:, path:)
    raise RustsecAdvisoryError, "Cannot import a non-RUSTSEC advisory" unless path.match?(RUSTSEC_ID_PATTERN)
    raise RustsecAdvisoryError, "Ensure raw_payload is using UTF-8 encoding" unless raw_payload.encoding == Encoding::UTF_8

    @path = path
    @raw_payload = raw_payload
  end

  def parsed_payload
    parts = RUSTSEC_ADVISORY_PATTERN.match(raw_payload)
    toml = parts[:toml]
    summary = parts[:summary]
    description = parts[:description]
    parsed_toml = Tomlrb.parse(toml)

    # Merge everything together into a single hash for the parsed payload
    parsed_toml.merge({ "summary" => summary, "description" => description })
  end

  # Rustsec advisories have an "aliases" field that can contain one or more of CVE IDs and GHSA IDs.
  # Since we have a restriction on one CVE ID per Advisory Review, and because it would be
  # complicated to assume user-provided data is correct and match CVE IDs or GHSA IDs with other
  # identifiers, we create one feed entry per alias which results in one Advisory Review per alias.
  # This allows a Curator to look at the data and merge or resolve as needed.
  def importer_objects
    return @importer_objects if defined? @importer_objects
    return [] if type == "unmaintained"

    importer_objects = []

    if cve_ids.count <= 1 && ghsa_ids.count <= 1
      importer_objects <<
        {
          identifier: "rustsec/#{path}",
          cve_id: cve_ids.first,
          ghsa_id: ghsa_ids.first,
          rustsec_id: path,
          raw_payload: parsed_payload,
          advisory_payload: advisory_payload,
        }
    else
      cve_ids.each do |cve_id|
        importer_objects <<
          {
            identifier: "rustsec/#{path}/#{cve_id}",
            cve_id: cve_id,
            ghsa_id: nil,
            rustsec_id: "#{path}/#{cve_id}",
            raw_payload: parsed_payload,
            advisory_payload: advisory_payload,
          }
      end

      ghsa_ids.each do |ghsa_id|
        importer_objects <<
          {
            identifier: "rustsec/#{path}/#{ghsa_id}",
            cve_id: nil,
            ghsa_id: ghsa_id,
            rustsec_id: "#{path}/#{ghsa_id}",
            raw_payload: parsed_payload,
            advisory_payload: advisory_payload,
          }
      end
    end

    @importer_objects = importer_objects
  end

  # Returns an array of CVE ID strings
  #
  # If present, CVE IDs are stored as "aliases = ["CVE-2020-12345", "CVE-2020-12346"]" in the
  #   YAML files, so if there is one or more, we return them as an array of IDs
  def cve_ids
    Array.wrap(parsed_payload.dig("advisory", "aliases")).select { |identifier| AdvisoryDBToolkit::CVEIDValidator.valid?(identifier) }
  end

  # Returns an array of GHSA ID strings
  #
  # If present, GHSA IDs are stored as "aliases = ["GHSA-abcd-1234"]" in the
  #   YAML files, so if there is one or more, we return them as an array of IDs
  def ghsa_ids
    Array.wrap(parsed_payload.dig("advisory", "aliases")).select { |identifier| AdvisoryDBToolkit::GHSAIDValidator.valid?(identifier) }
  end

  def advisory_payload
    {
      summary: summary,
      description: description,
      severity: severity,
      cvss_v3: cvss_v3,
      cvss_v4: cvss_v4,
      references: references,
      vulnerabilities: vulnerabilities,
      withdrawn: parsed_payload["withdrawn"].present?,
    }
  end

  def summary
    parsed_payload["summary"]
  end

  def description
    parsed_payload["description"]
  end

  # Some sources, such as Rubysec, have a score field for v2, v3, and v4 of CVSS.
  # However, Rustsec only has a generic CVSS vector string field, so we have to calculate
  # the severity ourselves. We prefer v4, so we check that first.
  def severity
    return unless cvss

    case cvss
    when cvss_v4
      SeverityCalculator.from_cvss_v4(cvss_v4)
    when cvss_v3
      SeverityCalculator.from_cvss_v3(cvss_v3)
    end
  end

  def references
    AdvisoryDBToolkit::ReferenceSorter.sorted_reference_list([parsed_payload["advisory"]["url"].presence, "https://rustsec.org/advisories/#{path[RUSTSEC_ID_PATTERN]}.html"])
  end

  def vulnerabilities
    vulnerabilities = {}

    patched = parsed_payload["versions"].fetch("patched", [])
    unaffected = parsed_payload["versions"].fetch("unaffected", [])

    # There are cases when either patched array size >= unaffected array size
    # or patched size < unaffected size, so we make sure to iterate as many
    # times as the one of greater length, so no information is missed.
    [patched.size, unaffected.size].max.times do |index|
      first_patched_version = patched[index]
      vulnerable_version_range = nil
      if unaffected[index]
        version_range = convert_unaffected_to_version_range(unaffected[index])

        if version_range.operator.nil?
          # when unaffected is a specific version, treat it as patched
          first_patched_version = [first_patched_version, version_range.to_s].compact.join(", ")
        else
          vulnerable_version_range = version_range.to_s
        end
      end

      vulnerabilities.merge!(index => {
        ecosystem: "rust",
        package_name: package_name,
        vulnerable_version_range: vulnerable_version_range,
        first_patched_version: first_patched_version,
      })
    end

    vulnerabilities
  end

  def convert_unaffected_to_version_range(unaffected)
    version_range = AdvisoryDB::VersionRange.new(unaffected)

    version_range.operator =
      case version_range.operator
      when ">" then "<="
      when ">=" then "<"
      when "<" then ">="
      when "<=" then ">"
      when "=" then nil
      end

    version_range
  end

  def package_name
    parsed_payload["advisory"]["package"]
  end

  def cvss
    parsed_payload["advisory"]["cvss"]
  end

  def cvss_v3
    cvss if cvss&.start_with?("CVSS:3.0", "CVSS:3.1")
  end

  def cvss_v4
    cvss if cvss&.start_with?("CVSS:4.0")
  end

  def type
    parsed_payload["advisory"]["informational"]
  end
end
