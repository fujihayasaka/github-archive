# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AppStore < Platform::Enums::Base
      description "The supported app stores currently supported for in-app purchases."

      mobile_only true

      value "APPLE", "Apple App Store", value: "apple"

      value "GOOGLE", "Google Play Store", value: "google"
    end
  end
end
