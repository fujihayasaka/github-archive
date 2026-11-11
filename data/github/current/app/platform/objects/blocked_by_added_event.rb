# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class BlockedByAddedEvent < Platform::Objects::Base
      include Platform::Objects::Base::IssueDependencyTimelineEventPermissions

      description "Represents a 'blocked_by_added' event on a given issue."
      model_name "IssueEvent"

      implements Interfaces::TimelineEvent
      implements Interfaces::PerformableViaApp

      scopeless_tokens_as_minimum

      field :blocking_issue, Issue, "The blocking issue that was added.", method: :async_subject_as_issue_or_pull_request, null: true

      implements_node templates: [[:rbbae, :repo_id, :issue_id, :id]],
        as: "BBAE",
        ready_date: "1970-01-01" do |event|
        Timeline::Placeholder.async_value_for(event).then do |event|
          {
            prefix: :rbbae,
            repo_id: event.repository_id,
            issue_id: event.issue_id,
            id: event.id,
          }
        end
      end
    end
  end
end
