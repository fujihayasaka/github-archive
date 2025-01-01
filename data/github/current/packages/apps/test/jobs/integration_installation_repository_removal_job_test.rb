# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"
require "test_helpers/job_test_helper"

class IntegrationInstallationRepositoryRemovalJobTest < GitHub::TestCase
  include PermissionsHelper
  include JobTestHelper

  fixtures do
    @target = create(:credit_card_organization)
    @admin  = @target.admins.first

    @repo = create(:repository, :minimal, owner: @target)
  end

  context "installation on subset of repositores" do
    context "with repository permissions" do
      test "uninstalls when the last repository is deleted" do
        installation = make_integration_installation(target: @target, repository: @repo, permissions: { "metadata" => :read })

        perform_enqueued_jobs(only: [UninstallIntegrationInstallationJob]) do
          @repo.destroy
          IntegrationInstallationRepositoryRemovalJob.perform_now(installation)
        end

        assert_nil IntegrationInstallation.find_by(id: installation.id)
      end

      test "does not uninstall when there are still repos" do
        other_repo   = create(:repository, :minimal, owner: @target)
        installation = make_integration_installation(target: @target, repositories: [@repo, other_repo], permissions: { "metadata" => :read })

        assert_equal 2, installation.repositories.count

        @repo.destroy
        IntegrationInstallationRepositoryRemovalJob.perform_now(installation)

        refute_nil IntegrationInstallation.find_by(id: installation.id)
        assert_equal 1, installation.repositories.count
      end

      test "clears the installation cached permissions", skip_if_feature_enabled: :cached_fgp_permissions do
        other_repo   = create(:repository, :minimal, owner: @target)
        installation = make_integration_installation(target: @target, repositories: [@repo, other_repo], permissions: { "metadata" => :read })

        assert_equal({ "metadata" => :read }, installation.permissions)
        # explicitly cache the permissions, to verify they are cleared after the update
        installation.get_cached_permissions
        assert_equal({ "metadata" => "read" }, installation.permissions_cache)

        @repo.destroy!
        IntegrationInstallationRepositoryRemovalJob.perform_now(installation)

        assert_equal({ "metadata" => :read }, installation.permissions)
        assert_nil installation.permissions_cache
      end
    end

    context "with no permissions" do
      test "does not uninstall when the last repository is deleted" do
        installation = make_integration_installation(target: @target, repository: @repo)
        assert_predicate installation.permissions, :empty?

        @repo.destroy
        IntegrationInstallationRepositoryRemovalJob.perform_now(installation)

        refute_nil IntegrationInstallation.find_by(id: installation.id)
      end
    end

    context "with organization and repository permissions" do
      test "does not uninstall when the last repository is deleted" do
        installation = make_integration_installation(target: @target, repository: @repo, permissions: { "metadata" => :read, "members" => :read })

        @repo.destroy
        IntegrationInstallationRepositoryRemovalJob.perform_now(installation)

        refute_nil IntegrationInstallation.find_by(id: installation.id)
      end

      test "re-calculates the rate limit for the installation" do
        installation = make_integration_installation(target: @target, repository: @repo, permissions: { "metadata" => :read, "members" => :read })

        @repo.destroy
        assert_enqueued_jobs 1, only: UpdateIntegrationInstallationRateLimitJob, queue: "update_integration_installation_rate_limit" do
          IntegrationInstallationRepositoryRemovalJob.perform_now(installation)
        end

        assert_enqueued_with(job: UpdateIntegrationInstallationRateLimitJob, args: [installation.id], queue: "update_integration_installation_rate_limit")
      end
    end
  end

  context "installation installed on target" do
    context "with repository permissions" do
      test "does not uninstall when the last repository is deleted" do
        installation = make_integration_installation(target: @target, permissions: { "metadata" => :read })

        @repo.destroy
        IntegrationInstallationRepositoryRemovalJob.perform_now(installation)

        refute_nil IntegrationInstallation.find_by(id: installation.id)
      end
    end

    context "with no permissions" do
      test "does not uninstall when the last repository is deleted" do
        installation = make_integration_installation(target: @target)
        assert_predicate installation.permissions, :empty?

        @repo.destroy
        IntegrationInstallationRepositoryRemovalJob.perform_now(installation)

        refute_nil IntegrationInstallation.find_by(id: installation.id)
      end
    end

    context "with organization and repository permissions" do
      test "does not uninstall when the last repository is deleted" do
        installation = make_integration_installation(target: @target, permissions: { "metadata" => :read, "members" => :read })

        @repo.destroy
        IntegrationInstallationRepositoryRemovalJob.perform_now(installation)

        refute_nil IntegrationInstallation.find_by(id: installation.id)
      end

      test "re-calculates the rate limit for the installation" do
        installation = make_integration_installation(target: @target, permissions: { "metadata" => :read, "members" => :read })

        @repo.destroy
        assert_enqueued_jobs 1, only: UpdateIntegrationInstallationRateLimitJob, queue: "update_integration_installation_rate_limit" do
          IntegrationInstallationRepositoryRemovalJob.perform_now(installation)
        end

        assert_enqueued_with(job: UpdateIntegrationInstallationRateLimitJob, args: [installation.id], queue: "update_integration_installation_rate_limit")
      end
    end
  end

  context "when a repository ID is supplied" do
    test "removes associated permission records" do
      other_repo = create(:repository, :minimal, owner: @target)
      installation = make_integration_installation(
        target: @target,
        repositories: [@repo, other_repo],
        permissions: { "metadata" => :read },
      )

      @repo.destroy
      IntegrationInstallationRepositoryRemovalJob.perform_now(installation, @repo.id)

      refute_actor_and_subject_granted_in_abilities_table(
        actor: installation,
        subject: @repo.resources.metadata,
        action: :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repo.resources.metadata,
        action: :read,
      )
    end
  end

  test "when target is deleted" do
    installation = make_integration_installation(target: @target, repository: @repo, permissions: { "metadata" => :read })

    perform_enqueued_jobs(only: [UninstallIntegrationInstallationJob]) do
      @repo.destroy; @target.delete; installation.reload
      IntegrationInstallationRepositoryRemovalJob.perform_now(installation)
    end

    assert_nil IntegrationInstallation.find_by(id: installation.id)
  end

  test "retry conditions" do
    installation = make_integration_installation(
      target: @target,
      repositories: [@repo],
      permissions: { "metadata" => :read },
    )

    assert_retry_on_dirty_exit job: IntegrationInstallationRepositoryRemovalJob, args: [installation]
  end
end
