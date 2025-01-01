# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dogstats_test_helpers"
require "test_helpers/permissions_helper"

class SiteScopedIntegrationInstallation::Editors::PackagesTest < GitHub::TestCase
  include DogstatsTestHelpers
  include PermissionsHelper

  fixtures do
    @user       = create(:user)
    @repository = create(:repository, :minimal, owner: @user)

    @package = PackageRegistry::PackageSubject.new(id: 1, access_type: :contents).freeze
  end

  setup do
    GitHub.flipper[:disabled_global_apps].disable
  end

  context ".grant" do
    test "grants permissions to requested package" do
      integration = create_internal_app_with_capabilities(
        permissions: { "metadata" => :read, "packages" => :write, "contents" => "read" },
        capabilities: {
          installed_globally: true,
          elevated_read_access_on_target: true,
          limited_access: false,
          manage_packages_permissions: true
        },
      )

      installation = make_site_scoped_integration_installation(integration: integration, target: @user, repositories: [@repository])

      result = SiteScopedIntegrationInstallation::Editors::Packages.grant(
        installation, @package, entry_point: :test_case
      )

      assert_predicate result, :success?

      assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @package.resources.contents, action: :read)
    end

    test "grants permissions with the expected expiration" do
      integration = create_internal_app_with_capabilities(
        permissions: { "metadata" => :read, "packages" => :write, "contents" => "read" },
        capabilities: {
          installed_globally: true,
          elevated_read_access_on_target: true,
          limited_access: false,
          manage_packages_permissions: true
        },
      )

      installation = make_site_scoped_integration_installation(integration: integration, target: @user, repositories: [@repository])

      result = SiteScopedIntegrationInstallation::Editors::Packages.grant(
        installation, @package, entry_point: :test_case
      )

      assert_predicate result, :success?

      subject = @package.resources.contents

      permission_record = Permission.where(
        actor_id: installation.ability_id,
        actor_type: installation.ability_type,
        subject_id: subject.ability_id,
        subject_type: subject.ability_type
      ).first

      refute_nil permission_record.expires_at
      assert_equal permission_record.expires_at.to_i, installation.expires_at.to_i
    end

    test "returns failed result on failure" do
      integration = create_unlimited_global_integration
      installation = make_site_scoped_integration_installation(integration: integration, target: @user, repositories: [@repository])

      ::SiteScopedIntegrationInstallation::Editors::Packages.any_instance.stubs(:grant_access_on).raises(RuntimeError)

      result = SiteScopedIntegrationInstallation::Editors::Packages.grant(
        installation, @package, entry_point: :test_case
      )

      assert_predicate result, :failed?
    end

    test "returns failed result if integration is not globally installed" do
      installation_with_incapable_integration = \
        SiteScopedIntegrationInstallation.create(integration: create(:integration), target: @user)

      result = SiteScopedIntegrationInstallation::Editors::Packages.grant(
        installation_with_incapable_integration, @package, entry_point: :test_case
      )

      assert_predicate result, :failed?
      assert_equal :integration_not_capable, result.reason
    end

    test "instruments success" do
      integration = create_internal_app_with_capabilities(
        permissions: { "metadata" => :read, "packages" => :write, "contents" => "read" },
        capabilities: {
          installed_globally: true,
          elevated_read_access_on_target: true,
          limited_access: false,
          manage_packages_permissions: true
        },
      )

      installation = make_site_scoped_integration_installation(integration: integration, target: @user, repositories: [@repository])

      SiteScopedIntegrationInstallation::Editors::Packages.grant(
        installation, @package, entry_point: :test_case
      )

      assert_dogstats_increment(1, "site_scoped_integration_installation.editors.packages", tags: ["result:success", "action:grant"])
    end

    test "instruments failed" do
      integration = create_internal_app_with_capabilities(
        permissions: { "metadata" => :read, "packages" => :write, "contents" => "read" },
        capabilities: {
          installed_globally: true,
          elevated_read_access_on_target: true,
          limited_access: false,
          manage_packages_permissions: true
        },
      )

      installation = make_site_scoped_integration_installation(integration: integration, target: @user, repositories: [@repository])
      ::SiteScopedIntegrationInstallation::Editors::Packages.any_instance.stubs(:grant_access_on).raises(RuntimeError)

      SiteScopedIntegrationInstallation::Editors::Packages.grant(
        installation, @package, entry_point: :test_case
      )

      assert_dogstats_increment(1, "site_scoped_integration_installation.editors.packages", tags: ["result:failure", "action:grant"])
    end
  end

  context ".revoke" do
    test "removes permissions to requested package" do
      codespace = create(:codespace, owner: @user, repository_id: @repository.id)
      integration = create_internal_app_with_capabilities(
        permissions: { "metadata" => :read, "packages" => :write, "contents" => "read" },
        capabilities: {
          installed_globally: true,
          elevated_read_access_on_target: true,
          limited_access: false,
          manage_packages_permissions: true,
          write_legacy_site_scoped_fine_grained_package_permissions: true
        },
      )

      result = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: [@repository], codespaces: [codespace], permissions: { "metadata" => :read, "packages" => :read, "contents" => "read" }, entry_point: :test_case
      )

      assert_predicate result, :success?
      installation = result.installation

      SiteScopedIntegrationInstallation::Editors::Packages.grant(
        installation, @package, entry_point: :test_case
      )

      assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @package.resources.contents, action: :read)

      result = SiteScopedIntegrationInstallation::Editors::Packages.revoke(
        installation, @package, entry_point: :test_case
      )

      assert_predicate result, :success?

      refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @package.resources.contents, action: :read)
    end

    test "returns failed result on failure" do
      integration = create_internal_app_with_capabilities(
        permissions: { "metadata" => :read, "packages" => :write, "contents" => "read" },
        capabilities: {
          installed_globally: true,
          elevated_read_access_on_target: true,
          limited_access: false,
          manage_packages_permissions: true,
          write_legacy_site_scoped_fine_grained_package_permissions: true
        },
      )

      installation = make_site_scoped_integration_installation(integration: integration, target: @user, repositories: [@repository])

      ::SiteScopedIntegrationInstallation::Editors::Packages.any_instance.stubs(:revoke_access_on).raises(RuntimeError)

      result = SiteScopedIntegrationInstallation::Editors::Packages.revoke(
        installation, @package, entry_point: :test_case
      )

      assert_predicate result, :failed?
    end

    test "returns failed result if integration is not globally installed" do
      installation_with_incapable_integration = \
        SiteScopedIntegrationInstallation.create(integration: create(:integration), target: @user)

      result = SiteScopedIntegrationInstallation::Editors::Packages.revoke(
        installation_with_incapable_integration, @package, entry_point: :test_case
      )

      assert_predicate result, :failed?
      assert_equal :integration_not_capable, result.reason
    end

    test "instruments success" do
      integration = create_internal_app_with_capabilities(
        permissions: { "metadata" => :read, "packages" => :write, "contents" => "read" },
        capabilities: {
          installed_globally: true,
          elevated_read_access_on_target: true,
          limited_access: false,
          manage_packages_permissions: true,
          write_legacy_site_scoped_fine_grained_package_permissions: true
        },
      )

      installation = make_site_scoped_integration_installation(integration: integration, target: @user, repositories: [@repository])

      SiteScopedIntegrationInstallation::Editors::Packages.revoke(
        installation, @package, entry_point: :test_case
      )

      assert_dogstats_increment(1, "site_scoped_integration_installation.editors.packages", tags: ["result:success", "action:revoke"])
    end

    test "instruments failed" do
      integration = create_internal_app_with_capabilities(
        permissions: { "metadata" => :read, "packages" => :write, "contents" => "read" },
        capabilities: {
          installed_globally: true,
          elevated_read_access_on_target: true,
          limited_access: false,
          manage_packages_permissions: true,
          write_legacy_site_scoped_fine_grained_package_permissions: true
        },
      )

      installation = make_site_scoped_integration_installation(integration: integration, target: @user, repositories: [@repository])

      ::SiteScopedIntegrationInstallation::Editors::Packages.any_instance.stubs(:revoke_access_on).raises(RuntimeError)

      SiteScopedIntegrationInstallation::Editors::Packages.revoke(
        installation, @package, entry_point: :test_case
      )

      assert_dogstats_increment(1, "site_scoped_integration_installation.editors.packages", tags: ["result:failure", "action:revoke"])
    end
  end
end
