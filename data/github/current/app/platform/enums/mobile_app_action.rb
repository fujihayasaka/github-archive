# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileAppAction < Platform::Enums::Base
      mobile_only true
      description "Represents the different mobile actions."

      value "PRESS", "Event came from a press", value: "press"
      value "SWIPE", "Event came from a swipe", value: "swipe"
      value "LEFT_SWIPE", "Event came from a left swipe RTL", value: "left_swipe"
      value "RIGHT_SWIPE", "Event came from a right swipe LTR", value: "right_swipe"
      value "LONG_PRESS", "Event came from a long press", value: "long_press"
      value "GESTURE", "Event came from a gesture", value: "gesture"
      value "KEY_COMMAND", "Event came from a key command", value: "key_command"
    end
  end
end
