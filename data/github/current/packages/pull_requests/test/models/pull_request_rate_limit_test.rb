# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

# Creating a pull request also creates a backing issue.
# Per https://github.com/github/pull-requests/issues/8423, we want to ensure
# we do not double count "tries" when creating a pull request against the
# content creation limit.
# See:
# https://github.com/github/github/blob/master/lib/github/rate_limited_creation.rb
class PullRequest::ContentCreationLimitTest < GitHub::TestCase
  include RateLimitedCreationTestHelpers

  fixtures do
    @owner = create :user, plan: "medium"
    @org = create(:organization, login: "acme", admin: @owner)
    @repo = create :repository, owner: @org, from_example: :pull_request_source

    @another_owner = create :user, plan: "medium"
    @another_org = create(:organization, login: "acme-clone", admin: @another_owner)
    @another_repo = create :repository, owner: @another_org, from_example: :pull_request_source
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    @owner.content_creation_rate_limit_deallowlist! allowlister: create(:user)
    reset_cache
    reset_redis_rate_limiter
    GitHub.context.push(actor_ip: "8.8.8.8")
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    enable_content_creation_rate_limiting
    GitHub.flipper[:exempt_backing_issue_from_content_creation_limit].disable
  end

  teardown_once do
    disable_cache_storage
  end

  test "with ff enabled, only increments the creation tries once when creating a pull request", skip_enterprise: true do
    # Dynamically set the limit to 1
    # Only the pull request created, not its backing issue, should count
    # toward the tries count. Creation should succeed.
    limit = 1
    GitHub.flipper[:exempt_backing_issue_from_content_creation_limit].enable(@org)
    GitHub::RateLimitedCreation.use_custom_limits({ user_minute: limit, user_hour: limit }) do
      pull = PullRequest.create_for!(@repo,
          base: "master",
          head: "master-forward-2",
          user: @owner,
          title: "new pr!")
      assert pull.valid?
    end
  end

  test "with ff enabled, returns validation error if content creation limit is exceeded", skip_enterprise: true do
    # Dynamically set the limit to 1
    # Only the pull request created, not its backing issue, should count
    # toward the tries count. Creation should succeed, but creating a second
    # issue by the same user should fail.
    limit = 1
    GitHub.flipper[:exempt_backing_issue_from_content_creation_limit].enable(@org)

    GitHub::RateLimitedCreation.use_custom_limits({ user_minute: limit, user_hour: limit }) do
      pull = PullRequest.create_for!(@repo,
          base: "master",
          head: "master-forward-2",
          user: @owner,
          title: "new pr!")
      assert pull.valid?
      issue = build(:issue, user: @owner)
      refute issue.valid?
      assert_equal "was submitted too quickly", issue.errors.full_messages.to_sentence
    end
  end

  test "with ff disabled, raises an error if the content creation limit is exceeded", skip_enterprise: true do
    # Dynamically set the limit to 1
    # Both the pull request created and its backing issue count toward the
    # limit, so an error should be raised as part of creating the pull
    # request.
    limit = 1
    GitHub.flipper[:exempt_backing_issue_from_content_creation_limit].disable
    error = assert_raises(ActiveRecord::RecordInvalid) do
      GitHub::RateLimitedCreation.use_custom_limits({ user_minute: limit, user_hour: limit }) do
        pull = PullRequest.create_for!(@repo,
            base: "master",
            head: "master-forward-2",
            user: @owner,
            title: "new pr!")
      end
    end
    assert_equal "Validation failed: was submitted too quickly", error.message
  end

  test "with ff disabled, raises a validation error if the content creation limit is exceeded when creating another issue after a pull request", skip_enterprise: true do
    # Dynamically set the limit to 2
    # Both the pull request created and its backing issue count toward the
    # limit. When creating another issue that sets it over the limit, the
    # issue should return validation errors.
    limit = 2
    GitHub.flipper[:exempt_backing_issue_from_content_creation_limit].disable
    GitHub::RateLimitedCreation.use_custom_limits({ user_minute: limit, user_hour: limit }) do
      pull = PullRequest.create_for!(@repo,
          base: "master",
          head: "master-forward-2",
          user: @owner,
          title: "new pr!")
      issue = build(:issue, user: @owner)
      refute issue.valid?
      assert_equal "was submitted too quickly", issue.errors.full_messages.to_sentence
    end
  end

  test "with ff disabled, does not raise an error if the content creation limit is not exceeded", skip_enterprise: true do
    # Dynamically set the limit to 2
    # Both the pull request created and its backing issue count toward the
    # limit, but since the limit is 2, no error should be raised.
    limit = 2
    GitHub.flipper[:exempt_backing_issue_from_content_creation_limit].disable
    GitHub::RateLimitedCreation.use_custom_limits({ user_minute: limit, user_hour: limit }) do
      pull = PullRequest.create_for!(@repo,
          base: "master",
          head: "master-forward-2",
          user: @owner,
          title: "new pr!")
    end
  end

  test "with ff disabled, does not raise an error if the content creation limit is not exceeded when creating an issue in addition to creating a pull request", skip_enterprise: true do
    # Dynamically set the limit to 3
    # Both the pull request created and its backing issue count toward the
    # limit, but since the limit is 3, no error should be raised.
    limit = 3
    GitHub.flipper[:exempt_backing_issue_from_content_creation_limit].disable
    GitHub::RateLimitedCreation.use_custom_limits({ user_minute: limit, user_hour: limit }) do
      pull = PullRequest.create_for!(@repo,
          base: "master",
          head: "master-forward-2",
          user: @owner,
          title: "new pr!")
      issue = build(:issue, user: @owner)
      assert issue.valid?
    end
  end

  test "feature flag is enabled by org", skip_enterprise: true do
    # Dynamically set the limit to 1
    # Only the pull request created, not its backing issue, should count
    # toward the tries count. Creation should succeed for @org, but fail for
    # @another_org
    limit = 1
    GitHub.flipper[:exempt_backing_issue_from_content_creation_limit].enable(@org)
    GitHub::RateLimitedCreation.use_custom_limits({ user_minute: limit, user_hour: limit }) do
      pull = PullRequest.create_for!(@repo,
          base: "master",
          head: "master-forward-2",
          user: @owner,
          title: "new pr!")
      assert pull.valid?

      error = assert_raises(ActiveRecord::RecordInvalid) do
        pull2 = PullRequest.create_for!(@another_repo,
            base: "master",
            head: "master-forward-2",
            user: @another_owner,
            title: "new pr!")
      end
      assert_equal "Validation failed: was submitted too quickly", error.message
    end
  end
