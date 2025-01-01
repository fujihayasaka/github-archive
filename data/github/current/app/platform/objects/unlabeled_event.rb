# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UnlabeledEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents an 'unlabeled' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, unlabeled_event)
        permission.belongs_to_issue_event(unlabeled_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rue, :repo_id, :issue_id, :unlabeled_event_id]
      ], as: "UNLE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rue,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          unlabeled_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :labelable, Interfaces::Labelable, "Identifies the `Labelable` associated with the event.", method: :async_issue_or_pull_request, null: false

      field :label, Label, description: "Identifies the label associated with the 'unlabeled' event.", null: false, scope: true

      def label
        @object.async_issue_event_detail.then do |issue_event_detail|
          Platform::Loaders::ActiveRecord.load(::Label, issue_event_detail.label_id).then do |label|
            if label.present?
              label
            else
              issue_event_detail.async_issue_event.then do |issue_event|
                issue_event.async_repository.then do |repo|
                  ::Label.new(
                    # We no longer have the true created at, as the underlying label was deleted, but the events created_at at least a lower bound.
                    # We need to set this to correctly set the graphQL id based on the new format, which is determined by the created_at timestamp.
                    created_at: issue_event_detail.created_at,
                    id: issue_event_detail.label_id || 0,
                    name: issue_event_detail.label_name,
                    color: issue_event_detail.label_color,
                    repository: repo)
                end
              end
            end
          end
        end
      end
    end
  end
end
