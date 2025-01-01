# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportablePullRequestTest < GitHub::TestCase
  fixtures do
    repo = create(:importable_repository).tap do |repo|
      example_repo :pull_request_source, repo
      head_ref = repo.heads.create("topic", repo.heads.find("master").target, repo.owner)
      head_ref.append_commit({ message: "a change", committer: repo.owner }, repo.owner) do |files|
        files.add("README.txt", "one\ntwo\nthree\n")
      end
      @repo = Repository.find_by(id: repo.id)
    end
    @pull = create(:importable_pull_request,
      repository: @repo,
      base_repository: @repo,
      head_repository: @repo,
      base_ref: "master",
      head_ref: "topic",
      base_user: @repo.owner,
      head_user: @repo.owner,
      base_sha: @repo.heads["master"].sha,
      head_sha: @repo.heads["topic"].sha,
      status: "open",
    )
    @user = create(:user)
    @import = create(:import, creator: @user)
  end

  context "#build_pull_request" do
    test "should create an active pull request" do
      created_at = Time.now - 7.days
      pull_request = ImportablePullRequest.build_pull_request(
        repository: @repo,
        user: @user,
        base_ref: "master",
        head_ref: "topic",
        base_sha: @repo.heads["master"].sha,
        head_sha: @repo.heads["topic"].sha,
        created_at: created_at,
        maintainer_can_modify: true,
        draft: true,
        import: @import,
        status: "open",
        issue_attributes: {
          title: "New pull request title",
          body: "Body of the pull request",
        }
      )

      assert pull_request.save
      assert_equal @repo.id, pull_request.repository_id
      assert_equal "master", pull_request.base_ref
      assert_equal "topic", pull_request.head_ref
      assert_equal @repo.heads.find("master").sha, pull_request.base_sha
      assert_equal @repo.heads.find("topic").sha, pull_request.head_sha
      assert_equal "New pull request title", pull_request.issue.title
      assert_equal true, pull_request.work_in_progress
      assert_nil pull_request.merged_at
      assert_equal :open, pull_request.state
      assert_equal "open", pull_request.status
      assert_equal created_at.to_i, pull_request.created_at.to_i
      assert_equal created_at.to_i, pull_request.issue.created_at.to_i
    end

    test "should create a pull request with a specified number" do
      created_at = Time.now - 7.days
      number = 55

      pull_request = ImportablePullRequest.build_pull_request(
        repository: @repo,
        user: @user,
        base_ref: "master",
        head_ref: "topic",
        base_sha: @repo.heads["master"].sha,
        head_sha: @repo.heads["topic"].sha,
        created_at: created_at,
        maintainer_can_modify: true,
        draft: true,
        import: @import,
        issue_attributes: {
          title: "New pull request title",
          body: "Body of the pull request",
          number: number
        }
      )

      assert pull_request.save
      assert_equal @repo.id, pull_request.repository_id
      assert_equal "New pull request title", pull_request.issue.title
      assert_equal number, pull_request.number
    end

    test "should create a pull request with an unspecified number" do
      created_at = Time.now - 7.days

      pull_request = ImportablePullRequest.build_pull_request(
        repository: @repo,
        user: @user,
        base_ref: "master",
        head_ref: "topic",
        base_sha: @repo.heads["master"].sha,
        head_sha: @repo.heads["topic"].sha,
        created_at: created_at,
        maintainer_can_modify: true,
        draft: true,
        import: @import,
        issue_attributes: {
          title: "New pull request title",
          body: "Body of the pull request"
        }
      )

      assert pull_request.save
      assert_equal @repo.id, pull_request.repository_id
      assert_equal "New pull request title", pull_request.issue.title
      assert_equal 2, pull_request.number
    end

    test "should create a merged pull request" do
      created_at = Time.now - 7.days
      merged_at = Time.now - 5.days
      pull_request = ImportablePullRequest.build_pull_request(
        repository: @repo,
        user: @user,
        base_ref: "master",
        head_ref: "topic",
        base_sha: @repo.heads["master"].sha,
        head_sha: @repo.heads["topic"].sha,
        created_at: created_at,
        merged_at: merged_at,
        closed_at: merged_at,
        draft: false,
        import: @import,
        issue_attributes: {
          title: "New pull request title",
          body: "Body of the pull request",
        }
      )

      assert pull_request.save
      assert_equal :merged, pull_request.state
      assert_equal true, pull_request.closed?
      assert_equal merged_at.to_i, pull_request.merged_at.to_i
      assert_equal merged_at.to_i, pull_request.issue.closed_at.to_i
    end

    test "should create a closed pull request" do
      created_at = Time.now - 7.days
      closed_at = Time.now - 5.days
      pull_request = ImportablePullRequest.build_pull_request(
        repository: @repo,
        user: @user,
        base_ref: "master",
        head_ref: "topic",
        base_sha: @repo.heads["master"].sha,
        head_sha: @repo.heads["topic"].sha,
        created_at: created_at,
        closed_at: closed_at,
        draft: false,
        import: @import,
        status: "closed",
        issue_attributes: {
          title: "New pull request title",
          body: "Body of the pull request",
        }
      )

      assert pull_request.save
      assert_equal :closed, pull_request.state
      assert_equal "closed", pull_request.status
      assert_equal true, pull_request.closed?
      assert_nil pull_request.merged_at
      assert_equal closed_at.to_i, pull_request.closed_at.to_i
      assert_equal closed_at.to_i, pull_request.issue.closed_at.to_i
    end

    test "should create a pull request with an associated milestone" do
      created_at = Time.now - 7.days
      milestone = create(:milestone, repository: @repo)
      pull_request = ImportablePullRequest.build_pull_request(
        repository: @repo,
        user: @user,
        base_ref: "master",
        head_ref: "topic",
        base_sha: @repo.heads["master"].sha,
        head_sha: @repo.heads["topic"].sha,
        created_at: created_at,
        draft: false,
        import: @import,
        issue_attributes: {
          title: "New pull request title",
          body: "Body of the pull request",
          milestone: milestone
        }
      )

      assert pull_request.save
      assert_equal @repo.id, pull_request.repository_id
      assert_equal "New pull request title", pull_request.issue.title
      assert_equal created_at.to_i, pull_request.created_at.to_i
      assert_equal created_at.to_i, pull_request.issue.created_at.to_i
      assert_equal milestone.id, pull_request.issue.milestone.id
    end
  end

  test "has PullRequest type" do
    assert_equal "PullRequest", @pull.type
  end

  context "#importing?" do
    test "#importing? returns true during import context" do
      assert @pull.importing?
    end

    test "#importing? returns false outside of import context" do
      non_import_pull_request = PullRequest.find(@pull.id)
      refute non_import_pull_request.importing?
    end
  end

  context "validations" do
    test "disables validations within import context" do
      pull_request = ImportablePullRequest.new
      pull_request.expects(:record_concrete_commit_points).never
      pull_request.expects(:prefix_refs).never
      pull_request.expects(:repo_and_base_must_match).never
      pull_request.expects(:must_have_commits).never
      pull_request.expects(:base_ref_is_real_branch).never
      pull_request.expects(:head_ref_is_not_namespaced).never
      pull_request.expects(:duplicate_check).never

      pull_request.save
    end
  end
