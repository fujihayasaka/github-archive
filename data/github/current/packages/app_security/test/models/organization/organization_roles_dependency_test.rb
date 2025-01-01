# typed: true
# frozen_string_literal: true
require "test_helper"

class Organization::OrganizationRolesDependencyTest < GitHub::TestCase

  fixtures do
    @org_admin = create(:user, login: "org-admin")
    @member = create(:user, login: "org-member")
    @org = create(:business_plus_organization, admin: @org_admin)

    @org.add_member(@member)

    @custom_role = create(:custom_organization_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization")
    @all_repo_role = OrganizationRole.all_repo_write_role
  end

  context "#grant_org_role" do
    test "grants the role to the user" do
      result = @org.grant_org_role(assignee: @member, role: @custom_role)
      assert result.success?

      user_role = UserRole.find_by!(role_id: @custom_role.id, actor_id: @member.id)
      assert_equal @custom_role, user_role.role
      assert_equal @member, user_role.actor
      assert_equal "Organization", user_role.target_type
    end

    test "grants an all repo role to a user" do
      result = @org.grant_org_role(assignee: @member, role: @all_repo_role)
      assert result.success?

      user_role = UserRole.find_by!(role_id: @all_repo_role.id, actor_id: @member.id)
      assert_equal @all_repo_role, user_role.role
      assert_equal @member, user_role.actor
      assert_equal "Organization", user_role.target_type
      assert_equal "Repository", user_role.role&.base_role&.target_type
    end

    test "does not write ability record when granting an all repo role" do
      refute @org.writable_by?(@member)

      result = @org.grant_org_role(assignee: @member, role: @all_repo_role)
      assert result.success?

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

      # system role
      result = @org.grant_org_role(assignee: @member, role: Role.read_role)
      refute result.success?
      refute UserRole.find_by(role_id: Role.read_role, actor_id: @member.id).present?
    end

    test "returns failure if role is not a Organization Role" do
      custom_repo_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization")
      result = @org.grant_org_role(assignee: @member, role: custom_repo_role)
      refute result.success?
      assert_match /Role needs to be an organization role/, result.reason
      refute_match /#{custom_repo_role.name}/, result.reason
      refute UserRole.find_by(role_id: custom_repo_role.id, actor_id: @member.id).present?
    end

    test "returns failure if role is an Enterprise Role" do
      mod_sys_roles = Role::SYSTEM_ROLES + %w(test_enterprise_role)
      Role.stub_const(:SYSTEM_ROLES, mod_sys_roles) do # We don't have a real enterprise role yet
        ent_role = Role.create!(
          name: "test_enterprise_role",
          target_type: "Business"
        )

        result = @org.grant_org_role(assignee: @member, role: ent_role)
        refute result.success?
        assert_match /Role needs to be an organization role/, result.reason
        refute_match /#{ent_role.name}/, result.reason
        refute UserRole.find_by(role_id: ent_role.id, actor_id: @member.id).present?
      end
    end
  end

  context "#revoke_org_role" do
    test "revokes the role from the user" do
      # assign the role first
      result = @org.grant_org_role(assignee: @member, role: @custom_role)
      assert_predicate result, :success?

      result = @org.revoke_org_role(assignee: @member, role: @custom_role)
      assert result.success?

      user_role = UserRole.find_by(role_id: @custom_role.id, actor_id: @member.id)
      assert_nil user_role
    end

    test "revokes an all repo role from a user" do
      result = @org.grant_org_role(assignee: @member, role: @all_repo_role)
      assert result.success?

      result = @org.revoke_org_role(assignee: @member, role: @all_repo_role)
      assert result.success?

      user_role = UserRole.find_by(role_id: @all_repo_role.id, actor_id: @member.id)
      assert_nil user_role
    end
  end

  context "#revoke_all_org_roles" do
    test "revokes all the roles from the user" do
      custom_role2 = create(:custom_organization_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization")

      # assign the roles first
      result = @org.grant_org_role(assignee: @member, role: @custom_role)
      assert_predicate result, :success?

      result = @org.grant_org_role(assignee: @member, role: custom_role2)
      assert_predicate result, :success?

      result = @org.grant_org_role(assignee: @member, role: @all_repo_role)
      assert_predicate result, :success?

      # revoke all roles
      result = @org.revoke_all_org_roles(assignee: @member)
      assert result.success?

      assert_nil UserRole.find_by(role_id: @custom_role.id, actor_id: @member.id)
      assert_nil UserRole.find_by(role_id: custom_role2.id, actor_id: @member.id)
      assert_nil UserRole.find_by(role_id: @all_repo_role.id, actor_id: @member.id)
    end
  end
end
