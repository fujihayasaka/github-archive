# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ColorThemeType < Platform::Enums::Base
      description "Indicates the color theme for a user's selected theme"
      feature_flag :issue_app_graphql_integration

      value "DARK", "Dark theme", value: "dark"
      value "DARK_HIGH_CONTRAST", "Dark theme with high contrast", value: "dark_high_contrast"
      value "DARK_DIMMED", "Dark theme with dimming", value: "dark_dimmed"
      value "LIGHT", "Light theme", value: "light"
    end
  end
end
