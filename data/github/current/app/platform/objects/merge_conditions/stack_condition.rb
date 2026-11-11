# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module MergeConditions
      class StackCondition < Platform::Objects::Base
        docs_category :pulls
        description "Stacked pull request error condition"
        feature_flag :pull_request_stacks

        class << self
          delegate :async_api_can_access?, to: Platform::Interfaces::PullRequestMergeCondition
          delegate :async_viewer_can_see?, to: Platform::Interfaces::PullRequestMergeCondition
        end

        implements Interfaces::PullRequestMergeCondition
      end
    end
  end
end
