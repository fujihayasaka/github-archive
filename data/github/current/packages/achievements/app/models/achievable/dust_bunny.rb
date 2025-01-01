# typed: true
# frozen_string_literal: true

class Achievable
  class DustBunny < ::Achievable
    define_tier
    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Commit.new
    mobile_background_color "#303A45"
  end
end
