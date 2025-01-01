# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::Transfers::PostTransferVisibilityTest < GitHub::TestCase

  fixtures do
    @user = create(:user)

    @integration = create(:integration, default_permissions: { "metadata" => :read })

    @business = create(:business)
    @org = create(:organization, business: @business)
    @enterprise_owned_integration = create(:enterprise_owned_integration, owner: @business, default_permissions: { "metadata" => :read })
  end

  context "#update_required?" do
    test "returns true if the integration is being transferred to an enterprise" do
      transfer_visibility = Integration::Transfers::PostTransferVisibility.new(integration: @integration, target: @business)
      assert transfer_visibility.update_required?
    end

    test "returns true if the integration is being transferred from an enterprise" do
      transfer_visibility = Integration::Transfers::PostTransferVisibility.new(integration: @enterprise_owned_integration, target: @org)
      assert transfer_visibility.update_required?
    end

    test "returns false if the integration is not being transferred to or from an enterprise" do
      transfer_visibility = Integration::Transfers::PostTransferVisibility.new(integration: @integration, target: @org)
      refute transfer_visibility.update_required?
    end
  end

  context "#new_visibility" do
    test "returns the same visibility if the integration is not being transferred to or from an enterprise" do
      transfer_visibility = Integration::Transfers::PostTransferVisibility.new(integration: @integration, target: @org)
      assert_equal @integration.visibility, transfer_visibility.new_visibility
    end

    context "internal_visibility" do
      test "returns 'internal_visibility' if the integration is being transferred to an enterprise" do
        transfer_visibility = Integration::Transfers::PostTransferVisibility.new(integration: @integration, target: @business)
        assert_equal "internal_visibility", transfer_visibility.new_visibility
      end
    end

    context "public_visibility" do
      test "returns 'public_visibility' if the integration with installations is being transferred from an enterprise to a user" do
        make_integration_installation(integration: @enterprise_owned_integration, target: @org)

        transfer_visibility = Integration::Transfers::PostTransferVisibility.new(integration: @enterprise_owned_integration, target: @user)
        assert_equal "public_visibility", transfer_visibility.new_visibility
      end

      test "returns 'public_visibility' if the integration with installations is being transferred from an enterprise to an organization" do
        make_integration_installation(integration: @enterprise_owned_integration, target: @org)

        transfer_visibility = Integration::Transfers::PostTransferVisibility.new(integration: @enterprise_owned_integration, target: @org)
        assert_equal "public_visibility", transfer_visibility.new_visibility
      end

      test "returns 'public_visibility' if the integration without installations is being transferred from an enterprise to EMU user" do
        emu_user = create(:emu)
        emu_business = emu_user.enterprise_managed_business
        emu_business_org = create :enterprise_linked_organization, business: emu_business, admin: emu_user

        integration = create(:enterprise_owned_integration, owner: emu_business, default_permissions: { "metadata" => :read })

        transfer_visibility = Integration::Transfers::PostTransferVisibility.new(integration: integration, target: emu_user)
        assert_equal "public_visibility", transfer_visibility.new_visibility
      end unless GitHub.single_business_environment?

      test "returns 'public_visibility' if the integration without installations is being transferred from an enterprise to EMU organization" do
        emu_user = create(:emu)
        emu_business = emu_user.enterprise_managed_business
        emu_business_org = create :enterprise_linked_organization, business: emu_business, admin: emu_user

        integration = create(:enterprise_owned_integration, owner: emu_business, default_permissions: { "metadata" => :read })

        transfer_visibility = Integration::Transfers::PostTransferVisibility.new(integration: integration, target: emu_business_org)
        assert_equal "public_visibility", transfer_visibility.new_visibility
      end unless GitHub.single_business_environment?
    end

    context "private_visibility" do
      test "returns 'private_visibility' if the integration without installations is being transferred from an enterprise to a user" do
        transfer_visibility = Integration::Transfers::PostTransferVisibility.new(integration: @enterprise_owned_integration, target: @user)
        assert_equal "private_visibility", transfer_visibility.new_visibility
      end

      test "returns 'private_visibility' if the integration without installations is being transferred from an enterprise to an organization" do
        transfer_visibility = Integration::Transfers::PostTransferVisibility.new(integration: @enterprise_owned_integration, target: @org)
        assert_equal "private_visibility", transfer_visibility.new_visibility
      end
    end unless GitHub.multi_tenant_enterprise?
  end
end
