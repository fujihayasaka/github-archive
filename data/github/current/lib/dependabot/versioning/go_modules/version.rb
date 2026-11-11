# typed: true
# frozen_string_literal: true

#
# NOTE: Temporarily copied from https://github.com/dependabot/dependabot-core.
# Will be removed and replaced once version logic can be vendored as an isolated gem, as noted in P1 work for https://github.com/github/team-advisory-database/issues/3344.

module Dependabot
  module Versioning
    module GoModules
      class Version < Dependabot::Versioning::Version
        VERSION_PATTERN = '[0-9]+[0-9a-zA-Z]*(?>\.[0-9a-zA-Z]+)*' \
                          '(-[0-9A-Za-z-]+(\.[0-9a-zA-Z-]+)*)?' \
                          '(\+incompatible)?'
        ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/

        def self.correct?(version)
          version = version.gsub(/^v/, "") if version.is_a?(String)
          version = version.to_s.split("+").first if version.to_s.include?("+")

          super(version)
        end

        def initialize(version)
          @version_string = version.to_s.gsub(/^v/, "")
          version = version.gsub(/^v/, "") if version.is_a?(String)
          version = version.to_s.split("+").first if version.to_s.include?("+")

          super
        end

        def inspect # :nodoc:
          "#<#{self.class} #{@version_string.inspect}>"
        end

        def to_s
          @version_string
        end
      end
    end
  end
end
