# typed: true
# frozen_string_literal: true
#
# NOTE: Temporarily copied from https://github.com/dependabot/dependabot-core.
# Will be removed and replaced once version logic can be vendored as an isolated gem, as noted in P1 work for https://github.com/github/team-advisory-database/issues/3344.

module Dependabot
  module Versioning
    module Bundler
      class Version < Dependabot::Versioning::Version
      end
    end
  end
end
