# typed: true
# frozen_string_literal: true

class Achievable
  class PullShark < ::Achievable
    define_tier threshold: 2
    define_tier threshold: 16
    define_tier threshold: 128
    define_tier threshold: 1024

    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Exact.new("PullRequest")

    mobile_background_color "#002B61"
  end
end
