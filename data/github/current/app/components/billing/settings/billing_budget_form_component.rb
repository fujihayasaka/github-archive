# typed: true
# frozen_string_literal: true

class Billing::Settings::BillingBudgetFormComponent < ApplicationComponent
  def initialize(business:, organizations:, cancel_path:, submit_path:, budget: nil)
    @business = business
    @organizations = organizations
    @cancel_path = cancel_path
    @submit_path = submit_path
    @budget = budget
  end

  private

  def render?
    GitHub.flipper[:ghe_spending_limits].enabled?(@business) && @business.present? && logged_in?
  end

  def services_list
    [{ label: Billing::Budget.product_labels[:shared], value: "shared" }, { label: Billing::Budget.product_labels[:codespaces], value: "codespaces" }]
  end

  def organization_menu_items
    @organizations&.map do |organization|
      GitHub::Menu::RadioComponent.new(
        text: organization.name,
        avatar: GitHub::AvatarComponent.new(actor: organization, size: 16, mr: 2),
        name: organizations_field,
        value: organization.id,
        replace_text: organization.name,
        checked: @budget&.owner == organization
      )
    end
  end

  def organization_radio_disabled?
    @organizations.length == 0
  end

  def organization_radio_classes
    organization_radio_disabled? ? "form-checkbox organization-radio-button-budget-disabled" : "form-checkbox"
  end

  def services_field
    "budget[service]"
  end

  def organizations_field
    "budget[organization_id]"
  end
end
