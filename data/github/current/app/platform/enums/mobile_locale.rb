# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileLocale < Platform::Enums::Base
      description "Locales necessary to support to provide server-side localized achievement text to mobile clients."

      mobile_only true

      value "EN", "English (US)", value: "en"
    end
  end
end
