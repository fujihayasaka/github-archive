# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/enterprise_accounts/kv"

# Tests involving the creation of a new Business account, based on its 'trial_completion_status'.
# Currently includes trial, organization upgrades, and coupon redemption tests.
class CreationLifecycleTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include GitHub::ZuoraTestHelper
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers

  fixtures do
    @owner = create :user
    @billing_manager = create :user, login: "billing-manager"
    @org1 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @org2 = create :organization, plan: GitHub::Plan.business_plus, seats: 10

    only = [SyncBusinessOrganizationBillingSettingsJob, BusinessOrganizationBillingJob]
    @business = perform_enqueued_jobs only: only do
      create :business, :with_valid_contact_for_billing, :with_self_serve_payment, name: "CDE Ltd", owners: [@owner], organizations: [@org1, @org2], seats: 20
    end
    @business.billing.add_manager(@billing_manager, actor: @owner)

    @billing_contact = {
      entity_name: "CDE",
      country_code: "US",
      address1: "123 Main St",
      address2: "Danger Room",
      city: "San Francisco",
      postal_code: "94106",
      region: "CA",
    }
    @record = @billing_contact.merge({ vat_code: "1234567890" })

    unless GitHub.single_business_environment?
      @enterprise_managed_business = \
        create :business, business_type: :enterprise_managed, shortcode: "qqq"
      @upgrading_org = create :organization, name: "upgrading-org", plan: "business", admins: [@owner]
      @upgrading_business = perform_enqueued_jobs only: only do
        create :business, :with_valid_contact_for_billing, name: "Business to upgrade", owners: [@owner], upgrade_initiated_from_organization_id: @upgrading_org.id
      end
      @upgrading_business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
      @upgrading_org.upgrade_to_enterprise_in_progress!(@upgrading_business)
      @coupon_business = create :business, :with_valid_contact_for_billing, name: "couponed-biz", owners: [@owner]
      @coupon_business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
      @org_to_attach = create :organization, plan: "business", admins: [@owner]
      @coupon_business.upgrade_initiated_from_organization_id = @org_to_attach.id
      @org_to_attach.upgrade_to_enterprise_in_progress!(@coupon_business)
      @coupon = create :coupon, discount: 0.5, code: "real-ghec-coupon"
      @coupon_business.save!
      @org_to_attach.save!

      @business_emu_metered_trial = create(:business, :with_azure_subscription, business_type: :enterprise_managed, shortcode: "blue", owners: [@owner])
    end
  end

  setup do
    enable_feature_flag(:unbundle_ghas_for_new_org_ent)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    @coupon_business.redeem_coupon(@coupon.code, actor: @owner)
    unless GitHub.single_business_environment?
      @business_emu_metered_trial.customer.update!(metered_ghe: true)
      @business_emu_metered_trial.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
    end
    @shipping_contact = {
      entity_name: "Newspace, Inc.",
      address1: "789 Main St",
      city: "Boston",
      postal_code: "02110",
      country_code: "US",
      region: "MA"
    }
  end

  context "#eligible_for_trial?" do
    test "returns false for non-trial enterprise managed business" do
      @business.update(business_type: :enterprise_managed)
      assert_predicate @business, :enterprise_managed?
      refute_predicate @business, :eligible_for_trial?
    end

    test "returns true for trial enterprise managed business accounts" do
      @business.update(business_type: :enterprise_managed)
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      assert_predicate @business, :enterprise_managed?
      assert_predicate @business, :eligible_for_trial?
    end

    test "returns true for default managed business" do
      assert_predicate @business, :default_managed?
      assert_predicate @business, :eligible_for_trial?
    end
  end

  context "#trial?" do
    test "returns false for a non-trial business account" do
      refute @business.trial?
    end

    test "returns true when trial_expires_at is set" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert @business.trial?
    end
  end

  context "#authenticated_through_digital_front_door?" do
    test "returns true for a trial business with an authorized payment method" do
      @business.update! dfd_trial: true
      @business.customer = create :credit_card_customer
      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)  # Create a payment method
      # Create an authorized payment (authorization_cancelled is deemed a successful payment)
      create(:billing_transaction, transaction_type: "authorization", last_status: "authorization_cancelled", amount_in_cents: 4, customer: @business.customer, last_four: @business.payment_method.last_four)
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      assert_predicate @business, :authenticated_through_digital_front_door?
    end

    test "returns true for a trial business with an Azure subscription" do
      customer = create(:customer, :metered_ghe, :azure)
      azure_business = create(:business, customer: customer, trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now)
      azure_business.update! dfd_trial: true

      assert_predicate azure_business, :authenticated_through_digital_front_door?
    end

    test "returns false for non-DFD trial business" do
      @business.customer = create :credit_card_customer
      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)  # Create a payment method
      create(:billing_transaction, transaction_type: "authorization", last_status: "authorization_cancelled", amount_in_cents: 4, customer: @business.customer, last_four: @business.payment_method.last_four)
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      refute_predicate @business, :authenticated_through_digital_front_door?
    end

    test "returns false if the business is not on trial" do
      @business.update! dfd_trial: true
      @business.customer = create :credit_card_customer
      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)  # Create a payment method
      create(:billing_transaction, amount_in_cents: 4, customer: @business.customer)  # Create a successful payment

      refute_predicate @business, :trial?
      refute_predicate @business, :authenticated_through_digital_front_door?
    end

    test "returns false if the business has a valid payment method, but no authorized payments" do
      @business.update! dfd_trial: true
      @business.customer = create :credit_card_customer
      @business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)  # Create a payment method
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      assert_empty @business.billing_transactions.authorizations
      refute_predicate @business, :authenticated_through_digital_front_door?
    end

    test "returns false if the business has had authorized payments, but the payment method has changed" do
      @business.update! dfd_trial: true
      @business.customer = create :credit_card_customer
      create(:billing_transaction, transaction_type: "authorization", last_status: "authorization_cancelled", amount_in_cents: 4, customer: @business.customer, last_four: @business.payment_method.last_four)
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.payment_method.update!(last_four: "4321") # New payment method

      assert_predicate @business.reload, :has_valid_payment_method?
      refute_equal @business.payment_method.last_four, @business.billing_transactions.authorizations.last.last_four
      refute_predicate @business, :authenticated_through_digital_front_door?
    end

    test "returns false if the business has had an authorized payment in the past, but the most recent transition failed" do
      @business.update! dfd_trial: true
      @business.customer = create :credit_card_customer
      create(:billing_transaction, transaction_type: "authorization", last_status: "authorization_cancelled", amount_in_cents: 4, customer: @business.customer, last_four: @business.payment_method.last_four)  # Create a successful payment
      create(:billing_transaction, transaction_type: "authorization", last_status: "failed", amount_in_cents: 4, customer: @business.customer, last_four: @business.payment_method.last_four)  # Create a recent failed payment
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      refute_empty @business.billing_transactions.authorizations
      assert @business.billing_transactions.authorizations.last.failed?
      refute_predicate @business, :authenticated_through_digital_front_door?
    end
  end

  context "has_ongoing_copilot_business_trial?" do
    test "returns true if the business has an organization with an ongoing CB trial" do
      organization = create(:organization, admins: [@owner])
      @business.add_organization(organization)
      trial = create(:copilot_business_trial, :organization, trialable: organization)
      organization = trial.trialable

      assert_predicate @business, :has_ongoing_copilot_business_trial?
    end
    test "returns false if the business does not have any organizations with an ongoing CB trial" do
      organization = create(:organization, admins: [@owner])
      @business.add_organization(organization)
      trial = create(:copilot_business_trial, :organization, trialable: organization)
      organization = trial.trialable

      trial.cancel!

      assert_equal trial.state, "canceled"
      refute_predicate @business, :has_ongoing_copilot_business_trial?
    end
  end

  context "#cancel_trial_flavor" do
    test "returns Cancel for active trial" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?
      assert_equal "Cancel", @business.cancel_trial_flavor
    end

    test "returns Delete for expired trial" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.ago
      assert_predicate @business, :trial_expired?
      assert_equal "Delete", @business.cancel_trial_flavor
    end
  end

  context "#cancelling_trial_flavor" do
    test "returns cancelling for active trial" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?
      assert_equal "cancelling", @business.cancelling_trial_flavor
    end

    test "returns deleting for expired trial" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.ago
      assert_predicate @business, :trial_expired?
      assert_equal "deleting", @business.cancelling_trial_flavor
    end
  end

  context "#extended_trial?" do
    test "returns false for non-trial enterprise" do
      refute_predicate @business, :extended_trial?
    end

    test "returns false when trial expires at default time" do
      @business.update! \
        trial_expires_at: @business.created_at + Billing::EnterpriseCloudTrial.trial_length
      refute_predicate @business, :extended_trial?
    end

    test "returns true when trial expires after default time" do
      @business.update! \
        trial_expires_at: @business.created_at + Billing::EnterpriseCloudTrial.trial_length
      @business.update! \
        trial_expires_at: @business.trial_expires_at + Billing::EnterpriseCloudTrial.trial_length
      assert_predicate @business, :extended_trial?
    end
  end

  context "trial scope" do
    test "returns business accounts in trial" do
      assert_difference -> { Business.trial.count }, 1 do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      end
    end
  end

  context "#trial_expired?" do
    test "returns false for active trials" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      refute @business.trial_expired?
      assert_equal 0, Business.trial_expired.count
    end

    test "returns true when trial_expires_at is in the past" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.ago
      assert @business.trial_expired?
      assert_equal 1, Business.trial_expired.count
    end
  end

  context "trial_expired scope" do
    test "returns expired trials" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_equal 0, Business.trial_expired.count
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.ago
      assert_equal 1, Business.trial_expired.count
    end

    test "returns trials marked as expired" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_equal 0, Business.trial_expired.count
      @business.expire_trial
      assert_equal 1, Business.trial_expired.count
    end

    test "does not instrument when business is not a trial" do
      events = assert_performed_audit_entries(count: 0, only: "business.expire_trial") do
        refute @business.expire_trial
      end
      assert events.empty?
      assert_equal 0, GitHub.dogstats.increments("business.trial.expire").length
    end

    test "instruments business.expire_trial when trial is successfully cancelled" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      events = assert_performed_audit_entries(count: 1, only: "business.expire_trial") do
        @business.expire_trial
      end
      assert_equal 1, GitHub.dogstats.increments("business.trial.expire").length
    end
  end

  context "#can_update_trial_expires_at_manually?" do
    test "returns false for enterprise managed business" do
      assert_predicate @enterprise_managed_business, :enterprise_managed?
      refute_predicate @enterprise_managed_business, :can_update_trial_expires_at_manually?
    end

    test "returns false for default managed business on invoiced payments" do
      @business.customer.update! billing_type: Customer::BILLING_TYPE_INVOICE
      @business.reload
      assert_predicate @business, :default_managed?
      assert_predicate @business, :invoiced?
      refute_predicate @business, :can_update_trial_expires_at_manually?
    end

    test "returns false for default managed business on self-serve payments but not on trial" do
      assert_predicate @business, :default_managed?
      assert_predicate @business, :self_serve_payment?
      refute_predicate @business, :trial?
      refute_predicate @business, :can_update_trial_expires_at_manually?
    end

    test "returns false for business whose trial has expired" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
      @business.expire_trial(@owner)
      @business.reload

      assert_predicate @business, :default_managed?
      assert_predicate @business, :self_serve_payment?
      assert_predicate @business, :trial_expired?
      refute_predicate @business, :can_update_trial_expires_at_manually?
    end

    test "returns false for business whose trial has been cancelled" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        expires_at = @business.trial_expires_at
        @business.build_trade_screening_record(@record)
        @business.billing_contact.assign_attributes(@billing_contact)
        @business.shipping_contact.assign_attributes(@shipping_contact)
        @business.cancel_trial(@owner)
        @business.reload

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :CANCELLED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :CANCELLED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          enterprise_name: @business.name,
          billing_email: @business.billing_email,
          zuora_account_id: @business.customer.zuora_account_id,
          zuora_account_number: @business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
        assert_predicate @business, :default_managed?
        assert_predicate @business, :self_serve_payment?
        assert_predicate @business, :trial_cancelled?
        refute_predicate @business, :can_update_trial_expires_at_manually?
      end
    end

    test "returns false for emu metered business whose trial has been cancelled" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")

      travel_to jan_1st do
        @business_emu_metered_trial.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        @business_emu_metered_trial.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        expires_at = @business_emu_metered_trial.trial_expires_at

        @business_emu_metered_trial.build_trade_screening_record(@record)
        @business_emu_metered_trial.billing_contact.assign_attributes(@billing_contact)
        @business_emu_metered_trial.shipping_contact.assign_attributes(@shipping_contact)
        @business_emu_metered_trial.cancel_trial(@owner)
        @business_emu_metered_trial.reload

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business_emu_metered_trial),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :CANCELLED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: true,
          emu: true,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business_emu_metered_trial),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :CANCELLED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: true,
          emu: true,
          enterprise_name: @business_emu_metered_trial.name,
          billing_email: @business_emu_metered_trial.billing_email,
          zuora_account_id: @business_emu_metered_trial.customer.zuora_account_id,
          zuora_account_number: @business_emu_metered_trial.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
        assert_predicate @business_emu_metered_trial, :enterprise_managed?
        assert_predicate @business_emu_metered_trial, :self_serve_payment?
        assert_predicate @business_emu_metered_trial, :trial_cancelled?
        refute_predicate @business_emu_metered_trial, :can_update_trial_expires_at_manually?
      end
    end

    test "returns false for business whose trial conversion has been initiated" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
      @business.initiate_trial_conversion
      @business.reload

      assert_predicate @business, :default_managed?
      assert_predicate @business, :self_serve_payment?
      assert_predicate @business, :trial_conversion_initiated?
      refute_predicate @business, :can_update_trial_expires_at_manually?
    end

    test "returns false for business that has converted from trial" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
      @business.convert_trial(@owner)
      @business.reload

      assert_predicate @business, :default_managed?
      assert_predicate @business, :self_serve_payment?
      assert_predicate @business, :trial_converted?
      refute_predicate @business, :can_update_trial_expires_at_manually?
    end

    test "returns true for business with active trial" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
      @business.reload

      assert_predicate @business, :default_managed?
      assert_predicate @business, :self_serve_payment?
      assert_predicate @business, :trial?
      assert_predicate @business, :can_update_trial_expires_at_manually?
    end

    test "returns true for emu business with active trial and feature flag enabled" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
      @business.update(business_type: :enterprise_managed)
      @business.reload

      assert_predicate @business, :default_managed?
      assert_predicate @business, :self_serve_payment?
      assert_predicate @business, :trial?
      assert_predicate @business, :can_update_trial_expires_at_manually?
    end
  end

  context "#initiate_trial_conversion" do
    test "does not initiate conversion for non-trial business account" do
      @business.update_attribute :trial_expires_at, nil
      refute_predicate @business, :trial?

      @business.initiate_trial_conversion

      refute_predicate @business, :trial_conversion_initiated?
      assert_nil @business.trial_conversion_initiated_at
    end

    test "initiates conversion for trial business account" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?

      @business.initiate_trial_conversion

      assert_predicate @business, :trial_conversion_initiated?
      refute_nil @business.trial_conversion_initiated_at
    end

    test "clears the expired trial business deletion date, if it was set" do
      @business.update_attribute :trial_expires_at, 1.second.ago
      @business.update_attribute :trial_deleted_at, 7.days.from_now
      assert_predicate @business, :trial_expired?
      refute_nil @business.trial_deleted_at

      @business.initiate_trial_conversion

      assert_predicate @business, :trial_conversion_initiated?
      refute_nil @business.trial_conversion_initiated_at
      assert_nil @business.trial_deleted_at
    end

    test "no-ops wrt the expired trial business deletion date, if none was set" do
      @business.update_attribute :trial_expires_at, 1.second.ago
      assert_predicate @business, :trial_expired?
      assert_nil @business.trial_deleted_at

      assert_nothing_raised do
        @business.initiate_trial_conversion
      end

      assert_predicate @business, :trial_conversion_initiated?
      refute_nil @business.trial_conversion_initiated_at
      assert_nil @business.trial_deleted_at
    end
  end

  context "#convert_trial" do
    test "converts trial account to non-trial account" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @business.reload

      assert @business.trial?
      assert @business.convert_trial(@owner)
      refute @business.trial?
      refute_nil @business.trial_completed_at
      assert @business.trial_converted?
    end

    test "converts cancelled trial account to non-trial account" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @business.reload
      assert @business.cancel_trial(@owner)
      assert_predicate @business, :trial_cancelled?

      assert @business.convert_trial(@owner)

      refute_predicate @business, :trial?
      refute_predicate @business, :trial_cancelled?
      refute_predicate @business, :downgraded_to_free_plan?
      assert_predicate @business, :trial_converted?
      assert_equal GitHub::Plan.business_plus(account: @business), @business.plan
    end

    test "does nothing if account is not a trial" do
      refute @business.convert_trial
    end

    test "upgrades plan to business_plus for business downgraded to free plan", skip_enterprise: true do
      @business.update! trial_expires_at: GitHub::Billing.now, downgraded_at: GitHub::Billing.now
      @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @business.reload
      assert_predicate @business, :trial?
      assert_predicate @business, :downgraded_to_free_plan?

      @business.convert_trial @owner
      refute_predicate @business, :downgraded_to_free_plan?
      assert_equal GitHub::Plan.business_plus(account: @business), @business.plan
    end

    test "leaves metered billing type as card when payment is not Azure" do
      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD, metered_plan: true
      @business.reload
      assert_predicate @business, :trial?
      assert_predicate @business, :metered_plan?

      @business.convert_trial @owner
      @business.reload
      assert_predicate @business, :trial_converted?
      assert_equal Customer::BILLING_TYPE_CARD, @business.billing_type
    end

    test "sets seats to 0 for metered accounts" do
      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update!(
        billing_type: Customer::BILLING_TYPE_CARD,
        metered_plan: true,
        azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
        azure_subscription_name: "My subscription"
      )
      @business.reload
      assert_predicate @business, :trial?
      assert_predicate @business, :metered_plan?

      @business.convert_trial @owner
      @business.reload
      assert_predicate @business, :trial_converted?
      assert_equal 0, @business.seats
    end

    test "unsuspends first EMU owner for EMU business" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      perform_enqueued_jobs only: BusinessTrialCancellationCleanupJob do
        @business.cancel_trial(@owner)
      end

      first_emu_owner = @business.find_first_emu_owner
      assert_predicate first_emu_owner, :suspended?

      assert @business.convert_trial(@owner)
      refute_predicate first_emu_owner.reload, :suspended?
    end if TestEnv.test_with_all_emus?

    test "publishes hydro event" do
      Timecop.freeze("2023-04-01") do
        reset_hydro # clear any messages that were sent during setup

        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
        @business.reload
        expires_at = @business.trial_expires_at
        @business.billing_contact.assign_attributes(@billing_contact)
        @business.shipping_contact.assign_attributes(@shipping_contact)
        @business.convert_trial(@owner)

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :UPGRADED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :UPGRADED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          enterprise_name: "CDE Ltd",
          billing_email: @business.billing_email,
          zuora_account_id: @business.customer.zuora_account_id,
          zuora_account_number: @business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact,
          talk_to_sales: :UNKNOWN_STATE,
          payment_method: :CARD
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "publishes salesforce trial update hydro event for metered business with azure subscription" do
      Timecop.freeze("2023-04-01") do
        reset_hydro # clear any messages that were sent during setup

        customer = create(
          :customer,
          metered_ghe: true,
          azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
          azure_subscription_name: "My subscription"
        )
        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now, customer: customer
        @business.talk_to_sales = :YES
        @business.reload
        assert_predicate @business, :metered_ghe?
        assert_predicate @business, :linked_azure_subscription?

        expires_at = @business.trial_expires_at
        @business.build_trade_screening_record(@record)
        @business.billing_contact.assign_attributes(@billing_contact)
        @business.shipping_contact.assign_attributes(@shipping_contact)
        @business.convert_trial(@owner)

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :UPGRADED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: true,
          emu: false,
          enterprise_name: "CDE Ltd",
          billing_email: @business.billing_email,
          billing_information: @record,
          shipping_information: @shipping_contact,
          talk_to_sales: :YES,
          payment_method: :AZURE_SUBSCRIPTION
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "publishes salesforce trial update hydro event for business with credit card" do
      Timecop.freeze("2023-04-01") do
        reset_hydro # clear any messages that were sent during setup

        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        payment_method = create :payment_method, :zuora
        payment_method.update! customer: @business.customer
        @business.talk_to_sales = :YES
        assert_predicate @business.reload, :has_credit_card?

        expires_at = @business.trial_expires_at
        @business.trade_screening_record.assign_attributes(@record)
        @business.billing_contact.assign_attributes(@billing_contact)
        @business.shipping_contact.assign_attributes(@shipping_contact)
        @business.convert_trial(@owner)

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :UPGRADED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          enterprise_name: "CDE Ltd",
          billing_email: @business.billing_email,
          zuora_account_id: @business.customer.zuora_account_id,
          zuora_account_number: @business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact,
          talk_to_sales: :YES,
          payment_method: :CARD
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "publishes salesforce trial update hydro event for business that does not want to be contacted by sales" do
      Timecop.freeze("2023-04-01") do
        reset_hydro # clear any messages that were sent during setup

        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        payment_method = create :payment_method, :zuora
        payment_method.update! customer: @business.customer
        @business.talk_to_sales = :NO
        assert_predicate @business.reload, :has_credit_card?

        expires_at = @business.trial_expires_at
        @business.billing_contact.assign_attributes(@billing_contact)
        @business.shipping_contact.assign_attributes(@shipping_contact)
        @business.convert_trial(@owner)

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :UPGRADED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          enterprise_name: "CDE Ltd",
          billing_email: @business.billing_email,
          zuora_account_id: @business.customer.zuora_account_id,
          zuora_account_number: @business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact,
          talk_to_sales: :NO,
          payment_method: :CARD
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "publishes hydro event with upgraded organization information" do
      Timecop.freeze("2023-04-01") do
        reset_hydro # clear any messages that were sent during setup

        org = create :organization, admins: [@owner], plan: "business"
        business = create :business, upgraded_at: 1.day.ago, upgraded_from: org
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
        business.reload

        expires_at = business.trial_expires_at
        business.build_trade_screening_record(@record)
        business.billing_contact.assign_attributes(@billing_contact)
        business.shipping_contact.assign_attributes(@shipping_contact)
        business.convert_trial(@owner)

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :UPGRADED,
          expiration_timestamp: expires_at,
          upgraded_organization: Hydro::EntitySerializer.organization(org),
          metered: false,
          emu: false,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :UPGRADED,
          expiration_timestamp: expires_at,
          upgraded_organization: Hydro::EntitySerializer.organization(org),
          metered: false,
          emu: false,
          enterprise_name: business.name,
          billing_email: business.billing_email,
          zuora_account_id: business.customer.zuora_account_id,
          zuora_account_number: business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "removes transferred organization's references to zuora subscription when trial enterprise is converted" do
      synchronize_github_products_to_zuora
      owner = create(:user)
      business = create(:business, :with_self_serve_payment, trial_expires_at: 2.weeks.from_now, owners: [owner])
      transferred_org = create(:credit_card_org, admins: [owner])
      zuora_successful_customer_account_creation(business)
      zuora_successful_customer_account_creation(transferred_org)

      with_live_zuora("zuora/cancel_zuora_subscription_of_transferred_org") do
        business.reload
        transferred_org.reload
        plan_subscription = transferred_org.plan_subscription
        create(:billing_product_uuid, :github_plan, zuora_product_rate_plan_id: "product-rate-plan-id")
        Billing::PlanSubscription::Synchronizer.create(plan_subscription)

        invite = create(:business_organization_invitation, business: business, invitee: transferred_org, inviter: owner)
        invite.accept(owner)
        only = [SuspendPlanSubscriptionJob, SyncBusinessOrganizationBillingSettingsJob]
        assert_enqueued_jobs 1, only: only do
          invite.confirm(owner)
        end

        # Perform enqueued jobs outside of the scope of invite.confirm
        # to prevent nested transaction errors when there's not
        perform_enqueued_jobs only: only

        zuora_subscription = Billing::Zuora::Subscription.find(transferred_org.plan_subscription.zuora_subscription_number)
        assert T.must(zuora_subscription).suspended?
        refute_nil transferred_org.plan_subscription.zuora_subscription_number
        refute_nil transferred_org.plan_subscription.zuora_subscription_id

        assert business.trial?
        only = [SyncBusinessOrganizationBillingSettingsJob, CloseOutZuoraSubscriptionJob]
        perform_enqueued_jobs only: only do
          assert business.convert_trial(owner)
        end
        refute business.trial?

        plan_subscription = transferred_org.plan_subscription.reload
        assert_nil plan_subscription.zuora_subscription_number
        assert_nil plan_subscription.zuora_subscription_id
      end
    end

    test "removes upgraded_from organization reference to zuora subscription when trial enterprise is converted" do
      synchronize_github_products_to_zuora
      owner = create(:user)
      org = create(:organization, plan: GitHub::Plan.business_plus, seats: 10)
      business = create(:business, :with_self_serve_payment, trial_expires_at: 2.weeks.from_now, owners: [owner])
      zuora_successful_customer_account_creation(business)
      zuora_successful_customer_account_creation(org)

      with_live_zuora("zuora/cancel_zuora_subscription_of_upgraded_org") do
        business.reload
        org.reload
        plan_subscription = org.plan_subscription
        create(:billing_product_uuid, :github_plan, zuora_product_rate_plan_id: "product-rate-plan-id")
        Billing::PlanSubscription::Synchronizer.create(plan_subscription.reload)

        business.add_organization(org)
        business.upgraded_from = org
        business.save
        org.plan_subscription.suspend

        assert business.trial?
        only = [SyncBusinessOrganizationBillingSettingsJob, CloseOutZuoraSubscriptionJob]
        perform_enqueued_jobs only: only do
          assert business.convert_trial(owner)
        end
        refute business.trial?

        plan_subscription = org.plan_subscription.reload
        assert_nil plan_subscription.zuora_subscription_number
        assert_nil plan_subscription.zuora_subscription_id
      end
    end

    test "does not instrument when business is not a trial" do
      events = assert_performed_audit_entries(count: 0, only: "business.convert_trial") do
        refute @business.convert_trial
      end
      assert events.empty?

      assert_equal 0, GitHub.dogstats.increments("business.trial.convert").length
    end

    test "instruments when trial is successfully converted" do
      events = assert_performed_audit_entries(count: 1, only: "business.convert_trial") do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
        @business.reload
        @business.convert_trial
      end

      assert_equal 1, GitHub.dogstats.increments("business.trial.convert").length
    end

    test "does not enable auto-pay on trial conversion if business is affected by RBI restrictions" do
      business = create(:business, :with_self_serve_payment, trial_expires_at: 1.month.from_now, owners: [@owner])
      business.payment_method.update!(country: "IND")
      business.disable_automatic_self_serve_payment(User.ghost, reason: :india_rbi)
      assert_predicate business, :autopay_disabled_by_india_rbi?

      assert business.trial?
      assert business.convert_trial(@owner)
      refute business.trial?

      assert_predicate business, :trial_converted?
      refute_predicate business, :automatic_self_serve_payment_enabled?
      assert_predicate business, :autopay_disabled_by_india_rbi?
    end

    test "enables auto-pay and instruments toggle event for business remaining on self-serve payments" do
      Customer.any_instance.expects(:auto_pay?).returns(false)
      events = assert_performed_audit_entries(count: 1, only: "account.toggle_auto_pay") do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
        @business.convert_trial(@owner)
      end

      expected_payload = {
        business: @business.slug,
        business_id: @business.id,
        actor: @owner.login,
        actor_id: @owner.id,
        auto_pay_status: true,
        auto_pay_reason: :enterprise_purchase
      }

      @business.reload
      assert_predicate @business, :trial_converted?
      assert_predicate @business, :self_serve_payment?
      assert_predicate @business, :automatic_self_serve_payment_enabled?
      assert_subset_hash expected_payload, events.first
    end

    test "does not enable auto-pay and instrument toggle event for business switching to invoiced payments" do
      events = assert_performed_audit_entries(count: 0, only: "account.toggle_auto_pay") do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.convert_trial(@owner, switch_billing_to_invoice: true)
      end

      @business.reload
      assert_predicate @business, :trial_converted?
      assert_predicate @business, :invoiced?
      refute_predicate @business, :automatic_self_serve_payment_enabled?
      assert_empty events
    end

    test "job to sync billing settings to organizations enqueued", skip_enterprise: true do
      org = create :business_organization, business: @business
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @business.reload
      assert_predicate @business, :trial?

      assert_enqueued_with(
        job: SyncBusinessOrganizationBillingSettingsJob,
        args: [@business, enterprise_purchase: true, switch_org_billing_to_invoice: false]
      ) do
        @business.convert_trial(@owner)
      end

      refute_predicate @business, :trial?
      assert_predicate @business, :trial_converted?
    end

    test "job to update licenses enqueued", skip_enterprise: true do
      org = create :business_organization, business: @business
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @business.reload
      assert_predicate @business, :trial?

      assert_enqueued_with job: BusinessUpdateLicenseUsageJob, args: [@business.id] do
        @business.convert_trial(@owner)
      end
    end

    test "sends welcome email to admins" do
      enable_feature_flag(:ghec_receive_net_new_enterprise_account_email)

      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @business.reload

      @business.expects(:send_welcome_net_new_enterprise_account_email).once

      @business.convert_trial(@owner)
    end

    test "clears the expired trial business deletion date if one had been set" do
      @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @business.update_attribute :trial_expires_at, 1.second.ago
      @business.update_attribute :trial_deleted_at, 7.days.from_now

      assert_predicate @business, :trial_expired?
      refute_nil @business.trial_deleted_at

      assert @business.convert_trial(@owner)
      assert @business.trial_converted?
      assert_nil @business.trial_deleted_at
    end

    test "does nothing wrt the expired trial business deletion date if none had been set" do
      @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @business.update_attribute :trial_expires_at, 1.second.ago
      assert_nil @business.trial_deleted_at

      assert_nothing_raised do
        assert @business.convert_trial(@owner)
      end
      assert @business.trial_converted?
      assert_nil @business.trial_deleted_at
    end

    context "advanced security" do
      test "activates unbundled metered ghas on metered ghe businesses with advanced security trial" do
        create(:billing_product_uuid, :advanced_security)
        self_serve_business = create(:business, :with_self_serve_payment)
        owner = self_serve_business.owners.first
        self_serve_business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        self_serve_business.customer.update! metered_ghe: true
        self_serve_business.customer.azure_subscription_id = SecureRandom.uuid

        result = self_serve_business.subscribe_to_advanced_security_trial(
          actor: owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
        )

        assert self_serve_business.has_active_advanced_security_trial?

        perform_enqueued_jobs(only: [Billing::OnboardCustomerToProductInBillingPlatformJob]) do
          self_serve_business.convert_trial(owner)
        end

        self_serve_business.config.reset

        assert_equal Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED, self_serve_business.advanced_security_enabled_type_for_entity
        refute self_serve_business.has_active_advanced_security_trial?
      end

      # This test can eventually be removed when unbundle_ghas_for_new_org_ent is removed
      test "activates bundled metered ghas on metered ghe businesses with advanced security trial" do
        disable_feature_flag(:unbundle_ghas_for_new_org_ent)

        create(:billing_product_uuid, :advanced_security)
        self_serve_business = create(:business, :with_self_serve_payment)
        owner = self_serve_business.owners.first
        self_serve_business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        self_serve_business.customer.update! metered_ghe: true
        self_serve_business.customer.azure_subscription_id = SecureRandom.uuid

        result = self_serve_business.subscribe_to_advanced_security_trial(
          actor: owner,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
        )

        assert self_serve_business.has_active_advanced_security_trial?

        perform_enqueued_jobs(only: [Billing::OnboardCustomerToProductInBillingPlatformJob]) do
          self_serve_business.convert_trial(owner)
        end

        self_serve_business.config.reset

        assert_equal Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, self_serve_business.advanced_security_enabled_type_for_entity
        refute self_serve_business.has_active_advanced_security_trial?
      end
    end
  end

  context "#convert_trial_failed" do
    test "resets seat count to 50 if set higher" do
      @business.update trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now, seats: 1000
      @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @business.reload

      assert @business.trial?
      assert @business.convert_trial_failed
      assert_equal 50, @business.seats
      assert @business.trial?
      refute @business.trial_converted?
    end
  end

  context "trial_converted scope" do
    test "returns converted trials" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @business.reload

      assert_equal 0, Business.trial_converted.count
      assert @business.convert_trial
      assert_equal 1, Business.trial_converted.count
    end
  end

  context "#expire_trial" do
    test "expires trial account" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?
      refute_predicate @business, :trial_expired?
      assert_nil @business.trial_completed_at

      assert @business.expire_trial
      assert_predicate @business, :trial_expired?
      refute_nil @business.trial_completed_at
    end

    test "expires trial even when billing email is disposable" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?
      refute_predicate @business, :trial_expired?
      assert_nil @business.trial_completed_at

      email = "billing@gmai.com"
      assert UserEmail::DisposableEmailsDependency.disposable_email?(email)
      @business.update_column :billing_email, email
      refute_predicate @business, :valid?

      assert @business.expire_trial

      assert_predicate @business, :trial_expired?
      refute_nil @business.trial_completed_at
    end

    test "disables SAML on the business level" do
      provider = create(:business_saml_provider)
      business = provider.business
      business.update_attribute :trial_expires_at, GitHub::Billing.today - 1.day
      refute_nil business.saml_provider
      assert_predicate business, :trial?

      assert business.expire_trial(business.owners.first)

      assert_nil business.reload.saml_provider
    end

    test "cancels active GHAS trial" do
      @business.update_attribute :trial_expires_at, GitHub::Billing.today - 1.day
      create(:billing_product_uuid, :advanced_security)
      @business.customer.update! metered_ghe: true

      result = @business.subscribe_to_advanced_security_trial(
        actor: @business.owners.first,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )

      assert @business.has_active_advanced_security_trial?

      assert @business.expire_trial(@business.owners.first)

      refute @business.reload.has_active_advanced_security_trial?
    end

    test "does nothing if account is not a trial" do
      refute @business.expire_trial
    end

    test "removes invited organizations and retains organizations created in business" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      org = create :organization
      create :business_organization_invitation, business: @business, invitee: org, confirmed_at: Time.current
      @business.add_organization org
      @business.reload
      assert @business.organizations.count > 0
      assert @business.organization_invitations.count > 0

      orgs_to_retain = @business.organizations.count - @business.organization_invitations.count
      @business.expire_trial(@owner)
      @business.reload
      assert_equal orgs_to_retain, @business.organizations.count
    end

    test "removes invited organizations from business" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      invited_org_1 = create :organization
      invited_org_2 = create :organization
      [invited_org_1, invited_org_2].each do |org|
        create :business_organization_invitation, business: @business, invitee: org, confirmed_at: Time.current
        @business.add_organization(org)
      end
      assert @business.organizations.count > 1
      assert @business.organization_invitations.count > 1

      orgs_to_retain = @business.organizations.pluck(:id) - @business.organization_invitations.pluck(:invitee_id)

      @business.expire_trial(@owner)

      @business.reload
      assert_same_elements orgs_to_retain, @business.organizations.pluck(:id)
      refute_includes @business.organizations, invited_org_1
      refute_includes @business.organizations, invited_org_2
    end

    test "does not attempt to remove an organization that has already been removed" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      invited_org_1 = create :organization
      invited_org_2 = create :organization
      [invited_org_1, invited_org_2].each do |org|
        create :business_organization_invitation, business: @business, invitee: org, confirmed_at: Time.current
        @business.add_organization(org)
      end

      @business.remove_organization(invited_org_1)  # Remove an organization prior to expiring the trial

      # If Business::OrganizationIsNotMemberError is not raised, it means the removal was not attempted
      assert_nothing_raised do
        @business.expire_trial(@owner)
      end

      @business.reload
      refute_includes @business.organizations, invited_org_1
      refute_includes @business.organizations, invited_org_2
    end

    test "removes organization whose trial business created as a result of upgrading from the org" do
      org = create :organization
      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now, upgraded_from: org
      @business.add_organization org
      @business.reload
      assert_equal org, @business.upgraded_from
      assert_includes @business.organizations, org
      assert_empty @business.organization_invitations

      @business.expire_trial(@owner)
      refute_includes @business.reload.organizations, org
    end

    test "does not remove business membership of org that was upgraded into the trial if the org has already been removed", skip_enterprise: true do
      org = create :organization
      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now, upgraded_from: org
      @business.add_organization org
      assert_equal org, @business.upgraded_from
      assert_includes @business.organizations, org
      assert_empty @business.organization_invitations

      @business.remove_organization(org)

      new_business = create :business
      new_business.add_organization(org)

      @business.expire_trial(@owner)
      refute_includes @business.reload.organizations, org
      assert_includes new_business.reload.organizations, org  # The org's new business membership should not be destroyed
    end

    test "removes all pending organization invitations from business" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      free_org = create(:organization, plan: GitHub::Plan.free)
      invite = create :business_organization_invitation,
        business: @business, inviter: @owner, invitee: free_org
      assert_equal 1, @business.reload.organization_invitations.pending.count

      @business.expire_trial(@owner)
      assert_equal 0, @business.reload.organization_invitations.pending.count
    end

    test "retains confirmed organization invitations in business" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      free_org = create(:organization, plan: GitHub::Plan.free)
      invite = create(
        :business_organization_invitation,
        business: @business,
        inviter: @owner,
        invitee: free_org,
        confirmed_at: Time.current
      )
      assert_predicate invite, :confirmed?

      @business.expire_trial(@owner)
      assert_includes @business.reload.organization_invitations, invite
    end

    test "sends email to notify the admin that the trial has ended" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert @business.trial?
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          assert @business.expire_trial
          assert @business.trial?
          assert @business.trial_expired?
        end
      end
    end

    test "publishes hydro event" do
      Timecop.freeze("2023-04-01") do
        reset_hydro # clear any messages that were sent during setup

        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        expires_at = @business.trial_expires_at
        @business.build_trade_screening_record(@record)
        @business.billing_contact.assign_attributes(@billing_contact)
        @business.shipping_contact.assign_attributes(@shipping_contact)
        @business.expire_trial

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: nil,
          user_initiated: :AUTOMATION,
          status: :EXPIRED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: nil,
          user_initiated: :AUTOMATION,
          status: :EXPIRED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          enterprise_name: @business.name,
          billing_email: @business.billing_email,
          zuora_account_id: @business.customer.zuora_account_id,
          zuora_account_number: @business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "publishes hydro event with actor" do
      Timecop.freeze("2023-04-01") do
        reset_hydro # clear any messages that were sent during setup

        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        expires_at = @business.trial_expires_at
        @business.build_trade_screening_record(@record)
        @business.billing_contact.assign_attributes(@billing_contact)
        @business.shipping_contact.assign_attributes(@shipping_contact)
        @business.expire_trial

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: nil,
          user_initiated: :AUTOMATION,
          status: :EXPIRED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: nil,
          user_initiated: :AUTOMATION,
          status: :EXPIRED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          enterprise_name: @business.name,
          billing_email: @business.billing_email,
          zuora_account_id: @business.customer.zuora_account_id,
          zuora_account_number: @business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "publishes hydro event with upgraded organization information" do
      Timecop.freeze("2023-04-01") do
        reset_hydro # clear any messages that were sent during setup

        org = create :organization, admins: [@owner], plan: "business"
        business = create :business, upgraded_at: 1.day.ago, upgraded_from: org
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        business.build_trade_screening_record(@record)
        business.billing_contact.assign_attributes(@billing_contact)
        business.shipping_contact.assign_attributes(@shipping_contact)

        expires_at = business.trial_expires_at
        business.expire_trial(@owner)

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :STAFF,
          status: :EXPIRED,
          expiration_timestamp: expires_at,
          upgraded_organization: Hydro::EntitySerializer.organization(org),
          metered: false,
          emu: false,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :STAFF,
          status: :EXPIRED,
          expiration_timestamp: expires_at,
          upgraded_organization: Hydro::EntitySerializer.organization(org),
          metered: false,
          emu: false,
          enterprise_name: business.name,
          billing_email: business.billing_email,
          zuora_account_id: business.customer.zuora_account_id,
          zuora_account_number: business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "downgrades account" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      refute @business.downgraded_to_free_plan?
      assert @business.trial?
      assert @business.expire_trial
      assert @business.trial?
      assert @business.downgraded_to_free_plan?
    end

    test "reverts org to previous plan" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      organization = create(:organization, plan: :business, seats: 10)
      create(
        :business_organization_invitation,
        business: @business,
        invitee: organization,
        confirmed_at: Time.current
      )
      @business.add_organization(organization)
      @business.reload
      assert_equal "business_plus", organization.reload.plan.name
      assert @business.expire_trial
      assert_equal "business", organization.reload.plan.name
    end

    test "resumes billing for an invited organization that was removed from a trial due to expiration" do
      invited_org = create(:credit_card_org, admin: @owner)
      create(:business_organization_invitation, business: @business, invitee: invited_org, confirmed_at: Time.current)
      plan_subscription = create(:billing_plan_subscription, user: invited_org)

      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      @business.add_organization(invited_org)

      assert_enqueued_jobs 1, only: ResumePlanSubscriptionJob do
        @business.expire_trial
      end
    end

    test "resumes billing for an upgraded organization that was removed from a trial due to expiration" do
      upgraded_org = create(:credit_card_org, admin: @owner)
      plan_subscription = create(:billing_plan_subscription, user: upgraded_org)

      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now, upgraded_from: upgraded_org
      @business.add_organization(upgraded_org)

      assert_enqueued_jobs 1, only: ResumePlanSubscriptionJob do
        @business.expire_trial
      end
    end

    test "sets the trial deletion date, and notifies admins of upcoming EA deletion 30, 60, 83, and 89 days after trial expiration, if the business is eligible for expired trial deletion, and the feature flag is enabled" do
      enable_feature_flag(:expired_trial_deletion)
      # need to delete all existing businesses, to ensure that other existing EA trial fixtures
      # don't expire and trigger the deletion job
      Business.delete_all
      frozen_date = (Business::EXPIRED_TRIAL_DELETION_CUTOFF_DATE - 1.year).freeze
      business = create :business, :with_self_serve_payment, trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      travel_to frozen_date do
        business.expire_trial
      end

      trial_deleted_at = business.trial_deleted_at
      assert_predicate business, :eligible_for_expired_trial_deletion?
      refute_nil trial_deleted_at

      [60, 30, 7, 1].each do |days_to_deletion|
        travel_to trial_deleted_at.to_datetime - days_to_deletion.days do
          assert_equal Business.trial_expired.count, 1
          assert_predicate business, :eligible_for_expired_trial_deletion?
          assert_enqueued_jobs(1, only: [ApplicationDeliveryJob]) do
            NotifyExpiredTrialsJob.perform_now
          end
        end
      end

      queued_email_jobs = enqueued_jobs.select do |job|
        job["job_class"] == "ApplicationDeliveryJob" && \
        job["arguments"].first == "BusinessMailer" && \
        job["arguments"].second == "notify_expired_trial_admins"
      end
      assert_equal queued_email_jobs.count, 4
    end

    test "publishes hydro events recording emailing of admins 30, 60, 83, and 89 days after trial expiration, if the business is eligible for expired trial deletion, and the feature flag is enabled" do
      enable_feature_flag(:expired_trial_deletion)
      # need to delete all existing businesses, to ensure that other existing EA trial fixtures
      # don't expire and trigger the deletion job
      Business.delete_all
      frozen_date = (Business::EXPIRED_TRIAL_DELETION_CUTOFF_DATE - 1.year).freeze
      business = create :business, :with_self_serve_payment, trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      travel_to frozen_date do
        business.expire_trial
      end

      assert_predicate business, :eligible_for_expired_trial_deletion?
      trial_deleted_at = business.trial_deleted_at
      refute_nil trial_deleted_at

      [60, 30, 7, 1].each do |days_to_deletion|
        travel_to trial_deleted_at.to_datetime - days_to_deletion.days do
          assert_enqueued_jobs(1, only: [ApplicationDeliveryJob]) do
            NotifyExpiredTrialsJob.perform_now
          end

          assert_hydro_published({
            enterprise: Hydro::EntitySerializer.business(business),
            trial_deleted_at: trial_deleted_at.to_s,
            days_to_deletion: days_to_deletion,
            action_taken: :EMAIL,
          }, schema: "github.enterprise_account.v0.ExpiredTrialDeletion")
        end
      end
    end

    test "soft-deletes the business after 90 days after expiration and hard-deletes the business after another 90 days if the business is eligible for expired trial deletion, and the feature flag is enabled" do
      enable_feature_flag(:expired_trial_deletion)
      # need to delete all existing businesses, to ensure that other existing EA trial fixtures
      # don't expire and trigger the deletion job
      Business.delete_all
      frozen_date = (Business::EXPIRED_TRIAL_DELETION_CUTOFF_DATE - 1.year).freeze
      business = create :business, :with_self_serve_payment, trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      business_id = business.id
      travel_to frozen_date do
        business.expire_trial
      end

      trial_deleted_at = business.reload.trial_deleted_at
      refute_nil trial_deleted_at

      travel_to trial_deleted_at.to_datetime do
        assert_equal Business.trial_expired.count, 1
        assert_predicate business, :eligible_for_expired_trial_deletion?
        assert_enqueued_jobs(1, only: [ApplicationDeliveryJob]) do
          DeleteExpiredTrialsJob.perform_now
        end

        queued_email_jobs = enqueued_jobs.select do |job|
          job["job_class"] == "ApplicationDeliveryJob" && \
          job["arguments"].first == "BusinessMailer" && \
          job["arguments"].second == "notify_expired_enterprise_trial_deleted"
        end

        assert_predicate business.reload, :deleted?
        assert_equal queued_email_jobs.count, 1
      end

      # check if the business gets hard deleted after 90 days
      travel_to trial_deleted_at.to_datetime + 90.days + 1.second do
        assert_equal Business.deleted.count, 1

        assert_performed_jobs(1, only: [DestroyBusinessJob]) do
          PurgeSoftDeletedBusinessesJob.perform_now
        end

        assert_nil Business.find_by(id: business_id)
      end
    end

    test "does not set the trial deletion date, or notifies admins of upcoming EA deletion, or soft deletes the business, if the feature flag is disabled" do
      disable_feature_flag(:expired_trial_deletion)
      frozen_date = (Business::EXPIRED_TRIAL_DELETION_CUTOFF_DATE - 1.year).freeze
      business = create :business, :with_self_serve_payment,  trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      travel_to frozen_date do
        business.expire_trial
      end

      refute_predicate business, :eligible_for_expired_trial_deletion?
      assert_nil business.trial_deleted_at

      # have to work from the expiration date here, since there is no
      # set trial deletion date. Would be 90 days from frozen_date if it had
      # been set, thus we'd expect emails on the days post-expiration below.
      [30, 60, 83, 89].each do |num_days_since_expiration|
        travel_to frozen_date + num_days_since_expiration.days do
          assert_no_performed_jobs(only: [ApplicationDeliveryJob]) do
            NotifyExpiredTrialsJob.perform_now
          end
        end
      end

      travel_to frozen_date + 90.days do
        DeleteExpiredTrialsJob.perform_now
        refute_predicate business, :deleted?
      end
    end

    test "does not set the trial deletion date, or notifies admins of upcoming EA deletion, or soft deletes the business, if the account is staff-owned" do
      enable_feature_flag(:expired_trial_deletion)
      frozen_date = (Business::EXPIRED_TRIAL_DELETION_CUTOFF_DATE - 1.year).freeze
      staff_admin = create :staff_admin_user
      business = create :business, :with_self_serve_payment, owners: [staff_admin], staff_owned: true,  trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      travel_to frozen_date do
        business.expire_trial
      end

      refute_predicate business, :eligible_for_expired_trial_deletion?
      assert_nil business.trial_deleted_at

      # have to work from the expiration date here, since there is no
      # set trial deletion date. Would be 90 days from frozen_date if it had
      # been set, thus we'd expect emails on the days post-expiration below.
      [30, 60, 83, 89].each do |num_days_since_expiration|
        travel_to frozen_date + num_days_since_expiration.days do
          assert_no_performed_jobs(only: [ApplicationDeliveryJob]) do
            NotifyExpiredTrialsJob.perform_now
          end
        end
      end

      travel_to frozen_date + 90.days do
        DeleteExpiredTrialsJob.perform_now
        refute_predicate business, :deleted?
      end
    end

    test "does not set the trial deletion date, notifies admins of upcoming EA deletion, or soft-deletes the business, if the expired trial is invoiced" do
      enable_feature_flag(:expired_trial_deletion)
      frozen_date = (Business::EXPIRED_TRIAL_DELETION_CUTOFF_DATE - 1.year).freeze
      business = create :business, trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      travel_to frozen_date do
        business.expire_trial
      end

      business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_INVOICE

      refute_predicate business, :eligible_for_expired_trial_deletion?
      assert_nil business.trial_deleted_at

      # have to work from the expiration date here, since there is no
      # set trial deletion date. Would be 90 days from frozen_date if it had
      # been set, thus we'd expect emails on the days post-expiration below.
      [30, 60, 83, 89].each do |num_days_since_expiration|
        travel_to frozen_date + num_days_since_expiration.days do
          assert_no_performed_jobs(only: [ApplicationDeliveryJob]) do
            NotifyExpiredTrialsJob.perform_now
          end
        end
      end

      travel_to frozen_date + 90.days do
        DeleteExpiredTrialsJob.perform_now
        refute_predicate business, :deleted?
      end
    end
  end

  context "#cancel_trial" do
    test "converts trial account to non-trial account" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert @business.trial?
      assert @business.cancel_trial(@owner)
      refute @business.trial?
      refute_nil @business.trial_completed_at
      assert @business.trial_cancelled?
    end

    test "cancels active GHAS trial" do
      @business.update_attribute :trial_expires_at, GitHub::Billing.today - 1.day
      create(:billing_product_uuid, :advanced_security)
      @business.customer.update! metered_ghe: true
      assert @business.trial?

      @business.subscribe_to_advanced_security_trial(
        actor: @business.owners.first,
        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month
      )

      assert @business.has_active_advanced_security_trial?

      assert @business.cancel_trial(@business.owners.first)

      refute @business.reload.has_active_advanced_security_trial?
    end

    test "does nothing if account is not a trial" do
      refute @business.cancel_trial(@owner)
    end

    test "disables SAML on the business level" do
      provider = create(:business_saml_provider)
      business = provider.business
      business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      refute_nil business.saml_provider
      assert_predicate business, :trial?

      assert business.cancel_trial(business.owners.first)

      assert_nil business.reload.saml_provider
    end

    test "removes all owners from business" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert @business.owners.count > 0
      perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob]) do
        @business.cancel_trial(@owner)
      end
      assert_equal 0, @business.owners.count
    end

    test "removes all billing managers from business" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert @business.billing_managers.count > 0
      perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob]) do
        @business.cancel_trial(@owner)
      end
      assert_equal 0, @business.billing_managers.count
    end

    test "removes all members from the cancelled enterprise trial who were part of organizations that were transfered out" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      org_member = create(:user)
      org_owner = create(:user)
      invited_org = create(:organization)
      invited_org.add_member(org_member)
      invited_org.add_admin(org_owner)

      create :business_organization_invitation, business: @business, invitee: invited_org, confirmed_at: Time.current

      @business.add_organization(invited_org)
      assert @business.member?(org_member)
      assert @business.member?(org_owner)

      perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob, RemoveOrgAdminJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @business.cancel_trial(@owner)
      end

      @business.reload
      refute_includes @business.organizations, invited_org

      # Members should not be removed from orgs that were upgraded, or invited into the enterprise.
      assert invited_org.member?(org_member)
      assert invited_org.member?(org_owner)
      assert invited_org.adminable_by?(org_owner)

      # All members should be removed from the enterprise
      refute @business.member?(org_member)
      refute @business.member?(org_owner)

      assert_equal @business.members.count, 0
    end

    test "removes all members from the cancelled enterprise trial who were part of organizations that were locked in" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      org_member = create(:user)
      org_owner = create(:user)
      created_org = create(:organization)
      created_org.add_member(org_member)
      created_org.add_admin(org_owner)

      @business.add_organization(created_org)
      assert @business.member?(org_member)
      assert @business.member?(org_owner)

      perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob, RemoveOrgAdminJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @business.cancel_trial(@owner)
      end

      @business.reload
      assert_includes @business.organizations, created_org

      # Members should be removed from orgs that were created during the trial.
      refute created_org.member?(org_member)
      refute created_org.member?(org_owner)
      refute created_org.adminable_by?(org_owner)

      # All members should be removed from the enterprise
      refute @business.member?(org_member)
      refute @business.member?(org_owner)

      assert_equal @business.members.count, 0
    end

    test "removes all members from the cancelled enterprise trial who were part of the organization that upgraded into the trial and got transferred out" do
      upgraded_org = create :organization
      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now, upgraded_from: upgraded_org

      org_member = create(:user)
      org_owner = create(:user)
      upgraded_org.add_member(org_member)
      upgraded_org.add_admin(org_owner)

      @business.add_organization(upgraded_org)
      assert_equal upgraded_org, @business.upgraded_from
      assert_includes @business.organizations, upgraded_org
      assert @business.member?(org_member)
      assert @business.member?(org_owner)

      perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob, RemoveOrgAdminJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @business.cancel_trial(@owner)
      end

      @business.reload
      refute_includes @business.organizations, upgraded_org

      # Members should not be removed from orgs that were upgraded, or invited into the enterprise.
      assert upgraded_org.member?(org_member)
      assert upgraded_org.member?(org_owner)
      assert upgraded_org.adminable_by?(org_owner)

      # All members should be removed from the enterprise
      refute @business.member?(org_member)
      refute @business.member?(org_owner)

      assert_equal @business.members.count, 0
    end

    test "removes invited organizations from business" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      invited_org_1 = create :organization
      invited_org_2 = create :organization
      [invited_org_1, invited_org_2].each do |org|
        create :business_organization_invitation, business: @business, invitee: org, confirmed_at: Time.current
        @business.add_organization(org)
      end
      assert @business.organizations.count > 1
      assert @business.organization_invitations.count > 1

      orgs_to_retain = @business.organizations.pluck(:id) - @business.organization_invitations.pluck(:invitee_id)
      perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob]) do
        @business.cancel_trial(@owner)
      end
      @business.reload

      assert_same_elements orgs_to_retain, @business.organizations.pluck(:id)
      refute_includes @business.organizations, invited_org_1
      refute_includes @business.organizations, invited_org_2
    end

    test "does not attempt to remove an organization that has already been removed" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      invited_org_1 = create :organization
      invited_org_2 = create :organization
      [invited_org_1, invited_org_2].each do |org|
        create :business_organization_invitation, business: @business, invitee: org, confirmed_at: Time.current
        @business.add_organization(org)
      end

      @business.remove_organization(invited_org_1)  # Remove an organization prior to cancelling the trial

      # If Business::OrganizationIsNotMemberError is not raised, it means the removal was not attempted
      assert_nothing_raised do
        perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob]) do
          @business.cancel_trial(@owner)
        end
        @business.reload
      end

      refute_includes @business.organizations, invited_org_1
      refute_includes @business.organizations, invited_org_2
    end

    test "removes both organizations that were upgraded into the business, and invited organizations" do
      upgraded_org = create :organization
      invited_org = create :organization

      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now, upgraded_from: upgraded_org
      @business.add_organization upgraded_org

      create :business_organization_invitation, business: @business, invitee: invited_org, confirmed_at: Time.current
      @business.add_organization invited_org

      assert_equal upgraded_org, @business.upgraded_from

      orgs_to_retain = @business.organizations.count - @business.organization_invitations.count - 1
      perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob]) do
        @business.cancel_trial(@owner)
      end
      @business.reload

      assert_equal orgs_to_retain, @business.organizations.count
      refute_includes @business.organizations, invited_org
      refute_includes @business.organizations, upgraded_org
    end

    test "does not remove business membership of org that was upgraded into the trial if the org has already been removed", skip_enterprise: true do
      upgraded_org = create :organization

      @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now, upgraded_from: upgraded_org
      @business.add_organization upgraded_org
      assert_equal upgraded_org, @business.upgraded_from

      @business.remove_organization(upgraded_org)

      new_business = create :business
      new_business.add_organization(upgraded_org)

      orgs_to_retain = @business.organizations.count - @business.organization_invitations.count
      perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob]) do
        @business.cancel_trial(@owner)
      end
      @business.reload

      assert_equal orgs_to_retain, @business.organizations.count
      refute_includes @business.organizations, upgraded_org
      assert_includes new_business.organizations, upgraded_org  # The org's new business membership should not be destroyed
    end

    test "removes all pending organization invitations from business" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      free_org = create(:organization, plan: GitHub::Plan.free)
      invite = create :business_organization_invitation,
        business: @business, inviter: @owner, invitee: free_org
      perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob]) do
        @business.cancel_trial(@owner)
      end
      assert_equal 0, @business.organization_invitations.count
    end

    test "does not instrument when business is not a trial" do
      events = assert_performed_audit_entries(count: 0, only: "business.cancel_trial") do
        refute @business.cancel_trial(@owner)
      end
      assert events.empty?
      assert_equal 0, GitHub.dogstats.increments("business.trial.cancel").length
    end

    test "instruments business.cancel_trial when trial is successfully cancelled" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      events = assert_performed_audit_entries(count: 1, only: "business.cancel_trial") do
        @business.cancel_trial(@owner)
      end
      assert_equal 1, GitHub.dogstats.increments("business.trial.cancel").length
    end

    test "publishes hydro event" do
      Timecop.freeze("2023-04-01") do
        reset_hydro # clear any messages that were sent during setup

        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        expires_at = @business.trial_expires_at
        @business.build_trade_screening_record(@record)
        @business.billing_contact.assign_attributes(@billing_contact)
        @business.shipping_contact.assign_attributes(@shipping_contact)
        @business.cancel_trial(@owner)

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :CANCELLED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :CANCELLED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          enterprise_name: @business.name,
          billing_email: @business.billing_email,
          zuora_account_id: @business.customer.zuora_account_id,
          zuora_account_number: @business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    test "publishes hydro event with upgraded organization information" do
      Timecop.freeze("2023-04-01") do
        reset_hydro # clear any messages that were sent during setup

        org = create :organization, admins: [@owner], plan: "business"
        business = create :business, upgraded_at: 1.day.ago, upgraded_from: org
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        expires_at = business.trial_expires_at
        business.build_trade_screening_record(@record)
        business.billing_contact.assign_attributes(@billing_contact)
        business.shipping_contact.assign_attributes(@shipping_contact)
        business.cancel_trial(@owner)

        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :CANCELLED,
          expiration_timestamp: expires_at,
          upgraded_organization: Hydro::EntitySerializer.organization(org),
          metered: false,
          emu: false,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :USER,
          status: :CANCELLED,
          expiration_timestamp: expires_at,
          upgraded_organization: Hydro::EntitySerializer.organization(org),
          metered: false,
          emu: false,
          enterprise_name: business.name,
          billing_email: business.billing_email,
          zuora_account_id: business.customer.zuora_account_id,
          zuora_account_number: business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end
    end

    if GitHub.billing_enabled?
      test "downgrades enterprise to the free plan" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        refute @business.downgraded_to_free_plan?
        assert @business.trial?
        assert @business.cancel_trial(@owner)
        refute @business.trial?
        assert @business.downgraded_to_free_plan?
      end

      test "downgrades enterprise and associated orgs to the free plan" do
        org1 = create(:organization, plan: :business_plus)
        org2 = create(:organization, plan: :business_plus)

        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        refute @business.downgraded_to_free_plan?
        assert @business.trial?

        @business.add_organization(org1)
        @business.add_organization(org2)
        assert_equal "business_plus", org1.plan.name
        assert_equal "business_plus", org2.plan.name

        perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob]) do
          @business.cancel_trial(@owner)
        end

        refute @business.trial?
        assert @business.downgraded_to_free_plan?
        assert_equal "free", org1.reload.plan.name
        assert_equal "free", org2.reload.plan.name
      end

      test "invited organizations that are removed from a canceled trial are not downgraded to the free plan" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        org = create(:organization, plan: :business_plus)
        assert_equal "business_plus", org.plan.name

        create :business_organization_invitation, business: @business, invitee: org, confirmed_at: Time.current
        @business.add_organization org
        assert_includes @business.organizations, org

        perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob]) do
          @business.cancel_trial(@owner)
        end

        refute_includes @business.reload.organizations, org
        assert_equal "business_plus", org.reload.plan.name
      end

      test "cancels an expired trial" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        refute @business.downgraded_to_free_plan?
        assert @business.trial?

        assert @business.expire_trial
        assert @business.trial?

        assert @business.cancel_trial(@owner)
        refute @business.trial?
        assert @business.downgraded_to_free_plan?
      end

      test "reverts org to previous plan" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        organization = create(:organization, plan: :business, seats: 10)
        create(
          :business_organization_invitation,
          business: @business,
          invitee: organization,
          confirmed_at: Time.current
        )
        @business.add_organization(organization)
        assert_equal "business_plus", organization.reload.plan.name

        perform_enqueued_jobs(only: [BusinessTrialCancellationCleanupJob]) do
          @business.cancel_trial(@owner)
        end
        assert_nil organization.reload.business
        assert_equal "business", organization.reload.plan.name
      end

      test "resumes billing for an invited organization that was removed from a trial due to cancellation" do
        invited_org = create(:credit_card_org, admin: @owner)
        create(:business_organization_invitation, business: @business, invitee: invited_org, confirmed_at: Time.current)
        plan_subscription = create(:billing_plan_subscription, user: invited_org)

        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.add_organization(invited_org)

        @business.cancel_trial(@owner)
        assert_enqueued_jobs 1, only: ResumePlanSubscriptionJob do
          BusinessTrialCancellationCleanupJob.perform_now(@business)
        end
      end

      test "resumes billing for an upgraded organization that was removed from a trial due to cancellation" do
        upgraded_org = create(:credit_card_org, admin: @owner)
        plan_subscription = create(:billing_plan_subscription, user: upgraded_org)

        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now, upgraded_from: upgraded_org
        @business.add_organization(upgraded_org)

        @business.cancel_trial(@owner)
        assert_enqueued_jobs 1, only: ResumePlanSubscriptionJob do
          BusinessTrialCancellationCleanupJob.perform_now(@business)
        end
      end

      test "cancels trial for active trial business on metered plan billing" do
        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update! metered_plan: true
        assert_predicate @business.reload, :metered_plan?
        assert_predicate @business, :trial?
        refute_predicate @business, :trial_expired?
        refute_predicate @business, :trial_cancelled?

        @business.cancel_trial(@owner)
        assert_predicate @business, :trial_cancelled?
        assert_predicate @business, :downgraded_to_free_plan?
      end

      test "cancels trial for expired trial business on metered plan billing" do
        @business.update! trial_expires_at: 2.days.ago
        @business.customer.update! metered_plan: true
        assert_predicate @business.reload, :metered_plan?
        assert_predicate @business, :trial_expired?
        refute_predicate @business, :trial_cancelled?

        @business.cancel_trial(@owner)
        assert_predicate @business, :trial_cancelled?
        assert_predicate @business, :downgraded_to_free_plan?
      end

      test "removes azure subscription for business on metered plan billing" do
        @business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update!(
          metered_plan: true,
          azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
          azure_subscription_name: "My subscription"
        )
        @business.reload
        assert_predicate @business, :metered_plan?
        assert_predicate @business, :linked_azure_subscription?
        refute_predicate @business, :trial_cancelled?

        @business.cancel_trial(@owner)
        @business.reload
        refute_predicate @business, :linked_azure_subscription?
        assert_predicate @business, :trial_cancelled?
      end
    end
  end

  context "#extend_trial" do
    if GitHub.billing_enabled?
      test "extends trial enterprise trial by 30 days" do
        @business.update_attribute :trial_expires_at, 1.day.from_now

        assert @business.extend_trial(@owner)
        assert @business.extended_trial?
        assert_equal 31.days.from_now.to_date, @business.trial_expires_at.to_date
      end

      test "instruments business.extend_trial when trial period is successfully extended" do
        @business.update_attribute :trial_expires_at, 1.day.from_now

        events = assert_performed_audit_entries(count: 1, only: "business.extend_trial") do
          @business.extend_trial(@owner)
        end

        assert @business.extended_trial?
        assert_equal 1, GitHub.dogstats.increments("business.trial.extend").length
      end

      test "publishes hydro event" do
        reset_hydro # clear any messages that were sent during setup
        @business.update_attribute :trial_expires_at, 1.day.from_now
        @business.build_trade_screening_record(@record)
        @business.billing_contact.assign_attributes(@billing_contact)
        @business.shipping_contact.assign_attributes(@shipping_contact)
        @business.extend_trial(@owner)
        expires_at = @business.reload.trial_expires_at

        assert @business.extended_trial?
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :STAFF,
          status: :EXTENDED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(@business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :STAFF,
          status: :EXTENDED,
          expiration_timestamp: expires_at,
          upgraded_organization: nil,
          metered: false,
          emu: false,
          enterprise_name: @business.name,
          billing_email: @business.billing_email,
          zuora_account_id: @business.customer.zuora_account_id,
          zuora_account_number: @business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end

      test "publishes hydro event with upgraded organization information" do
        reset_hydro # clear any messages that were sent during setup

        org = create :organization, admins: [@owner], plan: "business"
        business = create :business, upgraded_at: 1.day.ago, upgraded_from: org
        business.update_attribute :trial_expires_at, 1.day.from_now

        business.build_trade_screening_record(@record)
        business.billing_contact.assign_attributes(@billing_contact)
        business.shipping_contact.assign_attributes(@shipping_contact)
        business.extend_trial(@owner)
        expires_at = business.reload.trial_expires_at

        assert business.extended_trial?
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :STAFF,
          status: :EXTENDED,
          expiration_timestamp: expires_at,
          upgraded_organization: Hydro::EntitySerializer.organization(org),
          metered: false,
          emu: false,
          context: {},
        }, schema: "github.enterprise_account.v0.Trial")
        assert_hydro_published({
          enterprise: Hydro::EntitySerializer.business(business),
          actor: Hydro::EntitySerializer.user(@owner),
          user_initiated: :STAFF,
          status: :EXTENDED,
          expiration_timestamp: expires_at,
          upgraded_organization: Hydro::EntitySerializer.organization(org),
          metered: false,
          emu: false,
          enterprise_name: business.name,
          billing_email: business.billing_email,
          zuora_account_id: business.customer.zuora_account_id,
          zuora_account_number: business.customer.zuora_account_number,
          billing_information: @record,
          shipping_information: @shipping_contact
        }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
      end

      test "billing end date not updated if billing end date comes after trial expiration date" do
        @business.customer.update(billing_end_date: 40.days.from_now)
        @business.update(trial_expires_at: 1.day.from_now)
        assert_predicate @business, :trial?

        billing_end_date_before_trial_extension = @business.customer.billing_end_date
        assert @business.extend_trial(@owner)
        assert_predicate @business, :extended_trial?
        assert_equal billing_end_date_before_trial_extension, @business.customer.billing_end_date
      end

      test "updates billing end date to trial expiration date if expiration date comes after billing end date" do
        @business.customer.update(billing_end_date: 20.days.from_now)
        @business.update(trial_expires_at: 1.day.from_now)
        assert_predicate @business, :trial?

        assert @business.extend_trial(@owner)
        assert_predicate @business, :extended_trial?
        assert_equal @business.customer.billing_end_date.to_date, @business.trial_expires_at.to_date
      end

      test "clears the expired trial business deletion date if one was set" do
        @business.update_attribute :created_at, 1.month.ago
        @business.update_attribute :trial_expires_at, 1.second.ago
        @business.update_attribute :trial_deleted_at, 7.days.from_now

        refute_nil @business.trial_deleted_at

        assert @business.extend_trial(@owner)

        assert_predicate @business, :extended_trial?
        assert_nil @business.trial_deleted_at
      end

      test "does nothing wrt the expired trial business deletion date if none was set" do
        @business.update_attribute :created_at, 1.month.ago
        @business.update_attribute :trial_expires_at, 1.second.ago
        assert_predicate @business, :trial_expired?
        assert_nil @business.trial_deleted_at

        assert_nothing_raised do
          assert @business.extend_trial(@owner)
        end

        assert_predicate @business, :extended_trial?
        assert_nil @business.trial_deleted_at
      end
    end
  end

  context "#reset_trial" do
    if GitHub.billing_enabled?
      test "resets expired trial enterprise back to trial status" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

        assert @business.expire_trial(@owner)
        assert @business.reload.downgraded_to_free_plan?
        assert @business.trial_expired?

        @business.reset_trial(@owner)

        assert_equal "business_plus", @business.plan_name
        refute @business.trial_expired?
        assert @business.trial?
      end

      test "fails to reset trial period for a converted enterprise" do
        @business.trial_converted!

        refute @business.reset_trial(@owner)
      end

      test "fails to reset trial period for enterprise whose conversion has been initiated" do
        @business.trial_conversion_initiated!

        refute @business.reset_trial(@owner)
      end

      test "fails to reset trial period for active trial enterprise" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

        refute @business.reset_trial(@owner)
      end

      test "resets cancelled trial enterprise back to trial status" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

        assert @business.cancel_trial(@owner)
        assert @business.reload.downgraded_to_free_plan?
        assert @business.trial_cancelled?

        @business.reset_trial(@owner)

        assert_equal "business_plus", @business.plan_name
        refute @business.trial_cancelled?
        assert @business.trial?
      end

      test "instruments business.reset_trial when trial is successfully reset" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.expire_trial(@owner)

        events = assert_performed_audit_entries(count: 1, only: "business.reset_trial") do
          @business.reset_trial(@owner)
        end

        assert_equal 1, GitHub.dogstats.increments("business.trial.reset").length
      end

      test "publishes hydro event" do
        Timecop.freeze("2023-04-01") do
          reset_hydro # clear any messages that were sent during setup
          @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
          @business.expire_trial(@owner)
          @business.build_trade_screening_record(@record)
          @business.billing_contact.assign_attributes(@billing_contact)
          @business.shipping_contact.assign_attributes(@shipping_contact)
          @business.reset_trial(@owner)
          expires_at = @business.reload.trial_expires_at

          assert_hydro_published({
            enterprise: Hydro::EntitySerializer.business(@business),
            actor: Hydro::EntitySerializer.user(@owner),
            user_initiated: :STAFF,
            status: :RESET,
            expiration_timestamp: expires_at,
            upgraded_organization: nil,
            metered: false,
            emu: false,
            context: {},
          }, schema: "github.enterprise_account.v0.Trial")
          assert_hydro_published({
            enterprise: Hydro::EntitySerializer.business(@business),
            actor: Hydro::EntitySerializer.user(@owner),
            user_initiated: :STAFF,
            status: :RESET,
            expiration_timestamp: expires_at,
            upgraded_organization: nil,
            metered: false,
            emu: false,
            enterprise_name: @business.name,
            billing_email: @business.billing_email,
            zuora_account_id: @business.customer.zuora_account_id,
            zuora_account_number: @business.customer.zuora_account_number,
            billing_information: @record,
            shipping_information: @shipping_contact
          }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
        end
      end

      test "publishes hydro event with upgraded organization information" do
        Timecop.freeze("2023-04-01") do
          reset_hydro # clear any messages that were sent during setup

          org = create :organization, admins: [@owner], plan: "business"
          business = create :business, upgraded_at: 1.day.ago, upgraded_from: org
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
          business.expire_trial(@owner)
          business.build_trade_screening_record(@record)
          business.billing_contact.assign_attributes(@billing_contact)
          business.shipping_contact.assign_attributes(@shipping_contact)
          business.reset_trial(@owner)
          expires_at = business.reload.trial_expires_at

          assert_hydro_published({
            enterprise: Hydro::EntitySerializer.business(business),
            actor: Hydro::EntitySerializer.user(@owner),
            user_initiated: :STAFF,
            status: :RESET,
            expiration_timestamp: expires_at,
            upgraded_organization: Hydro::EntitySerializer.organization(org),
            metered: false,
            emu: false,
            context: {},
          }, schema: "github.enterprise_account.v0.Trial")
          assert_hydro_published({
            enterprise: Hydro::EntitySerializer.business(business),
            actor: Hydro::EntitySerializer.user(@owner),
            user_initiated: :STAFF,
            status: :RESET,
            expiration_timestamp: expires_at,
            upgraded_organization: Hydro::EntitySerializer.organization(org),
            metered: false,
            emu: false,
            enterprise_name: business.name,
            billing_email: business.billing_email,
            zuora_account_id: business.customer.zuora_account_id,
            zuora_account_number: business.customer.zuora_account_number,
            billing_information: @record,
            shipping_information: @shipping_contact
          }, schema: "github.enterprise_account.v0.SalesforceTrialUpdate")
        end
      end

      test "billing end date not updated if billing end date comes after trial expiration date" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update(billing_end_date: 40.days.from_now)
        @business.expire_trial(@owner)
        assert_predicate @business, :trial_expired?

        billing_end_date_before_trial_reset = @business.customer.billing_end_date
        assert @business.reset_trial(@owner)
        refute_predicate @business, :trial_expired?
        assert_equal billing_end_date_before_trial_reset, @business.customer.billing_end_date
      end

      test "updates billing end date to trial expiration date if expiration date comes after billing end date" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        @business.customer.update(billing_end_date: 20.days.from_now)
        @business.expire_trial(@owner)
        assert_predicate @business, :trial_expired?

        assert @business.reset_trial(@owner)
        refute_predicate @business, :trial_expired?
        assert_equal @business.customer.billing_end_date.to_date, @business.trial_expires_at.to_date
      end

      test "unsuspends first EMU owner for EMU business" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        perform_enqueued_jobs only: BusinessTrialCancellationCleanupJob do
          @business.cancel_trial(@owner)
        end

        first_emu_owner = @business.find_first_emu_owner
        assert_predicate first_emu_owner, :suspended?

        assert @business.reset_trial(@owner)
        refute_predicate first_emu_owner.reload, :suspended?
      end if TestEnv.test_with_all_emus?

      test "clears the expired trial business deletion date for the expired business so that it's not queued for deletion" do
        @business.update_attribute :trial_expires_at, 1.second.ago
        @business.update_attribute :trial_deleted_at, 7.days.from_now
        @business.trial_expired!
        assert_predicate @business, :trial_expired?
        refute_nil @business.trial_deleted_at

        assert @business.reset_trial(@owner)
        refute_predicate @business, :trial_expired?
        assert_nil @business.trial_deleted_at
      end

      test "does not do anything to the expired trial business deletion date if none was set for the business" do
        @business.update_attribute :trial_expires_at, 1.second.ago
        @business.trial_expired!
        assert_predicate @business, :trial_expired?

        assert_nothing_raised do
          assert @business.reset_trial(@owner)
        end
        refute_predicate @business, :trial_expired?
        assert_nil @business.trial_deleted_at
      end
    end

    test "sends email to notify owners that the trial has been cancelled" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          @business.cancel_trial(@owner)
        end
      end

      assert_predicate @business, :trial_cancelled?
    end
  end

  context "trial_cancelled scope" do
    test "returns cancelled trials" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_equal 0, Business.trial_cancelled.count
      assert @business.cancel_trial(@owner)
      assert_equal 1, Business.trial_cancelled.count
    end
  end

  context "#trial_days_remaining" do
    test "returns number of days remaining in trial" do
      Timecop.freeze(GitHub::Billing.today) do
        @business.update_attribute :trial_expires_at, (GitHub::Billing.today + 30.days)

        assert_equal 30, @business.trial_days_remaining
      end
    end

    test "returns 0 if trial is expiring on the same day" do
      Timecop.freeze(GitHub::Billing.today) do
        @business.update_attribute :trial_expires_at, GitHub::Billing.today

        assert_equal 0, @business.trial_days_remaining
      end
    end

    test "returns nil when trial has expired" do
      Timecop.freeze(GitHub::Billing.today) do
        @business.update_attribute :trial_expires_at, (GitHub::Billing.today - 1.day)

        assert_nil @business.trial_days_remaining
      end
    end
  end

  context "trial account" do
    if GitHub.billing_enabled?
      test "reverts org to previous plan when removed" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        organization = create(:organization, plan: :business, seats: 10)
        create(
          :business_organization_invitation,
          business: @business,
          invitee: organization,
          confirmed_at: Time.current
        )
        @business.add_organization(organization)
        assert_equal "business_plus", organization.reload.plan.name
        @business.remove_organization(organization)
        assert_equal "business", organization.reload.plan.name
      end

      test "resumes organization subscription when removed" do
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        organization = create(:organization, plan: :business, seats: 10)
        plan_subscription = create(:billing_plan_subscription, :zuora, user: organization)
        create(
          :business_organization_invitation,
          business: @business,
          invitee: organization,
          confirmed_at: Time.current
        )
        @business.add_organization(organization)
        organization.expects(:resume_billing)
        @business.remove_organization(organization)
      end

      test "plan limits matches cloud trial" do
        org = create :free_organization
        Billing::EnterpriseCloudTrial.new(org).create
        @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_equal org.plan.actions_included_private_minutes, @business.plan.actions_included_private_minutes
        assert_equal org.plan.actions_included_private_minutes, @org1.plan.actions_included_private_minutes
        assert_equal org.plan.shared_storage_included_megabytes, @business.plan.shared_storage_included_megabytes
        assert_equal org.plan.package_registry_included_bandwidth, @business.plan.package_registry_included_bandwidth
      end
    end
  end

  context "#initiate_organization_upgrade" do
    test "does not initiate organization upgrade for a trial business account" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?

      @business.initiate_organization_upgrade

      refute_predicate @business, :organization_upgrade_initiated?
    end

    test "initiates organization upgrade for a non-trial business account" do
      refute_predicate @upgrading_business, :trial?

      @upgrading_business.initiate_organization_upgrade

      assert_predicate @upgrading_business, :organization_upgrade_initiated?
    end

    test "publishes hydro event when organization upgrade is initiated" do
      reset_hydro

      marketplace_subscription = @upgrading_business.upgrade_initiated_from_organization.active_marketplace_listing_subscription_items.any?
      @upgrading_business.initiate_organization_upgrade(@owner)

      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        organization: Hydro::EntitySerializer.organization(@upgrading_org),
        enterprise: Hydro::EntitySerializer.business(@upgrading_business),
        actor: Hydro::EntitySerializer.user(@owner),
        organization_previous_plan: "business",
        organization_previous_customer_id: @upgrading_org.customer&.id,
        billing_type: "card",
        status: :UPGRADE_INITIATED,
        marketplace_subscription: marketplace_subscription
      }, schema: "github.enterprise_account.v0.OrganizationUpgrade")
    end
  end

  context "#initiate_organization_upgrade_purchase" do
    test "does not initiate purchase for organization upgrade for a trial business account" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?

      @business.initiate_organization_upgrade_purchase
      refute_predicate @business, :organization_upgrade_initiated?
    end

    test "initiates purchase for an organization upgrade for a non-trial business account, that is in the organization_upgrade_initiated state" do
      refute_predicate @upgrading_business, :trial?

      @upgrading_business.initiate_organization_upgrade
      assert_predicate @upgrading_business, :organization_upgrade_initiated?

      @upgrading_business.initiate_organization_upgrade_purchase
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?
    end

    test "sets the upgrade_purchase_initiated_at value when a payment attempt is made" do
      @upgrading_business.initiate_organization_upgrade
      assert_predicate @upgrading_business, :organization_upgrade_initiated?

      @upgrading_business.initiate_organization_upgrade_purchase
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?
      refute_nil @upgrading_business.upgrade_purchase_initiated_at
    end

    test "does not initiate purchase for an organization upgrade if business is not in the organization_upgrade_initiated state" do
      refute_predicate @upgrading_business, :organization_upgrade_initiated?

      @upgrading_business.initiate_organization_upgrade_purchase
      refute_predicate @upgrading_business, :organization_upgrade_purchase_initiated?
    end

    test "publishes hydro event when organization upgrade purchase is initiated" do
      reset_hydro

      marketplace_subscription = @upgrading_business.upgrade_initiated_from_organization.active_marketplace_listing_subscription_items.any?

      @upgrading_business.initiate_organization_upgrade(@owner)
      @upgrading_business.initiate_organization_upgrade_purchase(@owner)

      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        organization: Hydro::EntitySerializer.organization(@upgrading_org),
        enterprise: Hydro::EntitySerializer.business(@upgrading_business),
        actor: Hydro::EntitySerializer.user(@owner),
        organization_previous_plan: "business",
        organization_previous_customer_id: @upgrading_org.customer&.id,
        billing_type: "card",
        status: :UPGRADE_PURCHASE_INITIATED,
        marketplace_subscription: marketplace_subscription
      }, schema: "github.enterprise_account.v0.OrganizationUpgrade")
    end
  end

  context "#upgrade_from_organization" do
    test "does not upgrade the organization if the business is a trial account" do
      # I'm not sure this test makes a lot of sense as is
      # we have to do some weird artificial set up to get into a trial state
      # and in the organization_upgrade_purchase_initiated state
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase
      @upgrading_business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      assert_predicate @upgrading_business, :trial?

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :trial?
      refute_predicate @upgrading_business, :organization_upgrade_completed?
      refute_includes @upgrading_business.organizations, @upgrading_org
    end

    test "no-ops if business is not in the organization_upgrade_purchase_initiated state" do
      @upgrading_business.initiate_organization_upgrade

      refute_predicate @upgrading_business, :trial?
      assert_predicate @upgrading_business, :organization_upgrade_initiated?
      refute_predicate @upgrading_business, :organization_upgrade_purchase_initiated?

      @upgrading_business.upgrade_from_organization(@owner)

      refute_predicate @upgrading_business, :organization_upgrade_completed?
      assert_predicate @upgrading_business, :organization_upgrade_initiated?
      refute_includes @upgrading_business.organizations, @upgrading_org
    end

    test "upgrades the business to a full EA for a non-trial business account that is in the organization_upgrade_purchase_initiated state, and attaches the organization" do
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      refute_predicate @upgrading_business, :trial?
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_equal @upgrading_business.upgrade_initiated_from_organization_id, @upgrading_org.id
      refute_predicate @upgrading_org, :upgrade_to_enterprise_in_progress?
      assert_includes @upgrading_business.organizations, @upgrading_org
      assert_equal @upgrading_business.upgraded_from, @upgrading_org
    end

    test "upgrades the business to a full EA for a non-trial business account that is in the organization_upgrade_purchase_initiated state, but doesn't attach the organization if the upgrading user is no longer an admin of the upgrading org" do
      @upgrading_business.customer.update_attribute :billing_type, Customer::BILLING_TYPE_CARD
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase
      @upgrading_org.add_admin(create :user)
      @upgrading_org.remove_member!(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?
      assert_predicate @upgrading_org, :upgrade_to_enterprise_in_progress?
      refute_includes @upgrading_org.admins, @upgrading_business.owners.first

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_equal @upgrading_business.upgrade_initiated_from_organization_id, @upgrading_org.id
      refute_predicate @upgrading_org, :upgrade_to_enterprise_in_progress?
      refute_includes @upgrading_business.organizations, @upgrading_org
      assert_nil @upgrading_business.upgraded_from
    end

    test "upgrades the business to a full EA for a non-trial business account that is in the organization_upgrade_purchase_initiated state, but doesn't attach the upgrading organization if that organization got deleted between the initiation of the upgrade and the processing of the payment" do
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      refute_predicate @upgrading_business, :trial?
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?

      @upgrading_org.destroy
      @upgrading_business.reload

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      refute_nil @upgrading_business.upgrade_initiated_from_organization_id
      refute_includes @upgrading_business.organizations, @upgrading_org
    end

    test "upgrades the business to a full EA for a non-trial business account that is in the organization_upgrade_purchase_initiated state, but doesn't attach the upgrading organization if that organization's seat count changed between the initiation of the upgrade and the processing of the payment" do
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      refute_predicate @upgrading_business, :trial?
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?
      assert_predicate @upgrading_org, :upgrade_to_enterprise_in_progress?

      @upgrading_business.update!(seats: @upgrading_org.seats)
      @upgrading_org.update!(seats: @upgrading_org.default_seats + 1)
      @upgrading_org.invite(email: "random@example.com", inviter: @upgrading_org.admins.first)

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          @upgrading_business.upgrade_from_organization(@owner)
        end
      end

      @upgrading_business.reload
      assert_predicate @upgrading_business, :organization_upgrade_completed?
      refute_nil @upgrading_business.upgrade_initiated_from_organization_id
      refute_predicate @upgrading_org, :upgrade_to_enterprise_in_progress?
      refute_includes @upgrading_business.organizations, @upgrading_org
      assert_nil @upgrading_business.upgraded_from
    end

    test "removes upgraded organization's references to zuora subscription when purchase is completed" do
      synchronize_github_products_to_zuora
      owner = create(:user)

      zuora_successful_customer_account_creation(@upgrading_business)
      zuora_successful_customer_account_creation(@upgrading_org)

      @upgrading_business.initiate_organization_upgrade
      assert_predicate @upgrading_business, :organization_upgrade_initiated?

      with_live_zuora("zuora/cancel_zuora_subscription_of_upgraded_org") do
        @upgrading_business.reload
        @upgrading_org.reload
        plan_subscription = @upgrading_org.plan_subscription
        create(:billing_product_uuid, :github_plan, zuora_product_rate_plan_id: "product-rate-plan-id")
        Billing::PlanSubscription::Synchronizer.create(plan_subscription)

        zuora_subscription = Billing::Zuora::Subscription.find(@upgrading_org.plan_subscription.zuora_subscription_number)
        assert T.must(zuora_subscription).active?  # Subscription is active until the purchase has been completed
        refute_nil @upgrading_org.plan_subscription.zuora_subscription_number
        refute_nil @upgrading_org.plan_subscription.zuora_subscription_id

        @upgrading_business.initiate_organization_upgrade_purchase
        assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?
        only = [SyncBusinessOrganizationBillingSettingsJob, CloseOutZuoraSubscriptionJob]
        perform_enqueued_jobs only: only do
          assert @upgrading_business.upgrade_from_organization(@owner)
        end

        assert_predicate @upgrading_business, :organization_upgrade_completed?
        plan_subscription = @upgrading_org.plan_subscription.reload
        assert_nil plan_subscription.zuora_subscription_number
        assert_nil plan_subscription.zuora_subscription_id
      end
    end

    test "transfers org's marketplace subscription items to business" do
      organization = create :organization, admin: @owner, plan: "business"
      upgrading_business = create :business, owners: [@owner], upgrade_initiated_from_organization_id: organization.id

      org_plan_subscription = create :billing_plan_subscription, user: organization
      listing_plan = create :marketplace_listing_plan, :verified_listing
      ano_listing_plan = create :marketplace_listing_plan, :verified_listing
      qty = 99
      org_subscription_item = create :billing_subscription_item, plan_subscription: org_plan_subscription,
        subscribable: listing_plan, quantity: qty
      cancelled_org_subscription_item = create :billing_subscription_item, plan_subscription: org_plan_subscription,
        subscribable: ano_listing_plan, quantity: 0

      upgrading_business.enable_self_serve_payments
      upgrading_business.initiate_organization_upgrade(@owner)
      organization.upgrade_to_enterprise_in_progress!(upgrading_business)
      upgrading_business.initiate_organization_upgrade_purchase(@owner)

      assert_equal 0, upgrading_business.subscription_items.count

      only = [SyncBusinessOrganizationBillingSettingsJob]
      perform_enqueued_jobs only: only do
        upgrading_business.upgrade_from_organization(@owner)
      end

      assert_predicate upgrading_business, :organization_upgrade_completed?
      assert_equal 2, upgrading_business.subscription_items.count

      business_subscription_item = upgrading_business.subscription_items.find { |si| si.quantity == qty }
      cancelled_business_subscription_item = upgrading_business.subscription_items.find { |si| si.quantity == 0 }

      assert_equal org_subscription_item.subscribable, business_subscription_item.subscribable
      assert_equal qty, business_subscription_item.quantity

      assert_equal cancelled_org_subscription_item.subscribable, cancelled_business_subscription_item.subscribable

      org_subscription_item.reload
      assert_predicate org_subscription_item.quantity, :zero?
      assert_equal organization.id, business_subscription_item.organization_id
      assert_equal organization.id, cancelled_business_subscription_item.organization_id
    end

    test "transfers the organization's existing Copilot settings" do
      business_customer = create :credit_card_customer
      @upgrading_business.customer = business_customer
      @upgrading_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      Copilot::Organization.new(@upgrading_org).enable_copilot!
      assert_predicate Copilot::Organization.new(@upgrading_org.reload), :copilot_enabled?

      refute_predicate @upgrading_business, :trial?
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_equal @upgrading_business.upgraded_from, @upgrading_org

      assert_equal Copilot::Business.new(@upgrading_business.reload).copilot_enabled_organizations_count, 1
      assert_predicate Copilot::Organization.new(@upgrading_org.reload), :copilot_enabled?
    end

    test "transfers the organization's default workflow permission" do
      @upgrading_business.set_default_workflow_permissions("read", @owner) # Reset the default for the test
      @upgrading_business.set_actions_workflow_permission_can_approve_pr(false, @owner)
      assert_predicate @upgrading_business, :actions_default_workflow_permissions_read_only?
      refute_predicate @upgrading_business, :actions_workflow_permission_can_approve_pr?

      business_customer = create :credit_card_customer
      @upgrading_business.customer = business_customer
      @upgrading_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      @upgrading_org.set_default_workflow_permissions("write", @owner)
      @upgrading_org.set_actions_workflow_permission_can_approve_pr(true, @owner)
      refute_predicate @upgrading_org, :actions_default_workflow_permissions_read_only?
      assert_predicate @upgrading_org, :actions_workflow_permission_can_approve_pr?

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_equal @upgrading_business.upgraded_from, @upgrading_org

      refute_predicate @upgrading_business, :actions_default_workflow_permissions_read_only?
      assert_predicate @upgrading_business, :actions_workflow_permission_can_approve_pr?
    end

    test "transfers a couponed organization's default workflow permission" do
      @upgrading_business.set_default_workflow_permissions("read", @owner) # Reset the default for the test
      @upgrading_business.set_actions_workflow_permission_can_approve_pr(false, @owner)
      assert_predicate @upgrading_business, :actions_default_workflow_permissions_read_only?
      refute_predicate @upgrading_business, :actions_workflow_permission_can_approve_pr?

      business_customer = create :credit_card_customer
      @upgrading_business.customer = business_customer
      @upgrading_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
      @upgrading_business.payment_method.destroy!

      @upgrading_business.reload.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      coupon = create :coupon, discount: 0.5
      @upgrading_org.redeem_coupon(coupon.code)
      @upgrading_org.set_default_workflow_permissions("write", @owner)
      @upgrading_org.set_actions_workflow_permission_can_approve_pr(true, @owner)
      refute_predicate @upgrading_org, :actions_default_workflow_permissions_read_only?
      assert_predicate @upgrading_org, :actions_workflow_permission_can_approve_pr?

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_equal @upgrading_business.upgraded_from, @upgrading_org

      refute_predicate @upgrading_business, :actions_default_workflow_permissions_read_only?
      assert_predicate @upgrading_business, :actions_workflow_permission_can_approve_pr?
    end

    test "transfers the organization's fork pr workflow permissions" do
      refute_predicate @upgrading_business, :can_run_fork_pr_workflows?
      refute_equal @upgrading_business.actions_private_fork_pr_approvals_policy, Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS

      business_customer = create :credit_card_customer
      @upgrading_business.customer = business_customer
      @upgrading_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      policy = Configurable::ForkPrWorkflowsPolicy::RUN_WORKFLOWS
      policy |= Configurable::ForkPrWorkflowsPolicy::RUN_WITH_TOKENS
      policy |= Configurable::ForkPrWorkflowsPolicy::RUN_WITH_SECRETS
      @upgrading_org.set_fork_pr_workflows_policy(policy: policy, actor: @owner)
      @upgrading_org.set_actions_private_fork_pr_approvals_policy(policy: Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS, actor: @owner)
      assert_predicate @upgrading_org, :can_run_fork_pr_workflows?
      assert_equal @upgrading_org.actions_private_fork_pr_approvals_policy, Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_equal @upgrading_business.upgraded_from, @upgrading_org

      assert_predicate @upgrading_business, :can_run_fork_pr_workflows?
      assert_predicate @upgrading_business, :can_run_fork_pr_workflows_with_write_tokens?
      assert_predicate @upgrading_business, :can_run_fork_pr_workflows_with_secrets?
      assert_equal @upgrading_business.actions_private_fork_pr_approvals_policy, Configurable::ActionsPrivateForkPrApprovals::READ_ONLY_USERS
    end

    test "transfers the organization's existing spending limits" do
      org_customer = create :credit_card_customer
      @upgrading_org.customer = org_customer

      business_customer = create :credit_card_customer
      @upgrading_business.customer = business_customer
      @upgrading_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      @upgrading_org.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      @upgrading_org.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      refute_predicate @upgrading_business, :trial?
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?

      assert_predicate @upgrading_org.budget_for(group: :codespaces), :valid?
      assert_predicate @upgrading_org.budget_for(group: :shared), :valid?

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_equal @upgrading_business.upgraded_from, @upgrading_org

      assert_equal @upgrading_business.budget_for(group: :codespaces).spending_limit_in_subunits / 100, 100
      assert_equal @upgrading_business.budget_for(group: :shared).spending_limit_in_subunits / 100, 200
    end

    test "transfers the organization's existing spending limits, even if the payment method was detached" do
      org_customer = create :credit_card_customer
      @upgrading_org.customer = org_customer

      business_customer = create :credit_card_customer
      @upgrading_business.customer = business_customer
      @upgrading_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      @upgrading_org.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      @upgrading_org.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      Organization.any_instance.stubs(:has_valid_payment_method?).returns(false)  # Payment method is detached from org
      refute_predicate @upgrading_org, :has_valid_payment_method?

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_equal @upgrading_business.upgraded_from, @upgrading_org

      assert_equal @upgrading_business.budget_for(group: :codespaces).spending_limit_in_subunits / 100, 100
      assert_equal @upgrading_business.budget_for(group: :shared).spending_limit_in_subunits / 100, 200
    end

    test "transfer the organization's existing deploy key policy" do
      refute_predicate @upgrading_business, :deploy_key_policy_enabled?

      business_customer = create :credit_card_customer
      @upgrading_business.customer = business_customer
      @upgrading_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      @upgrading_org.enable_deploy_key_policy(actor: @owner)

      assert_predicate @upgrading_org, :deploy_key_policy_enabled?

      @upgrading_business.upgrade_from_organization(@owner)
      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_equal @upgrading_business.upgraded_from, @upgrading_org

      assert_predicate @upgrading_business, :deploy_key_policy_enabled?
    end

    test "does not attempt to transfer the organization's existing spending limits, if multiple errors are present" do
      org_customer = create :credit_card_customer
      @upgrading_org.customer = org_customer

      business_customer = create :credit_card_customer
      @upgrading_business.customer = business_customer
      @upgrading_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      @upgrading_org.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      @upgrading_org.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      errors = [ActiveModel::Error.new("Error", :payment_method, "must be present and valid"), ActiveModel::Error.new("Error", :tiered_spending, "other error")]  # Multiple errors
      Billing::Budget.any_instance.stubs(:errors).returns(errors)
      Billing::Budget.any_instance.stubs(:valid?).returns(false)  # Not valid due to multiple validation errors
      assert_equal @upgrading_org.budget_for(group: :codespaces).errors.count, 2
      assert_equal @upgrading_org.budget_for(group: :shared).errors.count, 2

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_equal @upgrading_business.upgraded_from, @upgrading_org

      assert_equal @upgrading_business.budget_for(group: :codespaces).spending_limit_in_subunits, 0
      assert_equal @upgrading_business.budget_for(group: :shared).spending_limit_in_subunits, 0
    end

    test "does not attempt to transfer an organization's invalid spending limits" do
      org_customer = create :credit_card_customer
      @upgrading_org.customer = org_customer

      business_customer = create :credit_card_customer
      @upgrading_business.customer = business_customer
      @upgrading_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      @upgrading_org.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      @upgrading_org.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      Billing::Budget.any_instance.stubs(:valid?).returns(false)  # Stub the spending limits to be invalid

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_equal @upgrading_business.upgraded_from, @upgrading_org

      assert_equal @upgrading_business.budget_for(group: :codespaces).spending_limit_in_subunits, 0  # Limit is the default
      assert_equal @upgrading_business.budget_for(group: :shared).spending_limit_in_subunits, 0
    end

    test "does not attempt to transfer the organization's existing spending limits if the business does not have a valid payment method" do
      org_customer = create :credit_card_customer
      @org_to_attach.customer = org_customer

      @org_to_attach.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      @org_to_attach.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      @coupon_business.initiate_creation_from_coupon(@owner)

      refute_predicate @coupon_business, :trial?
      assert_predicate @coupon_business, :creation_initiated_from_coupon?
      refute_predicate @coupon_business, :has_valid_payment_method?

      assert_predicate @org_to_attach.budget_for(group: :codespaces), :valid?
      assert_predicate @org_to_attach.budget_for(group: :shared), :valid?

      @coupon_business.complete_creation_from_coupon(@owner)

      assert_predicate @coupon_business, :created_from_coupon?
      assert_equal @coupon_business.upgraded_from, @org_to_attach

      assert_equal @coupon_business.budget_for(group: :codespaces).spending_limit_in_subunits, 0  # Limit is the default
      assert_equal @coupon_business.budget_for(group: :shared).spending_limit_in_subunits, 0
    end

    test "instruments upgrade_from_organization audit log event when upgrade is successful" do
      events = assert_performed_audit_entries(count: 1, only: "business.upgrade_from_organization") do

        @upgrading_business.initiate_organization_upgrade
        @upgrading_business.initiate_organization_upgrade_purchase
        @upgrading_business.upgrade_from_organization(@owner)
      end

      expected_payload = {
        business: @upgrading_business.slug,
        business_id: @upgrading_business.id,
        org: @upgrading_org.login,
        org_id: @upgrading_org.id
      }

      assert_subset_hash expected_payload, events.first
    end

    test "publishes hydro event when organization upgrade is completed" do
      reset_hydro

      Organization.any_instance.stubs(:active_marketplace_listing_subscription_items).returns(["dummy_item"])
      marketplace_subscription = @upgrading_business.upgrade_initiated_from_organization.active_marketplace_listing_subscription_items.any?
      assert marketplace_subscription

      @upgrading_business.initiate_organization_upgrade(@owner)
      @upgrading_business.initiate_organization_upgrade_purchase(@owner)
      perform_enqueued_jobs(only: [BusinessCreatedFromOrganizationJob, SyncBusinessOrganizationBillingSettingsJob]) do
        @upgrading_business.upgrade_from_organization(@owner)
      end

      @upgrading_org.reload
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        organization: Hydro::EntitySerializer.organization(@upgrading_org),
        enterprise: Hydro::EntitySerializer.business(@upgrading_business),
        actor: Hydro::EntitySerializer.user(@owner),
        organization_previous_plan: "business",
        organization_previous_customer_id: @upgrading_org.customer&.id,
        billing_type: "card",
        status: :PURCHASE_UPGRADED,
        marketplace_subscription: marketplace_subscription
      }, schema: "github.enterprise_account.v0.OrganizationUpgrade")
    end

    test "enables auto-pay and instruments toggle event for business remaining on self-serve payments" do
      Customer.any_instance.expects(:auto_pay?).returns(false)
      events = assert_performed_audit_entries(count: 1, only: "account.toggle_auto_pay") do

        @upgrading_business.initiate_organization_upgrade
        @upgrading_business.initiate_organization_upgrade_purchase
        @upgrading_business.upgrade_from_organization(@owner)
      end

      expected_payload = {
        business: @upgrading_business.slug,
        business_id: @upgrading_business.id,
        actor: @owner.login,
        actor_id: @owner.id,
        auto_pay_status: true,
        auto_pay_reason: :enterprise_purchase
      }

      @upgrading_business.reload
      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_predicate @upgrading_business, :automatic_self_serve_payment_enabled?
      assert_subset_hash expected_payload, events.first
    end

    test "job to sync billing settings to organizations enqueued", skip_enterprise: true do
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase
      @upgrading_business.reload
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?

      assert_enqueued_with(
        job: SyncBusinessOrganizationBillingSettingsJob,
        args: [@upgrading_business, enterprise_purchase: true, switch_org_billing_to_invoice: false]
      ) do
        @upgrading_business.upgrade_from_organization(@owner)
      end

      @upgrading_business.reload
      assert_includes @upgrading_business.organizations, @upgrading_org
      assert_predicate @upgrading_business, :organization_upgrade_completed?
    end

    test "removes the EnterpriseAccounts::KV.store key that records that the business was previously in the organization_upgrade_purchase_initiated state" do
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?
      assert EnterpriseAccounts::KV.store.exists("organization_upgrade_purchase_initiated/#{@upgrading_business.id}").value!

      @upgrading_business.upgrade_from_organization(@owner)

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      refute EnterpriseAccounts::KV.store.exists("organization_upgrade_purchase_initiated/#{@upgrading_business.id}").value!
    end

    test "org upgrade onboarding notice gets set on the owners of the business when upgrade is complete" do
      @upgrading_org.add_admin(create(:user))
      assert_equal @upgrading_org.admins.count, 2
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?

      @upgrading_business.owners.each do |owner|
        refute @upgrading_business.org_upgrade_onboarding_notice_set?(owner)
      end

      perform_enqueued_jobs(only: [BusinessCreatedFromOrganizationJob]) do
        @upgrading_business.upgrade_from_organization
      end

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_same_elements @upgrading_business.owners, @upgrading_org.admins
      @upgrading_business.owners.each do |owner|
        assert @upgrading_business.org_upgrade_onboarding_notice_set?(owner)
      end
    end

    test "org upgrade onboarding notice gets set on the only owner of the business if a race condition prevents attachment of the upgrading org to the business" do
      @upgrading_org.add_admin(create(:user))
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase
      @upgrading_business.update!(seats: @upgrading_org.seats)
      @upgrading_org.update!(seats: @upgrading_org.default_seats + 1)
      @upgrading_org.invite(email: "random@example.com", inviter: @upgrading_org.admins.first)

      refute @upgrading_business.org_upgrade_onboarding_notice_set?(@owner)

      perform_enqueued_jobs(only: [BusinessCreatedFromOrganizationJob]) do
        @upgrading_business.upgrade_from_organization
      end

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_empty @upgrading_business.organizations
      assert_equal @upgrading_business.owners, [@owner]
      assert @upgrading_business.org_upgrade_onboarding_notice_set?(@owner)
    end

    test "org upgrade onboarding notice gets set on the only owner of the business if the upgrading organization gets deleted between the initiation of the upgrade and the processing of the payment" do
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      @upgrading_org.destroy
      assert_nil @upgrading_business.reload.upgrade_initiated_from_organization

      refute @upgrading_business.org_upgrade_onboarding_notice_set?(@owner)

      perform_enqueued_jobs(only: [BusinessCreatedFromOrganizationJob]) do
        @upgrading_business.upgrade_from_organization
      end

      assert_predicate @upgrading_business, :organization_upgrade_completed?
      assert_empty @upgrading_business.organizations
      assert_equal @upgrading_business.owners, [@owner]
      assert @upgrading_business.org_upgrade_onboarding_notice_set?(@owner)
    end
  end

  context "#cancel_organization_upgrade" do
    test "no-ops if business is not in the organization_upgrade_initiated state" do
      @upgrading_business.initiate_organization_upgrade
      @upgrading_business.initiate_organization_upgrade_purchase

      refute_predicate @upgrading_business, :organization_upgrade_initiated?
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?

      @upgrading_business.cancel_organization_upgrade(@owner)

      refute_nil @upgrading_business
      assert_predicate @upgrading_business, :organization_upgrade_purchase_initiated?
    end

    test "publishes hydro event when organization upgrade is cancelled" do
      reset_hydro

      marketplace_subscription = @upgrading_business.upgrade_initiated_from_organization.active_marketplace_listing_subscription_items.any?
      @upgrading_business.initiate_organization_upgrade(@owner)
      @upgrading_business.cancel_organization_upgrade(@owner)

      @upgrading_org.reload
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        organization: Hydro::EntitySerializer.organization(@upgrading_org),
        enterprise: Hydro::EntitySerializer.business(@upgrading_business),
        actor: Hydro::EntitySerializer.user(@owner),
        organization_previous_plan: "business",
        organization_previous_customer_id: @upgrading_org.customer&.id,
        billing_type: "card",
        status: :UPGRADE_CANCELLED,
        marketplace_subscription: marketplace_subscription,
      }, schema: "github.enterprise_account.v0.OrganizationUpgrade")
    end

    test "job to cancel organization upgrade is enqueued" do
      @upgrading_business.initiate_organization_upgrade
      assert_predicate @upgrading_business, :organization_upgrade_initiated?

      assert_enqueued_with(job: BusinessUpgradeCancellationJob) do
        @upgrading_business.cancel_organization_upgrade(@owner)
      end
    end
  end

  context "#initiate_creation_from_coupon" do
    test "does not initiate enterprise creation from coupon for a trial business account" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @business, :trial?

      @business.initiate_creation_from_coupon(@owner)

      refute_predicate @business, :creation_initiated_from_coupon?
    end

    test "initiates enterprise creation from coupon for a non-trial business account" do
      refute_predicate @business, :trial?

      @business.initiate_creation_from_coupon(@owner)

      assert_predicate @business, :creation_initiated_from_coupon?
    end

    test "logs the business creation in hydro, when no org has been selected for attachment to the business" do
      reset_hydro # clear any messages that were sent during setup
      @coupon_business.upgrade_initiated_from_organization_id = nil
      @coupon_business.save!
      @coupon_business.initiate_creation_from_coupon(@owner, coupon_code: @coupon.code)
      assert_predicate @coupon_business, :creation_initiated_from_coupon?

      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@coupon_business),
        actor: Hydro::EntitySerializer.user(@owner),
        organization: nil,
        slug: @coupon_business.slug,
        status: :CREATION_INITIATED_FROM_COUPON,
        coupon: @coupon.code,
        organization_previous_plan: nil,
      }, schema: "github.enterprise_account.v0.CreationFromCouponRedemption")
    end

    test "logs the business creation in hydro, and records if an organization is slated to be attached to the business" do
      reset_hydro # clear any messages that were sent during setup
      assert_equal @coupon_business.upgrade_initiated_from_organization_id, @org_to_attach.id
      assert_equal @org_to_attach.upgrade_to_enterprise_in_progress, @coupon_business
      assert_equal @org_to_attach.plan.name, "business"

      @coupon_business.initiate_creation_from_coupon(@owner, coupon_code: @coupon.code)
      assert_predicate @coupon_business, :creation_initiated_from_coupon?

      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@coupon_business),
        actor: Hydro::EntitySerializer.user(@owner),
        organization: Hydro::EntitySerializer.organization(@org_to_attach),
        slug: @coupon_business.slug,
        status: :CREATION_INITIATED_FROM_COUPON,
        coupon: @coupon.code,
        organization_previous_plan: @org_to_attach.plan.name,
      }, schema: "github.enterprise_account.v0.CreationFromCouponRedemption")
    end
  end

  context "#initiate_creation_purchase_from_coupon" do
    test "does not initiate purchase for couponed EA for a trial business account" do
      @coupon_business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @coupon_business, :trial?

      @coupon_business.initiate_creation_purchase_from_coupon
      refute_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
    end

    test "initiates purchase for a new couponed EA, that is in the creation_initiated_from_coupon state" do
      refute_predicate @coupon_business, :trial?

      @coupon_business.initiate_creation_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_initiated_from_coupon?

      @coupon_business.initiate_creation_purchase_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
    end

    test "sets the upgrade_purchase_initiated_at value when a payment attempt is made" do
      @coupon_business.initiate_creation_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_initiated_from_coupon?

      @coupon_business.initiate_creation_purchase_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
      refute_nil @coupon_business.upgrade_purchase_initiated_at
    end

    test "does not initiate purchase for a new couponed EA if business is not in the creation_initiated_from_coupon state" do
      refute_predicate @upgrading_business, :creation_initiated_from_coupon?

      @coupon_business.initiate_creation_purchase_from_coupon(@owner)
      refute_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
    end

    test "logs the creation from coupon purchase initiated event in hydro, when no org has been selected for attachment to the business" do
      @coupon_business.upgrade_initiated_from_organization_id = nil
      @coupon_business.save!
      @coupon_business.initiate_creation_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_initiated_from_coupon?

      reset_hydro # clear any messages that were sent during setup
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
      refute_nil @coupon_business.upgrade_purchase_initiated_at

      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@coupon_business),
        actor: Hydro::EntitySerializer.user(@owner),
        organization: nil,
        slug: @coupon_business.slug,
        status: :CREATION_FROM_COUPON_PURCHASE_INITIATED,
        coupon: nil,
        organization_previous_plan: nil,
      }, schema: "github.enterprise_account.v0.CreationFromCouponRedemption")
    end

    test "logs the creation from coupon purchase event in hydro, and records if an organization is slated to be attached to the business" do
      assert_equal @coupon_business.upgrade_initiated_from_organization_id, @org_to_attach.id
      assert_equal @org_to_attach.upgrade_to_enterprise_in_progress, @coupon_business
      assert_equal @org_to_attach.plan.name, "business"
      @coupon_business.initiate_creation_from_coupon(@owner)
      reset_hydro # clear any messages that were sent during setup

      @coupon_business.initiate_creation_purchase_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
      refute_nil @coupon_business.upgrade_purchase_initiated_at

      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@coupon_business),
        actor: Hydro::EntitySerializer.user(@owner),
        organization: Hydro::EntitySerializer.organization(@org_to_attach),
        slug: @coupon_business.slug,
        status: :CREATION_FROM_COUPON_PURCHASE_INITIATED,
        coupon: nil,
        organization_previous_plan: @org_to_attach.plan.name,
      }, schema: "github.enterprise_account.v0.CreationFromCouponRedemption")
    end
  end

  context "#complete_creation_from_coupon" do
    test "completes enterprise creation from a coupon for a non-trial business account in the creation_initiated_from_coupon state" do
      refute_predicate @coupon_business, :trial?

      @coupon_business.initiate_creation_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_initiated_from_coupon?

      @coupon_business.complete_creation_from_coupon(@owner)

      assert_predicate @coupon_business, :created_from_coupon?
    end

    test "completes enterprise creation from a coupon for a non-trial business account in the creation_from_coupon_purchase_initiated state" do
      refute_predicate @coupon_business, :trial?

      @coupon_business.initiate_creation_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_initiated_from_coupon?

      @coupon_business.initiate_creation_purchase_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?

      @coupon_business.complete_creation_from_coupon(@owner)

      assert_predicate @coupon_business, :created_from_coupon?
    end

    test "does not complete enterprise creation from a coupon if account is not in any of the allowed states" do
      refute_predicate @coupon_business, :creation_initiated_from_coupon?
      refute_predicate @coupon_business, :creation_from_coupon_purchase_initiated?

      @coupon_business.complete_creation_from_coupon(@owner)

      refute_predicate @coupon_business, :created_from_coupon?
    end

    test "if specified and owned by the business owner, attaches the organization to the business" do
      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)

      refute_predicate @coupon_business, :trial?
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
      assert_equal @coupon_business.upgrade_initiated_from_organization_id, @org_to_attach.id
      assert_equal @org_to_attach.upgrade_to_enterprise_in_progress, @coupon_business
      assert_same_elements @coupon_business.owners, @org_to_attach.admins

      @coupon_business.complete_creation_from_coupon(@owner)

      assert_predicate @coupon_business.reload, :created_from_coupon?
      assert_equal @coupon_business.organizations, [@org_to_attach]
      refute_predicate @org_to_attach, :upgrade_to_enterprise_in_progress?
      assert_equal @coupon_business.upgraded_from, @org_to_attach
    end

    test "does not attach the specified organization to the business if business owner is not an admin of the org" do
      org_to_attach = create :organization, admins: [create(:user)]
      @coupon_business.upgrade_initiated_from_organization_id = org_to_attach.id
      org_to_attach.upgrade_to_enterprise_in_progress!(@coupon_business)
      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)

      refute_predicate @coupon_business, :trial?
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
      assert_equal @coupon_business.upgrade_initiated_from_organization_id, org_to_attach.id
      assert_equal org_to_attach.upgrade_to_enterprise_in_progress, @coupon_business
      refute_includes org_to_attach.admins, @coupon_business.owners

      @coupon_business.complete_creation_from_coupon(@owner)

      assert_predicate @coupon_business.reload, :created_from_coupon?
      refute_includes @coupon_business.organizations, org_to_attach
      refute_predicate org_to_attach.reload, :upgrade_to_enterprise_in_progress?
      assert_nil @coupon_business.upgraded_from
    end

    test "if an org gets attached to the business, expires the org's active coupon" do
      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)
      coupon = create :coupon, discount: 0.5
      @org_to_attach.redeem_coupon(coupon.code)

      refute_predicate @coupon_business, :trial?
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
      assert_equal @coupon_business.upgrade_initiated_from_organization_id, @org_to_attach.id
      assert_equal @org_to_attach.upgrade_to_enterprise_in_progress, @coupon_business
      assert_predicate @org_to_attach, :has_an_active_coupon?

      @coupon_business.complete_creation_from_coupon(@owner)

      assert_predicate @coupon_business.reload, :created_from_coupon?
      assert_equal @coupon_business.organizations, [@org_to_attach]
      refute_predicate @org_to_attach, :upgrade_to_enterprise_in_progress?
      assert_equal @coupon_business.upgraded_from, @org_to_attach
      refute_predicate @org_to_attach.reload, :has_an_active_coupon?
    end

    test "removes upgraded organization's references to zuora subscription when purchase is completed" do
      assert_equal @coupon_business.upgrade_initiated_from_organization_id, @org_to_attach.id

      synchronize_github_products_to_zuora

      zuora_successful_customer_account_creation(@coupon_business)
      zuora_successful_customer_account_creation(@org_to_attach)

      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.upgrade_initiated_from_organization_id = @org_to_attach.id
      assert_predicate @coupon_business, :creation_initiated_from_coupon?

      with_live_zuora("zuora/cancel_zuora_subscription_of_org_upgraded_into_couponed_business") do
        @coupon_business.reload
        @org_to_attach.reload
        plan_subscription = @org_to_attach.plan_subscription
        create(:billing_product_uuid, :github_plan, zuora_product_rate_plan_id: "product-rate-plan-id")
        Billing::PlanSubscription::Synchronizer.create(plan_subscription)

        zuora_subscription = Billing::Zuora::Subscription.find(@org_to_attach.plan_subscription.zuora_subscription_number)
        assert T.must(zuora_subscription).active?  # Subscription is active until the purchase has been completed
        refute_nil @org_to_attach.plan_subscription.zuora_subscription_number
        refute_nil @org_to_attach.plan_subscription.zuora_subscription_id

        @coupon_business.initiate_creation_purchase_from_coupon(@owner)
        assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
        only = [SyncBusinessOrganizationBillingSettingsJob, CloseOutZuoraSubscriptionJob]
        perform_enqueued_jobs only: only do
          @coupon_business.complete_creation_from_coupon(@owner)
        end

        assert_predicate @coupon_business.reload, :created_from_coupon?
        assert_equal @coupon_business.organizations, [@org_to_attach]
        plan_subscription = @org_to_attach.plan_subscription.reload
        assert_nil plan_subscription.zuora_subscription_number
        assert_nil plan_subscription.zuora_subscription_id
      end
    end

    test "transfers the organization's existing Copilot settings" do
      business_customer = create :credit_card_customer
      @coupon_business.customer = business_customer
      @coupon_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)

      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)

      Copilot::Organization.new(@org_to_attach).enable_copilot!
      assert_predicate Copilot::Organization.new(@org_to_attach.reload), :copilot_enabled?

      refute_predicate @coupon_business, :trial?
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?

      @coupon_business.complete_creation_from_coupon(@owner)

      assert_predicate @coupon_business, :created_from_coupon?
      assert_equal @coupon_business.upgraded_from, @org_to_attach

      assert_equal Copilot::Business.new(@coupon_business.reload).copilot_enabled_organizations_count, 1
      assert_predicate Copilot::Organization.new(@org_to_attach.reload), :copilot_enabled?
    end

    test "transfers the organization's existing spending limits" do
      org_customer = create :credit_card_customer
      @org_to_attach.customer = org_customer

      business_customer = create :credit_card_customer
      @coupon_business.customer = business_customer
      @coupon_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)

      @org_to_attach.budget_for(group: :codespaces).configure(
        enforce_spending_limit: true,
        limit: 100
      )
      @org_to_attach.budget_for(group: :shared).configure(
        enforce_spending_limit: true,
        limit: 200
      )

      refute_predicate @coupon_business, :trial?
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?

      @coupon_business.complete_creation_from_coupon(@owner)

      assert_predicate @coupon_business, :created_from_coupon?
      assert_equal @coupon_business.upgraded_from, @org_to_attach
      assert_equal @coupon_business.budget_for(group: :codespaces).spending_limit_in_subunits / 100, 100
      assert_equal @coupon_business.budget_for(group: :shared).spending_limit_in_subunits / 100, 200
    end

    test "job to sync billing settings to organizations enqueued", skip_enterprise: true do
      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)

      assert_enqueued_with(
        job: SyncBusinessOrganizationBillingSettingsJob,
        args: [@coupon_business, enterprise_purchase: true, switch_org_billing_to_invoice: false]
      ) do
        @coupon_business.complete_creation_from_coupon(@owner)
      end

      @coupon_business.reload
      assert_includes @coupon_business.organizations, @org_to_attach
      assert_predicate @coupon_business, :created_from_coupon?
    end

    test "logs the created from coupon event in hydro, when no org has been selected for attachment to the business" do
      @coupon_business.upgrade_initiated_from_organization_id = nil
      @coupon_business.save!
      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
      assert_predicate @coupon_business.reload, :has_an_active_coupon?

      reset_hydro # clear any messages that were sent during setup

      @coupon_business.complete_creation_from_coupon(@owner)

      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@coupon_business),
        actor: Hydro::EntitySerializer.user(@owner),
        organization: nil,
        slug: @coupon_business.slug,
        status: :CREATED_FROM_COUPON,
        coupon: @coupon.code,
        organization_previous_plan: nil,
      }, schema: "github.enterprise_account.v0.CreationFromCouponRedemption")
    end

    test "logs the creation from coupon purchase event in hydro, and records if an organization is slated to be attached to the business" do
      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_from_coupon_purchase_initiated?
      assert_predicate @coupon_business.reload, :has_an_active_coupon?
      assert_equal @coupon_business.upgrade_initiated_from_organization_id, @org_to_attach.id
      assert_equal @org_to_attach.upgrade_to_enterprise_in_progress, @coupon_business

      reset_hydro # clear any messages that were sent during setup

      @coupon_business.complete_creation_from_coupon(@owner)

      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@coupon_business),
        actor: Hydro::EntitySerializer.user(@owner),
        organization: Hydro::EntitySerializer.organization(@org_to_attach.reload),
        slug: @coupon_business.slug,
        status: :CREATED_FROM_COUPON,
        coupon: @coupon.code,
        organization_previous_plan: "business",
      }, schema: "github.enterprise_account.v0.CreationFromCouponRedemption")
    end

    test "emails unique owner of the business to inform them of business creation if no org was attached to the business" do
      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)
      @coupon_business.upgrade_initiated_from_organization_id = nil
      @coupon_business.save!

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          @coupon_business.complete_creation_from_coupon(@owner)
        end
      end

      assert_equal @coupon_business.owners.count, 1
      mail = ActionMailer::Base.deliveries.last
      assert_predicate @coupon_business, :created_from_coupon?
      assert_empty @coupon_business.organizations

      assert_equal mail.bcc, [@coupon_business.owners.first.email]
      assert_equal \
        "[GitHub] Welcome to GitHub Enterprise — Let's Get Started!",
        mail.subject
      assert_includes mail.html_part.body.to_s,
        "Hi @#{@coupon_business.owners.first.display_login}!"
      assert_includes mail.html_part.body.to_s,
        "Thank you for creating your GitHub Enterprise account, #{@coupon_business}."
      refute_includes mail.html_part.body.to_s,
        "All previous owners of the #{@org_to_attach.safe_profile_name} organization"
      refute_includes mail.html_part.body.to_s,
        "are now owners of the #{@coupon_business.name} enterprise."
      assert_includes mail.text_part.body.to_s,
        "Hi @#{@coupon_business.owners.first.display_login}!"
      refute_includes mail.text_part.body.to_s,
        "All previous owners of the #{@org_to_attach.safe_profile_name} organization are now"
      refute_includes mail.text_part.body.to_s,
        "owners of the #{@coupon_business.name} enterprise."
    end

    test "email informs business owners that all org owners are now owners of the business, if org was attached to the business and BusinessCreatedFromOrganizationJob runs after the email is queued" do
      @org_to_attach.add_admin(create(:user))
      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_enqueued_jobs(1, only: BusinessCreatedFromOrganizationJob) do
          assert_difference "ActionMailer::Base.deliveries.size", +1 do
            @coupon_business.complete_creation_from_coupon(@owner)
          end
        end
      end

      # BusinessCreatedFromOrganizationJob promotes org admins to business owners
      # asynchronously.
      # Only allowing BusinessCreatedFromOrganizationJob to run after the email job
      # has run, to verify that promoting org admins to business owners
      # after email is sent still results in all business owners
      # receiving the email
      perform_enqueued_jobs(only: BusinessCreatedFromOrganizationJob)
      assert_predicate @coupon_business.reload, :created_from_coupon?
      assert_same_elements @coupon_business.owners, @org_to_attach.admins
      assert @org_to_attach.admins.count > 1
      assert_equal @coupon_business.organizations, [@org_to_attach]

      mail = ActionMailer::Base.deliveries.last
      assert_same_elements mail.bcc, @coupon_business.owners.map { |user| user.email }
      assert_equal \
        "[GitHub] Welcome to GitHub Enterprise — Let's Get Started!",
        mail.subject
      assert_includes mail.html_part.body.to_s,
        "@#{@coupon_business.owners.first.display_login} has created the new #{@coupon_business.name} Enterprise account on GitHub."
      assert_includes mail.html_part.body.to_s,
        "All previous owners of the #{@org_to_attach.safe_profile_name} organization"
      assert_includes mail.html_part.body.to_s,
        "are now owners of the #{@coupon_business.name} enterprise."
      assert_includes mail.text_part.body.to_s,
        "@#{@coupon_business.owners.first.display_login} has created the new #{@coupon_business.name} Enterprise account on GitHub."
      assert_includes mail.text_part.body.to_s,
        "All previous owners of the #{@org_to_attach.safe_profile_name} organization are now"
      assert_includes mail.text_part.body.to_s,
        "owners of the #{@coupon_business.name} enterprise."
    end

    test "email informs business owners that all org owners are now owners of the business, if org was attached to the business and BusinessCreatedFromOrganizationJob runs before the email is queued" do
      @org_to_attach.add_admin(create(:user))
      @coupon_business.initiate_creation_from_coupon(@owner)
      @coupon_business.initiate_creation_purchase_from_coupon(@owner)

      perform_enqueued_jobs(only: [BusinessCreatedFromOrganizationJob]) do
        assert_enqueued_jobs(1, only: ApplicationDeliveryJob) do
          @coupon_business.complete_creation_from_coupon(@owner)
        end
      end

      # verifying that the email job can complete after the
      # BusinessCreatedFromOrganizationJob and email still
      # gets addressed to the right users.
      perform_enqueued_jobs(only: ApplicationDeliveryJob)

      assert_predicate @coupon_business.reload, :created_from_coupon?
      assert_same_elements @coupon_business.owners, @org_to_attach.admins
      assert @org_to_attach.admins.count > 1
      assert_equal @coupon_business.organizations, [@org_to_attach]

      mail = ActionMailer::Base.deliveries.last
      assert_same_elements mail.bcc, @coupon_business.owners.map { |user| user.email }
      assert_equal \
        "[GitHub] Welcome to GitHub Enterprise — Let's Get Started!",
        mail.subject
      assert_includes mail.html_part.body.to_s,
        "@#{@coupon_business.owners.first.display_login} has created the new #{@coupon_business.name} Enterprise account on GitHub."
      assert_includes mail.html_part.body.to_s,
        "All previous owners of the #{@org_to_attach.safe_profile_name} organization"
      assert_includes mail.html_part.body.to_s,
        "are now owners of the #{@coupon_business.name} enterprise."
      assert_includes mail.text_part.body.to_s,
        "@#{@coupon_business.owners.first.display_login} has created the new #{@coupon_business.name} Enterprise account on GitHub."
      assert_includes mail.text_part.body.to_s,
        "All previous owners of the #{@org_to_attach.safe_profile_name} organization are now"
      assert_includes mail.text_part.body.to_s,
        "owners of the #{@coupon_business.name} enterprise."
    end
  end

  context "#cancel_creation_from_coupon" do
    test "no-ops if business is not in the creation_initiated_from_coupon state" do
      refute_predicate @upgrading_business, :creation_initiated_from_coupon?

      @coupon_business.cancel_creation_from_coupon(@owner)

      refute_nil @coupon_business
    end

    test "no-ops if the actor is not an owner of the business" do
      @coupon_business.initiate_creation_from_coupon(@owner, coupon_code: @coupon.code)
      assert_predicate @coupon_business, :creation_initiated_from_coupon?

      random_user = create :user
      @coupon_business.cancel_creation_from_coupon(random_user)

      refute_nil @coupon_business
      assert_predicate @coupon_business, :creation_initiated_from_coupon?
    end

    test "job to cancel creation from coupon redemption is enqueued" do
      @coupon_business.initiate_creation_from_coupon(@owner, coupon_code: @coupon.code)
      assert_predicate @coupon_business, :creation_initiated_from_coupon?

      assert_enqueued_with(job: BusinessUpgradeCancellationJob) do
        @coupon_business.cancel_creation_from_coupon(@owner)
      end
    end

    test "logs the cancellation of a coupon redemption for a new Enterprise account event in hydro" do
      assert_equal @coupon_business.upgrade_initiated_from_organization_id, @org_to_attach.id
      assert_equal @org_to_attach.upgrade_to_enterprise_in_progress, @coupon_business
      assert_equal @org_to_attach.plan.name, "business"
      @coupon_business.initiate_creation_from_coupon(@owner)
      assert_predicate @coupon_business, :creation_initiated_from_coupon?
      reset_hydro # clear any messages that were sent during setup

      @coupon_business.cancel_creation_from_coupon(@owner)

      assert_hydro_published({
        enterprise: Hydro::EntitySerializer.business(@coupon_business),
        actor: Hydro::EntitySerializer.user(@owner),
        organization: Hydro::EntitySerializer.organization(@org_to_attach),
        slug: @coupon_business.slug,
        status: :REDEMPTION_CANCELLED,
        coupon: nil,
        organization_previous_plan: @org_to_attach.plan.name,
      }, schema: "github.enterprise_account.v0.CreationFromCouponRedemption")
    end
  end

  context "#trial_org_creation_limit_reached?" do
    test "returns false for non-trial business" do
      refute_predicate @business, :trial?

      refute_predicate @business, :trial_org_creation_limit_reached?
    end

    test "returns false for trial business with less than three orgs created from business" do
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_equal 2, @business.enterprise_created_organizations.count
      assert_predicate @business, :trial?

      refute_predicate @business, :trial_org_creation_limit_reached?
    end

    test "returns true for trial business with three orgs created from business" do
      @business.add_organization(create :organization)
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_equal 3, @business.reload.enterprise_created_organizations.count
      assert_predicate @business, :trial?

      assert_predicate @business, :trial_org_creation_limit_reached?
    end

    test "returns true for trial business with more than three orgs created from business" do
      @business.add_organization(create :organization)
      @business.add_organization(create :organization)
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_equal 4, @business.reload.enterprise_created_organizations.count
      assert_predicate @business, :trial?

      assert_predicate @business, :trial_org_creation_limit_reached?
    end
  end
end if GitHub.billing_enabled?
