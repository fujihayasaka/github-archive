# typed: strict
# frozen_string_literal: true

class BusinessUserAccounts::SidebarCostCenterComponent < ApplicationComponent
  include GitHub::Memoizer

  sig { returns(Business) }
  attr_reader :business
  sig { returns(T.nilable(User)) }
  attr_reader :user

  sig { params(business: Business, user: T.nilable(User)).void }
  def initialize(business:, user:)
    @business = business
    @user = user
  end

  sig { returns(T::Boolean) }
  def render?
    return false if business_user_account.nil?
    business.customer&.billing_platform_enabled_product&.ghec? || business.customer&.billing_platform_enabled_product&.copilot? || ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false) || false
  end

  sig { returns(T.nilable(String)) }
  def cost_center
    return nil if business.customer_id.nil?
    return nil if user.nil?

    find_cost_center_response = billing_platform_client.find_cost_center_for(entity_detail: { customerId: business.customer_id.to_s, actorId: user&.id })
    return "Unavailable" if find_cost_center_response.is_a?(Billing::Platform::Api::Error)
    uuid = find_cost_center_response.dig(:costCenterKey, :uuid)
    return nil if uuid.nil?
    cost_center_response = billing_platform_client.get_cost_center(cost_center_key: { customerId: business.customer_id.to_s, uuid: uuid })
    return "Unavailable" if cost_center_response.is_a?(Billing::Platform::Api::Error)
    cost_center_response.dig(:costCenter, :name)
  end

  sig { returns(T.nilable(BusinessUserAccount)) }
  memoize def business_user_account
    return nil if user.nil?
    business.business_user_account_for(user)
  end

  sig { returns(Billing::Platform::Api::Client) }
  memoize def billing_platform_client
    Billing::Platform::Api::Client.new(timeout: 1)
  end
end
