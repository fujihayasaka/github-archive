# typed: true
# frozen_string_literal: true

module Discussions
  class TimelineLoadMoreComponent < ApplicationComponent
    # timeline - a DiscussionTimeline
    # hidden_items_count - Integer count of how many items are hidden that could be loaded
    # before - optional String pagination cursor
    # after - optional String pagination cursor
    def initialize(timeline:, hidden_items_count:, before: nil, after: nil)
      @timeline = timeline
      @hidden_items_count = hidden_items_count
      @before = before
      @after = after
    end

    private

    attr_reader :timeline, :hidden_items_count, :before, :after

    delegate :repo_owner_login, :repo_name, :discussion_number, to: :timeline

    def render?
      timeline.present? && hidden_items_count&.positive? && GitHub.discussions_available_on_platform?
    end
  end
end
