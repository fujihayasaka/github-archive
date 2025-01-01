# typed: true
# frozen_string_literal: true

require "test_helper"

class SiteScopedIntegrationInstallation::PermissionsTest < GitHub::TestCase
  fixtures do
    @user        = create(:user)
    @repository  = create(:repository, :minimal, owner: @user)
    @integration = create(:integration, default_permissions: { "metadata" => :read })

    @all_repositories = SiteScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES
  end

  context "ACTION :create" do
    test "requires an integration" do
      result = SiteScopedIntegrationInstallation::Permissions.check(integration: nil, target: @user, repositories: [@repository], action: :create)

      refute_predicate result, :permitted?

      assert_equal :missing_integration, result.reason
      assert_equal "A parent integration is required.", result.error_message
    end

    test "requires a target" do
      result = SiteScopedIntegrationInstallation::Permissions.check(integration: @integration, target: nil, repositories: [@repository], action: :create)

      refute_predicate result, :permitted?

      assert_equal :missing_target, result.reason
      assert_equal "A target is required.", result.error_message
    end

    test "requires at least one repository when repository permissions are requested" do
      result = SiteScopedIntegrationInstallation::Permissions.check(
        integration: @integration,
        target: @user,
        repositories: [],
        action: :create,
        permissions: { "metadata" => :read },
      )
      refute_predicate result, :permitted?
      assert_equal :missing_repositories, result.reason
      assert_equal "No repositories were provided.", result.error_message
    end

    test "is permitted for valid repositories even if there aren't any repository permissions" do
      integration = create(:integration, default_permissions: {})

      result = SiteScopedIntegrationInstallation::Permissions.check(
        integration: integration, target: @user, repositories: [@repository], action: :create,
      )

      assert_predicate result, :permitted?
    end

    test "is not permitted if the repository does not belong to the target" do
      repo_by_another_user = create(:repository, :minimal)

      result = SiteScopedIntegrationInstallation::Permissions.check(
        integration: @integration,
        target: @user,
        repositories: [repo_by_another_user],
        action: :create,
      )

      refute_predicate result, :permitted?

      assert_equal :repositories_not_available_to_target, result.reason
      assert_equal "There is at least one repository that does not exist or is not accessible by the target.", result.error_message
    end

    test "is not permitted if the repository is destroyed" do
      deleted_repo  = create(:repository, :minimal, owner: @user)
      Repository.where(id: deleted_repo.id).first!.destroy! # rubocop:todo PackageAPI/Repositories/GetActiveOrDeleted

      result = SiteScopedIntegrationInstallation::Permissions.check(
        integration: @integration,
        target: @user,
        repositories: [deleted_repo],
        action: :create,
      )

      refute_predicate result, :permitted?

      assert_equal :repositories_not_available_to_target, result.reason
      assert_equal "There is at least one repository that does not exist or is not accessible by the target.", result.error_message
    end

    test "is permitted if the repositories are duplicated" do
      result = SiteScopedIntegrationInstallation::Permissions.check(
        integration: @integration, target: @user, repositories: [@repository, @repository], action: :create,
      )

      assert_predicate result, :permitted?
    end

    context "with specific permissions" do
      test "is not permitted if there are permissions not granted on the integration" do
        integration = create(:integration, default_permissions: { "metadata" => :read })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: [@repository],
          action: :create,
          permissions: { "issues" => :read },
        )
        refute_predicate result, :permitted?
        assert_equal :permissions_added_or_upgraded, result.reason
      end

      test "is not permitted if the requested permission is an upgrade from the integration's permissions" do
        integration = create(:integration, default_permissions: { "issues" => :read })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: [@repository],
          action: :create,
          permissions: { "issues" => :write },
        )
        refute_predicate result, :permitted?

        assert_equal :permissions_added_or_upgraded, result.reason
        assert_equal "The permissions requested are not granted to this integration.", result.error_message
      end

      test "is permitted if the requested permissions are of equal value than the parents" do
        integration = create(:integration, default_permissions: { "issues" => :read })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: [@repository],
          action: :create,
          permissions: { "issues" => :read },
        )
        assert_predicate result, :permitted?
      end

      test "is permitted if the requested permissions are of lesser value than the parents" do
        integration = create(:integration, default_permissions: { "issues" => :write })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: [@repository],
          action: :create,
          permissions: { "issues" => :read },
        )
        assert_predicate result, :permitted?
      end

      test "is not permitted if the permission actions are not supported" do
        integration = create(:integration, default_permissions: { "issues" => :read })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: [@repository],
          action: :create,
          permissions: { "issues" => :read_or_write },
        )
        refute_predicate result, :permitted?
        assert_equal :invalid_action, result.reason
      end

      test "is not permitted if the requested resource does not exist" do
        integration = create(:integration, default_permissions: { "issues" => :read })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: [@repository],
          action: :create,
          permissions: { "actually_a_lot_of_issues" => :read },
        )
        refute_predicate result, :permitted?
        assert_equal :invalid_resource, result.reason
      end
    end
  end

  context "ACTION :create installing on all repositories" do
    test "is permitted for valid integrations even if no permissions are requested" do
      integration = create(:integration, default_permissions: {})

      result = SiteScopedIntegrationInstallation::Permissions.check(
        integration: integration, target: @user, repositories: @all_repositories, action: :create,
      )

      assert_predicate result, :permitted?
    end

    test "is permitted on valid targets" do
      result = SiteScopedIntegrationInstallation::Permissions.check(
        integration: @integration,
        target: @user,
        repositories: @all_repositories,
        action: :create,
        permissions: { "metadata" => :read },
      )
      assert_predicate result, :permitted?
    end

    context "with specific permissions" do
      test "is not permitted if there are permissions not granted on the integration" do
        integration = create(:integration, default_permissions: { "metadata" => :read })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: @all_repositories,
          action: :create,
          permissions: { "issues" => :read },
        )
        refute_predicate result, :permitted?

        assert_equal :permissions_added_or_upgraded, result.reason
        assert_equal "The permissions requested are not granted to this integration.", result.error_message
      end

      test "is not permitted if the requested permission is an upgrade from the parent's permission" do
        integration = create(:integration, default_permissions: { "issues" => :read })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: @all_repositories,
          action: :create,
          permissions: { "issues" => :write },
        )
        refute_predicate result, :permitted?

        assert_equal :permissions_added_or_upgraded, result.reason
        assert_equal "The permissions requested are not granted to this integration.", result.error_message
      end

      test "is permitted if the requested permissions are of equal value than the parents" do
        integration = create(:integration, default_permissions: { "issues" => :write })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: @all_repositories,
          action: :create,
          permissions: { "issues" => :write },
        )
        assert_predicate result, :permitted?
      end

      test "is permitted if the requested permissions are of lesser value than the parents" do
        integration = create(:integration, default_permissions: { "issues" => :write })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: @all_repositories,
          action: :create,
          permissions: { "issues" => :read },
        )
        assert_predicate result, :permitted?
      end

      test "is permitted even if repository permissions are not specified" do
        integration = create(:integration, default_permissions: { "issues" => :write, "members" => :read })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: @all_repositories,
          action: :create,
          permissions: { "members" => :read },
        )
        assert_predicate result, :permitted?
      end

      test "is not permitted if the permission actions are not supported" do
        integration = create(:integration, default_permissions: { "issues" => :read })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: @all_repositories,
          action: :create,
          permissions: { "issues" => :read_or_write },
        )
        refute_predicate result, :permitted?
        assert_equal :invalid_action, result.reason
        assert_equal "There is at least one permission action that is not supported. It should be one of: \"read\", \"write\" or \"admin\".", result.error_message
      end

      test "is not permitted if the requested resource does not exist" do
        integration = create(:integration, default_permissions: { "issues" => :read })

        result = SiteScopedIntegrationInstallation::Permissions.check(
          integration: integration,
          target: @user,
          repositories: @all_repositories,
          action: :create,
          permissions: { "actually_a_lot_of_issues" => :read },
        )
        refute_predicate result, :permitted?
        assert_equal :invalid_resource, result.reason
        assert_equal "There is at least one permission resource that is not supported.", result.error_message
      end
    end
  end
end
