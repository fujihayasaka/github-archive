# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallation::PermissionTargetTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner

    @admin     = create(:user, login: "org-admin")
    @org       = create(:organization, admin: @admin)
    @rando     = create(:user, login: "rando")
    @noora     = create(:user, login: "noora")
    @business  = create(:business, owners: [@admin])

    @app_owner   = create(:user, login: "app-owner")
    @integration = create(:integration, owner: @app_owner)

    @installation = make_integration_installation(target: @org, integration: @integration, permissions: { "metadata" => :read })

    @repo_with_admin = create(:repository, :minimal, owner: @org)
    @repo_with_admin.add_member(@noora, action: :admin)

    @repo_with_admin2 = create(:repository, :minimal, owner: @org)
    @repo_with_admin2.add_member(@noora, action: :admin)

    @repo_admin_integration  = create(:integration, owner: @app_owner)
    @repo_admin_installation = make_integration_installation(integration: @repo_admin_integration, repository: @repo_with_admin, permissions: { "metadata" => :read })
  end

  context "Business target feature flag disabled" do
    context "single file name" do
      test "is permitted when the single file name has changed" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "single_file" => :read, "test_subject_for_required_permissions" => :read }, single_file_name: "README.m")
        version      = create(:integration_version, integration: @integration, default_permissions: { "single_file" => :read }, single_file_name: "README.md")

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "Business permissions" do
      test "is not permitted when permissions are added" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "enterprise_administration" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :permissions_added, result.reason
      end

      test "is not permitted when permissions are upgraded" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "enterprise_administration" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "enterprise_administration" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :permissions_upgraded, result.reason
      end

      test "is permitted when permissions are downgraded" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "enterprise_administration" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: { "enterprise_administration" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "enterprise_administration" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "Repository permissions" do
      test "is permitted when permissions are added" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "metadata" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are upgraded" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "contents" => :read, "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "contents" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are downgraded" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "contents" => :write, "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "contents" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "contents" => :write, "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "Organization permissions" do
      test "is permitted when permissions are added" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "members" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are upgraded" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "members" => :read, "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "members" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are downgraded" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "members" => :write, "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "members" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "members" => :write, "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "User permissions" do
      test "is permitted when permissions are added" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "emails" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are upgraded" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "emails" => :read, "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "emails" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are downgraded" do
        GitHub.flipper[:enterprise_app_installation_management].disable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "emails" => :write, "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "emails" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        GitHub.flipper[:enterprise_app_installation_management].disable

        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "emails" => :write, "test_subject_for_required_permissions" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end
  end

  context "Business target feature flag enabled" do
    context "single file name" do
      test "is permitted when the single file name has changed" do
        GitHub.flipper[:enterprise_app_installation_management].enable

        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "single_file" => :read, "test_subject_for_required_permissions" => :read }, single_file_name: "README.m")
        version      = create(:integration_version, integration: @integration, default_permissions: { "single_file" => :read, "test_subject_for_required_permissions" => :read }, single_file_name: "README.md")

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "Business permissions" do
      test "is not permitted when permissions are added" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { Business::Resources.subject_types.first => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "enterprise_organization_installation_repositories" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :permissions_added, result.reason
      end

      test "is not permitted when permissions are upgraded" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "enterprise_administration" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "enterprise_administration" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :permissions_upgraded, result.reason
      end

      test "is permitted when permissions are downgraded" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "enterprise_administration" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: { "enterprise_administration" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "enterprise_administration" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "Repository permissions" do
      test "is permitted when permissions are added" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { "metadata" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are upgraded" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "contents" => :read, Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { "contents" => :write, Business::Resources.subject_types.first => "read" })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are downgraded" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "contents" => :write, Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { "contents" => :read, Business::Resources.subject_types.first => "read" })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "contents" => :write, Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { Business::Resources.subject_types.first => "read" })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "Organization permissions" do
      test "is permitted when permissions are added" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { "members" => :read, Business::Resources.subject_types.first => "read" })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are upgraded" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "members" => :read, Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { "members" => :write, Business::Resources.subject_types.first => "read" })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are downgraded" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "members" => :write, Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { "members" => :read, Business::Resources.subject_types.first => "read" })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "members" => :write, Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { Business::Resources.subject_types.first => "read" })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "User permissions" do
      test "is permitted when permissions are added" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { "emails" => :read, Business::Resources.subject_types.first => "read" })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are upgraded" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "emails" => :read, Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { "emails" => :write, Business::Resources.subject_types.first => "read" })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are downgraded" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "emails" => :write, Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { "emails" => :read, Business::Resources.subject_types.first => "read" })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        GitHub.flipper[:enterprise_app_installation_management].enable
        installation = make_integration_installation(integration: @integration, target: @business, permissions: { "emails" => :write, Business::Resources.subject_types.first => "read" })
        version      = create(:integration_version, integration: @integration, default_permissions: { Business::Resources.subject_types.first => "read" })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end
  end

  context "Organization target" do
    context "single file name" do
      test "is not permitted when the single file name has changed" do
        installation = make_integration_installation(target: @org, permissions: { "single_file" => :read }, single_file_name: "README.m")
        version      = create(:integration_version, integration: installation.integration, default_permissions: { "single_file" => :read }, single_file_name: "README.md")

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :single_file_name_changed, result.reason
      end
    end

    context "Business permissions" do
      test "is permitted when permissions are added" do
        version = create(:integration_version, integration: @integration, default_permissions: { "enterprise_administration" => :read })
        result  = IntegrationInstallation::Permissions.check(installation: @installation, actor: nil, action: :auto_upgrade, version: version)

        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are upgraded" do
        installation = make_integration_installation(target: @org, permissions: { "enterprise_administration" => :read })
        version      = create(:integration_version, integration: installation.integration, default_permissions: { "enterprise_administration" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are downgraded" do
        installation = make_integration_installation(target: @org, permissions: { "enterprise_administration" => :write })
        version      = create(:integration_version, integration: installation.integration, default_permissions: { "enterprise_administration" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        installation = make_integration_installation(target: @org, permissions: { "enterprise_administration" => :write })
        version      = create(:integration_version, integration: installation.integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "Repository permissions" do
      test "is not permitted when permissions are added" do
        version = create(:integration_version, integration: @integration, default_permissions: { "metadata" => :read, "contents" => :read })

        result = IntegrationInstallation::Permissions.check(installation: @installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :permissions_added, result.reason
      end

      test "is not permitted when permissions are upgraded" do
        installation = make_integration_installation(target: @org, permissions: { "contents" => :read })
        version      = create(:integration_version, integration: installation.integration, default_permissions: { "contents" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :permissions_upgraded, result.reason
      end

      test "is permitted when permissions are downgraded" do
        installation = make_integration_installation(target: @org, permissions: { "contents" => :write })
        version      = create(:integration_version, integration: installation.integration, default_permissions: { "contents" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        version = create(:integration_version, integration: @integration, default_permissions: {})
        result  = IntegrationInstallation::Permissions.check(installation: @installation, actor: nil, action: :auto_upgrade, version: version)

        assert_predicate result, :permitted?
      end
    end

    context "Organization permissions" do
      test "is not permitted when permissions are added" do
        installation = make_integration_installation(target: @org, permissions: {})
        version      = create(:integration_version, integration: installation.integration, default_permissions: { "members" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :permissions_added, result.reason
      end

      test "is not permitted when permissions are upgraded" do
        installation = make_integration_installation(target: @org, permissions: { "members" => :read })
        version      = create(:integration_version, integration: installation.integration, default_permissions: { "members" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :permissions_upgraded, result.reason
      end

      test "is permitted when permissions are downgraded" do
        installation = make_integration_installation(target: @org, permissions: { "members" => :write })
        version      = create(:integration_version, integration: installation.integration, default_permissions: { "members" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        installation = make_integration_installation(target: @org, permissions: { "members" => :write })
        version      = create(:integration_version, integration: installation.integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "User permissions" do
      test "is permitted when permissions are added" do
        installation = make_integration_installation(target: @org, permissions: {})
        version      = create(:integration_version, integration: installation.integration, default_permissions: { "emails" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are upgraded" do
        installation = make_integration_installation(target: @org, permissions: { "emails" => :read })
        version      = create(:integration_version, integration: installation.integration, default_permissions: { "emails" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are downgraded" do
        installation = make_integration_installation(target: @org, permissions: { "emails" => :write })
        version      = create(:integration_version, integration: installation.integration, default_permissions: { "emails" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        installation = make_integration_installation(target: @org, permissions: { "emails" => :write })
        version      = create(:integration_version, integration: installation.integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end
  end

  context "User target" do
    context "single file name" do
      test "is not permitted when the single file name has changed" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "single_file" => :read }, single_file_name: "README.m")
        version      = create(:integration_version, integration: @integration, default_permissions: { "single_file" => :read }, single_file_name: "README.md")

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :single_file_name_changed, result.reason
      end
    end

    context "Business permissions" do
      test "is permitted when permissions are added" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: {})
        version      = create(:integration_version, integration: @integration, default_permissions: { "enterprise_administration" => :read })

        result  = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are upgraded" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "enterprise_administration" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "enterprise_administration" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are downgraded" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "enterprise_administration" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: { "enterprise_administration" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "enterprise_administration" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "Repository permissions" do
      test "is not permitted when permissions are added" do
        installation = make_integration_installation(integration: @integration, target: @admin)
        version      = create(:integration_version, integration: @integration, default_permissions: { "metadata" => :read, "contents" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :permissions_added, result.reason
      end

      test "is not permitted when permissions are upgraded" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "contents" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "contents" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)

        refute_predicate result, :permitted?
        assert_equal :permissions_upgraded, result.reason
      end

      test "is permitted when permissions are downgraded" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "contents" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: { "contents" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "contents" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "Organization permissions" do
      test "is permitted when permissions are added" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: {})
        version      = create(:integration_version, integration: @integration, default_permissions: { "members" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are upgraded" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "members" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "members" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are downgraded" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "members" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: { "members" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "members" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end

    context "User permissions" do
      test "is permitted when permissions are added" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: {})
        version      = create(:integration_version, integration: @integration, default_permissions: { "emails" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are upgraded" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "emails" => :read })
        version      = create(:integration_version, integration: @integration, default_permissions: { "emails" => :write })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are downgraded" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "emails" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: { "emails" => :read })

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end

      test "is permitted when permissions are removed" do
        installation = make_integration_installation(integration: @integration, target: @admin, permissions: { "emails" => :write })
        version      = create(:integration_version, integration: @integration, default_permissions: {})

        result = IntegrationInstallation::Permissions.check(installation: installation, actor: nil, action: :auto_upgrade, version: version)
        assert_predicate result, :permitted?
      end
    end
  end
end
