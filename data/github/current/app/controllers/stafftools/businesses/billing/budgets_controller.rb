# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::BudgetsController < Stafftools::Businesses::BillingController

  include ApplicationController::VerifiedFetchDependency
  include Billing::Platform::Api::Utils
  include Billing::BudgetsDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index]


  allow_verified_fetch only: [:index, :create, :update]

  sig { returns(String) }
  def self.react_bundle_name
    "billing-app"
  end

  sig { void }
  def index
    page = params[:page]&.to_i
    page_size = (params[:page_size] || params[:per_page])&.to_i
    scope = params[:scope]
    exclude_scope = params[:exclude_scope]

    render_budgets(
      this_entity: this_business,
      is_stafftools_route: true,
      pagination: {
        page: page,
        page_size: page_size,
        scope: scope,
        exclude_scope: exclude_scope
      }
    )
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
      showCopilotPremiumBanner: copilot_premium_overage_disabled?(this_business),
      copilotPremiumPolicyLink: copilot_premium_policy_link(this_business),
    }, page_data: { selected_link: :business_billing_vnext_budgets_alerts, sidebar: :billing_and_licensing }, title: "Edit monthly budget"
  end

  sig { void }
  def update
    # Preserve the existing budget's UUID to prevent replacement
    updated_params = budget_request_params.dup
    old_budget = fetch_old_budget(customer_id, params[:id])
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

    GitHub.instrument "billing.budget_update", {
      actor: current_user,
      customer_id: this_business.customer_id.to_s,
      business: this_business,
      target_amount: edit_budget_request[:targetAmount],
      target_type: edit_budget_request[:targetType],
      target_id: edit_budget_request[:targetId],
      alert_enabled: edit_budget_request[:alertEnabled],
      exclude_cost_center_usage: edit_budget_request[:excludeCostCenterUsage],
      status: "success"
    }

    render_react_app payload: {}
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
