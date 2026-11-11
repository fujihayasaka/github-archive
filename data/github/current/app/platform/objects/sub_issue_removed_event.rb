# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SubIssueRemovedEvent < Platform::Objects::Base
      description "Represents a 'sub_issue_removed' event on a given issue."
      model_name "IssueEvent"

      implements Interfaces::TimelineEvent
      implements Interfaces::PerformableViaApp

      scopeless_tokens_as_minimum

      visibility :public

      field :sub_issue, Issue, "The sub-issue removed.", method: :async_subject_as_issue_or_pull_request, null: true

      implements_node templates: [[:rsire, :repo_id, :issue_id, :id]],
        as: "SIRE",
        ready_date: "1970-01-01" do |event|
        Timeline::Placeholder.async_value_for(event).then do |event|
          {
            prefix: :rsire,
            repo_id: event.repository_id,
            issue_id: event.issue_id,
            id: event.id,
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, sub_issue_removed_event)
        permission.belongs_to_issue_event(sub_issue_removed_event).then do |issue_event_accessible|
          next false unless issue_event_accessible

          sub_issue_removed_event.async_subject_as_issue_or_pull_request.then do |subject|
            next unless subject
            permission.async_repo_and_org_owner(subject).then do |subject_repo, subject_repo_org|
              next unless subject_repo
              permission.access_allowed?(:list_issue_timeline, resource: subject, repo: subject_repo, current_org: subject_repo_org, allow_integrations: true, allow_user_via_granular_actor: true)
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object).then do |visible|
          next false unless visible
          object.async_subject_as_issue_or_pull_request.then do |subject|
            next false unless subject

            cap_filter = permission.cap_filter
            if cap_filter
              next false unless cap_filter.authorized_resources([subject]).any?
            end

            graphql_type_name = Platform::Helpers::NodeIdentification.type_name_from_object(subject)
            permission.typed_can_see?(graphql_type_name, subject)
          end
        end
      end
    end
  end
end
