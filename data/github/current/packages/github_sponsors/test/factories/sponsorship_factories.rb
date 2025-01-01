# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsorship do
    transient do
      quantity { 1 }
      monthly_price_in_cents { nil }
      skip_subscription_item { false }
      sponsor_login { "sponsor-#{SecureRandom.hex(9)}" }
      sponsorable_login { "sponsorable-#{SecureRandom.hex(9)}" }
      frequency { :recurring }
      tier_traits { [] }
      skip_metadata_creation { false }
      sponsor_factory { :credit_card_user }
    end

    sponsor do
      create(sponsor_factory, :verified, plan: GitHub::Plan.free_with_addons, login: sponsor_login)
    end
    privacy_level { "public" }
    active { true }
    activated_at { Time.now }
    subscribable_selected_at { Time.now }
    is_sponsor_opted_in_to_email { true }
    paid_at { Time.now }
    state { :active_test }

    trait :one_time do
      transient do
        frequency { :one_time }
      end
      expires_at { Sponsorship.expiration_time }
      skip_proration { true }
    end

    trait :pending do
      state { :pending }
      paid_at { nil }
    end

    trait :with_spammy_sponsor do
      sponsor do
        create(:credit_card_user, :verified, spammy: true, plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons, login: sponsor_login)
      end
    end

    trait :sponsor_with_valid_contact_for_billing do
      sponsor do
        create(sponsor_factory, :with_valid_contact_for_billing, :verified, plan: GitHub::Plan.free_with_addons, login: sponsor_login)
      end
    end

    trait :custom_amount do
      tier do
        listing = sponsorable&.sponsors_listing
        tier_attrs = { frequency: frequency, sponsorable_login: sponsorable_login }
        tier_attrs[:creator] = sponsor if sponsor
        tier_attrs[:sponsors_listing] = listing if listing
        create(:sponsors_tier, :custom, **tier_attrs)
      end

      expires_at { Sponsorship.expiration_time if tier&.one_time? }
      skip_proration { tier&.one_time? }
    end

    after(:build) do |sponsorship, evaluator|
      sponsorship.actor ||= sponsorship.sponsor

      tier = sponsorship.tier
      sponsorship.sponsorable ||= if tier
        tier.sponsorable
      end

      listing = sponsorship.sponsorable&.sponsors_listing
      sponsorship.tier ||= if listing&.default_tier
        sponsorship_frequency = evaluator.frequency || tier&.frequency
        listing.default_tier if sponsorship_frequency.to_s == listing.default_tier.frequency
      end

      if sponsorship.tier&.one_time?
        sponsorship.expires_at ||= Sponsorship.expiration_time
      end

      sponsorship.skip_proration = true if sponsorship.tier&.one_time?
    end

    after(:create) do |sponsorship, evaluator|
      sponsorship.instrument_sponsorship_start

      unless evaluator.skip_metadata_creation
        if sponsorship.sponsor.user?
          if metadata = sponsorship.sponsor.user_metadata
            metadata.update(sponsoring_count: metadata.sponsoring_count + 1, has_sponsoring_badge: true)
          else
            create(
              :user_metadata,
              user: sponsorship.sponsor,
              sponsoring_count: 1,
              has_sponsoring_badge: true,
            )
          end
        end

        if sponsorship.to_user?
          if metadata = sponsorship.sponsorable.user_metadata
            metadata.update(sponsors_count: metadata.sponsors_count + 1)
          else
            create(:user_metadata, user: sponsorship.sponsorable, sponsors_count: 1)
          end
        end
      end
    end

    trait :with_tier_repository do
      tier_traits { [:with_repository] }
    end

    before(:create) do |sponsorship, evaluator|
      sponsorship.sponsorable ||= create(:user, :sponsorable, sponsors_tier_count: 0,
        login: evaluator.sponsorable_login)

      if sponsorship.tier.nil? || evaluator.tier_traits.any?
        listing = sponsorship.sponsors_listing
        tier_attrs = {
          sponsors_listing: listing,
          frequency: evaluator.frequency,
          sponsorable_login: evaluator.sponsorable_login,
        }
        if evaluator.monthly_price_in_cents
          tier_attrs[:monthly_price_in_cents] = evaluator.monthly_price_in_cents
        end
        tier_traits = evaluator.tier_traits << :published
        sponsorship.tier = create(:sponsors_tier, *tier_traits, tier_attrs)
      end

      if !evaluator.skip_subscription_item && !sponsorship.tier&.invoiced? && sponsorship.subscription_item.nil?
        sponsor = sponsorship.sponsor
        sponsorship.subscription_item = create(:sponsors_subscription_item,
          account: sponsor,
          subscribable: sponsorship.tier,
          quantity: evaluator.quantity,
        )
      end
    end

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :unlocked do
      subscribable_selected_at { (Sponsorship::LOCK_CUTOFF_IN_DAYS + 1).days.ago }
    end

    trait :from_org do
      transient do
        sponsor_factory { :credit_card_org }
      end

      sponsor do
        create(sponsor_factory, plan_subscription: create(:billing_plan_subscription), login: sponsor_login)
      end
    end

    trait :with_org_sponsorable do
      sponsorable do
        create(:sponsors_listing, :approved, :for_org).sponsorable
      end
    end

    trait :private do
      privacy_level { "private" }
    end

    trait :public do
      privacy_level { "public" }
    end

    trait :email_opted_out do
      is_sponsor_opted_in_to_email { false }
    end

    trait :invoiced do
      invoiced_sponsorship_transfer { create(:invoiced_sponsorship_transfer) }
      sponsorable { invoiced_sponsorship_transfer.sponsorable }
      sponsor { invoiced_sponsorship_transfer.sponsor }
      subscription_item { nil }
      skip_subscription_item { true }
      expires_at { invoiced_sponsorship_transfer.created_at + 2.months }
      paid_at { invoiced_sponsorship_transfer&.transfer_created_at }

      tier do
        tier_attrs = {
          sponsors_listing: invoiced_sponsorship_transfer.sponsors_listing,
          creator: invoiced_sponsorship_transfer.sponsor,
        }
        tier_attrs[:monthly_price_in_cents] = monthly_price_in_cents if monthly_price_in_cents
        create(:sponsors_tier, :invoiced, **tier_attrs)
      end
    end

    trait :patreon do
      subscription_item { nil }
      skip_subscription_item { true }
      skip_metadata_creation { true }
      payment_source { "patreon" }
      custom_amount
      paid
    end

    trait :sponsors_invoiced do
      sponsor { create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription) }
      expires_at { 2.months.from_now }
    end

    trait :inactive do
      state { :inactive_test }
      active { false }
      before(:create) do |sponsorship, _|
        sponsorship.subscription_item&.update_attribute(:quantity, 0)
      end
    end

    trait :from_linked_org do
      sponsor do
        child_org = create(:credit_card_org,
          plan_subscription: create(:billing_plan_subscription),
          login: sponsor_login)
        create(:enterprise_linked_organization, sponsoring_linked_organization: child_org)
        child_org
      end
    end

    trait :paid do
      paid_at { Time.now }
      paid { true }
    end

    trait :unpaid do
      paid_at { nil }
      paid { false }
    end

    trait :with_billing_transaction_and_line_item do
      transient do
        platform_transaction_id { SecureRandom.hex(3) }
        plan_subscription { nil }
      end

      after(:create) do |sponsorship, evaluator|
        tier = sponsorship.tier
        sponsor = sponsorship.sponsor
        listing = tier.listing

        xact_attrs = {
          user: sponsor,
          amount_in_cents: tier.monthly_price_in_cents,
          platform_transaction_id: evaluator.platform_transaction_id,
          country: "USA",
          region: "California",
          postal_code: "90210",
        }
        if evaluator.plan_subscription
          xact_attrs[:plan_subscription] = evaluator.plan_subscription
        end
        transaction = create(:billing_transaction, xact_attrs)

        sponsorship_date = sponsorship.subscribable_selected_at || sponsorship.created_at

        # TODO: ideally this should come from the ProductUUID but these sponsor tiers are not
        # synced or created with one
        product_rate_plan_charge_id = SecureRandom.alphanumeric(32)

        transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => tier.monthly_price_in_dollars.to_i,
              "chargeName" => listing.monthly_plan_or_charge_name,
              "chargeAmount" => tier.monthly_price_in_dollars,
              "productRatePlanChargeId" => product_rate_plan_charge_id,
              "quantity" => 1,
              "serviceStartDate" => sponsorship_date.to_formatted_s(:date),
              "serviceEndDate" => (sponsorship_date + 1.month).to_formatted_s(:date),
            }, subscribable: tier),
          ]
        )

        fee_amount = Sponsorship.fee_at_sponsorship_payment_time_for(sponsor: sponsor, flat_price: tier.base_price)
        if fee_amount > 0
          # TODO: ideally this should come from the ProductUUID but these sponsor tiers are not
          # synced or created with one
          fee_product_rate_plan_charge_id = SecureRandom.alphanumeric(32)
          transaction.log_recurring_charge(
            billable_entity: sponsor,
            invoiced_items: [
              Billing::Zuora::SubscribableInvoiceItem.new({
                "id" => SecureRandom.alphanumeric(32),
                "chargeId" => SecureRandom.alphanumeric(32),
                "unitPrice" => tier.monthly_price_in_dollars,
                "chargeName" => SponsorsListing.fee_charge_name_for(listing.monthly_plan_or_charge_name),
                "chargeAmount" => fee_amount.cents,
                "quantity" => 1.0,
                "serviceStartDate" => sponsorship_date.to_formatted_s(:date),
                "serviceEndDate" => (sponsorship_date + 1.month).to_formatted_s(:date),
                "productRatePlanChargeId" => fee_product_rate_plan_charge_id,
              }, subscribable: tier),
            ]
          )
        end

        # billing callbacks update the record, such as the paid_at field
        sponsorship.reload
      end
    end

    trait :with_prorated_billing_transaction_and_line_item do
      transient do
        platform_transaction_id { SecureRandom.hex(3) }
      end

      after(:create) do |sponsorship, evaluator|
        tier = sponsorship.tier
        sponsor = sponsorship.sponsor

        transaction = create(:billing_transaction,
          user: sponsor,
          amount_in_cents: tier.monthly_price_in_cents / 2,
          platform_transaction_id: evaluator.platform_transaction_id,
          country: "USA",
          region: "California",
          postal_code: "90210",
        )

        product_rate_plan_charge_id = SecureRandom.alphanumeric(32)

        sponsorship_date = sponsorship.subscribable_selected_at || sponsorship.created_at
        charge_amount = tier.monthly_price_in_dollars / 2
        transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => charge_amount.to_i,
              "chargeName" => tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => charge_amount,
              "quantity" => 1,
              "serviceStartDate" => sponsorship_date.to_formatted_s(:date),
              "serviceEndDate" => (sponsorship_date + 15.days).to_formatted_s(:date),
              "productRatePlanChargeId" => product_rate_plan_charge_id,
            }, subscribable: tier),
          ],
          charge_type: Billing::BillingTransaction::PRORATED_CHARGE_TRANSACTION_TYPES.first,
        )

        # billing callbacks update the record, such as the paid_at field
        sponsorship.reload
      end
    end

    trait :with_failed_billing_transaction_and_line_item do
      transient do
        platform_transaction_id { SecureRandom.hex(3) }
      end

      after(:create) do |sponsorship, evaluator|
        tier = sponsorship.tier
        sponsor = sponsorship.sponsor

        transaction = create(:billing_transaction,
          :failed,
          user: sponsor,
          amount_in_cents: tier.monthly_price_in_cents,
          platform_transaction_id: evaluator.platform_transaction_id,
          country: "USA",
          region: "California",
          postal_code: "90210",
        )
        product_rate_plan_charge_id = SecureRandom.alphanumeric(32)

        sponsorship_date = sponsorship.subscribable_selected_at || sponsorship.created_at
        charge_amount = tier.monthly_price_in_dollars
        transaction.log_recurring_charge(
          billable_entity: sponsor,
          invoiced_items: [
            Billing::Zuora::SubscribableInvoiceItem.new({
              "chargeId" => SecureRandom.alphanumeric(32),
              "unitPrice" => charge_amount.to_i,
              "chargeName" => tier.listing.monthly_plan_or_charge_name,
              "chargeAmount" => charge_amount,
              "quantity" => 1,
              "serviceStartDate" => sponsorship_date.to_formatted_s(:date),
              "serviceEndDate" => (sponsorship_date + 1.month).to_formatted_s(:date),
              "productRatePlanChargeId" => product_rate_plan_charge_id,
            }, subscribable: tier),
          ],
        )

        # billing callbacks update the record, such as the paid_at field
        sponsorship.reload
      end
    end

    trait :with_payouts_ledger_entries do
      after :create do |sponsorship, _evaluator|
        sponsors_listing = sponsorship.sponsors_listing
        stripe_connect_account = sponsors_listing.active_stripe_account_for_self_or_fiscal_host
        if sponsorship.manual_invoiced?
          transfer = sponsorship.invoiced_sponsorship_transfer
          extra_payment_attrs = { primary_reference_id: transfer.zuora_payment_id }
          extra_transfer_attrs = { zuora_transaction_id: transfer.zuora_payment_id }
        else
          billing_transaction = Billing::BillingTransaction.last
          extra_payment_attrs = { billing_transaction: billing_transaction }
          extra_transfer_attrs = { billing_transaction: billing_transaction }
        end

        create(:payouts_ledger_entry, :payment,
          sponsors_listing: sponsors_listing,
          stripe_connect_account: stripe_connect_account,
          **extra_payment_attrs
        )
        create(:payouts_ledger_entry, :transfer,
          sponsors_listing: sponsors_listing,
          stripe_connect_account: stripe_connect_account,
          **extra_transfer_attrs
        )
      end
    end

    trait :pending_cancellation do
      after(:create) do |sponsorship, _evaluator|
        create(:billing_pending_subscription_item_change,
          :cancellation,
          subscribable: sponsorship.tier,
          account: sponsorship.billable_entity
        )
      end
    end

    trait :pending_activation do
      after(:create) do |sponsorship, _evaluator|
        # to create a pending activation, we deactivate the current subscription item, and schedule an activation
        sponsorship.subscription_item.update!(quantity: 0)

        create(:billing_pending_subscription_item_change,
          quantity: 1,
          subscribable: sponsorship.tier,
          account: sponsorship.billable_entity
        )
      end
    end

    trait :pending_downgrade do
      after(:create) do |sponsorship, _evaluator|
        # to create a pending downgrade, we generate a new higher-value tier for the listing, switch to using it,
        # and then schedule a pending sub item change back to the previous tier.
        lower_tier = sponsorship.tier
        higher_tier = create(:sponsors_tier, :published, listing: sponsorship.sponsors_listing)
        sponsorship.update!(tier: higher_tier)
        sponsorship.subscription_item.update!(subscribable: higher_tier)

        create(:billing_pending_subscription_item_change,
          quantity: 1,
          subscribable: lower_tier,
          account: sponsorship.billable_entity
        )
      end
    end

    trait :via_bulk_sponsorship do
      after(:create) do |sponsorship, _evaluator|
        create(:sponsors_activity, :new_sponsorship, :via_bulk_sponsorship,
          sponsor: sponsorship.sponsor,
          sponsorable: sponsorship.sponsorable,
          sponsors_tier: sponsorship.tier,
        )
      end
    end

    trait :with_activity do
      after(:create) do |sponsorship, _evaluator|
        create(:sponsors_activity,
          sponsor: sponsorship.sponsor,
          sponsorable: sponsorship.sponsorable,
          sponsors_tier: sponsorship.tier,
        )
      end
    end

    trait :with_business_tax_identifier do
      before(:create) do |sponsorship|
        create(:sponsors_business_tax_identifier, user: sponsorship.sponsor)
      end
    end
  end
end
