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

      assert_includes result.installation.repositories, @other_repo
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
      assert_includes result.installation.repositories, @other_repo
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

    test "permissions cannot be upgraded without upgrade_default_permissions capability" do
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
    # Note that the App permissions themselves don't need to change in order to update the SSII permissions.
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

    test "permissions can be upgraded also in authorization details" do
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

      authorization_details = details_struct(installation)
      refute authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [@other_repo.id],
        resource: "pull_requests",
        action: :write
      )

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation,
        repositories: [@other_repo],
        repository_permissions: { "pull_requests" => :write },
        entry_point: :test_case
      )

      upgraded_authorization_details = details_struct(installation)
      assert upgraded_authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [@other_repo.id],
        resource: "pull_requests",
        action: :write
      )
    end

    test "adds repositories to the JSON details if the hash exists" do
      integration = create_unlimited_global_integration(
        permissions: { "pull_requests" => :write },
      )

      installation = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      authorization_details = details_struct(installation)

      refute authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [@other_repo.id],
        resource: "pull_requests",
      )

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation,
        repositories: [@other_repo],
        entry_point: :test_case,
        repository_permissions: { "pull_requests" => :read },
      )

      installation.reload
      assert_predicate result, :success?

      updated_authorization_details = details_struct(result.installation)

      assert updated_authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [@other_repo.id],
        resource: "pull_requests",
      )
    end

    test "adds multiple repos in sequence" do
      another_other_repo = create(:repository, :minimal, owner: @user)

      integration = create_unlimited_global_integration(
        permissions: { "pull_requests" => :write },
      )

      installation = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: [@repository], entry_point: :test_case
      ).installation

      SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation,
        repositories: [@other_repo],
        entry_point: :test_case,
        repository_permissions: { "pull_requests" => :read },
      )

      result = SiteScopedIntegrationInstallation::Editors::Repository.grant(
        installation,
        repositories: [another_other_repo],
        entry_point: :test_case,
        repository_permissions: { "pull_requests" => :read },
      )

      updated_authorization_details = details_struct(result.installation.reload)

      assert updated_authorization_details.explicitly_grants_permission?(
        resource_type: resource_type_for("Repository"),
        selection: [@other_repo.id, another_other_repo.id],
        resource: "pull_requests",
      )
    end
  end
end
