# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportableIssueCommentTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @issue_comment = create(:importable_issue_comment)
  end

  test "has IssueComent type" do
    assert_equal "IssueComment", @issue_comment.type
  end

  context "#importing?" do
    test "#importing? returns true during import context" do
      assert @issue_comment.importing?
    end

    test "#importing? returns false outside of import context" do
      non_import_issue_comment = IssueComment.find(@issue_comment.id)
      refute non_import_issue_comment.importing?
    end

    test "does not create notifications on create" do
      importable_issue_comment = build(:importable_issue_comment)
      assert importable_issue_comment.save

      Notifyd::NotifyPublisher.any_instance.expects(:publish).never
      refute_delivered_any_notifications(importable_issue_comment.user)

      assert_equal CreateIssueCommentOrchestration.last&.state, "succeeded"
      assert_equal CreateIssueCommentOrchestration.last&.issue_comment_id, importable_issue_comment.id
    end
  end

  context "skipped callbacks" do
    context "#subscribe_and_notify" do
      test "is skipped within an import context" do
        ImportableIssueComment.any_instance.expects(:subscribe_and_notify).never
        create(:importable_issue_comment, :wait_for_orchestration)
      end

      test "is not skipped outside an import context" do
        IssueComment.any_instance.expects(:subscribe_and_notify).once
        create(:issue_comment, :wait_for_orchestration)
      end
    end
  end
end

class ImportableIssueCommentRateLimitTest < GitHub::TestCase
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
        assert_create_limited_to(@creation_limit, repo: @repo, creator: @user, type: :importable_issue_comment)
      end
    end
  end

  test "can apply a dynamic rate limit configuration" do
    enable_content_creation_rate_limiting
    GitHub.flipper[:octoshift_importable_creation_rate_limits].enable

    # Make sure the limits we're going to use below are stricter than the defaults.
    assert T.must(GitHub::RateLimitedCreation.limits[:user_minute]) > @creation_limit

    with_dynamic_rate_limits_for_octoshift(user_minute: @creation_limit) do
      assert_create_limited_to(@creation_limit, repo: @repo, creator: @user, type: :importable_issue_comment)
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:importable_issue_comment", "name:per_user_minute", "config_type:dynamic"]
    )
  end

  test "does not apply a dynamic rate limit configuration by default" do
    enable_content_creation_rate_limiting
    GitHub.flipper[:octoshift_importable_creation_rate_limits].disable

    GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
      with_dynamic_rate_limits_for_octoshift(user_minute: @creation_limit - 1) do
        assert_create_limited_to(@creation_limit, type: :importable_issue_comment)
      end
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:importable_issue_comment", "name:per_user_minute", "config_type:static"]
    )
  end

  test "does not rate limit creation of importable issue comment when rate limiting is disabled" do
    disable_content_creation_rate_limiting
    Timecop.freeze do
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
        @creation_limit.times do
          create(:importable_issue_comment)
        end

        importable_issue_comment = build(:importable_issue_comment)
        assert importable_issue_comment.save
        assert_empty importable_issue_comment.errors
      end
    end
  end
end
