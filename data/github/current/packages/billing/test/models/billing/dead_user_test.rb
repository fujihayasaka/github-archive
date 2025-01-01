# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class DeadUserTest < GitHub::BillingTestCase
    fixtures do
      @user         = create :user, plan: "small"

      @org_user     = create(:user)
      @organization = create :organization, admin: @org_user, plan: "silver"


      @user_txn     = create :billing_transaction, user: @user
      @org_txn      = create :billing_transaction,
        user: @organization,
        user_type: "organization"
    end

    test "a dead user" do
      @user.delete
      dead_user = @user_txn.dead_user

      assert_equal @user.email, dead_user.email
      assert_equal @user.billing_email, dead_user.billing_email
      assert_equal @user.id, dead_user.id
      assert_equal @user.login, dead_user.to_s
      assert_equal @user.login, dead_user.login
      assert_nil dead_user.vat_code
      assert_equal [dead_user], dead_user.billing_users
      refute dead_user.organization?
    end

    test "a dead organization" do
      @organization.delete
      dead_org = @org_txn.dead_user

      # assert_equal @organization.email, dead_org.email
      assert_equal @organization.billing_email, dead_org.billing_email
      assert_equal @organization.id, dead_org.id
      assert_equal @organization.login, dead_org.to_s
      assert_equal @organization.login, dead_org.login
      assert_nil dead_org.vat_code
      assert_equal [dead_org], dead_org.billing_users
      assert dead_org.organization?
    end
  end
end
