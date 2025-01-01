# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class CreatedPullRequestOrRestrictedContribution < Platform::Unions::Base

      description "Represents either a pull request the viewer can access or a restricted contribution."

      possible_types Objects::CreatedPullRequestContribution, Objects::RestrictedContribution
    end
  end
end
