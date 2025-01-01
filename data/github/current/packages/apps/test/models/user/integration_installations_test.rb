# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class UserIntegrationInstallationsTest < GitHub::TestCase

  include PermissionsHelper

  fixtures do
    @user = create(:user)
  end

  context "#installations_on_all_repositories" do
    test "returns all installations on all repositories" do
      installation_a = make_integration_installation(target: @user, permissions: { "metadata" => :read })
      installation_b = make_integration_installation(target: @user, permissions: { "metadata" => :read })

      assert_same_elements [installation_a, installation_b], @user.installations_on_all_repositories
    end

    test "returns one IntegrationInstallation record for Integrations with permissions on multiple resources" do
      installation_a = make_integration_installation(target: @user, permissions: { "metadata" => :read, "issues" => :read })
      installation_b = make_integration_installation(target: @user, permissions: { "metadata" => :read, "pull_requests" => :read })

      assert_same_elements [installation_a, installation_b], @user.installations_on_all_repositories
    end

    test "returns an empty Array, when there is an installation on only some of the user's repositories" do
      repo = create(:repository, :minimal, owner: @user)
      make_integration_installation(repository: repo)

      assert_empty @user.installations_on_all_repositories
    end

    test "returns an empty Array, when there are no installations on the user's repositories" do
      create(:repository, :minimal, owner: @user)

      assert_empty @user.installations_on_all_repositories
    end

    test "it doesn't include [Site]ScopedIntegrationInstallations" do
      repo = create(:repository, :minimal, owner: @user)

      integration = create(:integration, default_permissions: { "metadata" => :read, "issues" => :read })
      installation_on_all = make_integration_installation(
        target: @user, repositories: [], integration: integration,
      )
      assert_equal "all", installation_on_all.repository_selection

      scoped_installation = make_scoped_integration_installation(
        repositories: :all, parent: installation_on_all, permissions: { "metadata" => :read },
      )

      global_integration = create_unlimited_global_integration(permissions: { "metadata" => :read })
      GitHub.flipper[:disabled_global_apps].disable(global_integration)
      site_scoped_installation = make_site_scoped_integration_installation(
        integration: global_integration, target: @user, repositories: :all,
      )

      # Simulate we have some random IntegrationInstallations in the system, and then
      # we hack the actor_ids on permissions so that they map to our existing
      # scoped installations.
      random_installation = make_integration_installation(target: create(:user))
      another_random_installation = make_integration_installation(target: create(:user))

      Permission.
        where(actor_type: "ScopedIntegrationInstallation", actor_id: scoped_installation.id).
        update_all(actor_id: random_installation.id)

      Permission.
        where(actor_type: "SiteScopedIntegrationInstallation", actor_id: site_scoped_installation.id).
        update_all(actor_id: another_random_installation.id)

      assert_equal [installation_on_all], @user.installations_on_all_repositories
    end
  end
end
