# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class TimelineItemComponent < ApplicationComponent
    attr_reader :issue_event, :render_actor, :badge_params

    renders_one :body
    renders_one :additional_details
    renders_one :action

    def initialize(issue_event:, render_actor: true, render_copilot: false, **badge_params)
      @issue_event = issue_event
      @render_actor = render_actor
      @render_copilot = render_copilot
      @badge_params = badge_params
    end

    memoize def actor
      if @render_copilot
        copilot_app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
        return copilot_app.bot if copilot_app.present?
      end

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
