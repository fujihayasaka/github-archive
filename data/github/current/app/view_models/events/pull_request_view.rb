# typed: false
# frozen_string_literal: true

module Events
  class PullRequestView < View
    BODY_MAX_LENGTH = 150

    def labeled_event?
      Stratocaster::Event.labeled_event?(action)
    end

    def title_text
      parts = if labeled_event?
        [
          actor_text,
          actor_bot_identifier_text,
          action,
          "a pull request with",
          label_name,
          "in",
          repo_text,
        ]
      else
        [actor_text, actor_bot_identifier_text, action, "a pull request in", repo_text]
      end
      parts.compact.join(" ")
    end

    # Returns 'opened', 'reopened', 'closed', or 'merged'.
    def action
      a = super
      a == "closed" && pull_request.try(:merged_at) ? "merged" : a
    end

    def not_closed
      action != "closed"
    end

    def pull_title
      pull_request_hash[:title] || pull_request.try(:title)
    end

    def commit_text
      "commit".pluralize(total_commits)
    end

    def addition_text
      "addition".pluralize(total_additions)
    end

    def deletion_text
      "deletion".pluralize(total_deletions)
    end

    # The first 150 characters of the pull request's HTML body.
    #
    # Returns a String or nil.
    def formatted_pull_request_body
      if pull_request_body.present?
        truncate_html(pull_request_body, BODY_MAX_LENGTH)
      end
    end

    # The class to apply to the pull request's octicon.
    #
    # Returns a String.
    def octicon_class
      if pull_request_hash["merged"]
        "merged"
      else
        pull_request_state || ""
      end
    end

    def url
      if (num = issue_number) > 0
        "/#{repo_nwo}/pull/#{num}"
      else
        "/#{repo_nwo}/pulls"
      end
    end

    def total_additions
      pull_request_hash[:additions] ||= pull_request ? pull_request.historical_comparison.diffs.additions : 0
    end

    def total_deletions
      pull_request_hash[:deletions] ||= pull_request ? pull_request.historical_comparison.diffs.deletions : 0
    end

    def total_commits
      pull_request_hash[:commits] ||= pull_request ? pull_request.historical_comparison.total_commits : 0
    end

    def issue_number
      pull_request_hash[:number] || payload[:number] || pull_request.try(:number) || 0
    end

    def icon
      "issues_#{action}"
    end

    private

    # do not call this
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def pull_request
      @pull_request ||= unless defined?(@pull_request)
        id = pull_request_hash[:id].to_i
        ::PullRequest.find_by_id(id)
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def pull_request_hash
      pull = payload[:pull_request]
      case pull
      when Hash
        pull
      else
        { id: pull }
      end
    end
  end
end
