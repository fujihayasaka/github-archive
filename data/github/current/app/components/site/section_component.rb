# typed: true
# frozen_string_literal: true

module Site
  class SectionComponent < ApplicationComponent
    include SiteHelper

    def initialize(theme: nil, size: :xl, container: true, padding: true, classes: nil, overflow: false, **options)
      @theme = theme
      @container = container
      @padding = padding
      @classes = classes
      @overflow = overflow
      @options = options
      @size = size
    end

    def wrapper_classes
      class_names(
        @classes,
        {
          "overflow-hidden": @overflow == false,
          "tmp-px-3": @container == true && @size == :xl,
          "tmp-px-3 tmp-px-md-4": @container == true && @size == :xxl,
          "tmp-pb-8 tmp-pt-5": @padding == true
        }
      )
    end

    def container_classes
      class_names(
        {
          "container-xl": @size == :xl,
          "container-xxl": @size == :xxl
        }
      )
    end

    def data_attributes
      case @theme
      when :light
        mktg_color_theme_data(mode: "light")
      when :dark
        mktg_color_theme_data(mode: "dark")
      end
    end
  end
end
