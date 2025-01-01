# typed: true
# frozen_string_literal: true

require "test_helper"

class UserRoleBasedPermissionsDependencyTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @org = create(:business_plus_organization)
    @other_org = create(:business_plus_organization)

    @member = create(:user)
    @org.add_member(@member)

    @team = create(:team, organization: @org)
    @team.add_member(@member)

    @org_role_1 = create(:custom_organization_role, owner_id: @org.id, owner_type: "Organization")
    @org_role_2 = create(:custom_organization_role, owner_id: @org.id, owner_type: "Organization")
  end

  context "#org_roles_for" do
    test "returns roles a user has in the org" do
      @org.grant_org_role(assignee: @member, role: @org_role_1)
      @org.grant_org_role(assignee: @member, role: @org_role_2)
      roles = @member.org_roles_for(@org)
      other_org_roles = @member.org_roles_for(@other_org)

      assert_same_elements [@org_role_1, @org_role_2], roles
      assert_empty other_org_roles
    end

    test "does not include roles from teams" do
      @org.grant_org_role(assignee: @member, role: @org_role_1)
      @org.grant_org_role(assignee: @team, role: @org_role_2)
      roles = @member.org_roles_for(@org)

      assert_same_elements [@org_role_1], roles
    end
  end
end
