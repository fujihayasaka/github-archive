# A RequirementSet represents a list of requirements. Requirements can be
# combined in a variety of ways and different package managers have different
# compound requirement semantics. RequirementSet defines the dependency graph's
# universal serialization format.
#
# RequirementSets are instantiated with a set of requirements ranges that are
# OR-ed together. Requirements within a range are AND-ed together. For example,
# the following RequirementSet stipulates that a version must fall within the
# ">= 2.0.0 - <= 2.1.0" range OR must equal "2.5.0".
#
#  RequirementSet.new([
#    [">= 2.0.0", "<= 2.1.0"],
#    ["= 2.5.0"]
#  ])
#
# Compound requirements serialization rules:
#
#   ">= 2.0.0"                     - versions greater or equal to 2.0.0
#
#   ">= 2.0.0, <= 2.0.5"           - versions between 2.0.0 and 2.0.5
#
#   "= 2.0.0 || = 2.0.1"           - version 2.0.0 or 2.0.1
#
#   ""                             - any version
#
#   "= 2.0.0, <= 2.1.0 || = 2.5.0" - versions between 2.0.0 and 2.1.0 or version 2.5.0
#
# Package manager adapters are expected to formulate requirements in
# compliance with this serialization format.
module Versioning
  class RequirementSet

    # Split operators preceding spaces matched using Negative lookbehind assertion anchor
    # Fix for https://github.com/github/dependency-graph-api/security/code-scanning/6
    SPLIT_AND = /(?<!\s)\s*,\s*/
    SPLIT_OR  = /(?<!\s)\s*\|\|\s*/

    JOIN_AND  = ",".freeze
    JOIN_OR   = " || ".freeze

    attr_reader :ranges, :allow_named_versions

    def self.deserialize(string, allow_named_versions:, version_parser: ::Versioning::VersionParser, on_error: nil)
      return wildcard if string.blank?

      new(
        ranges: string.to_s.split(SPLIT_OR).map do |range|
          deserialize_range(range, allow_named_versions:, version_parser:, on_error:)
        end,
        allow_named_versions: allow_named_versions
      )
    end

    def self.deserialize_range(range, allow_named_versions:, version_parser: ::Versioning::VersionParser, on_error: nil)
      return [Requirement.wildcard] if range.blank?

      range.strip.split(SPLIT_AND)
        .map { |str| Requirement.deserialize(str, allow_named_versions:, version_parser:) }
        .select do |requirement|
          next true if requirement.valid?

          on_error&.call(range)
          false
        end
    end

    def self.wildcard
      new(ranges: [[Requirement.wildcard]], allow_named_versions: false)
    end

    def initialize(ranges:, allow_named_versions:)
      @ranges = ranges.map { |range| RequirementRange.new(range) }
      @allow_named_versions = allow_named_versions
    end

    def encoded_lower_bound
      substitute_wildcards.map(&:max_encoded_lower_bound).min
    rescue Versioning::NoEncodedVersionError
      nil
    end

    def encoded_upper_bound
      substitute_wildcards.map(&:min_encoded_upper_bound).max
    rescue Versioning::NoEncodedVersionError
      nil
    end

    def encoded_ranges
      substitute_wildcards.map(&:encoded)
    end

    def serialize
      ranges.map { |range| range.map(&:serialize).join(JOIN_AND) }.join(JOIN_OR)
    end

    def to_s
      serialize
    end

    def valid?
      !ranges.all?(&:empty?)
    end

    def substitute_wildcards
      @substitute_wildcards ||= ranges.map(&:substitute_wildcard)
    end

    def cover?(version)
      ranges.any? do |range|
        range.all? { |requirement| requirement.cover?(version) }
      end
    end

    # Public: Does every requirement range from `other` correspond to at least one
    # requirement range in this requirement set?
    #
    #  `>= 5.0.0, < 5.1.0` contains `= 5.0.0` but not `= 5.1.0` or `> 5.0.0`
    #
    # Returns a Boolean.
    def contain?(other)
      if other.is_a? VersionRange
        other = other.to_requirements_set(allow_named_versions: allow_named_versions)
      end

      # When there are multiple ranges in this context, it means they're joined with "OR".
      # Every range on the right must match at least one range on the left.
      other.ranges.all? { |right|
        ranges.any? { |left|
          left.contain?(right)
        }
      }
    end

    # Public: Do any requirement ranges from this requirement set overlap with
    # the bounds from any ranges in the other requirement set?
    #
    #  `>= 5.0.0, < 5.1.0` overlaps `= 5.0.0` and `> 5.0.0` but not `= 5.1.0`
    #
    # Returns a Boolean.
    def overlap?(other)
      if other.is_a? VersionRange
        other = other.to_requirements_set(allow_named_versions: allow_named_versions)
      end

      raise TypeError unless other.is_a? RequirementSet
      ranges.any? do |range|
        other.ranges.any? { |other_range| range.overlap?(other_range) }
      end
    end

    def exact_version
      # if this requirement range has an exact version, give it
      if ranges.count == 1 && ranges.first.exact_version.present?
        return ranges.first.exact_version
      else
        return nil
      end
    end
  end
end
