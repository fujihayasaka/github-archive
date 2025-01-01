# typed: true
# frozen_string_literal: true

module Site
  class AvatarComponent < ApplicationComponent
    include AvatarHelper

    SIZE_DEFAULT = 64
    ROUNDED_DEFAULT = :circle
    ROUNDED = [ROUNDED_DEFAULT, 0, 1, 2, 3].freeze

    def initialize(
        handle:,
        size: SIZE_DEFAULT,
        rounded: ROUNDED_DEFAULT,
        classes: nil,
        style: nil,
        alt: nil,
        aria_hidden: true,
        lazy: true,
        decoding: nil,
        **options
      )

      @handle = handle
      @alt = alt || @handle
      @size = size
      @extension = File.exist?("public/images/modules/site/avatars/#{@handle}.jpg") ? "jpg" : "png"
      @rounded = fetch_or_fallback(ROUNDED, rounded, ROUNDED_DEFAULT)
      @classes = classes
      @style = style || "width: #{@size}px"
      @aria_hidden = aria_hidden
      @loading = "lazy" if lazy == true
      @decoding = decoding
      @decoding = "async" if lazy == true && decoding.nil?
      @options = options
    end

    def classes
      class_names(
        "avatar height-auto",
        @classes,
        {
          "circle" => @rounded == :circle,
          "rounded-#{@rounded}" => @rounded.is_a?(Integer),
        }
      )
    end
  end
end
