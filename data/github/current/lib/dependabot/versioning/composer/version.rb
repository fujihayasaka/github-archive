# typed: true
# frozen_string_literal: true

#
# NOTE: Temporarily copied from https://github.com/dependabot/dependabot-core.
# Will be removed and replaced once version logic can be vendored as an isolated gem, as noted in P1 work for https://github.com/github/team-advisory-database/issues/3344.

# PHP pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.

module Dependabot
  module Versioning
    module Composer
      class Version < Dependabot::Versioning::Version
        def initialize(version)
          @version_string = version.to_s
          super
        end

        def to_s
          @version_string
        end
      end
    end
  end
end
