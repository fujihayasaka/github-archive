# typed: true
# frozen_string_literal: true

require "test_helper"

class TrialDependencyTest < GitHub::TestCase

  fixtures do
    @business = create(:business, :metered_ghec, trial_expires_at: 30.days.from_now)
    @org = create(:organization, business: @business)
  end

  context "#digital_front_door?" do
    test "returns false if digital front door mvp is not enabled" do
      GitHub.flipper[:digital_front_door_mvp].disable
      GitHub.flipper[:copilot_metered_enterprise].enable
      trial = ::Copilot::BusinessTrial.create_trial!(@org,
      @org.admins.first,
      trial_length: 10,
      )
      trial.start_trial!

      create(:billing_product_uuid, :advanced_security)
      @business.subscribe_to_advanced_security_trial(
        actor: @business.owners.first,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )

      refute @business.digital_front_door?
    end

    test "returns false if copilot metered enterprise is not enabled" do
      GitHub.flipper[:digital_front_door_mvp].enable
      GitHub.flipper[:copilot_metered_enterprise].disable
      trial = ::Copilot::BusinessTrial.create_trial!(@org,
      @org.admins.first,
      trial_length: 10,
      )
      trial.start_trial!

      create(:billing_product_uuid, :advanced_security)
      @business.subscribe_to_advanced_security_trial(
        actor: @business.owners.first,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )

      refute @business.digital_front_door?
    end

    test "returns false if trial is not metered" do
      GitHub.flipper[:digital_front_door_mvp].enable
      GitHub.flipper[:copilot_metered_enterprise].disable

      volume_trial = create(:business, trial_expires_at: 30.days.from_now)
      volume_org = create(:organization, business: volume_trial)
      refute volume_trial.metered_ghe?

      trial = ::Copilot::BusinessTrial.create_trial!(volume_org,
        volume_org.admins.first,
        trial_length: 10,
        )
      trial.start_trial!

      create(:billing_product_uuid, :advanced_security)
      volume_trial.subscribe_to_advanced_security_trial(
        actor: volume_trial.owners.first,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )

      refute volume_trial.digital_front_door?
    end

    test "returns false if trial does not have Copilot trial" do
      GitHub.flipper[:digital_front_door_mvp].enable
      GitHub.flipper[:copilot_metered_enterprise].disable

      create(:billing_product_uuid, :advanced_security)
      @business.subscribe_to_advanced_security_trial(
        actor: @business.owners.first,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )

      refute @business.digital_front_door?
    end

    test "returns false if trial does not have GHAS enabled" do
      GitHub.flipper[:digital_front_door_mvp].enable
      GitHub.flipper[:copilot_metered_enterprise].enable
      trial = ::Copilot::BusinessTrial.create_trial!(@org,
      @org.admins.first,
      trial_length: 10,
      )
      trial.start_trial!

      refute @business.digital_front_door?
    end

    test "returns false if business is not an active trial" do
      GitHub.flipper[:digital_front_door_mvp].enable
      GitHub.flipper[:copilot_metered_enterprise].enable

      metered_business = create(:business, :metered_ghec)
      metered_org = create(:organization, business: metered_business)

      trial = ::Copilot::BusinessTrial.create_trial!(metered_org,
        metered_org.admins.first,
        trial_length: 10,
        )
      trial.start_trial!

      create(:billing_product_uuid, :advanced_security)
      metered_business.subscribe_to_advanced_security_trial(
        actor: metered_business.owners.first,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )

      refute metered_business.digital_front_door?
    end

    test "returns true if feature flags are enabled and metered trial has CfB and GHAS" do
      GitHub.flipper[:digital_front_door_mvp].enable
      GitHub.flipper[:copilot_metered_enterprise].enable

      trial = ::Copilot::BusinessTrial.create_trial!(@org,
        @org.admins.first,
        trial_length: 10,
        )
      trial.start_trial!

      create(:billing_product_uuid, :advanced_security)
      @business.subscribe_to_advanced_security_trial(
        actor: @business.owners.first,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )

      assert @business.digital_front_door?
    end
  end
end unless GitHub.single_business_environment?
