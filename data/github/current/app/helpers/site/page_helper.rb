# typed: true
# frozen_string_literal: true

module Site
  module PageHelper
    include TagAttributeHelper

    PAGE_COLOR_MODES = %w[light dark].freeze

    def marketing_page_color_mode_attributes
      return "" unless defined?(@marketing_page_theme) && @marketing_page_theme.in?(PAGE_COLOR_MODES)

      attributes =
        case @marketing_page_theme
        when "light"
          { "data-color-mode": "light", "data-light-theme": "light" }
        when "dark"
          { "data-color-mode": "dark", "data-dark-theme": "dark" }
        end

      tag_attributes(attributes)
    end
  end
end
