# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UnmarkedAsDuplicateEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents an 'unmarked_as_duplicate' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, unmarked_as_duplicate_event)
        permission.belongs_to_issue_event(unmarked_as_duplicate_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object).then do |visible|
          next false unless visible
          object.async_subject_as_issue_or_pull_request.then do |canonical|
            next false unless canonical

            cap_filter = permission.cap_filter
            if cap_filter
              next false unless cap_filter.authorized_resources([canonical]).any?
            end

            canonical_type = Helpers::NodeIdentification.type_name_from_object(canonical)
            permission.typed_can_see?(canonical_type, canonical)
          end
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:ruad, :repo_id, :issue_id, :id]
      ], as: "UADE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :ruad,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :canonical, Unions::IssueOrPullRequest, "The authoritative issue or pull request which has been duplicated by another.", method: :async_subject_as_issue_or_pull_request, null: true

      field :duplicate, Unions::IssueOrPullRequest, "The issue or pull request which has been marked as a duplicate of another.", method: :async_issue_or_pull_request, null: true

      field :is_cross_repository, Boolean, "Canonical and duplicate belong to different repositories.", method: :async_cross_subject_repository?, null: false
    end
  end
end
