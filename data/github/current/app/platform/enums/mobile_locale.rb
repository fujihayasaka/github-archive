# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileLocale < Platform::Enums::Base
      description "Locales necessary to support to provide server-side localized achievement text to mobile clients."

      required_capabilities [:mobile_only_schema_mask]

      value "EN", "English (US)", value: "en"
    end
  end
end
