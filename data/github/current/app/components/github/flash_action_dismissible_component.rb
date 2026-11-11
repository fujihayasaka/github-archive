# typed: true
# frozen_string_literal: true

module GitHub
  class FlashActionDismissibleComponent < ApplicationComponent

    attr_reader :level, :dismissible_path, :dismissible_method, :is_dismissible, :test_selector, :text_align, :display_icon

    renders_one :action, ->(path: "/") { Primer::Beta::Link.new(href: path, classes: "btn btn-sm") }
    renders_one :title, ->(font_size: 5, font_weight: :bold, **kwargs) {
      T.bind(self, GitHub::FlashActionDismissibleComponent)

      classes = kwargs[:classes] || ""
      kwargs = { classes: classes, font_weight: font_weight, font_size: font_size }

      # need to offset the spacing caused by the dismissible button
      # 56px comes from the size of the "x" + padding-left + margin-left of the dismissible
      kwargs[:style] = "margin-left: 56px;" if is_dismissible && classes.include?("text-center")

      Primer::Beta::Text.new(**kwargs)
    }
    renders_one :text, ->(font_size: 5, style: nil, **kwargs) {
      Primer::Beta::Text.new(classes: kwargs[:classes], style: style, font_size: font_size)
    }

    def initialize(level:, dismissible_path: nil, dismissible_method: "delete", is_dismissible: true, test_selector: nil, text_align: :left, display_icon: true, **system_arguments)
      @text_align = text_align
      @display_icon = display_icon
      @level = level
      @dismissible_path = dismissible_path
      @dismissible_method = dismissible_method
      @is_dismissible = is_dismissible
      @test_selector = test_selector
      @system_arguments = system_arguments
    end

    sig { returns(T.nilable(Symbol)) }
    def icon
      return nil if !@display_icon
      case @level
      when :danger
        :stop
      when :warning
        :alert
      when :default
        :info
      when :success
        :'check-circle'
      end
    end

    class Text < ViewComponent::Base
      attr_reader :classes, :style

      def initialize(classes: "f5", style: nil)
        @classes = classes
        @style = style
      end
    end
  end
end
