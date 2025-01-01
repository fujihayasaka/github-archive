# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgFgpMetadataTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  test "only custom org role enabled FGPs have metadata" do
    custom_org_role_fgps = Permissions::FineGrainedPermissionIm.org_fgps_for_custom_roles.map { |fgp| fgp.action.to_sym }
    assert_same_elements custom_org_role_fgps, OrgFgpMetadata::DESCRIPTIONS.keys
    assert_same_elements custom_org_role_fgps, OrgFgpMetadata::CATEGORIES.values.flatten
  end

  test "valid FGP label returns appropriate metadata" do
    valid_fgp = OrgFgpMetadata.for(:read_organization_custom_org_role)

    assert_equal :access_management, valid_fgp.category
    assert_equal "View organization roles", valid_fgp.description
  end

  test "invalid FGP label does not blow up" do
    invalid_fgp = OrgFgpMetadata.for(:foo)

    assert_equal :unknown, invalid_fgp.category
    assert_equal "unknown", invalid_fgp.description
  end

  context ".for_role" do
    test "can display them for a custom org role" do
      plan = GitHub.enterprise? ? GitHub::Plan.default_plan.name : GitHub::Plan.business_plus.name
      org = create(:organization, admin: @admin, plan: plan)
      custom_org_role = create_custom_org_role(owner: org, role_description: "Test Org Role", fgps: [:read_organization_custom_org_role])
      metadata = OrgFgpMetadata.for_role(custom_org_role)
      assert_equal ["Access management"], metadata.keys
      assert_equal ["View organization roles"], metadata["Access management"]
    end
  end
end
