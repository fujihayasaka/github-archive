# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ConnectedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'connected' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, connected_event)
        Promise.all([
          connected_event.async_issue_or_pull_request,
          connected_event.async_subject_as_issue_or_pull_request,
        ]).then do |source, subject|
          next unless source && subject
          permission.async_repo_and_org_owner(source).then do |source_repo, source_repo_org|
            next unless source_repo
            permission.async_repo_and_org_owner(subject).then do |subject_repo, subject_repo_org|
              next unless subject_repo
              permission.access_allowed?(:list_issue_timeline, resource: source, repo: source_repo, current_org: source_repo_org, allow_integrations: true, allow_user_via_granular_actor: true) &&
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
          object.async_subject_as_issue_or_pull_request.then do |canonical|
            next false unless canonical
            graphql_type_name = Platform::Helpers::NodeIdentification.type_name_from_object(canonical)
            permission.typed_can_see?(graphql_type_name, canonical)
          end
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rce, :repo_id, :issue_id, :connected_event_id]
      ], as: "COE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rce,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          connected_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent


      field :source, Unions::ReferencedSubject, "Issue or pull request that made the reference.", method: :async_issue_or_pull_request, null: false

      field :subject, Unions::ReferencedSubject, "Issue or pull request which was connected.", method: :async_subject_as_issue_or_pull_request, null: false

      field :is_cross_repository, Boolean, "Reference originated in a different repository.", method: :async_cross_subject_repository?, null: false
    end
  end
end
