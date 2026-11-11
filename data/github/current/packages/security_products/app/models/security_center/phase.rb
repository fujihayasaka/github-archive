# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class Phase

    VALID_PHASES = T.let([:alpha, :private_beta, :beta, :ga].freeze, T::Array[Symbol])

    sig { params(feature: Symbol).returns(Symbol) }
    def self.for_feature(feature)
      # If there's still a feature flag check in GHES, and we make it this far,
      # we can safely assume we should tag the feature as public beta.
      return :beta if GitHub.enterprise?

      fully_enabled = FeatureFlag.vexi.fully_enabled_or_raise?(feature) || FeatureFlag.vexi.percentage_of_actors_value_or_raise(feature) == 100.0 # rubocop: disable GitHub/FeatureManagement/NoVexiNonStandardUsage

      # We don't consider assigning specific actors or groups (like staff-shipping) as "rolling out" to customers
      rolling_out =
        FeatureFlag.vexi.percentage_of_actors_value_or_raise(feature) > 0 ||  # rubocop: disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        FeatureFlag.vexi.percentage_of_calls_value_or_raise(feature) > 0  # rubocop: disable GitHub/FeatureManagement/NoVexiNonStandardUsage

      private_beta_feature_flag = "#{feature}_private_beta"
      enabled_for_private_beta = FeatureFlag.vexi.fully_enabled_or_raise?(private_beta_feature_flag) || FeatureFlag.vexi.percentage_of_actors_value_or_raise(private_beta_feature_flag) == 100.0 # rubocop: disable GitHub/FeatureManagement/NoVexiNonStandardUsage

      if !enabled_for_private_beta && !(rolling_out || fully_enabled)
        :alpha
      elsif enabled_for_private_beta && !(rolling_out || fully_enabled)
        :private_beta
      elsif enabled_for_private_beta && (rolling_out || fully_enabled)
        :beta
      else
        :ga
      end
    end
  end
end
