# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RemovedFromProjectEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'removed_from_project' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, removed_from_project_event)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)
        permission.belongs_to_issue_event(removed_from_project_event).then do |issue_event_accessible|
          next false unless issue_event_accessible

          removed_from_project_event.async_project.then { |project| project && permission.can_access?(project) }
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object).then do |result|
          result && permission.belongs_to_project(object)
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rrfp, :repo_id, :issue_id, :id]
      ], as: "RFPE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rrfp,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::ProjectEvent

      implements Interfaces::PerformableViaApp


      # TODO: remove this when the declaration in TimelineEvent becomes public
      database_id_field deprecated: Helpers::ProjectDeprecation::Notice

      field :project_column_name, String, description: "Column name referenced by this project event.", method: :async_project_column_name, null: false, deprecated: Helpers::ProjectDeprecation::Notice
    end
  end
end
