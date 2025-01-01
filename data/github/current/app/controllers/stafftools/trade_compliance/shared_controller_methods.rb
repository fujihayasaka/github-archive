# typed: strict
# frozen_string_literal: true

module Stafftools::TradeCompliance::SharedControllerMethods
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { StafftoolsController }

  sig { overridable.returns(Billing::Types::Account) }
  def target
    this_user
  end

  sig { params(feature_type: Symbol, return_to: T.nilable(String), fallback_location: T.nilable(String)).void }
  def ensure_target_not_restricted(feature_type: :default, return_to: nil, fallback_location: nil)
    return unless target.has_commercial_interaction_restriction?(feature_type: feature_type)

    flash[:error] = "This action cannot be performed on a account that is trade restricted."

    if return_to.present?
      redirect_to return_to
    else
      redirect_back fallback_location: fallback_location
    end
  end
end
