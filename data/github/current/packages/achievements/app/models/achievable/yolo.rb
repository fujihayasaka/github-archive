# typed: true
# frozen_string_literal: true

class Achievable
  class Yolo < ::Achievable
    define_tier
    unlocking_event model_spec: ::Achievable::UnlockingModelSpec::Exact.new("PullRequest")
    mobile_background_color "#444986"

    def self.display_name
      "YOLO"
    end
  end
end
