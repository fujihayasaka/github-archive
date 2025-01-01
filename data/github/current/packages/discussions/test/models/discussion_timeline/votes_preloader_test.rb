# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimeline::VotesPreloaderTest < GitHub::TestCase
  fixtures do
    @repo_owner = create(:verified_user)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @discussion = create(:discussion, repository: @public_repo)
    @discussion_comment = create(:discussion_comment, discussion: @discussion)
  end

  setup do
    @vote = create(:discussion_comment_vote, comment: @discussion_comment, user: @repo_owner)
  end

  test "loads" do
    preloader = DiscussionTimeline::VotesPreloader.new(
      discussion: @discussion,
      comments: [@discussion_comment],
      viewer: @repo_owner,
    )

    assert_query_count_per_table({ discussion_comment_votes: 1 }) do
      preloader.preload
    end

    assert_query_count_per_table({ discussion_comment_votes: 0 }) do
      assert_equal @vote, preloader.vote_for(@discussion_comment)
    end
  end

  test "finds discussion comment from cache" do
    preloader = DiscussionTimeline::VotesPreloader.new(
      discussion: @discussion,
      comments: [@discussion_comment],
      viewer: @repo_owner,
    )
    assert_equal @vote, preloader.vote_for(@discussion_comment)
  end
end
