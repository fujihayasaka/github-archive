# typed: strict
# frozen_string_literal: true

module Billing::DiscountsDependency
  extend T::Helpers

  include Billing::Platform::Api::Utils
  include BillingSettingsHelper

  requires_ancestor { ApplicationController }

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

        user_owned_org_ids = current_user.owned_organization_ids

        if user_owned_org_ids.any? && enterprise_org_owner_but_not_enterprise_owner?(this_entity)

          net_items_response = billing_platform_client.get_net_usage_line_items(
            usage_entity_id: customer_id,
            billing_period: BillingSettingsHelper::USAGE_PERIOD[:this_month],
            year: year,
            month: month,
            organization_ids: user_owned_org_ids,
          )

          if net_items_response.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "Unable to retrieve organizations' net usage line items", discounts: discounts }, status: 500
          end

          net_usage_items = net_items_response[:netUsageItems]

          return render json: { discounts: discounts }, status: 200 if net_usage_items.empty?

          # Tally all the org level discounts
          enabled_product_names = enabled_products.map { |product| product[:name] }
          total_orgs_discounts = net_usage_items.sum do |item|
            enabled_product_names.include?(item[:product]) ? item[:discountAmount] : 0
          end

          # Instead of sending an array of net usage line items to the UI, we calculate the total orgs discount on the backend
          # and send a single discount state placeholder response for an enterprise org owner.
          discounts = [
            {
              "isFullyApplied": false,
              "currentAmount": total_orgs_discounts,
              "targetAmount": 0.0,
              "percentage": 0.0,
              "uuid": "",
              "targets": [
                {
                    "id": "",
                    "type": "NoDiscountTarget"
                }
              ]
            },
          ]
        else
          discount_states_responses = billing_platform_client.get_all_discount_states(customer_id: customer_id, year: year, month: month)

          if discount_states_responses.is_a?(Billing::Platform::Api::Error)
            return render json: { error: "Unable to retrieve discounts", discounts: discounts }, status: 500
          end

          discounts = discount_states_responses[:discounts]
        end

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

  sig { params(this_entity: ::Billing::Types::Account).returns(T::Boolean) }
  def enterprise_org_owner_but_not_enterprise_owner?(this_entity)
    roles = admin_roles(this_entity)
    roles.include?("enterprise_org_owner") && !roles.include?("owner")
  end
end
