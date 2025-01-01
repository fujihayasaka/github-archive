# typed: false
# frozen_string_literal: true

module Events
  class PullRequestReviewCommentView < View
    include ActionView::Helpers::TagHelper

    def title_text
      parts = [actor_text, actor_bot_identifier_text, "commented on pull request", pull_text]
      parts.compact.join(" ")
    end

    def pull_text
      if pull_comment_url
        "#{repo_nwo}##{pull_number}"
      else
        "(deleted)"
      end
    end

    def formatted_comment
      truncate_html(comment_body, 150)
    end

    def pull_comment_url
      comment_url || pull_url
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def comment_body
      @comment_body ||= if payload[:comment]
        payload[:comment][:body]
      else
        comment && comment.body
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def icon
      "issues_comment"
    end

    private

    def comment_url
      payload[:comment][:_links][:html][:href]
    rescue # rubocop:todo Lint/GenericRescue
      nil
    end

    # do not call this
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def comment
      @comment ||= unless defined?(@comment)
        if (id = payload[:comment] && payload[:comment][:id]).to_i > 0
          ::PullRequestReviewComment.find_by_id(id)
        end
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # We don't have the pull request number as a field in the event or payload
    # so find it by stripping it from the URL we do have.
    #
    #   @url = "http://github.dev/mojombo/god/pull/2#discussion_r1130"
    #   pull_number
    #   # => 2
    #
    # Returns the pull request number Integer.
    def pull_number
      pull_url.split("/").last.to_i
    end

    # We don't have the bare pull request url in the event or payload so create it
    # by stripping the comment hash from the url.
    #
    #   @url = "http://github.dev/mojombo/god/pull/2#discussion_r1130"
    #   pull_url
    #   # => "http://github.dev/mojombo/god/pull/2"
    #
    # Returns the full path (without the host) to the pull request as a String.
    def pull_url
      if href = payload[:comment][:_links][:html][:href] rescue nil
        href
      elsif pull = comment.try(:pull_request)
        pull.permalink(include_host: false)
      end
    end
  end
end
