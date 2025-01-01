# typed: true
# frozen_string_literal: true
require "test_helper"

class Permissions::OrgFGPTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper
  include AuthndClientTestHelpers
  include ApiProgrammaticGrantHelpers

  setup do
    setup_authnd_stub
  end

  teardown do
    remove_authnd_stub
  end

  fixtures do
    @owner = create(:user)
    @org = create(:business_plus_organization, admin: @owner)
    @other_org = create(:business_plus_organization, admin: @owner)

    @basic_member = create(:user)
    @org.add_member(@basic_member, action: :write)
    @rando = create(:user)

    # test team membership
    @team = create(:team, organization: @org)
    @team_member = create(:user)
    @org.add_member(@team_member)
    @team.add_member(@team_member)
  end

  context "organization authzd check" do
    [
      [:read_audit_logs, :async_can_read_org_audit_logs?],
      [:manage_organization_webhooks, :async_can_write_org_webhooks?],
      [:manage_organization_webhooks, :async_can_read_org_webhooks?],
      [:read_organization_custom_repo_role, :async_can_read_custom_repo_roles?],
      [:write_organization_custom_repo_role, :async_can_write_custom_repo_roles?],
      [:read_organization_custom_org_role, :async_can_read_custom_org_roles?],
      [:write_organization_custom_org_role, :async_can_write_custom_org_roles?],
      [:manage_organization_oauth_application_policy, :async_can_manage_org_oauth_app_policy?],
      [:manage_org_custom_properties_definitions, :async_can_manage_organization_custom_properties_definitions?],
      [:edit_org_custom_properties_values, :async_can_edit_organization_custom_properties_values?],
      [:write_organization_actions_settings, :async_can_write_organization_actions_settings?],
      [:write_organization_actions_secrets, :async_can_write_organization_actions_secrets?],
      [:write_organization_actions_variables, :async_can_write_organization_actions_variables?],
      [:write_organization_runners_and_runner_groups, :async_can_write_organization_runners_and_runner_groups?],
      [:write_organization_packages, :async_can_write_organization_packages?],
      [:read_organization_actions_usage_metrics, :async_can_read_organization_actions_usage_metrics?],
    ].each do |fgp, method|
      test "#{method} denies when actor is not a member" do
        allowed = @org.send(method, @rando).sync
        refute allowed
      end

      test "#{method} denies when actor is a member without permission" do
        allowed = @org.send(method, @basic_member).sync
        refute allowed
      end

      test "#{method} denies when actor has permission on different organization" do
        grant_custom_org_role(user: @basic_member, target: @org, fgps: [fgp])
        allowed = @other_org.send(method, @basic_member).sync
        refute allowed
      end

      test "#{method} allows when actor is a member with correct fine-grained permission" do
        grant_custom_org_role(user: @basic_member, target: @org, fgps: [fgp])
        allowed = @org.send(method, @basic_member).sync
        assert allowed
      end

      test "#{method} allows when actor is an org admin" do
        allowed = @org.send(method, @owner).sync
        assert allowed
      end

      test "#{method} allows when actor is a team member with correct fine-grained permission" do
        grant_custom_org_role(user: @team, target: @org, fgps: [fgp])
        allowed = @org.send(method, @team_member).sync
        assert allowed
      end

      test "#{method} denies when actor is a team member without correct fine-grained permission" do
        allowed = @org.send(method, @team_member).sync
        refute allowed
      end
    end

    test "write repo role FGP grants read access too" do
      refute @org.async_can_read_custom_repo_roles?(@basic_member).sync
      grant_custom_org_role(user: @basic_member, target: @org, fgps: [:write_organization_custom_repo_role])
      assert @org.async_can_read_custom_repo_roles?(@basic_member).sync

      refute @org.async_can_read_custom_repo_roles?(@team_member).sync
      grant_custom_org_role(user: @team, target: @org, fgps: [:write_organization_custom_repo_role])
      assert @org.async_can_read_custom_repo_roles?(@team_member).sync
    end

    test "write org role FGP grants read access too" do
      refute @org.async_can_read_custom_org_roles?(@basic_member).sync
      grant_custom_org_role(user: @basic_member, target: @org, fgps: [:write_organization_custom_org_role])
      assert @org.async_can_read_custom_org_roles?(@basic_member).sync

      refute @org.async_can_read_custom_org_roles?(@team_member).sync
      grant_custom_org_role(user: @team, target: @org, fgps: [:write_organization_custom_org_role])
      assert @org.async_can_read_custom_org_roles?(@team_member).sync
    end

    [
      ["organization_hooks", :write, :async_can_write_org_webhooks?],
      ["organization_hooks", :read, :async_can_read_org_webhooks?],
      ["organization_administration", :read, :async_can_read_org_audit_logs?],
    ].each do |pa_resource, pa_action, method|
      test "#{method} allows when actor is a PAT with correct programmatic access permission" do
        pat = make_user_programmatic_access_with_grant(target: @org, requester: @owner, permissions: { pa_resource => pa_action })
        allowed = @org.send(method, pat.grant).sync
        assert allowed
      end

      test "#{method} denies when actor is a PAT with no programmatic access permission" do
        pat = make_user_programmatic_access_with_grant(target: @org, requester: @owner, permissions: {})
        allowed = @org.send(method, pat.grant).sync
        refute allowed
      end
    end
  end
