# typed: true
# frozen_string_literal: true

require "test_helper"

class TrialDependencyTest < GitHub::TestCase

  fixtures do
    @owner = create(:user)
    @business = create(
      :business,
      :metered_ghec,
      trial_expires_at: 30.days.from_now,
      dfd_trial: true,
      owners: [@owner]
    )
    @payment_method = create(:payment_method, customer: @business.customer)
    @business.customer.update!(billing_type: ::Customer::BILLING_TYPE_CARD, billed_via_billing_platform: true)
    @org = create(:organization, business: @business, admins: [@owner])
    @other_org = create(:organization, admins: [@owner])
  end

  context "#digital_front_door?" do
    test "returns false for non-DFD trial business" do
      @business.update! dfd_trial: false

      trial = ::Copilot::BusinessTrial.create_trial!(@org,
      @org.admins.first,
      trial_length: 10,
      )
      trial.start_trial!

      refute @business.digital_front_door?
    end

    test "returns false if trial is not metered" do
      volume_trial = create(:business, trial_expires_at: 30.days.from_now)
      volume_org = create(:organization, business: volume_trial)
      refute volume_trial.metered_ghe?

      trial = ::Copilot::BusinessTrial.create_trial!(volume_org,
        volume_org.admins.first,
        trial_length: 10,
        )
      trial.start_trial!

      refute volume_trial.digital_front_door?
    end

    test "returns false if trial does not have Copilot trial" do
      refute @business.digital_front_door?
    end

    test "returns false if business is not an active trial" do
      metered_business = create(:business, :metered_ghec)
      metered_org = create(:organization, business: metered_business)

      trial = ::Copilot::BusinessTrial.create_trial!(metered_org,
        metered_org.admins.first,
        trial_length: 10,
        )
      trial.start_trial!

      refute metered_business.digital_front_door?
    end

    test "returns true for a metered, dfd trial business that has CfB" do
      trial = ::Copilot::BusinessTrial.create_trial!(@org,
        @org.admins.first,
        trial_length: 10,
        )
      trial.start_trial!

      assert @business.digital_front_door?
    end
  end

  context "#has_failed_trial_authorization?" do
    test "returns false for a metered, non-dfd trial business" do
      @business.update! dfd_trial: false

      trial = ::Copilot::BusinessTrial.create_trial!(@org,
      @org.admins.first,
      trial_length: 10,
      )
      trial.start_trial!

      refute @business.has_failed_trial_authorization?
    end

    test "returns false if trial is not metered" do
      volume_trial = create(:business, trial_expires_at: 30.days.from_now)
      volume_org = create(:organization, business: volume_trial)
      refute volume_trial.metered_ghe?

      trial = ::Copilot::BusinessTrial.create_trial!(volume_org,
        volume_org.admins.first,
        trial_length: 10,
        )
      trial.start_trial!

      refute volume_trial.has_failed_trial_authorization?
    end

    test "returns false if business is not an active trial" do
      metered_business = create(:business, :metered_ghec)
      metered_org = create(:organization, business: metered_business)

      trial = ::Copilot::BusinessTrial.create_trial!(metered_org,
        metered_org.admins.first,
        trial_length: 10,
        )
      trial.start_trial!

      refute metered_business.has_failed_trial_authorization?
    end

    test "returns false for a metered, dfd trial that has active CfB" do
      trial = ::Copilot::BusinessTrial.create_trial!(@org,
        @org.admins.first,
        trial_length: 10,
        )
      trial.start_trial!

      refute @business.has_failed_trial_authorization?
    end

    test "returns false for a metered dfd trial business that does not have customer" do
      @business.customer.destroy!
      refute @business.reload.customer

      refute @business.has_failed_trial_authorization?
    end

    test "returns false for a metered dfd trial business with no billing authorizations" do
      assert_empty @business.billing_transactions
      refute @business.has_failed_trial_authorization?
    end


    test "returns true for a dfd trial business whose last billing authorization is a failure" do
      unsuccessful_transaction = create(
        :billing_transaction,
        customer_id: @business.customer.id,
        transaction_type: "authorization",
        last_status: :processor_declined
      )

      assert @business.has_failed_trial_authorization?
    end

    test "returns false for a dfd trial business whose last billing authorization is a success" do
      unsuccessful_transaction = create(
        :billing_transaction,
        customer_id: @business.customer.id,
        transaction_type: "authorization",
        last_status: :processor_declined
      )

      successful_transaction = create(
        :billing_transaction,
        customer_id: @business.customer.id,
        transaction_type: "authorization",
        last_status: :authorization_cancelled
      )
      refute @business.has_failed_trial_authorization?
    end
  end

  context "#eligible_for_expired_trial_deletion?" do
    test "returns false for an enterprise managed business" do
      business = create(:business, :with_self_serve_payment, :enterprise_managed_business, trial_expires_at: 2.days.ago)

      assert_predicate business, :enterprise_managed_user_enabled?
      refute business.has_commercial_interaction_restriction?
      assert_predicate business, :trial_expired?
      refute_predicate business, :deleted?
      refute_predicate business, :trial_conversion_initiated?
      refute_predicate business, :invoiced?
      assert_empty business.organizations

      refute_predicate business, :eligible_for_expired_trial_deletion?
    end

    test "returns false if business has commercial interaction restriction" do
      account_screening_profile = create(:account_screening_profile, :with_business)
      account_screening_profile.hit_in_review!
      business = account_screening_profile.owner
      business.update(trial_expires_at: 2.days.ago)
      business.customer = create :credit_card_customer
      business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
      enable_feature_flag(:live_sdn_screening, business)

      refute_predicate business, :enterprise_managed_user_enabled?
      assert business.has_commercial_interaction_restriction?
      assert_predicate business, :trial_expired?
      refute_predicate business, :deleted?
      refute_predicate business, :trial_conversion_initiated?
      refute_predicate business, :invoiced?
      assert_empty business.organizations

      refute_predicate business, :eligible_for_expired_trial_deletion?
    end

    test "returns true for an expired trial EA with no organizations, if the feature flag is enabled" do
      enable_feature_flag(:expired_trial_deletion)
      business = create :business, :with_self_serve_payment, trial_expires_at: 10.days.ago
      refute_predicate business, :enterprise_managed_user_enabled?
      refute business.has_commercial_interaction_restriction?
      assert_predicate business, :trial_expired?
      refute_predicate business, :deleted?
      refute_predicate business, :trial_conversion_initiated?
      refute_predicate business, :invoiced?
      assert_empty business.organizations

      assert_predicate business, :eligible_for_expired_trial_deletion?
    end

    test "returns true for an expired trial EA with organizations if org feature flag is enabled" do
      enable_feature_flag(:expired_trial_deletion)
      enable_feature_flag(:expired_trial_org_deletion)
      business = create :business, :with_credit_card, trial_expires_at: 10.days.ago, organizations: [create(:organization)]
      refute_predicate business, :enterprise_managed_user_enabled?
      refute business.has_commercial_interaction_restriction?
      assert_predicate business, :trial_expired?
      refute_predicate business, :deleted?
      refute_predicate business, :trial_conversion_initiated?
      refute_predicate business, :invoiced?
      refute_empty business.organizations

      assert_predicate business, :eligible_for_expired_trial_deletion?
    end

    test "returns false for an expired trial EA with organizations if org feature flag is disabled and deletion date is not present" do
      enable_feature_flag(:expired_trial_deletion)
      disable_feature_flag(:expired_trial_org_deletion)
      business = create :business, :with_credit_card, trial_expires_at: 10.days.ago, organizations: [create(:organization)]
      refute_predicate business, :enterprise_managed_user_enabled?
      refute business.has_commercial_interaction_restriction?
      assert_predicate business, :trial_expired?
      refute_predicate business, :deleted?
      refute_predicate business, :trial_conversion_initiated?
      refute_predicate business, :invoiced?
      refute_empty business.organizations
      refute business.trial_deleted_at.present?

      refute_predicate business, :eligible_for_expired_trial_deletion?
    end

    test "returns true for an expired trial EA with organizations if org feature flag is disabled and deletion date is present" do
      enable_feature_flag(:expired_trial_deletion)
      disable_feature_flag(:expired_trial_org_deletion)
      business = create :business, :with_credit_card, trial_expires_at: 10.days.ago, trial_deleted_at: 80.days.from_now, organizations: [create(:organization)]
      refute_predicate business, :enterprise_managed_user_enabled?
      refute business.has_commercial_interaction_restriction?
      assert_predicate business, :trial_expired?
      refute_predicate business, :deleted?
      refute_predicate business, :trial_conversion_initiated?
      refute_predicate business, :invoiced?
      refute_empty business.organizations
      assert business.trial_deleted_at.present?

      assert_predicate business, :eligible_for_expired_trial_deletion?
    end

    test "returns false for a trial EA whose invoiced" do
      enable_feature_flag(:expired_trial_deletion)
      business = create :business, trial_expires_at: 10.days.ago

      refute_predicate business, :enterprise_managed_user_enabled?
      refute business.has_commercial_interaction_restriction?
      assert_predicate business, :trial_expired?
      refute_predicate business, :deleted?
      refute_predicate business, :trial_conversion_initiated?
      assert_predicate business, :invoiced?
      assert_empty business.organizations

      refute_predicate business, :eligible_for_expired_trial_deletion?
    end

    test "returns false for an active trial with no organizations" do
      enable_feature_flag(:expired_trial_deletion)
      business = create :business, :with_self_serve_payment, trial_expires_at: 2.days.from_now
      refute_predicate business, :enterprise_managed_user_enabled?
      refute business.has_commercial_interaction_restriction?
      refute_predicate business, :trial_expired?
      refute_predicate business, :deleted?
      refute_predicate business, :trial_conversion_initiated?
      refute_predicate business, :invoiced?
      assert_empty business.organizations

      refute_predicate business, :eligible_for_expired_trial_deletion?
    end

    test "returns false for an EA that's been soft deleted" do
      enable_feature_flag(:expired_trial_deletion)
      business = create :business, :with_self_serve_payment, trial_expires_at: 10.days.ago
      business.touch(:deleted_at)
      refute_predicate business, :enterprise_managed_user_enabled?
      refute business.has_commercial_interaction_restriction?
      assert_predicate business, :trial_expired?
      assert_predicate business, :deleted?
      refute_predicate business, :trial_conversion_initiated?
      refute_predicate business, :invoiced?
      assert_empty business.organizations

      refute_predicate business, :eligible_for_expired_trial_deletion?
    end

    test "returns false for a trial EA whose trial conversion has been initiated" do
      enable_feature_flag(:expired_trial_deletion)
      business = create :business, :with_self_serve_payment,  trial_expires_at: 10.days.ago
      business.trial_conversion_initiated!

      refute_predicate business, :enterprise_managed_user_enabled?
      refute business.has_commercial_interaction_restriction?
      assert_predicate business, :trial_expired?
      refute_predicate business, :deleted?
      assert_predicate business, :trial_conversion_initiated?
      refute_predicate business, :invoiced?
      assert_empty business.organizations

      refute_predicate business, :eligible_for_expired_trial_deletion?
    end

    test "returns false if the feature flag is disabled" do
      disable_feature_flag(:expired_trial_deletion)
      business = create :business, :with_self_serve_payment, trial_expires_at: 10.days.ago
      assert_predicate business, :trial_expired?
      refute_predicate business, :deleted?
      refute_predicate business, :trial_conversion_initiated?
      refute_predicate business, :invoiced?
      assert_empty business.organizations

      refute_predicate business, :eligible_for_expired_trial_deletion?
    end
  end

  context "#set_microsoft_analytics_kv" do
    test "creates a new unique ID in the kv store" do
      @business.set_microsoft_analytics_kv
      assert EnterpriseAccounts::KV.store.get(@business.microsoft_analytics_key).value { nil }.present?
    end
  end

  context "#get_microsoft_analytics_metadata" do
    test "returns a msft analytics metadata object if the business slug corresponds to a valid kv entry" do
      @business.set_microsoft_analytics_kv
      uuid = EnterpriseAccounts::KV.store.get(@business.microsoft_analytics_key).value { nil }

      assert_equal @business.get_microsoft_analytics_metadata,
        { order_id: uuid, product_title: "GitHub Enterprise Trial" }
    end

    test "returns nil if business slug is not present in the KV" do
      assert_nil EnterpriseAccounts::KV.store.get(@business.microsoft_analytics_key).value { nil }
      assert_nil @business.get_microsoft_analytics_metadata
    end
  end

  context "#trial_selectable_organizations" do
    if TestEnv.test_with_all_emus?
      test "returns empty array" do
        @other_org.update!(business: nil)
        assert_empty @business.trial_selectable_organizations(@owner)
      end
    else
      test "returns selectable orgs" do
        selectable_organizations = @business.trial_selectable_organizations(@owner)
        refute_empty selectable_organizations
        assert_includes selectable_organizations, @other_org
      end
    end
  end
end unless GitHub.single_business_environment?
