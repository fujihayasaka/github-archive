# typed: true
# frozen_string_literal: true

module Events
  class IssueCommentView < View
    def title_text
      parts = [actor_text, actor_bot_identifier_text, "commented on", object, issue_text]
      parts.compact.join(" ")
    end

    def number
      if payload[:issue]
        payload[:issue][:number].to_i
      elsif issue
        issue.number
      end
    end

    def issue_text
      if number
        "#{T.unsafe(self).repo_nwo}##{number}"
      else
        "(deleted)"
      end
    end

    def formatted_comment
      truncate_html(comment_body, 150)
    end

    def object
      is_pull_request ? "pull request" : "issue"
    end

    def url
      comment_url || issue_url
    end

    def issue_title
      if payload[:issue]
        payload[:issue][:title]
      else
        issue.try(:title)
      end
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

    def is_pull_request
      if pull_request
        !pull_request[:html_url].nil?
      else
        issue.try(:pull_request?)
      end
    end

    # do not call this
    # Deal with multiple payload versions:
    #
    #     {:issue_id => 123}
    #     {:issue => {:id => 123}
    #
    # Returns an Issue, or nil.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def issue
      @issue ||= unless defined?(@issue)
        if (id = (payload[:issue] && payload[:issue][:id]) || 0).to_i > 0
          ::Issue.find_by(id: id)
        elsif (id = payload[:issue_id].to_i) > 0
          ::Issue.find_by(id: id)
        end
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # do not call this
    # Deal with multiple payload versions:
    #
    #     {:comment_id => 123}
    #     {:comment => {:id => 123}
    #
    # Returns an IssueComment, or nil.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def comment
      @comment ||= unless defined?(@comment)
        if (id = payload[:comment] && payload[:comment][:id]).to_i > 0
          ::IssueComment.find_by(id: id)
        elsif (id = payload[:comment_id].to_i) > 0
          ::IssueComment.find_by(id: id)
        end
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def pull_request
      (payload[:issue] && payload[:issue][:pull_request]) || {}
    end

    def issue_url
      type = is_pull_request ? :pull : :issues
      "/#{T.unsafe(self).repo_nwo}/#{type}/#{number}"
    end

    def comment_url
      id = if payload[:comment]
        payload[:comment][:id]
      else
        payload[:comment_id] || (comment && comment.id)
      end
      id && "#{issue_url}#issuecomment-#{id}"
    end
  end
end
