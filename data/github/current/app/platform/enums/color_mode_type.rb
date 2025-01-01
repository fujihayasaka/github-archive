# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ColorModeType < Platform::Enums::Base
      description "Indicates the color mode for a user's selected theme"
      feature_flag :issue_app_graphql_integration

      value "AUTO", "Use system settings", value: "auto"
      value "DARK", "Dark theme", value: "dark"
      value "LIGHT", "Light theme", value: "light"
    end
  end
end
