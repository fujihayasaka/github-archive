# typed: true
# frozen_string_literal: true

module Discussions
  class SidebarEventsComponent < ApplicationComponent
    JS_EVENT_LIST_DOM_ID = "paginated-discussion-events-list"

    def initialize(timeline:, events:)
      @timeline = timeline
      @events = events
    end

    private

    attr_reader :timeline, :events

    delegate :repo_name, :repo_owner_login, :discussion, to: :timeline

    memoize def paginated?
      timeline.has_paginated_events?
    end

    def render?
      events.present? && logged_in?
    end

    def is_comment(item)
      item.is_a?(DiscussionComment)
    end
  end
end
