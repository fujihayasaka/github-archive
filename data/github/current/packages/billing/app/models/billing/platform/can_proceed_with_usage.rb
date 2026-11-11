# typed: true
# frozen_string_literal: true

class Billing::Platform::CanProceedWithUsage
  class Response < T::Struct
    const :error, T.nilable(Billing::Platform::Api::Error)

    const :status, Symbol, default: :error
    const :can_proceed, T.nilable(T::Boolean), name: "canProceed", default: nil
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
    prop :trust_tier, Integer, default: 0
    # BillingPlatform::Base::CopilotPlan enum value. Left nil to elide the
    # field from the wire entirely (proto3_optional tracks presence, so
    # setting to 0/UNKNOWN would still send the field).
    prop :copilot_plan, T.nilable(Integer), default: nil

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

  sig { params(params: RequestParams, timeout: T.nilable(T.any(Integer, Float))).returns(Response) }
  def self.call(params, timeout: nil)
    new(params, timeout: timeout).call
  end

  sig { params(params: RequestParams, timeout: T.nilable(T.any(Integer, Float))).void }
  def initialize(params, timeout: nil)
    @params = params
    entity_detail_args = {
      customerId: params.customer_id.to_s,
      repoId: params.repo_id,
      ownerId: params.org_id,
      actorId: params.actor_id,
    }
    # Only set copilotPlan when explicitly provided. proto3_optional preserves
    # field presence, so omitting it keeps the wire format unchanged for
    # callers that don't opt in.
    entity_detail_args[:copilotPlan] = params.copilot_plan unless params.copilot_plan.nil?
    entity_detail = BillingPlatform::Base::EntityDetail.new(**entity_detail_args)
    @usage_key = BillingPlatform::Api::V1::UsageKey.new(
      product: params.product,
      sku: params.sku,
      entityDetail: entity_detail,
      usageAt: params.usage_at.to_i,
      quantity: params.quantity.to_f,
    )
    @trust_tier = @params.trust_tier
    @client = Billing::Platform::Api::Client.new(timeout: timeout)
  end

  sig { returns(Response) }
  def call
    response = client.can_proceed_with_usage(usage_key: usage_key, trust_tier: trust_tier)

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

  sig { returns(Integer) }
  attr_reader :trust_tier

  sig { returns(Billing::Platform::Api::Client) }
  attr_reader :client
end
