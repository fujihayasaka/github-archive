# typed: strict
# frozen_string_literal: true

module Businesses::Billing::Concerns::Discounts
  extend T::Helpers

  include Billing::Platform::Api::Utils
  include BillingSettingsHelper

  requires_ancestor { ApplicationController }
  requires_ancestor { ReactHelper }

  abstract!

  sig { abstract.returns(String) }
  def customer_id; end

  sig { abstract.returns(T::Array[T.untyped]) }
  def enabled_products; end

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_discounts_index(this_entity:, is_stafftools_route: false)
    respond_to do |format|
      format.json do
        discounts = []

        year = params.has_key?(:year) ? params[:year].to_i : Time.now.utc.year
        month = params.has_key?(:month) ? params[:month].to_i : Time.now.utc.month

        discount_states_responses = billing_platform_client.get_all_discount_states(customer_id: customer_id, year: year, month: month)

        if discount_states_responses.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "Unable to retrieve discounts", discounts: [] }, status: 500
        end

        discounts = discount_states_responses[:discounts].map { |discount| discount.to_hash }
        return render json: { discounts: discounts }, status: 200
      end
      format.html do
        if !is_stafftools_route
          head :no_content
        else
          render_react_app(
            payload: {
              customer: customer_payload(this_entity),
              enabledProducts: enabled_products,
            },
            ssr: true,
          )
        end
      end
    end
  end

  private

  sig { returns(Billing::Platform::Api::Client) }
  def billing_platform_client
    Billing::Platform::Api::Client.new
  end
end
