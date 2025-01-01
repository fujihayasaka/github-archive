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

      flipper_feature = FlipperFeature.find_by(name: feature)
      fully_enabled = flipper_feature&.fully_enabled?

      # We don't consider assigning specific actors or groups (like staff-shipping) as "rolling out" to customers
      rolling_out =
        (flipper_feature&.percentage_of_actors_value || 0) > 0 ||
        (flipper_feature&.percentage_of_time_value || 0) > 0

      enabled_for_private_beta = FlipperFeature.find_by(name: "#{feature}_private_beta")&.fully_enabled?

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
