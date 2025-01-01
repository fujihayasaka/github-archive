# typed: true
# frozen_string_literal: true

require "test_helper"

class FgpMetadataTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  test "only custom repo role enabled FGPs have metadata" do
    custom_role_fgps = Permissions::FineGrainedPermissionIm.repo_fgps_for_custom_roles.map { |fgp| fgp.action.to_sym }
    assert_same_elements custom_role_fgps, FgpMetadata::DESCRIPTIONS.keys
    assert_same_elements custom_role_fgps, FgpMetadata::CATEGORIES.values.flatten
  end

  test "valid FGP label returns appropriate metadata" do
    valid_fgp = FgpMetadata.for(:manage_settings_merge_types)

    assert_equal :repository, valid_fgp.category
    assert_equal "Manage pull request merging settings", valid_fgp.description
  end

  test "invalid FGP label does not blow up" do
    invalid_fgp = FgpMetadata.for(:foo)

    assert_equal :unknown, invalid_fgp.category
    assert_equal "unknown", invalid_fgp.description
  end

  context ".for_role" do
    test "only returns relevant categories and fgps for a system role" do
      write_role = Role.write_role

      metadata = FgpMetadata.for_role(write_role)

      refute metadata["Repository"].include?("Manage Webhooks")
      assert metadata["Repository"].include?("Set milestones")
    end

    test "is empty for read" do
      read_role = Role.read_role

      metadata = FgpMetadata.for_role(read_role)
      assert_empty metadata
    end

    test "can display them for a custom role" do
      custom_role = create_custom_role(owner: create(:business_plus_organization), base_role: :read, fgps: [:set_milestone])

      metadata = FgpMetadata.for_role(custom_role)
      assert_equal ["Repository"], metadata.keys
      assert_equal ["Set milestones"], metadata["Repository"]
    end
  end
end
