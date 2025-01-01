# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dogstats_test_helpers"
require "test_helpers/permissions_helper"

class ScopedIntegrationInstallation::CreatorTest < GitHub::TestCase
  include DogstatsTestHelpers
  include PermissionsHelper
  include GitHub::LoggerHelper

  fixtures do
    @user                = create(:user)
    @repository          = create(:repository, :minimal, owner: @user)
    @parent_installation = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "contents" => :write })
  end

  context ".perform" do
    context "when scoping to a subset of repositories" do
      test "returns a scoped installation for a valid installation" do
        result = ScopedIntegrationInstallation::Creator.perform(@parent_installation, repositories: [@repository], entry_point: :test_case)

        assert_predicate result, :success?
        refute_predicate result, :found_cached?
        assert result.installation

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   result.installation,
          subject: @repository.resources.metadata,
          action:  :read,
        )

        refute_actor_and_subject_granted_in_permissions_table(
          actor:   result.installation,
          subject: @repository.resources.issues,
          action:  :read,
        )
      end

      test "writes permissions as JSON when the feature flag is enabled" do
        GitHub.flipper[:scoped_installation_with_authorization_details].enable(@parent_installation)

        result = ScopedIntegrationInstallation::Creator.perform(@parent_installation, repositories: [@repository], entry_point: :test_case)
        assert_predicate result, :success?

        assert_same_hash({
          "version" => 1,
          "selections"  => { "repository" => "subset" },
          "subject_ids" => { "repository" => [@repository.id] },
          "subject_types_and_actions" => {
            "repository" => { "metadata" => 0, "contents" => 1 }
          }
        }, result.installation.authorization_details)
      end

      test "does not write permissions as JSON when the feature flag is disabled" do
        GitHub.flipper[:scoped_installation_with_authorization_details].disable

        result = ScopedIntegrationInstallation::Creator.perform(@parent_installation, repositories: [@repository], entry_point: :test_case)
        assert_predicate result, :success?

        assert_nil result.installation.authorization_details
      end
    end

    context "when scoping to :all repositories" do
      test "returns a scoped installation for a valid installation" do
        parent_installation_all_repos = make_integration_installation(target: @user, permissions: { "metadata" => :read })
        result = ScopedIntegrationInstallation::Creator.perform(parent_installation_all_repos, repositories: :all, entry_point: :test_case)

        assert_predicate result, :success?
        assert result.installation

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   result.installation,
          subject: @user.repository_resources.metadata,
          action:  :read,
        )

        refute_actor_and_subject_granted_in_permissions_table(
          actor:   result.installation,
          subject: @user.repository_resources.issues,
          action:  :read,
        )
      end

      test "writes permissions as JSON when the feature flag is enabled" do
        parent_installation_all_repos = make_integration_installation(target: @user, permissions: { "metadata" => :read })
        GitHub.flipper[:scoped_installation_with_authorization_details].enable(parent_installation_all_repos)

        result = ScopedIntegrationInstallation::Creator.perform(parent_installation_all_repos, repositories: :all, entry_point: :test_case)
        assert_predicate result, :success?

        assert_same_hash({
          "version" => 1,
          "selections" => { "repository" => "parent" },
          "subject_types_and_actions" => {
            "repository" => { "metadata" => 0 }
          }
        }, result.installation.authorization_details)
      end

      test "does not write permissions as JSON when the feature flag is disabled" do
        parent_installation_all_repos = make_integration_installation(target: @user, permissions: { "metadata" => :read })
        GitHub.flipper[:scoped_installation_with_authorization_details].disable

        result = ScopedIntegrationInstallation::Creator.perform(parent_installation_all_repos, repositories: :all, entry_point: :test_case)
        assert_predicate result, :success?

        assert_nil result.installation.authorization_details
      end
    end

    context "when scoping to :selected repositories" do
      test "returns a scoped installation for a valid installation" do
        result = ScopedIntegrationInstallation::Creator.perform(@parent_installation, repositories: :selected, entry_point: :test_case)

        assert_predicate result, :success?
        assert result.installation

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   result.installation,
          subject: @repository.resources.metadata,
          action:  :read,
        )
      end

      test "writes permissions as JSON when the feature flag is enabled" do
        GitHub.flipper[:scoped_installation_with_authorization_details].enable(@parent_installation)

        result = ScopedIntegrationInstallation::Creator.perform(@parent_installation, repositories: :selected, entry_point: :test_case)
        assert_predicate result, :success?

        assert_same_hash({
          "version" => 1,
          "selections" => { "repository" => "parent" },
          "subject_types_and_actions" => {
            "repository" => { "metadata" => 0, "contents" => 1 }
          }
        }, result.installation.authorization_details)
      end

      test "does not write permissions as JSON when the feature flag is disabled" do
        GitHub.flipper[:scoped_installation_with_authorization_details].disable

        result = ScopedIntegrationInstallation::Creator.perform(@parent_installation, repositories: :selected, entry_point: :test_case)
        assert_predicate result, :success?

        assert_nil result.installation.authorization_details
      end
    end

    test "grants access to all of the specified resources" do
      owner = @repository.owner
      repo2 = create(:repository, :minimal, owner: owner)

      parent_installation = make_integration_installation(target: owner, permissions: { "metadata" => :read })
      result              = ScopedIntegrationInstallation::Creator.perform(parent_installation, repositories: owner.repositories, entry_point: :test_case)

      assert_predicate result, :success?

      installation = result.installation

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.metadata,
        action: :read,
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: repo2.resources.metadata,
        action: :read,
      )
    end

    test "grants limited permissions" do
      owner = @repository.owner
      repo2 = create(:repository, :minimal, owner: owner)

      parent_installation = make_integration_installation(target: owner, permissions: { "metadata" => :read, "issues" => :read })
      result              = ScopedIntegrationInstallation::Creator.perform(parent_installation, repositories: owner.repositories, permissions: { "metadata" => :read }, entry_point: :test_case)

      assert_predicate result, :success?

      installation = result.installation

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.metadata,
        action: :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.issues,
        action: :read,
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: repo2.resources.metadata,
        action: :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: repo2.resources.issues,
        action: :read,
      )
    end

    test "grants organization permissions" do
      org = create(:organization)

      parent_installation = make_integration_installation(target: org, permissions: { "members" => :write })
      result              = ScopedIntegrationInstallation::Creator.perform(parent_installation, repositories: org.repositories, permissions: { "members" => :read }, entry_point: :test_case)

      assert_predicate result, :success?

      installation = result.installation

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: org.resources.members,
        action: :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: org.resources.members,
        action: :write,
      )
    end

    test "test log_data written as expected" do
      log_data = {}
      owner = @repository.owner
      parent_installation = make_integration_installation(
        repository: @repository,
        permissions: { "metadata" => :read, "pull_requests" => :read, "issues" => :write },
      )

      ScopedIntegrationInstallation::Creator.stub_const(:MAX_REPOSITORY_IDS, 0) do

        result = ScopedIntegrationInstallation::Creator.perform(
          parent_installation,
          repositories: [@repository],
          permissions: { "issues" => :read },
          log_data: log_data,
          entry_point: :test_case,
        )

        assert_equal false, log_data[:installations_repositories_all]
        assert_equal 1, log_data[:repositories_count]
        assert_equal GitHub.flipper[:installations_max_repository_ids].enabled?, log_data[:circuit_breaker_enabled]
        assert_equal true, log_data[:installations_repositories_subset]

      end

    end

    context "max permission rows limiter" do
      test "does not log or block if the toggle is disabled" do
        repo = create(:repository, :minimal, owner: @user)

        parent_installation = make_integration_installation(
          repositories: [@repository, repo],
          permissions: { "metadata" => :read, "pull_requests" => :read, "issues" => :write },
        )

        GitHub.flipper[:installations_max_permission_rows_toggle].disable

        unexpected_log = {
          "Body" => "Detected an App creating a scoped installation access token due to exceeding MAX_PERMISSION_ROWS",
          "gh.integration.id" => parent_installation.integration.id,
          "gh.installation.repositories_count" => 2,
          "gh.installation.repository_limit" => 1,
          "gh.installation.permission_rows_count" => 6,
          "gh.installation.target.id" => @user.id,
          "gh.installation.repos_subset" => true,
          "gh.installation.max_permission_rows_flipper_enabled" => false
        }

        refute_logged(**unexpected_log) do
          ScopedIntegrationInstallation::Creator.stub_const(:MAX_PERMISSION_ROWS, 3) do
            result = ScopedIntegrationInstallation::Creator.perform(
              parent_installation,
              repositories: [@repository, repo],
              permissions: { "metadata" => :read, "pull_requests" => :read, "issues" => :read },
              entry_point: :test_case,
            )

            assert_predicate result, :success?
          end
        end
      end

      test "logs but does not block if the toggle is enabled, but the FF is disabled" do
        repo = create(:repository, :minimal, owner: @user)

        parent_installation = make_integration_installation(
          repositories: [@repository, repo],
          permissions: { "metadata" => :read, "pull_requests" => :read, "issues" => :write },
        )

        GitHub.flipper[:installations_max_permission_rows_toggle].enable
        GitHub.flipper[:installations_max_permission_rows].disable

        expected_log = {
          "Body" => "Detected an App creating a scoped installation access token due to exceeding MAX_PERMISSION_ROWS",
          "gh.integration.id" => parent_installation.integration.id,
          "gh.installation.repositories_count" => 2,
          "gh.installation.repository_limit" => 1,
          "gh.installation.permission_rows_count" => 6,
          "gh.installation.target.id" => @user.id,
          "gh.installation.repos_subset" => true,
          "gh.installation.max_permission_rows_flipper_enabled" => false
        }

        assert_logged(**expected_log) do
          ScopedIntegrationInstallation::Creator.stub_const(:MAX_PERMISSION_ROWS, 3) do
            result = ScopedIntegrationInstallation::Creator.perform(
              parent_installation,
              repositories: [@repository, repo],
              permissions: { "metadata" => :read, "pull_requests" => :read, "issues" => :read },
              entry_point: :test_case,
            )

            assert_predicate result, :success?
          end
        end
      end

      test "logs and blocks too many permission rows to be written" do
        repo = create(:repository, :minimal, owner: @user)

        parent_installation = make_integration_installation(
          repositories: [@repository, repo],
          permissions: { "metadata" => :read, "pull_requests" => :read, "issues" => :write },
        )

        GitHub.flipper[:installations_max_permission_rows_toggle].enable(parent_installation.integration)
        GitHub.flipper[:installations_max_permission_rows].enable(parent_installation.integration)

        expected_log = {
          "Body" => "Detected an App creating a scoped installation access token due to exceeding MAX_PERMISSION_ROWS",
          "gh.integration.id" => parent_installation.integration.id,
          "gh.installation.repositories_count" => 2,
          "gh.installation.repository_limit" => 1,
          "gh.installation.permission_rows_count" => 6,
          "gh.installation.target.id" => @user.id,
          "gh.installation.repos_subset" => true,
          "gh.installation.max_permission_rows_flipper_enabled" => true
        }

        assert_logged(**expected_log) do
          ScopedIntegrationInstallation::Creator.stub_const(:MAX_PERMISSION_ROWS, 3) do
            result = ScopedIntegrationInstallation::Creator.perform(
              parent_installation,
              repositories: [@repository, repo],
              permissions: { "metadata" => :read, "pull_requests" => :read, "issues" => :read },
              entry_point: :test_case,
            )

            expected_msg = "Too many repositories for installation. Please reduce the number of repositories this application has access to to 1 repositories or fewer, or use the `repositories` or `repository_ids` request attributes to list up to 1 repositories in the request. You can also reduce the number of permissions requested, or set the application to be installed on all repositories in the organization."

            assert_predicate result, :failed?
            assert_equal expected_msg, result.error
          end
        end
      end
    end

    test "applies mandatory permissions if the parent installation have them" do
      owner = @repository.owner
      parent_installation = make_integration_installation(
        repository: @repository,
        permissions: { "metadata" => :read, "pull_requests" => :read, "issues" => :write },
      )

      result = ScopedIntegrationInstallation::Creator.perform(
        parent_installation,
        repositories: [@repository],
        permissions: { "issues" => :read },
        entry_point: :test_case,
      )

      assert_predicate result, :success?

      installation = result.installation

      # This is the main assertion on this test
      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.metadata,
        action: :read,
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.issues,
        action: :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.pull_requests,
        action: :read,
      )
    end

    test "does not apply mandatory permissions if the parent installation is missing them" do
      GitHub.flipper[:cached_fgp_permissions].disable

      owner = @repository.owner
      parent_installation = make_integration_installation(
        repository: @repository,
        permissions: { "pull_requests" => :read, "issues" => :write },
      )

      # We have to go ahead and delete this permission to simulate
      # the state of an installation that was created before we
      # started applying mandatory permissions
      Permission.where(
        actor_id: parent_installation.id,
        actor_type: parent_installation.class.name,
        subject_type: @repository.resources.metadata.ability_type,
      ).destroy_all

      refute_actor_and_subject_granted_in_permissions_table(
        actor: parent_installation,
        subject: @repository.resources.metadata,
        action: :read,
      )

      # reset the parent_installation cache
      parent_installation.clear_cached_permissions

      result = ScopedIntegrationInstallation::Creator.perform(
        parent_installation,
        repositories: [@repository],
        permissions: { "issues" => :read },
        entry_point: :test_case,
      )

      assert_predicate result, :success?
      installation = result.installation

      # This is the main assertion on this test
      refute_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.metadata,
        action: :read,
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.issues,
        action: :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.pull_requests,
        action: :read,
      )
    end

    test "sets the expires_at column by default" do
      Timecop.freeze do
        expiry = ScopedIntegrationInstallation::Creators::Base::EXPIRATION_WINDOW.from_now
        result = ScopedIntegrationInstallation::Creator.perform(@parent_installation, repositories: [@repository], entry_point: :test_case)

        assert_predicate result, :success?
        scoped_installation = result.installation

        # We need to compare using `.to_i` because of the following:
        #
        # Minitest::Assertion: No visible difference in the ActiveSupport::TimeWithZone#inspect output.
        # You should look at the implementation of #== on ActiveSupport::TimeWithZone or its members.
        assert_equal expiry.to_i, scoped_installation.expires_at.to_i

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   scoped_installation,
          subject: @repository.resources.metadata,
          action:  :read,
        )

        permission_records = Permission.where(actor: scoped_installation)
        assert_equal 2, permission_records.count

        permission = permission_records.first
        assert_equal expiry.to_i, permission.expires_at.to_i
      end
    end

    test "can opt out of setting the expires_at column" do
      result = ScopedIntegrationInstallation::Creator.perform(@parent_installation, repositories: [@repository], expires: false, entry_point: :test_case)

      assert_predicate result, :success?
      scoped_installation = result.installation

      assert_nil scoped_installation.expires_at

      assert_actor_and_subject_granted_in_permissions_table(
        actor:   scoped_installation,
        subject: @repository.resources.metadata,
        action:  :read,
      )

      permission_records = Permission.where(actor: scoped_installation)
      assert_equal 2, permission_records.count

      permission = permission_records.first
      assert_nil permission.expires_at
    end

    test "returns a failure when the permissions check returns a failure" do
      failed_check_result = ScopedIntegrationInstallation::Permissions::Result.new(false, reason: :missing_parent)
      ScopedIntegrationInstallation::Permissions.any_instance.stubs(:check).returns(failed_check_result)

      result = ScopedIntegrationInstallation::Creator.perform(@parent_installation, repositories: [@repository], entry_point: :test_case)

      assert_predicate result, :failed?
      assert_nil result.installation
    end

    context "when the scoped installation can't be created" do
      context "with :write_permissions_with_insert_all enabled" do
        test "returns a failed result and reports to Failbot" do
          installation = IntegrationInstallation.new(updated_at: Time.current)

          creator = ScopedIntegrationInstallation::Creator.new(
            installation, repositories: [@repository], permissions: { "metadata" => "read" }, entry_point: :test_case
          )

          Failbot.expects(:report).with(instance_of(ActiveRecord::RecordInvalid))
          creator.expects(:validate_permissions!).returns(nil)

          result = creator.perform

          assert_predicate result, :failed?
          assert_nil result.installation

          assert_equal "Validation failed: Integration installation can't be blank", result.error
        end
      end
    end

    test "does not allow internal apps to elevate scoped installations permissions" do
      make_trusted_oauth_apps_owner

      actions = create(:launch_integration, default_permissions: { "contents" => :read })

      parent_installation = make_integration_installation(
        integration: actions,
        repository: @repository,
        permissions: { "contents" => :read },
      )

      result = ScopedIntegrationInstallation::Creator.perform(
        parent_installation, repositories: [@repository], permissions: { "contents" => :write }, entry_point: :test_case
      )
      refute_predicate result, :success?
      expected_error = "The level of access for permissions requested are not granted to this installation."
      assert_equal expected_error, result.error
    end

    test "returns a successful result for a permissionless installation token" do
      make_trusted_oauth_apps_owner
      installation = make_integration_installation(integration: create(:dependabot_integration), target: @repository.owner)

      assert_predicate ScopedIntegrationInstallation::Creator.perform(installation, permissions: :none, entry_point: :test_case), :success?
    end
  end

  context ".perform_with_cache" do
    test "uses the cached installation if one is available" do
      parent_installation = make_integration_installation(
        repository: @repository, permissions: { "metadata" => :read, "contents" => :write },
      )
      # Warm up the permissions-cache to avoid flakes on racy cache-evictions when touching the parent-installation timestamp.
      assert_predicate parent_installation.get_cached_permissions, :present?

      with_cache_enabled do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        result = ScopedIntegrationInstallation::Creator.perform_with_cache(parent_installation, repositories: [@repository], entry_point: :test_case)
        assert_predicate result, :success?

        installation_id = result.installation.id

        assert_no_difference "ScopedIntegrationInstallation.count" do
          result = ScopedIntegrationInstallation::Creator.perform_with_cache(parent_installation, repositories: [@repository], entry_point: :test_case)

          assert_predicate result, :success?
          assert_predicate result, :found_cached?
        end

        assert_equal installation_id, result.installation.id
        stats = GitHub.dogstats.distributions("scoped_integration_installation.perform_with_cache.remaining_expiry_in_hours")
        assert_equal 1, stats.count
      end
    end

    test "does not use the cache if the installation is expired" do
      with_cache_enabled do
        result = ScopedIntegrationInstallation::Creator.perform_with_cache(@parent_installation, repositories: [@repository], entry_point: :test_case)
        assert_predicate result, :success?

        installation = result.installation
        installation_id = installation.id
        installation.update_attribute(:expires_at, 2.days.ago)
        assert_predicate installation.reload, :expired?

        assert_difference "ScopedIntegrationInstallation.count", 1 do
          result = ScopedIntegrationInstallation::Creator.perform_with_cache(@parent_installation, repositories: [@repository], entry_point: :test_case)

          assert_predicate result, :success?
          refute_predicate result, :found_cached?
        end

        refute_equal installation_id, result.installation.id
      end
    end

    test "asynchronously bumps the installation (and permissions) expiration" do
      with_cache_enabled do
        parent_installation = make_integration_installation(
          repository: @repository, permissions: { "metadata" => :read, "contents" => :write },
        )
        # Warm up the permissions-cache to avoid flakes on racy cache-evictions when touching the parent-installation timestamp.
        assert_predicate parent_installation.get_cached_permissions, :present?

        result = ScopedIntegrationInstallation::Creator.perform_with_cache(parent_installation, repositories: [@repository], entry_point: :test_case)
        assert_predicate result, :success?

        installation = result.installation
        installation_id = installation.id
        installation.update_attribute(:expires_at, 2.hours.from_now)
        refute_predicate installation.reload, :expired?

        Timecop.freeze do
          expected_job = ScopedIntegrationInstallableExpirationExtensionJob
          assert_performed_with(job: expected_job, args: [installation, 25.hours.from_now, { entry_point: :test_case }]) do
            assert_no_difference "ScopedIntegrationInstallation.count" do
              result = ScopedIntegrationInstallation::Creator.perform_with_cache(parent_installation, repositories: [@repository], entry_point: :test_case)
              assert_predicate result, :success?
            end

            assert_equal 25.hours.from_now.to_i, installation.reload.expires_at.to_i
            assert_equal installation_id, result.installation.id
          end
        end
      end
    end

    test "does not bump the installation (and permissions) expiration if expiration is not with threshold" do
      with_cache_enabled do
        parent_installation = make_integration_installation(
          repository: @repository, permissions: { "metadata" => :read, "contents" => :write },
        )
        # Warm up the permissions-cache to avoid flakes on racy cache-evictions when touching the parent-installation timestamp.
        assert_predicate parent_installation.get_cached_permissions, :present?

        result = ScopedIntegrationInstallation::Creator.perform_with_cache(parent_installation, repositories: [@repository], entry_point: :test_case)
        assert_predicate result, :success?

        installation = result.installation
        installation_id = installation.id

        Timecop.freeze do
          installation.update_attribute(:expires_at, 6.hours.from_now)
          refute_predicate installation.reload, :expired?
          assert_no_performed_jobs(only: ScopedIntegrationInstallableExpirationExtensionJob) do
            assert_no_difference "ScopedIntegrationInstallation.count" do
              result = ScopedIntegrationInstallation::Creator.perform_with_cache(parent_installation, repositories: [@repository], entry_point: :test_case)
              assert_predicate result, :success?
            end
          end

          assert_equal 6.hours.from_now.to_i, installation.reload.expires_at.to_i, "Expected expires_at not to be bumped"
          assert_equal installation_id, result.installation.id
        end
      end
    end

    test "creates a new record if the cached record was destroyed" do
      with_cache_enabled do
        result = ScopedIntegrationInstallation::Creator.perform_with_cache(@parent_installation, repositories: [@repository], entry_point: :test_case)
        assert_predicate result, :success?
        cached_installation_id = result.installation.id

        result.installation.destroy

        assert_difference "ScopedIntegrationInstallation.count", 1 do
          result = ScopedIntegrationInstallation::Creator.perform_with_cache(@parent_installation, repositories: [@repository], entry_point: :test_case)
          assert_predicate result, :success?
        end

        refute_equal cached_installation_id, result.installation.id
      end
    end

    test "does not use the cached scoped installation if repositories requested are no longer available" do
      with_cache_enabled do
        repository2 = create(:repository, :minimal, owner: @user)

        @parent_installation.edit(repositories: [@repository, repository2], editor: @user, entry_point: :test_case)
        @parent_installation.reload

        result = ScopedIntegrationInstallation::Creator.perform_with_cache(@parent_installation, repositories: [@repository, repository2], entry_point: :test_case)
        assert_predicate result, :success?

        @parent_installation.edit(repositories: [@repository], editor: @user, entry_point: :test_case)
        @parent_installation.reload

        assert_no_difference "ScopedIntegrationInstallation.count" do
          result = ScopedIntegrationInstallation::Creator.perform_with_cache(@parent_installation, repositories: [@repository, repository2], entry_point: :test_case)
          assert_predicate result, :failed?
        end
      end
    end

    test "does not use cached installation if the permissions requested are no longer available" do
      with_cache_enabled do
        result = ScopedIntegrationInstallation::Creator.perform_with_cache(@parent_installation, repositories: [@repository], permissions: { "metadata" => :read, "contents" => :write }, entry_point: :test_case)
        assert_predicate result, :success?

        integration = @parent_installation.integration

        integration.update(default_permissions: { "metadata" => :read })
        integration.reload

        latest_version = integration.latest_version
        @parent_installation.update_version(editor: @user, version: latest_version, entry_point: :test_case)

        assert_no_difference "ScopedIntegrationInstallation.count" do
          result = ScopedIntegrationInstallation::Creator.perform_with_cache(@parent_installation, repositories: [@repository], permissions: { "metadata" => :read, "contents" => :write }, entry_point: :test_case)
          assert_predicate result, :failed?
        end
      end
    end

    test "does not use cached scoped installation if parent installation was updated" do
      Timecop.freeze do
        with_cache_enabled do
          # Create a scoped installation
          permissions = { "metadata" => :read, "contents" => :write }
          repositories = [@repository]
          previous_result = ScopedIntegrationInstallation::Creator.perform_with_cache(@parent_installation, repositories: repositories, permissions: permissions, entry_point: :test_case)
          previous_scoped_installation_id = previous_result.installation.id

          Timecop.travel(1.second) do
            # Add repo to parent installation to simulate an update that would bust the cache.
            new_repository = create(:repository, owner: @user)
            IntegrationInstallation::Editor.perform(
              @parent_installation,
              repositories: [@repository, new_repository],
              editor: @user,
              entry_point: :test_case,
            )

            latest_result = T.let(nil, T.nilable(ScopedIntegrationInstallation::Result))

            assert_difference "ScopedIntegrationInstallation.count", 1 do
              # Create a new scoped installation
              latest_result = ScopedIntegrationInstallation::Creator.perform_with_cache(@parent_installation, repositories: repositories, permissions: permissions, entry_point: :test_case)
              assert_predicate latest_result, :success?
            end

            latest_scoped_installation_id = latest_result&.installation&.id

            refute_equal previous_scoped_installation_id, latest_scoped_installation_id
          end
        end
      end
    end
  end

  context "packages" do
    test "does not grant organization_packages by default for internal apps with the manage_packages_permissions capability" do
      integration = create_internal_app_with_capabilities(
        permissions: { "contents" => :write, "metadata" => :read, "packages" => :write },
        capabilities: { manage_packages_permissions: true },
      )

      parent_installation = make_integration_installation(integration: integration, target: @user)
      refute parent_installation.permissions.key?("organization_packages")

      result = ScopedIntegrationInstallation::Creator.perform(parent_installation, repositories: [@repository], permissions: { "metadata" => :read, "packages" => :write }, entry_point: :test_case)

      assert_predicate result, :success?
      assert scoped_installation = result.installation

      subject = IntegrationInstallation::AbilityCollection.new(parent: @user, name: "organization_packages", ability_type_prefix: "Organization")
      refute_actor_and_subject_granted_in_permissions_table(actor: scoped_installation, subject: subject, action: :write)
    end
  end

  test "deletes the scoped installation if permissions fail to be written" do
    Permission.stubs(:insert_all!).raises(ActiveRecord::RecordNotUnique)
    Failbot.expects(:report).with(instance_of(ActiveRecord::RecordNotUnique))

    assert_no_difference "ScopedIntegrationInstallation.count" do
      assert_no_difference "Permission.count" do
        result = ScopedIntegrationInstallation::Creator.perform(@parent_installation, repositories: [@repository], entry_point: :test_case)
        assert_predicate result, :failed?
      end
    end
  end

  context "instrumentation" do
    test "creation" do
      events = subscribe "scoped_integration_installation.create"

      installation = make_integration_installation(
        target: @user,
        permissions: {
          "metadata" => :read,
          "contents" => :write,
          "issues" => :read,
        },
      )

      repo = create(:repository, :minimal, owner: @user)
      created_at = 2.hours.ago.beginning_of_hour
      result = Timecop.freeze(created_at) do
        ScopedIntegrationInstallation::Creator.perform(
          installation,
          repositories: [repo],
          permissions: { "metadata" => :read, "issues" => :read },
          entry_point: :test_case,
        )
      end

      assert_predicate result, :success?
      scoped_installation = result.installation
      integration = installation.integration

      expected_payload = {}.tap do |payload|
        payload[:scoped_integration_installation]    = scoped_installation.name
        payload[:scoped_integration_installation_id] = scoped_installation.id
        payload[:parent_integration_installation_id] = installation.id
        payload[:integration]                        = integration.name
        payload[:integration_id]                     = integration.id
        payload[:repository_selection]               = "selected"
        payload[:repository_ids]                     = [repo.id]
        payload[:user]                               = @user.to_s
        payload[:user_id]                            = @user.id
        payload[:permissions]                        = { "metadata" => :read, "issues" => :read }
        payload[:created_at]                         = created_at
      end

      assert event = events.pop, "expected an instrument creation event"
      assert_equal "scoped_integration_installation.create", event.name
      assert_same_hash expected_payload, event.payload
    end

    test "does not instrument the Actions app" do
      events = subscribe "scoped_integration_installation.create"

      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      integration = create(:launch_integration)
      installation = make_integration_installation(target: @user, integration: integration, permissions: {
        "metadata" => :read,
        "contents" => :write,
        "issues" => :read,
      })

      repo = create(:repository, :minimal, owner: @user)
      result = ScopedIntegrationInstallation::Creator.perform(
        installation,
        repositories: [repo],
        permissions: { "metadata" => :read, "issues" => :read },
        entry_point: :test_case,
      )

      assert_predicate result, :success?
      assert_equal integration, result.installation.integration

      assert_equal 0, events.size
    end

    test "does instrument proper stats" do
      installation = make_integration_installation(
        target: @user,
        permissions: {
          "metadata" => :read,
          "contents" => :write,
          "issues" => :read,
        },
      )

      repo = create(:repository, :minimal, owner: @user)
      result = ScopedIntegrationInstallation::Creator.perform(
        installation,
        repositories: [repo],
        permissions: { "metadata" => :read, "issues" => :read },
      )

      assert_predicate result, :success?

      expected_tags = ["result:success"]
      assert_dogstats_increment("scoped_integration_installation.create", tags: expected_tags)
    end
  end
end
