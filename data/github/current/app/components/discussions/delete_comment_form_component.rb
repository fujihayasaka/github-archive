# typed: strict
# frozen_string_literal: true

module Discussions
  class DeleteCommentFormComponent < ApplicationComponent
    sig { params(comment: DiscussionComment, timeline: DiscussionTimeline).void }
    def initialize(comment:, timeline:)
      @comment = comment
      @timeline = timeline
    end

    sig { returns(DiscussionComment) }
    attr_reader :comment

    sig { returns(DiscussionTimeline) }
    attr_reader :timeline

    # Private: Should deleting a discussion or one of its comments happen in an
    # AJAX request or a regular HTTP request?
    #
    # Returns a Boolean. True indicates an AJAX request is fine for deletion.
    sig { params(discussion_or_comment: T.any(Discussion, DiscussionComment)).returns(T::Boolean) }
    def self.delete_discussion_or_comment_async?(discussion_or_comment)
      if discussion_or_comment.is_a?(Discussion)
        # Do regular HTTP request for deleting a discussion since
        # the user will be redirected to another page.
        false
      else
        # If we have a nested comment, we can delete it asynchronously because
        # it won't have any child comments.
        return true if discussion_or_comment.nested?

        # If we have a top-level comment with no children, can delete
        # asynchronously. Otherwise, want to do a regular HTTP request so
        # the page reloads and we show the ghost user for the wiped parent comment.
        discussion_or_comment.comment_count < 1
      end
    end

    private

    sig { returns(String) }
    def form_path
      discussion_comment_path(timeline.repo_owner_login, timeline.repo_name, timeline.discussion_number, comment)
    end

    sig { params(discussion_or_comment: T.any(Discussion, DiscussionComment)).returns(T::Boolean) }
    def delete_discussion_or_comment_async?(discussion_or_comment)
      self.class.delete_discussion_or_comment_async?(discussion_or_comment)
    end
  end
end
