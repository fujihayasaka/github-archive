# typed: true
# frozen_string_literal: true

class Businesses::BillingBudgetsController < Businesses::BusinessController

  before_action :ensure_billing_enabled
  before_action :business_access_required
  before_action :ensure_budgets_enabled
  before_action :ensure_configured_azure_id

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    only: [:new]

  def new
    render "businesses/billing_budgets/new"
  end

  def create
    budget_owner = if budget_form_params[:scope] == "enterprise"
      this_business
    elsif budget_form_params[:scope] == "organization"
      find_organization_by_id(budget_form_params[:organization_id])
    end

    if budget_owner.nil?
      flash[:budgets_error] = "Failed to save the budget there must be a budget owner"
      return render "businesses/billing_budgets/new"
    end

    if no_services_selected
      flash[:budgets_error] = "Please select a service"
      return render "businesses/billing_budgets/new"
    end

    # iterate through each service in the params, make sure its checked, and create a new budget for it
    budget_form_params[:services].each do |budget_group, value|
      if value == "1" && Billing::Budget.valid_budget_group?(budget_group)
        budget = Billing::Budget.new(
          budget_name: budget_form_params[:budget_name],
          owner: budget_owner,
          enforce_spending_limit: enforce_spending_limit,
          spending_limit_in_subunits: spending_limit_in_subunits,
          product: budget_group,
          notify_spending: notify_spending
        )

        if budget.invalid?(Billing::Budget.ghe_budgets_validation_scope)
          flash[:budgets_error] = budget.errors.full_messages.to_sentence
          return render "businesses/billing_budgets/new"
        end

        if !budget.save
          flash[:budgets_error] = "Failed to save the budget"
          return render "businesses/billing_budgets/new"
        end
      end
    end

    flash[:budgets_notice] = "Successfully created a budget"
    redirect_to settings_billing_tab_enterprise_path(tab: :budgets)
  end

  def edit
    budget = Billing::Budget.find(budget_id_param)
    render "businesses/billing_budgets/edit",
      locals: { budget: budget }
  end

  def update
    budget = Billing::Budget.find(budget_id_param)

    if budget.nil?
      flash[:budgets_error] = "Can't find the selected budget"
      return redirect_to settings_billing_tab_enterprise_path(tab: :budgets)
    end

    budget_owner = if budget_form_params[:scope] == "enterprise"
      this_business
    elsif budget_form_params[:scope] == "organization"
      find_organization_by_id(budget_form_params[:organization_id])
    end

    budget.assign_attributes(
      budget_name: budget_form_params[:budget_name],
      owner: budget_owner,
      enforce_spending_limit: enforce_spending_limit,
      spending_limit_in_subunits: spending_limit_in_subunits,
      notify_spending: notify_spending
    )

    if budget.invalid?(Billing::Budget.ghe_budgets_validation_scope)
      flash[:budgets_error] = budget.errors.full_messages.to_sentence
      return redirect_to edit_billing_settings_billing_budget_path(id: budget.id)
    end

    if budget.save
      spending_limit = budget.enforce_spending_limit ? Billing::Money.new(budget.spending_limit_in_subunits).format : "an unlimited"
      flash[:budgets_notice] = "Updated #{budget.budget_name} budget with #{spending_limit} spending limit."
    else
      flash[:budgets_error] = "Can't update the selected budget"
      return redirect_to edit_billing_settings_billing_budget_path(id: budget.id)
    end

    redirect_to settings_billing_tab_enterprise_path(tab: :budgets)
  end

  def destroy
    budget = Billing::Budget.find_by(id: budget_id_param)

    if budget&.destroy
      flash[:budgets_notice] = "Budget successfully deleted"
    else
      flash[:budgets_error] = "Can't delete the selected budget"
    end

    redirect_to settings_billing_tab_enterprise_path(tab: :budgets)
  end

  private

  def no_services_selected
    budget_form_params[:services].values.map(&:to_i).reduce(:+) == 0
  end

  def budget_form_params
    services_allowed = [:shared, :codespaces]
    params.require(:budget).permit(:budget_name, :scope, :organization_id, :email_notification, spending_limit: [:type, :value], services: services_allowed)
  end

  def find_organization_by_id(organization_id)
    this_business.organizations.find { |organization| organization.id == organization_id.to_i }
  end

  def ensure_budgets_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:ghe_spending_limits, this_business, default: false)
  end

  def ensure_configured_azure_id
    render_404 if this_business.billed_through_azure_subscription? && !this_business.linked_azure_subscription?
  end

  def spending_limit_in_subunits
    budget_form_params[:spending_limit][:type] == "limit" ? (budget_form_params[:spending_limit][:value].to_d * 100).to_i : 0
  end

  def enforce_spending_limit
    budget_form_params[:spending_limit][:type] == "limit"
  end

  def notify_spending
    budget_form_params[:email_notification]
  end

  def budget_id_param
    params.require(:id)
  end
end
