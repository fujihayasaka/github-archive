# typed: strict
# frozen_string_literal: true

class Businesses::Billing::BudgetsController < Businesses::BillingsController
  T.unsafe(self).react_bundle_name = "billing-app"

  include ApplicationController::VerifiedFetchDependency
  include Billing::Platform::Api::Utils
  include Billing::BudgetsDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    only: [:new, :index, :edit]

  allow_verified_fetch only: [:index, :create, :update, :destroy]

  rescue_from Billing::Platform::Api::UpsertBudgetRequest::InvalidTargetError,
    Billing::Platform::Api::UpsertBudgetRequest::InvalidRequestError do
    render json: { error: "Invalid target" }, status: 400
  end

  rescue_from Billing::Platform::Api::UpsertBudgetRequest::InvalidAccessError do
    render json: { error: "Not found" }, status: 404
  end

  before_action :set_organizations, only: [:new, :edit]

  sig { void }
  def index
    render_budgets(this_entity: this_business, layout: "react_business")
  end

  sig { void }
  def new
    # If customer is on trial they can't create budgets, redirect to index
    if this_business.plan.entitlement_plan_name == "enterprise_trial"
      redirect_to action: :index
    else
      render_react_app payload: {
        slug: this_business.slug,
        adminRoles: admin_roles(this_business),
        current_user_id: current_user.global_relay_id,
        enabledProducts: enabled_products(this_business),
        enabledSkus: enabled_skus(this_entity: this_business),
        show_missing_payment_banner: false,
        show_models_banner: !this_business.models_billing_enabled?,
        showCopilotPremiumBanner: copilot_premium_overage_disabled?(this_business),
        copilotPremiumPolicyLink: copilot_premium_policy_link(this_business),
        billing_coding_agent_enabled: billing_coding_agent_enabled?(this_business),
        customer: customer_payload(this_business),
        billing_spark_enabled: billing_spark_enabled?(this_business),
      }, page_data: { selected_link: :business_billing_vnext_budgets_alerts, sidebar: :billing_and_licensing }, title: "New monthly budget", layout: "react_business"
    end
  end

  sig { void }
  def edit
    budget_response = billing_platform_client.get_budget_by_uuid(
      customer_id: customer_id,
      uuid: params[:id]
    )

    render_react_app payload: {
      slug: this_business.slug,
      budget: budget_response[:budget].to_edit_json,
      adminRoles: admin_roles(this_business),
      enabledProducts: enabled_products(this_business),
      enabledSkus: enabled_skus(this_entity: this_business),
      show_missing_payment_banner: false,
      showCopilotPremiumBanner: copilot_premium_overage_disabled?(this_business),
      copilotPremiumPolicyLink: copilot_premium_policy_link(this_business),
      customer: customer_payload(this_business),
    }, page_data: { selected_link: :business_billing_vnext_budgets_alerts, sidebar: :billing_and_licensing }, title: "Edit monthly budget", layout: "react_business"
  end

  sig { void }
  def create
    create_budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
      raw_upsert_budget_request: budget_request_params,
      current_user: current_user,
      customer_id: customer_id,
      this_entity: this_business
    )

    budget_response = billing_platform_client.get_budget(key: create_budget_request.json_key)

    if budget_response[:budget].present?
      return render json: { error: "Budget with this key already exists" }, status: 400
    end

    response = billing_platform_client.create_or_update_budget(budget: create_budget_request.to_json)
    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to create budget" }, status: 500
    end

    reason_type = reason_type(create_budget_request)
    publish_budget_changed_notification(create_budget_request.pricing_target_id, create_budget_request.pricing_target_type, this_business, customer_id, reason_type)

    GitHub.instrument "billing.budget_create", {
      actor: current_user,
      customer_id: this_business.customer_id.to_s,
      business: this_business,
      target_amount: create_budget_request[:targetAmount],
      target_type: create_budget_request[:targetType],
      target_id: create_budget_request[:targetId],
      alert_enabled: create_budget_request[:alertEnabled],
      pricing_target_type: create_budget_request[:pricingTargetType],
      pricing_target_id: create_budget_request[:pricingTargetId],
      budget_limit_type: create_budget_request[:budgetLimitType],
      status: "success"
    }

    GitHub.dogstats.increment("billing.budget_create", tags: ["pricing_target_id:#{create_budget_request.pricing_target_id}", "account_type:business"])

    render_react_app payload: {}
  end

  sig { void }
  def update
    old_budget = fetch_old_budget(customer_id, params[:id])

    edit_budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
      raw_upsert_budget_request: budget_request_params,
      current_user: current_user,
      customer_id: customer_id,
      this_entity: this_business
    )

    response = billing_platform_client.create_or_update_budget(budget: edit_budget_request.to_json)
    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to edit budget" }, status: 500
    end

    reason_type = reason_type(edit_budget_request)
    publish_budget_changed_notification(edit_budget_request.pricing_target_id, edit_budget_request.pricing_target_type, this_business, customer_id, reason_type)

    audit_fields = build_audit_fields(old_budget, edit_budget_request)

    GitHub.instrument "billing.budget_update", {
      actor: current_user,
      customer_id: this_business.customer_id.to_s,
      business: this_business,
      target_amount: edit_budget_request[:targetAmount],
      pricing_target_type: edit_budget_request[:pricingTargetType],
      pricing_target_id: edit_budget_request[:pricingTargetId],
      budget_limit_type: edit_budget_request[:budgetLimitType],
      target_type: edit_budget_request[:targetType],
      target_id: edit_budget_request[:targetId],
      alert_enabled: edit_budget_request[:alertEnabled],
      status: "success"
    }.merge(audit_fields)

    render_react_app payload: {}
  end

  sig { void }
  def destroy
    old_budget = nil
    begin
      old_budget = fetch_old_budget(customer_id, params[:id])
    rescue => e
      Rails.logger.warn("Failed to fetch old budget for deletion: #{e.message}")
    end

    response = billing_platform_client.delete_budget(customer_id: customer_id, uuid: params[:id])

    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to delete budget" }, status: 500
    end

    reason_type = Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::BUDGET_DELETED)

    if response[:pricingTargetId]
      publish_budget_changed_notification(response[:pricingTargetId], response[:pricingTargetType], this_business, customer_id, reason_type)
    end

    GitHub.instrument "billing.budget_delete", {
      actor: current_user,
      customer_id: this_business.customer_id.to_s,
      business: this_business,
      uuid: params[:id],
      pricing_target_type: old_budget&.dig("key", "pricingTargetType") || response[:pricingTargetType],
      pricing_target_id: old_budget&.dig("key", "pricingTargetId") || response[:pricingTargetId],
      budget_limit_type: old_budget&.dig("budgetLimitType") || response[:budgetLimitType],
      target_type: old_budget&.dig("key", "targetType") || response[:targetType],
      target_amount: old_budget&.dig("targetAmount") || response[:targetAmount],
      alert_enabled: old_budget&.dig("budgetAlerting", "willAlert") || false,
      status: "success"
    }

    render json: {}
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  memoize def budget_request_params
    JSON.parse(request.body.read)
  end

  sig { returns(String) }
  def customer_id
    this_business.customer_id.to_s
  end
end
