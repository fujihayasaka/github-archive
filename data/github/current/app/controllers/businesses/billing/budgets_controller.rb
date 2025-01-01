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
        enabledProducts: enabled_products,
        show_missing_payment_banner: false,
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
      enabledProducts: enabled_products,
      show_missing_payment_banner: false,
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

    GitHub.instrument "billing.budget_create", {
      actor: current_user,
      customer_id: this_business.customer_id.to_s,
      business: this_business,
      target_amount: create_budget_request[:targetAmount],
      target_type: create_budget_request[:targetType],
      target_id: create_budget_request[:targetId],
      alert_enabled: create_budget_request[:alertEnabled],
      status: "success"
    }

    render_react_app payload: {}
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

  sig { void }
  def destroy
    response = billing_platform_client.delete_budget(customer_id: customer_id, uuid: params[:id])

    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to delete budget" }, status: 500
    end

    GitHub.instrument "billing.budget_delete", {
      actor: current_user,
      customer_id: this_business.customer_id.to_s,
      business: this_business,
      uuid: params[:id],
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
