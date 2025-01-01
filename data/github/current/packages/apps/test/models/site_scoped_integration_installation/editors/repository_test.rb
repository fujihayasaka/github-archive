# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class SiteScopedIntegrationInstallation::Editors::RepositoryTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @user        = create(:user)
    @other_user  = create(:user)
    @repository  = create(:repository, :minimal, owner: @user)
    @other_repo  = create(:repository, :minimal, owner: @user)
    @other_user_repo = create(:repository, :minimal, owner: @other_user)
    GitHub.flipper[:disabled_global_apps].disable
    @integration = create_unlimited_global_integration
  end

  context ".grant" do
    test "grants permissions on requested repositories" do
      installation = SiteScopedIntegrationInstallation::Creator.perform(
        @integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation
      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation, repositories: [@other_repo], entry_point: :test_case
      )
      assert_predicate result, :success?

      assert_includes installation.repositories, @other_repo
    end

    test "sets the expiration to match the installation" do
      installation = SiteScopedIntegrationInstallation::Creator.perform(
        @integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      refute_nil installation.expires_at

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation, repositories: [@other_repo], entry_point: :test_case
      )
      assert_predicate result, :success?

      permission_record = Permission.where(
        actor_id: installation.ability_id,
        actor_type: installation.ability_type,
        subject_id: @other_repo.ability_id,
        subject_type: "Repository/metadata"
      ).first

      refute_nil permission_record.expires_at
      assert_equal permission_record.expires_at.to_i, installation.expires_at.to_i
    end

    test "raises an exception if permissions can't be written" do
      installation = SiteScopedIntegrationInstallation::Creator.perform(
        @integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      ::Permissions::Service.stubs(:grant_permissions!).raises(RuntimeError)

      assert_raises(RuntimeError) do
        SiteScopedIntegrationInstallation::Editors::Repository.grant(
          installation, repositories: [@other_repo], entry_point: :test_case
        )
      end
    end

    test "returns success if already installed on all repositories" do
      installation = SiteScopedIntegrationInstallation::Creator.perform(
        @integration, @user, repositories: :all, entry_point: :test_case
      ).installation

      assert_predicate installation, :installed_on_all_repositories?

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation, repositories: [@repository], entry_point: :test_case
      )

      assert_predicate result, :success?
    end

    test "returns a failure for different target without cross-target capability" do
      @integration = create_unlimited_global_integration(
        capabilities: { integration_installation_multiple_target_permissions: false },
      )
      installation = SiteScopedIntegrationInstallation::Creator.perform(
        @integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation, repositories: [@other_user_repo], entry_point: :test_case
      )

      assert_predicate result, :failed?

      assert_equal :multiple_target_permissions, result.reason
    end

    test "cross-target repository grants" do
      @integration = create_unlimited_global_integration(
        capabilities: { integration_installation_multiple_target_permissions: true },
      )

      installation = SiteScopedIntegrationInstallation::Creator.perform(
        @integration, @user, repositories: :all, entry_point: :test_case
      ).installation

      assert_predicate installation, :installed_on_all_repositories?

      org = create(:organization)
      org_repo = create(:repository, :minimal, owner: org)

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation, repositories: [org_repo], entry_point: :test_case
      )

      assert_predicate result, :success?

      assert org_repo.resources.contents.readable_by?(installation)
      refute org_repo.resources.contents.writable_by?(installation)
    end

    test "instruments success" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      installation = SiteScopedIntegrationInstallation::Creator.perform(
        @integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation, repositories: [@other_repo], entry_point: :test_case
      )
      expected_key = "site_scoped_integration_installation.editors.repository.update"
      assert_equal 1, GitHub.dogstats.increments(expected_key, tags: ["result:success"]).count
    end

    test "instruments failed" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      installation = SiteScopedIntegrationInstallation::Creator.perform(
        @integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      elevated_permissions = { "pull_requests" => :write }
      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation,
        repositories: [@other_repo],
        entry_point: :test_case,
        repository_permissions: elevated_permissions,
      )

      expected_key = "site_scoped_integration_installation.editors.repository.update"
      assert_equal 1, GitHub.dogstats.increments(expected_key, tags: ["result:failed"]).count
    end

    test "accepts repository_permissions" do
      integration = create_unlimited_global_integration(
        permissions: { "pull_requests" => :write },
      )

      installation = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation,
        repositories: [@other_repo],
        entry_point: :test_case,
        repository_permissions: { "pull_requests" => :read },
      )

      assert_predicate result, :success?
      assert_includes installation.repositories, @other_repo

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation, subject: @repository.resources.pull_requests, action: :write
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation, subject: @other_repo.resources.pull_requests, action: :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: installation, subject: @other_repo.resources.pull_requests, action: :write,
      )
    end

    test "new permissions cannot be added" do
      integration = create_unlimited_global_integration(
        permissions: { "pull_requests" => :read },
      )

      installation = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation, repositories: [@other_repo], repository_permissions: {
          "issues" => :write,
        },
        entry_point: :test_case,
      )

      refute_predicate result, :success?
      assert_equal :invalid_permissions, result.reason
    end

    test "permissions cannnot be upgraded without upgrade_default_permissions capability" do
      integration = create_unlimited_global_integration(
        permissions: { "pull_requests" => :read },
      )

      installation = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation,
        repositories: [@other_repo],
        repository_permissions: { "pull_requests" => :write },
        entry_point: :test_case,
      )

      refute_predicate result, :success?
      assert_equal :invalid_permissions, result.reason
    end

    # TODO: This is the current behavior from the legacy Editor code, but is this **really** the desired behavior?
    # Note that the App permissions themselves don't need to change in order to update the SSSI permissions.
    # This sounds like a permissions escalation to me.
    test "permissions can be upgraded if with the upgrade_default_permissions capability" do
      integration = create_unlimited_global_integration(
        permissions: {
          "pull_requests" => :read,
        },
        capabilities: {
          upgrade_default_permissions: true,
        },
      )

      installation = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation,
        repositories: [@other_repo],
        repository_permissions: { "pull_requests" => :write },
        entry_point: :test_case
      )

      assert_predicate result, :success?
    end

    test "does not write JSON details if the installation doesn't have details previously written", feature_disabled: :write_authorization_details_for_site_scoped_integration_installations do
      integration = create_unlimited_global_integration(
        permissions: { "pull_requests" => :write },
      )

      installation = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      assert_nil installation.authorization_details

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation,
        repositories: [@other_repo],
        entry_point: :test_case,
        repository_permissions: { "pull_requests" => :read },
      )

      installation.reload
      assert_predicate result, :success?

      assert_nil installation.authorization_details
    end

    test "adds repositories to the JSON details if the hash exists", feature_enabled: :write_authorization_details_for_site_scoped_integration_installations  do
      integration = create_unlimited_global_integration(
        permissions: { "pull_requests" => :write },
      )

      installation = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      expected = {
        "version" => 1,
        "selections" => {
          "repository" => "subset"
        },
        "subject_ids" => {
          "repository" => [@repository.id]
        },
        "subject_types_and_actions" => {
          "repository" => {
            "metadata" => 0, "pull_requests" => 1
          }
        }
      }

      assert_same_hash expected, installation.authorization_details

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation,
        repositories: [@other_repo],
        entry_point: :test_case,
        repository_permissions: { "pull_requests" => :read },
      )

      installation.reload
      assert_predicate result, :success?

      expected["asymmetric"] = {
        "repository" => {
          "pull_requests" => {
            "read" => [@other_repo.id]
          }
        }
      }

      assert_same_hash expected, installation.authorization_details
    end
  end
end
