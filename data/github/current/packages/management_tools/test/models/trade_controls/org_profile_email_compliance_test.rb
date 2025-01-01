# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsOrgProfileEmailComplianceTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner")
    @owner_2 = create(:user, login: "owner2")
    @org = create(:organization, admin: @owner)
    @free_org = create(:free_organization, admin: @owner_2)
  end

  setup do
    @compliance = TradeControls::OrgProfileEmailCompliance.new(organization: @org)
  end

  test "responds to violation?" do
    assert @compliance.respond_to? :violation?
  end

  test "#reason is symbol/string" do
    assert @compliance.reason.kind_of?(String) ||
      @compliance.reason.kind_of?(Symbol)
  end

  test "#to_hydro is a Hash" do
    @org.create_profile(email: "test@example.sy")
    compliance = TradeControls::OrgProfileEmailCompliance.new(organization: @org.reload)

    assert_kind_of Hash, compliance.to_hydro
  end

  test "responds to full_restriction_violation?" do
    assert @compliance.respond_to? :full_restriction_violation?
  end

  test "responds to tier_1_restriction_violation?" do
    assert @compliance.respond_to? :tier_1_restriction_violation?
  end

  test "#full_restriction_violation? is true for paid orgs with sanctioned email" do
    @org.create_profile(email: "test@example.sy")
    compliance = TradeControls::OrgProfileEmailCompliance.new(organization: @org.reload)

    assert_predicate compliance, :full_restriction_violation?
  end


  test "#full_restriction_violation? is false for paid orgs with unsanctioned email domain" do
    @org.create_profile(email: "test@example.gh")
    compliance = TradeControls::OrgProfileEmailCompliance.new(organization: @org.reload)

    refute_predicate compliance, :full_restriction_violation?
  end

  test "#tier_1_restriction_violation? is true for free orgs with sanctioned email" do
    @free_org.create_profile(email: "test@example.sy")
    compliance = TradeControls::OrgProfileEmailCompliance.new(organization: @free_org.reload)

    assert_predicate compliance, :tier_1_restriction_violation?
  end

  test "#tier_1_restriction_violation? is false for free orgs eith unsactioned email domain " do
    @free_org.create_profile(email: "test@example.gh")
    compliance = TradeControls::OrgProfileEmailCompliance.new(organization: @free_org.reload)

    refute_predicate compliance, :tier_1_restriction_violation?
  end

  test "#violation? is true for paid orgs with sanctioned email" do
    @org.create_profile(email: "test@example.sy")
    compliance = TradeControls::OrgProfileEmailCompliance.new(organization: @org.reload)

    assert_predicate compliance, :violation?
  end


  test "#violation? is false for paid orgs with unsanctioned email domain" do
    @org.create_profile(email: "test@example.gh")
    compliance = TradeControls::OrgProfileEmailCompliance.new(organization: @org.reload)

    refute_predicate compliance, :violation?
  end

  test "#violation? is true for free orgs with sanctioned email" do
    @free_org.create_profile(email: "test@example.sy")
    compliance = TradeControls::OrgProfileEmailCompliance.new(organization: @free_org.reload)

    assert_predicate compliance, :violation?
  end

  test "#violation? is false for free orgs eith unsactioned email domain " do
    @free_org.create_profile(email: "test@example.gh")
    compliance = TradeControls::OrgProfileEmailCompliance.new(organization: @free_org.reload)

    refute_predicate compliance, :violation?
  end
end
