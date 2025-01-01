# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ConvertedFromDraftEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'converted_from_draft' event on a given issue or pull request."

      visibility :internal

      implements Interfaces::TimelineEvent
      implements Interfaces::ProjectV2Event
      implements Interfaces::PerformableViaApp

      minimum_accepted_scopes ["read:project"]

      implements_node templates: [[:rcfde, :repo_id, :issue_id, :id]],
        as: "CFDE",
        ready_date: "1970-01-01" do |event|
        {
          prefix: :rcfde,
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
