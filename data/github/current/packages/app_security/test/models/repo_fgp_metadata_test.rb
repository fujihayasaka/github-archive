# typed: true
# frozen_string_literal: true

require "test_helper"

class RepoFgpMetadataTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  test "custom repo role enabled FGPs have metadata" do
    Permissions::FineGrainedPermissionIm.org_fgps_for_custom_roles.each do |fgp|
      refute_empty fgp.description
      refute_empty fgp.category
    end
  end

  test "valid FGP label returns appropriate metadata" do
    valid_fgp = RepoFgpMetadata.for(:manage_settings_merge_types)

    assert_equal :repository, valid_fgp.category
    assert_equal "Manage pull request merging settings", valid_fgp.description
  end

  test "invalid FGP label does not blow up" do
    invalid_fgp = RepoFgpMetadata.for(:foo)

    assert_equal :unknown, invalid_fgp.category
    assert_equal "unknown", invalid_fgp.description
  end

  test "all categories are represented in CATEGORY_ORDER" do
    categories = Permissions::FineGrainedPermissionIm.repo_fgps_for_custom_roles.map { |fgp| fgp.category&.to_sym }.uniq

    assert_same_elements RepoFgpMetadata::CATEGORY_ORDER, categories
  end

  context ".for_role" do
    test "only returns relevant categories and fgps for a system role" do
      write_role = Role.write_role

      metadata = RepoFgpMetadata.for_role(write_role)

      refute metadata["Repository"].include?("Manage Webhooks")
      assert metadata["Repository"].include?("Set milestones")
    end

    test "is empty for read" do
      read_role = Role.read_role

      metadata = RepoFgpMetadata.for_role(read_role)
      assert_empty metadata
    end

    test "can display them for a custom role" do
      custom_role = create_custom_role(owner: create(:business_plus_organization), base_role: :read, fgps: [:set_milestone])

      metadata = RepoFgpMetadata.for_role(custom_role)
      assert_equal ["Repository"], metadata.keys
      assert_equal ["Set milestones"], metadata["Repository"]
    end
  end
end
