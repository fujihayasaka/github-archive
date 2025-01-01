# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RemovedFromProjectV2Event < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'removed_from_project_v2' event on a given issue or pull request."

      visibility :internal

      implements Interfaces::TimelineEvent
      implements Interfaces::ProjectV2Event
      implements Interfaces::PerformableViaApp

      minimum_accepted_scopes ["read:project"]

      implements_node templates: [[:rrfpvte, :repo_id, :issue_id, :id]],
        as: "RFPVTE",
        ready_date: "1970-01-01" do |event|
        {
          prefix: :rrfpvte,
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
