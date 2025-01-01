# typed: true
# frozen_string_literal: true

class Billing::Platform::CanProceedWithUsage
  class Response < T::Struct
    const :error, T.nilable(Billing::Platform::Api::Error)

    const :status, Symbol, default: :error
    const :can_proceed, T::Boolean, name: "canProceed", default: false
    const :applicable_budgets, T::Array[T.untyped], name: "applicableBudgets", default: []
    const :plan_discounts, T::Array[T.untyped], name: "planDiscounts", default: []
    const :plan_name, String, name: "planName", default: ""
  end

  class RequestParams < T::Struct
    prop :customer_id, T.any(String, Integer)
    prop :product, String
    prop :sku, String
    prop :repo_id, Integer, default: 0
    prop :org_id, Integer, default: 0
    prop :actor_id, Integer, default: 0
    prop :usage_at, Time, default: Time.now.utc

    # currently unused, see https://github.com/github/billing-platform/blob/main/docs/can_proceed_with_usage.md#usage
    prop :quantity, Billing::Types::NonMoneyNumeric, default: 0.0

    def missing_keys
      missing = []
      missing << :customer_id if customer_id.blank?
      missing << :product if product.blank?
      missing << :sku if sku.blank?
      missing
    end

    def valid?
      missing_keys.empty?
    end
  end

  sig { params(params: RequestParams).returns(Response) }
  def self.call(params)
    new(params).call
  end

  sig { params(params: RequestParams).void }
  def initialize(params)
    @params = params
    entity_detail = BillingPlatform::Base::EntityDetail.new(
      customerId: params.customer_id.to_s,
      repoId: params.repo_id,
      ownerId: params.org_id,
      actorId: params.actor_id,
    )
    @usage_key = BillingPlatform::Api::V1::UsageKey.new(
      product: params.product,
      sku: params.sku,
      entityDetail: entity_detail,
      usageAt: params.usage_at.to_i,
      quantity: params.quantity.to_f,
    )
    @client = Billing::Platform::Api::Client.new
  end

  sig { returns(Response) }
  def call
    response = client.can_proceed_with_usage(usage_key: usage_key)
    if response.is_a?(Billing::Platform::Api::Error)
      return Response.new(error: response)
    end

    Response.from_hash(response.with_indifferent_access)
  end

  private

  sig { returns(RequestParams) }
  attr_reader :params

  sig { returns(BillingPlatform::Api::V1::UsageKey) }
  attr_reader :usage_key

  sig { returns(Billing::Platform::Api::Client) }
  attr_reader :client
end
