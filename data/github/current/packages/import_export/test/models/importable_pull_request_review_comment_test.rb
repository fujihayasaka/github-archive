# typed: false
# frozen_string_literal: true

require "test_helper"

class ImportablePullRequestReviewCommentTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    repo = create(:importable_repository).tap do |repo|
      example_repo :pull_request_source, repo
      head_ref = repo.heads.create("topic", repo.heads.find("master").target, repo.owner)
      head_ref.append_commit({ message: "a change", committer: repo.owner }, repo.owner) do |files|
        files.add("README.txt", "one\ntwo\nthree\n")
      end
      head_ref.append_commit({ message: "a second change", committer: repo.owner }, repo.owner) do |files|
        files.add("SECOND_README.txt", "four\nfive\nsix\n")
      end
      head_ref.append_commit({ message: "a big change", committer: repo.owner }, repo.owner) do |files|
        files.add("THIRD_README.txt", "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\n")
      end
      repo.import = @import
    end
    @repo = Repository.find_by(id: repo.id)
    @importable_pull_request = create(:importable_pull_request,
                                      user: @user,
                                      repository: @repo,
                                      base_repository: @repo,
                                      head_repository: @repo,
                                      base_ref: "master",
                                      head_ref: "topic",
                                      base_user: @repo.owner,
                                      head_user: @repo.owner,
                                      base_sha: @repo.heads["master"].sha,
                                      head_sha: @repo.heads["topic"].sha,
                                      )
    @pull_request = PullRequest.find_by(id: @importable_pull_request.id)

    @importable_pull_request_review = ImportablePullRequestReview.create(
      pull_request: @pull_request,
      user: @user,
      state: :pending,
      head_sha: @repo.heads.find("master").sha,
      created_at: @created_at,
      submitted_at: @submitted_at,
      body: "Review body comment",
      formatter: :markdown
    )
    @review_thread = create(:pull_request_review_thread, pull_request: @pull_request, path: "README.txt", position: 1)

    @importable_pull_request_review_thread = ImportablePullRequestReviewThread.find(@review_thread.id)
    @pull_request_review_comment = ImportablePullRequestReviewComment.create(
      user: @user,
      pull_request_review_thread: @importable_pull_request_review_thread,
      pull_request_review_id: @importable_pull_request_review.id,
      pull_request: @pull_request,
      body: "Some comment"
    )
  end

  setup do
    @created_at = (Time.now - 3.days).utc
    @submitted_at = (Time.now - 3.days).utc
  end

  test "has PullRequest type" do
    assert_equal "PullRequestReviewComment", @pull_request_review_comment.type
  end

  context "#importing?" do
    test "#importing? returns true during import context" do
      assert @pull_request_review_comment.importing?
    end

    test "#importing? returns false outside of import context" do
      non_import_review_comment = PullRequestReviewComment.find(@pull_request_review_comment.id)
      refute non_import_review_comment.importing?
    end
  end
end

