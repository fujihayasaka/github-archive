# typed: true
# frozen_string_literal: true

module Api
  module Versioning
    NEXT_VERSION = "next"
    NEXT_VERSION_SYM = :next

    # Determine the default API version. Currently, this is the earliest supported version.
    #
    # @return [String]
    def self.default_version
      GitHub.api_versions.last
    end

    # Determine the most recent published API version.
    #
    # @return [String]
    def self.latest_version
      GitHub.api_versions.first
    end

    # Determine if a version can be used.
    #
    # @param version [String, Symbol] the version to check
    #   (ISO 8601 formatted date, :next, or "next")
    #
    # @return [Boolean]
    def self.usable_version?(version)
      # Uses to_s to support a Symbol version of NEXT_VERSION
      version.to_s == NEXT_VERSION || GitHub.api_versions.include?(version)
    end

    # Retrieve a list of usable versions.
    #
    # @return [Array<String, Symbol>]
    def self.usable_versions
      GitHub.api_versions + [NEXT_VERSION_SYM]
    end

    # Sort versions in the canonical, oldest-to-newest order.
    #
    # @param versions [Array<String, Symbol>]
    #
    # @return [Array<String, Symbol>]
    def self.sort_versions(versions)
      versions.sort do |a, b|
        if a.to_s == NEXT_VERSION
          1
        elsif b.to_s == NEXT_VERSION
          -1
        else
          Date.parse(a) <=> Date.parse(b)
        end
      end
    end
  end
end
