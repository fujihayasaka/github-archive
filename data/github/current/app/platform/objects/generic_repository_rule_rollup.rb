# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class GenericRepositoryRuleRollup < Platform::Objects::Base
      description "Rollup state representing multiple runs of a specific rule type"
      minimum_accepted_scopes ["public_repo"]
      feature_flag :pull_request_merge_requirements_api

      implements Interfaces::RepositoryRuleRollup

      class << self
        delegate :async_api_can_access?, to: Platform::Interfaces::RepositoryRuleRollup
        delegate :async_viewer_can_see?, to: Platform::Interfaces::RepositoryRuleRollup
      end
    end
  end
end
