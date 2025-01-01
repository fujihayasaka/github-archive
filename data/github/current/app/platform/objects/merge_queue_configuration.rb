# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MergeQueueConfiguration < Platform::Objects::Base
      description "Configuration for a MergeQueue"
      visibility :public, environments: [:dotcom, :enterprise]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, merge_queue_configuration)
        permission.async_repo_and_org_owner(merge_queue_configuration[:merge_queue]).then do |repo, org|
          permission.access_allowed?(
            :get_merge_queue_config,
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, merge_queue_configuration)
        permission.belongs_to_repository(merge_queue_configuration[:merge_queue])
      end

      scopeless_tokens_as_minimum

      field :merge_method, Platform::Enums::PullRequestMergeMethod, description: "The merge method to use for this queue.",
        null: true

      field :maximum_entries_to_build, Integer, description: "The maximum number of entries to build at once.",
        null: true

      field :minimum_entries_to_merge, Integer, description: "The minimum number of entries required to merge at once.",
        null: true

      field :minimum_entries_to_merge_wait_time, Integer,
        description: "The amount of time in minutes to wait before ignoring the minumum number of entries in the queue requirement and merging a collection of entries",
        null: true

      field :maximum_entries_to_merge, Integer, description: "The maximum number of entries to merge at once.",
        null: true

      field :check_response_timeout, Integer, description: "The amount of time in minutes to wait for a check response before considering it a failure.",
        null: true

      field :merging_strategy, Platform::Enums::MergeQueueMergingStrategy, description: "The strategy to use when merging entries.",
        null: true
    end
  end
end
