# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectV2ItemStatusChangedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'project_v2_item_status_changed' event on a given issue or pull request."

      visibility :internal

      implements Interfaces::TimelineEvent
      implements Interfaces::ProjectV2Event
      implements Interfaces::PerformableViaApp

      minimum_accepted_scopes ["read:project"]

      field :status, String, "The new status of the project item.", method: :project_status, null: false
      field :previous_status, String, "The previous status of the project item.", method: :project_previous_status, null: false

      implements_node templates: [[:rpvtisc, :repo_id, :issue_id, :id]],
        as: "PVTISC",
        ready_date: "1970-01-01" do |event|
        {
          prefix: :rpvtisc,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          id: event.id
        }
      end

      class << self
        delegate :async_api_can_access?, to: Platform::Interfaces::ProjectV2Event
        delegate :async_viewer_can_see?, to: Platform::Interfaces::ProjectV2Event
      end
    end
  end
end
