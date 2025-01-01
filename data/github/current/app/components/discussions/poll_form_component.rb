# typed: true
# frozen_string_literal: true

module Discussions
  class PollFormComponent < ApplicationComponent
    def initialize(discussion:, category:, required_options_min: DiscussionPoll::MIN_OPTIONS, hidden: false)
      @discussion = discussion
      @category = category
      @required_options_min = required_options_min
      @hidden = hidden
    end

    attr_accessor :discussion, :category, :required_options_min, :hidden

    def hidden?
      @hidden
    end

    def poll_error_present?
      discussion_poll&.errors.present?
    end

    def discussion_poll
      @discussion.poll || @discussion.build_poll
    end

    def required_option?(index)
      index < required_options_min
    end

    def option_placeholder_text(index)
      required_option?(index) ? "Option #{index + 1} (required)" : "Option"
    end

    def get_discussion_poll_preview_path
      repository = discussion.repository
      discussions_poll_preview_path(
        user_id: repository.owner,
        repository: repository
      )
    end
  end
end
