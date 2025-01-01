# typed: true
# frozen_string_literal: true

module Site
  class BadgeComponent < ApplicationComponent
    VERSION = "1.0.1"

    def initialize(text: "Beta", classes: nil, size: :medium)
      @text = text
      @classes = classes
      @size = size
    end

    def badge_classes
      class_names(
        "gradient-border-mktg d-inline-block z-1 position-relative",
        @classes,
        {
          "px-2 lh-condensed": @size == :small,
          "py-1 px-3 mb-2": @size == :medium || @size == :large,
          "py-1 py-lg-2 px-3 px-lg-4 lh-condensed mb-2 mb-lg-4": @size == :xlarge,
          "f6-mktg": @size == :small,
          "f5-mktg": @size == :medium,
          "f4-mktg": @size == :large,
          "f3-mktg": @size == :xlarge
        }
      )
    end

    def text_classes
      class_names(
        "text-gradient-mktg",
        {
          "text-semibold": @size != :xlarge,
          "text-medium py-1": @size == :xlarge
        }
      )
    end
  end
end
