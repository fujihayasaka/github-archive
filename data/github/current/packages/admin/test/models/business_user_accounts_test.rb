# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessUserAccountsTest < GitHub::TestCase
  fixtures do
    # Allow creation of multiple businesses for these tests, regardless of
    # whether running in single global business mode or not.
    GitHub.stubs(:single_business_environment?).returns(false)
    @admin = create :user
    @user = create :user
    @business_1 = create :business, owners: [@user]
    @business_2 = create :business, owners: [@admin]
    @business_3 = create :business

    @org = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @org.add_member @user

    @business_2.billing.add_manager @user, actor: @admin
    perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) { @business_3.add_organization @org }
  end

  test "deletes business_user_accounts when user is deleted" do
    assert_equal 3, @user.business_user_accounts.count

    @business_1.add_owner @admin, actor: @user
    @business_1.remove_owner @user, actor: @admin
    @user.destroy
    assert_equal 0, @user.business_user_accounts.count
  end
end
