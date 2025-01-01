# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestSuggestedReviewerTest < GitHub::TestCase
  setup do
    @user = User.new
  end

  context "scoring suggestions" do
    test "combines blame and comment scores into total" do
      subject = PullRequest::SuggestedReviewer.new(user: @user, pull: nil, author: 12, commenter: 30)
      assert_equal 42, subject.score
    end
  end

  context "sorting suggestions" do
    test "orders suggestions by total score lowest to highest" do
      user2 = User.new
      user3 = User.new

      suggestions = [
        PullRequest::SuggestedReviewer.new(user: user2, pull: nil, author: 20),
        PullRequest::SuggestedReviewer.new(user: @user, pull: nil, author: 10),
        PullRequest::SuggestedReviewer.new(user: user3, pull: nil, author: 30),
      ]

      assert_equal [@user, user2, user3], suggestions.sort.map(&:user)
    end
  end

  context "merging suggestions" do
    test "creates a new suggestion with merged score" do
      author = PullRequest::SuggestedReviewer.new(user: @user, pull: nil, author: 12)
      commenter = PullRequest::SuggestedReviewer.new(user: @user, pull: nil, commenter: 30)
      merged = author.merge(commenter)

      assert_equal 12, author.score
      assert_equal 30, commenter.score

      assert_equal 42, merged.score
      assert_predicate merged, :author?
      assert_predicate merged, :commenter?
    end
  end

  test "provides suggestion reasons" do
    author = PullRequest::SuggestedReviewer.new(user: @user, pull: nil, author: 12)
    assert_predicate author, :author?
    refute_predicate author, :commenter?

    reviewer = PullRequest::SuggestedReviewer.new(user: @user, pull: nil, commenter: 30)
    refute_predicate reviewer, :author?
    assert_predicate reviewer, :commenter?

    merged = author.merge(reviewer)
    assert_predicate merged, :author?
    assert_predicate merged, :commenter?
  end
end
