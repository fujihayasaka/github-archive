# typed: strict
# frozen_string_literal: true

module Billing::CopilotUsageCardDependency
  include Billing::Platform::Api::Utils
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_usage_card_data(this_entity:, is_stafftools_route: false)
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params)

        new_query = {
          customer_id: query[:usage_entity_id],
          year: query[:year],
          month: query[:month],
          billing_period: query[:billing_period],
          org_id: query[:org_id],
          user_id: query[:user_id],
          model: query[:model],
          cost_center_id: query[:cost_center_id],
          organization_admin_ids: filtered_orgs(is_stafftools_route: is_stafftools_route, this_entity: this_entity),
        }

        begin
          usage_response = billing_platform_client.get_copilot_usage_card_data(**new_query)
        rescue => e # rubocop:todo Lint/RescueException
          Failbot.report(e, app: "billing-platform")
          return render json: { error: "Unable to query usage" }, status: 500
        end

        if usage_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occurred" }, status: 500
        end

        render json: {
          netBilledAmount: usage_response[:net_billed_amount],
          netQuantity: usage_response[:net_quantity],
          discountQuantity: usage_response[:discount_quantity],
          userPremiumRequestEntitlement: get_user_premium_request_entitlement_amount(this_entity),
        }, status: 200
      end
    end
  end

  protected

  # Get the included premium request count for a user. We ignore organizations and enterprises since their counts are
  # pooled across all their users and we do not show the pooled count in the UI.
  sig { params(this_entity: ::Billing::Types::Account).returns(Integer) }
  def get_user_premium_request_entitlement_amount(this_entity)
    if this_entity.is_a?(User) && !this_entity.is_a?(Organization)
      copilot_user = Copilot::Public::User.new(this_entity)
      copilot_user.quota_snapshots.dig("premium_interactions", :entitlement) || 0
    else
      0
    end
  end

  sig { params(is_stafftools_route: T::Boolean, this_entity: ::Billing::Types::Account).returns(T.nilable(T::Array[String])) }
  def filtered_orgs(is_stafftools_route:, this_entity:)
    if is_stafftools_route
      # Don't filter out any data for stafftools routes
      return nil
    end
    # Only business requests will need to filter data by a specific org
    if should_filter_usage_for_business?(this_entity, current_user)
      if this_entity.is_a?(Business)
        get_org_ids_for_org_admin(this_entity, current_user)
      else
        nil
      end
    end
  end

  sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
  def usage_filter_params; end

  sig { abstract.returns(Billing::Platform::Api::Client) }
  def billing_platform_client; end
end