end

class ImportablePullRequestRateLimitTest < GitHub::TestCase
  include RateLimitedCreationTestHelpers

  fixtures do
    @user = create(:user)
    repo = create(:importable_repository).tap do |repo|
      example_repo :pull_request_source, repo
    end
    @import = create(:import, creator: @user)
    @repo = Repository.find_by(id: repo.id)
    @creation_limit = 10
    # we have to halve the expected importable pull requests
    # because each pr creation also creates an issue,
    # which counts against the user's creation limit
    @expected_importable_pull_requests = @creation_limit / 2
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    reset_redis_rate_limiter
    reset_cache
    @created_at = Time.now - 7.days
  end

  teardown_once do
    disable_cache_storage
  end

  test "disallows new creation when rate limit is exceeded" do
    enable_content_creation_rate_limiting
    Timecop.freeze do
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
        assert_create_limited_to_importable_pr(@expected_importable_pull_requests, repo: @repo, creator: @user, import: @import)
      end
    end
  end

  test "can apply a dynamic rate limit configuration" do
    enable_content_creation_rate_limiting
    enable_feature_flag(:octoshift_importable_creation_rate_limits)

    # Make sure the limits we're going to use below are stricter than the defaults.
    assert T.must(GitHub::RateLimitedCreation.limits[:user_minute]) > @creation_limit

    with_dynamic_rate_limits_for_octoshift(user_minute: @creation_limit) do
      assert_create_limited_to_importable_pr(@expected_importable_pull_requests, repo: @repo, creator: @user, import: @import)
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:importable_pull_request", "name:per_user_minute", "config_type:dynamic"]
    )
  end

  test "does not apply a dynamic rate limit configuration by default" do
    enable_content_creation_rate_limiting
    disable_feature_flag(:octoshift_importable_creation_rate_limits)

    GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
      with_dynamic_rate_limits_for_octoshift(user_minute: @expected_importable_pull_requests - 1) do
        assert_create_limited_to_importable_pr(@expected_importable_pull_requests, repo: @repo, creator: @user, import: @import)
      end
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:importable_issue", "name:per_user_minute", "config_type:static"]
    )
  end

  test "does not rate limit creation of importable pull request when rate limiting is disabled" do
    disable_content_creation_rate_limiting
    Timecop.freeze do
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
        @creation_limit.times do
          build_pr(@repo, @import, @user)
        end

        importable_issue = build_pr(@repo, @import, @user)
        assert importable_issue.save
        assert_empty importable_issue.errors
      end
    end
  end

  private

  def build_pr(repo, import, user)
    ref_name = Faker::Alphanumeric.alphanumeric(number: 7)
    ref = repo.heads.create(ref_name, repo.heads.find("master").target, repo.owner)
    ref.append_commit({ message: "a change", committer: repo.owner }, repo.owner) do |files|
      files.add("README.txt", "one\ntwo\nthree\n")
    end

    created_at = Time.now - 7.days

    importable_pull_request = ImportablePullRequest.build_pull_request(
      repository: repo,
      user: user,
      base_ref: "master",
      head_ref: ref_name,
      base_sha: repo.heads["master"].sha,
      head_sha: repo.heads[ref_name].sha,
      created_at: created_at,
      maintainer_can_modify: true,
      draft: true,
      import: @import,
      issue_attributes: {
        title: "New pull request title",
        body: "Body of the pull request",
      }
    )
    importable_pull_request.save!
    importable_pull_request
  end

  def assert_create_limited_to_importable_pr(count, repo: @repo, creator: @user, import: @import)
    Timecop.freeze do
      count.times do |i|
        begin
          ref_name = Faker::Alphanumeric.alphanumeric(number: 7)
          item = build_pr(repo, import, creator)
          assert_empty item.errors
        rescue ActiveRecord::RecordInvalid => e
          if e.message.include?("submitted too quickly")
            raise StandardError.new("Expected rate to be limited to #{count}, but failed on #{i + 1}")
          end
        end
      end

      begin
        ref_name = Faker::Alphanumeric.alphanumeric(number: 7)
        build_pr(repo, import, creator)

      rescue ActiveRecord::RecordInvalid => e
        assert_match "submitted too quickly", e.message
        return true
      end

    end

    raise StandardError.new("Expected rate was limited to #{count}, but all items created without error.")
  end
end
