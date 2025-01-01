# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsOrgAdminThresholdComplianceTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner")
    @owner_2 = create(:user, login: "owner2")
    @org = create(:organization, admin: @owner)
    @free_org = create(:free_organization, admin: @owner_2)

    @user_1 = create(:user)
    @user_2 = create(:user)
    @user_3 = create(:user)
    @user_4 = create(:user)

    @restricted_user_1 = create(:user, :fully_trade_restricted)
    @restricted_user_2 = create(:user, :fully_trade_restricted)
    @restricted_user_3 = create(:user, :fully_trade_restricted)
  end

  setup do
    @compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @org)
  end

  test "responds to violation?" do
    assert @compliance.respond_to? :violation?
  end

  test "#reason is symbol/string" do
    assert @compliance.reason.kind_of?(String) ||
      @compliance.reason.kind_of?(Symbol)
  end

  test "#to_hydro is a Hash" do
    assert_kind_of Hash, @compliance.to_hydro
  end

  test "responds to full_restriction_violation?" do
    assert @compliance.respond_to? :full_restriction_violation?
  end

  test "responds to tier_1_restriction_violation?" do
    assert @compliance.respond_to? :tier_1_restriction_violation?
  end

  test "current_threshold uses 2 decimals as precision" do
    [@user_1, @restricted_user_1].each do |u|
      @org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @org.reload)

    assert_equal 2, T.must(compliance.current_threshold.to_s.split(".").last).size
  end

  test "#full_restriction_violation? is true for paid orgs whose trade restricted admins is = 50%" do
    [@user_1, @restricted_user_1, @restricted_user_2].each do |u|
      @org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @org.reload)

    assert compliance.admins_count == 4
    assert compliance.trade_restricted_admins_count == 2
    assert_predicate compliance, :full_restriction_violation?
  end

  test "#violation? is true for paid orgs whose trade restricted admins > 50%" do
    [@user_1, @restricted_user_1, @restricted_user_2, @restricted_user_3].each do |u|
      @org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @org.reload)

    assert compliance.admins_count == 5
    assert compliance.trade_restricted_admins_count == 3
    assert_predicate compliance, :violation?
  end

  test "#full_restriction_violation? is false for paid orgs whose trade restricted admins is < 50%" do
    [@user_1, @restricted_user_1].each do |u|
      @org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @org.reload)

    assert compliance.admins_count == 3
    assert compliance.trade_restricted_admins_count == 1
    refute_predicate compliance, :full_restriction_violation?
  end

  test "#tier_1_restriction_violation? is true for free orgs whose trade restricted admins = 50%" do
    [@user_1, @restricted_user_1, @restricted_user_2].each do |u|
      @free_org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @free_org.reload)

    assert compliance.admins_count == 4
    assert compliance.trade_restricted_admins_count == 2
    assert_predicate compliance, :tier_1_restriction_violation?
  end

  test "#tier_1_restriction_violation? is true for free orgs whose trade restricted admins is > 50%" do
    [@user_1, @restricted_user_1, @restricted_user_2, @restricted_user_3].each do |u|
      @free_org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @free_org.reload)

    assert compliance.admins_count == 5
    assert compliance.trade_restricted_admins_count == 3
    assert_predicate compliance, :tier_1_restriction_violation?
  end

  test "#tier_1_restriction_violation? is false for free orgs whose trade restricted admins is < 50%" do
    [@user_1, @user_2, @user_3, @restricted_user_1, @restricted_user_2, @restricted_user_3].each do |u|
      @free_org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @free_org.reload)

    assert compliance.admins_count == 7
    assert compliance.trade_restricted_admins_count == 3
    refute_predicate compliance, :tier_1_restriction_violation?
  end

  test "#tier_0_restriction_violation? is true for free orgs whose trade restricted admins = 25% when" do
    [@user_1, @user_2, @restricted_user_1].each do |u|
      @free_org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @free_org.reload)

    assert compliance.admins_count == 4
    assert compliance.trade_restricted_admins_count == 1
    assert_predicate compliance, :tier_0_restriction_violation?
  end

  test "#tier_0_restriction_violation? is true for free orgs whose trade restricted admins is > 25%" do
    [@user_1, @user_2, @user_3, @restricted_user_1, @restricted_user_2].each do |u|
      @free_org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @free_org.reload)

    assert compliance.admins_count == 6
    assert compliance.trade_restricted_admins_count == 2
    assert_predicate compliance, :tier_0_restriction_violation?
  end

  test "#tier_0_restriction_violation? is false for free orgs whose trade restricted admins is > 49%" do
    [@user_1, @user_2, @restricted_user_1, @restricted_user_2, @restricted_user_3].each do |u|
      @free_org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @free_org.reload)

    assert compliance.admins_count == 6
    assert compliance.trade_restricted_admins_count == 3
    refute_predicate compliance, :tier_0_restriction_violation?
  end

  test "#violation? is true for free orgs whose trade restricted admins > 25%" do
    [@user_1, @restricted_user_1, @restricted_user_2].each do |u|
      @free_org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @free_org.reload)

    assert compliance.admins_count == 4
    assert compliance.trade_restricted_admins_count == 2
    assert_predicate compliance, :violation?
  end

  test "#violation? is false for free orgs whose trade restricted admins is < 25%" do
    [@user_1, @user_2, @user_3, @user_4, @restricted_user_1].each do |u|
      @free_org.add_admin(u)
    end

    compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @free_org.reload)

    assert_equal 6, compliance.admins_count
    assert_equal 1, compliance.trade_restricted_admins_count
    refute_predicate compliance, :violation?
  end

  context "org creation" do
    test "it restricts free org if org owner is restricted" do

      free_org = build(:organization, admin: @restricted_user_1, plan: "free")
      perform_enqueued_jobs(only: TradeControls::OrganizationComplianceCheckJob) do
        free_org.save
      end

      free_org.reload
      assert_predicate free_org, :has_tier_1_trade_restrictions?
    end

    test "it does not restrict free org if org owner is not restricted" do

      free_org = build(:organization, admin: @user_1, plan: "free")
      perform_enqueued_jobs(only: TradeControls::OrganizationComplianceCheckJob) do
        free_org.save
      end

      free_org.reload
      refute_predicate free_org, :has_any_trade_restrictions?
    end
  end unless GitHub.enterprise?
end
