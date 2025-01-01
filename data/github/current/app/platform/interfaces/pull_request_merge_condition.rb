# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module PullRequestMergeCondition
      include Platform::Interfaces::Base
      description "Represents a shared interface among merge conditions for a pull request"

      required_capabilities [:mobile_only_schema_mask]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.typed_can_access?("PullRequest", object.pull_request)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("PullRequest", object.pull_request)
      end

      field :display_name, String, description: "The display name for the merge condition", null: false
      field :description, String, description: "A description of the merge condition", null: false
      field :message, String, description: "A user-friendly message about the result of the merge condition", null: true
      field :result, Enums::PullRequestMergeConditionResult, description: "The result of evaluating the merge condition", null: false

      # Custom type resolver for types with separate definitions
      # this makes returning [Interfaces::PullRequestMergeCondition] work
      def self.resolve_type(object, context)
        case object
        when ::MergeConditions::PullRequestState
          Objects::MergeConditions::PullRequestStateCondition
        when ::MergeConditions::PullRequestRepoState
          Objects::MergeConditions::PullRequestRepoStateCondition
        when ::MergeConditions::PullRequestUserState
          Objects::MergeConditions::PullRequestUserStateCondition
        when ::MergeConditions::PullRequestRules
          Objects::MergeConditions::PullRequestRulesCondition
        when ::MergeConditions::PullRequestMergeConflictState
          Objects::MergeConditions::PullRequestMergeConflictStateCondition
        when ::MergeConditions::PullRequestMergeMethod
          Objects::MergeConditions::PullRequestMergeMethodCondition
        else
          raise Platform::Errors::Internal, "Unable to resolve concrete MergeCondition"
        end
      end
    end
  end
end
