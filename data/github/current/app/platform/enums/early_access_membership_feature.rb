# typed: true
# frozen_string_literal: true
module Platform
  module Enums
    class EarlyAccessMembershipFeature < Platform::Enums::Base
      visibility :internal
      description "An early access feature that a user can apply for access to."

      value "TESTING_ONLY", "For testing only", value: "testing_only"
      value "GITHUB_SPONSORS", "The GitHub Sponsors beta", value: "github_sponsors"
      value "REGISTRY", "The GitHub Package Registry beta", value: "registry"
      value "TEAM_SYNC", "The team synchronization beta", value: "team_sync"
    end
  end
end
