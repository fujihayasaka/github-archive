# typed: true
# frozen_string_literal: true

module Discussions
  class TimelineItemsComponent < ApplicationComponent
    # timeline - a DiscussionTimeline
    # items - Array that may contain DiscussionComment, DiscussionEventGroup, or DiscussionEvent objects
    def initialize(timeline:, items:)
      @timeline = timeline
      @items = items
    end

    private

    attr_reader :timeline

    delegate :repo_name, :discussion_number, :max_number_of_nested_comments_to_render, :repo_owner_login,
      to: :timeline

    def render?
      timeline.present? && GitHub.discussions_available_on_platform?
    end

    def discussion_comments
      @items.select { |item| item.is_a?(DiscussionComment) }
    end
  end
end
