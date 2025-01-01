# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseFgpMetadataTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    GitHub.flipper[:custom_enterprise_role_feature].enable
  end

  test "custom enterprise role enabled FGPs have metadata" do
    custom_role_fgps = Permissions::FineGrainedPermissionIm.enterprise_fgps_for_custom_roles.map { |fgp| fgp.action.to_sym }
    assert_same_elements custom_role_fgps, EnterpriseFgpMetadata::DESCRIPTIONS.keys
    assert_same_elements custom_role_fgps, EnterpriseFgpMetadata::CATEGORIES.values.flatten
  end

  test "invalid FGP label does not blow up" do
    invalid_fgp = EnterpriseFgpMetadata.for(:foo)

    assert_equal :unknown, invalid_fgp.category
    assert_equal "unknown", invalid_fgp.description
  end

  context ".for_role" do
    test "can display them for a custom enterprise role" do
      fgp = Permissions::FineGrainedPermissionIm.new("enterprise_test_fgp", target_type: "Business", custom_roles_enabled: true)
      Permissions::FineGrainedPermissionIm.with_testing_permission(fgp) do
        business = create(:business)
        EnterpriseRole.stubs(:custom_role_limit_for_enterprise).returns(5)
        custom_role = create_custom_enterprise_role(owner: business, fgps: [fgp.action])

        # Adding to the Descritption and Category Constants
        stub_metadata = {
          DESCRIPTIONS: { "#{fgp.action.to_sym}": "Test FGP" },
          CATEGORIES: { general: [fgp.action.to_sym] },
        }

        EnterpriseFgpMetadata.stub_consts(stub_metadata) do
          metadata = EnterpriseFgpMetadata.for_role(custom_role)
          assert_equal metadata.keys, ["General"]
          assert_equal metadata["General"], ["Test FGP"]
        end
      end
    end
  end
end
