# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopedIntegrationInstallation::AuthorizationDetailsTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @org_repo = create(:repository, :minimal, owner: @org)

    @parent = make_integration_installation(target: @org, permissions: { "metadata" => :read, "contents" => :write, "issues" => :read })
  end

  setup do
    GitHub.flipper[:scoped_installation_with_authorization_details].enable
  end

  context "#permission_results" do
    test "permissions are downgraded if the parent is downgraded" do
      GitHub.flipper[:cached_fgp_permissions].disable
      GitHub.flipper[:cancel_upgrade_integration_installation_version_job].disable

      integration = @parent.integration

      scoped_installation = make_scoped_integration_installation(parent: @parent, repositories: [@org_repo], permissions: { "metadata" => :read, "contents" => :write })
      AuthenticationToken.create_for(scoped_installation) # create an active token so that the permissions get downgraded on the scoped installation.

      perform_enqueued_jobs(only: [UpgradeIntegrationInstallationVersionJob, SyncScopedIntegrationInstallationsJob]) do
        Integration::PermissionsEditor.perform(integration: @parent.integration, permissions_and_events: {
          default_permissions: { "metadata" => :read, "contents" => :read }
        })
      end

      @parent.reload

      assert_same_hash({ "metadata" => :read, "contents" => :read }, scoped_installation.permission_results)
    end

    test "permissions are removed if the parent has removed them" do
      GitHub.flipper[:cached_fgp_permissions].disable
      GitHub.flipper[:cancel_upgrade_integration_installation_version_job].disable

      scoped_installation = make_scoped_integration_installation(parent: @parent, repositories: [@org_repo], permissions: { "metadata" => :read, "contents" => :read })
      AuthenticationToken.create_for(scoped_installation) # create an active token so that the permissions get downgraded on the scoped installation.

      perform_enqueued_jobs(only: [UpgradeIntegrationInstallationVersionJob, SyncScopedIntegrationInstallationsJob]) do
        Integration::PermissionsEditor.perform(integration: @parent.integration, permissions_and_events: {
          default_permissions: { "metadata" => :read }
        })
      end

      @parent.reload

      assert_same_hash({ "metadata" => :read }, scoped_installation.permission_results)
    end

    test "permissions are not added if the parent has added them" do
      scoped_installation = make_scoped_integration_installation(parent: @parent, repositories: [@org_repo], permissions: { "metadata" => :read, "contents" => :write })

      Integration::PermissionsEditor.perform(integration: @parent.integration, permissions_and_events: {
        default_permissions: { "metadata" => :read, "contents" => :write, "pull_requests" => :read }
      })

      editor = @org.admins.first
      version = @parent.integration.reload.latest_version

      IntegrationInstallation::PermissionsEditor.perform(@parent, editor: editor, version: version, entry_point: :test_case)
      @parent.clear_cached_permissions; @parent.reload

      assert_same_hash({ "metadata" => :read, "contents" => :write }, scoped_installation.permission_results)
    end

    test "permissions are not upgraded if the parent is upgraded" do
      GitHub.flipper[:cached_fgp_permissions].disable

      scoped_installation = make_scoped_integration_installation(parent: @parent, repositories: [@org_repo], permissions: { "metadata" => :read, "issues" => :read })

      Integration::PermissionsEditor.perform(integration: @parent.integration, permissions_and_events: {
        default_permissions: { "metadata" => :read, "issues" => :write }
      })

      editor = @org.admins.first
      version = @parent.integration.reload.latest_version

      IntegrationInstallation::PermissionsEditor.perform(@parent, editor: editor, version: version, entry_point: :test_case)
      @parent.clear_cached_permissions; @parent.reload

      assert_same_hash({ "metadata" => :read, "issues" => :read }, scoped_installation.permission_results)
    end
  end
end
