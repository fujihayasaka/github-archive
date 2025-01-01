# typed: true
# frozen_string_literal: true

class Achievable
  class Starstruck < ::Achievable
    define_tier threshold: 16
    define_tier threshold: 128
    define_tier threshold: 512
    define_tier threshold: 4096

    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Exact.new("Repository")

    mobile_background_color "#854D00"

    def self.uses_skin_tone?(tier:)
      tier.zero?
    end
  end
end
