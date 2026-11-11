# typed: strict
# frozen_string_literal: true

module Billing::Invoices
  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { abstract.returns(String) }
  def entity_slug; end

  sig { params(this_entity: ::Billing::Types::Account).void }
  def render_invoices(this_entity:)
    respond_to do |format|
      format.json do
        invoices_response = billing_platform_client.get_invoices(customer_id: params[:customer_id])
        if invoices_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: invoices_response.message, invoices: [] }, status: 500
        end

        render json: { invoices: invoices_response[:invoices] }, status: 200
      end

      format.html do
        selected_link = this_entity.is_a?(Business) ? :business_billing_settings : :invoices

        render_invoices_react_app(payload: { customerSelections: usage_customer_selections(this_entity) }, entity_slug: entity_slug, selected_link: selected_link)
      end
    end
  end

  private

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end

  sig { params(payload: T::Hash[Symbol, T.untyped], entity_slug: String, selected_link: Symbol).void }
  def render_invoices_react_app(payload:, entity_slug:, selected_link:)
    payload = {
      slug: entity_slug,
    }.merge!(payload)

    render_react_app(
      payload: payload,
      page_data: { selected_link: :selected_link },
      title: "#{entity_slug} | Invoices",
    )
  end

  sig do
    params(entity: ::Billing::Types::Account)
      .returns(T::Array[{ id: String, displayText: String }])
  end
  def usage_customer_selections(entity)
    customer = T.must(entity.customer)
    response = Billing::Platform::Api::Client.new.get_all_cost_centers(customer_id: customer.id.to_s, use_cache: true)
    selections = [{ id: customer.id.to_s, displayText: "None" }]

    if !response.is_a?(Billing::Platform::Api::Error) && entity.is_a?(Business)
      cost_centers = response[:costCenters].map { |cc| { id: cc[:costCenterKey][:uuid], displayText: cc[:name] } }
      selections = cost_centers + selections
    end

    selections
  end
end
