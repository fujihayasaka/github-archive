# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionSearchResultTest < GitHub::TestCase
  fixtures do
    setup_search
  end

  teardown do
    teardown_search
  end

  context ".search" do
    test "returns discussions matching the query" do
      repo_owner = create(:user)
      repo = create(:repository, owner: repo_owner, has_discussions: true)

      discussion_matching_title = create(:discussion, repository: repo, title: "qwerty")
      make_searchable discussion_matching_title

      discussion_matching_body = create(:discussion, repository: repo, body: "qwerty abc")
      make_searchable discussion_matching_body

      discussion_matching_comment_body = create(:discussion, repository: repo).tap do |disc|
        create(:discussion_comment, discussion: disc, body: "abc qwerty")
      end
      make_searchable discussion_matching_comment_body

      discussion_not_matching = create(:discussion, repository: repo, title: "not a match")
      make_searchable discussion_not_matching

      refresh_search

      result = Discussion::SearchResult.search(
        query: ["qwerty"],
        page: nil,
        per_page: nil,
        repo: repo,
        current_user: repo_owner,
      )

      assert_equal 3, result.size
      assert_includes result, discussion_matching_title
      assert_includes result, discussion_matching_body
      assert_includes result, discussion_matching_comment_body
      refute_includes result, discussion_not_matching
    end

    test "limits the total_entries of paginated entries based on max_offset_default" do
      repo = create(:repository, has_discussions: true)
      discussions = create_list(:discussion, 3, repository: repo, title: "qwerty")
      discussions << create(:discussion, repository: repo, title: "not a match")
      discussions.map(&method(:make_searchable))
      refresh_search

      ::Search::Query.stubs(:max_offset_default).returns(2)
      result = Discussion::SearchResult.search(
        query: ["qwerty"],
        page: nil,
        per_page: nil,
        repo: repo,
        current_user: repo.owner,
      )

      assert_equal 3, result.size
      assert_equal 2, result.total_entries

      ::Search::Query.stubs(:max_offset_default).returns(3)
      result = Discussion::SearchResult.search(
        query: ["qwerty"],
        page: nil,
        per_page: nil,
        repo: repo,
        current_user: repo.owner,
      )

      assert_equal 3, result.size
      assert_equal 3, result.total_entries
    end

    test "returns discussions matching the query -is:answered" do
      repo_owner = create(:user)
      repo = create(:repository, owner: repo_owner, has_discussions: true)

      category = create(:discussion_category, repository: repo, supports_mark_as_answer: true)

      discussion_answered = create(:discussion, repository: repo, category: category).tap do |disc|
        disc.chosen_comment = create(:discussion_comment, discussion: disc)
      end
      make_searchable discussion_answered

      discussion_not_answered = create(:discussion, repository: repo, category: category)
      make_searchable discussion_not_answered

      refresh_search

      result = Discussion::SearchResult.search(
        query: ["-is:answered"],
        page: nil,
        per_page: nil,
        repo: repo,
        current_user: repo_owner,
      )

      assert_equal 1, result.size
      assert_includes result, discussion_not_answered
      refute_includes result, discussion_answered
    end

    test "resturns empty result if SearchResult is error" do
      repo = create(:repository, has_discussions: true)
      make_searchable create(:discussion, repository: repo, title: "qwerty")
      refresh_search

      ::Search::Results.any_instance.stubs(:error?).returns(true)

      result = Discussion::SearchResult.search(
        query: ["qwerty"],
        page: nil,
        per_page: nil,
        repo: repo,
        current_user: repo.owner,
      )

      assert_equal 0, result.size
    end
  end
end
