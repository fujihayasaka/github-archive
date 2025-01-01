# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ItemStatusChangedEvent < Platform::Objects::Base

      description "Represents a 'project_v2_item_status_changed' event on a given issue or pull request."

      model_name "Timeline::Placeholder::ProjectItemStatusChanged"

      visibility :internal

      implements Interfaces::TimelineEvent
      implements Interfaces::ProjectV2Event
      implements Interfaces::PerformableViaApp

      minimum_accepted_scopes ["read:project"]

      field :status, String, "The new status of the project item.", null: false
      field :previous_status, String, "The previous status of the project item.", null: false

      implements_node templates: [[:rpvtisc, :repo_id, :issue_id, :id]],
        as: "PVTISC",
        ready_date: "1970-01-01" do |event|
        Platform::Loaders::ActiveRecord.load(::Issue, event.issue_id).then do |issue|
          issue = T.must(issue)
          {
            prefix: :rpvtisc,
            repo_id: issue.repository_id,
            issue_id: issue.id,
            id: event.id
          }
        end
      end

      class << self
        delegate :load_from_next_global_id, to: Platform::Interfaces::ProjectV2Event
        delegate :load_from_global_id, to: Platform::Interfaces::ProjectV2Event
        delegate :async_api_can_access?, to: Platform::Interfaces::ProjectV2Event
        delegate :async_viewer_can_see?, to: Platform::Interfaces::ProjectV2Event
      end
    end
  end
end
