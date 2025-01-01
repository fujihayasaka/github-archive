# typed: false
# frozen_string_literal: true

require "test_helper"

class ImportablePullRequestReviewTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    repo = create(:importable_repository).tap do |repo|
      example_repo :pull_request_source, repo
      head_ref = repo.heads.create("topic", repo.heads.find("master").target, repo.owner)
      head_ref.append_commit({ message: "a change", committer: repo.owner }, repo.owner) do |files|
        files.add("README.txt", "one\ntwo\nthree\n")
      end
      @repo = Repository.find_by(id: repo.id)
    end
    @importable_pull_request = create(:importable_pull_request,
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
    @pull_request_review = create(:importable_pull_request_review, :approved, pull_request: @pull_request, user: @user)
  end

  test "has PullRequest type" do
    assert_equal "PullRequestReview", @pull_request_review.type
  end

  context "#importing?" do
    test "#importing? returns true during import context" do
      assert @pull_request_review.importing?
    end

    test "#importing? returns false outside of import context" do
      non_import_review = PullRequestReview.find(@pull_request_review.id)
      refute non_import_review.importing?
    end
  end

  context "skipped callbacks" do
    context "#subscribe_and_notify" do
      test "is skipped within an import context" do
        PullRequestReview.any_instance.expects(:subscribe_and_notify).never
        @pull_request_review.save!
      end

      test "is not skipped outside an import context" do
        PullRequestReview.any_instance.expects(:subscribe_and_notify).once
        import_review = create(:pull_request_review, pull_request: @pull_request, user: @user)
        import_review.approve!
      end
    end
  end
end

class ImportablePullRequestReviewRateLimitTest < GitHub::TestCase
  include RateLimitedCreationTestHelpers

  fixtures do
    @user = create(:verified_user)
    repo = create(:importable_repository).tap do |repo|
      example_repo :pull_request_source, repo
      head_ref = repo.heads.create("topic", repo.heads.find("master").target, repo.owner)
      head_ref.append_commit({ message: "a change", committer: repo.owner }, repo.owner) do |files|
        files.add("README.txt", "one\ntwo\nthree\n")
      end
    end
    @repo = Repository.find_by(id: repo.id)
    @importable_pull_request = create(:importable_pull_request,
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
    @creation_limit = 5
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    reset_cache
    reset_monolith_redis_rate_limiter
  end

  teardown_once do
    disable_cache_storage
  end

  test "disallows new creation when rate limit is exceeded" do
    enable_content_creation_rate_limiting
    Timecop.freeze do
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
        assert_create_limited_to_importable_pr_review(@creation_limit, creator: @user, pull_request: @pull_request)
      end
    end
  end

  test "can apply a dynamic rate limit configuration" do
    enable_content_creation_rate_limiting
    GitHub.flipper[:octoshift_importable_creation_rate_limits].enable

    # Make sure the limits we're going to use below are stricter than the defaults.
    assert GitHub::RateLimitedCreation.limits[:user_minute] > @creation_limit

    with_dynamic_rate_limits_for_octoshift(user_minute: @creation_limit) do
      assert_create_limited_to_importable_pr_review(@creation_limit, creator: @user, pull_request: @pull_request)
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:importable_pull_request_review", "name:per_user_minute", "config_type:dynamic"]
    )
  end

  test "does not apply a dynamic rate limit configuration by default" do
    enable_content_creation_rate_limiting
    GitHub.flipper[:octoshift_importable_creation_rate_limits].disable

    GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
      with_dynamic_rate_limits_for_octoshift(user_minute: @creation_limit - 1) do
        assert_create_limited_to_importable_pr_review(@creation_limit, creator: @user, pull_request: @pull_request)
      end
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:importable_pull_request_review", "name:per_user_minute", "config_type:static"]
    )
  end

  test "does not rate limit creation of importable pull request review when rate limiting is disabled" do
    disable_content_creation_rate_limiting
    Timecop.freeze do
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
        @creation_limit.times do
          create(:importable_pull_request_review, :approved, pull_request: @pull_request, user: @user)
        end

        importable_pr_review = create(:importable_pull_request_review, :approved, pull_request: @pull_request, user: @user)
        assert_empty importable_pr_review.errors
      end
    end
  end

  def assert_create_limited_to_importable_pr_review(count, creator: @user, pull_request: @pull_request)
    Timecop.freeze do
      count.times do |i|
        begin
          item = create(:importable_pull_request_review, :approved, pull_request: pull_request, user: creator)
          assert_empty item.errors
        rescue ActiveRecord::RecordInvalid => e
          if e.message.include?("submitted too quickly")
            raise StandardError.new("Expected rate to be limited to #{count}, but failed on #{i + 1}")
          end
        end
      end

      begin
        create(:importable_pull_request_review, :approved, pull_request: pull_request, user: creator)
      rescue ActiveRecord::RecordInvalid => e
        assert_match "submitted too quickly", e.message
        return true
      end
    end

    raise StandardError.new("Expected rate was limited to #{count}, but all items created without error.")
  end
end
