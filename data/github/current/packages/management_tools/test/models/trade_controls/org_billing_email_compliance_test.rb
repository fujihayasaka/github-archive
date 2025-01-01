# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsOrgBillingEmailComplianceTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner")
    @owner_2 = create(:user, login: "owner2")
    @org = create(:organization, admin: @owner)
    @free_org = create(:free_organization, admin: @owner_2)
  end

  setup do
    @compliance = TradeControls::OrgBillingEmailCompliance.new(organization: @org)
  end

  test "responds to violation?" do
    assert @compliance.respond_to? :violation?
  end

  test "#reason is symbol/string" do
    assert @compliance.reason.kind_of?(String) ||
      @compliance.reason.kind_of?(Symbol)
  end

  test "#to_hydro is a Hash" do
    @org.update(billing_email: "test@example.sy")
    compliance = TradeControls::OrgBillingEmailCompliance.new(organization: @org.reload)

    assert_kind_of Hash, compliance.to_hydro
  end

  test "responds to full_restriction_violation?" do
    assert @compliance.respond_to? :full_restriction_violation?
  end

  test "responds to tier_1_restriction_violation?" do
    assert @compliance.respond_to? :tier_1_restriction_violation?
  end


  test "#full_restriction_violation? is true for paid orgs with sanctioned email" do
    @org.update(billing_email: "test@example.sy")
    compliance = TradeControls::OrgBillingEmailCompliance.new(organization: @org.reload)

    assert_predicate compliance, :full_restriction_violation?
  end


  test "#full_restriction_violation? is false for paid orgs with unsanctioned email domain" do
    @org.update(billing_email: "test@example.gh")
    compliance = TradeControls::OrgBillingEmailCompliance.new(organization: @org.reload)

    refute_predicate compliance, :full_restriction_violation?
  end

  test "#tier_1_restriction_violation? is true for free orgs with sanctioned email" do
    @free_org.update(billing_email: "test@example.sy")
    compliance = TradeControls::OrgBillingEmailCompliance.new(organization: @free_org.reload)

    assert_predicate compliance, :tier_1_restriction_violation?
  end

  test "#tier_1_restriction_violation? is false for free orgs eith unsactioned email domain " do
    @free_org.update(billing_email: "test@example.gh")
    compliance = TradeControls::OrgBillingEmailCompliance.new(organization: @free_org.reload)

    refute_predicate compliance, :tier_1_restriction_violation?
  end

  test "#violation? is true for paid orgs with sanctioned email" do
    @org.update(billing_email: "test@example.sy")
    compliance = TradeControls::OrgBillingEmailCompliance.new(organization: @org.reload)

    assert_predicate compliance, :violation?
  end


  test "#violation? is false for paid orgs with unsanctioned email domain" do
    @org.update(billing_email: "test@example.gh")
    compliance = TradeControls::OrgBillingEmailCompliance.new(organization: @org.reload)

    refute_predicate compliance, :violation?
  end

  test "#violation? is true for free orgs with sanctioned email" do
    @free_org.update(billing_email: "test@example.sy")
    compliance = TradeControls::OrgBillingEmailCompliance.new(organization: @free_org.reload)

    assert_predicate compliance, :violation?
  end

  test "#violation? is false for free orgs eith unsactioned email domain " do
    @free_org.update(billing_email: "test@example.gh")
    compliance = TradeControls::OrgBillingEmailCompliance.new(organization: @free_org.reload)

    refute_predicate compliance, :violation?
  end

  context "org creation" do
    test "it fully restricts paid org if billing email TLD is sanctioned on org creation" do
      org = build(:organization, billing_email: "kofi@example.sy")
      only = [TradeControls::OrganizationComplianceCheckJob, InstrumentOrganizationTradeRestrictionEnforceJob]
      perform_enqueued_jobs(only: only) do
        org.save
      end

      org.reload
      assert_equal org.charged_account?, true
      assert_predicate org, :has_full_trade_restrictions?
    end

    test "it does not restrict paid org if billing email TLD is not sanctioned on org creation" do
      org = build(:organization, billing_email: "kofi@example.uk")
      only = [TradeControls::OrganizationComplianceCheckJob, InstrumentOrganizationTradeRestrictionEnforceJob]
      perform_enqueued_jobs(only: only) do
        org.save
      end

      org.reload
      assert_equal org.charged_account?, true
      refute_predicate org, :has_any_trade_restrictions?
    end

    test "it tier_1 restricts free org if billing email TLD is sanctioned on org creation" do
      free_org = build(:organization, billing_email: "kofi@example.sy", plan: "free")
      only = [TradeControls::OrganizationComplianceCheckJob, InstrumentOrganizationTradeRestrictionEnforceJob]
      perform_enqueued_jobs(only: only) do
        free_org.save
      end

      free_org.reload
      assert_equal free_org.uncharged_account?, true
      assert_predicate free_org, :has_tier_1_trade_restrictions?
    end

    test "it does not restrict free org if billing email TLD is not sanctioned on org creation" do
      free_org = build(:organization, billing_email: "kofi@example.uk", plan: "free")
      only = [TradeControls::OrganizationComplianceCheckJob, InstrumentOrganizationTradeRestrictionEnforceJob]
      perform_enqueued_jobs(only: only) do
        free_org.save
      end

      free_org.reload
      assert_equal free_org.uncharged_account?, true
      refute_predicate free_org, :has_any_trade_restrictions?
    end
  end unless GitHub.enterprise?
end