end

class PullRequestRateLimitTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @forker = create(:user)
    @source = create(:repository, owner: @user, from_example: :pull_request_source)
    @fork, msg = @source.fork(forker: @forker)
    example_repo :pull_request_fork,   @fork

    example_repo_snapshot
  end

  setup do
    example_repo_restore
    reset_cache
    reset_redis_rate_limiter
  end

  test "rate limited per user" do
    enable_content_creation_rate_limiting
    expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]

    with_cache_enabled do
      Timecop.freeze do
        GitHub::RateLimitedCreation.use_custom_limits(user_minute: 2) do
          PullRequest.create!(
            repository: @source,
            base_repository: @source,
            base_user: @source.owner,
            base_ref: "master",
            head_repository: @source,
            head_user: @source.owner,
            head_ref: "master-forward-2",
            issue: create(:issue, repository: @source),
            user: @user)

          PullRequest.create!(
            repository: @source,
            base_repository: @source,
            base_user: @source.owner,
            base_ref: "master",
            head_repository: @fork,
            head_user: @fork.owner,
            head_ref: "topic",
            issue: create(:issue, repository: @source),
            user: @user)

          pull = PullRequest.new(
            repository: @fork,
            base_repository: @fork,
            base_user: @fork.owner,
            base_ref: "master",
            head_repository: @fork,
            head_user: @fork.owner,
            head_ref: "topic",
            issue: create(:issue, repository: @fork),
            user: @user)

          refute_predicate pull, :valid?
          assert_equal expected_errors, pull.errors.full_messages
        end
      end
    end
  end

  test "no errors when no rate limits" do
    disable_content_creation_rate_limiting
    with_cache_enabled do
      Timecop.freeze do
        GitHub::RateLimitedCreation.use_custom_limits(user_minute: 2) do
          PullRequest.create!(
            repository: @source,
            base_repository: @source,
            base_user: @source.owner,
            base_ref: "master",
            head_repository: @source,
            head_user: @source.owner,
            head_ref: "master-forward-2",
            issue: create(:issue, repository: @source),
            user: @user)

          PullRequest.create!(
            repository: @source,
            base_repository: @source,
            base_user: @source.owner,
            base_ref: "master",
            head_repository: @fork,
            head_user: @fork.owner,
            head_ref: "topic",
            issue: create(:issue, repository: @source),
            user: @user)

          pull = PullRequest.new(
            repository: @fork,
            base_repository: @fork,
            base_user: @fork.owner,
            base_ref: "master",
            head_repository: @fork,
            head_user: @fork.owner,
            head_ref: "topic",
            issue: create(:issue, repository: @fork),
            user: @user)

          assert_predicate pull, :valid?
          assert_empty pull.errors.full_messages
        end
      end
    end
  end
end
