# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewEnforcedLoaderTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include PerformanceTestHelpers

  setup do
    @owner = create(:user, plan: "micro")
    @collab = create(:user)
    @another_collab = create(:user)
    @read_only_user = create(:user)

    @source = create(:private_repository, owner: @owner, from_example: :review_comment_source)
    @source.add_member @collab, action: :write
    @source.add_member @another_collab, action: :write
    @source.add_member @read_only_user, action: :read


    metadata = { message: "new commit", committer: @owner }
    @commit = @source.commits.create(metadata, @source.refs.find("master").target_oid) do |files|
      files.add("new-file.txt", "new file")
    end

    @source.heads.create("fake-master", @source.heads.find("master").target_oid, @owner)

    @reviews = []
    first_review = T.let(nil, T.nilable(PullRequestReview))
    second_review = T.let(nil, T.nilable(PullRequestReview))
    third_review = T.let(nil, T.nilable(PullRequestReview))
    fourth_review = T.let(nil, T.nilable(PullRequestReview))
    2.times do |index|
      ref = @source.refs.create("refs/heads/topic-#{index}", @commit, @owner)

      issue = create(:issue, user: @owner, repository: @source)
      pull = PullRequest.create_for(@source,
        base: "master",
        head: ref.name,
        user: issue.user,
        issue: issue)
      issue.pull_request = pull

      Timecop.freeze(5.minutes.ago) do
        first_review = create(:pull_request_review, pull_request: pull,
          user: @collab,
          head_sha: pull.head_sha
        )
        first_review.request_changes!
      end

      second_review = Timecop.freeze(4.minutes.ago) do
        second_review = create(:pull_request_review, pull_request: pull,
          user: @collab,
          head_sha: pull.head_sha
        )
        second_review.approve!
        second_review
      end

      third_review = Timecop.freeze(3.minutes.ago) do
        third_review = create(:pull_request_review, pull_request: pull,
          user: @read_only_user,
          head_sha: pull.head_sha
        )
        third_review.request_changes!
        third_review
      end

      if index == 0
        fourth_review = Timecop.freeze(2.minutes.ago) do
          fourth_review = create(:pull_request_review, pull_request: pull,
            user: @another_collab,
            head_sha: pull.head_sha
          )
          fourth_review.approve!
          fourth_review
        end
        @reviews << fourth_review
      end

      @reviews << second_review << third_review
    end

    # create a pull request on a differing base branch. Its reviews should not be considered
    # for inclusion when looking for reviews based on master.
    issue = create(:issue, user: @owner, repository: @source)
    pull_with_wrong_base = PullRequest.create_for(@source,
      base: "fake-master",
      head: "topic-1",
      user: issue.user,
      issue: issue,
    )
    issue.pull_request = pull_with_wrong_base

    review = create(:pull_request_review, pull_request: pull_with_wrong_base,
      user: @collab,
      head_sha: pull_with_wrong_base.head_sha
    )
    review.approve!
  end

  test "loads enforced reviews for a head SHA" do
    loader = PullRequestReview::EnforcedLoader.new(
      repository: @source,
      pull_request_head_sha: @commit.oid,
      base_ref_name: "master",
    )
    reviews = loader.execute

    assert_equal @reviews.sort, reviews.sort

    reviews_per_pull = @reviews.group_by(&:pull_request_id).values
    assert_equal [3, 2], reviews_per_pull.map(&:count)
  end

  test "loads enforced reviews for a head SHA created by writers only" do
    loader = PullRequestReview::EnforcedLoader.new(
      repository: @source,
      pull_request_head_sha: @commit.oid,
      base_ref_name: "master",
      writers_only: true,
    )
    reviews = loader.execute

    reviews_per_pull = @reviews.group_by(&:pull_request_id).values
    writers_reviews = reviews_per_pull.map { |reviews| reviews.select(&:writer?) }
    assert_equal [2, 1], writers_reviews.map(&:count)
  end

  test "loads enforced reviews for a head SHA, base ref, and open PRs only" do
    reviews_per_pull = @reviews.group_by(&:pull_request)
    pulls = reviews_per_pull.keys
    assert_equal 2, pulls.size # sanity check

    pulls.first.close
    pulls.first.save!
    expected_reviews = reviews_per_pull[pulls.last]

    loader = PullRequestReview::EnforcedLoader.new(
      repository: @source,
      pull_request_head_sha: @commit.oid,
      base_ref_name: "master",
      open_pulls_only: true,
    )
    reviews = loader.execute

    assert_equal expected_reviews.sort, reviews.sort
  end

  test "loads enforced reviews by fully qualified base ref" do
    reviews_per_pull_request = @reviews.group_by(&:pull_request)
    pull_request = reviews_per_pull_request.keys.last

    loader = PullRequestReview::EnforcedLoader.new(
      repository: @source,
      pull_request_head_sha: @commit.oid,
      base_ref_name: "refs/heads/master",
      open_pulls_only: true,
    )

    reviews = loader.execute
    loaded_reviews = reviews.select { |review| review.pull_request == pull_request }.sort

    assert_equal reviews_per_pull_request[pull_request].sort, loaded_reviews
  end

  test "loads enforced reviews for a PR ID" do
    pull_request_id = @reviews.first.pull_request_id
    loader = PullRequestReview::EnforcedLoader.new(
      repository: @source,
      pull_request: @reviews.first.pull_request,
    )
    reviews = loader.execute

    expected_reviews = @reviews.select { |r| r.pull_request_id == pull_request_id }
    assert_equal expected_reviews.sort, reviews.sort
  end

  test "The loader matches the enforced loader with writers_only being false" do
    pull_request_id = @reviews.first.pull_request_id
    loader = PullRequestReview::EnforcedLoader.new(
      repository: @source,
      pull_request: @reviews.first.pull_request,
    )
    reviews = loader.execute
    loader_reviews = Platform::Loaders::PullRequestEnforcedReviews.load(@reviews.first.pull_request, writers_only: false).sync

    expected_reviews = @reviews.select { |r| r.pull_request_id == pull_request_id }
    assert_equal expected_reviews.sort, reviews.sort
    assert_equal loader_reviews.sort, reviews.sort
  end

  test "The loader matches the enforced loader with writers_only being true" do
    pull_request_id = @reviews.first.pull_request_id
    loader = PullRequestReview::EnforcedLoader.new(
      repository: @source,
      pull_request: @reviews.first.pull_request,
      writers_only: true,
    )

    reviews = loader.execute
    loader_reviews = Platform::Loaders::PullRequestEnforcedReviews.load(@reviews.first.pull_request, writers_only: true).sync
    assert_equal loader_reviews.sort, reviews.sort
  end


  test "The loader matches the enforced loader with writers_only being true with batch loading" do
    pulls = @reviews.map { |r| r.pull_request }
    Promise.all(pulls.map do |pull|
      pull.async_latest_enforced_reviews(writers_only: true)
    end).sync

    pulls.each do |pull|
      reviews = PullRequestReview::EnforcedLoader.new(
        repository: pull.repository,
        pull_request: pull,
        writers_only: true,
      ).execute

      assert_max_query_count(0, ignore_feature_flags: true) do
        assert_equal pull.async_latest_enforced_reviews(writers_only: true).sync.sort, reviews.sort
      end
    end
  end

  test "Ensure loader only queries once" do
    pulls = @reviews.map { |r| r.pull_request }
    assert_equal 5, pulls.length
    table_counts = { pull_request_reviews: 1 }
    # Only one loader query should be executed since it should be batched
    assert_max_query_count_per_table(table_counts) do
      Promise.all(pulls.map do |pull|
        pull.async_latest_enforced_reviews(writers_only: true)
      end).sync
    end
  end

  test "creates valid queries" do
    assert_no_query_warnings do
      loader = PullRequestReview::EnforcedLoader.new(
        repository: @source,
        pull_request_head_sha: @commit.oid,
        base_ref_name: GRIN_EMOJI,
      )
      reviews = loader.execute

      assert_equal [], reviews
    end
  end

  context "raises error" do
    test "if neither head OID nor PR ID is passed" do
      assert_raises ArgumentError do
        PullRequestReview::EnforcedLoader.new(repository: @source, base_ref_name: "master")
      end
    end

    test "if neither head OID nor base_ref_name are passed" do
      assert_raises ArgumentError do
        PullRequestReview::EnforcedLoader.new(repository: @source, pull_request_head_sha: "f" * 40)
      end
    end

    test "if no head OID, base_ref_name, nor PR ID are passed" do
      assert_raises ArgumentError do
        PullRequestReview::EnforcedLoader.new(repository: @source)
      end
    end
  end

  test "prefills the passed in pull request on each review" do
    pull_request = @reviews.first.pull_request
    reviews = PullRequestReview::EnforcedLoader.new(
      repository: @source,
      pull_request: pull_request,
    ).execute
    refute_empty reviews
    reviews.each { |review| assert_same pull_request, review.pull_request }
  end

  test "observes exclude draft parameter" do
    # verify that we have 3 reviews for the first pull request and 2 for the second
    pull_request = @reviews.group_by(&:pull_request).keys.first
    loader = PullRequestReview::EnforcedLoader.new(
      repository: @source,
      pull_request_head_sha: @commit.oid,
      base_ref_name: "refs/heads/master",
      open_pulls_only: true,
      exclude_drafts: false,
    )
    reviews = loader.execute.group_by(&:pull_request)
    assert_equal 2, reviews.keys.count
    assert_equal pull_request.id, reviews.keys.first.id
    assert_equal [3, 2], reviews.values.map(&:count)

    # update the first pull request to be a draft
    pull_request.convert_to_draft(user: pull_request.user)

    # verify that we now only have 2 reviews for the second pull request
    loader = PullRequestReview::EnforcedLoader.new(
      repository: @source,
      pull_request_head_sha: @commit.oid,
      base_ref_name: "refs/heads/master",
      open_pulls_only: true,
      exclude_drafts: true,
    )
    reviews = loader.execute.group_by(&:pull_request)
    assert_equal 1, reviews.keys.count
    refute_equal pull_request.id, reviews.keys.first.id
    assert_equal [2], reviews.values.map(&:count)
  end
end
