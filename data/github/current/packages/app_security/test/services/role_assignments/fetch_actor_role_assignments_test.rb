# typed: true
# frozen_string_literal: true

require "test_helper"

class RoleAssignments::FetchActorRoleAssignmentsTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    enable_feature_flag(:custom_enterprise_role_feature)
    enable_feature_flag(:enterprise_teams_crud)

    @business = create(:business)
    @business_team = create(:business_team, business: @business)

    @enterprise_role = EnterpriseRole.create!(name: "Enterprise role", owner: @business, owner_type: @business.class, description: "ent desc")

    Permissions::Granters::RoleGranter.new(actor: @business_team, target: @business, role: @enterprise_role).grant!
  end

  context ".paginate_enterprise_role_assignments" do
    test "includes directly assigned roles" do
      result = RoleAssignments::FetchActorRoleAssignments.new(actor: @business_team).paginate_enterprise_role_assignments(page: 1)

      assert_equal @business_team.id, result.actor.id
      assert_equal 1, result.role_assignments.size
      assert_role_attributes @enterprise_role, result.role_assignments[0]
    end

    test "orders by role id and paginates correctly" do
      ent_role_2 = EnterpriseRole.create!(name: "Enterprise role 2", owner: @business, owner_type: @business.class, description: "ent 2 desc")
      ent_role_3 = EnterpriseRole.create!(name: "Enterprise role 3", owner: @business, owner_type: @business.class, description: "ent 3 desc")
      Permissions::Granters::RoleGranter.new(actor: @business_team, target: @business, role: ent_role_2).grant!
      Permissions::Granters::RoleGranter.new(actor: @business_team, target: @business, role: ent_role_3).grant!

      RoleAssignments::FetchActorRoleAssignments.stub_const(:PAGE_SIZE, 2) do
        fetcher = RoleAssignments::FetchActorRoleAssignments.new(actor: @business_team)

        result_1 = fetcher.paginate_enterprise_role_assignments(page: 1)
        result_2 = fetcher.paginate_enterprise_role_assignments(page: 2)

        assert_equal 2, result_1.role_assignments.size
        assert_role_attributes @enterprise_role, result_1.role_assignments[0]
        assert_role_attributes ent_role_2, result_1.role_assignments[1]
        assert_equal 1, result_2.role_assignments.size
        assert_role_attributes ent_role_3, result_2.role_assignments[0]

      end
    end

    test "returns result with no roles" do
      disable_feature_flag(:enterprise_teams_crud)
      disable_feature_flag(:erp_staffship)
      disable_feature_flag(:erp_preview)

      result = RoleAssignments::FetchActorRoleAssignments.new(actor: @business_team).paginate_enterprise_role_assignments(page: 1)

      assert_equal @business_team.id, result.actor.id
      assert_empty result.role_assignments
    end

    test "only includes enterprise roles" do
      org = create(:business_plus_organization)
      org_role = OrganizationRole.create!(name: "Org role", owner: org, owner_type: org.class, description: "org desc")
      Permissions::Granters::RoleGranter.new(actor: @business_team, target: org, role: org_role).grant!

      result = RoleAssignments::FetchActorRoleAssignments.new(actor: @business_team).paginate_enterprise_role_assignments(page: 1)

      refute result.role_assignments.any? { |ra| ra.role.id == org_role.id }
    end
  end

  private def assert_role_assignments(expected, result)
    assert_same_elements expected.map(&:id), result.role_assignments.map(&:id)
  end

  private def assert_role_attributes(expected, result)
    assert_equal true, result.directly_assigned
    assert_equal expected.id, result.role.id
    assert_equal expected.name, result.role.name
    assert_equal expected.description, result.role.description
    assert_equal expected.octicon, result.role.octicon
  end
end
