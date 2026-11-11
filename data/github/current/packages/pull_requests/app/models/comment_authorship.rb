# typed: true
# frozen_string_literal: true

# Mixin for CommitComments, IssueComments, PullRequestReviews,
# and PullRequestReviewComments to check if a given user authored
# the comment.
module CommentAuthorship
  extend T::Helpers

  requires_ancestor { ActiveRecord::Base }

  abstract!

  sig { abstract.returns(T.nilable(Integer)) }
  def user_id; end

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def authored_by?(user)
    user_id == user&.id
  end
end
