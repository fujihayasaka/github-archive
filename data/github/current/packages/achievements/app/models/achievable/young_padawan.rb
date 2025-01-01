# typed: true
# frozen_string_literal: true

class Achievable
  class YoungPadawan < ::Achievable
    define_tier
    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Issueish.new
    mobile_background_color "#EA783C"
  end
end
