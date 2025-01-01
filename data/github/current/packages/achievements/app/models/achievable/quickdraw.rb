# typed: true
# frozen_string_literal: true

class Achievable
  class Quickdraw < ::Achievable
    define_tier threshold: 5.minutes
    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Issueish.new
    mobile_background_color "#8B410C"

    def self.uses_skin_tone?(tier:)
      true
    end
  end
end
