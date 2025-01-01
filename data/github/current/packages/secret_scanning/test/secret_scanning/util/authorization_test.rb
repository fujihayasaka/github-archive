# typed: true
# frozen_string_literal: true

require "test_helper"

class SecretScanningAuthorizationTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @admin = create(:user)

    @org = create(:business_plus_organization, admin: @admin)
    @another_org = create(:business_plus_organization, admin: @admin)

    @org_owned_repo = create(:repository, owner: @org)
    @org.add_member(@user)

    @team = create(:team, organization: @org, privacy: :closed)
  end

  context "get_default_and_custom_roles_from_role_ids" do
    test "separates default and custom roles" do
      # Default repository role
      default_repo_role = Role.read_role

      # Custom repository role
      custom_repo_role = create(:custom_repository_role, owner_id: @org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)

      # Default organization role
      default_org_role = Role.security_manager_role

      # Custom organization role
      custom_org_role = create(:custom_organization_role, owner_id: @org.id, owner_type: "Organization", base_role_id: Role.write_role.id)

      # Include an invalid role ID for good measure. It should get skipped.
      role_ids = [
        default_repo_role.id, custom_repo_role.id, default_org_role.id, custom_org_role.id, T.must(Role.last).id + 1
      ]

      default_roles, custom_roles = SecretScanning::Util::Authorization.get_default_and_custom_roles_from_role_ids(role_ids)

      assert_same_elements [default_repo_role, default_org_role], default_roles
      assert_same_elements [custom_repo_role, custom_org_role], custom_roles
    end
  end

  context "get_org_roles_with_fgp" do
    test "returns org role IDs with the FGP" do
      # Create custom roles for the org, with the FGP
      fgp = :org_review_and_manage_secret_scanning_closure_requests
      custom_org_role_1 = create_custom_org_role(owner: @org, fgps: [fgp], base_role: Role.write_role)
      custom_org_role_2 = create_custom_org_role(owner: @org, fgps: [fgp], base_role: Role.maintain_role)
      # This one doesn't have the FGP
      custom_org_role_3 = create_custom_org_role(owner: @org, fgps: [], base_role: Role.write_role)

      # Create a custom role for another org, with the FGP. This one should not be included
      another_org_custom_role = create_custom_org_role(owner: @another_org, fgps: [fgp], base_role: Role.maintain_role)

      role_ids_with_fgp = SecretScanning::Util::Authorization.get_org_role_ids_with_fgp(@org, fgp)

      assert_includes role_ids_with_fgp, custom_org_role_1.id
      assert_includes role_ids_with_fgp, custom_org_role_2.id

      # Remove these custom roles. What's remaining should be default roles
      role_ids_with_fgp.delete(custom_org_role_1.id)
      role_ids_with_fgp.delete(custom_org_role_2.id)

      role_ids_with_fgp.each do |role_id|
        role = Role.find_by(id: role_id)
        assert role
        # These are the characteristics of default roles
        assert_nil T.must(role).owner_id
        assert_nil T.must(role).owner_type
      end
    end
  end

  context "get_users_with_fgp_via_custom_roles_for_org" do
    test "returns users with the FGP via custom roles" do
      fgp = :org_review_and_manage_secret_scanning_closure_requests

      # Assign users the FGP via a direct custom role assignment
      user1 = create(:user)
      user2 = create(:user)
      @org.add_member(user1)
      @org.add_member(user2)
      grant_custom_org_role(user: user1, target: @org, fgps: [fgp], base_role: Role.write_role)
      grant_custom_org_role(user: user2, target: @org, fgps: [fgp], base_role: Role.maintain_role)

      # Create a team and assign the FGP to the team via a custom role
      team = create(:team, organization: @org, privacy: :closed)
      team_member1 = create(:user)
      team_member2 = create(:user)

      team.add_member(team_member1)
      team.add_member(team_member2)
      # Add a user with a direct assignment to the team, to make sure deduping works
      team.add_member(user1)
      grant_custom_org_role(user: team, target: @org, fgps: [fgp], base_role: Role.write_role)

      expected_user_ids = [user1.id, user2.id, team_member1.id, team_member2.id]

      assert_same_elements expected_user_ids, SecretScanning::Util::Authorization.get_users_with_fgp_via_custom_roles_for_org(@org, fgp)
    end
  end
end