class ImportablePullRequestReviewCommentRateLimitTest < GitHub::TestCase
  include RateLimitedCreationTestHelpers

  fixtures do
    @user = create(:user)
    repo = create(:importable_repository).tap do |repo|
      example_repo :pull_request_source, repo
      head_ref = repo.heads.create("topic", repo.heads.find("master").target, repo.owner)
      head_ref.append_commit({ message: "a change", committer: repo.owner }, repo.owner) do |files|
        files.add("README.txt", "one\ntwo\nthree\n")
      end
      head_ref.append_commit({ message: "a second change", committer: repo.owner }, repo.owner) do |files|
        files.add("SECOND_README.txt", "four\nfive\nsix\n")
      end
      head_ref.append_commit({ message: "a big change", committer: repo.owner }, repo.owner) do |files|
        files.add("THIRD_README.txt", "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\n")
      end
      repo.import = @import
    end
    @repo = Repository.find_by(id: repo.id)
    @importable_pull_request = create(:importable_pull_request,
                                      user: @user,
                                      repository: @repo,
                                      base_repository: @repo,
                                      head_repository: @repo,
                                      base_ref: "master",
                                      head_ref: "topic",
                                      base_user: @repo.owner,
                                      head_user: @repo.owner,
                                      base_sha: @repo.heads["master"].sha,
                                      head_sha: @repo.heads["topic"].sha,
                                      )
    @pull_request = PullRequest.find_by(id: @importable_pull_request.id)

    @pull_request_review = ImportablePullRequestReview.create(
      pull_request: @pull_request,
      user: @user,
      state: :pending,
      head_sha: @repo.heads.find("master").sha,
      created_at: @created_at,
      submitted_at: @submitted_at,
      body: "Review body comment",
      formatter: :markdown
    )
    review_thread = create(:pull_request_review_thread, pull_request: @pull_request, path: "README.txt", position: 1)
    @importable_review_thread = ImportablePullRequestReviewThread.find(review_thread.id)

    @creation_limit = 5
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    reset_redis_rate_limiter
    reset_cache
    @created_at = (Time.now - 3.days).utc
    @submitted_at = (Time.now - 3.days).utc
  end

  teardown_once do
    disable_cache_storage
  end

  test "disallows new creation when rate limit is exceeded" do
    enable_content_creation_rate_limiting
    Timecop.freeze do
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
        assert_create_limited_to_importable_pr_review_comment(@creation_limit, creator: @user, pull_request: @pull_request, review: @pull_request_review, thread: @importable_review_thread)
      end
    end
  end

  test "can apply a dynamic rate limit configuration" do
    enable_content_creation_rate_limiting
    GitHub.flipper[:octoshift_importable_creation_rate_limits].enable

    # Make sure the limits we're going to use below are stricter than the defaults.
    assert GitHub::RateLimitedCreation.limits[:user_minute] > @creation_limit

    with_dynamic_rate_limits_for_octoshift(user_minute: @creation_limit) do
      assert_create_limited_to_importable_pr_review_comment(@creation_limit, creator: @user, pull_request: @pull_request, review: @pull_request_review, thread: @importable_review_thread)
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:importable_pull_request_review_comment", "name:per_user_minute", "config_type:dynamic"]
    )
  end

  test "does not apply a dynamic rate limit configuration by default" do
    enable_content_creation_rate_limiting
    GitHub.flipper[:octoshift_importable_creation_rate_limits].disable

    GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
      with_dynamic_rate_limits_for_octoshift(user_minute: @creation_limit - 1) do
        assert_create_limited_to_importable_pr_review_comment(@creation_limit, creator: @user, pull_request: @pull_request, review: @pull_request_review, thread: @importable_review_thread)
      end
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:importable_pull_request_review_comment", "name:per_user_minute", "config_type:static"]
    )
  end

  test "does not rate limit creation of importable pull request review comment when rate limiting is disabled" do
    disable_content_creation_rate_limiting
    Timecop.freeze do
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
        @creation_limit.times do
          build_review_comment(@user, @pull_request, @importable_review_thread, @pull_request_review)
        end

        importable_pr_review_comment = build_review_comment(@user, @pull_request, @importable_review_thread, @pull_request_review)
        assert_empty importable_pr_review_comment.errors
      end
    end
  end

  def assert_create_limited_to_importable_pr_review_comment(count, creator: @user, pull_request: @pull_request, thread: @importable_review_thread, review: @pull_request_review)
    Timecop.freeze do
      count.times do |i|
        begin
          item = build_review_comment(creator, pull_request, thread, review)
          assert_empty item.errors
        rescue ActiveRecord::RecordInvalid => e
          if e.message.include?("submitted too quickly")
            raise StandardError.new("Expected rate to be limited to #{count}, but failed on #{i + 1}")
          end
        end
      end

      begin
        build_review_comment(creator, pull_request, thread, review)
      rescue ActiveRecord::RecordInvalid => e
        assert_match "submitted too quickly", e.message
        return true
      end
    end

    raise StandardError.new("Expected rate was limited to #{count}, but all items created without error.")
  end

  def build_review_comment(user, pull_request, thread, review)
    ImportablePullRequestReviewComment.create!(
      user: user,
      pull_request_review_thread: thread,
      pull_request_review_id: review.id,
      pull_request: pull_request,
      body: "Some comment"
    )
  end
end
