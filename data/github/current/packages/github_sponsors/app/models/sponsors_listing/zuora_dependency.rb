# typed: true
# frozen_string_literal: true

module SponsorsListing::ZuoraDependency
  extend ActiveSupport::Concern

  extend T::Helpers

  include GitHub::BatchMethod
  include Billing::ZuoraProduct::ZuoraSettings
  include GitHub::Memoizer

  class ZuoraSyncError < StandardError; end

  class ZuoraProductRatePlanSyncResult < T::Struct
    prop :id, String
    prop :created, T::Boolean

    def created?
      created
    end
  end

  requires_ancestor { SponsorsListing }

  ZUORA_PRODUCT_CATEGORY = "sponsorships"
  ZUORA_PRODUCT_TYPE = "sponsorable.sponsors_listing"
  MONTHLY_CHARGE_NAME_SUFFIX = ": Recurring #{User::BillingDependency::MONTHLY_PLAN}ly"
  YEARLY_CHARGE_NAME_SUFFIX = ": Recurring #{User::BillingDependency::YEARLY_PLAN}ly"
  FEE_CHARGE_SUFFIX = " fee"

  # The unit cost for each rate plan will be 1 USD.
  # We will leverage chargeOverrides to change the sponsorship amount.
  UNIT_COST = "1"

  class_methods do

    # Public: Get the value to use for a sponsorship fee charge, given the corresponding non-fee charge's name.
    #
    # charge_name - a String like "sponsors-user-123: Recurring monthly"
    #
    # Returns a String, e.g., "sponsors-user-123: Recurring monthly fee".
    sig { params(charge_name: String).returns(String) }
    def fee_charge_name_for(charge_name)
      "#{charge_name}#{FEE_CHARGE_SUFFIX}"
    end
  end

  included do
    # Public: Get the product UUID for this Sponsors listing for the specified billing cycle.
    #
    # billing_cycle - Symbol or String "month", "one_time", or "year"
    #
    # Examples
    #
    #   # To prevent N+1s when this method is called on a list of SponsorsListing records, prefill it this way:
    #
    #   # Execute 1 query to preload:
    #   GitHub::PrefillAssociations.prefill_batch_method(sponsors_listings, :product_uuid, "month")
    #
    #   sponsors_listings.each do |sponsors_listing|
    #     # Method is preloaded and memoized -- no queries are executed here!
    #     sponsors_listing.product_uuid("month")
    #   end
    #
    # Returns a Billing::ProductUUID or nil.
    batch_method :product_uuid do |sponsors_listings, billing_cycle|
      product_keys_by_sponsors_listing_id = sponsors_listings.each_with_object({}) do |sponsors_listing, hash|
        hash[sponsors_listing.id] = sponsors_listing.product_key(billing_cycle: billing_cycle)
      end

      product_keys = product_keys_by_sponsors_listing_id.values
      product_uuids = Billing::ProductUUID.sponsors_listings.with_product_key(product_keys)
      product_uuids_by_product_key = product_uuids.each_with_object({}) do |product_uuid, hash|
        hash[product_uuid.product_key] = product_uuid
      end

      sponsors_listings.each_with_object({}) do |sponsors_listing, hash|
        product_key = product_keys_by_sponsors_listing_id[sponsors_listing.id]
        product_uuid = product_uuids_by_product_key[product_key]
        hash[sponsors_listing] = product_uuid
      end
    end
  end

  sig { void }
  def sync_to_zuora
    return unless GitHub.billing_enabled?
    return unless approved?

    create_zuora_product
    create_rate_plans
  end

  # billing_cycle - String "month", "one_time", or "year"
  sig { params(billing_cycle: T.any(String, Symbol)).returns(String) }
  def product_key(billing_cycle:)
    "#{id}-#{billing_cycle}"
  end

  # billing_cycle - String "month", "one_time", or "year"
  sig { params(billing_cycle: T.any(String, Symbol)).returns(T.nilable(String)) }
  def zuora_rate_plan_id(billing_cycle:)
    billing_cycle = billing_cycle.to_s.downcase
    return unless Billing::ProductUUID.billing_cycles.key?(billing_cycle)

    product = product_uuid(billing_cycle)
    return product.zuora_product_rate_plan_id if product

    if approved?
      log_missing_necessary_zuora_product_and_sync(method_name: __method__, billing_cycle: billing_cycle)
    end

    nil
  end

  ZuoraRatePlanChargeIdsType = T.type_alias { { flat: String, fee: String } }

  # billing_cycle - String "month", "one_time", or "year"
  #
  # Returns a Hash with keys :flat and :fee and String values, e.g., `{:flat=>"8ad08cbd8707aae301870a970de44b95",
  # :fee=>"8ad08cbd8707aae301870a970e144b9f"}`.
  sig { params(billing_cycle: T.any(String, Symbol)).returns(T.nilable(ZuoraRatePlanChargeIdsType)) }
  def zuora_rate_plan_charge_ids(billing_cycle:)
    billing_cycle = billing_cycle.to_s.downcase
    return unless Billing::ProductUUID.billing_cycles.key?(billing_cycle)

    product = product_uuid(billing_cycle)
    return T.cast(product.zuora_product_rate_plan_charge_ids, ZuoraRatePlanChargeIdsType) if product

    if approved?
      log_missing_necessary_zuora_product_and_sync(method_name: __method__, billing_cycle: billing_cycle)
    end

    nil
  end

  sig { returns String }
  def zuora_slug
    "sponsors-#{sponsorable.class}-#{sponsorable_id}".parameterize
  end

  sig { returns String }
  def monthly_plan_or_charge_name
    "#{zuora_slug}#{MONTHLY_CHARGE_NAME_SUFFIX}"
  end

  sig { returns String }
  def yearly_plan_or_charge_name
    "#{zuora_slug}#{YEARLY_CHARGE_NAME_SUFFIX}"
  end

  # Public: Rename the Zuora product and update its maintainer name to match the specified new Sponsors listing slug
  # and the new login for the Sponsors listing's sponsorable.
  #
  # old_slug - the String slug that this Sponsors listing used to have
  # new_slug - the String slug that this Sponsors listing will have
  # new_login - the String login for the User or Organization this Sponsors listing represents
  #
  # Returns a Boolean indicating success. Returns true if there's no Zuora product to update.
  sig { params(old_slug: String, new_slug: String, new_login: String).returns(T::Boolean) }
  def update_zuora_product_and_maintainer_name(old_slug:, new_slug:, new_login:)
    product_id_to_update = GitHub.zuorest_client.get_product_id_for_name(old_slug)
    unless product_id_to_update
      GitHub.dogstats.increment("sponsors_listing.zuora_product_rename", tags: ["old_product_exists:false"])
      return true
    end

    result = ::Billing::ProductUUID.where(zuora_product_id: product_id_to_update)
      .update_all(name: new_slug)

    unless result
      GitHub.dogstats.increment(
        "sponsors_listing.zuora_product_rename",
        tags: ["old_product_exists:true", "success:false"]
      )

      return false
    end

    result = GitHub.zuorest_client.update_product(product_id_to_update,
      Name: new_slug,
      MaintainerName__c: new_login,
    )
    success = result["Success"]

    GitHub.dogstats.increment("sponsors_listing.zuora_product_rename",
      tags: ["old_product_exists:true", "success:#{success}"])

    success
  end

  def zuora_product_id
    return @zuora_product_id if defined?(@zuora_product_id)
    @zuora_product_id = GitHub.zuorest_client.get_product_id_for_name(slug)
  end

  private

  sig { params(method_name: T.nilable(Symbol), billing_cycle: String).void }
  def log_missing_necessary_zuora_product_and_sync(method_name:, billing_cycle:)
    GitHub.logger.error("Sponsors listing is missing necessary Zuora product",
      "code.namespace": self.class.name,
      "gh.catalog_service": "github/github_sponsors",
      "code.function": method_name,
      "gh.user.id": sponsorable_id,
      "gh.billing_cycle": billing_cycle,
    )
    SponsorsListingZuoraSyncJob.perform_later(T.cast(self, SponsorsListing))
  end

  sig { returns String }
  def create_zuora_product
    return zuora_product_id if zuora_product_id.present?

    result = GitHub.zuorest_client.create_product(
      {
        Name: slug,
        EffectiveStartDate: backdated_start_date.to_s,
        EffectiveEndDate: EFFECTIVE_END_DATE,
        ProductCategory__c: ZUORA_PRODUCT_CATEGORY,
        MaintainerName__c: sponsorable&.login,
        MaintainerSlug__c: zuora_slug,
      },
    )
    @zuora_product_id = result["Id"]
  end

  # Metadata on one-time, monthly recurring, and yearly recurring rate plan charges
  sig { returns T::Array[{ billing_cycle: String, charge_type: String, charge_name: String, plan_name: String }] }
  def rate_plan_charges
    [
      {
        billing_cycle: Billing::ProductUUID::ONE_TIME_BILLING_CYCLE,
        charge_type: "OneTime",
        charge_name: "#{zuora_slug}: One-Time",
        plan_name: "#{zuora_slug}: One-Time",
      },
      {
        billing_cycle: User::BillingDependency::MONTHLY_PLAN,
        charge_type: "Recurring",
        charge_name: monthly_plan_or_charge_name,
        plan_name: monthly_plan_or_charge_name,
      },
      {
        billing_cycle: User::BillingDependency::YEARLY_PLAN,
        charge_type: "Recurring",
        charge_name: yearly_plan_or_charge_name,
        plan_name: yearly_plan_or_charge_name,
      },
    ]
  end

  sig { void }
  def create_rate_plans
    product_keys = rate_plan_charges.map { |options| product_key(billing_cycle: options.fetch(:billing_cycle)) }.uniq
    product_uuid_existence_by_product_key = Billing::ProductUUID
      .where(product_type: ZUORA_PRODUCT_TYPE, product_key: product_keys)
      .pluck(:product_key, :id)
      .each_with_object({}) { |(product_key, id), hash| hash[product_key] = id.present? }

    rate_plan_charges.each do |options|
      billing_cycle = options.fetch(:billing_cycle)
      charge_type   = options.fetch(:charge_type)
      charge_name   = options.fetch(:charge_name)
      plan_name     = options.fetch(:plan_name)

      product_key = product_key(billing_cycle: billing_cycle)
      next if product_uuid_existence_by_product_key[product_key]

      product_rate_plan_sync_result = sync_zuora_product_rate_plan(plan_name)
      zuora_product_rate_plan_charge_ids = sync_zuora_product_rate_plan_charges(
        charge_name, billing_cycle, charge_type, product_rate_plan_sync_result
      )

      base_charge = Billing::ProductUUID::Charge.new(
        type: "flat",
        name: charge_name,
        price: UNIT_COST.to_d,
        billing_duration: billing_cycle,
        zuora_product_rate_plan_charge_id: zuora_product_rate_plan_charge_ids[:flat],
      )
      fee_charge = Billing::ProductUUID::Charge.new(
        type: "flat",
        name: SponsorsListing.fee_charge_name_for(charge_name),
        price: UNIT_COST.to_d,
        billing_duration: billing_cycle,
        zuora_product_rate_plan_charge_id: zuora_product_rate_plan_charge_ids[:fee],
      )

      Billing::ProductUUID.throttle_writes_with_retry do
        Billing::ProductUUID.create!(
          name: slug,
          product_type: ZUORA_PRODUCT_TYPE,
          product_key: product_key,
          billing_cycle: billing_cycle,
          zuora_product_id: zuora_product_id,
          zuora_product_rate_plan_id: product_rate_plan_sync_result.id,
          zuora_product_rate_plan_charge_ids: {
            flat: base_charge.zuora_product_rate_plan_charge_id,  # The base charge rate plan
            fee: fee_charge.zuora_product_rate_plan_charge_id,   # The fee charge rate plan
          },
          charges: [base_charge, fee_charge]
        )
      end
    end
  end

  sig { params(plan_name: String).returns(ZuoraProductRatePlanSyncResult) }
  def sync_zuora_product_rate_plan(plan_name)
    resp = GitHub.zuorest_client.create_product_rate_plan(
      EffectiveStartDate: backdated_start_date.to_s,
      EffectiveEndDate: EFFECTIVE_END_DATE,
      Name: plan_name,
      ProductId: zuora_product_id,
    )
    if resp["Success"] || resp["success"]
      ZuoraProductRatePlanSyncResult.new(id: resp["Id"], created: true)
    elsif resp["Errors"]&.detect { |error| error["Code"] == "DUPLICATE_VALUE" }
      product_rate_plan = zuora_product_rate_plans.detect { |plan| plan["name"] == plan_name }
      ZuoraProductRatePlanSyncResult.new(id: product_rate_plan["id"], created: false)
    else
      error_sentence = resp["Errors"].map["Message"].join(", ")
      raise ZuoraSyncError.new(error_sentence)
    end
  end

  sig do
    params(
      base_charge_name: String,
      billing_cycle: String,
      charge_type: String,
      product_rate_plan_sync: ZuoraProductRatePlanSyncResult
    ).returns({ flat: String, fee: String })
  end
  def sync_zuora_product_rate_plan_charges(base_charge_name, billing_cycle, charge_type, product_rate_plan_sync)
    # TODO handle case when already exists or errors on creation
    rate_plan_id = product_rate_plan_sync.id
    billing_period = billing_cycle == User::BillingDependency::YEARLY_PLAN ? "Annual" : "Month"
    fee_charge_name = SponsorsListing.fee_charge_name_for(base_charge_name)

    rate_plan_charge_params = default_zuora_rate_plan_charge_params.merge(
      BillingPeriod: billing_period, # This will be Month for One Time as no other values are applicable
      ChargeType: charge_type,
      ProductRatePlanId: rate_plan_id,
    )

    # This ensures that each yearly subscription will renew on the day it started.
    if billing_cycle == User::BillingDependency::YEARLY_PLAN
      rate_plan_charge_params[:BillingPeriodAlignment] = "AlignToSubscriptionStart"
    end

    if !product_rate_plan_sync.created?
      existing_charges = zuora_product_rate_plan_charges(rate_plan_id)
      if existing_charges.present?
        is_fee_charge = proc do |charge|
          charge["name"].ends_with?(SponsorsListing::ZuoraDependency::FEE_CHARGE_SUFFIX)
        end
        return {
          flat: existing_charges.find { |charge| is_fee_charge.call(charge) }&.fetch("id"),
          fee: existing_charges.find { |charge| !is_fee_charge.call(charge) }&.fetch("id")
        }
      end
    end

    rate_plan_charges = [
      rate_plan_charge_params.merge(
        Name: base_charge_name
      ),
      rate_plan_charge_params.merge(
        Name: fee_charge_name,
        ProductRevenueTreatment__c: "Corp Sponsors Fee"
      )
    ]

    resp = GitHub.zuorest_client.create_action(
      type: "ProductRatePlanCharge",
      objects: rate_plan_charges
    )

    {
      flat: resp[0]["Id"],
      fee: resp[1]["Id"],
    }
  end

  sig { returns T::Hash[Symbol, T.untyped] }
  def default_zuora_rate_plan_charge_params
    {
      ChargeModel: "Flat Fee Pricing", # We will modify prices through overrides
      DeferredRevenueAccount: DEFERRED_REVENUE_ACCOUNT,
      RecognizedRevenueAccount: RECOGNIZED_REVENUE_ACCOUNT,
      TaxCode: TAX_CODE,
      TaxMode: "TaxExclusive",
      Taxable: false,
      TriggerEvent: "ContractEffective",
      ProductRatePlanChargeTierData: {
        ProductRatePlanChargeTier: [
          {
            Currency: "USD",
            Price: UNIT_COST,
          },
        ],
      },
    }
  end

  # Backdate the start date 1 year so new subscriptions can be backdated to the
  # sponsors' billing cycle to bypass proration.
  sig { returns Date }
  def backdated_start_date
    GitHub::Billing.today - 1.year
  end

  memoize def zuora_product_rate_plans
    GitHub.zuorest_client.get_product_rate_plan(zuora_product_id)["productRatePlans"]
  end

  sig { params(rate_plan_id: String).returns(T::Array[Hash]) }
  def zuora_product_rate_plan_charges(rate_plan_id)
    rate_plan = zuora_product_rate_plans.find { |rate_plan| rate_plan["id"] == rate_plan_id }
    if rate_plan.present?
      rate_plan["productRatePlanCharges"]
    else
      []
    end
  end
end
