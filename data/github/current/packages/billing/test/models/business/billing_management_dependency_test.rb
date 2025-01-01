# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessBillingManagementDependencyTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
    @user = create(:user)
    @user2 = create(:user)
  end

  context "#billing" do
    test "returns a Business::BillingManagement instance" do
      @business.billing.is_a?(Business::BillingManagement)
    end
  end

  context "#billing_manager?" do
    test "false if the user is not a billing manager of the business" do
      refute @business.billing_manager?(@user)
    end

    test "true if the user is a billing manager of the business" do
      @business.billing.add_manager(@user, actor: @business.owners.first)
      assert_able @user, :write, @business.billing
      assert @business.billing_manager?(@user)
    end
  end

  context "#billing_managers" do
    test "returns all billing managers for the business" do
      @business.billing.add_manager(@user, actor: @business.owners.first)
      assert_same_elements [@user], @business.billing_managers
    end

    test "returns an empty array if there are no billing managers in the business" do
      assert_empty @business.billing_managers
    end
  end

  context "#billing_manager_ids" do
    test "returns all billing manager ids for the business" do
      @business.billing.add_manager(@user, actor: @business.owners.first)
      assert_same_elements [@user.id], @business.billing_manager_ids
    end

    test "returns an empty array if there are no billing managers in the business" do
      assert_empty @business.billing_manager_ids
    end
  end

  context "#billing_users" do
    test "includes billing managers for the business" do
      @business.billing.add_manager(@user, actor: @business.owners.first)
      assert_same_elements @business.owners + [@user], @business.billing_users
    end
  end

  context "#remove_billing_managers" do
    test "removes billing managers, but does not notify them when destroying a business" do
      @business.billing.add_manager(@user, actor: @business.owners.first)
      assert @business.billing_manager?(@user)

      @business.billing_managers.each do |billing_manager|
        @business.expects(:remove_user_from_business).with(billing_manager).once
      end
      BusinessMailer.expects(:removed_as_business_admin).never

      @business.destroy
    end
  end

  test "cleans up permissions when business is destroyed" do
    @business.billing.add_manager(@user, actor: @business.owners.first)
    assert @business.billing_manager?(@user)

    @business.destroy

    refute @business.billing_manager?(@user)
  end
end

class UserWithBillingManagementAccessToABusinessTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @business = create(:business, organizations: [@org])
    @billing_manager = create(:user)
    @business.billing.add_manager(@billing_manager, actor: @business.owners.first)
  end

  test "can't admin the business" do
    refute @business.adminable_by?(@billing_manager)
  end

  test "can't admin an org" do
    refute @org.adminable_by?(@billing_manager)
  end
end
