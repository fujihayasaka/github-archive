# typed: true
# frozen_string_literal: true

class Achievable
  class ProximaPioneer < ::Achievable
    define_tier
    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Issueish.new
    mobile_background_color "#2C2C4E"
  end
end
