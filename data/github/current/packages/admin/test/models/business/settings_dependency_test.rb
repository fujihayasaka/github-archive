# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessSettingsDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "bizadmin"
    @org1 = create :business_plus_organization, login: "org1", seats: 5
    @org2 = create :business_plus_organization, login: "org2"

    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @business = create :business, \
        name: "Acme Corp",
        owners: [@owner],
        organizations: [@org1, @org2]
    end
  end

  context "#two_factor_required_organizations" do
    test "returns organizations with two-factor required enabled" do
      @business.organizations.each { |org| org.disable_two_factor_required(actor: @owner) }

      orgs = (1..2).map do
        admin = create :two_factor_credential_user
        org = create :organization, admin: admin
        @business.add_organization(org)
        org.enable_two_factor_required(actor: @owner)
        org
      end

      two_factor_required_orgs = @business.two_factor_required_organizations(value: true)

      assert_equal orgs.size, two_factor_required_orgs.count
      assert_same_elements orgs.map(&:login), two_factor_required_orgs.map(&:login)
    end

    test "returns organizations with default two-factor required setting (default is disabled)" do
      two_factor_not_required_orgs = @business.two_factor_required_organizations(value: false)
      assert_equal @business.organizations.size, two_factor_not_required_orgs.count
      assert_same_elements @business.organizations.map(&:login), two_factor_not_required_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.two_factor_required_organizations(
        value: false,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#saml_configured_organizations" do
    test "returns organizations with SAML SSO configured and enforced" do
      orgs = (1..2).map do
        admin = create :user
        org = create :organization, admin: admin
        create :organization_saml_provider, :enforced, organization: org
        @business.add_organization(org)
        org
      end

      enforced_orgs = @business.saml_configured_organizations(value: "ENFORCED")

      assert_equal orgs.size, enforced_orgs.count
      assert_same_elements orgs.map(&:login), enforced_orgs.map(&:login)
    end

    test "returns organizations with SAML SSO configured but not enforced" do
      orgs = (1..2).map do
        admin = create :user
        org = create :organization, admin: admin
        create :organization_saml_provider, organization: org
        @business.add_organization(org)
        org
      end

      configured_orgs = @business.saml_configured_organizations(value: "CONFIGURED")

      assert_equal orgs.size, configured_orgs.count
      assert_same_elements orgs.map(&:login), configured_orgs.map(&:login)
    end

    test "returns organizations with SAML SSO unconfigured" do
      unconfigured_orgs = @business.saml_configured_organizations(value: "UNCONFIGURED")
      assert_equal @business.organizations.size, unconfigured_orgs.count
      assert_same_elements @business.organizations.map(&:login), unconfigured_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.saml_configured_organizations(
        value: "UNCONFIGURED",
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#team_sync_enabled_orgs" do
    test "returns only orgs which have a pending, ready, or enabled team sync tenant status" do
      team_sync_tenant = create(:team_sync_tenant)
      org_with_team_sync = team_sync_tenant.organization
      org_with_team_sync.update(login: "bbb")

      disabled_team_sync_tenant = create(:team_sync_tenant, status: :disabled)
      org_with_team_sync_disabled = disabled_team_sync_tenant.organization
      org_with_team_sync_disabled.update(login: "ddd")

      @business.add_organization(org_with_team_sync)
      @business.add_organization(org_with_team_sync_disabled)

      assert_same_elements [@org1, @org2, org_with_team_sync, org_with_team_sync_disabled], @business.organizations
      assert_same_elements [org_with_team_sync], @business.team_sync_enabled_orgs
    end
  end

  context "#allow_private_repository_forking_setting_organizations" do
    test "returns organizations with private repository forking enabled" do
      @business.organizations.each { |org| org.block_private_repository_forking(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_private_repository_forking(actor: @owner)
        org
      end

      enabled_orgs = @business.allow_private_repository_forking_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with private repository forking enabled with an enhanced forking policy" do
      @business.organizations.each { |org| org.block_private_repository_forking(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_private_repository_forking(actor: @owner, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
        org
      end

      enabled_orgs = @business.allow_private_repository_forking_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with private repository forking disabled" do
      @business.organizations.each { |org| org.allow_private_repository_forking(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.block_private_repository_forking(actor: @owner)
        org
      end

      disabled_orgs = @business.allow_private_repository_forking_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with default private repository forking setting (default is disabled)" do
      @business.organizations.each { |org| org.allow_private_repository_forking(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      default_orgs = @business.allow_private_repository_forking_setting_organizations(value: false)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.allow_private_repository_forking_setting_organizations(
        value: false,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#members_can_invite_collaborators_setting_organizations" do
    test "returns organizations with members can invite collaborators enabled" do
      @business.organizations.each { |org| org.disallow_members_can_invite_outside_collaborators(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_members_can_invite_outside_collaborators(actor: @owner)
        org
      end

      enabled_orgs = @business.members_can_invite_collaborators_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with members can invite collaborators disabled" do
      @business.organizations.each { |org| org.allow_members_can_invite_outside_collaborators(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.disallow_members_can_invite_outside_collaborators(actor: @owner)
        org
      end

      disabled_orgs = @business.members_can_invite_collaborators_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with default members can invite collaborators setting (default is enabled)" do
      @business.organizations.each { |org| org.disallow_members_can_invite_outside_collaborators(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      default_orgs = @business.members_can_invite_collaborators_setting_organizations(value: true)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.members_can_invite_collaborators_setting_organizations(
        value: true,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#members_can_change_repository_visibility_setting_organizations" do
    test "returns organizations with members can change visibility enabled" do
      @business.organizations.each { |org| org.block_members_from_changing_repo_visibility(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_members_to_change_repo_visibility(actor: @owner)
        org
      end

      enabled_orgs = @business.members_can_change_repository_visibility_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with members can change visibility disabled" do
      @business.organizations.each { |org| org.allow_members_to_change_repo_visibility(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.block_members_from_changing_repo_visibility(actor: @owner)
        org
      end

      disabled_orgs = @business.members_can_change_repository_visibility_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with default members can change visibility setting (default is enabled)" do
      @business.organizations.each { |org| org.block_members_from_changing_repo_visibility(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      default_orgs = @business.members_can_change_repository_visibility_setting_organizations(value: true)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.members_can_change_repository_visibility_setting_organizations(
        value: true,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#members_can_change_project_visibility_setting_organizations" do
    test "returns organizations with members can change visibility enabled" do
      @business.organizations.each { |org| org.block_members_from_changing_project_visibility(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_members_to_change_project_visibility(actor: @owner)
        org
      end

      enabled_orgs = @business.members_can_change_project_visibility_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with members can change visibility disabled" do
      @business.organizations.each { |org| org.allow_members_to_change_project_visibility(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.block_members_from_changing_project_visibility(actor: @owner)
        org
      end

      disabled_orgs = @business.members_can_change_project_visibility_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with members not able to change visibility setting by default" do
      @business.organizations.each { |org| org.allow_members_to_change_project_visibility(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      default_orgs = @business.members_can_change_project_visibility_setting_organizations(value: false)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      @business.organizations.each { |org| org.allow_members_to_change_project_visibility(actor: @owner) }

      ordered_orgs = @business.members_can_change_project_visibility_setting_organizations(
        value: true,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#members_can_delete_repositories_setting_organizations" do
    test "returns organizations with setting enabled" do
      @business.organizations.each { |org| org.disallow_members_can_delete_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_members_can_delete_repositories(actor: @owner)
        org
      end

      enabled_orgs = @business.members_can_delete_repositories_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with setting disabled" do
      @business.organizations.each { |org| org.allow_members_can_delete_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.disallow_members_can_delete_repositories(actor: @owner)
        org
      end

      disabled_orgs = @business.members_can_delete_repositories_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with default setting (default is enabled)" do
      @business.organizations.each { |org| org.disallow_members_can_delete_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      default_orgs = @business.members_can_delete_repositories_setting_organizations(value: true)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.members_can_delete_repositories_setting_organizations(
        value: true,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#members_can_delete_issues_setting_organizations" do
    test "returns organizations with setting enabled" do
      @business.organizations.each { |org| org.disallow_members_can_delete_issues(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_members_can_delete_issues(actor: @owner)
        org
      end

      enabled_orgs = @business.members_can_delete_issues_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with setting disabled" do
      @business.organizations.each { |org| org.allow_members_can_delete_issues(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.disallow_members_can_delete_issues(actor: @owner)
        org
      end

      disabled_orgs = @business.members_can_delete_issues_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with default setting (default is disabled)" do
      @business.organizations.each { |org| org.allow_members_can_delete_issues(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      default_orgs = @business.members_can_delete_issues_setting_organizations(value: false)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.members_can_delete_issues_setting_organizations(
        value: false,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#members_can_update_protected_branches_setting_organizations" do
    test "returns organizations with setting enabled" do
      @business.organizations.each { |org| org.disallow_members_can_update_protected_branches(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_members_can_update_protected_branches(actor: @owner)
        org
      end

      enabled_orgs = @business.members_can_update_protected_branches_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with setting disabled" do
      @business.organizations.each { |org| org.allow_members_can_update_protected_branches(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.disallow_members_can_update_protected_branches(actor: @owner)
        org
      end

      disabled_orgs = @business.members_can_update_protected_branches_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with default setting (default is enabled)" do
      @business.organizations.each { |org| org.disallow_members_can_update_protected_branches(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      default_orgs = @business.members_can_update_protected_branches_setting_organizations(value: true)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.members_can_update_protected_branches_setting_organizations(
        value: true,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#team_discussions_setting_organizations" do
    test "returns organizations with team discussions enabled" do
      @business.organizations.each { |org| org.disallow_team_discussions(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_team_discussions(actor: @owner)
        org
      end

      enabled_orgs = @business.team_discussions_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with team discussions disabled" do
      @business.organizations.each { |org| org.allow_team_discussions(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.disallow_team_discussions(actor: @owner)
        org
      end

      disabled_orgs = @business.team_discussions_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with default team discussions setting (default is enabled)" do
      @business.organizations.each { |org| org.disallow_team_discussions(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      default_orgs = @business.team_discussions_setting_organizations(value: true)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.team_discussions_setting_organizations(
        value: true,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#organization_projects_setting_organizations" do
    test "returns organizations with organization projects enabled" do
      @business.organizations.each { |org| org.disable_organization_projects(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.enable_organization_projects(actor: @owner)
        org
      end

      enabled_orgs = @business.organization_projects_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with organization projects disabled" do
      @business.organizations.each { |org| org.enable_organization_projects(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.disable_organization_projects(actor: @owner)
        org
      end

      disabled_orgs = @business.organization_projects_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with default organization projects setting (default is enabled)" do
      @business.organizations.each { |org| org.disable_organization_projects(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      default_orgs = @business.organization_projects_setting_organizations(value: true)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.organization_projects_setting_organizations(
        value: true,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#repository_projects_setting_organizations" do
    test "returns organizations with repository projects enabled" do
      @business.organizations.each { |org| org.disable_repository_projects(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.enable_repository_projects(actor: @owner)
        org
      end

      enabled_orgs = @business.repository_projects_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with repository projects disabled" do
      @business.organizations.each { |org| org.enable_repository_projects(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.disable_repository_projects(actor: @owner)
        org
      end

      disabled_orgs = @business.repository_projects_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with default repository projects setting (default is enabled)" do
      @business.organizations.each { |org| org.disable_repository_projects(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      default_orgs = @business.repository_projects_setting_organizations(value: true)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.repository_projects_setting_organizations(
        value: true,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#members_can_view_dependency_insights_setting_organizations" do
    test "returns organizations with setting enabled" do
      @business.organizations.each { |org| org.disallow_members_can_view_dependency_insights(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_members_can_view_dependency_insights(actor: @owner)
        org
      end

      enabled_orgs = @business.members_can_view_dependency_insights_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with setting disabled" do
      @business.organizations.each { |org| org.allow_members_can_view_dependency_insights(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.disallow_members_can_view_dependency_insights(actor: @owner)
        org
      end

      disabled_orgs = @business.members_can_view_dependency_insights_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with default setting (default is enabled)" do
      @business.organizations.each { |org| org.disallow_members_can_view_dependency_insights(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      default_orgs = @business.members_can_view_dependency_insights_setting_organizations(value: true)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      ordered_orgs = @business.members_can_view_dependency_insights_setting_organizations(
        value: true,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end

  context "#default_repository_permission_setting_organizations" do
    test "returns organizations with read default repository permission" do
      @business.organizations.each { |org| org.update_default_repository_permission(:none, actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
          @business.add_organization(org)
          org.update_default_repository_permission(:read, actor: @owner)
        end
        org
      end

      test_orgs = @business.default_repository_permission_setting_organizations(value: "read")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "returns organizations with write default repository permission" do
      @business.organizations.each { |org| org.update_default_repository_permission(:none, actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
          @business.add_organization(org)
          org.update_default_repository_permission(:write, actor: @owner)
        end
        org
      end

      test_orgs = @business.default_repository_permission_setting_organizations(value: "write")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "returns organizations with admin default repository permission" do
      @business.organizations.each { |org| org.update_default_repository_permission(:none, actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
          @business.add_organization(org)
          org.update_default_repository_permission(:admin, actor: @owner)
        end
        org
      end

      test_orgs = @business.default_repository_permission_setting_organizations(value: "admin")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "returns organizations with none default repository permission" do
      @business.organizations.each { |org| org.update_default_repository_permission(:read, actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
          @business.add_organization(org)
          org.update_default_repository_permission(:none, actor: @owner)
        end
        org
      end

      test_orgs = @business.default_repository_permission_setting_organizations(value: "none")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "orders results" do
      test_orgs = @business.default_repository_permission_setting_organizations(
        value: "read",
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, test_orgs.map(&:login)
    end
  end

  context "#members_can_create_repositories_organizations" do
    test "returns organizations where users can create public repositories" do
      @business.organizations.each { |org| org.disallow_members_can_create_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_members_can_create_repositories_with_visibilities(actor: @owner,
          public_visibility: true,
          private_visibility: false,
          internal_visibility: false)
        org
      end
      do_not_return_org = create :organization
      @business.add_organization(do_not_return_org)
      do_not_return_org.update_attribute(:plan, "business_plus") unless GitHub.enterprise?
      do_not_return_org.allow_members_can_create_repositories_with_visibilities(actor: @owner,
        public_visibility: false,
        private_visibility: true,
        internal_visibility: true)

      test_orgs = @business.members_can_create_repositories_organizations(visibility: "PUBLIC")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "returns organizations where users can only create private repositories" do
      @business.organizations.each { |org| org.disallow_members_can_create_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.update_attribute(:plan, "business_plus") unless GitHub.enterprise?
        org.allow_members_can_create_repositories_with_visibilities(actor: @owner,
          public_visibility: false,
          private_visibility: true,
          internal_visibility: false)
        org
      end
      do_not_return_org = create :organization
      @business.add_organization(do_not_return_org)
      do_not_return_org.update_attribute(:plan, "business_plus") unless GitHub.enterprise?
      do_not_return_org.allow_members_can_create_repositories_with_visibilities(actor: @owner,
        public_visibility: true,
        private_visibility: false,
        internal_visibility: true)

      test_orgs = @business.members_can_create_repositories_organizations(visibility: "PRIVATE")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "returns organizations where users can only create internal repositories" do
      @business.organizations.each { |org| org.disallow_members_can_create_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.update_attribute(:plan, "business_plus") unless GitHub.enterprise?
        org.allow_members_can_create_repositories_with_visibilities(actor: @owner,
          public_visibility: false,
          private_visibility: false,
          internal_visibility: true)
        org
      end
      do_not_return_org = create :organization
      @business.add_organization(do_not_return_org)
      do_not_return_org.update_attribute(:plan, "business_plus") unless GitHub.enterprise?
      do_not_return_org.allow_members_can_create_repositories_with_visibilities(actor: @owner,
        public_visibility: true,
        private_visibility: true,
        internal_visibility: false)

      test_orgs = @business.members_can_create_repositories_organizations(visibility: "INTERNAL")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "returns organizations where users cannot create repositories" do
      @business.organizations.each { |org| org.allow_members_can_create_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.disallow_members_can_create_repositories(actor: @owner)
        org
      end
      do_not_return_org = create :organization
      @business.add_organization(do_not_return_org)
      do_not_return_org.update_attribute(:plan, "business_plus") unless GitHub.enterprise?
      do_not_return_org.allow_members_can_create_repositories_with_visibilities(actor: @owner,
        public_visibility: false,
        private_visibility: true,
        internal_visibility: false)

      test_orgs = @business.members_can_create_repositories_organizations(visibility: "NONE")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "orders results" do
      @business.organizations.each { |org| org.disallow_members_can_create_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_members_can_create_repositories_with_visibilities(actor: @owner,
          public_visibility: true,
          private_visibility: false,
          internal_visibility: false)
        org
      end
      do_not_return_org = create :organization
      @business.add_organization(do_not_return_org)
      do_not_return_org.update_attribute(:plan, "business_plus") unless GitHub.enterprise?
      do_not_return_org.allow_members_can_create_repositories_with_visibilities(actor: @owner,
        public_visibility: false,
        private_visibility: true,
        internal_visibility: true)

      test_orgs = @business.members_can_create_repositories_organizations(
        visibility: "PUBLIC",
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal orgs.map(&:login).sort.reverse, test_orgs.map(&:login)
    end
  end

  context "#members_can_create_repositories_setting_organizations" do
    test "returns organizations where users can create public and private repositories" do
      @business.organizations.each { |org| org.disallow_members_can_create_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.allow_members_can_create_repositories(actor: @owner)
        org
      end

      test_orgs = @business.members_can_create_repositories_setting_organizations(value: "ALL")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "returns organizations where users can only create private repositories" do
      @business.organizations.each { |org| org.disallow_members_can_create_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.update_attribute(:plan, "business_plus") unless GitHub.enterprise?
        org.disallow_members_can_create_public_repositories(actor: @owner)
        org
      end

      test_orgs = @business.members_can_create_repositories_setting_organizations(value: "PRIVATE")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "returns organizations where users cannot create repositories" do
      @business.organizations.each { |org| org.allow_members_can_create_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.disallow_members_can_create_repositories(actor: @owner)
        org
      end

      test_orgs = @business.members_can_create_repositories_setting_organizations(value: "DISABLED")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "returns organizations with default repository creation setting (default is public and private)" do
      @business.organizations.each { |org| org.disallow_members_can_create_repositories(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org
      end

      test_orgs = @business.members_can_create_repositories_setting_organizations(value: "ALL")

      assert_equal orgs.size, test_orgs.count
      assert_same_elements orgs.map(&:login), test_orgs.map(&:login)
    end

    test "orders results" do
      test_orgs = @business.members_can_create_repositories_setting_organizations(
        value: "ALL",
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, test_orgs.map(&:login)
    end
  end

  context "#restrict_notification_delivery_setting_organizations" do
    test "returns organizations with restriction of email notifications to domain email enabled" do
      create :verifiable_domain, owner: @business, verified: true
      @business.organizations.each { |org| org.disable_notification_restrictions(actor: @owner) }

      orgs = (1..2).map do
        org = create :business_plus_organization
        @business.add_organization(org)
        org.reload
        org.enable_notification_restrictions(actor: @owner)
        org
      end

      enabled_orgs = @business.restrict_notification_delivery_setting_organizations(value: true)

      assert_equal orgs.size, enabled_orgs.count
      assert_same_elements orgs.map(&:login), enabled_orgs.map(&:login)
    end

    test "returns organizations with restriction of email notifications to domain email disabled" do
      create :verifiable_domain, owner: @business, verified: true
      @business.organizations.each { |org| org.enable_notification_restrictions(actor: @owner) }

      orgs = (1..2).map do
        org = create :organization
        @business.add_organization(org)
        org.reload
        org.disable_notification_restrictions(actor: @owner)
        org
      end

      disabled_orgs = @business.restrict_notification_delivery_setting_organizations(value: false)

      assert_equal orgs.size, disabled_orgs.count
      assert_same_elements orgs.map(&:login), disabled_orgs.map(&:login)
    end

    test "returns organizations with default restriction of email notifications to domain email setting (default is disabled)" do
      create :verifiable_domain, owner: @business, verified: true
      @business.organizations.each { |org| org.enable_notification_restrictions(actor: @owner) }

      orgs = (1..2).map do
        org = create :business_plus_organization
        @business.add_organization(org)
        org.reload
        org
      end

      default_orgs = @business.restrict_notification_delivery_setting_organizations(value: false)

      assert_equal orgs.size, default_orgs.count
      assert_same_elements orgs.map(&:login), default_orgs.map(&:login)
    end

    test "orders results" do
      create :verifiable_domain, owner: @business, verified: true
      ordered_orgs = @business.restrict_notification_delivery_setting_organizations(
        value: false,
        order_by_field: "LOGIN",
        order_by_direction: "DESC",
      )

      assert_equal @business.organizations.map(&:login).sort.reverse, ordered_orgs.map(&:login)
    end
  end
end
