# typed: strict
# frozen_string_literal: true

module Businesses::Billing::Concerns::Budgets
  extend T::Sig
  extend T::Helpers

  include Billing::Platform::Api::Utils
  include BillingSettingsHelper

  requires_ancestor { ApplicationController }
  requires_ancestor { ReactHelper }

  abstract!

  sig { abstract.returns(Business) }
  def this_business; end

  sig { abstract.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def enabled_products; end

  sig { params(this_entity: ::Billing::Types::Account, layout: T.nilable(String)).void }
  def render_budgets(this_entity:, layout: nil)
    budgets = []
    selected_link = :billing_vnext_budgets
    if this_entity.is_a?(Business)
      query = Billing::Public::Budgets::QueryBuilder.index(this_entity, **budgets_filter_params)
      budgets_response = Billing::Platform::Api::Client.new.get_all_budgets(customer_id: query[:customer_id])
      selected_link = :business_billing_vnext_budgets_alerts
    else
      budgets_response = Billing::Platform::Api::Client.new.get_all_budgets(customer_id: this_entity.customer&.id.to_s)
    end

    if budgets_response.is_a?(Billing::Platform::Api::Error)
      return render json: { error: "Unable to query budgets" }, status: 500
    end

    budgets = filter_budget_by_role(budgets: budgets_response[:budgets], current_user: current_user, entity: this_entity)

    payload = {
      adminRoles: admin_roles(this_entity),
      budgets: budgets,
      enabledProducts: enabled_products,
      customer: customer_payload(this_entity),
      helpUrl: GitHub.help_url
    }
    kwargs = {
      payload: payload,
      page_data: { selected_link: selected_link },
      title: "Budgets",
      ssr: true
    }
    kwargs.merge!(layout: layout) if layout.present?

    render_react_app(**kwargs)
  rescue => e # rubocop:todo Lint/GenericRescue
    Failbot.report(e)
    render json: { error: "Unable to query budgets" }, status: 500
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def budgets_filter_params
    params.except(:slug).permit(:customer_id).to_h.symbolize_keys
  end
end
