# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessSupportEntitleeDependencyTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @admin = create :user
    @member = create :user
    @rando = create :user
    @nonmember = create :user

    @org = create :organization, admin: @admin
    @org.add_member(@member)
    @org2 = create :organization, admin: @admin
    @org2.add_member(@member)

    # biz
    @customer = create :customer, payment_method: \
      build(:paypal_payment_method, user: @rando, customer: nil)
    @business = create :business, :volume_licensed, owners: [@admin], organizations: [@org, @org2], customer: @customer

    @billing_manager = create :user, login: "billing-manager"
    @business.billing.add_manager(@billing_manager, actor: @admin)
  end

  test "ability" do
    @business.add_support_entitlee(@member, actor: @admin)
    ability = Business::SupportEntitlee.new(@member).abilities.first
    assert_equal "SupportEntitlee", ability.actor_type
    assert_equal "Business", ability.subject_type
  end

  test "add_support_entitlee only adds members" do
    @business.add_support_entitlee(@nonmember, actor: @admin)
    assert_equal 0, @business.support_entitlees.count
    @business.add_support_entitlee(@member, actor: @admin)
    assert_equal 1, @business.support_entitlees.count
  end

  test "remove_support_entitlee removes" do
    @business.add_support_entitlee(@member, actor: @admin)
    assert_equal 1, @business.support_entitlees.count
    @business.remove_support_entitlee(@member, actor: @admin)
    assert_equal 0, @business.support_entitlees.count
  end

  test "support_entitled?" do
    @business.add_support_entitlee(@member, actor: @admin)
    assert @business.support_entitled?(@member)
    refute @business.support_entitled?(@admin)
    refute @business.support_entitled?(@nonmember)
  end

  test "support_entitlees" do
    @business.add_support_entitlee(@member, actor: @admin)
    assert_equal @business.support_entitlees.first, @member
  end

  test "max_support_entitlees for premium business" do
    empty_business = create :business, owners: []
    empty_business.support_plan = "premium"

    assert_equal 20, empty_business.max_support_entitlees
  end

  test "max_support_entitlees for premium plus business" do
    empty_business = create :business, owners: []
    empty_business.support_plan = "premium_plus"

    assert_equal 40, empty_business.max_support_entitlees
  end

  test "removes on business destroy" do
    business = create :business
    owner = business.owners.first
    business.add_support_entitlee(owner, actor: nil)
    assert_equal 1, Business::SupportEntitlee.new(owner).abilities.count
    business.destroy
    assert_equal 0, Business::SupportEntitlee.new(owner).abilities.count
  end

  test "removes on business membership removal" do
    only = [
      BusinessMembershipCleanupJob,
      RevokeOrgMembershipAbilitiesJob,
      DeleteDependentAbilitiesJob,
      RemoveOrgMemberJob
    ]
    perform_enqueued_jobs only: only do
      @business.add_support_entitlee(@member, actor: @admin)
      @business.remove_member(@member, actor: @admin)
      assert_equal 0, Business::SupportEntitlee.new(@member).abilities.count
    end
  end

  test "removes on remove from all orgs" do
    only = [
      BusinessMembershipCleanupJob,
      RevokeOrgMembershipAbilitiesJob
    ]
    perform_enqueued_jobs only: only do
      disable_feature_flag(:unaffiliated_user_accounts)
      @business.add_support_entitlee(@member, actor: @admin)
      @org.remove_member!(@member)
      assert_equal 1, Business::SupportEntitlee.new(@member).abilities.count
      @org2.remove_member!(@member)
      refute @org.member?(@member)
      refute @org2.member?(@member)
      refute @business.member?(@member)
      assert_equal 0, Business::SupportEntitlee.new(@member).abilities.count
    end
  end

  test "does not remove on remove from all orgs when unaffiliated users are supported" do
    only = [RevokeOrgMembershipAbilitiesJob]
    perform_enqueued_jobs only: only do
      enable_feature_flag(:unaffiliated_user_accounts)
      @business.add_support_entitlee(@member, actor: @admin)
      @org.remove_member!(@member)
      assert_equal 1, Business::SupportEntitlee.new(@member).abilities.count
      @org2.remove_member!(@member)
      refute @org.member?(@member)
      refute @org2.member?(@member)
      refute @business.member?(@member)
      assert @business.unaffiliated_member?(@member)
      assert_equal 1, Business::SupportEntitlee.new(@member).abilities.count
    end
  end
end
