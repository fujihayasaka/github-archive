# typed: true
# frozen_string_literal: true

class Achievable
  class HeartOnYourSleeve < ::Achievable
    define_tier threshold: 2
    define_tier threshold: 16
    define_tier threshold: 128
    define_tier threshold: 1024

    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Reactable.new

    mobile_background_color "#7D3D5F"
  end
end
