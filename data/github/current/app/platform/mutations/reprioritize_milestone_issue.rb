# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReprioritizeMilestoneIssue < Platform::Mutations::Base
      description "Update the priority of an issue or pull request in a milestone"
      visibility :internal
      minimum_accepted_scopes ["repo"]

      argument :id, ID, "The ID of the Issue or pull request to modify the priority.", required: true, loads: Unions::IssueOrPullRequest, as: :item
      argument :milestone_id, ID, "The ID of the Milestone to modify the priority of.", required: true, loads: Objects::Milestone, as: :milestone
      argument :prev_id, ID, "The ID of the Issue or pull request that comes before the one to modify the priority of.", required: false, loads: Unions::IssueOrPullRequest, as: :prev_item
      argument :timestamp, Scalars::DateTime, "The current updated_at timestamp of the milestone (required for optimistic concurrency)", required: true

      field :milestone, Objects::Milestone, "The updated milestone.", null: true

      def self.async_api_can_modify?(permission, milestone:, **inputs)
        permission.async_owner_if_org(milestone.repository).then do |org|
          permission.access_allowed? :update_milestone, current_org: org, repo: milestone.repository, allow_integrations: true, allow_user_via_granular_actor: true
        end
      end

      def resolve(item:, milestone:, prev_item:, timestamp:, **inputs)
        item_issue = if item.is_a?(::PullRequest)
          item.issue
        else
          item
        end

        prev_item_issue = if prev_item && prev_item.is_a?(::PullRequest)
          prev_item.issue
        else
          prev_item
        end

        repository = milestone.repository
        authorization = ContentAuthorizer::MilestoneAuthorizer.new(context[:viewer], :update, repository: repository)
        if authorization.failed?
          raise Errors::Unprocessable.new(authorization.error_messages)
        end

        if !timestamp.is_a?(Time) || milestone.updated_at.utc != timestamp.utc
          raise Errors::Unprocessable.new("Milestone has changed. Please refresh and try again.")
        end

        unless milestone.prioritizable?
          raise Errors::Unprocessable.new("Milestone is not prioritizable")
        end
        if item_issue.milestone != milestone
          raise Errors::Unprocessable.new("Item is not in the milestone")
        end
        if prev_item_issue && prev_item_issue.milestone != milestone
          raise Errors::Unprocessable.new("Previous item is not in the milestone")
        end

        check_database_resource_update_rate_limit!(resource: item_issue, current_user: context[:viewer])

        begin
          if prev_item_issue.present?
            milestone.prioritize_issue!(item_issue, after: prev_item_issue)
          else
            milestone.prioritize_issue!(item_issue, position: :top)
          end
          { milestone: milestone }
        rescue GitHub::Prioritizable::Context::LockedForRebalance
          raise Errors::ServiceUnavailable.new("Sorry! This milestone is temporarily locked for maintenance. Please try again.")
        end
      end
    end
  end
end
