# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseFgpMetadataTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  setup do
    enable_feature_flag(:custom_enterprise_role_feature)
  end

  test "custom enterprise role enabled FGPs have metadata" do
    Permissions::FineGrainedPermissionIm.enterprise_fgps_for_custom_roles.each do |fgp|
      refute_empty fgp.description
      refute_empty fgp.category
    end
  end

  test "invalid FGP label does not blow up" do
    invalid_fgp = EnterpriseFgpMetadata.for(:foo)

    assert_equal :unknown, invalid_fgp.category
    assert_equal "unknown", invalid_fgp.description
  end

  test "all categories are represented in CATEGORY_ORDER" do
    categories = Permissions::FineGrainedPermissionIm.enterprise_fgps_for_custom_roles.map { |fgp| fgp.category&.to_sym }.uniq

    assert_same_elements categories, EnterpriseFgpMetadata::CATEGORY_ORDER
  end

  context ".for_role" do
    test "can display them for a custom enterprise role" do
      fgp = Permissions::FineGrainedPermissionIm.new("enterprise_test_fgp", target_type: "Business", custom_roles_enabled: true, description: "Test FGP", category: :access_management)
      Permissions::FineGrainedPermissionIm.with_testing_permission(fgp) do
        business = create(:business)
        custom_role = create_custom_enterprise_role(owner: business, fgps: [fgp.action])

        # Adding to the Descritption and Category Constants
        stub_metadata = {
          DESCRIPTIONS: { "#{fgp.action.to_sym}": "Test FGP" },
          CATEGORIES: { general: [fgp.action.to_sym] },
        }

        EnterpriseFgpMetadata.stub_consts(stub_metadata) do
          metadata = EnterpriseFgpMetadata.for_role(custom_role)
          assert_equal metadata.keys, ["Access management"]
          assert_equal metadata["Access management"], ["Test FGP"]
        end
      end
    end
  end
end
