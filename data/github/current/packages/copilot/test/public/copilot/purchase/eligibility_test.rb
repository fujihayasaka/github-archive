# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Purchase::EligibilityTest < GitHub::TestCase
  fixtures do
    @credit_card_org = create(:copilot_credit_card_org)

    @owning_biz = create(:business)
    @owned_org = create(:organization, business: @owning_biz)
    @other_owned_org = create(:organization, business: @owning_biz)

    @copilot_business_trial = create(:copilot_business_trial, :organization, :active, :started)
    @trial_org = @copilot_business_trial.trialable
    @trial_biz = if TestEnv.test_with_all_emus?
      @trial_org.business
    else
      create(:business)
    end

    @standalone_biz = create(:business, seats_plan_type: :basic)
  end

  setup do
    @trial_biz.organizations = [@trial_org]
    GitHub.flipper[:copilot_mixed_licenses].enable
    GitHub.flipper[:copilot_enabled_unconfigured].enable
  end

  context "the happy path" do
    test "no ineligible reasons a standalone org" do
      eligibility = Copilot::Purchase::Eligibility.new(orgs: [@credit_card_org], businesses: [])
      factors = eligibility.for(@credit_card_org)

      assert_equal true, factors[:eligible]
      assert_equal :ok, factors[:reason]
    end

    test "no ineligible reasons for a business" do
      eligibility = Copilot::Purchase::Eligibility.new(orgs: [@owned_org], businesses: [@owning_biz])
      factors = eligibility.for(@owning_biz)

      assert_equal true, factors[:eligible]
      assert_equal :ok, factors[:reason]
    end
  end

  context "the unhappy path" do
    context "standalone org" do
      test "ineligible when on a trial" do
        eligibility = Copilot::Purchase::Eligibility.new(orgs: [@trial_org], businesses: [])
        factors = eligibility.for(@trial_org)

        assert_equal false, factors[:eligible]
        assert_equal :has_trial, factors[:reason]
      end

      test "ineligible when copilot enabled" do
        Copilot::Organization.new(@credit_card_org).enable_copilot!

        eligibility = Copilot::Purchase::Eligibility.new(orgs: [@credit_card_org], businesses: [])
        factors = eligibility.for(@credit_card_org)

        assert_equal false, factors[:eligible]
        assert_equal :copilot_enabled, factors[:reason]
      end

      test "ineligible when on a legacy plan" do
        @credit_card_org.plan.stubs(:legacy?).returns(true)

        eligibility = Copilot::Purchase::Eligibility.new(orgs: [@credit_card_org], businesses: [])

        factors = eligibility.for(@credit_card_org)

        assert_equal false, factors[:eligible]
        assert_equal :has_legacy_plan, factors[:reason]
      end

      test "ineligible when not trade screen linked" do
        org = create(:invoiced_org, plan: "business")

        factors = Copilot::Purchase::Eligibility.for(account: org)

        assert_equal false, factors[:eligible]
        assert_equal :no_trade_screening_record, factors[:reason]
      end
    end

    context "orgs with a parent business" do
      test "ineligible when copilot disabled by parent" do
        Copilot::Business.new(@owning_biz).enable_copilot_for_selected_organizations!([])
        Copilot::Organization.new(@owned_org).copilot_plan_business!

        eligibility = Copilot::Purchase::Eligibility.new(orgs: [@owned_org], businesses: [@owning_biz])
        factors = eligibility.for(@owned_org)

        assert_equal false, factors[:eligible]
        assert_equal :copilot_disabled_by_parent, factors[:reason]
      end

      test "ineligible when copilot is disabled for all orgs" do
        Copilot::Business.new(@owning_biz).disable_copilot!

        eligibility = Copilot::Purchase::Eligibility.new(orgs: [@owned_org], businesses: [@owning_biz])
        factors = eligibility.for(@owned_org)

        assert_equal false, factors[:eligible]
        assert_equal :copilot_disabled_by_parent, factors[:reason]
      end

      test "ineligible when org has a parent at all and copilot can be unconfigured at enterprise level" do
        eligibility = Copilot::Purchase::Eligibility.new(orgs: [@owned_org], businesses: [@owning_biz])
        factors = eligibility.for(@owned_org)

        assert_equal false, factors[:eligible]
        assert_equal :owned_by_parent, factors[:reason]
      end
    end

    context "business" do
      test "ineligible when all orgs are on a trial" do
        eligibility = Copilot::Purchase::Eligibility.new(orgs: [@trial_org], businesses: [@trial_biz])
        factors = eligibility.for(@trial_biz)

        assert_equal false, factors[:eligible]
        assert_equal :has_trial, factors[:reason]
      end

      test "ineligible is copilot is enabled for all orgs" do
        Copilot::Business.new(@owning_biz).enable_copilot_for_all_organizations!

        eligibility = Copilot::Purchase::Eligibility.new(orgs: [@owned_org, @other_owned_org], businesses: [@owning_biz])
        factors = eligibility.for(@owning_biz)

        assert_equal false, factors[:eligible]
        assert_equal :copilot_enabled, factors[:reason]
      end

      test "ineligible if copilot is enabled for some owned orgs" do
        Copilot::Business.new(@owning_biz).enable_copilot_for_selected_organizations!([@owned_org])

        eligibility = Copilot::Purchase::Eligibility.new(orgs: [@owned_org, @other_owned_org], businesses: [@owning_biz])
        factors = eligibility.for(@owning_biz)

        assert_equal false, factors[:eligible]
        assert_equal :copilot_enabled, factors[:reason]
      end

      test "ineligible if a standalone business has Copilot enabled" do
        if TestEnv.test_with_all_emus?
          @standalone_biz.update(seats_plan_type: :basic)
          @standalone_biz.reload
        end

        Copilot::Business.new(@standalone_biz).enable_copilot!

        eligibility = Copilot::Purchase::Eligibility.new(orgs: [], businesses: [@standalone_biz])
        factors = eligibility.for(@standalone_biz)

        assert_equal false, factors[:eligible]
        assert_equal :copilot_enabled, factors[:reason]
      end
    end
  end
end unless GitHub.enterprise?
