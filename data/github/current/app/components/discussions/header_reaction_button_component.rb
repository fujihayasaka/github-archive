# typed: true
# frozen_string_literal: true

module Discussions
  class HeaderReactionButtonComponent < ApplicationComponent
    # discussion_or_comment - a Discussion or DiscussionComment
    # timeline - a DiscussionTimeline
    def initialize(discussion_or_comment:, timeline:)
      @discussion_or_comment = discussion_or_comment
      @timeline = timeline
    end

    private

    attr_reader :discussion_or_comment, :timeline

    delegate :discussion, :repository, to: :timeline

    def render?
      logged_in? && discussion_or_comment.present? && timeline.present?
    end

    memoize def nested_comment?
      discussion_or_comment.is_a?(DiscussionComment) && discussion_or_comment.nested?
    end

    def deferred_content_path
      reactions_discussion_path(user_id: repository.owner_display_login, repository: repository.name,
        number: discussion.number)
    end

    def deferred_content_inputs
      { comment_id: discussion_or_comment.id, button_only: true }
    end

    def viewer_reactions
      timeline.reaction_groups(discussion_or_comment).filter_map do |reaction_group|
        reaction_group.emotion.content if reaction_group.user_reacted?(current_user)
      end
    end
  end
end
