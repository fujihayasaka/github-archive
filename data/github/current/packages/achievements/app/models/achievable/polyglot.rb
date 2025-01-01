# typed: true
# frozen_string_literal: true

class Achievable
  class Polyglot < ::Achievable
    define_tier threshold: 2
    define_tier threshold: 8
    define_tier threshold: 16

    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Commit.new

    mobile_background_color "#274B80"
  end
end
