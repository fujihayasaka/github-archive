# typed: true
# frozen_string_literal: true

module Discussions
  class ContentComponent < ApplicationComponent
    def initialize(
      timeline:,
      parsed_discussions_query: [],
      org_param: nil
    )
      @timeline = timeline
      @parsed_discussions_query = parsed_discussions_query
      @org_param = org_param
    end

    private

    attr_reader :timeline, :parsed_discussions_query, :org_param

    delegate :discussion, :repository, :blocked_from_commenting?, to: :timeline

    def render?
      timeline.present?
    end

    def render_discussions_summary?
      logged_in? && current_user.copilot_discussion_summary_feature_enabled?
    end
  end
end
