# typed: strict
# frozen_string_literal: true

module CodeCoverage
  # Finds the most recent code coverage comment posted by the given author on
  # a pull request issue.
  #
  # Identification uses two layers:
  #   1. The comment must belong to the given author.
  #   2. The comment body must contain the HTML marker <!-- code-coverage-overview -->.
  #
  # All bot comments are scanned (newest first) so that non-coverage comments
  # posted after the marked one don't prevent it from being found.
  # Minimized marked comments are still returned so they can be updated
  # in place without being expanded.
  class CommentFinder
    MARKER = "<!-- code-coverage-overview -->"

    sig { returns(Issue) }
    attr_reader :issue

    sig { returns(User) }
    attr_reader :author

    sig { params(issue: Issue, author: User).void }
    def initialize(issue:, author:)
      @issue = issue
      @author = author
    end

    sig { returns(T.nilable(IssueComment)) }
    def find
      issue.comments.where(user: author).reorder(id: :desc).detect do |comment|
        comment.body.include?(MARKER)
      end
    end
  end
end
