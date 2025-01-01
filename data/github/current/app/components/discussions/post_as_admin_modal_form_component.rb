# typed: strict
# frozen_string_literal: true

module Discussions
  class PostAsAdminModalFormComponent < ApplicationComponent
    sig { params(discussion_or_comment: T.any(Discussion, DiscussionComment), timeline: DiscussionTimeline).void }
    def initialize(discussion_or_comment:, timeline:)
      @discussion_or_comment = discussion_or_comment
      @timeline = timeline
    end

    sig { returns(T.any(Discussion, DiscussionComment)) }
    attr_reader :discussion_or_comment

    sig { returns(DiscussionTimeline) }
    attr_reader :timeline

    private

    sig { returns(T::Boolean) }
    def render?
      helpers.can_post_as_admin? &&
        (discussion_or_comment.author&.site_admin? || discussion_or_comment.author&.employee?)
    end

    sig { returns(String) }
    def form_path
      if discussion_or_comment.is_a?(Discussion)
        discussion_path(
          timeline.discussion,
          timeline.discussion.repository,
        )
      else
        discussion_comment_path(
          timeline.repo_owner_login,
          timeline.repo_name,
          timeline.discussion.number,
          id: discussion_or_comment.id,
        )
      end
    end

    sig { returns(String) }
    def parameter_name
      if discussion_or_comment.is_a?(Discussion)
        "discussion[post_as_admin]"
      else
        "comment[post_as_admin]"
      end
    end
  end
end
