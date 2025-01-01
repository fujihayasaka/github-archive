# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Purchase::EligibilityTest < GitHub::TestCase
  fixtures do
    @credit_card_org = create(:copilot_credit_card_org)

    # The with_trade_screening_record trait is not a 1:1 check for valid
    # billing contact information, but an account cant have a screening record without
    # billing contact info, so this should be a good enough proxy for that.
    @owning_biz = create(:business, :with_trade_screening_record)
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
    enable_feature_flag(:copilot_enabled_unconfigured)
  end

  context "eligible" do
    test "no ineligible reasons a standalone org" do
      factors = Copilot::Purchase::Eligibility.for(account: @credit_card_org)

      assert_equal true, factors[:eligible]
      assert_equal :ok, factors[:reason]
    end

    test "no ineligible reasons for a business" do
      factors = Copilot::Purchase::Eligibility.for(account: @owning_biz)

      assert_equal true, factors[:eligible]
      assert_equal :ok, factors[:reason]
    end

    test "copilot_billable? accounts metered via azure are always eligible" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      azure_org = create(:organization, :with_azure_subscription, plan: "business")
      azure_biz = create(:business, :with_azure_subscription)

      org_factors = Copilot::Purchase::Eligibility.for(account: azure_org)
      biz_factors = Copilot::Purchase::Eligibility.for(account: azure_biz)

      assert org_factors[:eligible]
      assert_equal :ok, org_factors[:reason]

      assert biz_factors[:eligible]
      assert_equal :ok, biz_factors[:reason]
    end

    # There are no standalone orgs in EMU-land
    test "elibigle when the org is invoiced, even without billing contact information", skip_with_all_emus: true do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      org = create(:organization, plan: "business_plus", billing_type: "invoice")

      factors = Copilot::Purchase::Eligibility.for(account: org)
      assert_equal :ok, factors[:reason]
    end

    test "eligible when the enterprise is invoiced, even without billing contact information" do
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      biz = create(:business, :invoiced)

      factors = Copilot::Purchase::Eligibility.for(account: biz)
      assert_equal :ok, factors[:reason]
    end
  end

  context "ineligibility" do
    context "standalone org" do
      test "ineligible when on a trial" do
        factors = Copilot::Purchase::Eligibility.for(account: @trial_org)

        assert_equal false, factors[:eligible]
        assert_equal :has_trial, factors[:reason]
      end

      test "ineligible when copilot enabled" do
        Copilot::Organization.new(@credit_card_org).enable_copilot!

        factors = Copilot::Purchase::Eligibility.for(account: @credit_card_org)

        assert_equal false, factors[:eligible]
        assert_equal :copilot_enabled, factors[:reason]
      end

      test "ineligible when on a legacy plan" do
        @credit_card_org.plan.stubs(:legacy?).returns(true)

        factors = Copilot::Purchase::Eligibility.for(account: @credit_card_org)

        assert_equal false, factors[:eligible]
        assert_equal :has_legacy_plan, factors[:reason]
      end

      test "ineligible when not billable" do
        org  = create(:organization, plan: "business")
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(false)

        factors = Copilot::Purchase::Eligibility.for(account: org)

        refute factors[:eligible]
        assert_equal :not_billable, factors[:reason]
      end
    end

    context "orgs with a parent enterprise" do
      test "ineligible because the parent controls their access" do
        Copilot::Business.new(@owning_biz).enable_copilot_for_selected_organizations!([])
        Copilot::Organization.new(@owned_org).copilot_plan_business!

        factors = Copilot::Purchase::Eligibility.for(account: @owned_org)

        assert_equal false, factors[:eligible]
        assert_equal :owned_by_parent, factors[:reason]
      end

      test "ineligible because the org is on a trial" do
        trial = create(:copilot_business_trial, :organization, :active)
        org = trial.trialable
        factors = Copilot::Purchase::Eligibility.for(account: org)

        assert_equal false, factors[:eligible]
        assert_equal :has_trial, factors[:reason]
      end

      test "ineligible when on a legacy plan" do
        org = create(:organization, plan: "silver")
        factors = Copilot::Purchase::Eligibility.for(account: org)

        refute factors[:eligible]
        assert_equal :has_legacy_plan, factors[:reason]
      end
    end

    context "enterprise" do
      test "ineligible when all orgs are on a trial" do
        factors = Copilot::Purchase::Eligibility.for(account: @trial_biz)

        assert_equal false, factors[:eligible]
        assert_equal :manages_trial, factors[:reason]
      end

      test "ineligible if Copilot is enabled for all orgs" do
        Copilot::Business.new(@owning_biz).enable_copilot_for_all_organizations!

        factors = Copilot::Purchase::Eligibility.for(account: @owning_biz)

        assert_equal false, factors[:eligible]
        assert_equal :copilot_enabled, factors[:reason]
      end

      test "ineligible if copilot is enabled for some owned orgs" do
        Copilot::Business.new(@owning_biz).enable_copilot_for_selected_organizations!([@owned_org])

        factors = Copilot::Purchase::Eligibility.for(account: @owning_biz)

        assert_equal false, factors[:eligible]
        assert_equal :copilot_enabled, factors[:reason]
      end

      test "ineligible if a standalone business has Copilot enabled" do
        if TestEnv.test_with_all_emus?
          @standalone_biz.update(seats_plan_type: :basic)
          @standalone_biz.reload
        end

        Copilot::Business.new(@standalone_biz).enable_copilot!

        factors = Copilot::Purchase::Eligibility.for(account: @standalone_biz)

        assert_equal false, factors[:eligible]
        assert_equal :copilot_enabled, factors[:reason]
      end

      test "ineligible if the enterprise is on a trial" do
        @trial_biz.stubs(:trial?).returns(true)
        factors = Copilot::Purchase::Eligibility.for(account: @trial_biz)

        assert_equal false, factors[:eligible]
        assert_equal :has_trial, factors[:reason]
      end

      # Businesses are always billable in multitenant mode
      test "ineligible if the enterprise is not billable", skip_in_multitenant_mode: true do
        Copilot::Business.any_instance.stubs(:copilot_billable?).returns(false)
        biz = create(:business)
        factors = Copilot::Purchase::Eligibility.for(account: biz)
        assert_equal false, factors[:eligible]
        assert_equal :not_billable, factors[:reason]
      end

      # While an enterprise that must be sales-served is also not billable,
      # we want to treat it as a distinct state in the UI because the user
      # can't resolve this state on their own.
      test "ineligible if the enterprise must be sales served" do
        biz = create(:business)
        biz.enterprise_agreements.create!(agreement_id: "test", category: :visual_studio_bundle, status: :active)
        biz.customer.update(
          azure_subscription_id: nil,
          azure_subscription_name: nil
        )
        biz.stubs(:eligible_for_self_serve_payment?).returns(false)

        factors = Copilot::Purchase::Eligibility.for(account: biz)

        assert_equal false, factors[:eligible]
        assert_equal :force_sales_serve, factors[:reason]
      end

      test "ineligible when enterprise has a valid payment method but no billing contact information" do
        biz = create(:business, :with_self_serve_payment)
        create(:billing_plan_subscription, :zuora_business, customer: biz.customer, user: biz.owners.first)

        factors = Copilot::Purchase::Eligibility.for(account: biz)

        assert_equal false, factors[:eligible]
        assert_equal :no_billing_contact_information, factors[:reason]
      end

      test "ineligible when org has a valid payment method but no billing contact information" do
        org = create(:credit_card_org, plan: "business")

        factors = Copilot::Purchase::Eligibility.for(account: org)

        assert_equal false, factors[:eligible]
        assert_equal :no_billing_contact_information, factors[:reason]
      end
    end
  end
end unless GitHub.enterprise?
