# typed: strict
# frozen_string_literal: true

module Businesses::Billing::Concerns::Budgets
  extend T::Helpers

  include Billing::Platform::Api::Utils
  include BillingSettingsHelper

  requires_ancestor { ApplicationController }
  requires_ancestor { ReactHelper }

  abstract!

  sig { abstract.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def enabled_products; end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T.nilable(T::Boolean), layout: T.nilable(String)).void }
  def render_budgets(this_entity:, is_stafftools_route: false, layout: nil)
    budgets = []
    selected_link =  this_entity.is_a?(Business) ? :business_billing_vnext_budgets_alerts : :billing_vnext_budgets

    budgets_response = billing_platform_client.get_all_budgets(customer_id: this_entity.customer&.id.to_s)

    if budgets_response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to query budgets" }, status: 500
    end

    budgets = budgets_response[:budgets]
    if !is_stafftools_route
      budgets = filter_budget_by_role(budgets: budgets_response[:budgets], current_user: current_user, entity: this_entity)
    end

    payload = {
      adminRoles: admin_roles(this_entity),
      budgets: budgets,
      enabledProducts: enabled_products,
      customer: customer_payload(this_entity),
      helpUrl: GitHub.help_url,
      layout: layout
    }
    kwargs = {
      payload: payload,
      page_data: { selected_link: selected_link },
      title: "Budgets",
      ssr: true
    }

    if layout.present? && !is_stafftools_route
      kwargs.merge!(layout: layout)
    end

    render_react_app(**kwargs)
  rescue => e # rubocop:todo Lint/GenericRescue
    Failbot.report(e)
    render json: { error: "Unable to query budgets" }, status: 500
  end

  private

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end
end
