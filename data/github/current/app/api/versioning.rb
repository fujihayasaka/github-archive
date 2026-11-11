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

    # Determine when a supported API version will be retired.
    #
    # A version is retired 6 months after the release that follows it.
    #
    # @param version [String, Symbol] the supported API version to check
    #
    # @return [Date, nil]
    def self.retirement_date(version)
      ordered_versions = sort_versions(GitHub.api_versions)
      selected_index = ordered_versions.index(version.to_s)
      return if selected_index.nil?

      following_version = ordered_versions[selected_index + 1]
      return if following_version.nil?

      Date.iso8601(following_version) >> 6
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

    # Determine if a version is explicitly unsupported.
    #
    # @param version [String, Symbol] the version to check
    #
    # @return [Boolean]
    def self.unsupported_version?(version)
      GitHub.unsupported_api_versions.include?(version.to_s)
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

    # Return versions whose deprecation date is within the given number of days from now.
    #
    # @param days [Integer] the lookahead window in days
    #
    # @return [Array<String>] versions deprecating within the window
    def self.versions_deprecating_within(days)
      today = Date.today
      cutoff = today + days
      deprecating = GitHub.api_version_deprecation_dates.select do |_version, date_str|
        date = Date.iso8601(date_str)
        date >= today && date <= cutoff
      end
      deprecating.keys
    end

    # Return the deprecation date for a given version.
    #
    # @param version [String] the API version string
    #
    # @return [Date, nil] the deprecation date, or nil if not set
    def self.deprecation_date_for(version)
      date_str = GitHub.api_version_deprecation_dates[version]
      date_str ? Date.iso8601(date_str) : nil
    end

    # Return true if `latest_version` is an ISO 8601 date equal to `today`.
    #
    # Used by the release notification dispatcher to decide whether today's
    # invocation should fan out per-user release notification jobs. Returns
    # false for nil, blank, or non-ISO-8601 latest version strings so callers
    # never need to defend against malformed configuration.
    #
    # @param today [Date] the comparison date (defaults to Date.today)
    #
    # @return [Boolean]
    def self.latest_version_released_today?(today: Date.today)
      version = latest_version
      return false if version.nil? || version.to_s.empty?

      Date.iso8601(version.to_s) == today
    rescue Date::Error
      false
    end

    # Return the configured deprecation dates as a String → Date hash,
    # optionally excluding a single version. Used by the release notification
    # dispatcher to attach upcoming deprecations to the release-day mail
    # payload without re-emitting the freshly-released version itself.
    #
    # @param excluding [String, nil] an API version to omit from the result
    #
    # @return [Hash{String => Date}]
    def self.deprecating_versions_with_dates(excluding: nil)
      GitHub.api_version_deprecation_dates.each_with_object({}) do |(version, date_str), result|
        next if excluding && version == excluding

        result[version] = Date.iso8601(date_str)
      end
    end
  end
end
