# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class CopilotWorkStartedComponent < ApplicationComponent
    attr_reader :event, :actor, :alert, :last_event

    def initialize(event:, actor:, alert:, last_event:)
      @event = event
      @actor = actor
      @alert = alert
      @last_event = last_event
    end

    def render?
      Dependabot.dependabot_alert_assign_to_copilot_for?(alert.repository)
    end

    def event_at
      event.created_at
    end

    def padding
      @last_event ? 0 : 3
    end

    memoize def session_url
      return nil unless event.session_id.present?

      urls = ViewModel::URLs.new
      return nil unless urls.respond_to?(:repo_session_path)

      repo = alert.repository
      urls.repo_session_path(user_id: repo.owner_display_login, repository: repo.name, session_id: event.session_id)
    end
  end
end
