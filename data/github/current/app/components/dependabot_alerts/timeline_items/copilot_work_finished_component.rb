# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class CopilotWorkFinishedComponent < ApplicationComponent
    attr_reader :event, :actor, :alert, :last_event, :current_user

    def initialize(event:, actor:, alert:, last_event:, current_user: nil)
      @event = event
      @actor = actor
      @alert = alert
      @last_event = last_event
      @current_user = current_user
    end

    # TODO: Remove current_user param once dependabot_alerts_assign_to_copilot feature flag is removed
    def render?
      Dependabot.dependabot_alert_assign_to_copilot_for?(alert.repository, current_user)
    end

    def event_at
      event.created_at
    end

    def padding
      @last_event ? 0 : 3
    end

    memoize def pull_request
      event.pull_request
    end

    delegate :number, to: :pull_request, prefix: true, allow_nil: true

    def pull_request_path
      pull_request && helpers.pull_request_path(pull_request, alert.repository)
    end

    def pull_request_link_data_attributes
      return {} unless pull_request
      {
        hovercard_type: "pull_request",
        hovercard_url: "#{pull_request_path}/hovercard",
      }
    end

    # Taken from https://github.com/github/github/blob/5d6e6aafca3049308861ed049b58fcf2b7085da7/app/helpers/issues_helper.rb#L727
    # It was not imported due to test `HelpersAreUsedProperlyTest#test_no_files_include_app_helpers`,
    # @see https://github.com/github/monolith-fitness/discussions/92
    def pr_state_octicon_ar(pr)
      return nil unless pr.is_a? PullRequest

      icon = PullRequest::Icon.new(
        pr,
        permit_queued_icon: false,
      )
      octicon(
        icon.octicon_name,
        class: "#{icon.state} color-fg-#{icon.primer_color}",
        title: icon.short_label,
        "aria-label": icon.label,
      )
    end
  end
end
