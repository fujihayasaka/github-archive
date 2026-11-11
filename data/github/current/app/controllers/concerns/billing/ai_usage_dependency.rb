# typed: strict
# frozen_string_literal: true

module Billing::AiUsageDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include BillingSettingsHelper
  include Billing::UsageDependency
  include Billing::ProductsDependency
  include Billing::PremiumRequestsUsageDependency
  include Customers::Concerns::BillingPayload
  include Billing::TokenBasedBilling

  requires_ancestor { ApplicationController }

  abstract!

  TBB_LAUNCH_DATE = T.let(Time.utc(2026, 6, 1).freeze, Time)

  sig { params(entity: ::Billing::Types::Account).void }
  def ensure_ai_usage_enabled(entity:)
    render_404 unless billing_tbb_enabled?(entity)
  end

  sig { params(entity: ::Billing::Types::Account, current_user: T.nilable(User), is_stafftools_route: T::Boolean).void }
  def render_ai_usage(entity:, current_user:, is_stafftools_route: false)
    selected_link = entity.is_a?(Business) ? :business_billing_vnext_ai_usage : :billing_vnext_ai_usage
    customer = customer_payload(entity)
    copilot_plan = ai_usage_copilot_plan(entity)

    payload = {
      customer: customer,
      customer_selections: usage_customer_selections(entity),
      group_selections: premium_requests_usage_group_selections(entity, T.must(current_user), is_stafftools_route: is_stafftools_route),
      period_selections: premium_requests_usage_period_selections,
      report_type_selections: premium_request_usage_report_type_selections(entity: entity),
      min_custom_date: min_custom_date(customer: T.must(entity.customer), premium_request_report: true),
      disable_usage_reports: FeatureFlag.vexi.enabled?(:disable_billing_usage_reports, entity, default: false),
      slug: entity.to_param,
      overage_enabled: copilot_ai_unit_overage_enabled?(entity),
      ai_usage_launch_date: TBB_LAUNCH_DATE.iso8601,
      is_token_based_billing_enabled: billing_tbb_enabled?(entity),
      copilot_plan: copilot_plan,
    }

    if current_user
      payload[:current_user_email] = current_user.default_notification_email
      payload[:can_request_all_usage] = entity.is_a?(Business) ? entity.owner?(current_user) || entity.billing_manager?(current_user) : true
      payload[:is_copilot_standalone] = entity.is_a?(Business) && entity.is_copilot_standalone?
    end

    if entity.user? && current_user
      copilot_user = Copilot::User.new(T.cast(entity, ::User))
      payload[:billing_user_level_ai_units] = copilot_user.use_token_based_billing?
      if copilot_user.consumptive_user?
        payload[:cfi_quota] = cfi_quota_payload(copilot_user)
        payload[:copilot_trust_tier_limit_hit_banner] = trust_tier_limit_hit_banner_payload(copilot_user)
      end
    end

    render_react_app(
      payload: payload,
      page_data: { selected_link: selected_link, sidebar: :billing_and_licensing },
      layout: react_layout(entity, is_stafftools_route),
      title: "AI usage"
    )
  end

  sig { params(entity: ::Billing::Types::Account).returns(T.nilable(String)) }
  def ai_usage_copilot_plan(entity)
    case entity
    when Organization
      copilot_org = Copilot::Organization.new(entity)
      return "enterprise" if copilot_org.copilot_plan_enterprise?
      return "business" if copilot_org.copilot_plan_business?

      nil
    when User
      copilot_user = Copilot::User.new(entity)
      copilot_plan_for_user(copilot_user)
    when Business
      copilot_business = Copilot::Business.new(entity)
      return "enterprise" if copilot_business.copilot_plan_enterprise?
      return "business" if copilot_business.copilot_plan_business?

      nil
    end
  end

  sig { params(copilot_user: Copilot::User).returns(T.nilable(String)) }
  def copilot_plan_for_user(copilot_user)
    return "max" if copilot_user.has_max_subscription?
    return "pro_plus" if copilot_user.has_pro_plus_subscription?
    return "student" if copilot_user.active_subscription_is_edu
    return "pro" if copilot_user.has_pro_subscription?
    return "free" if copilot_user.limited_user.present?

    nil
  end

  sig { params(entity: ::Billing::Types::Account).returns(T::Boolean) }
  def copilot_ai_unit_overage_enabled?(entity)
    return false if entity.user?
    return false unless entity.customer

    customer_id = T.must(entity.customer).id.to_s
    is_for_business = entity.is_a?(Business)
    client = billing_platform_client

    skus = [
      Billing::OveragePolicyConfiguration::COPILOT_AI_UNIT,
      Billing::OveragePolicyConfiguration::CODING_AGENT_AI_UNIT,
      Billing::OveragePolicyConfiguration::SPARK_AI_UNIT,
    ]

    skus.any? do |sku|
      response = client.get_overage_policy(
        customer_id: customer_id,
        overage_policy_type: Billing::OveragePolicyConfiguration::SKU,
        name: sku,
        is_for_business: is_for_business,
      )

      next false if response.is_a?(Billing::Platform::Api::Error)

      response[:overagePolicy][:enabled] == true
    end
  rescue => e
    Failbot.report(e, app: "billing-platform", context: "copilot_ai_unit_overage_enabled?", customer_id: customer_id)
    false
  end

  sig { params(entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).returns(T.any(Symbol, String)) }
  def react_layout(entity, is_stafftools_route)
    if is_stafftools_route
      :default
    elsif entity.is_a?(Business)
      "react_business"
    elsif entity.is_a?(Organization)
      "organization_settings"
    else
      "user_settings"
    end
  end

  sig { params(copilot_user: Copilot::User).returns(T.nilable(Copilot::TrustTierLimitHitBannerPayload::Payload)) }
  def trust_tier_limit_hit_banner_payload(copilot_user)
    Copilot::TrustTierLimitHitBannerPayload.build(
      copilot_user: copilot_user,
      billing_platform_client: billing_platform_client,
      time_zone: copilot_user.user_object.time_zone,
    )
  end

  sig { params(copilot_user: Copilot::User).returns(T::Hash[Symbol, T.untyped]) }
  def cfi_quota_payload(copilot_user)
    overage = build_cfi_overage_data(copilot_user)

    {
      limits: build_entitlement_data(copilot_user),
      overage:,
    }
  end

  sig { params(copilot_user: Copilot::User).returns(T::Hash[Symbol, T.untyped]) }
  def build_entitlement_data(copilot_user)
    snapshot = copilot_user.quota_snapshots["premium_interactions"] || {}

    entitlement = snapshot.fetch(:entitlement, 0) || 0
    quota_remaining = (snapshot[:quota_remaining] || snapshot[:remaining] || 0).clamp(0, entitlement)
    entitlement_used = (entitlement.to_d - quota_remaining.to_d).to_f.round

    {
      entitlement:,
      entitlement_used:,
      reset_label: Copilot::QuotaDataHelper.format_reset_label(
        copilot_user.quota_reset_date,
        time_zone: copilot_user.user_object.time_zone
      ),
    }
  end

  sig { params(copilot_user: Copilot::User).returns(Copilot::QuotaDataHelper::OverageData) }
  def build_cfi_overage_data(copilot_user)
    overage_permitted = T.let(false, T::Boolean)
    overage_reset_label = T.let("", String)

    snapshot = copilot_user.quota_snapshots["premium_interactions"]
    if snapshot
      overage_permitted = snapshot[:overage_permitted] || false
    end

    customer = copilot_user.user_object.customer
    return Copilot::QuotaDataHelper.default_overage_data(overage_permitted:, overage_reset_label:) unless customer

    result = Copilot::QuotaDataHelper.fetch_budget_spend(client: billing_platform_client, customer_id: customer.id.to_s)
    return Copilot::QuotaDataHelper.default_overage_data(overage_permitted:, overage_reset_label:) unless result

    Copilot::QuotaDataHelper.build_overage_from_budget_values(
      budget_uuid: result[:uuid],
      budget_amount: result[:target_amount],
      current_spend: result[:current_spend],
      overage_permitted:,
      overage_reset_label:,
    )
  rescue StandardError => e
    Failbot.report(e, "context" => "billing.ai_usage.cfi_quota_overage")
    Copilot::QuotaDataHelper.default_overage_data(overage_permitted: overage_permitted || false, overage_reset_label: overage_reset_label || "")
  end
end
