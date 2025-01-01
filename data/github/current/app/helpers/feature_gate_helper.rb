# typed: strict
# frozen_string_literal: true

module FeatureGateHelper

  include HydroHelper

  sig { params(feature: T.nilable(T.any(String, Symbol)), user: T.nilable(User)).returns(T::Hash[Symbol, T.untyped]) }
  def feature_gate_upsell_click_attrs(feature = nil, user: T.unsafe(self).current_user)
    hydro_click_tracking_attributes("feature_gate_upsell.click",
      feature_name: feature,
      user_id: user&.id,
    )
  end
end
