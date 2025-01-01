# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryHasDiscussionsTest < GitHub::TestCase
  JOBS = [AddToSearchIndexJob, RemoveFromSearchIndexJob, RepositoryOrchestrationJob]

  fixtures do
    create_search_indices

    @repo = create(:repository, has_discussions: true)
    @discussion = create(:discussion, repository: @repo, title: "repohasdiscussionstest")

    setup_search
    make_searchable(@discussion)
  end

  test "converting from private to public lazily re-indexes discussions" do
    perform_enqueued_jobs(only: JOBS) do
      @repo.toggle_visibility(actor: @repo.owner, visibility: "private")

      refresh_search
      # now that the index has been refreshed, this query returns the discussion correctly
      assert_equal [@discussion], search_results_for_query("#{@discussion.title} is:private")
      assert_equal [], search_results_for_query("#{@discussion.title} is:public")
    end

    perform_enqueued_jobs(only: JOBS) do
      @repo.toggle_visibility(actor: @repo.owner, visibility: "public")
    end

    perform_enqueued_jobs(only: JOBS) do
      refresh_search
      # index has not been updated yet, so visibility is out of date.
      # the reindex job should be kicked off, but because there is no visibilty qualifier in the search, we can still
      # return the result
      assert_equal [@discussion], search_results_for_query(@discussion.title)

      refresh_search
      assert_equal [], search_results_for_query("#{@discussion.title} is:private")
      assert_equal [@discussion], search_results_for_query("#{@discussion.title} is:public")
    end
  end

  test "disabling discussions removes them from the search index" do
    assert @repo.discussions_on?

    make_searchable(@discussion)
    refresh_search
    assert_equal [@discussion], search_results_for_query(@discussion.title),
      "expected @discussion to be searchable"

    perform_enqueued_jobs(only: JOBS) do
      @repo.turn_off_discussions(actor: @repo.owner, instrument: false)
    end

    refresh_search
    assert_empty search_results_for_query(@discussion.title),
      "expected @discussion to have been removed"
  end

  test "deleting the repository does not fail the reindexing job" do
    Failbot.expects(:report!).never

    perform_enqueued_jobs(only: JOBS) do
      @repo.remove(@repo.owner, synchronous: true)
      @repo.purge(synchronous: true)
    end

    refresh_search
    assert_empty search_results_for_query(@discussion.title),
      "expected @discussion to have been removed"
  end

  test "enabling discussions adds them to the search index" do
    @repo.turn_off_discussions(actor: @repo.owner, instrument: false)
    refute @repo.discussions_on?

    refresh_search
    assert_empty search_results_for_query(@discussion.title),
      "expected @discussion to not be indexed"

    perform_enqueued_jobs(only: JOBS) do
      @repo.turn_on_discussions(actor: @repo.owner, instrument: false)
    end

    refresh_search
    assert_equal [@discussion], search_results_for_query(@discussion.title),
      "expected @discussion to be searchable"
  end

  def search_results_for_query(query)
    query = Search::Queries::DiscussionQuery.normalize(
      Search::Queries::DiscussionQuery.parse(query),
    )

    Discussion::SearchResult.search(
      query: query,
      page: 1,
      per_page: 5,
      repo: @repo,
      current_user: @repo.owner,
    )
  end
end
