# typed: true
# frozen_string_literal: true

module Issues
  class LabelComponent < ApplicationComponent
    VARIANT_MAPPINGS = {
      big: "IssueLabel--big",
    }.freeze
    VARIANT_OPTIONS = VARIANT_MAPPINGS.keys << nil

    # @param color [String] The background color of the label pill in the HTML color format
    # @param id [String] An optional, explicit ID for the label element. If not provided, a random ID will be generated. Set this when rendering the label inside a <template> element.
    # @param name [String] The name of the label
    # @param description [String] An optional text that describes the label. If present, the label will be rendered with a tooltip.
    # @param kwargs [Hash] Any additional HTML attributes to be added to the label element. Usually contains system arguments: <%= link_to_system_arguments_docs %>
    def initialize(color:, id: nil, name: nil, description: nil, variant: nil, **kwargs)
      @color, @description, @kwargs = color, description, kwargs

      @id = id || "label-#{SecureRandom.hex(3)}"

      # Ensure we don't show a native tooltip
      @kwargs[:title] = nil

      @kwargs[:"data-name"] = name if name.present?
      @kwargs[:style] = style
      @kwargs[:test_selector] = "issue-label-component" unless kwargs.include?(:test_selector)
      @kwargs[:classes] = class_names(
        "IssueLabel hx_IssueLabel",
        VARIANT_MAPPINGS[fetch_or_fallback(VARIANT_OPTIONS, variant)],
        kwargs[:classes]
      )
      unless kwargs.include?(:tag)
        @kwargs[:tag] = if kwargs.include?(:href)
          :a
        else
          :span
        end
      end
    end

    private

    def render_label
      render(Primer::BaseComponent.new(**@kwargs)) { content }
    end

    def style
      [
        "--label-r:#{rgb.red.to_i};",
        "--label-g:#{rgb.green.to_i};",
        "--label-b:#{rgb.blue.to_i};",
        "--label-h:#{hsl.hue.to_i};",
        "--label-s:#{hsl.saturation.to_i};",
        "--label-l:#{hsl.luminosity.to_i};"
      ].join("")
    end

    memoize def rgb
      Color::RGB.from_html(@color)
    end

    memoize def hsl
      rgb.to_hsl
    end

    def render_tooltip?
      is_interactive? && @description.present?
    end

    def is_interactive?
      tag = @kwargs[:tag].to_sym

      return true if tag == :a && @kwargs.include?(:href)
      return true if tag == :input && !@kwargs[:hidden]
      return true if [:button, :summary, :select, :textarea].include?(tag)

      false
    end
  end
end
