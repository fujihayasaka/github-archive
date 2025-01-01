# typed: true
# frozen_string_literal: true

module Discussions
  class CommentCountComponent < ApplicationComponent
    # discussion - a Discussion
    # repository - the Repository the given discussion belongs to
    def initialize(discussion:, repository:)
      @discussion = discussion
      @repository = repository
    end

    private

    attr_reader :discussion

    delegate :comment_count, to: :discussion
    delegate :direct_comment_count, to: :discussion

    def live_update_path
      discussion_comment_count_path(@repository.owner_display_login, @repository.name, discussion)
    end

    memoize def reply_count
      begin
        comment_count - direct_comment_count
      end
    end

    def direct_comment_noun
      "comment"
    end
  end
end
