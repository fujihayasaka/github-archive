# typed: true
# frozen_string_literal: true

class Achievable
  class OpenSourcerer < ::Achievable
    define_tier threshold: 2
    define_tier threshold: 8
    define_tier threshold: 16
    define_tier threshold: 64

    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Exact.new("PullRequest")

    mobile_background_color "#4A1D60"
  end
end
