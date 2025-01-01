# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class ReviewRequestedEventComponent < ApplicationComponent
    attr_reader :issue_events

    def initialize(issue_events:, pull_request:)
      @issue_events = issue_events
      @pull_request = pull_request
    end

    # A component describing what happened.  Most of the logic is delegated to these.
    def description_component
      if issue_events.size == 1
        PullRequests::TimelineEvents::ReviewRequest::SingleDescriptionComponent.new(
          issue_event: issue_events.first, actor: actor, pull_request: @pull_request
        )
      else
        PullRequests::TimelineEvents::ReviewRequest::MultipleDescriptionComponent.new(
          issue_events: issue_events, pull_request: @pull_request
        )
      end
    end

    memoize def actor
      issue_events.first.event_actor(viewer: @current_user)
    end
  end
end
