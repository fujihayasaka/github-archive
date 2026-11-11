# typed: true
# frozen_string_literal: true

module Site
  module FooterHelper
    include TagAttributeHelper

    FOOTER_COLOR_MODES = %w[light dark].freeze

    # Returns the color mode to pass to the React `marketing-footer` partial. `"auto"` lets the
    # Brand `ThemeProvider` follow the user's system / page-level preference.
    def marketing_footer_color_mode
      @marketing_footer_theme.in?(FOOTER_COLOR_MODES) ? @marketing_footer_theme : "auto"
    end

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
