# typed: true
# frozen_string_literal: true

module Site
  module FooterHelper
    include TagAttributeHelper

    FOOTER_COLOR_MODES = %w[light dark].freeze

    def marketing_footer_color_mode_attributes
      return "" unless @marketing_footer_theme.in?(FOOTER_COLOR_MODES)

      attributes =
        case @marketing_footer_theme
        when "light"
          { "data-color-mode": "light", "data-light-theme": "light" }
        when "dark"
          { "data-color-mode": "dark", "data-dark-theme": "dark" }
        end

      tag_attributes(attributes)
    end
  end
end
