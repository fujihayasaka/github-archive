# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsBillingManagersComplianceTest < GitHub::TestCase
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
    @compliance = TradeControls::BillingManagersCompliance.new(organization: @org)
  end

  test "responds to violation?" do
    assert @compliance.respond_to? :violation?
  end

  test "responds to full_restriction_violation?" do
    assert @compliance.respond_to? :full_restriction_violation?
  end

  test "responds to tier_1_restriction_violation?" do
    assert @compliance.respond_to? :tier_1_restriction_violation?
  end

  test "#reason is symbol/string" do
    assert @compliance.reason.kind_of?(String) ||
      @compliance.reason.kind_of?(Symbol)
  end

  test "#to_hydro is a Hash" do
    assert_kind_of Hash, @compliance.to_hydro
  end

  test "current_threshold uses 2 decimals as precision" do
    [@user_1, @user_2, @restricted_user_1].each do |u|
      @org.billing.add_manager(u, actor: @owner)
    end

    compliance = TradeControls::BillingManagersCompliance.new(organization: @org.reload)

    assert_equal 2, T.must(compliance.current_threshold.to_s.split(".").last).size
  end

  test "#violation? is true for paid orgs whose trade restricted billing managers is = 50%" do
    [@user_1, @user_2, @restricted_user_1, @restricted_user_2].each do |u|
      @org.billing.add_manager(u, actor: @owner)
    end

    compliance = TradeControls::BillingManagersCompliance.new(organization: @org.reload)

    assert compliance.number_of_billing_managers == 4
    assert compliance.number_of_trade_restricted_billing_managers == 2
    assert_predicate compliance, :violation?
  end

  test "#full_restriction_violation? is true for paid orgs whose trade restricted billing managers is = 50%" do
    [@user_1, @user_2, @restricted_user_1, @restricted_user_2].each do |u|
      @org.billing.add_manager(u, actor: @owner)
    end

    compliance = TradeControls::BillingManagersCompliance.new(organization: @org.reload)

    assert compliance.number_of_billing_managers == 4
    assert compliance.number_of_trade_restricted_billing_managers == 2
    assert_predicate compliance, :full_restriction_violation?
  end

  test "#violation? is true for paid orgs whose trade restricted billing managers > 50%" do
    [@user_1, @user_2, @restricted_user_1, @restricted_user_2, @restricted_user_3].each do |u|
      @org.billing.add_manager(u, actor: @owner)
    end

    compliance = TradeControls::BillingManagersCompliance.new(organization: @org.reload)

    assert compliance.number_of_billing_managers == 5
    assert compliance.number_of_trade_restricted_billing_managers == 3
    assert_predicate compliance, :violation?
  end

  test "#violation? is false for paid orgs whose trade restricted billing managers is < 50%" do
    [@user_1, @user_2, @restricted_user_1].each do |u|
      @org.billing.add_manager(u, actor: @owner)
    end

    compliance = TradeControls::BillingManagersCompliance.new(organization: @org.reload)

    assert compliance.number_of_billing_managers == 3
    assert compliance.number_of_trade_restricted_billing_managers == 1
    refute_predicate compliance, :violation?
  end

  test "#violation? is true for free orgs whose trade restricted billing managers is = 25%" do
    [@user_1, @user_2, @user_3, @restricted_user_1].each do |u|
      @free_org.billing.add_manager(u, actor: @owner_2)
    end

    compliance = TradeControls::BillingManagersCompliance.new(organization: @free_org.reload)

    assert compliance.number_of_billing_managers == 4
    assert compliance.number_of_trade_restricted_billing_managers == 1
    assert_predicate compliance, :violation?
  end

  test "#tier_1_restriction_violation? is true for free orgs whose trade restricted billing managers is = 25%" do
    [@user_1, @user_2, @user_3, @restricted_user_1].each do |u|
      @free_org.billing.add_manager(u, actor: @owner_2)
    end

    compliance = TradeControls::BillingManagersCompliance.new(organization: @free_org.reload)

    assert compliance.number_of_billing_managers == 4
    assert compliance.number_of_trade_restricted_billing_managers == 1
    assert_predicate compliance, :tier_1_restriction_violation?
  end

  test "#violation? is true for free orgs whose trade restricted billing managers > 25%" do
    [@user_1, @user_2, @user_3, @restricted_user_1, @restricted_user_2].each do |u|
      @free_org.billing.add_manager(u, actor: @owner_2)
    end

    compliance = TradeControls::BillingManagersCompliance.new(organization: @free_org.reload)

    assert compliance.number_of_billing_managers == 5
    assert compliance.number_of_trade_restricted_billing_managers == 2
    assert_predicate compliance, :violation?
  end

  test "#violation? is false for free orgs trade restricted billing managers is < 25%" do
    [@user_1, @user_2, @user_3, @user_4, @restricted_user_1].each do |u|
      @free_org.billing.add_manager(u, actor: @owner_2)
    end

    compliance = TradeControls::BillingManagersCompliance.new(organization: @free_org.reload)

    assert_equal 5, compliance.number_of_billing_managers
    assert_equal 1, compliance.number_of_trade_restricted_billing_managers
    refute_predicate compliance, :violation?
  end
end
