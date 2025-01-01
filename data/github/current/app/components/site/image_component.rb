# typed: true
# frozen_string_literal: true

module Site
  class ImageComponent < ApplicationComponent
    VERSION = "1.0.0"
    SIZE_FRACTIONS = [1, 0.8, 0.6, 0.5, 0.4, 0.2]
    # PNG compress less well than lossy jpg/webp through Fastly, and requires bigger steps to produce gains
    # PNGs are also served as lossless webp, enforced by passing format=webpll
    # https://developer.fastly.com/reference/io/format
    PNG_SIZE_FRACTIONS = [1, 0.5, 0.4, 0.25]

    # width and height should be set to the image's natural/intrinsic size, NOT the size it's rendered as
    def initialize(src:, height:, width:, sizes:, alt: "", classes: "height-auto", picture_classes: nil, style: nil, lazy: true, decoding: nil, build_margin_bottom: nil, max_width: 3600, optimize: true, **options)
      @src = src || ""
      # If optmized is turned off, only the original image will be served
      @optimize = optimize

      # The accepted *type* is image/jpeg, not jpg, even though the file is indeed a jpg
      # https://developer.mozilla.org/en-US/docs/Web/Media/Formats/Image_types
      @format = File.extname(@src).delete(".")
      @type = @format == "jpg" ? "image/jpeg" : "image/#{@format}"

      # 'sizes' is used for hinting to a browser when which image size that should be used
      # follows the standard "sizes" attribute, see
      # https://developer.mozilla.org/en-US/docs/Web/HTML/Element/img#attr-sizes
      @sizes = sizes

      # Default to  loading="lazy" to lazy load images when they are needed
      # (handled by the browser). This is not an optimization but a
      # *prioritization*, and should be turned off if the image is
      # displayed above the fold (e.g. in a hero)
      # https://developer.mozilla.org/en-US/docs/Web/HTML/Element/img#attr-loading
      @loading = "lazy" if lazy == true

      # Default to decoding="async", similarly a depriotization of the asset's decoding
      # https://developer.mozilla.org/en-US/docs/Web/API/HTMLImageElement/decoding
      @decoding = decoding
      @decoding = "async" if lazy == true && decoding.nil?

      # If animated in, control *where* in the viewport it should animate in (defaults to 30% visible)
      @build_margin_bottom = build_margin_bottom

      @picture_classes = picture_classes
      @classes = classes
      @alt = alt
      @style = style
      @options = options
      @max_width = max_width
      @width = [width.to_i, max_width].min
      @height = height.to_i * @width / width
    end

    private

    def src_for_format(format, width: @width)
      return @src if @optimize == false

      src = "#{@src}"
      if format != @format
        src += "?width=#{width}&format=#{format}"
      elsif width != @width
        src += "?width=#{width}"
      end

      src
    end

    def srcset_for_format(format)
      fractions = format == "png" ? PNG_SIZE_FRACTIONS : SIZE_FRACTIONS
      srcset = fractions.map do |fraction|
        fraction_width = (@width.to_f * fraction).to_i

        "#{src_for_format(format, width: fraction_width)} #{fraction_width}w"
      end

      srcset.join(",")
    end
  end
end
