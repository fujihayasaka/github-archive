# typed: true
# frozen_string_literal: true

# Represents the rate plan for Codespaces for interaction with Zuora subscriptions
class Billing::Codespaces::RatePlan
  PRODUCT_TYPE = "github.codespaces"
  PRODUCT_KEY = "v1" # v0 contains the previous compute and storage rate plan charges

  # From: https://github.com/github/gitcoin/issues/6712#issuecomment-825871948
  PRODUCTION_PRODUCT = {
    zuora_product_id: "2c92a00d7394b04a01739ba8e48315f2",
    zuora_product_rate_plan_id: "2c92a00878f898c60179001f84184164",
    zuora_product_rate_plan_charge_ids: {
      compute_d2: "2c92a01178f898d8017900260fb45e50",
      compute_d4: "2c92a00f78f898dd017900258c64574a",
      compute_d8: "2c92a00d78f898c501790024643973e3",
      compute_d16: "2c92a00f78f898e101790023c3464d77",
      compute_d32: "2c92a01078f88c6f017900233344322f",
      storage: "2c92a00e78f88c3b01790021e755628c"
    }
  }.freeze

  # From: https://github.com/github/gitcoin/issues/6712#issuecomment-840189219
  SANDBOX_PRODUCT = {
    zuora_product_id: "2c92c0f87250378d017252da38150320",
    zuora_product_rate_plan_id: "2c92c0f9795f39a10179630b0f660b9c",
    zuora_product_rate_plan_charge_ids: {
      compute_d2: "2c92c0f9795f39a1017963109c122979",
      compute_d4: "2c92c0f8795f29d60179631028093358",
      compute_d8: "2c92c0f8795f29d60179630fb8d12ab2",
      compute_d16: "2c92c0f8795f29d00179630f40a65540",
      compute_d32: "2c92c0f9795f39410179630edbb141b1",
      storage: "2c92c0f8795f29e40179630e2c1e6cac"
    }
  }.freeze

  def initialize
    @product_uuid = ::Billing::ProductUUID.find_by(product_type: PRODUCT_TYPE, product_key: PRODUCT_KEY) || create_product
  end

  # Public: The product rate plan ID
  #
  # Returns String
  def zuora_product_rate_plan_id
    product_uuid.zuora_product_rate_plan_id
  end

  # Public: The rate plan charge ID for Codespaces Compute D2 usage rate plan charge
  #
  # Returns String
  def compute_d2_product_rate_plan_charge_id
    product_uuid.zuora_product_rate_plan_charge_ids[:compute_d2]
  end

  # Public: The rate plan charge ID for Codespaces Compute D4 usage rate plan charge
  #
  # Returns String
  def compute_d4_product_rate_plan_charge_id
    product_uuid.zuora_product_rate_plan_charge_ids[:compute_d4]
  end

  # Public: The rate plan charge ID for Codespaces Compute D8 usage rate plan charge
  #
  # Returns String
  def compute_d8_product_rate_plan_charge_id
    product_uuid.zuora_product_rate_plan_charge_ids[:compute_d8]
  end

  # Public: The rate plan charge ID for Codespaces Compute D16 usage rate plan charge
  #
  # Returns String
  def compute_d16_product_rate_plan_charge_id
    product_uuid.zuora_product_rate_plan_charge_ids[:compute_d16]
  end

  # Public: The rate plan charge ID for Codespaces Compute D32 usage rate plan charge
  #
  # Returns String
  def compute_d32_product_rate_plan_charge_id
    product_uuid.zuora_product_rate_plan_charge_ids[:compute_d32]
  end

  # Public: The rate plan charge ID for Codespaces Storage rate plan charge
  #
  # Returns String
  def storage_product_rate_plan_charge_id
    product_uuid.zuora_product_rate_plan_charge_ids[:storage]
  end

  # Public: Hash of arguments needed for ZuoraSubscriptionParams
  # This method should only be used by ZuoraSubscriptionParams as the return may change
  #
  # Returns Hash
  def to_zuora_subscription_params
    {
      productRatePlanId: product_uuid.zuora_product_rate_plan_id,
      chargeOverrides: []
    }
  end

  private

  attr_reader :product_uuid, :user

  def codespaces_compute_d2_usage_overrides
    {
      productRatePlanChargeId: compute_d2_product_rate_plan_charge_id,
    }
  end

  def codespaces_compute_d4_usage_overrides
    {
      productRatePlanChargeId: compute_d4_product_rate_plan_charge_id,
    }
  end

  def codespaces_compute_d8_usage_overrides
    {
      productRatePlanChargeId: compute_d8_product_rate_plan_charge_id,
    }
  end

  def codespaces_compute_d16_usage_overrides
    {
      productRatePlanChargeId: compute_d16_product_rate_plan_charge_id,
    }
  end

  def codespaces_compute_d32_usage_overrides
    {
      productRatePlanChargeId: compute_d32_product_rate_plan_charge_id,
    }
  end

  def codespaces_storage_usage_overrides
    {
      productRatePlanChargeId: storage_product_rate_plan_charge_id,
    }
  end

  def create_product
    zuora_product =
      if Rails.env.production?
        PRODUCTION_PRODUCT
      else
        SANDBOX_PRODUCT
      end

    product_name = "GitHub Codespaces"
    billing_duration = User::BillingDependency::MONTHLY_PLAN

    charges = zuora_product[:zuora_product_rate_plan_charge_ids].map do |charge_key, charge_id|
      # NOTE: These prices are set directly in Zuora. We'll leave them as 0 for now.
      # Becuase these are new attributes, there's no real need to set the proper price
      # and once we work on a proper product catalog, the prices will be set properly there.
      Billing::ProductUUID::Charge.new(
        type: "overage",
        name: "#{product_name} #{charge_key.to_s.titleize}",
        price: 0,
        billing_duration: billing_duration,
        zuora_product_rate_plan_charge_id: charge_id,
      )
    end

    Billing::ProductUUID.create!(
      name: product_name,
      product_type: PRODUCT_TYPE,
      product_key: PRODUCT_KEY,
      billing_cycle: billing_duration,
      metered: true,
      zuora_product_id: zuora_product[:zuora_product_id],
      zuora_product_rate_plan_id: zuora_product[:zuora_product_rate_plan_id],
      zuora_product_rate_plan_charge_ids: zuora_product[:zuora_product_rate_plan_charge_ids],
      charges: charges
    )
  end
end
