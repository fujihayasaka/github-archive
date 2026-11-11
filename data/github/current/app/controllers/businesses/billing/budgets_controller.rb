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
    ApplicationRecord::Authnd,
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
    add_client_feature_flag([:billing_split_pru_skus, :billing_enterprise_budget_option_to_exclude_cost_centers, :billing_user_level_budgets, :billing_user_level_budgets_manage, :billing_discount_threshold_notification], entity: this_business)
    page = params[:page]&.to_i
    page_size = (params[:page_size] || params[:per_page])&.to_i
    scope = params[:scope]
    exclude_scope = params[:exclude_scope]
    scopes = params[:scopes]
    exclude_scopes = params[:exclude_scopes]

    render_budgets(
      this_entity: this_business,
      layout: "react_business",
      pagination: {
        page: page,
        page_size: page_size,
        scope: scope,
        exclude_scope: exclude_scope,
        scopes: scopes,
        exclude_scopes: exclude_scopes,
      }
    )
  end

  sig { void }
  def new
    # If customer is on trial they can't create budgets, redirect to index
    if this_business.plan.entitlement_plan_name == "enterprise_trial"
      redirect_to action: :index
    else
      add_client_feature_flag([:billing_enterprise_budget_option_to_exclude_cost_centers, :billing_user_level_budgets_manage, :billing_cost_centers_ui_pagination_enabled, :ipm_budget_deep_linking], entity: this_business)

      if admin_role == "enterprise_org_owner"
        add_client_feature_flag([:billing_cost_centers_disable_org_admin_pagination], entity: this_business)
      end

      payload = {
        slug: this_business.slug,
        adminRoles: admin_roles(this_business),
        current_user_id: current_user.global_relay_id,
        enabledProducts: enabled_products(this_business),
        enabledSkus: enabled_skus(this_entity: this_business),
        show_missing_payment_banner: false,
        show_models_banner: !this_business.models_billing_enabled?,
        showCopilotPremiumBanner: copilot_premium_overage_disabled?(this_business),
        copilotPremiumPolicyLink: copilot_premium_policy_link(this_business),
        customer: customer_payload(this_business),
        isCopilotStandalone: Copilot::Business.new(this_business).copilot_standalone?,
        is_token_based_billing_enabled: billing_tbb_enabled?(this_business),
      }

      prefill = build_budget_prefill
      payload[:prefill] = prefill if prefill.present?

      render_react_app payload: payload, page_data: { selected_link: :business_billing_vnext_budgets_alerts, sidebar: :billing_and_licensing }, title: "New monthly budget", layout: "react_business"
    end
  end

  sig { void }
  def edit
    budget_response = billing_platform_client.get_budget_by_uuid(
      customer_id: customer_id,
      uuid: params[:id]
    )

    if budget_response.is_a?(Billing::Platform::Api::Error)
      # Handle different error types appropriately
      if budget_response.http_404?
        return render_404
      elsif budget_response.http_5xx?
        # Server errors should be logged and return 500
        Failbot.report(budget_response)
        respond_to do |format|
          format.html { render_404 } # Show 404 to users for server errors too
          format.json { render json: { error: "Internal server error" }, status: :internal_server_error }
        end
        return
      else
        # For other 4xx errors (400, 401, 403, 409, etc.)
        respond_to do |format|
          format.html { render_404 } # Show 404 to users for client errors too
          format.json { render json: { error: "Bad request" }, status: :bad_request }
        end
        return
      end
    end

    budget = budget_response[:budget]
    if budget.nil? || budget.raw_budget_hash[:budget].nil?
      return render_404
    end

    # Verify organization owner has access to this budget
    unless authorized_to_access_budget?(budget.raw_budget_hash[:budget])
      return render_404
    end

    admin_roles = admin_roles(this_business)
    add_client_feature_flag([:billing_enterprise_budget_option_to_exclude_cost_centers, :billing_user_level_budgets_manage, :billing_cost_centers_ui_pagination_enabled], entity: this_business)

    render_react_app payload: {
      slug: this_business.slug,
      budget: budget.to_edit_json,
      adminRoles: admin_roles,
      enabledProducts: enabled_products(this_business),
      enabledSkus: enabled_skus(this_entity: this_business),
      show_missing_payment_banner: false,
      showCopilotPremiumBanner: copilot_premium_overage_disabled?(this_business),
      copilotPremiumPolicyLink: copilot_premium_policy_link(this_business),
      customer: customer_payload(this_business),
      is_token_based_billing_enabled: billing_tbb_enabled?(this_business),
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

    conflicting_key = single_sku_conflicting_budget_key(create_budget_request)
    if conflicting_key
      conflict_response = billing_platform_client.get_budget(key: conflicting_key)
      if conflict_response[:budget].present?
        existing_level = conflicting_key[:pricingTargetType] == "ProductPricing" ? "product" : "SKU"
        return render json: { error: "A budget already exists at the #{existing_level} level for this product" }, status: 400
      end
    end

    response = billing_platform_client.create_or_update_budget(budget: create_budget_request.to_json, feature_flag_target: this_business)
    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to create budget" }, status: 500
    end

    reason_type = reason_type(create_budget_request)
    publish_budget_changed_notification(create_budget_request.pricing_target_id, create_budget_request.pricing_target_type, this_business, customer_id, reason_type, target_type: create_budget_request.target_type, target_id: create_budget_request.target_id)

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
      exclude_cost_center_usage: create_budget_request[:excludeCostCenterUsage],
      status: "success"
    }

    GitHub.dogstats.increment("billing.budget_create", tags: ["pricing_target_id:#{create_budget_request.pricing_target_id}", "account_type:business"])

    budget_uuid = response.is_a?(Hash) ? response.dig(:budget, :uuid) : nil
    render json: { uuid: budget_uuid }
  end

  sig { void }
  def update
    # Preserve the existing budget's UUID to prevent replacement
    updated_params = budget_request_params.dup
    old_budget = fetch_old_budget(customer_id, params[:id])

    # Verify organization owner has access to this budget
    unless authorized_to_access_budget?(old_budget)
      return render json: { error: "Not found" }, status: 404
    end

    updated_params["uuid"] = old_budget&.dig("uuid") || params[:id]

    edit_budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
      raw_upsert_budget_request: updated_params,
      current_user: current_user,
      customer_id: customer_id,
      this_entity: this_business
    )

    response = billing_platform_client.create_or_update_budget(budget: edit_budget_request.to_json, feature_flag_target: this_business)
    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to edit budget" }, status: 500
    end

    reason_type = reason_type(edit_budget_request)
    publish_budget_changed_notification(edit_budget_request.pricing_target_id, edit_budget_request.pricing_target_type, this_business, customer_id, reason_type, target_type: edit_budget_request.target_type, target_id: edit_budget_request.target_id)

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
      exclude_cost_center_usage: edit_budget_request[:excludeCostCenterUsage],
      status: "success"
    }.merge(audit_fields)

    render_react_app payload: {}
  end

  sig { void }
  def destroy
    old_budget = nil
    begin
      old_budget = fetch_old_budget(customer_id, params[:id])
    rescue StandardError => e
      GitHub.logger.warn("Failed to fetch old budget for deletion", {
        exception: e,
        "gh.billing.customer.id": customer_id,
        "gh.billing_platform.budget.uuid": params[:id]
      })
    end

    unless authorized_to_access_budget?(old_budget)
      return render json: { error: "Not found" }, status: 404
    end

    response = billing_platform_client.delete_budget(customer_id: customer_id, uuid: params[:id], feature_flag_target: this_business)

    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to delete budget" }, status: 500
    end

    reason_type = Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::BUDGET_DELETED)

    if response[:pricingTargetId]
      publish_budget_changed_notification(response[:pricingTargetId], response[:pricingTargetType], this_business, customer_id, reason_type, target_type: (old_budget&.dig("key", "targetType") || response[:targetType])&.to_s, target_id: old_budget&.dig("key", "targetId") || response[:targetId])
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
      exclude_cost_center_usage: old_budget&.dig("excludeCostCenterUsage") || false,
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

  GHAS_PRODUCT = "ghas"
  GHAS_BUNDLED_SKU = "ghas_licenses"

  # Returns a conflicting budget key if the request targets a bundled GHAS product/SKU and a
  # budget at the opposite pricing level could conflict. Only applies when the business is bundled
  # (i.e. has a single ghas_licenses SKU rather than split SKUs).
  sig { params(budget_request: Billing::Platform::Api::UpsertBudgetRequest).returns(T.nilable(T::Hash[Symbol, String])) }
  def single_sku_conflicting_budget_key(budget_request)
    return nil unless this_business.advanced_security_products_bundled_for_entity?

    pricing_type = budget_request.pricing_target_type
    pricing_id = budget_request.pricing_target_id

    if pricing_type == "SkuPricing" && pricing_id == GHAS_BUNDLED_SKU
      budget_request.json_key.merge(pricingTargetType: "ProductPricing", pricingTargetId: GHAS_PRODUCT)
    elsif pricing_type == "ProductPricing" && pricing_id == GHAS_PRODUCT
      budget_request.json_key.merge(pricingTargetType: "SkuPricing", pricingTargetId: GHAS_BUNDLED_SKU)
    end
  end

  sig { params(budget_hash: T.nilable(T::Hash[String, T.untyped])).returns(T::Boolean) }
  def authorized_to_access_budget?(budget_hash)
    roles = admin_roles(this_business)
    is_only_org_owner = !roles.include?("owner") && !roles.include?("billing_manager") && roles.include?("enterprise_org_owner")

    # Business owners and billing managers can access any budget (or handle nil budget downstream)
    return true unless is_only_org_owner

    # For org-only admins, nil budget means not found
    if budget_hash.nil?
      return false
    end

    budget_type = budget_hash.dig("key", "targetType")
    budget_target_id = budget_hash.dig("key", "targetId")

    # Enterprise org owners (without business owner/billing manager roles) can only access
    # organization-scoped budgets for organizations they own
    # Only allow access to organization-type budgets (compare as strings to handle symbol/string mismatch)
    if budget_type.to_s == ORGANIZATION_TARGET
      owned_org_ids = current_user.owned_organizations.pluck(:id)
      owned_org_ids.include?(budget_target_id.to_i)
    elsif budget_type.to_s == REPOSITORY_TARGET
      # For repository-type budgets, check if the org that the repo belongs to is owned by the user
      repo = Repository.find_by(id: budget_target_id.to_i)
      if repo.nil?
        return false
      end
      owned_org_ids = current_user.owned_organizations.pluck(:id)
      owned_org_ids.include?(repo.organization_id)
    else
      # Organization owners cannot access non-organization budgets (business, CustomerResource, etc.)
      false
    end
  end
end
