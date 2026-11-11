# typed: true
# frozen_string_literal: true

module Discussions
  class ManageCategoryPinComponent < ApplicationComponent
    # timeline - a DiscussionTimeline
    def initialize(timeline:)
      @timeline = timeline
    end

    private

    attr_reader :timeline

    delegate :repository, :discussion, :repo_owner_login, :repo_name, :discussion_number, to: :timeline

    def render?
      timeline.can_manage_category_pins?
    end

    def category
      discussion.category
    end

    def pinned?
      timeline.pinned?
    end
  end
end
