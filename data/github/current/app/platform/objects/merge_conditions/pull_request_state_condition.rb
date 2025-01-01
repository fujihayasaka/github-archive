# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module MergeConditions
      class PullRequestStateCondition < Platform::Objects::Base
        description "Pull request state merge condition"

        class << self
          delegate :async_api_can_access?, to: Platform::Interfaces::PullRequestMergeCondition
          delegate :async_viewer_can_see?, to: Platform::Interfaces::PullRequestMergeCondition
        end

        implements Interfaces::PullRequestMergeCondition
      end
    end
  end
end
