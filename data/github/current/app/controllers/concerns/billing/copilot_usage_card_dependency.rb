# typed: strict
# frozen_string_literal: true

module Billing::CopilotUsageCardDependency
  include Billing::Platform::Api::Utils
  include Billing::UnitTypeResolver
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { params(this_entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def render_usage_card_data(this_entity:, is_stafftools_route: false)
    respond_to do |format|
      format.json do
        query = Billing::Public::Usage::QueryBuilder.build(this_entity, **usage_filter_params.except(:unit_type))
        unit_type_int = resolve_unit_type(this_entity)

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
          unit_type: unit_type_int,
        }

        begin
          usage_response = billing_platform_client.get_copilot_usage_card_data(**new_query)
        rescue => e
          Failbot.report(e, app: "billing-platform")
          return render json: { error: "Unable to query usage" }, status: 500
        end

        if usage_response.is_a?(Billing::Platform::Api::Error)
          return render json: { error: "An unknown error occurred" }, status: 500
        end

        response_data = if unit_type_int == BillingPlatform::Base::UnitType::AIUnits
          {
            includedCreditsUsed: usage_response[:discount_quantity].to_f.round,
            includedCreditsEntitlement: usage_response[:included_credits_entitlement],
            overageSpend: usage_response[:net_billed_amount].to_f.round(2),
            netQuantity: usage_response[:net_quantity],
          }
        else
          {
            netBilledAmount: usage_response[:net_billed_amount],
            netQuantity: usage_response[:net_quantity],
            discountQuantity: usage_response[:discount_quantity],
            userPremiumRequestEntitlement: get_user_premium_request_entitlement_amount(this_entity),
            filteredUserPremiumRequestEntitlement: filtered_user_premium_request_entitlement(this_entity: this_entity, user_id: query[:user_id])
          }
        end

        render json: response_data, status: 200
      end
    end
  end

  protected

  # Get the included premium request count for a user. We ignore organizations and enterprises since their counts are
  # pooled across all their users and we do not show the pooled count in the UI.
  sig { params(this_entity: ::Billing::Types::Account).returns(Integer) }
  def get_user_premium_request_entitlement_amount(this_entity)
    if this_entity.is_a?(User) && !this_entity.is_a?(Organization)
      copilot_user = Copilot::Public::User.for(this_entity)
      copilot_user.quota_snapshots.dig("premium_interactions", :entitlement) || 0
    else
      0
    end
  end

  # Business and org accounts can filter/search for a specific user. In this case, we want to show the included
  # premium request entitlement for the selected user. Returns 0 for individual users or when no user filter is applied.
  sig { params(this_entity: ::Billing::Types::Account, user_id: T.nilable(Integer)).returns(Integer) }
  def filtered_user_premium_request_entitlement(this_entity:, user_id:)
    return 0 unless (this_entity.is_a?(Organization) || this_entity.is_a?(Business)) && user_id.present?

    user = User.find_by(id: user_id)
    return 0 unless user && !user.is_a?(Organization)

    copilot_user = Copilot::Public::User.for(user)
    copilot_user.quota_snapshots.dig("premium_interactions", :entitlement) || 0
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
