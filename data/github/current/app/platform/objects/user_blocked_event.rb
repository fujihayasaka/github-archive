# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserBlockedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'user_blocked' event on a given user."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, user_blocked_event)
        permission.belongs_to_issue_event(user_blocked_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object).then do |issue_check|
          next false unless issue_check

          object.async_commit_repository.then do |commit_repo|
            next true unless commit_repo
            permission.typed_can_see?("Repository", commit_repo)
          end
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rube, :repo_id, :issue_id, :user_blocked_event_id]
      ], as: "UBE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rube,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          user_blocked_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :subject, Objects::User, "The user who was blocked.", resolver: Resolvers::ActorSubject, null: true

      field :block_duration, Enums::UserBlockDuration, "Number of days that the user was blocked for.", method: :block_duration_days, null: false
    end
  end
end
