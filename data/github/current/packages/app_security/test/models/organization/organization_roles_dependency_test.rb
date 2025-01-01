# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::OrganizationRolesDependencyTest < GitHub::TestCase

  fixtures do
    @business = create :global_business

    @org_admin = create(:user, login: "org-admin")
    @member = create(:user, login: "org-member")
    @org = create(:business_plus_organization, admin: @org_admin)
    @team = create(:team, organization: @org)

    @biz_org = create(:business_plus_organization, admin: @org_admin, business: @business)
    @biz_org_not_selected = create(:business_plus_organization, admin: @org_admin, business: @business)

    @business_team_all_orgs = create(:business_team, business: @business, organization_selection_type: :all)
    @business_team_select_orgs = create(:business_team, business: @business, organization_selection_type: :selected)
    @business_team_biz_org_assignment = BusinessTeamOrgAssignment.create!(business_team: @business_team_select_orgs, organization: @biz_org)
    @business_team_no_orgs = create(:business_team, business: @business, organization_selection_type: :disabled)

    @enterprise_team = create(:enterprise_team, business: @business)
    @et_org_team = create(:team, organization: @org)
    EnterpriseTeamOrganizationMapping.create(enterprise_team: @enterprise_team, organization: @org, team: @et_org_team)

    @org.add_member(@member)

    @custom_role = create(:custom_organization_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization")
    @custom_biz_org_role = create(:custom_organization_role, :with_extra_permissions, owner_id: @biz_org.id, owner_type: "Organization")
    @custom_role_not_selected = create(:custom_organization_role, :with_extra_permissions, owner_id: @biz_org_not_selected.id, owner_type: "Organization")
    @all_repo_role = OrganizationRole.all_repo_write_role
  end

  context "#grant_org_role" do
    test "grants the role to the user" do
      result = @org.grant_org_role(assignee: @member, role: @custom_role)
      assert_predicate result, :success?

      user_role = UserRole.find_by!(role_id: @custom_role.id, actor_id: @member.id)
      assert_equal @custom_role, user_role.role
      assert_equal @member, user_role.actor
      assert_equal "Organization", user_role.target_type
    end

    test "grants an all repo role to a user" do
      result = @org.grant_org_role(assignee: @member, role: @all_repo_role)
      assert_predicate result, :success?

      user_role = UserRole.find_by!(role_id: @all_repo_role.id, actor_id: @member.id)
      assert_equal @all_repo_role, user_role.role
      assert_equal @member, user_role.actor
      assert_equal "Organization", user_role.target_type
      assert_equal "Repository", user_role.role&.base_role&.target_type
    end

    test "does not write ability record when granting an all repo role" do
      refute @org.writable_by?(@member)

      result = @org.grant_org_role(assignee: @member, role: @all_repo_role)
      assert_predicate result, :success?

      user_role = UserRole.find_by(role_id: @all_repo_role.id, actor_id: @member.id)
      refute_nil user_role
      refute @org.writable_by?(@member), "assigning an all repo role should not create an ability record on the organization"
    end

    test "returns failure if user is not member" do
      rando = create(:user)
      result = @org.grant_org_role(assignee: rando, role: @custom_role)
      refute result.success?
      assert_match /#{rando.login} is not a member of the organization/, result.reason
      refute UserRole.find_by(role_id: @custom_role.id, actor_id: rando.id).present?
    end

    test "returns failure if the team belongs to a different org" do
      other_org = create(:business_plus_organization, admin: @org_admin)
      other_team = create(:team, organization: other_org)

      result = @org.grant_org_role(assignee: other_team, role: @custom_role)
      refute result.success?
      assert_match /Invalid team for the organization/, result.reason
      refute UserRole.find_by(role_id: @custom_role.id, actor_id: other_team.id).present?
    end

    test "returns failure if role is not valid" do
      other_org = create(:business_plus_organization, admin: @org_admin)

      # role from different org
      other_org_custom_role = create(:custom_organization_role, :with_extra_permissions, owner_id: other_org.id, owner_type: "Organization")
      result = @org.grant_org_role(assignee: @member, role: other_org_custom_role)
      refute result.success?
      assert_match /Role is invalid/, result.reason
      refute_match /#{other_org_custom_role.name}/, result.reason
      refute UserRole.find_by(role_id: other_org_custom_role.id, actor_id: @member.id).present?
    end

    test "grants org role to business team when org selection type is :all" do
      result = @biz_org.grant_org_role(assignee: @business_team_all_orgs, role: @custom_biz_org_role)
      if @business.feature_enabled?(:enterprise_teams_org_roles)
        assert_predicate result, :success?

        user_role = UserRole.find_by!(role_id: @custom_biz_org_role.id, actor_id: @business_team_all_orgs.id)
        assert_equal @custom_biz_org_role, user_role.role
        # we expect this to work with https://github.com/github/authz-exp/issues/205
        # assert_equal business_team, user_role.actor
        assert_equal "Organization", user_role.target_type
      else
        refute result.success?
      end
    end

    test "grants org role to business team associated with org when type is :selected" do
      result_selected = @biz_org.grant_org_role(assignee: @business_team_select_orgs, role: @custom_biz_org_role)
      if @business.feature_enabled?(:enterprise_teams_org_roles)
        assert_predicate result_selected, :success?
        user_role = UserRole.find_by!(role_id: @custom_biz_org_role.id, actor_id: @business_team_select_orgs.id, target_id: @biz_org.id)
        assert_equal @custom_biz_org_role, user_role.role
        # we expect this to work with https://github.com/github/authz-exp/issues/205
        # assert_equal business_team, user_role.actor
        assert_equal "Organization", user_role.target_type
      else
        refute result_selected.success?
      end
    end

    test "does not grant org role to business team not associated with org when type is :selected" do
      result_not_selected = @biz_org_not_selected.grant_org_role(assignee: @business_team_select_orgs, role: @custom_role_not_selected)
      refute result_not_selected.success?
      assert_match /Invalid team for the organization/, result_not_selected.reason
      refute UserRole.find_by(role_id: @custom_role_not_selected.id, actor_id: @business_team_select_orgs.id, target_id: @biz_org_not_selected.id).present?
    end

    test "does not grant org role to business team when org selection is :disabled" do
      result = @biz_org.grant_org_role(assignee: @business_team_no_orgs, role: @custom_biz_org_role)
      refute result.success?
      assert_match /Invalid team for the organization/, result.reason
      refute UserRole.find_by(role_id: @custom_biz_org_role.id, actor_id: @business_team_no_orgs.id).present?
    end

    test "grants an all repo role to a business team when org selection is :all" do
      result = @biz_org.grant_org_role(assignee: @business_team_all_orgs, role: @all_repo_role)
      if @business.feature_enabled?(:enterprise_teams_org_roles)
        assert_predicate result, :success?

        user_role = UserRole.find_by!(role_id: @all_repo_role.id, actor_id: @business_team_all_orgs.id)
        assert_equal @all_repo_role, user_role.role
        # we expect this to work with https://github.com/github/authz-exp/issues/205
        # assert_equal @business_team_all_orgs, user_role.actor
        assert_equal "Organization", user_role.target_type
        assert_equal "Repository", user_role.role&.base_role&.target_type
      else
        refute result.success?
      end
    end

    test "grants an all repo role to a business team associated with org when type is :selected" do
      result_selected = @biz_org.grant_org_role(assignee: @business_team_select_orgs, role: @all_repo_role)
      if @business.feature_enabled?(:enterprise_teams_org_roles)
        assert_predicate result_selected, :success?
        user_role = UserRole.find_by!(role_id: @all_repo_role.id, actor_id: @business_team_select_orgs.id, target_id: @biz_org.id)
        assert_equal @all_repo_role, user_role.role
        # we expect this to work with https://github.com/github/authz-exp/issues/205
        # assert_equal business_team, user_role.actor
        assert_equal "Organization", user_role.target_type
      else
        refute result_selected.success?
      end
    end
  end

  context "#revoke_org_role" do
    context "when the assignee is a user" do
      test "revokes a role" do
        result = @org.grant_org_role(assignee: @member, role: @custom_role)
        assert_predicate result, :success?

        result = @org.revoke_org_role(assignee: @member, role: @custom_role)
        assert_predicate result, :success?

        assert_nil UserRole.find_by(role_id: @custom_role.id, actor_id: @member.id)
      end

      test "revokes an all repo role" do
        result = @org.grant_org_role(assignee: @member, role: @all_repo_role)
        assert_predicate result, :success?

        result = @org.revoke_org_role(assignee: @member, role: @all_repo_role)
        assert_predicate result, :success?

        assert_nil UserRole.find_by(role_id: @all_repo_role.id, actor_id: @member.id)
      end

      test "revokes the security manager role" do
        result = @org.grant_org_role(assignee: @member, role: Role.security_manager_role)
        assert_predicate result, :success?

        result = @org.revoke_org_role(assignee: @member, role: Role.security_manager_role)
        assert_predicate result, :success?

        assert_nil UserRole.find_by(role_id: Role.security_manager_role.id, actor_id: @member.id)
      end
    end

    context "when the assignee is a team" do
      test "revokes a role" do
        result = @org.grant_org_role(assignee: @team, role: @custom_role)
        assert_predicate result, :success?

        result = @org.revoke_org_role(assignee: @team, role: @custom_role)
        assert_predicate result, :success?

        assert_nil UserRole.find_by(role_id: @custom_role.id, actor_id: @team.id)
      end

      test "revokes an all repo role" do
        result = @org.grant_org_role(assignee: @team, role: @all_repo_role)
        assert_predicate result, :success?

        result = @org.revoke_org_role(assignee: @team, role: @all_repo_role)
        assert_predicate result, :success?

        assert_nil UserRole.find_by(role_id: @all_repo_role.id, actor_id: @team.id)
      end

      test "returns failure if the team belongs to a different org" do
        other_org = create(:business_plus_organization, admin: @org_admin)
        other_team = create(:team, organization: other_org)

        result = @org.revoke_org_role(assignee: other_team, role: @custom_role)
        refute result.success?
        assert_match /Team is not part of the organization/, result.reason
        refute UserRole.find_by(role_id: @custom_role.id, actor_id: other_team.id).present?
      end

      test "revokes the security manager role" do
        result = @org.grant_org_role(assignee: @team, role: Role.security_manager_role)
        assert_predicate result, :success?

        result = @org.revoke_org_role(assignee: @team, role: Role.security_manager_role)
        assert_predicate result, :success?

        assert_nil UserRole.find_by(role_id: Role.security_manager_role.id, actor_id: @team.id)
      end

      context "managed by an enterprise team" do
        test "revokes the security manager role" do
          EnterpriseTeam.expects(:enabled_for_organizations?).at_least_once.returns(true)

          result = @org.grant_org_role(assignee: @et_org_team, role: Role.security_manager_role)
          assert_predicate result, :success?

          result = @org.revoke_org_role(assignee: @et_org_team, role: Role.security_manager_role)
          assert_predicate result, :success?

          assert_nil UserRole.find_by(role_id: Role.security_manager_role.id, actor_id: @et_org_team.id)
        end

        test "returns failure if trying to revoke the security manager role when the enterprise team is an enterprise security manager team" do
          EnterpriseTeam.expects(:enabled_for_organizations?).at_least_once.returns(true)

          result = ::SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team)
          assert ::SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)

          result = @org.grant_org_role(assignee: @et_org_team, role: Role.security_manager_role)
          assert_predicate result, :success?

          result = @org.revoke_org_role(assignee: @et_org_team, role: Role.security_manager_role)
          refute result.success?
          assert_match /Role cannot be revoked from an enterprise security manager team/, result.reason

          refute_nil UserRole.find_by(role_id: Role.security_manager_role.id, actor_id: @et_org_team.id)
        end
      end

      context "assignee is a business team" do
        test "revokes a single role" do
          result = @biz_org.grant_org_role(assignee: @business_team_all_orgs, role: @custom_biz_org_role)
          if @business.feature_enabled?(:enterprise_teams_org_roles)
            assert_predicate result, :success?

            result = @biz_org.revoke_org_role(assignee: @business_team_all_orgs, role: @custom_biz_org_role)
            assert_predicate result, :success?

            assert_nil UserRole.find_by(role_id: @custom_biz_org_role.id, actor_id: @business_team_all_orgs.id)
          else
            refute result.success?
          end
        end
      end
    end
  end

  context "#revoke_all_org_roles" do
    context "when the assignee is a user" do
      test "revokes all the roles" do
        custom_role2 = create(:custom_organization_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization")

        # assign the roles first
        result = @org.grant_org_role(assignee: @member, role: Role.security_manager_role)
        assert_predicate result, :success?

        result = @org.grant_org_role(assignee: @member, role: @custom_role)
        assert_predicate result, :success?

        result = @org.grant_org_role(assignee: @member, role: custom_role2)
        assert_predicate result, :success?

        result = @org.grant_org_role(assignee: @member, role: @all_repo_role)
        assert_predicate result, :success?

        # revoke all roles
        result = @org.revoke_all_org_roles(assignee: @member)
        assert_predicate result, :success?

        assert_nil UserRole.find_by(role_id: Role.security_manager_role.id, actor_id: @member.id)
        assert_nil UserRole.find_by(role_id: @custom_role.id, actor_id: @member.id)
        assert_nil UserRole.find_by(role_id: custom_role2.id, actor_id: @member.id)
        assert_nil UserRole.find_by(role_id: @all_repo_role.id, actor_id: @member.id)
      end
    end

    context "when the assignee is a team" do
      test "revokes all the roles" do
        custom_role2 = create(:custom_organization_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization")

        # assign the roles first
        result = @org.grant_org_role(assignee: @team, role: Role.security_manager_role)
        assert_predicate result, :success?

        result = @org.grant_org_role(assignee: @team, role: @custom_role)
        assert_predicate result, :success?

        result = @org.grant_org_role(assignee: @team, role: custom_role2)
        assert_predicate result, :success?

        result = @org.grant_org_role(assignee: @team, role: @all_repo_role)
        assert_predicate result, :success?

        # revoke all roles
        result = @org.revoke_all_org_roles(assignee: @team)
        assert_predicate result, :success?

        assert_nil UserRole.find_by(role_id: Role.security_manager_role.id, actor_id: @team.id)
        assert_nil UserRole.find_by(role_id: @custom_role.id, actor_id: @team.id)
        assert_nil UserRole.find_by(role_id: custom_role2.id, actor_id: @team.id)
        assert_nil UserRole.find_by(role_id: @all_repo_role.id, actor_id: @team.id)
      end

      context "when the assignee is a business team" do
        test "revokes all the roles", skip_if_feature_disabled: :enterprise_teams_org_roles do
          custom_role2 = create(:custom_organization_role, :with_extra_permissions, owner_id: @biz_org.id, owner_type: "Organization")

          # assign the roles first
          result = @biz_org.grant_org_role(assignee: @business_team_all_orgs, role: Role.security_manager_role)
          assert_predicate result, :success?

          result = @biz_org.grant_org_role(assignee: @business_team_all_orgs, role: @custom_biz_org_role)
          assert_predicate result, :success?

          result = @biz_org.grant_org_role(assignee: @business_team_all_orgs, role: custom_role2)
          assert_predicate result, :success?

          result = @biz_org.grant_org_role(assignee: @business_team_all_orgs, role: @all_repo_role)
          assert_predicate result, :success?

          # revoke all roles
          result = @biz_org.revoke_all_org_roles(assignee: @business_team_all_orgs)
          assert_predicate result, :success?

          assert_nil UserRole.find_by(role_id: Role.security_manager_role.id, actor_id: @business_team_all_orgs.id)
          assert_nil UserRole.find_by(role_id: @custom_role.id, actor_id: @business_team_all_orgs.id)
          assert_nil UserRole.find_by(role_id: custom_role2.id, actor_id: @business_team_all_orgs.id)
          assert_nil UserRole.find_by(role_id: @all_repo_role.id, actor_id: @business_team_all_orgs.id)
        end
      end

      context "managed by an enterprise team" do
        test "revokes all the roles including security manager" do
          EnterpriseTeam.expects(:enabled_for_organizations?).at_least_once.returns(true)

          # assign the roles first
          result = @org.grant_org_role(assignee: @et_org_team, role: Role.security_manager_role)
          assert_predicate result, :success?

          result = @org.grant_org_role(assignee: @et_org_team, role: @custom_role)
          assert_predicate result, :success?

          result = @org.grant_org_role(assignee: @et_org_team, role: @all_repo_role)
          assert_predicate result, :success?

          # revoke all roles
          result = @org.revoke_all_org_roles(assignee: @et_org_team)
          assert_predicate result, :success?

          assert_nil UserRole.find_by(role_id: Role.security_manager_role.id, actor_id: @et_org_team.id)
          assert_nil UserRole.find_by(role_id: @custom_role.id, actor_id: @et_org_team.id)
          assert_nil UserRole.find_by(role_id: @all_repo_role.id, actor_id: @et_org_team.id)
        end

        test "revokes all the roles except security manager when the enterprise team is an enterprise security manager team" do
          EnterpriseTeam.expects(:enabled_for_organizations?).at_least_once.returns(true)

          # assign the roles first
          result = ::SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team)
          assert ::SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)

          result = @org.grant_org_role(assignee: @et_org_team, role: Role.security_manager_role)
          assert_predicate result, :success?

          result = @org.grant_org_role(assignee: @et_org_team, role: @custom_role)
          assert_predicate result, :success?

          result = @org.grant_org_role(assignee: @et_org_team, role: @all_repo_role)
          assert_predicate result, :success?

          # revoke all roles except security manager
          result = @org.revoke_all_org_roles(assignee: @et_org_team)
          assert_predicate result, :success?

          refute_nil UserRole.find_by(role_id: Role.security_manager_role.id, actor_id: @et_org_team.id)
          assert_nil UserRole.find_by(role_id: @custom_role.id, actor_id: @et_org_team.id)
          assert_nil UserRole.find_by(role_id: @all_repo_role.id, actor_id: @et_org_team.id)
        end
      end
    end
  end
end
