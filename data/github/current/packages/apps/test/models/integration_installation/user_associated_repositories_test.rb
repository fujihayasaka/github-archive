# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallation::UserAssociatedRepositoriesTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:private_repository, :minimal, owner: @user)
    @org = create(:organization)
    @org.add_member(@user)
    @org_repo = create(:private_repository, :minimal, owner: @org)

    @installation = make_integration_installation(repository: @repo, permissions: { "metadata" => :read })
    @org_installation = make_integration_installation(repository: @org_repo, permissions: { "metadata" => :read })
  end

  test "does nothing when feature flag is disabled for the associated App", skip_enterprise: true do
    Flipper[:installation_user_associated_repo_ids_cache].disable(@installation.integration)

    IntegrationInstallation::UserAssociatedRepositories.expects(:set_cache).never

    actual_value = IntegrationInstallation::UserAssociatedRepositories.with_cache(user: @user, installation: @installation) { [@repo.id] }
    assert_equal [@repo.id], actual_value
  end

  test "does nothing on Enterprise", enterprise_only: true do
    IntegrationInstallation::UserAssociatedRepositories.expects(:set_cache).never

    actual_value = IntegrationInstallation::UserAssociatedRepositories.with_cache(user: @user, installation: @installation) { [@repo.id] }
    assert_equal [@repo.id], actual_value
  end

  test "sets cache key based on user, installation type and installation ID", skip_enterprise: true do
    Flipper[:installation_user_associated_repo_ids_cache].enable(@installation.integration)

    IntegrationInstallation::UserAssociatedRepositories.expects(:set_cache).once.with do |key, _, _|
      assert_match /#{@user.id}:IntegrationInstallation:#{@installation.id}/, key
    end
    IntegrationInstallation::UserAssociatedRepositories.with_cache(user: @user, installation: @installation) { [@repo.id] }
  end

  test "sets cache value by JSON encoding value returned by block", skip_enterprise: true do
    Flipper[:installation_user_associated_repo_ids_cache].enable(@installation.integration)

    IntegrationInstallation::UserAssociatedRepositories.expects(:set_cache).once.with do |_, _value, _|
      [@repo.id].to_json
    end
    IntegrationInstallation::UserAssociatedRepositories.with_cache(user: @user, installation: @installation) { [@repo.id] }
  end

  test "sets cache TTL to 30 seconds", skip_enterprise: true do
    Flipper[:installation_user_associated_repo_ids_cache].enable(@installation.integration)

    IntegrationInstallation::UserAssociatedRepositories.expects(:set_cache).once.with do |_, _, ttl|
      assert_equal 30.seconds, ttl
    end
    IntegrationInstallation::UserAssociatedRepositories.with_cache(user: @user, installation: @installation) { [@repo.id] }
  end

  test "returns cached value when available", skip_enterprise: true do
    Flipper[:installation_user_associated_repo_ids_cache].enable(@installation.integration)

    # Ensure the cache is properly reset so we don't interfere with other tests
    # that stub GitHub.cache.
    with_cache_enabled(/installation:user:repo_ids/) do
      GitHub.cache.set(
        IntegrationInstallation::UserAssociatedRepositories.cache_key(@user, @installation),
        [@repo.id].to_json
      )

      actual_value = IntegrationInstallation::UserAssociatedRepositories.with_cache(user: @user, installation: @installation) { "irrelevant" }
      assert_equal [@repo.id], actual_value
    end
  end

  test "does not enqueue new job without flag enabled", skip_enterprise: true do
    Flipper[:installation_user_associated_repo_ids_cache].disable(@org_installation.integration)

    assert_no_enqueued_jobs(only: IntegrationInstallationUserAssociatedRepositoriesCacheJob) do
      with_cache_enabled(/installation:user:repo_ids/) do
        IntegrationInstallation::UserAssociatedRepositories.invalidate_cache(installation: @org_installation)
      end
    end
  end

  test "cache can be invalidated when installed on a user", skip_enterprise: true do
    Flipper[:installation_user_associated_repo_ids_cache].enable(@installation.integration)

    # Ensure the cache is properly reset so we don't interfere with other tests
    # that stub GitHub.cache.
    with_cache_enabled(/installation:user:repo_ids/) do
      GitHub.cache.set(
        IntegrationInstallation::UserAssociatedRepositories.cache_key(@user, @installation),
        [@repo.id].to_json
      )

      IntegrationInstallation::UserAssociatedRepositories.invalidate_cache(installation: @installation)

      actual_value = IntegrationInstallation::UserAssociatedRepositories.with_cache(user: @user, installation: @installation) { [] }
      assert_equal [], actual_value
    end
  end

  test "invalidates organization installations by enqueing a a background job", skip_enterprise: true do
    Flipper[:installation_user_associated_repo_ids_cache].enable(@org_installation.integration)

    # Ensure the cache is properly reset so we don't interfere with other tests
    # that stub GitHub.cache.
    with_cache_enabled(/installation:user:repo_ids/) do
      GitHub.cache.set(
        IntegrationInstallation::UserAssociatedRepositories.cache_key(@user, @org_installation),
        [@repo.id, @org_repo.id].to_json
      )

      assert_enqueued_with job: IntegrationInstallationUserAssociatedRepositoriesCacheJob, args: [@org_installation] do
        IntegrationInstallation::UserAssociatedRepositories.invalidate_cache(installation: @org_installation)
      end
    end
  end

  test "handles unparseable cache values" do
    Flipper[:installation_user_associated_repo_ids_cache].enable(@installation.integration)

    # Ensure the cache is properly reset so we don't interfere with other tests
    # that stub GitHub.cache.
    with_cache_enabled(/installation:user:repo_ids/) do
      GitHub.cache.set(
        IntegrationInstallation::UserAssociatedRepositories.cache_key(@user, @installation),
        "{ unparseable json }"
      )

      actual_value = IntegrationInstallation::UserAssociatedRepositories.with_cache(user: @user, installation: @installation) { [] }
      assert_equal [], actual_value
    end
  end
end
