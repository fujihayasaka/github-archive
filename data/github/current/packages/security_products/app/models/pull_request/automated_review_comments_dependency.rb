# typed: true
# frozen_string_literal: true

class PullRequest
  module AutomatedReviewCommentsDependency
    extend ActiveSupport::Concern
    extend T::Helpers
    include GitHub::Memoizer

    requires_ancestor { PullRequest }

    included do
      T.bind(self, T.class_of(PullRequest))
      has_many :automated_review_comments, -> (pr) { where(repository_id: pr.repository_id) }
      destroy_dependents_in_background :automated_review_comments
    end

    sig { params(review_comment_id: Integer).returns(T.nilable(AutomatedReviewComment)) }
    def automated_review_comment_for_review_comment(review_comment_id)
      unless defined?(@automated_review_comments_map)
        @automated_review_comments_map = automated_review_comments.to_a.index_by(&:pull_request_review_comment_id)
      end
      @automated_review_comments_map[review_comment_id]
    end
  end
end
