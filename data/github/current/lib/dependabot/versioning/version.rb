# typed: true
# frozen_string_literal: true

module Dependabot
  module Versioning
    class Version < Gem::Version
      def initialize(version)
        @original_version = version

        super
      end

      # Opt-in to Rubygems 4 behavior
      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end

      def to_semver
        @original_version
      end

      protected

      # Gem::Version#compute_sort_key assumes that non-prerelease versions have
      # only numeric canonical segments. Dependabot version subclasses override
      # prerelease? with ecosystem-specific logic, which can disagree with the
      # ".pre." segments injected by Gem::Version's hyphen conversion. Returning
      # nil opts out of the sort_key fast-path in Gem::Version#<=>; this is safe
      # because subclasses with non-standard version formats override <=> with
      # their own comparison logic, and those that inherit Gem::Version#<=>
      # normalize their version strings to be segment-compatible.
      def compute_sort_key
        nil
      end
    end
  end
end