end

class Permissions::SettingsAccessTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @owner = create(:user)
    @org = create(:business_plus_organization, admin: @owner)
    @business = create :business, owners: [@owner], organizations: [@org]

    @org_role_user = create(:user)
    @security_manager = create(:user)
    @billing_manager = create(:user)
    @moderator = create(:user)
    @app_manager = create(:user)
    @rando = create(:user)

    @org.add_member(@org_role_user)
    @org.add_member(@security_manager)
    @org.add_member(@billing_manager)
    @org.add_member(@moderator)
    @org.add_member(@app_manager)

    # test team membership
    @team = create(:team, organization: @org)
    @team_member = create(:user)
    @org.add_member(@team_member)
    @team.add_member(@team_member)

    security_team = create(:security_manager_team, organization: @org)
    security_team.add_member(@security_manager)
    @org.billing.add_manager @billing_manager, actor: @owner
    moderation = Organization::Moderation.new(@org)
    moderation.add_moderator(@moderator, actor: @owner)
    ::Permissions::Granter.grant(
      action: :manage_all_apps,
      actor_id: @app_manager.id,
      subject_id: @org.id,
    )
  end

  context "setting permissions" do
    test "#security_manager has access to setting permission" do
      permission_hash = @org.org_settings_permissions_hash(@security_manager)
      assert permission_hash.values.any?
      assert permission_hash[:is_code_security_manager]
      assert @org.can_view_organization_settings?(@security_manager)
    end

    test "#billing_manager has access to setting permission" do
      permission_hash = @org.org_settings_permissions_hash(@billing_manager)
      assert permission_hash.values.any?
      assert permission_hash[:is_billing_manager]
      assert @org.can_view_organization_settings?(@billing_manager)
    end

    test "#moderator has access to setting permission", skip_enterprise: true do
      permission_hash = @org.org_settings_permissions_hash(@moderator)
      assert permission_hash.values.any?
      assert permission_hash[:is_moderator]
      assert @org.can_view_organization_settings?(@moderator)
    end

    test "#app_manager has access to setting permission" do
      permission_hash = @org.org_settings_permissions_hash(@app_manager)
      assert permission_hash.values.any?
      assert permission_hash[:is_app_manager]
      assert @org.can_view_organization_settings?(@app_manager)
    end

    [
      :read_organization_custom_org_role,
      :write_organization_custom_org_role,
      :read_organization_custom_repo_role,
      :write_organization_custom_repo_role,
      :read_audit_logs,
      :manage_organization_webhooks,
      :manage_organization_oauth_application_policy,
      :manage_organization_ref_rules,
      :write_organization_actions_settings,
      :write_organization_runners_and_runner_groups,
      :read_organization_runner_custom_images,
      :write_organization_runner_custom_images,
      :read_organization_network_configurations,
      :write_organization_network_configurations,
    ].each do |fgp|
      test "#{fgp} FGP assigned to user grants access to settings" do
        grant_custom_org_role(user: @org_role_user, target: @org, fgps: [fgp])
        permission_hash = @org.org_settings_permissions_hash(@org_role_user)
        assert permission_hash.values.any?
        assert permission_hash[:can_view_org_setting]
        assert @org.can_view_organization_settings?(@org_role_user)
      end
      test "#{fgp} FGP assigned to team grants access to settings" do
        grant_custom_org_role(user: @team, target: @org, fgps: [fgp])
        permission_hash = @org.org_settings_permissions_hash(@team_member)
        assert permission_hash.values.any?
        assert permission_hash[:can_view_org_setting]
        assert @org.can_view_organization_settings?(@team_member)
      end
    end

    test "#owner has access to setting permission" do
      permission_hash = @org.org_settings_permissions_hash(@owner)
      assert permission_hash.values.any?
      assert @org.can_view_organization_settings?(@owner)
    end

    test "#random user has no access to setting permission" do
      permission_hash = @org.org_settings_permissions_hash(@rando)
      refute permission_hash.values.any?
      refute @org.can_view_organization_settings?(@rando)
    end
  end
end
