# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class TimelineItemComponent < ApplicationComponent
    attr_reader :issue_event, :render_actor, :badge_params

    renders_one :body
    renders_one :additional_details
    renders_one :action

    def initialize(issue_event:, render_actor: true, **badge_params)
      @issue_event = issue_event
      @render_actor = render_actor
      @badge_params = badge_params
    end

    memoize def actor
      issue_event.event_actor(viewer: current_user)
    end

    memoize def anchor
      "event-#{issue_event.id}"
    end

    memoize def via_app
      issue_event.async_integration_for_user(current_user).sync
    end
  end
end
