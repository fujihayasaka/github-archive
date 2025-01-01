# typed: false
# frozen_string_literal: true

module Events
  class CommitCommentView < View
    include ActionView::Helpers::TagHelper

    def title_text
      parts = [actor_text, actor_bot_identifier_text, "commented on commit", event_text]
      parts.compact.join(" ")
    end

    def formatted_comment
      comment.async_truncated_body_html(150).sync
    end

    def show_formatted_comment?
      comment.present?
    end

    def commit_sha_summary
      "#{repo_nwo}@#{commit_sha.first(10)}"
    end

    def comment_html_url
      return "/" unless comment
      comment.full_permalink(include_host: false)
    end

    def commit_sha
      comment_commit_id.to_s
    end

    private

    def event_text
      if commit_sha.present?
        commit_sha_summary
      end
    end

    # do not call this
    #
    # Returns a CommitComment or nil.
    def comment
      return @comment if defined?(@comment)

      @comment = if comment_id.present?
        ::CommitComment.find_by_id(comment_id)
      end
    end
  end
end
