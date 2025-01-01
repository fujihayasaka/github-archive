# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ReferencedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'referenced' event on a given `ReferencedSubject`."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, referenced_event)
        permission.belongs_to_issue_event(referenced_event)
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
        [:rre, :repo_id, :issue_id, :referenced_event_id]
      ], as: "REFE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rre,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          referenced_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :subject, Unions::ReferencedSubject, "Object referenced by event.", method: :async_issue_or_pull_request, null: false

      field :commit_repository, Repository, description: "Identifies the repository associated with the 'referenced' event.", method: :async_commit_repository, null: false

      field :commit, Objects::Commit, description: "Identifies the commit associated with the 'referenced' event.", method: :async_commit, null: true

      field :will_close_subject, Boolean, visibility: :internal, description: "Checks if the subject will be closed when the referencing commit is merged into the default branch.", method: :async_will_close_subject?, null: false

      field :has_closed_subject, Boolean, visibility: :internal, description: "Checks if the subject was closed by this commit reference.", method: :async_has_closed_subject?, null: false

      field :is_direct_reference, Boolean, description: "Checks if the commit message itself references the subject. Can be false in the case of a commit comment reference.", method: :async_direct_reference?, null: false

      field :is_cross_repository, Boolean, description: "Reference originated in a different repository.", method: :cross_commit_repository?, null: false

      field :is_authored_by_pusher, Boolean, "Checks if the pusher either committed or authored the commit.", method: :async_authored_by_pusher?, visibility: :internal, null: false
    end
  end
end
