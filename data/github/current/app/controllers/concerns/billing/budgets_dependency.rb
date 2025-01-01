# typed: strict
# frozen_string_literal: true

module Billing::BudgetsDependency
  extend T::Helpers

  include Billing::Platform::Api::Utils
  include BillingSettingsHelper
  include Billing::CopilotIapSubscription

  requires_ancestor { ApplicationController }

  abstract!

  sig { abstract.params(entity: ::Billing::Types::Account).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def enabled_products(entity); end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T.nilable(T::Boolean), layout: T.nilable(String)).void }
  def render_budgets(this_entity:, is_stafftools_route: false, layout: nil)
    selected_link = this_entity.is_a?(Business) ? :business_billing_vnext_budgets_alerts : :billing_vnext_budgets

    respond_to do |format|
      format.json do
        budgets = []
        budgets_response = billing_platform_client.get_all_budgets(customer_id: this_entity.customer&.id.to_s)

        if budgets_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "Unable to query budgets" }, status: 500
        end

        budgets = budgets_response[:budgets]
        # only filter the budgets for org and enterprise customers
        if !is_stafftools_route && !this_entity.is_a?(User)
          budgets = filter_budget_by_role(budgets: budgets_response[:budgets], current_user: current_user, entity: this_entity)
        end

        payload = {
          copilotIapSubscription: this_entity.is_a?(User) ? copilot_iap_subscription?(this_entity) : false,
          adminRoles: admin_roles(this_entity),
          budgets: budgets,
          enabledProducts: enabled_products(this_entity),
          enabledSkus: enabled_skus(this_entity: this_entity),
          customer: customer_payload(this_entity),
          helpUrl: GitHub.help_url,
        }

        render json: { payload: payload }, status: 200
      end

      format.html do
        payload = {
          copilotIapSubscription: this_entity.is_a?(User) ? copilot_iap_subscription?(this_entity) : false,
          adminRoles: admin_roles(this_entity),
          enabledProducts: enabled_products(this_entity),
          enabledSkus: enabled_skus(this_entity: this_entity),
          customer: customer_payload(this_entity),
          helpUrl: GitHub.help_url,
          layout: layout
        }
        kwargs = {
          payload: payload,
          page_data: { selected_link: selected_link, sidebar: :billing_and_licensing },
          title: "Budgets",
        }

        if layout.present? && !is_stafftools_route
          kwargs.merge!(layout: layout)
        end

        render_react_app(**kwargs)
      end
    end
  rescue => e # rubocop:todo Lint/GenericRescue
    Failbot.report(e)
    render json: { error: "Unable to query budgets" }, status: 500
  end

  sig { params(this_entity: ::Billing::Types::Account).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def enabled_skus(this_entity:)
    response = billing_platform_client.get_all_pricing
    current_time = Time.now.to_i

    if response.is_a?(::Billing::Platform::Api::Error)
      []
    else
      skus = response[:pricings]
      if this_entity.is_a?(Business) && this_entity.seats_plan_type == "basic" || this_entity.is_a?(User) && !this_entity.is_a?(Organization)
        skus.reject! { |sku| sku[:sku] == "copilot_for_business" }
      end

      if this_entity.is_a?(Business) && this_entity.seats_plan_type == "basic" || this_entity.is_a?(User)
        skus.reject! { |sku| sku[:sku] == "copilot_enterprise" }
      end

      if this_entity.is_a?(Business) && this_entity.seats_plan_type != "basic" || this_entity.is_a?(Organization) || this_entity.is_a?(User)
        skus.reject! { |sku| sku[:sku] == "copilot_standalone" }
      end

      if !this_entity.advanced_security_products_bundled?
        skus.reject! { |sku| sku[:sku] == "ghas_licenses" }
      else
        skus.reject! { |sku| sku[:sku] == "ghas_secret_protection_licenses" || sku[:sku] == "ghas_code_security_licenses" }
      end

      skus.reject! { |sku| !sku[:effectiveAt].nil? && sku[:effectiveAt] > current_time }
      skus
    end
  end

  private

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end
end
