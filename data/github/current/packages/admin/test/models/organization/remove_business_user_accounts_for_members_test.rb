# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationRemoveBusinessUserAccountsForMembersTest < GitHub::TestCase
  fixtures do
    @admin = create :user
    @org   = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @member = create(:user)
    @org.add_member(@member)

    @business = create :business, organizations: [@org], owners: [@admin]
  end

  if GitHub.single_business_environment?
    test "does not remove business user accounts for single business environment" do
      assert_equal 0, @business.user_accounts.count

      @org.destroy
      assert_equal 0, @business.user_accounts.count
    end
  else
    test "removes members of the organization who are not members of any other organization in the business" do
      disable_feature_flag(:unaffiliated_user_accounts)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb)
      assert_equal 3, @business.user_accounts.count

      @org.destroy
      assert_equal 1, @business.user_accounts.count
    end

    test "does not remove members of the organization who are not members of any other organization in the business when unaffiliated user accounts are supported" do
      enable_feature_flag(:unaffiliated_user_accounts)
      assert_equal 3, @business.user_accounts.count

      @org.destroy
      assert_equal 3, @business.user_accounts.count
    end

    test "does not remove business user accounts of members that are business administrators" do
      disable_feature_flag(:unaffiliated_user_accounts)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb)
      billing_manager = create :user
      @business.billing.add_manager billing_manager, actor: @admin
      @org.add_member @admin
      @org.add_member billing_manager

      expected_members = [*@org.admins, @member, @admin, billing_manager]
      assert_same_elements expected_members.map(&:id), @business.user_accounts.pluck(:user_id)

      @org.destroy

      expected_members = [@admin, billing_manager]
      assert_same_elements expected_members.map(&:id), @business.user_accounts.pluck(:user_id)
    end
  end
end
