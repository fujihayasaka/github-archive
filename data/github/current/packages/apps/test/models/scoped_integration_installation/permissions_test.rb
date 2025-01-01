# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedIntegrationInstallation::PermissionsTest < GitHub::TestCase
  fixtures do
    @repository          = create(:repository, :minimal)
    @parent_installation = make_integration_installation(target: @repository.owner, permissions: { "metadata" => :read })
  end

  context "ACTION :create" do
    test "requires a parent installation" do
      result = ScopedIntegrationInstallation::Permissions.check(
        installation: nil,
        repositories: [@repository],
        action: :create,
        permissions: { "metadata" => :read },
      )

      refute_predicate result, :permitted?

      assert_equal :missing_parent, result.reason
      assert_equal "A parent installation is required.", result.error_message
    end

    test "is not permitted if the parent installation is suspended" do

      @parent_installation.suspend!
      @parent_installation.reload
      result = ScopedIntegrationInstallation::Permissions.check(
        installation: @parent_installation,
        repositories: [@repository],
        action: :create,
        permissions: { "metadata" => :read },
      )

      refute_predicate result, :permitted?

      assert_equal :suspended_parent, result.reason
      assert_equal "The parent installation is suspended.", result.error_message
    end

    test "is not permitted if the repository does not belong to the parent installation target" do
      repo_by_another_user = create(:repository, :minimal)
      result = ScopedIntegrationInstallation::Permissions.check(
        installation: @parent_installation,
        repositories: [repo_by_another_user],
        action: :create,
        permissions: { "metadata" => :read },
      )

      refute_predicate result, :permitted?

      assert_equal :repositories_not_available_to_target, result.reason
      assert_equal "There is at least one repository that does not exist or is not accessible to the parent installation.", result.error_message
    end

    test "is not permitted unless the repository is accessible by the parent installation" do
      inaccessible_repo   = create(:repository, :minimal, owner: @repository.owner)
      parent_installation = make_integration_installation(repository: @repository, permissions: { "metadata" => :read })

      refute_includes parent_installation.repository_ids, inaccessible_repo.id

      result = ScopedIntegrationInstallation::Permissions.check(
        installation: parent_installation,
        repositories: [inaccessible_repo],
        action: :create,
        permissions: parent_installation.permissions,
      )

      refute_predicate result, :permitted?

      assert_equal :repositories_not_available_to_target, result.reason
      assert_equal "There is at least one repository that does not exist or is not accessible to the parent installation.", result.error_message
    end

    context "installation repository_selection 'all'" do
      test "is permitted when the repository is accessible by the installation" do
        assert_equal "all", @parent_installation.repository_selection

        result = ScopedIntegrationInstallation::Permissions.check(
          installation: @parent_installation,
          repositories: [@repository],
          action: :create,
          permissions: @parent_installation.permissions,
        )

        assert_predicate result, :permitted?
      end

      test "is permitted to install on all" do
        assert_equal "all", @parent_installation.repository_selection

        result = ScopedIntegrationInstallation::Permissions.check(
          installation: @parent_installation,
          repositories: [@repository],
          action: :create,
          permissions: @parent_installation.permissions,
        )

        assert_predicate result, :permitted?
      end

      test "is not permitted to use 'selected' option" do
        assert_equal "all", @parent_installation.repository_selection

        result = ScopedIntegrationInstallation::Permissions.check(
          installation: @parent_installation,
          repositories: :selected,
          action: :create,
          permissions: @parent_installation.permissions,
        )

        refute_predicate result, :permitted?
        assert_equal :not_installed_on_selected, result.reason
      end
    end

    context "installation repository_selection is 'selected'" do
      test "is permitted when the repository is accessible by the installation" do
        parent_installation = make_integration_installation(repository: @repository, permissions: { "metadata" => :read })
        assert_equal "selected", parent_installation.repository_selection

        result = ScopedIntegrationInstallation::Permissions.check(
          installation: parent_installation,
          repositories: [@repository],
          action: :create,
          permissions: parent_installation.permissions,
        )

        assert_predicate result, :permitted?
      end

      test "is permitted when the 'selected' option is provided" do
        parent_installation = make_integration_installation(repository: @repository, permissions: { "metadata" => :read })
        assert_equal "selected", parent_installation.repository_selection

        result = ScopedIntegrationInstallation::Permissions.check(
          installation: parent_installation,
          repositories: ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_SELECTED_REPOSITORIES,
          action: :create,
          permissions: parent_installation.permissions,
        )

        assert_predicate result, :permitted?
      end

      test "is not permitted to install on all" do
        parent_installation = make_integration_installation(repository: @repository, permissions: { "metadata" => :read })
        assert_equal "selected", parent_installation.repository_selection

        result = ScopedIntegrationInstallation::Permissions.check(
          installation: parent_installation,
          repositories: ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES,
          action: :create,
          permissions: parent_installation.permissions,
        )

        refute_predicate result, :permitted?
        assert_equal :not_installed_on_all, result.reason
      end
    end

    context "with specific permissions" do
      test "is not permitted if there are permissions not granted on the parent installation" do
        parent_installation = make_integration_installation(repository: @repository, permissions: { "metadata" => :read })

        result = ScopedIntegrationInstallation::Permissions.check(installation: parent_installation, repositories: [@repository], action: :create, permissions: { "issues" => :read })
        refute_predicate result, :permitted?

        assert_equal :permissions_added, result.reason
      end

      test "is not permitted if the requested permission is an upgrade from the parent's permission" do
        parent_installation = make_integration_installation(repository: @repository, permissions: { "issues" => :read })

        result = ScopedIntegrationInstallation::Permissions.check(installation: parent_installation, repositories: [@repository], action: :create, permissions: { "issues" => :write })
        refute_predicate result, :permitted?

        assert_equal :permissions_upgraded, result.reason
        assert_equal "The level of access for permissions requested are not granted to this installation.", result.error_message
      end

      test "is permitted if the requested permissions are of equal value than the parents" do
        parent_installation = make_integration_installation(repository: @repository, permissions: { "issues" => :read })

        result = ScopedIntegrationInstallation::Permissions.check(installation: parent_installation, repositories: [@repository], action: :create, permissions: { "issues" => :read })
        assert_predicate result, :permitted?
      end

      test "is permitted if the requested permissions are of lesser value than the parents" do
        parent_installation = make_integration_installation(repository: @repository, permissions: { "issues" => :write })

        result = ScopedIntegrationInstallation::Permissions.check(installation: parent_installation, repositories: [@repository], action: :create, permissions: { "issues" => :read })
        assert_predicate result, :permitted?
      end

      test "is permitted if repository permissions are not specified" do
        parent_installation = make_integration_installation(repository: @repository, permissions: { "issues" => :write, "members" => :read })

        result = ScopedIntegrationInstallation::Permissions.check(installation: parent_installation, action: :create, permissions: { "members" => :read })
        assert_predicate result, :permitted?
      end

      test "is not permitted if the permission actions are not supported" do
        parent_installation = make_integration_installation(repository: @repository, permissions: { "issues" => :read })

        result = ScopedIntegrationInstallation::Permissions.check(installation: parent_installation, repositories: [@repository], action: :create, permissions: { "issues" => :read_or_write })
        refute_predicate result, :permitted?
        assert_equal :invalid_action, result.reason
      end

      test "is not permitted if the requested resource does not exist" do
        parent_installation = make_integration_installation(repository: @repository, permissions: { "issues" => :read })

        result = ScopedIntegrationInstallation::Permissions.check(installation: parent_installation, repositories: [@repository], action: :create, permissions: { "actually_a_lot_of_issues" => :read })
        refute_predicate result, :permitted?
        assert_equal :permissions_added, result.reason
      end
    end
  end
end
