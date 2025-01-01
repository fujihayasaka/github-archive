# typed: true
# frozen_string_literal: true

module Comments
  class CommentSubjectAuthorComponent < ApplicationComponent
    attr_reader :comment

    def initialize(comment:)
      @comment = comment
    end

    def render?
      authored_by_subject_author
    end

    def subject_type
      case comment
      when ::PullRequestReview, ::PullRequestReviewComment
        "pull request"
      when ::CommitComment
        "commit"
      when ::IssueComment, ::Issue::Adapter::CommentAdapter
        if comment.issue.is_a?(::PullRequest::Adapter::PullRequestAdapter)
          "pull request"
        else
          "issue"
        end
      when ::RepositoryAdvisoryComment, ::RepositoryAdvisory::Adapter::CommentAdapter
        "repository advisory"
      else
        nil
      end
    end

    def authored_by_subject_author
      case comment
      when ::IssueComment
        comment.user_id == comment.issue.user_id
      when ::Issue::Adapter::CommentAdapter, ::RepositoryAdvisory::Adapter::CommentAdapter
        comment.authored_by_subject_author
      when ::PullRequestReview, ::PullRequestReviewComment
        comment.async_pull_request.then { |pull| pull.user_id == comment.user_id }.sync
      when ::GistComment
        comment.gist.user_id == comment.user_id
      when ::CommitComment
        comment.user_id == comment.commit&.author&.id
      when ::RepositoryAdvisoryComment
        comment.user_id == comment.repository_advisory.author_id
      else
        false
      end
    end

    memoize def viewer_did_author
      comment.user_id == current_user&.id
    end

    def label
      "#{viewer_did_author ? "You are" : "This user is" } the author of this #{subject_type}."
    end
  end
end
