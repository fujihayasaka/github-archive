# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportableIssueTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @issue = create(:importable_issue)
  end

  test "has Issue type" do
    assert_equal "Issue", @issue.type
  end

  context "#importing?" do
    test "#importing? returns true during import context" do
      assert @issue.importing?
    end

    test "#importing? returns false outside of import context" do
      non_import_issue = Issue.find(@issue.id)
      refute non_import_issue.importing?
    end

    test "does not create notifications on create" do
      importable_issue = build(:importable_issue)
      assert importable_issue.save

      Notifyd::NotifyPublisher.any_instance.expects(:publish).never
      refute_delivered_any_notifications(importable_issue.user)

      assert_equal CreateIssueOrchestration.last&.state, "succeeded"
      assert_equal CreateIssueOrchestration.last&.issue_id, importable_issue.id
    end
  end

  context "skipped callbacks" do
    context "#subscribe_and_notify" do
      test "is skipped within an import context" do
        ImportableIssue.any_instance.expects(:subscribe_and_notify).never
        create(:importable_issue)
      end

      test "is not skipped outside an import context" do
        Issue.any_instance.expects(:subscribe_and_notify).once
        create(:issue)
      end
    end

    context "#body" do
      test "soft limit is skipped within an import context" do
        string_length = MYSQL_UNICODE_BLOB_LIMIT / 4 + 1
        body = "Z" * string_length
        issue = build(:importable_issue, body: body)
        assert issue.valid?
      end

      test "hard limit is still enforced, issue fails to validate" do
        string_length = MYSQL_UNICODE_BLOB_LIMIT + 1
        body = "Z" * string_length
        issue = build(:importable_issue, body: body)
        refute issue.valid?
      end
    end
  end
end

class ImportableIssueRateLimitTest < GitHub::TestCase
  include RateLimitedCreationTestHelpers

  fixtures do
    @user = create(:verified_user)
    @repo = create(:repository, owner: @user)
    @creation_limit = 5
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    reset_redis_rate_limiter
    reset_cache
  end

  teardown_once do
    disable_cache_storage
  end

  test "disallows new creation when rate limit is exceeded" do
    enable_content_creation_rate_limiting
    Timecop.freeze do
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
        assert_create_limited_to(@creation_limit, repo: @repo, creator: @user, type: :importable_issue)
      end
    end
  end

  test "can apply a dynamic rate limit configuration" do
    enable_content_creation_rate_limiting
    GitHub.flipper[:octoshift_importable_creation_rate_limits].enable

    # Make sure the limits we're going to use below are stricter than the defaults.
    assert T.must(GitHub::RateLimitedCreation.limits[:user_minute]) > @creation_limit

    with_dynamic_rate_limits_for_octoshift(user_minute: @creation_limit) do
      assert_create_limited_to(@creation_limit, repo: @repo, creator: @user, type: :importable_issue)
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:importable_issue", "name:per_user_minute", "config_type:dynamic"]
    )
  end

  test "does not apply a dynamic rate limit configuration by default" do
    enable_content_creation_rate_limiting
    GitHub.flipper[:octoshift_importable_creation_rate_limits].disable

    GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
      with_dynamic_rate_limits_for_octoshift(user_minute: @creation_limit - 1) do
        assert_create_limited_to(@creation_limit, type: :importable_issue)
      end
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:importable_issue", "name:per_user_minute", "config_type:static"]
    )
  end

  test "does not rate limit creation of importable issue when rate limiting is disabled" do
    disable_content_creation_rate_limiting
    Timecop.freeze do
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
        @creation_limit.times do
          create(:importable_issue)
        end

        importable_issue = build(:importable_issue)
        assert importable_issue.save
        assert_empty importable_issue.errors
      end
    end
  end
end
