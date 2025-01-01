# typed: true
# frozen_string_literal: true

class Achievable
  class Heartbreaker < ::Achievable
    define_tier threshold: 100
    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Issueish.new
    mobile_background_color "#540905"
  end
end
