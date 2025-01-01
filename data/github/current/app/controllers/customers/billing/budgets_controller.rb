# typed: strict
# frozen_string_literal: true

# This controller is not implemented yet.
class Customers::Billing::BudgetsController < Customers::BillingController

  T.unsafe(self).react_bundle_name = "billing-app"

  include ApplicationController::VerifiedFetchDependency
  include Billing::Platform::Api::Utils
  include Businesses::Billing::Concerns::Budgets

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
    render_budgets(this_entity: this_organization, layout: react_layout)
  end

  sig { void }
  def new
    render_react_app payload: {
      slug: this_organization.display_login,
      adminRoles: admin_roles(this_organization),
      current_user_id: T.must(current_user).global_relay_id,
      enabledProducts: enabled_products
    }, page_data: { selected_link: selected_link }, title: "New monthly budget", layout: react_layout, ssr: true
  end

  sig { void }
  def create
    create_budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
      raw_upsert_budget_request: budget_request_params,
      current_user: current_user,
      customer_id: customer_id,
      this_entity: this_organization
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
      customer_id: customer_id,
      org: this_organization,
      target_amount: create_budget_request[:targetAmount],
      target_type: create_budget_request[:targetType],
      target_id: create_budget_request[:targetId],
      alert_enabled: create_budget_request[:alertEnabled],
      status: "success"
    }

    render_react_app payload: {}, ssr: true
  end

  sig { void }
  def edit
    budget_response = billing_platform_client.get_budget_by_uuid(
      customer_id: customer_id,
      uuid: params[:id]
    )

    render_react_app payload: {
      slug: this_organization.display_login,
      budget: budget_response[:budget].to_edit_json,
      adminRoles: admin_roles(this_organization),
      enabledProducts: enabled_products
    }, page_data: { selected_link: selected_link }, title: "Edit monthly budget", layout: react_layout, ssr: true
  end

  sig { void }
  def update
    edit_budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
      raw_upsert_budget_request: budget_request_params,
      current_user: current_user,
      customer_id: customer_id,
      this_entity: this_organization
    )

    response = billing_platform_client.create_or_update_budget(budget: edit_budget_request.to_json)
    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to edit budget" }, status: 500
    end

    GitHub.instrument "billing.budget_update", {
      actor: current_user,
      customer_id: customer_id,
      org: this_organization,
      target_amount: edit_budget_request[:targetAmount],
      target_type: edit_budget_request[:targetType],
      target_id: edit_budget_request[:targetId],
      alert_enabled: edit_budget_request[:alertEnabled],
      status: "success"
    }

    render_react_app payload: {}, ssr: true
  end

  sig { void }
  def destroy
    response = billing_platform_client.delete_budget(customer_id: customer_id, uuid: params[:id])

    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to delete budget" }, status: 500
    end

    GitHub.instrument "billing.budget_delete", {
      actor: current_user,
      customer_id: customer_id,
      org: this_organization,
      uuid: params[:id],
      status: "success"
    }

    render json: {}
  end

  private

  sig { returns(T::Hash[String, T.untyped]) }
  memoize def budget_request_params
    JSON.parse(T.must(request).body.read)
  end

  sig { returns(String) }
  def customer_id
    is_org? ? this_organization.customer.id.to_s : this_user.customer.id.to_s
  end

  sig { returns(Symbol) }
  def selected_link
    :billing_vnext_budgets
  end

end
