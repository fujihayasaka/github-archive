# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    def gh_stafftools_repository_issue_comments_path(issue)
      expand_issue_or_pr \
        issue,
        :stafftools_repository_issue_comments_path,
        :stafftools_repository_pull_request_comments_path
    end

    def gh_first_stafftools_repository_issue_comments_path(issue)
      expand_issue_or_pr \
        issue,
        :first_stafftools_repository_issue_comments_path,
        :first_stafftools_repository_pull_request_comments_path
    end

    def gh_stafftools_repository_issue_comment_path(comment)
      expand_issue_or_pr_comment \
        comment,
        :stafftools_repository_issue_comment_path,
        :stafftools_repository_pull_request_comment_path
    end

    def gh_database_stafftools_repository_issue_comment_path(comment)
      expand_issue_or_pr_comment \
        comment,
        :database_stafftools_repository_issue_comment_path,
        :database_stafftools_repository_pull_request_comment_path
    end

    def gh_stafftools_repository_issue_subscriptions_path(issue)
      expand_from_issue :stafftools_repository_issue_subscriptions_path, issue
    end

    def gh_stafftools_repository_pull_request_review_comments_path(pr)
      expand_from_pr :stafftools_repository_pull_request_review_comments_path, pr
    end

    def gh_stafftools_repository_pull_request_review_comment_path(comment)
      T.bind(self, T.untyped)
      pull = comment.pull_request
      repo = comment.repository
      stafftools_repository_pull_request_review_comment_path(repo.owner, repo.name, pull.number, comment)
    end

    def gh_database_stafftools_repository_pull_request_review_comment_path(comment)
      T.bind(self, T.untyped)
      pull = comment.pull_request
      repo = comment.repository
      database_stafftools_repository_pull_request_review_comment_path(repo.owner, repo.name, pull.number, comment)
    end

    private

    def expand_issue_or_pr(issue, issue_helper, pr_helper)
      if is_pr?(issue)
        expand_from_pr(pr_helper, issue)
      else
        expand_from_issue(issue_helper, issue)
      end
    end

    def expand_from_comment(helper, comment)
      issue = comment.issue
      repo = issue.repository
      send(helper, repo.owner, repo.name, issue.number, comment)
    end

    def expand_issue_or_pr_comment(comment, issue_helper, pr_helper)
      helper = is_pr?(comment.issue) ? pr_helper : issue_helper
      expand_from_comment helper, comment
    end

    def is_pr?(issue)
      issue.try(:pull_request?) || issue.is_a?(PullRequest)
    end

  end
end
