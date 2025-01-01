# typed: true
# frozen_string_literal: true

class Achievable
  class PairExtraordinaire < ::Achievable
    define_tier threshold: 1
    define_tier threshold: 10
    define_tier threshold: 25
    define_tier threshold: 100

    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Exact.new("PullRequest")

    mobile_background_color "#18600C"
  end
end
