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


  before_action :ensure_vnext_enabled
  allow_verified_fetch only: [:index, :create, :update]

  sig { returns(String) }
  def self.react_bundle_name
    "billing-app"
  end

  sig { void }
  def index
    render_budgets(this_entity: this_business, is_stafftools_route: true)
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
      enabledProducts: enabled_products
    }, page_data: { selected_link: :business_billing_vnext_budgets_alerts, sidebar: :billing_and_licensing }, title: "Edit monthly budget"
  end

  sig { void }
  def update
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

    GitHub.instrument "billing.budget_update", {
      actor: current_user,
      customer_id: this_business.customer_id.to_s,
      business: this_business,
      target_amount: edit_budget_request[:targetAmount],
      target_type: edit_budget_request[:targetType],
      target_id: edit_budget_request[:targetId],
      alert_enabled: edit_budget_request[:alertEnabled],
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
