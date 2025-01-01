# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ConvertedNoteToIssueEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'converted_note_to_issue' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, converted_note_to_issue_event)
        permission.belongs_to_issue_event(converted_note_to_issue_event).then do |issue_event_accessible|
          next false unless issue_event_accessible

          converted_note_to_issue_event.async_project.then { |project| project && permission.can_access?(project) }
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
        [:rcntie, :repo_id, :issue_id, :converted_note_to_issue_event_id]
      ], as: "CNTIE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rcntie,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          converted_note_to_issue_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::ProjectEvent

      implements Interfaces::PerformableViaApp


      # TODO: remove this when the declaration in TimelineEvent becomes public
      database_id_field

      field :project_column_name, String, description: "Column name referenced by this project event.", method: :async_project_column_name, null: false

      field :project_card, Objects::ProjectCard, description: "Project card referenced by this project event.", null: true

      def project_card
        @object.async_visible_project_card(@context[:permission])
      end
    end
  end
end
