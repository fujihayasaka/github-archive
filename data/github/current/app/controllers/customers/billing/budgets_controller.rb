# typed: strict
# frozen_string_literal: true

# This controller is not implemented yet.
class Customers::Billing::BudgetsController < Customers::BillingController

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
  before_action :return_404_if_not_owner_or_member_billing_manager_of_organization, only: [:new, :edit]
  before_action :verify_payment_method, only: [:create, :update]
  before_action :verify_can_delete_budgets, only: [:destroy]

  sig { void }
  def index
    render_budgets(this_entity: this_entity, layout: react_layout)
  end

  sig { void }
  def new
    render_react_app payload: {
      slug: this_entity.display_login,
      adminRoles: admin_roles(this_entity),
      current_user_id: current_user.global_relay_id,
      enabledProducts: enabled_products(this_entity),
      enabledSkus: enabled_skus(this_entity: this_entity),
      show_missing_payment_banner: missing_payment_method? && !is_invoiced?,
      show_models_banner: this_entity.feature_enabled?(:github_models_billing_ui) && !this_entity.models_billing_enabled?,
      billing_coding_agent_enabled: billing_coding_agent_enabled?(this_entity),
      billing_spark_enabled: billing_spark_enabled?(this_entity),
    }, page_data: { selected_link: selected_link }, title: "New monthly budget", layout: react_layout
  end

  sig { void }
  def create
    create_budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
      raw_upsert_budget_request: budget_request_params,
      current_user: current_user,
      customer_id: customer_id,
      this_entity: this_entity
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
    publish_budget_changed_notification(create_budget_request.pricing_target_id, this_entity, customer_id, reason_type)

    if this_organization
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

      GitHub.dogstats.increment("billing.budget_create", tags: ["pricing_target_id:#{create_budget_request.pricing_target_id}", "account_type:org"])
    else
      GitHub.instrument "billing.budget_create", {
        actor: current_user,
        customer_id: customer_id,
        target_amount: create_budget_request[:targetAmount],
        target_type: create_budget_request[:targetType],
        target_id: create_budget_request[:targetId],
        alert_enabled: create_budget_request[:alertEnabled],
        status: "success"
      }

      GitHub.dogstats.increment("billing.budget_create", tags: ["pricing_target_id:#{create_budget_request.pricing_target_id}", "account_type:user"])
    end

    render_react_app payload: {}
  end

  sig { void }
  def edit
    budget_response = billing_platform_client.get_budget_by_uuid(
      customer_id: customer_id,
      uuid: params[:id]
    )

    if budget_response.is_a?(Billing::Platform::Api::Error)
      error_msg = budget_response.original_error.respond_to?(:msg) ? budget_response.original_error.msg : ""
      return render json: { error: "Unable to load budget (#{error_msg})" }, status: 500
    end

    render_react_app payload: {
      slug: this_entity.display_login,
      budget: budget_response[:budget].to_edit_json,
      adminRoles: admin_roles(this_entity),
      enabledProducts: enabled_products(this_entity),
      enabledSkus: enabled_skus(this_entity: this_entity),
      show_missing_payment_banner: missing_payment_method? && !is_invoiced?,
      current_user_id: current_user.global_relay_id,
    }, page_data: { selected_link: selected_link }, title: "Edit monthly budget", layout: react_layout
  end

  sig { void }
  def update
    edit_budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
      raw_upsert_budget_request: budget_request_params,
      current_user: current_user,
      customer_id: customer_id,
      this_entity: this_entity
    )

    response = billing_platform_client.create_or_update_budget(budget: edit_budget_request.to_json)
    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to edit budget" }, status: 500
    end

    reason_type = reason_type(edit_budget_request)
    publish_budget_changed_notification(edit_budget_request.pricing_target_id, this_entity, customer_id, reason_type)

    GitHub.instrument "billing.budget_update", {
      actor: current_user,
      customer_id: customer_id,
      org: this_entity,
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
    budget_response = billing_platform_client.get_budget_by_uuid(
      customer_id: customer_id,
      uuid: params[:id]
    )

    response = billing_platform_client.delete_budget(customer_id: customer_id, uuid: params[:id])

    if response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to delete budget" }, status: 500
    end

    if !budget_response.is_a?(Billing::Platform::Api::Error)
      reason_type = Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::BUDGET_DELETED)
      budget = budget_response[:budget]
      if budget && budget.pricing_target_id
        publish_budget_changed_notification(budget.pricing_target_id, this_entity, customer_id, reason_type)
      end
    end

    GitHub.instrument "billing.budget_delete", {
      actor: current_user,
      customer_id: customer_id,
      org: this_entity,
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
    is_org? ? this_organization.customer.id.to_s : this_user.customer.id.to_s
  end
  sig { returns(Symbol) }
  def selected_link
    :billing_vnext_budgets
  end

  sig { returns(T::Boolean) }
  def missing_payment_method?
    return false if this_entity.metered_via_azure?

    if is_org?
      !this_organization.has_valid_payment_method?(feature_type: :noncommercial)
    else
      !this_user.has_valid_payment_method?(feature_type: :noncommercial)
    end
  end

  sig { returns(T::Boolean) }
  def is_invoiced?
    is_org? ? this_organization.invoiced? : this_user.invoiced?
  end

  sig { void }
  def verify_payment_method
    render json: { error: "Payment method is missing" }, status: 400 if missing_payment_method? && !is_invoiced?
  end

  sig { void }
  def verify_can_delete_budgets
    render json: { error: "Unable to delete budget: A valid payment method is required." }, status: 400 if missing_payment_method? && !this_entity.invoiced?
  end
end
