# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileAppType < Platform::Enums::Base
      required_capabilities [:mobile_only_schema_mask]
      description "Represents the different mobile applications."

      value "ANDROID", "Event came from Android app", value: "android"
      value "IOS", "Event came from iOS app", value: "ios"
    end
  end
end
