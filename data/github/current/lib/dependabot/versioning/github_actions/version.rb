# typed: true
# frozen_string_literal: true
#
# NOTE: Temporarily copied from https://github.com/dependabot/dependabot-core.
# Will be removed and replaced once version logic can be vendored as an isolated gem, as noted in P1 work for https://github.com/github/team-advisory-database/issues/3344.

module Dependabot
  module Versioning
    module GithubActions
      class Version < Dependabot::Versioning::Version
        def initialize(version)
          version = Version.remove_leading_v(version)
          super
        end

        def self.remove_leading_v(version)
          return version unless version.to_s.match?(/\Av([0-9])/)

          version.to_s.delete_prefix("v")
        end

        def self.correct?(version)
          version = Version.remove_leading_v(version)
          super
        end
      end
    end
  end
end
