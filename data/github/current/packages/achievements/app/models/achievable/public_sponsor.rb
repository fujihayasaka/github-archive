# typed: true
# frozen_string_literal: true

class Achievable
  class PublicSponsor < ::Achievable
    define_tier
    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Exact.new("Sponsorship")
    mobile_background_color "#893A69"

    def self.enabled?(_)
      true
    end

    def self.has_rounded_badge_variant?
      true
    end
  end
end
