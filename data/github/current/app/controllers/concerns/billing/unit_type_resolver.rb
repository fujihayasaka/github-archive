# typed: strict
# frozen_string_literal: true

module Billing::UnitTypeResolver
  extend ActiveSupport::Concern

  extend T::Helpers

  include Billing::TokenBasedBilling

  requires_ancestor { ApplicationController }

  sig { params(entity: ::Billing::Types::Account).returns(Integer) }
  def resolve_unit_type(entity)
    ai_units_requested = params[:unit_type].to_i == BillingPlatform::Base::UnitType::AIUnits

    return BillingPlatform::Base::UnitType::AIUnits if ai_units_requested && token_based_billing_enabled?(entity)

    BillingPlatform::Base::UnitType::Requests
  end

  sig { params(entity: ::Billing::Types::Account).returns(T::Boolean) }
  def token_based_billing_enabled?(entity)
    if entity.is_a?(User) && entity.user?
      Copilot::User.new(entity).use_token_based_billing?
    else
      billing_tbb_enabled?(entity)
    end
  end
end
