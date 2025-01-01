# typed: true
# frozen_string_literal: true

module Discussions
  class EventRowComponent < ApplicationComponent
    include HydroHelper
    include BotHelper

    DISCUSSION_EVENT_ICONS = {
      locked: "lock",
      unlocked: "key",
      answer_marked: "check-circle-fill",
      answer_unmarked: "check-circle",
      transferred: "arrow-right",
      created_issue: "issue-opened",
    }.freeze

    def initialize(event:, discussion:)
      @event = event
      @discussion = discussion
    end

    private

    attr_reader :event, :discussion
    delegate :current_repository, to: :helpers

    def click_profile_hydro_data
      helpers.discussion_view_click_attrs(discussion, target: :USER_PROFILE_LINK)
    end

    def discussion_event_badge_color(event_type)
      case event_type.to_sym
      when :locked, :unlocked
        "color-fg-muted"
      when :answer_marked
        "color-fg-success"
      when :answer_unmarked
        "color-fg-muted"
      else
        "color-fg-muted"
      end
    end

    def discussion_event_badge_icon(event_type)
      primer_octicon(DISCUSSION_EVENT_ICONS[event_type.to_sym] || "dot-fill")
    end
  end
end
