# typed: true
# frozen_string_literal: true

module Site
  class ContentfulImageComponent < ApplicationComponent
    SIZE_FRACTIONS = [1, 0.8, 0.6, 0.5, 0.4, 0.2]

    def initialize(src:, height:, width:, alt:, classes: nil, picture_classes: nil, style: nil, lazy: true, decoding: nil, sizes: nil, build_margin_bottom: nil, max_width: 3600, photo: true)
      @src = src || ""

      # Only allow png and jpg as original format and type
      # Note that the accepted type is jpeg, not jpg, even though
      # the file is indeed a jpg
      @format = if File.extname(@src) == ".png"
        "png"
      else
        File.extname(@src) == ".gif" ? "gif" : "jpg"
      end

      @type = if @format == "png"
        "image/png"
      else
        @format == "gif" ? "image/gif" : "image/jpeg"
      end
      # Should we optimize this image as if it's a photo? avif
      # typically compress photos better than webp, but illustrations
      # worse. If it's not a photo, we can skip avif
      @photo = @format != "png" && @format != "gif" && photo

      @sizes = sizes
      @picture_classes = picture_classes
      @classes = classes
      @alt = alt
      @style = style
      @loading = "lazy" if lazy == true
      @decoding = decoding
      @decoding = "async" if lazy == true && decoding.nil?
      @build_margin_bottom = build_margin_bottom

      @max_width = max_width
      @width = [width.to_i, max_width].min
      @height = height.to_i * @width / width
    end

    private

    def src_for_format(format, width: @width)
      "#{@src}?w=#{width}&fm=#{format}"
    end

    def srcset_for_format(format)
      srcset = SIZE_FRACTIONS.map do |fraction|
        fraction_width = (@width.to_f * fraction).to_i

        "#{src_for_format(format, width: fraction_width)} #{fraction_width}w"
      end

      srcset.join(",")
    end
  end
end
