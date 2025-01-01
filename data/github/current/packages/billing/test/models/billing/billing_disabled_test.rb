# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingDisabledTest < GitHub::TestCase
  context "ActionsPermissionTest" do
    context "#allowed?" do
      test "true for private repos if user is on a legacy plan" do
        user = create(:user, plan: "bronze", disabled: false)

        assert Billing::ActionsPermission.new(user).allowed?(public: false)
        assert Billing::ActionsPermission.new(user).allowed?
      end

      test "true if the user is on a legacy plan, even if they're not disabled" do
        user = create(:user, plan: "bronze", disabled: false)
        assert Billing::ActionsPermission.new(user).allowed?
      end
    end

    context "#status" do
      test "allowed is true if the user is on a legacy plan, even if they're not disabled" do
        user = create(:user, plan: "bronze", disabled: false)
        status = Billing::ActionsPermission.new(user).status

        assert status[:allowed]
        assert_empty status[:error]
      end
    end

    context "#usage_allowed" do
      test "returns true when private usage for a Legacy plan" do
        user = create(:user, plan: "bronze", disabled: false)
        assert Billing::ActionsPermission.new(user).usage_allowed?(public: false)
      end
    end
  end

  context "PackageRegistryPermissionTest" do
    context "#allowed?" do
      test "allowed when plan is legacy and repo is private" do
        owner = create(:user, plan: :silver, disabled: false)
        assert Billing::PackageRegistryPermission.new(owner).allowed?(public: false)
        assert Billing::PackageRegistryPermission.new(owner).allowed?
      end
    end

    context "#status" do
      test "allowed when the owner is enabled, but their plan is not eligible for GPR" do
        owner = create(:user, plan: :silver, disabled: false)
        result = Billing::PackageRegistryPermission.new(owner).status
        assert result[:allowed]
        assert_empty result[:error]
      end
    end

    context "#download_allowed?" do
      test "return true for private when owner has a legacy plan" do
        owner = create(:user, plan: :silver, disabled: false)
        assert Billing::PackageRegistryPermission.new(owner).download_allowed?(bytes: 1, public: false)
      end
    end

    context "#storage_allowed?" do
      test "return true for private when owner has a legacy plan" do
        owner = create(:user, plan: :silver, disabled: false)
        assert Billing::PackageRegistryPermission.new(owner).storage_allowed?(bytes: 1, public: false)
      end
    end
  end
end unless GitHub.billing_enabled?
