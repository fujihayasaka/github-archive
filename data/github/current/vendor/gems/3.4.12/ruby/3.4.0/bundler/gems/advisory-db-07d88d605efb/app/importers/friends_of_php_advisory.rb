# frozen_string_literal: true

require "severity_calculator"

# represent an advisory from FriendsOfPHP
# These advisories have a yaml file with data about the advisory, AND
# **The path is significant**, it identifies the package name. It is also the only thing that serves as a good identifier
# Therefore, initializing requires both a path and hash of file contents
#
# Example yaml from: https://github.com/FriendsOfPHP/security-advisories/blob/9332aea724d95f77fda9fb140635fccc17489bf8/api-platform/core/CVE-2019-1000011.yaml
# ---
# title:     "CVE-2019-1000011: Access control bypass in GraphQL mutations"
# link:      https://github.com/api-platform/core/pull/2441
# cve:       CVE-2019-1000011
# branches:
#     2.2.x:
#         time:     2019-01-15 17:30:00
#         versions: ['>=2.2.0', '<2.2.10']
#     2.3.x:
#         time:     2019-01-15 17:30:00
#         versions: ['>=2.3.0', '<2.3.6']
# reference: composer://api-platform/core
#

class FriendsOfPHPAdvisory
  FriendsOfPHPAdvisoryError = Class.new(StandardError)

  # the repo name-with-owner for the Friends Of PHP datasource
  REPO_NWO = "FriendsOfPHP/security-advisories"
  FILE_BASE_PATH = "https://github.com/#{REPO_NWO}/blob/master/".freeze
  RAW_FILE_BASE_PATH = "https://raw.githubusercontent.com/#{REPO_NWO}/master/".freeze
  ADVISORY_FILE_PATTERN = %r{^[a-z0-9]([_.-]?[a-z0-9]{0,191})*/[a-z0-9]([_.-]?[a-z0-9]{0,191}).*/.*.yaml}

  def self.file_url(path)
    FILE_BASE_PATH + path
  end

  def self.raw_file_url(path)
    RAW_FILE_BASE_PATH + path
  end

  def self.initialize_from_path(path)
    unless path.match?(ADVISORY_FILE_PATTERN)
      raise FriendsOfPHPAdvisoryError, "Not a valid advisory file path"
    end

    res = Net::HTTP.get_response(URI(raw_file_url(path)))
    case res.code
    when "200"
      parsed_yaml = YAML.safe_load(res.body, permitted_classes: [Date, Time])
      new(raw_payload: parsed_yaml, path: path)
    when "404"
      raise FriendsOfPHPAdvisoryError, "Advisory file no longer exists on main"
    else
      raise FriendsOfPHPAdvisoryError, "HTTP response code #{res.code} when fetching advisory file"
    end
  end

  attr_reader :raw_payload, :path

  def initialize(raw_payload:, path:)
    if !raw_payload["title"] || !raw_payload["link"] || !raw_payload["reference"] || !raw_payload["branches"]
      raise { FriendsOfPHPAdvisoryError.new("No package reference available") }
    end
    @raw_payload = raw_payload
    @path = path
  end

  def identifier
    "friends_of_php/#{path}"
  end

  def cve_id
    if AdvisoryDBToolkit::CVEIDValidator::PATTERN.match(raw_payload["cve"].presence)
      raw_payload["cve"]
    end
  end

  def advisory_payload
    {
      summary: summary,
      description: nil,
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
      friends_of_php_id: path,
      raw_payload: raw_payload,
      advisory_payload: advisory_payload,
    }
  end

  def summary
    raw_payload["title"]
  end

  def references
    AdvisoryDBToolkit::ReferenceSorter.sorted_reference_list([
      raw_payload["link"].presence,
      self.class.file_url(path), # link to the advisory on github
    ])
  end

  def package_name
    raw_payload["reference"].delete_prefix("composer://")
  end

  def vulnerabilities
    range_pairs = raw_payload.fetch("branches").values.map { |b| b.fetch("versions") }
    return {} if range_pairs.empty?

    version_ranges = range_pairs.map { |range_pair| VersionRange.new(range_pair) }

    # in this data, some version ranges are "continued" by the next range
    # in such cases, ranges should be combined, into a single range
    # For example ['>=3.3.0', '<3.4.0'] and ['>=3.4.0', '<3.4.26']
    # should be combined into a single ['>=3.3.0', '<3.4.26'] for our data
    # so transform the version_ranges list into a list of combined ranges
    # combined ranges will have length between 1 and version_ranges.length
    combined_ranges = []
    until version_ranges.empty?
      # take the first in the list
      range = version_ranges.shift
      # keep combining the range with the next range, until next range does not continue it
      while version_ranges.first && range.continued_by?(version_ranges.first)
        range = range.combined_range(version_ranges.shift)
      end
      # put it on the end of the list, preserving original ordering
      combined_ranges.push(range)
    end

    combined_ranges.each.with_index.with_object({}) do |(vr, index), memo|
      memo[index] = {
        ecosystem: "composer",
        package_name: package_name,
        vulnerable_version_range: vr.vulnerable_version_range,
        first_patched_version: vr.first_patched_version,
      }
    end
  end

  # This is a helper class, for parsing the version range data
  class VersionRange
    attr_reader :range_pair

    FRIENDS_OF_PHP_REQUIREMENTS_FORMAT = %r{
      \A
      # Two basic versions, those with the comma, and those without
      (?:
        (?: # version without comma
          \s*
          (?<only_operator>=|<|<=|>|>=)
          \s*
          (?<only_version>\d[^\s,]*)
          \s*
        )
        |
        (?: # version with comma
          \s*
          (?<lower_part>
            (?<lower_operator>>|>=) # restrict to it starting with greater-than or greater-than-or-equal-to
            \s*
            (?<lower_version>\d[^\s,]*)
          )
          \s*
          ,
          \s*
          (?<upper_part>\s*
            (?<upper_operator><|<=) # likewise upper operator must be less-than
            \s*
            (?<upper_version>\d[^\s,]*)
          )
          \s*
        )
      )
      \z
    }x

    def initialize(range_pair)
      @range_pair = range_pair
    end

    def range_parts
      return @range_parts if defined? @range_parts

      range_str = range_pair.join(",")
      range_parts = range_str.match(FRIENDS_OF_PHP_REQUIREMENTS_FORMAT)

      if range_parts.nil?
        raise ArgumentError, "unable to parse range: #{range_pair}"
      end

      @range_parts = range_parts
    end

    def lower_version_defined?
      range_parts[:lower_version].present?
    end

    def upper_version_defined?
      range_parts[:upper_version].present?
    end

    def continued_by?(other_range)
      return false unless other_range.is_a?(self.class)
      return false unless upper_version_defined?
      return false unless other_range.lower_version_defined?

      # ranges overlaps simply if
      range_parts[:upper_version] == other_range.range_parts[:lower_version]
    end

    def combined_range(other_range)
      raise "Can't combine these ranges" unless continued_by?(other_range)

      new_range_pair = [range_parts[:lower_part], other_range.range_parts[:upper_part]]
      self.class.new(new_range_pair)
    end

    def vulnerable_version_range
      return @vulnerable_version_range if defined? @vulnerable_version_range

      @vulnerable_version_range =
        if range_parts[:only_operator]
          "#{range_parts[:only_operator]} #{range_parts[:only_version]}"
        else
          "#{range_parts[:lower_operator]} #{range_parts[:lower_version]}, #{range_parts[:upper_operator]} #{range_parts[:upper_version]}"
        end
    end

    def first_patched_version
      return @first_patched_version if defined? @first_patched_version

      @first_patched_version =
        if range_parts[:only_operator] == "<"
          range_parts[:only_version]
        elsif range_parts[:upper_operator] == "<"
          range_parts[:upper_version]
        end
    end
  end
end
