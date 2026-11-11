# typed: true
# frozen_string_literal: true

class Achievable
  class GalaxyBrain < ::Achievable
    define_tier threshold: 2
    define_tier threshold: 8
    define_tier threshold: 16
    define_tier threshold: 32

    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Exact.new("DiscussionComment")

    mobile_background_color "#3E227D"
  end
end
